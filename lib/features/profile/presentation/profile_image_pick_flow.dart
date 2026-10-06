import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';

/// Picks a profile image of [kind] from the gallery and runs it through the
/// crop editor: the one pick → validate → compose pipeline of Edit profile and
/// of "Edytuj stronę" (a Page's photo and cover ARE the account's).
///
/// Returns the processed JPEG the editor produced (what gets stored IS the
/// crop the user composed, not the original plus display-time alignment), or
/// null when the user dismissed the picker or backed out of the editor.
/// Nothing is uploaded here: the caller keeps the result as a pending change
/// and commits it on Save.
///
/// Throws what the picker throws ([ProfileImageException] with a readable
/// message for a file that is too large or not a supported format).
///
/// [useRootNavigator] opens the editor over the whole window when the caller
/// lives in a nested navigator (the desktop shell's content slot).
Future<PickedProfileImage?> pickAndCropProfileImage(
  BuildContext context, {
  required ProfileService service,
  required ProfileImageKind kind,
  bool useRootNavigator = false,
}) async {
  final picked = await service.pickProfileImage(kind);
  // Null means the user dismissed the picker: not an error.
  if (picked == null || !context.mounted) return null;

  final decoded = await ImageCrop.decode(picked.bytes);
  if (!context.mounted) {
    decoded.dispose();
    return null;
  }
  final route = MaterialPageRoute<Uint8List>(
    builder: (_) => ImageCropScreen(image: decoded, kind: kind),
  );
  Uint8List? cropped;
  try {
    cropped = await Navigator.of(
      context,
      rootNavigator: useRootNavigator,
    ).push<Uint8List>(route);
    // Navigator.push completes when pop begins. Web still paints the reverse
    // transition, so retain the native image until its overlay is fully
    // removed. The caller remains the owner even if push/reset fails.
    await route.completed;
  } finally {
    decoded.dispose();
  }
  // Null means the user backed out of the editor: not an error.
  if (cropped == null) return null;
  return PickedProfileImage(
    kind: kind,
    bytes: cropped,
    format: ProfileImageFormat.jpeg,
  );
}
