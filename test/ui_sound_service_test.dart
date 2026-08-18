import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';

void main() {
  test('every cue has a distinct valid WAV asset', () {
    final paths = UiSound.values.map((sound) => sound.assetPath).toSet();
    expect(paths, hasLength(UiSound.values.length));

    for (final sound in UiSound.values) {
      final file = File('assets/${sound.assetPath}');
      expect(file.existsSync(), isTrue, reason: sound.name);
      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
      expect(bytes.length, lessThan(64 * 1024));
    }
  });

  test('disabled preference allocates no player and plays nothing', () async {
    var created = 0;
    final service = UiSoundService(
      enabled: () => false,
      playerFactory: (_) {
        created++;
        return _RecordingPlayer();
      },
    );

    await service.play(UiSound.roomCreated);

    expect(created, 0);
  });

  test('meaningful event families use separate lazy channels', () async {
    final players = <UiSoundChannel, _RecordingPlayer>{};
    var now = DateTime.utc(2026, 8, 18, 10);
    final service = UiSoundService(
      enabled: () => true,
      clock: () => now,
      playerFactory: (channel) =>
          players.putIfAbsent(channel, _RecordingPlayer.new),
    );

    await service.play(UiSound.roomJoined);
    now = now.add(const Duration(seconds: 1));
    await service.play(UiSound.microphoneMuted);
    now = now.add(const Duration(seconds: 1));
    await service.play(UiSound.notification);

    expect(players.keys, UiSoundChannel.values);
    expect(players[UiSoundChannel.room]!.paths, ['audio/ui/room_joined.wav']);
    expect(players[UiSoundChannel.controls]!.paths, [
      'audio/ui/microphone_muted.wav',
    ]);
    expect(players[UiSoundChannel.notification]!.paths, [
      'audio/ui/notification.wav',
    ]);
  });

  test('rapid duplicate room events are coalesced', () async {
    final player = _RecordingPlayer();
    var now = DateTime.utc(2026, 8, 18, 10);
    final service = UiSoundService(
      enabled: () => true,
      clock: () => now,
      playerFactory: (_) => player,
    );

    await service.play(UiSound.participantJoined);
    now = now.add(const Duration(milliseconds: 100));
    await service.play(UiSound.participantJoined);
    now = now.add(const Duration(milliseconds: 500));
    await service.play(UiSound.participantJoined);

    expect(player.paths, hasLength(2));
  });

  test('audio failure never escapes into the product action', () async {
    final service = UiSoundService(
      enabled: () => true,
      playerFactory: (_) => _ThrowingPlayer(),
    );

    await expectLater(service.play(UiSound.notification), completes);
  });
}

class _RecordingPlayer implements UiSoundPlayer {
  final List<String> paths = [];

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    paths.add(assetPath);
    expect(volume, inInclusiveRange(0, 1));
  }

  @override
  Future<void> dispose() async {}
}

class _ThrowingPlayer implements UiSoundPlayer {
  @override
  Future<void> play(String assetPath, {required double volume}) {
    throw StateError('audio unavailable');
  }

  @override
  Future<void> dispose() async {}
}
