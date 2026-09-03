import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'direct_video_playback_source.dart';

final class _DataDirectVideoSource implements PreparedDirectVideoSource {
  _DataDirectVideoSource(this.uri);

  final Uri uri;

  @override
  VideoPlayerController createController() =>
      VideoPlayerController.networkUrl(uri);

  @override
  Future<void> dispose() async {}
}

Future<PreparedDirectVideoSource> createPreparedDirectVideoSource(
  Uint8List bytes,
  String messageId,
  String mediaReference,
) async {
  final path = Uri.tryParse(mediaReference)?.path.toLowerCase() ?? '';
  final mime = path.endsWith('.mov')
      ? 'video/quicktime'
      : path.endsWith('.webm')
      ? 'video/webm'
      : 'video/mp4';
  return _DataDirectVideoSource(Uri.dataFromBytes(bytes, mimeType: mime));
}
