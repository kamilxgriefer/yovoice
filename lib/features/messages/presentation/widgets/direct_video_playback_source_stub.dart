import 'dart:typed_data';

import 'direct_video_playback_source.dart';

Future<PreparedDirectVideoSource> createPreparedDirectVideoSource(
  Uint8List bytes,
  String messageId,
  String mediaReference,
) => throw UnsupportedError('Private video playback is unavailable.');
