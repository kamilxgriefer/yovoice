import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

/// io (and the VM): `XFile.openRead` is already a file seek.
ReelByteRangeReader? reelPlatformRangeReader(XFile file, int length) => null;

/// io (and the VM): the caller's `openRead` header read is already exact.
Future<Uint8List?> readReelPlatformHead(XFile file, int limit) async => null;
