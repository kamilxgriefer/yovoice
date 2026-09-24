import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/call_tone.dart';
import 'package:yovoice/core/audio/call_tone_service.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('call tones use the versioned looping assets', () {
    expect(CallTone.incoming.assetPath, 'audio/ui/v6/call_incoming_loop.wav');
    expect(CallTone.outgoing.assetPath, 'audio/ui/v6/call_outgoing_loop.wav');
    expect(CallTone.values.map((tone) => tone.volume), everyElement(1.0));
  });

  test(
    'production player configures Android call focus and closes a late start',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final engine = _ControlledEngine(blockPlay: true);
      final player = AudioplayersCallTonePlayer(engine: engine);

      final starting = player.startLoop(
        CallTone.incoming.assetPath,
        volume: CallTone.incoming.volume,
      );
      await engine.playStarted.future;
      final stopping = player.stop();
      await stopping;
      engine.releasePlay.complete();
      await starting;

      expect(
        engine.actions,
        containsAllInOrder(['context', 'loop', 'play', 'release']),
      );
      expect(engine.releaseCalls, 2);
      await player.dispose();
      expect(engine.disposeCalls, 1);
      expect(identical(player.stop(), player.stop()), isTrue);
      expect(identical(player.dispose(), player.dispose()), isTrue);
    },
  );

  test('a hung release cannot prevent engine disposal', () async {
    final engine = _ControlledEngine(blockRelease: true);
    final player = AudioplayersCallTonePlayer(engine: engine);

    final stopping = player.stop();
    await engine.releaseStarted.future;
    final disposing = player.dispose();
    await engine.disposeStarted.future;

    expect(engine.disposeCalls, 1);
    engine.releaseStop.complete();
    await stopping;
    await disposing;
  });

  test('disabled preference does not allocate an audio player', () async {
    var creations = 0;
    final service = CallToneService(
      enabled: () => false,
      playerFactory: () {
        creations++;
        return _ControlledPlayer();
      },
    );

    expect(
      await service.startWithResult(CallTone.incoming),
      CallToneStartResult.disabled,
    );
    expect(creations, 0);
    expect(service.isPlaying, isFalse);
    await service.dispose();
  });

  test('same pending tone shares one player and one platform start', () async {
    final player = _ControlledPlayer(blockStart: true);
    var creations = 0;
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () {
        creations++;
        return player;
      },
    );

    final first = service.startWithResult(CallTone.outgoing);
    await player.startEntered.future;
    final duplicate = service.startWithResult(CallTone.outgoing);

    expect(identical(first, duplicate), isTrue);
    expect(creations, 1);
    expect(player.paths, [CallTone.outgoing.assetPath]);
    player.releaseStart.complete();
    expect(await first, CallToneStartResult.started);
    expect(service.activeTone, CallTone.outgoing);

    await service.dispose();
  });

  test('new tone stops the old player before it starts', () async {
    final incoming = _ControlledPlayer(blockStart: true);
    final outgoing = _ControlledPlayer();
    final players = <_ControlledPlayer>[incoming, outgoing];
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () => players.removeAt(0),
    );

    final oldStart = service.startWithResult(CallTone.incoming);
    await incoming.startEntered.future;
    final newStart = service.startWithResult(CallTone.outgoing);
    expect(incoming.stopCalls, 1);
    expect(outgoing.paths, isEmpty);

    await Future<void>.delayed(Duration.zero);
    expect(outgoing.paths, [CallTone.outgoing.assetPath]);
    expect(await newStart, CallToneStartResult.started);
    incoming.releaseStart.complete();
    expect(await oldStart, CallToneStartResult.superseded);
    expect(service.activeTone, CallTone.outgoing);

    await service.dispose();
  });

  test('stop wins while a platform start is pending', () async {
    final player = _ControlledPlayer(blockStart: true);
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () => player,
    );

    final starting = service.startWithResult(CallTone.incoming);
    await player.startEntered.future;
    await service.stop();

    expect(service.activeTone, isNull);
    expect(service.isPlaying, isFalse);
    expect(player.stopCalls, 1);
    player.releaseStart.complete();
    expect(await starting, CallToneStartResult.superseded);
    expect(service.isPlaying, isFalse);

    await service.dispose();
  });

  test('player failure is isolated and a later tone can retry', () async {
    final failed = _ControlledPlayer(startError: StateError('unavailable'));
    final recovered = _ControlledPlayer();
    final players = <_ControlledPlayer>[failed, recovered];
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () => players.removeAt(0),
    );

    expect(
      await service.startWithResult(CallTone.incoming),
      CallToneStartResult.failed,
    );
    expect(service.isPlaying, isFalse);
    expect(
      await service.startWithResult(CallTone.incoming),
      CallToneStartResult.started,
    );
    expect(service.activeTone, CallTone.incoming);

    await service.dispose();
  });

  test('factory failure stops the previous tone and never escapes', () async {
    final active = _ControlledPlayer();
    var creations = 0;
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () {
        creations++;
        if (creations == 1) return active;
        throw StateError('player allocation failed');
      },
    );
    expect(
      await service.startWithResult(CallTone.incoming),
      CallToneStartResult.started,
    );

    expect(
      await service.startWithResult(CallTone.outgoing),
      CallToneStartResult.failed,
    );
    expect(active.stopCalls, 1);
    expect(service.isPlaying, isFalse);

    await service.dispose();
  });

  test('an unconfirmed stop quarantines replacement playback', () async {
    final stopGate = Completer<void>();
    final active = _ControlledPlayer(stopGate: stopGate);
    final replacement = _ControlledPlayer();
    final players = <_ControlledPlayer>[active, replacement];
    final service = CallToneService(
      enabled: () => true,
      playerFactory: () => players.removeAt(0),
      stopTimeout: const Duration(milliseconds: 10),
      disposeTimeout: const Duration(milliseconds: 10),
    );

    expect(
      await service.startWithResult(CallTone.incoming),
      CallToneStartResult.started,
    );
    expect(
      await service.startWithResult(CallTone.outgoing),
      CallToneStartResult.failed,
    );
    expect(active.stopCalls, 1);
    expect(replacement.paths, isEmpty);
    expect(service.isPlaying, isFalse);

    stopGate.complete();
    await service.dispose();
  });

  test(
    'dispose stops active audio and permanently rejects new starts',
    () async {
      final player = _ControlledPlayer();
      final service = CallToneService(
        enabled: () => true,
        playerFactory: () => player,
      );
      expect(
        await service.startWithResult(CallTone.outgoing),
        CallToneStartResult.started,
      );

      final firstDispose = service.dispose();
      final secondDispose = service.dispose();
      expect(identical(firstDispose, secondDispose), isTrue);
      await firstDispose;

      expect(player.stopCalls, 1);
      expect(player.disposeCalls, 1);
      expect(
        await service.startWithResult(CallTone.incoming),
        CallToneStartResult.superseded,
      );
    },
  );
}

