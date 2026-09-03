import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<({Source source, Future<void> Function() dispose})>
prepareDirectVoiceSource(Uint8List bytes, String messageId) async {
  final needsFile =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  if (!needsFile) {
    return (
      source: BytesSource(bytes, mimeType: 'audio/mp4'),
      dispose: _noCleanup,
    );
  }

  final directory = await getTemporaryDirectory();
  final safeId = messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final file = File('${directory.path}/yovoice_dm_${safeId}_$stamp.m4a');
  await file.writeAsBytes(bytes, flush: true);
  return (
    source: DeviceFileSource(file.path, mimeType: 'audio/mp4'),
    dispose: () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The OS owns this temporary directory. A failed best-effort cleanup
        // must never turn a successfully played private message into an error.
      }
    },
  );
}

Future<void> _noCleanup() async {}
