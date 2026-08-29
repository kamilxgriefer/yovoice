import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';

/// Final room-cover payload selected by the host.
///
/// These are the final JPEG bytes: they power the immediate local preview and
/// are uploaded through RoomImageService's fixed JPEG cover contract.
class PickedRoomCover {
  const PickedRoomCover({required this.bytes});

  final Uint8List bytes;
}

typedef RoomCoverEditorCallback =
    Future<PickedRoomCover?> Function(
      BuildContext context,
      RoomImageService imageService,
    );

/// Shared picker → validation → manual crop flow for room creation and room
/// settings. Nothing uploads until the user confirms the fixed 21:9 frame.
class RoomCoverEditor {
  RoomCoverEditor._();

  static const maxSourceBytes = 8 * 1024 * 1024;

  static Future<PickedRoomCover?> pickAndCrop(
    BuildContext context,
    RoomImageService imageService,
  ) async {
    final picked = await imageService.pickRoomCoverSource();
    if (picked == null) return null;

    final sourceLength = await picked.length();
    if (sourceLength <= 0) {
      throw StateError("We couldn't process this image. Try another one.");
    }
    if (sourceLength > maxSourceBytes) {
      throw StateError('Choose a room cover smaller than 8 MB.');
    }
    final sourceBytes = await picked.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw StateError("We couldn't process this image. Try another one.");
    }
    if (sourceBytes.lengthInBytes > maxSourceBytes) {
      throw StateError('Choose a room cover smaller than 8 MB.');
    }
    if (ProfileImageRules.detectFormat(sourceBytes) == null) {
      throw StateError(
        'That file type is not supported. Use a JPG, PNG or WebP image.',
      );
    }

    try {
      final decoded = await ImageCrop.decode(sourceBytes);
      if (!context.mounted) {
        decoded.dispose();
        return null;
      }
      final route = MaterialPageRoute<Uint8List>(
        builder: (_) => ImageCropScreen.roomCover(image: decoded),
      );
      try {
        final cropped = await Navigator.of(context).push<Uint8List>(route);
        // Keep the decoded frame alive through the reverse transition. This
        // boundary also owns cleanup if an auth-epoch reset removes the route.
        await route.completed;
        if (cropped == null) return null;
        return PickedRoomCover(bytes: cropped);
      } finally {
        decoded.dispose();
      }
    } on ProfileImageException catch (error) {
      throw StateError(error.message);
    }
  }
}