class _ControlledPlayer implements CallTonePlayer {
  _ControlledPlayer({this.blockStart = false, this.startError, this.stopGate});

  final bool blockStart;
  final Object? startError;
  final Completer<void>? stopGate;
  final paths = <String>[];
  final startEntered = Completer<void>();
  final releaseStart = Completer<void>();
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> startLoop(String assetPath, {required double volume}) async {
    paths.add(assetPath);
    expect(volume, inInclusiveRange(0, 1));
    if (!startEntered.isCompleted) startEntered.complete();
    if (blockStart) await releaseStart.future;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _ControlledEngine implements CallTonePlaybackEngine {
  _ControlledEngine({this.blockPlay = false, this.blockRelease = false});

  final bool blockPlay;
  final bool blockRelease;
  final actions = <String>[];
  final playStarted = Completer<void>();
  final releasePlay = Completer<void>();
  final releaseStarted = Completer<void>();
  final releaseStop = Completer<void>();
  final disposeStarted = Completer<void>();
  int releaseCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> configureAndroidCallToneContext() async {
    actions.add('context');
  }

  @override
  Future<void> setLooping() async {
    actions.add('loop');
  }

  @override
  Future<void> playAsset(String assetPath, {required double volume}) async {
    actions.add('play');
    if (!playStarted.isCompleted) playStarted.complete();
    if (blockPlay) await releasePlay.future;
  }

  @override
  Future<void> stopAndRelease() async {
    releaseCalls++;
    actions.add('release');
    if (!releaseStarted.isCompleted) releaseStarted.complete();
    if (blockRelease) await releaseStop.future;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    actions.add('dispose');
    if (!disposeStarted.isCompleted) disposeStarted.complete();
  }
}
