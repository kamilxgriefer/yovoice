import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_draft_preview.dart';

void main() {
  testWidgets(
    'adding and swapping backing audio preserves a playing video timeline',
    (tester) async {
      final video = _FakeVideoController();
      final players = <_FakeAudioPlayer>[];
      final harnessKey = GlobalKey<_PreviewHarnessState>();
      await tester.pumpWidget(
        _PreviewHarness(
          key: harnessKey,
          video: video,
          audioPlayerFactory: () {
            final player = _FakeAudioPlayer();
            players.add(player);
            return player;
          },
        ),
      );
      await tester.pumpAndSettle();

      final preview = harnessKey.currentState!.previewKey.currentState!;
      await preview.toggle();
      await tester.pump();
      video.jumpTo(const Duration(seconds: 4));
      expect(video.value.isPlaying, isTrue);

      harnessKey.currentState!.setBackingAudio(_audioPayload(1));
      await _pumpPreviewWork(tester);

      expect(preview.isPlaying, isTrue);
      expect(video.value.isPlaying, isTrue);
      expect(video.value.position, const Duration(seconds: 4));
      expect(players, hasLength(1));
      expect(players.single.resumeCount, 1);

      video.jumpTo(const Duration(seconds: 7));
      harnessKey.currentState!.setBackingAudio(_audioPayload(2));
      await _pumpPreviewWork(tester);

      expect(preview.isPlaying, isTrue);
      expect(video.value.isPlaying, isTrue);
      expect(video.value.position, const Duration(seconds: 7));
      expect(players, hasLength(2));
      expect(players.last.resumeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'backing-audio picker success pauses in place and resumes after rebuild',
    (tester) async {
      final video = _FakeVideoController();
      final players = <_FakeAudioPlayer>[];
      final harnessKey = GlobalKey<_PreviewHarnessState>();
      await tester.pumpWidget(
        _PreviewHarness(
          key: harnessKey,
          video: video,
          audioPlayerFactory: () {
            final player = _FakeAudioPlayer();
            players.add(player);
            return player;
          },
        ),
      );
      await tester.pumpAndSettle();
      final harness = harnessKey.currentState!;
      final preview = harness.previewKey.currentState!;
      await preview.toggle();
      video.jumpTo(const Duration(seconds: 6));

      // Matches the composer: schedule active=false, capture the public picker
      // token before that rebuild, then let the system-owned picker take over.
      harness.setActive(false);
      final token = await preview.pauseForBackingAudioPicker();
      await tester.pump();
      expect(preview.isPlaying, isFalse);
      expect(video.value.position, const Duration(seconds: 6));

      // The composer applies the selected payload and releases the token before
      // Flutter delivers the active=true/backing-audio didUpdateWidget pass.
      harness.setBackingAudio(_audioPayload(3), active: true);
      preview.finishBackingAudioPicker(token);
      await _pumpPreviewWork(tester);

      expect(preview.isPlaying, isTrue);
      expect(video.value.isPlaying, isTrue);
      expect(video.value.position, const Duration(seconds: 6));
      expect(players, hasLength(1));
      expect(players.single.resumeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in <String>['cancel', 'error']) {
    testWidgets('backing-audio picker $outcome restores the prior playback', (
      tester,
    ) async {
      final video = _FakeVideoController();
      final harnessKey = GlobalKey<_PreviewHarnessState>();
      await tester.pumpWidget(
        _PreviewHarness(
          key: harnessKey,
          video: video,
          audioPlayerFactory: _FakeAudioPlayer.new,
        ),
      );
      await tester.pumpAndSettle();
      final harness = harnessKey.currentState!;
      final preview = harness.previewKey.currentState!;
      await preview.toggle();
      video.jumpTo(const Duration(seconds: 8));

      harness.setActive(false);
      final token = await preview.pauseForBackingAudioPicker();
      await tester.pump();
      expect(video.value.isPlaying, isFalse);

      // Both a null result and a caught picker exception run the composer's
      // same finally block: no payload changes, but the token is released.
      harness.setActive(true);
      preview.finishBackingAudioPicker(token);
      await _pumpPreviewWork(tester);

      expect(preview.isPlaying, isTrue);
      expect(video.value.isPlaying, isTrue);
      expect(video.value.position, const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('manual pause wins over a late backing-audio picker result', (
    tester,
  ) async {
    final video = _FakeVideoController();
    final players = <_FakeAudioPlayer>[];
    final harnessKey = GlobalKey<_PreviewHarnessState>();
    await tester.pumpWidget(
      _PreviewHarness(
        key: harnessKey,
        video: video,
        audioPlayerFactory: () {
          final player = _FakeAudioPlayer();
          players.add(player);
          return player;
        },
      ),
    );
    await tester.pumpAndSettle();
    final harness = harnessKey.currentState!;
    final preview = harness.previewKey.currentState!;
    await preview.toggle();
    video.jumpTo(const Duration(seconds: 9));

    harness.setActive(false);
    final staleToken = await preview.pauseForBackingAudioPicker();
    await tester.pump();
    await preview.pause();
    await tester.pump();

    harness.setBackingAudio(_audioPayload(4), active: true);
    preview.finishBackingAudioPicker(staleToken);
    await _pumpPreviewWork(tester);

    expect(preview.isPlaying, isFalse);
    expect(video.value.isPlaying, isFalse);
    expect(players, isEmpty, reason: 'No late audio player may start');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPreviewWork(WidgetTester tester) async {
  for (var index = 0; index < 200; index += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

class _PreviewHarness extends StatefulWidget {
  const _PreviewHarness({
    required this.video,
    required this.audioPlayerFactory,
    super.key,
  });

  final _FakeVideoController video;
  final AudioPlayer Function() audioPlayerFactory;

  @override
  State<_PreviewHarness> createState() => _PreviewHarnessState();
}

class _PreviewHarnessState extends State<_PreviewHarness> {
  final previewKey = GlobalKey<ReelDraftPreviewState>();
  final media = ReelUploadPayload(
    bytes: Uint8List.fromList(<int>[0, 0, 0, 0]),
    contentType: 'video/mp4',
    durationMs: 20000,
    sourcePath: '/tmp/preview.mp4',
  );
  ReelUploadPayload? backingAudio;
  bool active = true;
  ReelComposition composition = const ReelComposition(
    trimEndMs: 20000,
    originalAudioVolume: 100,
  );

  void setActive(bool value) => setState(() => active = value);

  void setBackingAudio(ReelUploadPayload payload, {bool? active}) {
    setState(() {
      if (active != null) this.active = active;
      backingAudio = payload;
      composition = composition.copyWith(
        backingAudioVolume: 70,
        audioTrimStartMs: 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 700,
          child: ReelDraftPreview(
            key: previewKey,
            media: media,
            backingAudio: backingAudio,
            composition: composition,
            active: active,
            audioPlayerFactory: widget.audioPlayerFactory,
            videoControllerFactory: (_) => widget.video,
          ),
        ),
      ),
    );
  }
}

ReelUploadPayload _audioPayload(int marker) => ReelUploadPayload(
  bytes: Uint8List.fromList(<int>[marker, ...List<int>.filled(511, 0)]),
  contentType: 'audio/mpeg',
  durationMs: 5000,
);

class _FakeVideoController implements VideoPlayerController {
  final ValueNotifier<VideoPlayerValue> _state = ValueNotifier(
    const VideoPlayerValue(duration: Duration(seconds: 20)),
  );
  int playCount = 0;
  int pauseCount = 0;

  @override
  VideoPlayerValue get value => _state.value;

  @override
  set value(VideoPlayerValue value) => _state.value = value;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, size: const Size(1080, 1920));
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> play() async {
    playCount += 1;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position);
  }

  void jumpTo(Duration position) => value = value.copyWith(position: position);

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Future<void> dispose() async => _state.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  int resumeCount = 0;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> setVolume(double value) async {}

  @override
  Future<void> seek(Duration position) async => _positions.add(position);

  @override
  Future<void> resume() async {
    resumeCount += 1;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    _states.add(PlayerState.paused);
  }

  @override
  Future<void> stop() async {
    _states.add(PlayerState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _positions.close();
    await _completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
