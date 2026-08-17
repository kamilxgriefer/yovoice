import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture_io.dart';

void main() {
  test('native capture still materializes and discards its M4A file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yovoice-native-audio-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/one-second.m4a');
    await file.writeAsBytes(List<int>.filled(4096, 0), flush: true);

    final audio = await const NativeAudioCapture().materialize(file.path);

    expect(audio, isA<FileRecordedAudio>());
    expect(audio.byteLength, 4096);
    expect(audio.contentType, 'audio/mp4');
    await audio.discard();
    expect(await file.exists(), false);
  });
}
