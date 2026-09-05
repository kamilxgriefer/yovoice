import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/features/moments/data/services/audio_capture/web_microphone_errors.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

import 'voice_moment_test_doubles.dart';

/// Regression suite for the WCAG 2.1 AA audit of the recording screen.
///
/// Two of these were actively misleading in production: a failed publish
/// announced a success-sounding status instead of the error, and a dead
/// microphone was indistinguishable from a quiet room.
void main() {
  const medium = Size(768, 1024);

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) =>
      MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child);

  /// Every announcement pushed through `flutter/accessibility` this test.
  List<Map<Object?, Object?>> captureAnnouncements(WidgetTester tester) {
    final captured = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (Object? message) async {
        if (message is Map && message['type'] == 'announce') {
          captured.add(message['data'] as Map<Object?, Object?>);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return captured;
  }

  bool isAssertive(Map<Object?, Object?> announcement) =>
      announcement['assertiveness'] == Assertiveness.assertive.index;

  String messageOf(Map<Object?, Object?> announcement) =>
      announcement['message'] as String;

  /// Walks the live semantics tree, not the widget tree: Flutter web writes
  /// every polite live region into one shared DOM element, so what matters
  /// is how many nodes carry the flag at once.
  List<SemanticsNode> liveRegions(WidgetTester tester) {
    final found = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      if (node.getSemanticsData().flagsCollection.isLiveRegion) {
        found.add(node);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    // The semantics owner hangs off a per-view child of the root pipeline
    // owner, so walk the owner tree rather than the deprecated global.
    SemanticsNode? root;
    void visitOwner(PipelineOwner owner) {
      root ??= owner.semanticsOwner?.rootSemanticsNode;
      owner.visitChildren(visitOwner);
    }

    visitOwner(tester.binding.rootPipelineOwner);
    if (root != null) visit(root!);
    return found;
  }

  ({
    FakeRecorderBackend backend,
    FakeAudioCapture capture,
    FakeStopwatch clock,
    FakePreviewAudioPlayer previewPlayer,
    StubMomentService service,
    Widget screen,
  })
  build({FakeRecordedAudio? recorded, FakePreviewAudioPlayer? previewPlayer}) {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()
      ..result = recorded ?? FakeRecordedAudio();
    final service = StubMomentService();
    final clock = FakeStopwatch();
    final player = previewPlayer ?? FakePreviewAudioPlayer();
    return (
      backend: backend,
      capture: capture,
      clock: clock,
      previewPlayer: player,
      service: service,
      screen: RecordVoiceMomentScreen(
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: service,
        previewPlayerFactory: () => player,
      ),
    );
  }

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

  // ------------------------------------------------------------------- B1

  group('B1 exactly one live region per phase', () {
    testWidgets('loading, idle, recording, reviewing and publishing', (
      tester,
    ) async {
      useSurface(tester, medium);
      final handle = tester.ensureSemantics();
      final harness = build();
      final gate = Completer<void>();

      await tester.pumpWidget(host(harness.screen));
      expect(liveRegions(tester), hasLength(1), reason: 'checkingSupport');

      await tester.pumpAndSettle();
      expect(liveRegions(tester), hasLength(1), reason: 'idle');

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      expect(liveRegions(tester), hasLength(1), reason: 'recording');

      harness.clock.value = const Duration(seconds: 3);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump();
      expect(liveRegions(tester), hasLength(1), reason: 'reviewing');

      harness.service.gate = gate;
      await tester.tap(find.text('Publish'));
      await tester.pump();
      expect(liveRegions(tester), hasLength(1), reason: 'publishing');

      gate.complete();
      await tester.pumpAndSettle();
      handle.dispose();
    });

    testWidgets('the unavailable phase announces itself exactly once', (
      tester,
    ) async {
      useSurface(tester, medium);
      final handle = tester.ensureSemantics();
      final backend = FakeRecorderBackend();
      final capture = FakeAudioCapture()
        ..support = const CaptureSupport.unsupported(
          reason: 'This browser cannot record MP4/AAC audio.',
          action: 'Open YO Voice in Chrome, Edge or Safari to record.',
        );

      await tester.pumpWidget(
        host(
          RecordVoiceMomentScreen(
            recorder: VoiceMomentRecorder(backend: backend, capture: capture),
            momentService: StubMomentService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(liveRegions(tester), hasLength(1));
      handle.dispose();
    });

    testWidgets(
      'a failed publish still has one live region, and the error is spoken '
      'on the assertive channel',
      (tester) async {
        useSurface(tester, medium);
        final handle = tester.ensureSemantics();
        final announcements = captureAnnouncements(tester);
        final harness = build();
        harness.service.failure = StateError(
          'Your Voice Moment could not be uploaded.',
        );

        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        await recordFor(tester, harness.clock);
        await tester.tap(find.text('Publish'));
        await tester.pumpAndSettle();

        // The notice card must not add a second live region: two polite
        // updates in one frame overwrite each other in Flutter web's single
        // shared announcement element, and the status line won — so a
        // screen reader spoke "Add a caption, then publish" after a failure.
        expect(liveRegions(tester), hasLength(1));

        final assertive = announcements.where(isAssertive).toList();
        expect(assertive, isNotEmpty);
        expect(
          assertive.map(messageOf).join(' | '),
          contains('Your Voice Moment could not be published.'),
        );
        expect(
          assertive.map(messageOf).join(' | '),
          isNot(contains('could not be uploaded')),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'a preview failure keeps one live region and is spoken assertively',
      (tester) async {
        useSurface(tester, medium);
        final handle = tester.ensureSemantics();
        final announcements = captureAnnouncements(tester);
        final player = FakePreviewAudioPlayer()
          ..playError = StateError('decoder details stay private');
        final harness = build(previewPlayer: player);

        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        await recordFor(tester, harness.clock);
        await tester.tap(find.byKey(const ValueKey('voice-preview-toggle')));
        await tester.pumpAndSettle();

        expect(liveRegions(tester), hasLength(1));
        expect(
          announcements.where(isAssertive).map(messageOf).join(' | '),
          contains('Preview could not be played'),
        );
        expect(find.textContaining('decoder details'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets(
      'invalid availability is announced and focuses the duration field',
      (tester) async {
        useSurface(tester, medium);
        final handle = tester.ensureSemantics();
        final announcements = captureAnnouncements(tester);
        final harness = build();

        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        await recordFor(tester, harness.clock);
        await tester.enterText(
          find.byKey(const ValueKey('availability-amount')),
          '1',
        );
        await tester.tap(find.text('Publish'));
        await tester.pumpAndSettle();

        expect(liveRegions(tester), hasLength(1));
        expect(
          announcements.where(isAssertive).map(messageOf).join(' | '),
          contains('Choose between 24 and 720 hours'),
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('availability-amount')),
              )
              .focusNode!
              .hasFocus,
          isTrue,
        );
        handle.dispose();
      },
    );

    testWidgets('the surviving live region is the status line', (tester) async {
      useSurface(tester, medium);
      final handle = tester.ensureSemantics();
      final harness = build();

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final regions = liveRegions(tester);
      expect(regions, hasLength(1));
      expect(regions.single.label, contains('Tap the microphone to start'));
      handle.dispose();
    });
  });

  // ------------------------------------------------------------------- B2

  group('B2 the level meter is not a purely visual signal', () {
    Finder meterNode() => find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.startsWith('Microphone level') ?? false),
    );

    String meterValue(WidgetTester tester) =>
        tester.widget<Semantics>(meterNode()).properties.value!;

    testWidgets('a coarse level is exposed as the node value', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      expect(meterValue(tester), 'Silent');

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      // -10 dBFS normalizes well above the "quiet" threshold.
      harness.clock.value = const Duration(seconds: 1);
      harness.backend.amplitudes.add(Amplitude(current: -10, max: -10));
      await tester.pump();
      expect(meterValue(tester), 'Good level');

      harness.clock.value = const Duration(seconds: 2);
      harness.backend.amplitudes.add(Amplitude(current: -40, max: -10));
      await tester.pump();
      expect(meterValue(tester), 'Quiet');
    });

    testWidgets('the value is throttled to at most once a second', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      harness.clock.value = const Duration(seconds: 1);
      harness.backend.amplitudes.add(Amplitude(current: -10, max: -10));
      await tester.pump();
      expect(meterValue(tester), 'Good level');

      // Four more samples inside the same second: the stream runs at ~8 Hz
      // and republishing the value each time would flood the queue.
      for (var i = 0; i < 4; i++) {
        harness.clock.value = Duration(milliseconds: 1000 + (i * 100));
        harness.backend.amplitudes.add(Amplitude(current: -160, max: -10));
        await tester.pump();
        expect(meterValue(tester), 'Good level');
      }

      harness.clock.value = const Duration(milliseconds: 2100);
      harness.backend.amplitudes.add(Amplitude(current: -160, max: -10));
      await tester.pump();
      expect(meterValue(tester), 'Silent');
    });

    testWidgets('sustained silence is announced once, assertively', (
      tester,
    ) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      // Silence for two seconds is not yet worth interrupting for.
      for (final ms in <int>[0, 500, 1000, 1500, 2000]) {
        harness.clock.value = Duration(milliseconds: ms);
        harness.backend.amplitudes.add(Amplitude(current: -160, max: -160));
        await tester.pump();
      }
      expect(announcements.where(isAssertive), isEmpty);

      // Past three seconds it is: otherwise a muted or dead microphone is
      // only discovered after publishing a minute of nothing.
      for (final ms in <int>[3100, 3600, 4200, 5000]) {
        harness.clock.value = Duration(milliseconds: ms);
        harness.backend.amplitudes.add(Amplitude(current: -160, max: -160));
        await tester.pump();
      }

      final silence = announcements
          .where(isAssertive)
          .where((a) => messageOf(a).contains('No sound is reaching'))
          .toList();
      expect(silence, hasLength(1), reason: 'exactly one warning, not a storm');
    });

    testWidgets('sound before the threshold cancels the warning', (
      tester,
    ) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      for (final (ms, db) in <(int, double)>[
        (0, -160),
        (1000, -160),
        (2000, -12),
        (3200, -160),
        (4000, -160),
      ]) {
        harness.clock.value = Duration(milliseconds: ms);
        harness.backend.amplitudes.add(Amplitude(current: db, max: db));
        await tester.pump();
      }

      expect(
        announcements
            .where((a) => messageOf(a).contains('No sound is reaching'))
            .toList(),
        isEmpty,
      );
    });

    testWidgets('a broken amplitude stream says so instead of reading silent', (
      tester,
    ) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      harness.backend.amplitudes.addError(StateError('analyser detached'));
      await tester.pump();

      expect(meterValue(tester), 'Input level unavailable');
      expect(
        announcements.map(messageOf).join(' | '),
        contains('level is unavailable'),
      );
      // Losing the meter must not stop the recording.
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------- B3

  group('B3 the record button has a visible focus indicator', () {
    testWidgets('it is an AccessibleTapRegion with its own Material', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final region = find.ancestor(
        of: find.byIcon(Icons.mic_rounded),
        matching: find.byType(AccessibleTapRegion),
      );
      expect(region, findsOneWidget);

      // The screen paints an opaque gradient and card over the Scaffold's
      // root Material, so ink features need a Material of their own.
      expect(
        find.descendant(
          of: region,
          matching: find.byWidgetPredicate(
            (w) => w is Material && w.type == MaterialType.transparency,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('focusing it actually paints a ring', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final region = find.ancestor(
        of: find.byIcon(Icons.mic_rounded),
        matching: find.byType(AccessibleTapRegion),
      );
      final ring = find.descendant(
        of: region,
        matching: find.byWidgetPredicate(
          (w) => w is AnimatedContainer && w.decoration is BoxDecoration,
        ),
      );

      Color? ringColour() {
        for (final widget in tester.widgetList<AnimatedContainer>(ring)) {
          final decoration = widget.decoration! as BoxDecoration;
          final border = decoration.border;
          if (border is Border) return border.top.color;
        }
        return null;
      }

      expect(ringColour(), Colors.transparent);

      Focus.of(tester.element(find.byIcon(Icons.mic_rounded))).requestFocus();
      await tester.pumpAndSettle();

      expect(
        ringColour(),
        isNot(Colors.transparent),
        reason: 'tabbing onto the record button must change something',
      );
    });
  });

  // ------------------------------------------------------------------- B4

  group('B4 focus survives publishing', () {
    Finder publishButton() => find.byType(FilledButton);

    testWidgets('the primary action stays focusable while busy', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      final gate = Completer<void>();
      harness.service.gate = gate;

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      await tester.tap(find.text('Publish'));
      await tester.pump();

      expect(find.text('Publishing…'), findsOneWidget);
      // A null callback would drop focus to the route scope.
      expect(tester.widget<FilledButton>(publishButton()).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(publishButton()).enabled, isTrue);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('activation is still refused while busy', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      final gate = Completer<void>();
      harness.service.gate = gate;

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      await tester.tap(find.text('Publish'));
      await tester.pump();
      await tester.tap(find.text('Publishing…'));
      await tester.pump();

      expect(harness.service.publishCalls, 1, reason: 'no double submission');

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('focus lands on the retry after a failure', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      harness.service.failure = StateError('The upload failed.');

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(publishButton());
      expect(button.focusNode, isNotNull);
      expect(
        button.focusNode!.hasFocus,
        isTrue,
        reason:
            'the retry must not be reachable only by traversing from the '
            'top with no indication anything moved',
      );
    });

    testWidgets('H4: the retry is scrolled into view after a failure', (
      tester,
    ) async {
      // 360x640 is short enough that the notice pushes the actions out of
      // the viewport, where they are also flagged hidden to AT.
      useSurface(tester, const Size(360, 640));
      final harness = build();
      harness.service.failure = StateError(
        'Publishing failed because the upload was interrupted partway '
        'through and could not be resumed automatically.',
      );

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      await tester.ensureVisible(find.text('Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      final retry = tester.getRect(find.text('Try again'));
      expect(retry.top, greaterThanOrEqualTo(0));
      expect(retry.bottom, lessThanOrEqualTo(640));
    });
  });

  // ------------------------------------------------------------------- B5

  group('B5 microphone failures are not all blamed on the user', () {
    test('DOMException names map to distinct outcomes', () {
      expect(
        microphoneAccessForError(
          'NotAllowedError',
          permissionStateAfter: 'denied',
        ).outcome,
        MicrophoneOutcome.blocked,
      );
      // A dismissed prompt leaves the permission at `prompt`, and unlike a
      // standing denial it can simply be asked again.
      expect(
        microphoneAccessForError(
          'NotAllowedError',
          permissionStateAfter: 'prompt',
        ).outcome,
        MicrophoneOutcome.dismissed,
      );
      expect(
        microphoneAccessForError('NotFoundError').outcome,
        MicrophoneOutcome.notFound,
      );
      expect(
        microphoneAccessForError('NotReadableError').outcome,
        MicrophoneOutcome.unavailable,
      );
      expect(
        microphoneAccessForError('AbortError').outcome,
        MicrophoneOutcome.failed,
      );
      // Firefox does not implement the microphone permission descriptor.
      expect(
        microphoneAccessForError('NotAllowedError').outcome,
        MicrophoneOutcome.blocked,
      );
    });

    test('a hardware problem is never described as a permission problem', () {
      for (final name in <String>['NotFoundError', 'NotReadableError']) {
        final access = microphoneAccessForError(name);
        expect(access.message, isNot(contains('blocked')));
        expect(access.action, isNot(contains('site settings')));
      }
    });

    test('the blocked action is performable without an address bar', () {
      final blocked = blockedMicrophoneAccess();
      // An installed PWA has no address bar, and once a denial is recorded
      // the page cannot re-prompt, so "try again" would not be actionable.
      expect(blocked.action, isNot(contains('address bar')));
      expect(blocked.action, contains('site settings'));
      expect(blocked.action, contains('reload'));
    });

    test('every outcome maps to its own problem', () {
      expect(
        problemForMicrophoneOutcome(MicrophoneOutcome.blocked),
        VoiceRecordingProblem.microphoneBlocked,
      );
      expect(
        problemForMicrophoneOutcome(MicrophoneOutcome.dismissed),
        VoiceRecordingProblem.microphonePromptDismissed,
      );
      expect(
        problemForMicrophoneOutcome(MicrophoneOutcome.notFound),
        VoiceRecordingProblem.microphoneNotFound,
      );
      expect(
        problemForMicrophoneOutcome(MicrophoneOutcome.unavailable),
        VoiceRecordingProblem.microphoneUnavailable,
      );
    });

    testWidgets('the screen shows the specific refusal, not "blocked"', (
      tester,
    ) async {
      for (final (access, expected, forbidden)
          in <(MicrophoneAccess, String, String)>[
            (
              microphoneAccessForError('NotFoundError'),
              'No microphone was found',
              'blocked',
            ),
            (
              microphoneAccessForError('NotReadableError'),
              'another app is probably using it',
              'blocked',
            ),
            (
              microphoneAccessForError(
                'NotAllowedError',
                permissionStateAfter: 'prompt',
              ),
              'request was dismissed',
              'site settings',
            ),
          ]) {
        useSurface(tester, medium);
        final backend = FakeRecorderBackend();
        final capture = FakeAudioCapture()
          ..result = FakeRecordedAudio()
          ..microphone = access;

        await tester.pumpWidget(
          host(
            RecordVoiceMomentScreen(
              // A distinct key per case: without it Flutter reuses the
              // existing State, which holds the previous recorder.
              key: ValueKey<String>(expected),
              recorder: VoiceMomentRecorder(backend: backend, capture: capture),
              momentService: StubMomentService(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pumpAndSettle();

        expect(find.textContaining(expected), findsOneWidget);
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('a refusal is spoken assertively', (tester) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      harness.capture.microphone = microphoneAccessForError('NotFoundError');

      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(
        announcements.where(isAssertive).map(messageOf).join(' | '),
        contains('No microphone was found'),
      );
    });
  });

  // ------------------------------------------------------- highs and clock

  group('H2 the caption field keeps its name', () {
    testWidgets('it is labelled, and the label survives typing', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      final decoration = tester
          .widget<TextField>(find.byKey(const ValueKey('voice-moment-caption')))
          .decoration!;
      expect(decoration.labelText, 'Caption');

      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'Morning thoughts',
      );
      await tester.pumpAndSettle();

      // The hint is gone once there is text; the label is what remains.
      final after = tester
          .widget<TextField>(find.byKey(const ValueKey('voice-moment-caption')))
          .decoration!;
      expect(after.labelText, 'Caption');
      expect(after.semanticCounterText, '16 of 140 characters');
    });

    testWidgets('reaching the limit is announced rather than silent', (
      tester,
    ) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'x' * 140,
      );
      await tester.pumpAndSettle();

      expect(
        announcements.map(messageOf).join(' | '),
        contains('Caption limit reached'),
      );
    });
  });

  group('H3 review has one re-record action and an explicit preview', () {
    testWidgets('the capture button becomes a labelled preview control', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await recordFor(tester, harness.clock);

      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('voice-preview-toggle')))
            .label,
        contains('Play recording preview'),
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('voice-preview-toggle')))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(find.text('Record again'), findsOneWidget);
    });
  });

  group('the elapsed clock', () {
    testWidgets('carries a value but is never a live region', (tester) async {
      useSurface(tester, medium);
      final handle = tester.ensureSemantics();
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      harness.clock.value = const Duration(seconds: 7);
      await tester.pump(const Duration(milliseconds: 200));

      final clock = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Recording length',
        ),
      );
      expect(clock.properties.value, '7 of 60 seconds');
      // At 200 ms updates a live region would flood the queue.
      expect(clock.properties.liveRegion, isNot(true));
      expect(liveRegions(tester), hasLength(1));
      handle.dispose();
    });

    testWidgets('warns once as the limit approaches', (tester) async {
      useSurface(tester, medium);
      final announcements = captureAnnouncements(tester);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();

      harness.clock.value = const Duration(seconds: 49);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        announcements.map(messageOf).where((m) => m.contains('seconds left')),
        isEmpty,
      );

      harness.clock.value = const Duration(seconds: 51);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        announcements
            .map(messageOf)
            .where((m) => m.contains('seconds left'))
            .toList(),
        hasLength(1),
      );
    });
  });
}
