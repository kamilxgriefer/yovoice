import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'direct_video_playback_source.dart';

final class _FileDirectVideoSource implements PreparedDirectVideoSource {
  _FileDirectVideoSource(this.file);

  final File file;

  @override
  VideoPlayerController createController() => VideoPlayerController.file(file);

  @override
  Future<void> dispose() async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cache cleanup is best effort; the OS also owns the temp directory.
    }
  }
}

Future<PreparedDirectVideoSource> createPreparedDirectVideoSource(
  Uint8List bytes,
  String messageId,
  String mediaReference,
) async {
  final directory = await getTemporaryDirectory();
  final safeId = messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final extension = _extension(mediaReference);
  final file = File(
    '${directory.path}/yovoice_dm_video_${safeId}_${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  return _FileDirectVideoSource(file);
}

String _extension(String reference) {
  final path = Uri.tryParse(reference)?.path.toLowerCase() ?? '';
  if (path.endsWith('.mov')) return 'mov';
  if (path.endsWith('.webm')) return 'webm';
  return 'mp4';
}
