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
    ui.Codec? codec;
    try {
      // ImageDescriptor.encoded works on the native engine but currently
      // rejects otherwise valid JPEG/PNG/WebP bytes on Flutter Web. Read only
      // the encoded header with package:image so the hostile-dimension guard
      // remains pre-decode, then use the cross-platform codec entry point.
      final format = ProfileImageRules.detectFormat(bytes);
      final info = switch (format) {
        ProfileImageFormat.jpeg => img.JpegDecoder().startDecode(bytes),
        ProfileImageFormat.png => img.PngDecoder().startDecode(bytes),
        ProfileImageFormat.webp => img.WebPDecoder().startDecode(bytes),
        null => null,
      };
      if (info == null) {
        throw const ProfileImageException(
          "We couldn't process this image. Try another one.",
        );
      }

      final width = info.width;
      final height = info.height;
      if (width <= 0 ||
          height <= 0 ||
          width > maxEncodedEdge ||
          height > maxEncodedEdge ||
          width * height > maxEncodedPixels) {
        throw const ProfileImageException(
          'This image is too large to process safely. Choose another one.',
        );
      }

      // JPEG SOF dimensions are stored before EXIF orientation. Parse only
      // the APP1 metadata so orientations 5–8 swap the axes before selecting
      // the one-axis target. This stays header-only: Flutter Web's
      // instantiateImageCodecWithSize first decodes a full frame to discover
      // its size, defeating the pre-allocation memory bound on large photos.
      final orientation = format == ProfileImageFormat.jpeg
          ? img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1
          : 1;
      final swapsAxes = orientation >= 5 && orientation <= 8;
      final orientedWidth = swapsAxes ? height : width;
      final orientedHeight = swapsAxes ? width : height;
      final targetWidth =
          orientedWidth >= orientedHeight && orientedWidth > maxDecodedEdge
          ? maxDecodedEdge
          : null;
      final targetHeight =
          orientedHeight > orientedWidth && orientedHeight > maxDecodedEdge
          ? maxDecodedEdge
          : null;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
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
