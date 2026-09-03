import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createReelLocalVideoController(String sourcePath) =>
    VideoPlayerController.file(File(sourcePath));
