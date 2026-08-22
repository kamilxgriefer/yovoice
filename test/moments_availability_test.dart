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
    test('mirrors the server whitelist exactly: 24, 72, 168, 720 hours or '
        'the literal permanent', () {
      expect(MomentAvailability.hours24.wireValue, 24);
      expect(MomentAvailability.days3.wireValue, 72);
      expect(MomentAvailability.days7.wireValue, 168);
      expect(MomentAvailability.days30.wireValue, 720);
      expect(MomentAvailability.permanent.wireValue, 'permanent');
    });

    test('only the 24-hour default may be omitted on the wire', () {
      expect(MomentAvailability.hours24.isServerDefault, isTrue);
      for (final other in MomentAvailability.values.where(
        (value) => value != MomentAvailability.hours24,
      )) {
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
        moment(
          expiresAt: now.add(const Duration(hours: 1)),
        ).isActiveAt(now),
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
    Widget host(Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: child,
    );

    ({
      FakeStopwatch clock,
      StubMomentService service,
      Widget screen,
    })
    build({String? replyToMomentId}) {
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

    Future<void> reachReview(
      WidgetTester tester,
      FakeStopwatch clock,
    ) async {
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      clock.value = const Duration(seconds: 5);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('offers exactly the five whitelisted choices, 24 hours '
        'selected by default', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      expect(find.text('Available for'), findsOneWidget);
      for (final option in MomentAvailability.values) {
        expect(
          find.byKey(ValueKey('availability-${option.name}')),
          findsOneWidget,
          reason: '${option.label} must be offered',
        );
        expect(find.text(option.label), findsOneWidget);
      }

      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(
        harness.service.publishedAvailability,
        MomentAvailability.hours24,
        reason: 'the default is today\'s behaviour: 24 hours',
      );
    });

    testWidgets('choosing Keep until deleted publishes as permanent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.tap(
        find.byKey(const ValueKey('availability-permanent')),
      );
      await tester.pump();
      expect(find.text('Stays in the feed until you delete it.'), findsOneWidget);

      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(
        harness.service.publishedAvailability,
        MomentAvailability.permanent,
      );
    });

    testWidgets('choosing 3 days publishes 72 hours', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await reachReview(tester, harness.clock);

      await tester.tap(find.byKey(const ValueKey('availability-days3')));
      await tester.pump();
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(harness.service.publishedAvailability, MomentAvailability.days3);
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
      expect(find.byKey(const ValueKey('availability-hours24')), findsNothing);
    });
  });

  group('the availabilityHours wire field', () {
    ({
      _RecordingFunctions functions,
      MomentService service,
    })
    build() {
      final functions = _RecordingFunctions();
      return (
        functions: functions,
        service: MomentService(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'me'),
          ),
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

    test('a timed choice sends its whitelisted hour count', () async {
      final harness = build();
      await harness.service.publishRecordedMoment(
        audio: FakeRecordedAudio(),
        durationSeconds: 5,
        caption: 'hello',
        availability: MomentAvailability.days7,
      );

      final finalize = harness.functions.calls.singleWhere(
        (call) => call.name == 'finalizeMomentDraft',
      );
      expect(finalize.payload['availabilityHours'], 168);
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
          availability: MomentAvailability.days3,
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
