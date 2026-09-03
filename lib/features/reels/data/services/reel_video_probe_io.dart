import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

Future<int> probeSelectedReelVideoDuration(XFile file) async {
  final controller = VideoPlayerController.file(File(file.path));
  try {
    await controller.initialize();
    return controller.value.duration.inMilliseconds;
  } finally {
    await controller.dispose();
  }
}
