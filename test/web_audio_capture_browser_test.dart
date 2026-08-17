@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture_web.dart';

void main() {
  test('a one-second Safari-style MP4 stays a native browser Blob', () async {
    // The exact duration is carried separately by the recorder; Storage only
    // needs the resulting encoded payload to meet its 1 KiB lower bound. A
    // data URL lets Chrome's browser runner create the same native Blob type
    // returned by MediaRecorder without a microphone permission prompt.
    final bytes = Uint8List(4096);
    final recordingUrl = 'data:audio/mp4;base64,${base64Encode(bytes)}';

    final audio = await WebAudioCapture().materialize(recordingUrl);

    expect(audio, isA<BlobRecordedAudio>());
    expect(audio.byteLength, bytes.lengthInBytes);
    expect(audio.contentType, 'audio/mp4');
    final blobAudio = audio as BlobRecordedAudio;
    expect(blobAudio.blob.type, 'audio/mp4');
    expect(blobAudio.blob.size, bytes.lengthInBytes);
  });
}
