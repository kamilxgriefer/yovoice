import 'dart:async';

import 'package:audioplayers/audioplayers.dart' show BytesSource;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';

import 'voice_moment_test_doubles.dart';

/// Every state the recording screen can actually be in, at every
/// breakpoint. The screen previously had two — "recording" and "not" — and
/// funnelled every failure, including a platform gap that made recording
/// impossible for all web users, into one snackbar reading "Could not start
/// recording".
void main() {
  const narrow = Size(360, 780);
  const medium = Size(768, 1024);
  const wide = Size(1440, 900);
  const sizes = <(String, Size)>[
    ('narrow', narrow),
    ('medium', medium),
    ('wide', wide),
  ];

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {double textScale = 1}) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      ),
      home: child,
    );
  }

  ({
    FakeRecorderBackend backend,
    FakeAudioCapture capture,
    FakeStopwatch clock,
    StubMomentService service,
    FakePreviewAudioPlayer previewPlayer,
    Widget screen,
  })
  build({
    CaptureSupport? support,
    FakeRecordedAudio? recorded,
    String? replyToMomentId,
    FakePreviewAudioPlayer? previewPlayer,
  }) {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()
      ..result = recorded ?? FakeRecordedAudio();
    if (support != null) capture.support = support;
    final service = StubMomentService();
    final clock = FakeStopwatch();
    final preview = previewPlayer ?? FakePreviewAudioPlayer();
    return (
      backend: backend,
      capture: capture,
      clock: clock,
      service: service,
      previewPlayer: preview,
      screen: RecordVoiceMomentScreen(
        replyToMomentId: replyToMomentId,
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: service,
        previewPlayerFactory: () => preview,
      ),
    );
  }

  /// Runs a capture of [seconds] and stops it.
  Future<void> recordFor(
    WidgetTester tester,
    FakeStopwatch clock, {
    int seconds = 3,
  }) async {
    final microphone = find.byIcon(Icons.mic_rounded);
    await tester.ensureVisible(microphone);
    await tester.pump();
    await tester.tap(microphone);
    await tester.pump();
    await tester.pump();
    clock.value = Duration(seconds: seconds);
    await tester.pump(const Duration(milliseconds: 200));
    final stop = find.byIcon(Icons.stop_rounded);
    await tester.ensureVisible(stop);
    await tester.pump();
    await tester.tap(stop);
    await tester.pump();
    await tester.pump();
  }

  group('loading and platform-gap states', () {
    testWidgets('opens in a loading state while support is being resolved', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));

      // First frame, before the async support probe completes.
      expect(
        find.text('Checking whether this device can record…'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    for (final (label, size) in sizes) {
      testWidgets(
        '$label: an unsupported browser explains itself specifically',
        (tester) async {
          useSurface(tester, size);
          final harness = build(
            support: const CaptureSupport.unsupported(
              reason:
                  'This browser cannot record MP4/AAC audio, which is the only '
                  'format YO Voice can publish a Voice Moment in.',
              action: 'Open YO Voice in Chrome, Edge or Safari to record.',
            ),
          );
          await tester.pumpWidget(host(harness.screen));
          await tester.pumpAndSettle();

          expect(find.text('Recording is not available here'), findsOneWidget);
          expect(find.textContaining('MP4/AAC'), findsOneWidget);
          expect(find.textContaining('Chrome, Edge or Safari'), findsOneWidget);

          // The two things this project forbids for an unavailable capability.
          expect(find.textContaining('Coming soon'), findsNothing);
          expect(
            find.textContaining('Could not start recording'),
            findsNothing,
          );

          // And no dead record button that would fail when tapped.
          expect(find.byIcon(Icons.mic_rounded), findsNothing);
          expect(find.text('Go back'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('local preview can play, pause and seek without uploading', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final harness = build(recorded: recorded);
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);

      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pump();
      expect(harness.previewPlayer.playCalls, 1);
      expect(harness.previewPlayer.lastSource, isA<BytesSource>());
      expect(harness.service.publishCalls, 0);
      expect(recorded.uploadCalls, 0);

      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pump();
      expect(harness.previewPlayer.pauseCalls, 1);

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('voice-preview-seek')),
      );
      slider.onChanged!(2500);
      slider.onChangeEnd!(2500);
      await tester.pump();
      expect(
        harness.previewPlayer.lastSeekPosition,
        const Duration(milliseconds: 2500),
      );
      expect(harness.service.publishCalls, 0);
    });

    testWidgets('a preview failure is honest and keeps publish available', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.previewPlayer.playError = StateError('decoder unavailable');
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);

      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Preview could not be played'),
        findsOneWidget,
      );
      expect(find.text('Publish'), findsOneWidget);
      expect(find.textContaining('decoder unavailable'), findsNothing);
    });

    testWidgets('publish stops and disposes preview before discarding audio', (
      tester,
    ) async {
      useSurface(tester, medium);
      final lifecycle = <String>[];
      final recorded = FakeRecordedAudio(lifecycle: lifecycle);
      final preview = FakePreviewAudioPlayer(lifecycle: lifecycle);
      final harness = build(recorded: recorded, previewPlayer: preview);
      harness.service.lifecycle = lifecycle;
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);
      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pump();

      await tester.tap(find.text('Publish'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        lifecycle,
        containsAllInOrder([
          'player.stop',
          'player.dispose',
          'service.publish',
          'audio.discard',
        ]),
      );
      expect(
        lifecycle.indexOf('player.dispose'),
        lessThan(lifecycle.indexOf('service.publish')),
      );
    });

    testWidgets('record again releases preview before the old take', (
      tester,
    ) async {
      useSurface(tester, medium);
      final lifecycle = <String>[];
      final recorded = FakeRecordedAudio(lifecycle: lifecycle);
      final preview = FakePreviewAudioPlayer(lifecycle: lifecycle);
      final harness = build(recorded: recorded, previewPlayer: preview);
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);
      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pump();

      await tester.tap(find.text('Record again'));
      await tester.pumpAndSettle();

      expect(lifecycle.take(3), [
        'player.stop',
        'player.dispose',
        'audio.discard',
      ]);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    testWidgets('back releases preview before discarding the take', (
      tester,
    ) async {
      useSurface(tester, medium);
      final lifecycle = <String>[];
      final recorded = FakeRecordedAudio(lifecycle: lifecycle);
      final preview = FakePreviewAudioPlayer(lifecycle: lifecycle);
      final harness = build(recorded: recorded, previewPlayer: preview);
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);
      await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
      await tester.pump();

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Back',
        ),
      );
      await tester.pumpAndSettle();

      expect(lifecycle.take(3), [
        'player.stop',
        'player.dispose',
        'audio.discard',
      ]);
    });

    testWidgets('an insecure-origin refusal names the real cause', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build(
        support: const CaptureSupport.unsupported(
          reason:
              'Browsers only allow microphone access over a secure (https) '
              'connection, and this page was not loaded over one.',
          action: 'Open YO Voice over https and try again.',
        ),
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      // Distinct from a denied permission: telling this user to allow the
      // microphone would send them after a control that cannot help.
      expect(find.textContaining('secure (https)'), findsOneWidget);
      expect(find.textContaining('Allow the microphone'), findsNothing);
    });
  });

  group('permission and capture failures stay distinguishable', () {
    testWidgets('a blocked microphone is reported as blocked, with an action', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.backend.permission = false;
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('is blocked in this browser'), findsOneWidget);
      expect(find.textContaining("browser's site settings"), findsOneWidget);
      // Recoverable: the screen stays usable rather than becoming terminal.
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text('Recording is not available here'), findsNothing);
    });

    testWidgets(
      'the original web bug surfaces as a platform gap, not a retryable error',
      (tester) async {
        useSurface(tester, medium);
        final harness = build();
        harness.capture.targetError = MissingPluginException(
          'No implementation found for method getTemporaryDirectory '
          'on channel plugins.flutter.io/path_provider',
        );
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Recording is not available here'), findsOneWidget);
        // Never the raw exception, and never the old generic snackbar.
        expect(find.textContaining('MissingPluginException'), findsNothing);
        expect(find.textContaining('path_provider'), findsNothing);
        expect(find.textContaining('Could not start recording'), findsNothing);
      },
    );

    testWidgets('a recorder that will not start keeps the screen retryable', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.backend.startError = StateError('device busy');
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be started'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.textContaining('device busy'), findsNothing);
    });

    testWidgets('a sub-second recording is refused with a specific reason', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      harness.clock.value = const Duration(milliseconds: 300);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('too short to publish'), findsOneWidget);
      expect(find.text('Publish'), findsNothing);
    });
  });

  group('recording, reviewing and publishing', () {
    testWidgets('recording shows a stop control and a live status', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      expect(find.text('Tap the microphone to start.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.text('Recording — tap to stop.'), findsOneWidget);

      // The level meter is fed by the recorder's real amplitude stream.
      harness.backend.amplitudes.add(Amplitude(current: -10, max: -10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('the timer reflects elapsed capture time', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      expect(find.text('0:00 / 1:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      harness.clock.value = const Duration(seconds: 4);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('0:04 / 1:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();
    });

    for (final (label, size) in sizes) {
      testWidgets('$label: reviewing offers a caption and both actions', (
        tester,
      ) async {
        useSurface(tester, size);
        final harness = build();
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();

        await recordFor(tester, harness.clock, seconds: 3);

        expect(
          find.byKey(const ValueKey('voice-moment-caption')),
          findsOneWidget,
        );
        expect(find.text('Publish'), findsOneWidget);
        expect(find.text('Record again'), findsOneWidget);
        expect(
          find.text('Preview your take, then publish — or record again.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('publishing sends the caption and measured duration', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final harness = build(recorded: recorded);
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 5);

      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'Morning thoughts',
      );
      await tester.pump();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(harness.service.publishCalls, 1);
      expect(harness.service.publishedCaption, 'Morning thoughts');
      expect(harness.service.publishedDuration, 5);
      expect(harness.service.publishedAudio, same(recorded));
      // Published recordings are released, not left holding a temporary
      // file or an object URL.
      expect(recorded.discarded, true);
    });

    testWidgets('the uploading state disables the caption, actions and back', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      final gate = Completer<void>();
      harness.service.gate = gate;
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Publish'));
      await tester.pump();

      expect(find.text('Publishing…'), findsOneWidget);
      expect(find.text('Publishing your Voice Moment…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('voice-moment-caption')),
            )
            .enabled,
        false,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Back',
              ),
            )
            .onPressed,
        isNull,
        reason: 'leaving mid-upload would orphan a reserved draft',
      );

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failed publish keeps the recording and offers a retry', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final harness = build(recorded: recorded);
      harness.service.failure = StateError(
        'You must be signed in to publish a Voice Moment.',
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      // Intentional user-facing copy is surfaced; the recording survives.
      expect(
        find.textContaining('You must be signed in to publish'),
        findsOneWidget,
      );
      expect(find.textContaining('recording is still here'), findsOneWidget);
      expect(recorded.discarded, false);
      expect(find.text('Try again'), findsOneWidget);

      // And retrying really retries.
      harness.service.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(harness.service.publishCalls, 2);
    });

    testWidgets(
      'record again after failed publish abandons retry identity before Blob discard',
      (tester) async {
        useSurface(tester, medium);
        final lifecycle = <String>[];
        final recorded = FakeRecordedAudio(lifecycle: lifecycle);
        final harness = build(recorded: recorded);
        harness.service
          ..lifecycle = lifecycle
          ..failure = StateError('publish failed');
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();

        await recordFor(tester, harness.clock, seconds: 3);
        await tester.tap(find.text('Publish'));
        await tester.pumpAndSettle();
        expect(recorded.discarded, false);

        await tester.ensureVisible(find.text('Record again'));
        await tester.tap(find.text('Record again'));
        await tester.pumpAndSettle();

        expect(harness.service.abandonCalls, 1);
        expect(harness.service.abandonedAudio, same(recorded));
        expect(recorded.discarded, true);
        expect(
          lifecycle.indexOf('service.abandon'),
          lessThan(lifecycle.indexOf('audio.discard')),
        );
      },
    );

    testWidgets('Back after failed publish abandons the retained retry', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final harness = build(recorded: recorded);
      harness.service.failure = StateError('publish failed');
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Back',
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.service.abandonCalls, 1);
      expect(harness.service.abandonedAudio, same(recorded));
      expect(recorded.discarded, true);
    });

    testWidgets('a raw upload exception never reaches the user verbatim', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.service.failure = Exception(
        'Dart exception thrown from converted Future. Use the properties '
        "'error' to fetch the boxed error",
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dart exception'), findsNothing);
      expect(
        find.text('Your Voice Moment could not be published.'),
        findsOneWidget,
      );
    });

    testWidgets('the active-Moment limit never surfaces callable detail', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.service.failure = FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'quota bucket users/private-user-id reached internal cap',
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('You have reached the limit of active Moments.'),
        findsOneWidget,
      );
      expect(find.textContaining('private-user-id'), findsNothing);
      expect(find.textContaining('internal cap'), findsNothing);
    });

    testWidgets('record again releases the previous recording', (tester) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final harness = build(recorded: recorded);
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.tap(find.text('Record again'));
      await tester.pumpAndSettle();

      expect(recorded.discarded, true);
      expect(find.text('Publish'), findsNothing);
      expect(find.text('Recording — tap to stop.'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    testWidgets('desktop presents a two-column workspace', (tester) async {
      useSurface(tester, wide);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      // Idle desktop: capture stage on the left, guidance beside it —
      // not a phone column stretched across the window.
      expect(find.text('Before you start'), findsOneWidget);

      final meter = tester.getRect(find.text('0:00 / 1:00'));
      final guidance = tester.getRect(find.text('Before you start'));
      expect(
        guidance.left,
        greaterThan(meter.right),
        reason: 'the side panel must sit beside the stage, not under it',
      );
    });

    testWidgets('phone and tablet keep a single column', (tester) async {
      for (final size in <Size>[narrow, medium]) {
        useSurface(tester, size);
        final harness = build();
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        expect(
          find.text('Before you start'),
          findsNothing,
          reason: 'the desktop side panel must not appear at ${size.width}px',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('narrow widths stack the two actions instead of clipping', (
      tester,
    ) async {
      useSurface(tester, narrow);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 3);

      final publish = tester.getRect(find.text('Publish'));
      final again = tester.getRect(find.text('Record again'));
      expect(
        again.top,
        greaterThan(publish.bottom),
        reason: 'side-by-side labels clip once the text grows',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide widths place the two actions side by side', (
      tester,
    ) async {
      useSurface(tester, wide);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 3);

      final publish = tester.getRect(find.text('Publish'));
      final again = tester.getRect(find.text('Record again'));
      expect(publish.left, greaterThan(again.left));
      expect((publish.center.dy - again.center.dy).abs(), lessThan(2));
    });
  });

  group('long content and text scaling', () {
    testWidgets('a long reply author name does not overflow at any width', (
      tester,
    ) async {
      for (final (label, size) in sizes) {
        useSurface(tester, size);
        final backend = FakeRecorderBackend();
        final capture = FakeAudioCapture()..result = FakeRecordedAudio();
        await tester.pumpWidget(
          host(
            RecordVoiceMomentScreen(
              replyToMomentId: 'parent',
              replyToAuthorName:
                  'Aleksandra-Katarzyna Wiśniewska-Brzęczyszczykiewicz '
                  'the Third of the Northern Voice Collective',
              recorder: VoiceMomentRecorder(backend: backend, capture: capture),
              momentService: StubMomentService(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'long reply title overflowed at $label',
        );
      }
    });

    testWidgets('a long caption and a long failure message stay laid out', (
      tester,
    ) async {
      useSurface(tester, narrow);
      final harness = build();
      harness.service.failure = StateError(
        'Publishing failed because the Voice Moment draft reservation could '
        'not be matched to an uploaded object, which usually means the '
        'upload was interrupted partway through.',
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await recordFor(tester, harness.clock, seconds: 3);
      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'A caption that runs all the way to the one hundred and forty '
        'character limit that this field allows, wrapping across lines.',
      );
      await tester.pump();
      // At 360px the actions sit below the fold once the caption grows.
      await tester.ensureVisible(find.text('Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      // A long caption and a three-line failure notice coexist on a 360px
      // surface without overflowing.
      expect(find.textContaining('interrupted partway'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the unavailable panel survives large text at 320px', (
      tester,
    ) async {
      useSurface(tester, const Size(320, 640));
      final harness = build(
        support: const CaptureSupport.unsupported(
          reason:
              'This browser cannot record MP4/AAC audio, which is the only '
              'format YO Voice can publish a Voice Moment in.',
          action: 'Open YO Voice in Chrome, Edge or Safari to record.',
        ),
      );
      await tester.pumpWidget(host(harness.screen, textScale: 1.6));
      await tester.pumpAndSettle();

      expect(find.text('Recording is not available here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('review controls survive a 320px viewport at 2x text', (
      tester,
    ) async {
      const surface = Size(320, 640);
      useSurface(tester, surface);
      final harness = build();
      await tester.pumpWidget(host(harness.screen, textScale: 2));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);

      final controls = <Finder>[
        find.byKey(const ValueKey('voice-preview-toggle')),
        find.byKey(const ValueKey('availability-timed')),
        find.byKey(const ValueKey('availability-permanent')),
        find.byKey(const ValueKey('availability-amount')),
        find.byKey(const ValueKey('availability-unit')),
        find.text('Publish'),
        find.text('Record again'),
      ];
      for (final control in controls) {
        expect(control, findsOneWidget);
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        final rect = tester.getRect(control);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(surface.height));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('visual regressions from the rendered-UI audit', () {
    testWidgets('V1: a full-length take never renders 0:60', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      expect(find.text('0:00 / 1:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      harness.clock.value = const Duration(seconds: 5);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('0:05 / 1:00'), findsOneWidget);

      // The 60 s auto-stop lands the user straight on the widest value the
      // clock can show, which used to be the impossible 0:60.
      harness.clock.value = const Duration(seconds: 60);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('0:60 / 1:00'), findsNothing);
      expect(find.text('1:00'), findsWidgets);
      expect(find.text('Publish'), findsOneWidget, reason: 'auto-stopped');
    });

    testWidgets('V2: sustained silence is visibly distinct from idle', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      const hint = 'No sound detected — check your microphone.';
      expect(find.text(hint), findsNothing, reason: 'idle shows no hint');

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      for (final ms in <int>[0, 1000, 2000]) {
        harness.clock.value = Duration(milliseconds: ms);
        harness.backend.amplitudes.add(Amplitude(current: -160, max: -160));
        await tester.pump();
      }
      expect(find.text(hint), findsNothing, reason: 'not yet three seconds');

      harness.clock.value = const Duration(milliseconds: 3200);
      harness.backend.amplitudes.add(Amplitude(current: -160, max: -160));
      await tester.pump();
      expect(find.text(hint), findsOneWidget);

      // Sound returning clears it — the hint tracks the signal, it does not
      // latch.
      harness.clock.value = const Duration(milliseconds: 3600);
      harness.backend.amplitudes.add(Amplitude(current: -12, max: -12));
      await tester.pump();
      expect(find.text(hint), findsNothing);
    });

    testWidgets('V3: the unavailable panel is not stretched at 1440', (
      tester,
    ) async {
      useSurface(tester, wide);
      final harness = build(
        support: const CaptureSupport.unsupported(
          reason: 'This browser cannot record MP4/AAC audio.',
          action: 'Open YO Voice in Chrome, Edge or Safari to record.',
        ),
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final button = tester.getRect(
        find.ancestor(
          of: find.text('Go back'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(
        button.width,
        lessThan(560),
        reason: 'a ~920px button is a phone stack inflated to desktop width',
      );
    });

    testWidgets(
      'V4: the desktop column reports the take, not pre-flight tips',
      (tester) async {
        useSurface(tester, wide);
        final harness = build();
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();

        expect(find.text('Before you start'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Before you start'),
          findsNothing,
          reason: 'advice for a moment that has already passed',
        );
        expect(find.text('Recording'), findsOneWidget);
        expect(find.text('Input level'), findsOneWidget);
        expect(find.text('Remaining'), findsOneWidget);
      },
    );

    testWidgets('V4: the desktop stage shares one alignment axis', (
      tester,
    ) async {
      useSurface(tester, wide);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final title = tester.getRect(find.text('Share your voice'));
      final clock = tester.getRect(find.text('0:00 / 1:00'));
      final button = tester.getRect(find.byIcon(Icons.mic_rounded));

      expect((title.center.dx - clock.center.dx).abs(), lessThan(2));
      expect((title.center.dx - button.center.dx).abs(), lessThan(2));
    });

    testWidgets('V5: the retry stays on screen at 375x812', (tester) async {
      useSurface(tester, const Size(375, 812));
      final harness = build();
      harness.service.failure = StateError(
        'Your Voice Moment could not be uploaded because the connection '
        'dropped partway through the upload and could not be resumed.',
      );
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 3);

      await tester.ensureVisible(find.text('Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      final retry = tester.getRect(find.text('Try again'));
      expect(retry.top, greaterThanOrEqualTo(0));
      expect(retry.bottom, lessThanOrEqualTo(812));
    });

    testWidgets('V6: a stalled microphone prompt can be cancelled', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      harness.capture.microphoneGate = Completer<MicrophoneAccess>();

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.text('Waiting for microphone access…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Tap the microphone to start.'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      // A late answer to the abandoned request must not resurrect it.
      harness.capture.microphoneGate!.complete(
        const MicrophoneAccess.granted(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tap the microphone to start.'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
    });

    testWidgets('V6: a prompt that never answers times out with a reason', (
      tester,
    ) async {
      useSurface(tester, medium);
      final backend = FakeRecorderBackend();
      final capture = FakeAudioCapture()
        ..result = FakeRecordedAudio()
        ..microphoneGate = Completer<MicrophoneAccess>();

      await tester.pumpWidget(
        host(
          RecordVoiceMomentScreen(
            recorder: VoiceMomentRecorder(
              backend: backend,
              capture: capture,
              microphoneTimeout: const Duration(milliseconds: 40),
            ),
            momentService: StubMomentService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('did not answer the microphone request'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('V7: controls meet the 44x44 minimum in docs/UI.md', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final back = tester.getRect(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Back'),
      );
      expect(back.width, greaterThanOrEqualTo(44));
      expect(back.height, greaterThanOrEqualTo(44));

      await recordFor(tester, harness.clock, seconds: 3);

      // The painted box, not merely the padded hit area.
      for (final finder in <Finder>[
        find.byType(FilledButton),
        find.byType(OutlinedButton),
      ]) {
        final box = tester.getRect(finder);
        expect(box.height, greaterThanOrEqualTo(44), reason: '$finder');
      }
    });
  });
}
