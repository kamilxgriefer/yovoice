// Local benchmark of the Dart-side preamble of MessageService.sendVoiceMessage:
//   readBytes -> sha256 -> payloadStore.write (temp file + fsync + rename)
// Run: dart run tool/perfprobe/voice_send_preamble_bench.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final rng = Random(7);
  // Representative AAC/M4A voice notes. YO Voice caps a voice DM at 60 s.
  const cases = <String, int>{
    '10 s @ 64 kbps (80 KB)': 80 * 1024,
    '30 s @ 64 kbps (240 KB)': 240 * 1024,
    '60 s @ 64 kbps (480 KB)': 480 * 1024,
    '60 s @ 128 kbps (960 KB)': 960 * 1024,
    '60 s @ 256 kbps (1.9 MB)': 1920 * 1024,
  };
  final dir = await Directory.systemTemp.createTemp('yv_voice_bench');
  final source = File('${dir.path}/recording.m4a');
  stdout.writeln('case,readBytesMs,sha256Ms,payloadWriteMs,totalMs');
  for (final entry in cases.entries) {
    final bytes = Uint8List.fromList(
      List<int>.generate(entry.value, (_) => rng.nextInt(256)),
    );
    await source.writeAsBytes(bytes, flush: true);
    // warm the page cache the way a just-finished recording would be
    await source.readAsBytes();

    var read = 0.0, hash = 0.0, write = 0.0;
    const runs = 5;
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      final buffer = await source.readAsBytes();
      read += sw.elapsedMicroseconds / 1000;
      sw.reset();
      sha256.convert(buffer).toString();
      hash += sw.elapsedMicroseconds / 1000;
      sw.reset();
      // What DirectAttachmentPayloadStore.write does on io:
      final dest = File('${dir.path}/entry$i.payload');
      final tmp = File('${dest.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
      await tmp.writeAsBytes(buffer, flush: true);
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      write += sw.elapsedMicroseconds / 1000;
      sw.stop();
      await dest.delete();
    }
    final r = read / runs, h = hash / runs, w = write / runs;
    stdout.writeln(
      '"${entry.key}",${r.toStringAsFixed(1)},${h.toStringAsFixed(1)},'
      '${w.toStringAsFixed(1)},${(r + h + w).toStringAsFixed(1)}',
    );
  }
  await dir.delete(recursive: true);
}
