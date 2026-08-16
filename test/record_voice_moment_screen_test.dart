import 'dart:async';

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
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
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
    Widget screen,
  })
  build({
    CaptureSupport? support,
    FakeRecordedAudio? recorded,
    String? replyToMomentId,
  }) {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()..result = recorded ?? FakeRecordedAudio();
    if (support != null) capture.support = support;
    final service = StubMomentService();
    final clock = FakeStopwatch();
    return (
      backend: backend,
      capture: capture,
      clock: clock,
      service: service,
      screen: RecordVoiceMomentScreen(
        replyToMomentId: replyToMomentId,
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: service,
      ),
    );
  }

  /// Runs a capture of [seconds] and stops it.
  Future<void> recordFor(
    WidgetTester tester,
    FakeStopwatch clock, {
    int seconds = 3,
  }) async {
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    await tester.pump();
    clock.value = Duration(seconds: seconds);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.stop_rounded));
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
      testWidgets('$label: an unsupported browser explains itself specifically',
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
        expect(find.textContaining('Could not start recording'), findsNothing);

        // And no dead record button that would fail when tapped.
        expect(find.byIcon(Icons.mic_rounded), findsNothing);
        expect(find.text('Go back'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

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

      expect(
        find.textContaining('blocked microphone access'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Allow the microphone for this site'),
        findsOneWidget,
      );
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

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Publish'), findsOneWidget);
        expect(find.text('Record again'), findsOneWidget);
        expect(
          find.text('Add a caption, then publish — or record again.'),
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

      await tester.enterText(find.byType(TextField), 'Morning thoughts');
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
        tester.widget<TextField>(find.byType(TextField)).enabled,
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
      expect(find.text('Tap the microphone to start.'), findsOneWidget);
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
        find.byType(TextField),
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
  });
}
