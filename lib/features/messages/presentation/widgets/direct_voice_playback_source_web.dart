import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

Future<({Source source, Future<void> Function() dispose})>
prepareDirectVoiceSource(Uint8List bytes, String messageId) async =>
    (source: BytesSource(bytes, mimeType: 'audio/mp4'), dispose: _noCleanup);

Future<void> _noCleanup() async {}
