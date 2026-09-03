import 'package:video_player/video_player.dart';

import 'reel_local_video_controller_stub.dart'
    if (dart.library.io) 'reel_local_video_controller_io.dart'
    if (dart.library.html) 'reel_local_video_controller_web.dart'
    as platform;

/// Builds the real local video controller for the file returned by the
/// platform picker. The path never leaves the device and is used only while
/// the composer is open.
VideoPlayerController createReelLocalVideoController(String sourcePath) =>
    platform.createReelLocalVideoController(sourcePath);
