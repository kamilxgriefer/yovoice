// Operator-chosen availability (the ADR-101 amendment): the recorder's
// "Available for" selector, the additive `availabilityHours` wire field,
// the amended null-means-permanent model reading, and the honest label
// copy on every surface.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/moment_availability.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';

import 'voice_moment_test_doubles.dart';

void main() {
  group('MomentAvailability', () {
    test('accepts every whole hour from 24 through 720, or permanent', () {
      expect(MomentAvailability.hours24.wireValue, 24);
      expect(MomentAvailability.timedHours(25).wireValue, 25);
      expect(MomentAvailability.timedHours(72).wireValue, 72);
      expect(MomentAvailability.timedHours(720).wireValue, 720);
      expect(MomentAvailability.permanent.wireValue, 'permanent');
      expect(() => MomentAvailability.timedHours(23), throwsRangeError);
      expect(() => MomentAvailability.timedHours(721), throwsRangeError);
    });

    test('only the 24-hour default may be omitted on the wire', () {
      expect(MomentAvailability.hours24.isServerDefault, isTrue);
      for (final other in [
        MomentAvailability.timedHours(25),
        MomentAvailability.timedHours(72),
        MomentAvailability.timedHours(720),
        MomentAvailability.permanent,
      ]) {
        expect(other.isServerDefault, isFalse, reason: '$other must be sent');
      }
    });
  });

  group('VoiceMoment.isActiveAt under the amended contract', () {
    VoiceMoment moment({DateTime? expiresAt, String status = 'published'}) {
      return VoiceMoment(
        id: 'x',
        authorId: 'a',
        authorName: 'A',
        authorPhotoUrl: null,
        caption: 'c',
        audioUrl: 'https://cdn.example/x.m4a',
        durationSeconds: 10,
        likeCount: 0,
        commentCount: 0,
        isPublished: true,
        createdAt: DateTime(2026, 8, 1),
        expiresAt: expiresAt,
        schemaVersion: 2,
        status: status,
        isDeleted: false,
      );
    }

    final now = DateTime(2026, 8, 22, 12);

    test('null expiresAt now means PERMANENT — visible, never expiring', () {
      // Deliberately REVERSES ADR-101's null=legacy-hidden reading: the
      // operator asked for "keep until deleted", finalize expresses it by
      // writing no expiresAt, and the only null-expiry documents in
      // production are legacy ones the operator owns.
      expect(moment().isActiveAt(now), isTrue);
      expect(moment().isPermanent, isTrue);
    });

    test('a future expiresAt is live, a past one is dead — unchanged', () {
      expect(
        moment(expiresAt: now.add(const Duration(hours: 1))).isActiveAt(now),
        isTrue,
      );
      expect(
        moment(
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ).isActiveAt(now),
        isFalse,
      );
    });

    test('the sweeper\'s expired mark still beats everything, even with no '
        'expiresAt', () {
      expect(moment(status: 'expired').isActiveAt(now), isFalse);
    });
  });

  group('availability labels', () {
    test('no label for a permanent Moment on public surfaces — nothing is '
        'expiring', () {
      expect(momentExpiryLabel(null), isNull);
    });

    test('the author\'s availability line names the permanent fact', () {
      expect(momentAvailabilityLabel(null), 'Stays until deleted');
    });

    test('long windows read in days, short ones in hours and minutes', () {
      final now = DateTime(2026, 8, 22, 12);
      expect(
        momentExpiryLabel(now.add(const Duration(hours: 720)), now: now),
        'Expires in 30d',
      );
      expect(
        momentExpiryLabel(now.add(const Duration(hours: 47)), now: now),
        'Expires in 47h',
      );
      expect(
        momentExpiryLabel(now.add(const Duration(minutes: 42)), now: now),
        'Expires in 42m',
      );
      expect(
        momentAvailabilityLabel(now.add(const Duration(hours: 8)), now: now),
        'Expires in 8h',
      );
    });
  });

  group('the recorder\'s Available for selector', () {
    Widget host(Widget child) =>
        MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child);

    ({FakeStopwatch clock, StubMomentService service, Widget screen}) build({
      String? replyToMomentId,
    }) {
      final backend = FakeRecorderBackend();
      final capture = FakeAudioCapture()..result = FakeRecordedAudio();
      final service = StubMomentService();
      final clock = FakeStopwatch();
      return (
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

    Future<void> reachReview(WidgetTester tester, FakeStopwatch clock) async {
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      clock.value = const Duration(seconds: 5);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('offers a custom timed duration with 24 hours by default', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      expect(find.text('Available for'), findsOneWidget);
      expect(find.byKey(const ValueKey('availability-timed')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('availability-permanent')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('availability-amount')),
            )
            .controller!
            .text,
        '24',
      );
      expect(find.text('Hours'), findsOneWidget);
      expect(
        find.textContaining('visible in the feed for 24 hours'),
        findsOneWidget,
      );

      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(
        harness.service.publishedAvailability,
        MomentAvailability.hours24,
        reason: 'the default is today\'s behaviour: 24 hours',
      );
    });

    testWidgets('choosing Until deleted publishes as permanent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.tap(find.byKey(const ValueKey('availability-permanent')));
      await tester.pump();
      expect(
        find.textContaining('visible in the feed until you delete it'),
        findsOneWidget,
      );

      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(
        harness.service.publishedAvailability,
        MomentAvailability.permanent,
      );
    });

    testWidgets('a custom 3-day choice publishes 72 hours', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.tap(find.byKey(const ValueKey('availability-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Days').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('availability-amount')),
        '3',
      );
      await tester.pump();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(
        harness.service.publishedAvailability,
        MomentAvailability.timedHours(72),
      );
    });

    testWidgets('a custom 25-hour choice is accepted', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.enterText(
        find.byKey(const ValueKey('availability-amount')),
        '25',
      );
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(
        harness.service.publishedAvailability,
        MomentAvailability.timedHours(25),
      );
    });

    testWidgets('invalid timed input is explained and cannot publish', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.enterText(
        find.byKey(const ValueKey('availability-amount')),
        '23',
      );
      await tester.tap(find.text('Publish'));
      await tester.pump();

      expect(find.text('Choose between 24 and 720 hours.'), findsOneWidget);
      expect(harness.service.publishCalls, 0);
    });

    testWidgets('caption and availability freeze after the first attempt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      harness.service.failure = StateError('network unavailable');
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'Frozen caption',
      );
      await tester.enterText(
        find.byKey(const ValueKey('availability-amount')),
        '25',
      );
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('voice-moment-caption')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('availability-amount')),
            )
            .enabled,
        isFalse,
      );
      expect(
        find.text('Caption and availability are locked for this retry.'),
        findsOneWidget,
      );

      harness.service.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(harness.service.publishedCaptions, [
        'Frozen caption',
        'Frozen caption',
      ]);
      expect(harness.service.publishedAvailabilities, [
        MomentAvailability.timedHours(25),
        MomentAvailability.timedHours(25),
      ]);
    });

    testWidgets('a voice REPLY never shows the selector — replies have no '
        'expiry of their own', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build(replyToMomentId: 'parent-1');
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      expect(find.text('Available for'), findsNothing);
      expect(find.byKey(const ValueKey('availability-timed')), findsNothing);
      expect(
        find.byKey(const ValueKey('voice-preview-toggle')),
        findsOneWidget,
      );

      harness.service.failure = StateError('network unavailable');
      await tester.enterText(
        find.byKey(const ValueKey('voice-moment-caption')),
        'A reply worth retrying',
      );
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('voice-moment-caption')),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('Caption is locked for this retry.'), findsOneWidget);
    });
  });

  group('the availabilityHours wire field', () {
    ({_RecordingFunctions functions, MomentService service}) build() {
      final functions = _RecordingFunctions();
      return (
        functions: functions,
        service: MomentService(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
          storage: MockFirebaseStorage(),
          functions: functions,
        ),
      );
    }

    test('the DEFAULT choice sends NO availabilityHours — indistinguishable '
        'from every pre-availability client', () async {
      final harness = build();
      await harness.service.publishRecordedMoment(
        audio: FakeRecordedAudio(),
        durationSeconds: 5,
        caption: 'hello',
      );

      final finalize = harness.functions.calls.singleWhere(
        (call) => call.name == 'finalizeMomentDraft',
      );
      expect(finalize.payload.containsKey('availabilityHours'), isFalse);
    });

    test('a custom timed choice sends its hour count', () async {
      final harness = build();
      await harness.service.publishRecordedMoment(
        audio: FakeRecordedAudio(),
        durationSeconds: 5,
        caption: 'hello',
        availability: MomentAvailability.timedHours(25),
      );

      final finalize = harness.functions.calls.singleWhere(
        (call) => call.name == 'finalizeMomentDraft',
      );
      expect(finalize.payload['availabilityHours'], 25);
    });

    test('permanent sends the literal string', () async {
      final harness = build();
      await harness.service.publishRecordedMoment(
        audio: FakeRecordedAudio(),
        durationSeconds: 5,
        caption: 'hello',
        availability: MomentAvailability.permanent,
      );

      final finalize = harness.functions.calls.singleWhere(
        (call) => call.name == 'finalizeMomentDraft',
      );
      expect(finalize.payload['availabilityHours'], 'permanent');
    });

    test('a retry with a CHANGED availability is refused — the author must '
        'review what actually publishes', () async {
      final harness = build();
      harness.functions.failFinalize = true;
      final audio = FakeRecordedAudio();

      await expectLater(
        harness.service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 5,
          caption: 'hello',
          availability: MomentAvailability.timedHours(72),
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      harness.functions.failFinalize = false;
      await expectLater(
        harness.service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 5,
          caption: 'hello',
          availability: MomentAvailability.permanent,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('availability'),
          ),
        ),
      );
    });
  });
}

class _Call {
  _Call(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

/// Answers the two publish callables the way the server does, and records
/// every payload so the wire contract can be asserted byte for byte.
class _RecordingFunctions implements FirebaseFunctions {
  final calls = <_Call>[];
  bool failFinalize = false;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(this, name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this.owner, this.name);
  final _RecordingFunctions owner;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls.add(_Call(name, Map<String, dynamic>.from(parameters! as Map)));
    if (name == 'reserveMomentDraft') {
      return _FakeResult<T>(
        {
              'momentId': 'm-reserved',
              'storagePath': 'voice_moments/me/m-reserved.m4a',
            }
            as T,
      );
    }
    if (name == 'finalizeMomentDraft' && owner.failFinalize) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'finalize refused for the test',
      );
    }
    return _FakeResult<T>(<Object?, Object?>{'ok': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  _FakeResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
