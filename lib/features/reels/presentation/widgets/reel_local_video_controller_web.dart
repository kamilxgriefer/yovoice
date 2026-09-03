import 'package:video_player/video_player.dart';

VideoPlayerController createReelLocalVideoController(String sourcePath) =>
    VideoPlayerController.networkUrl(Uri.parse(sourcePath));
