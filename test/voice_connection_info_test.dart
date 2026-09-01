import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/models/voice_connection_info.dart';

void main() {
  test('accepts only the production secure LiveKit endpoint', () {
    final info = VoiceConnectionInfo.fromMap(<String, dynamic>{
      'serverUrl': 'wss://yovoice-3f7j9fb7.livekit.cloud',
      'participantToken': 'signed-token',
      'permissions': <String, Object?>{'canPublish': false},
    });

    expect(info.serverUrl, 'wss://yovoice-3f7j9fb7.livekit.cloud');
    expect(info.participantToken, 'signed-token');
    expect(info.canPublish, isFalse);
  });

  test('rejects a response without authoritative publish intent', () {
    expect(
      () => VoiceConnectionInfo.fromMap(<String, dynamic>{
        'serverUrl': 'wss://yovoice-3f7j9fb7.livekit.cloud',
        'participantToken': 'signed-token',
      }),
      throwsFormatException,
    );
  });

  test('rejects a malformed publish permission envelope', () {
    expect(
      () => VoiceConnectionInfo.fromMap(<String, dynamic>{
        'serverUrl': 'wss://yovoice-3f7j9fb7.livekit.cloud',
        'participantToken': 'signed-token',
        'permissions': <String, Object?>{'canPublish': 'yes'},
      }),
      throwsFormatException,
    );
  });

  for (final serverUrl in <String>[
    'ws://yovoice-3f7j9fb7.livekit.cloud',
    'wss://attacker.example',
    'wss://attacker@yovoice-3f7j9fb7.livekit.cloud',
    'wss://yovoice-3f7j9fb7.livekit.cloud:444',
    'wss://yovoice-3f7j9fb7.livekit.cloud/unexpected',
    'wss://yovoice-3f7j9fb7.livekit.cloud?redirect=attacker.example',
  ]) {
    test('rejects untrusted voice endpoint $serverUrl', () {
      expect(
        () => VoiceConnectionInfo.fromMap(<String, dynamic>{
          'serverUrl': serverUrl,
          'participantToken': 'signed-token',
          'permissions': <String, Object?>{'canPublish': true},
        }),
        throwsFormatException,
      );
    });
  }
}
