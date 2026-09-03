import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

Future<Duration> inspectDirectVideoOnPlatform(XFile video) async {
  final controller = VideoPlayerController.file(File(video.path));
  try {
    await controller.initialize();
    return controller.value.duration;
  } finally {
    await controller.dispose();
  }
}
