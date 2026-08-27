@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture_web.dart';

void main() {
  test('native Blob owns one playback URL and revokes it on discard', () async {
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
    addTearDown(blobAudio.discard);

    final firstSource = blobAudio.playbackSource;
    final secondSource = blobAudio.playbackSource;
    expect(firstSource, isA<UrlSource>());
    expect(secondSource, isA<UrlSource>());
    final playbackUrl = (firstSource as UrlSource).url;
    expect(playbackUrl, startsWith('blob:'));
    expect((secondSource as UrlSource).url, playbackUrl);

    final beforeDiscard = await web.window.fetch(playbackUrl.toJS).toDart;
    expect(beforeDiscard.ok, true);
    final playableBlob = await beforeDiscard.blob().toDart;
    expect(playableBlob.type, 'audio/mp4');
    expect(playableBlob.size, bytes.lengthInBytes);

    await blobAudio.discard();
    await blobAudio.discard();
    expect(() => blobAudio.playbackSource, throwsA(isA<StateError>()));

    Object? revokedFetchError;
    try {
      await web.window.fetch(playbackUrl.toJS).toDart;
    } catch (error) {
      revokedFetchError = error;
    }
    expect(
      revokedFetchError,
      isNotNull,
      reason: 'discard must revoke the browser object URL, not only mark it',
    );
  });
}
