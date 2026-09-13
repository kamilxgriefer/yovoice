import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';

import 'voice_moment_test_doubles.dart';

/// The ONE additive seam the recorder grew for slice 5.
///
/// The whole of a deliberate recording flow — support probe, permission
/// request, the 1–60 s bound, the 140-character caption, pre-send listening,
/// cancel, retry with a frozen contract — is identical for a Voice Moment
/// reply and a Reel voice comment. These tests hold two things: that a host
/// supplying its own publisher gets exactly that flow, and that the Voice
/// Moment path is BYTE-FOR-BYTE the one it always had.
void main() {
  const medium = Size(768, 1024);

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );

  ({
    FakeRecorderBackend backend,
    FakeAudioCapture capture,
    FakeStopwatch clock,
    StubMomentService service,
    FakePreviewAudioPlayer preview,
    Widget screen,
  })
  build({
    String? replyToMomentId,
    VoiceMomentReplyPublisher? publishReply,
    FakeRecordedAudio? recorded,
  }) {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()
      ..result = recorded ?? FakeRecordedAudio();
    final service = StubMomentService();
    final clock = FakeStopwatch();
    final preview = FakePreviewAudioPlayer();
    return (
      backend: backend,
      capture: capture,
      clock: clock,
      service: service,
      preview: preview,
      screen: RecordVoiceMomentScreen(
        replyToMomentId: replyToMomentId,
        replyToAuthorName: 'Creator One',
        publishReply: publishReply,
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

  Future<void> publish(WidgetTester tester) async {
    final button = find.byIcon(Icons.publish_rounded);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('the injected publisher', () {
    testWidgets('never opens a microphone on mount', (tester) async {
      useSurface(tester, medium);
      var published = 0;
      final harness = build(
        publishReply:
            ({
              required RecordedAudio audio,
              required int durationSeconds,
              required String caption,
            }) async => published++,
      );

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      // A capability probe is not a microphone request.
      expect(harness.capture.probeCalls, 1);
      expect(harness.capture.microphoneCalls, 0);
      expect(harness.backend.startCalls, 0);
      expect(published, 0);
      // The record control is present and waiting for a deliberate press.
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('publishes through the seam, not through MomentService', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      final handed = <({int seconds, String caption})>[];
      final harness = build(
        recorded: recorded,
        publishReply:
            ({
              required RecordedAudio audio,
              required int durationSeconds,
              required String caption,
            }) async {
              expect(identical(audio, recorded), isTrue);
              handed.add((seconds: durationSeconds, caption: caption));
            },
      );

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 9);
      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'On the bridge',
      );
      await tester.pump();
      await publish(tester);

      expect(handed, hasLength(1));
      expect(handed.single.seconds, 9);
      expect(handed.single.caption, 'On the bridge');
      // The Voice Moment pipeline is never touched by a Reel comment.
      expect(harness.service.publishCalls, 0);
    });

    testWidgets('is reply mode: no availability selector', (tester) async {
      useSurface(tester, medium);
      final harness = build(
        publishReply:
            ({
              required RecordedAudio audio,
              required int durationSeconds,
              required String caption,
            }) async {},
      );

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      // The parent owns the lifetime; a reply never picks one of its own.
      expect(find.text('Reply to Creator One'), findsOneWidget);
      expect(
        find.text('Record a voice reply up to 60 seconds long.'),
        findsOneWidget,
      );
      expect(find.text('Until deleted'), findsNothing);
    });

    testWidgets('a refusal keeps the recording and shows the host\'s copy', (
      tester,
    ) async {
      useSurface(tester, medium);
      final recorded = FakeRecordedAudio();
      var attempts = 0;
      final harness = build(
        recorded: recorded,
        publishReply:
            ({
              required RecordedAudio audio,
              required int durationSeconds,
              required String caption,
            }) async {
              attempts++;
              if (attempts == 1) {
                throw const VoiceMomentPresentationNotice(
                  VoiceRecordingProblem.uploadFailed,
                  'You are commenting too quickly. Wait a moment and try '
                  'again.',
                  action: 'Your recording is still here — try again.',
                );
              }
            },
      );

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 5);
      await publish(tester);

      // The host's own words, verbatim — never Voice Moment wording.
      expect(
        find.textContaining('You are commenting too quickly.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your Voice Moment could not be published.'),
        findsNothing,
      );
      expect(recorded.discarded, isFalse);

      // And the retry goes through the same seam with the same recording.
      await publish(tester);
      expect(attempts, 2);
    });
  });

  group('the Voice Moment path is unchanged', () {
    testWidgets('a root Moment still publishes through MomentService', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock, seconds: 4);
      await publish(tester);

      expect(harness.service.publishCalls, 1);
      expect(harness.service.publishedReplyToMomentId, isNull);
    });

    testWidgets('a Moment reply still carries its parent id', (tester) async {
      useSurface(tester, medium);
      final harness = build(replyToMomentId: 'moment_1');

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      // Reply mode is reached by the parent id alone, with no publisher.
      expect(find.text('Reply to Creator One'), findsOneWidget);

      await recordFor(tester, harness.clock, seconds: 4);
      await publish(tester);

      expect(harness.service.publishCalls, 1);
      expect(harness.service.publishedReplyToMomentId, 'moment_1');
    });

    testWidgets('a root Moment still chooses its own availability', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      expect(find.text('Share your voice'), findsOneWidget);
      expect(find.text('Reply to Creator One'), findsNothing);
    });
  });
}
