import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

/// Pure crop pipeline for the avatar/banner editors, kept UI-free so the
/// geometry and the render can be unit-tested without pumping widgets.
///
/// ARCHITECTURE DECISION (P1 banner/avatar): we upload the FINAL CROPPED
/// IMAGE (option A), not original-plus-crop-metadata. One artifact renders
/// identically on Web and iOS with zero client-side transform math at
/// display time, every existing consumer (UserAvatar, ProfileBanner,
/// conversations, clubs, the fan-out copies) keeps working unchanged, and
/// there is no metadata schema to keep in sync across platforms. The
/// original stays on the user's device; re-cropping means re-picking —
/// the trade-off Instagram/WhatsApp/Discord all make.
class ImageCrop {
  ImageCrop._();

  static const maxEncodedEdge = 16384;
  static const maxEncodedPixels = 32 * 1024 * 1024;
  static const maxDecodedEdge = 3200;

  /// Decodes picked bytes into a [ui.Image] for the editor. Throws the
  /// product's own "couldn't process" error on undecodable data instead
  /// of leaking codec exceptions.
  static Future<ui.Image> decode(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > maxEncodedEdge ||
          height > maxEncodedEdge ||
          width * height > maxEncodedPixels) {
        throw const ProfileImageException(
          'This image is too large to process safely. Choose another one.',
        );
      }

      final scale = width > height
          ? (width > maxDecodedEdge ? maxDecodedEdge / width : 1.0)
          : (height > maxDecodedEdge ? maxDecodedEdge / height : 1.0);
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round(),
        targetHeight: (height * scale).round(),
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } on ProfileImageException {
      rethrow;
    } catch (_) {
      throw const ProfileImageException(
        "We couldn't process this image. Try another one.",
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Maps the editor viewport back onto source-image pixels.
  ///
  /// [matrix] is the InteractiveViewer transform (child = the image laid
  /// out at its intrinsic pixel size). The visible viewport rect, pushed
  /// through the inverse transform, IS the crop rect in image pixels —
  /// clamped to the image bounds to absorb float error at the edges.
  static Rect sourceRectFor({
    required Matrix4 matrix,
    required Size viewport,
    required Size imageSize,
  }) {
    final inverse = Matrix4.inverted(matrix);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(viewport.width, viewport.height),
    );
    final rect = Rect.fromPoints(topLeft, bottomRight);
    return Rect.fromLTRB(
      rect.left.clamp(0.0, imageSize.width),
      rect.top.clamp(0.0, imageSize.height),
      rect.right.clamp(0.0, imageSize.width),
      rect.bottom.clamp(0.0, imageSize.height),
    );
  }

  /// Renders [sourceRect] of [image] into an
  /// [outputWidth]x[outputHeight] JPEG.
  ///
  /// dart:ui draws (GPU-correct on every platform, honours EXIF because
  /// instantiateImageCodec already applied orientation), package:image
  /// encodes (dart:ui itself can only export PNG, which is enormous for
  /// photos). Quality 85 keeps a 1024px avatar around 100-300KB.
  static Future<Uint8List> renderCroppedJpeg({
    required ui.Image image,
    required Rect sourceRect,
    required int outputWidth,
    required int outputHeight,
    int quality = 85,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      sourceRect,
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final rendered = await recorder.endRecording().toImage(
      outputWidth,
      outputHeight,
    );
    try {
      final rgba = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) {
        throw const ProfileImageException(
          "We couldn't process this image. Try another one.",
        );
      }

      final raw = img.Image.fromBytes(
        width: outputWidth,
        height: outputHeight,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      return Uint8List.fromList(img.encodeJpg(raw, quality: quality));
    } finally {
      rendered.dispose();
    }
  }
}
