import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  test(
    'Velvet Prism pack is 48 kHz stereo, bounded and mastered in assets',
    () {
      final paths = UiSound.values.map((sound) => sound.assetPath).toSet();
      expect(paths, hasLength(UiSound.values.length));
      expect(UiSound.values, hasLength(8));
      expect(paths, everyElement(startsWith('audio/ui/v3/')));
      final packagedWavs = Directory('assets/audio/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.wav'))
          .map((file) => file.path.replaceAll('\\', '/'))
          .toSet();
      expect(packagedWavs, paths.map((path) => 'assets/$path').toSet());
      final fingerprints = <String>{};
      const expectedSeconds = <String, double>{
        'room_created.wav': 0.360,
        'room_joined.wav': 0.240,
        'room_left.wav': 0.190,
        'participant_joined.wav': 0.135,
        'participant_left.wav': 0.125,
        'microphone_muted.wav': 0.095,
        'microphone_unmuted.wav': 0.115,
        'notification.wav': 0.330,
      };
      const targetRms = <String, double>{
        'room_created.wav': -23,
        'room_joined.wav': -25,
        'room_left.wav': -26,
        'participant_joined.wav': -30,
        'participant_left.wav': -31,
        'microphone_muted.wav': -27,
        'microphone_unmuted.wav': -27,
        'notification.wav': -20,
      };

      for (final sound in UiSound.values) {
        final file = File('assets/${sound.assetPath}');
        expect(file.existsSync(), isTrue, reason: sound.name);
        final bytes = file.readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
        expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
        expect(data.getUint16(22, Endian.little), 2, reason: sound.name);
        expect(data.getUint32(24, Endian.little), 48000, reason: sound.name);
        expect(data.getUint16(34, Endian.little), 16, reason: sound.name);
        expect(bytes.length, lessThan(96 * 1024), reason: sound.name);

        final frameCount = data.getUint32(40, Endian.little) ~/ 4;
        expect(
          frameCount / 48000,
          closeTo(expectedSeconds[sound.fileName]!, 1 / 48000),
          reason: sound.name,
        );
        var peak = 0;
        var energy = 0.0;
        var sampleCount = 0;
        for (var offset = 44; offset + 1 < bytes.length; offset += 2) {
          final sample = data.getInt16(offset, Endian.little);
          if (sample.abs() > peak) peak = sample.abs();
          energy += sample * sample;
          sampleCount++;
        }
        final rms = math.sqrt(energy / sampleCount) / 32767;
        final rmsDb = 20 * math.log(rms) / math.ln10;
        expect(
          rmsDb,
          closeTo(targetRms[sound.fileName]!, 0.08),
          reason: '${sound.name} loudness',
        );
        expect(peak, lessThan(32767), reason: '${sound.name} must not clip');
        expect(
          bytes.skip(bytes.length - 64 * 4),
          everyElement(0),
          reason: '${sound.name} must end in exact silence',
        );
        fingerprints.add(String.fromCharCodes(bytes));
      }
      expect(fingerprints, hasLength(UiSound.values.length));
      expect(UiSound.values.map((sound) => sound.volume), everyElement(1.0));
    },
  );

  test(
    'Flutter, Android and iOS package the exact same notification master',
    () {
      final master = File(
        'assets/${UiSound.notification.assetPath}',
      ).readAsBytesSync();
      expect(
        File(
          'android/app/src/main/res/raw/yovoice_notification.wav',
        ).readAsBytesSync(),
        master,
      );
      expect(
        File('ios/Runner/yovoice_notification.wav').readAsBytesSync(),
        master,
      );
    },
  );

  test('Android fallback and Functions keep activity and call channels', () {
    const channel = PushNotificationService.androidChannelId;
    expect(channel, 'yovoice_activity_v3');
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:value="$channel"'),
    );
    final pushPayload = File(
      'functions/notifications/push_payload.js',
    ).readAsStringSync();
    expect(pushPayload, contains('"$channel"'));
    expect(pushPayload, contains('"yovoice_calls_v1"'));
    expect(pushPayload, contains('channelId: isCall'));
  });

  test(
    'production player subscribes before start and awaits the full cue tail',
    () async {
      final engine = _ControlledPlaybackEngine();
      final player = AudioplayersUiSoundPlayer(
        engine: engine,
        completionTimeout: const Duration(seconds: 1),
      );
      var returned = false;

      final playback = player
          .play(UiSound.roomCreated.assetPath, volume: 1)
          .then((_) => returned = true);
      await engine.playStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(engine.actions, containsAllInOrder(['listen', 'play']));
      expect(
        engine.actions.indexOf('listen'),
        lessThan(engine.actions.indexOf('play')),
      );
      expect(returned, isFalse, reason: 'play must represent the audible tail');
      expect(engine.stopCalls, 0, reason: 'a live cue must not be hard-cut');

      engine.completeCue();
      await playback;

      expect(returned, isTrue);
      expect(engine.stopCalls, 0);
      await player.dispose();
    },
  );

  test(
    'completion emitted synchronously during start cannot be missed',
    () async {
      final engine = _ControlledPlaybackEngine(completeDuringPlay: true);
      final player = AudioplayersUiSoundPlayer(
        engine: engine,
        completionTimeout: const Duration(seconds: 1),
      );

      await expectLater(
        player.play(UiSound.microphoneMuted.assetPath, volume: 1),
        completes,
      );

      expect(engine.actions, containsAllInOrder(['listen', 'play']));
      expect(
        engine.actions.indexOf('listen'),
        lessThan(engine.actions.indexOf('play')),
      );
      expect(engine.stopCalls, 0);
      await player.dispose();
    },
  );

  test(
    'missing platform completion is bounded and recovered with stop',
    () async {
      final engine = _ControlledPlaybackEngine();
      final player = AudioplayersUiSoundPlayer(
        engine: engine,
        completionTimeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        player.play(UiSound.notification.assetPath, volume: 1),
        throwsA(isA<TimeoutException>()),
      );

      expect(engine.stopCalls, 1);
      await player.dispose();
    },
  );

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
    expect(players[UiSoundChannel.room]!.paths, [
      'audio/ui/v3/room_joined.wav',
    ]);
    expect(players[UiSoundChannel.controls]!.paths, [
      'audio/ui/v3/microphone_muted.wav',
    ]);
    expect(players[UiSoundChannel.notification]!.paths, [
      'audio/ui/v3/notification.wav',
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
    now = now.add(const Duration(milliseconds: 750));
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

  test(
    'one channel serializes async playback and newest queued cue wins',
    () async {
      final player = _BlockingPlayer();
      var now = DateTime.utc(2026, 8, 27, 10);
      final service = UiSoundService(
        enabled: () => true,
        clock: () => now,
        playerFactory: (_) => player,
      );

      final first = service.play(UiSound.roomJoined);
      await player.firstStarted.future;
      now = now.add(const Duration(milliseconds: 200));
      final superseded = service.play(UiSound.participantJoined);
      now = now.add(const Duration(milliseconds: 200));
      final newest = service.play(UiSound.roomLeft);

      expect(player.maxInFlight, 1);
      expect(
        player.paths,
        [UiSound.roomJoined.assetPath],
        reason: 'queued cues must not begin before the active tail completes',
      );
      player.releaseFirst.complete();
      await Future.wait([first, superseded, newest]);

      expect(player.paths, [
        UiSound.roomJoined.assetPath,
        UiSound.roomLeft.assetPath,
      ]);
      expect(player.maxInFlight, 1);
    },
  );

  test('a backward wall-clock correction does not mute future cues', () async {
    final player = _RecordingPlayer();
    var now = DateTime.utc(2026, 8, 27, 10);
    final service = UiSoundService(
      enabled: () => true,
      clock: () => now,
      playerFactory: (_) => player,
    );

    await service.play(UiSound.microphoneMuted);
    now = now.subtract(const Duration(minutes: 1));
    await service.play(UiSound.microphoneMuted);

    expect(player.paths, hasLength(2));
  });

  test(
    'concurrent dispose calls share one completion and dispose once',
    () async {
      final engine = _ControlledPlaybackEngine(
        completeDuringPlay: true,
        blockDispose: true,
      );
      final player = AudioplayersUiSoundPlayer(engine: engine);
      final service = UiSoundService(
        enabled: () => true,
        playerFactory: (_) => player,
      );
      await service.play(UiSound.roomCreated);

      final first = service.dispose();
      final second = service.dispose();
      expect(identical(first, second), isTrue);
      await engine.disposeStarted.future;

      var finished = false;
      second.then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(engine.disposeCalls, 1);

      engine.releaseDispose.complete();
      await Future.wait([first, second]);

      expect(finished, isTrue);
      expect(engine.disposeCalls, 1);
      expect(identical(player.dispose(), player.dispose()), isTrue);
    },
  );
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

class _BlockingPlayer implements UiSoundPlayer {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  final paths = <String>[];
  var _inFlight = 0;
  var maxInFlight = 0;

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    paths.add(assetPath);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    if (paths.length == 1) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    _inFlight--;
  }

  @override
  Future<void> dispose() async {}
}

class _ControlledPlaybackEngine implements UiSoundPlaybackEngine {
  _ControlledPlaybackEngine({
    this.completeDuringPlay = false,
    this.blockDispose = false,
  }) {
    _completions = StreamController<void>.broadcast(
      sync: true,
      onListen: () => actions.add('listen'),
      onCancel: () => actions.add('cancel'),
    );
  }

  final bool completeDuringPlay;
  final bool blockDispose;
  final actions = <String>[];
  final playStarted = Completer<void>();
  final disposeStarted = Completer<void>();
  final releaseDispose = Completer<void>();
  late final StreamController<void> _completions;
  var stopCalls = 0;
  var disposeCalls = 0;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> configureAndroidUiSoundContext() async {
    actions.add('context');
  }

  @override
  Future<void> playAsset(String assetPath, {required double volume}) async {
    actions.add('play');
    if (!playStarted.isCompleted) playStarted.complete();
    if (completeDuringPlay) _completions.add(null);
  }

  void completeCue() => _completions.add(null);

  @override
  Future<void> stop() async {
    stopCalls++;
    actions.add('stop');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    if (blockDispose) await releaseDispose.future;
    await _completions.close();
  }
}
