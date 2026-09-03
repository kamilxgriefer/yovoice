import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'direct_voice_playback_source_io.dart'
    if (dart.library.js_interop) 'direct_voice_playback_source_web.dart'
    as implementation;

/// A playable DM voice source and the cleanup tied to its lifetime.
///
/// `audioplayers` does not implement [BytesSource] on iOS or macOS. Private
/// attachments still have to be downloaded through the authenticated Storage
/// SDK, so Apple platforms stage those bytes in the OS temporary directory
/// and play a [DeviceFileSource]. Web and the other native platforms keep the
/// cheaper in-memory source.
class PreparedDirectVoiceSource {
  const PreparedDirectVoiceSource({
    required this.source,
    required this.dispose,
  });

  final Source source;
  final Future<void> Function() dispose;
}

typedef DirectVoiceSourcePreparer =
    Future<PreparedDirectVoiceSource> Function(
      Uint8List bytes,
      String messageId,
    );

Future<PreparedDirectVoiceSource> prepareDirectVoiceSource(
  Uint8List bytes,
  String messageId,
) async {
  final prepared = await implementation.prepareDirectVoiceSource(
    bytes,
    messageId,
  );
  return PreparedDirectVoiceSource(
    source: prepared.source,
    dispose: prepared.dispose,
  );
}
