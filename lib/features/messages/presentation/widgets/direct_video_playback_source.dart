import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'direct_video_playback_source_stub.dart'
    if (dart.library.io) 'direct_video_playback_source_io.dart'
    if (dart.library.js_interop) 'direct_video_playback_source_web.dart';

typedef DirectVideoSourcePreparer =
    Future<PreparedDirectVideoSource> Function(
      Uint8List bytes,
      String messageId,
      String mediaReference,
    );

/// A platform-playable private video plus any temporary resources it owns.
abstract class PreparedDirectVideoSource {
  VideoPlayerController createController();

  Future<void> dispose();
}

Future<PreparedDirectVideoSource> prepareDirectVideoSource(
  Uint8List bytes,
  String messageId,
  String mediaReference,
) => createPreparedDirectVideoSource(bytes, messageId, mediaReference);
