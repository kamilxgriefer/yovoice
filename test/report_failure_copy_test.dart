import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';

/// Why a report was refused, in words the reporter can act on.
///
/// The defect this pins: [ReportService.report] used to distinguish a
/// duplicate by reading its own report document back. `reports` is
/// `allow read: if isActiveStaff()`, so that read is denied by design —
/// the `.catchError` always yielded false, [ReportAlreadyFiledException]
/// was unreachable in production, and a reporter who reported the same
/// account twice, reported too fast, or hit the daily cap saw the same
/// `[cloud_firestore/permission-denied] The caller does not have
/// permission…` string. On a safety path.
void main() {
  const uid = 'reporter-uid';
  const targetUid = 'target-uid';

  late FakeFirebaseFirestore db;
  late ReportService service;

  MockFirebaseAuth signedIn() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));

  setUp(() {
    db = FakeFirebaseFirestore();
    service = ReportService(firestore: db, auth: signedIn());
  });

  Future<void> seedTarget() =>
      db.collection('users').doc(targetUid).set({'uid': targetUid});

  Future<void> seedLimits({
    required Duration sinceLastReport,
    required Duration sinceWindowStart,
    required int windowCount,
  }) {
    final now = DateTime.now().toUtc();
    return db.collection('reportLimits').doc(uid).set({
      'lastReportAt': Timestamp.fromDate(now.subtract(sinceLastReport)),
      'lastReportId': 'previous',
      'windowStartAt': Timestamp.fromDate(now.subtract(sinceWindowStart)),
      'windowCount': windowCount,
    });
  }

  Future<void> fileReport() => service.report(
    targetType: ReportTargetType.user,
    targetId: targetUid,
    reportedUserId: targetUid,
    reason: ReportReason.harassment,
  );

  group('rate limits are told apart before the write', () {
    test('the 30-second cooldown says how long to wait', () async {
      await seedTarget();
      await seedLimits(
        sinceLastReport: const Duration(seconds: 12),
        sinceWindowStart: const Duration(seconds: 12),
        windowCount: 1,
      );

      try {
        await fileReport();
        fail('expected the cooldown to hold');
      } on ReportRateLimitedException catch (error) {
        expect(error.atDailyLimit, isFalse);
        expect(error.message, contains('wait'));
        expect(error.message, contains('second'));
        // The whole point: a screen running this through the shared
        // helper shows the reason, not "You don't have permission".
        expect(intentionalOrFriendly(error), error.message);
        expect(
          intentionalOrFriendly(error),
          isNot(contains("don't have permission")),
        );
      }
    });

    test('the daily cap says so, and points at blocking instead', () async {
      await seedTarget();
      await seedLimits(
        sinceLastReport: const Duration(minutes: 30),
        sinceWindowStart: const Duration(hours: 20),
        windowCount: ReportService.dailyLimit,
      );

      try {
        await fileReport();
        fail('expected the daily cap to hold');
      } on ReportRateLimitedException catch (error) {
        expect(error.atDailyLimit, isTrue);
        expect(error.message, contains('${ReportService.dailyLimit}'));
        expect(error.message, contains('24 hours'));
        // Someone at their cap during a sustained campaign needs a next
        // step, not a closed door.
        expect(error.message, contains('block'));
        expect(intentionalOrFriendly(error), error.message);
      }
    });

    test('the two refusals do not read the same', () async {
      await seedTarget();
      await seedLimits(
        sinceLastReport: const Duration(seconds: 5),
        sinceWindowStart: const Duration(seconds: 5),
        windowCount: 1,
      );
      final cooldown = await fileReport().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );

      await seedLimits(
        sinceLastReport: const Duration(minutes: 30),
        sinceWindowStart: const Duration(hours: 1),
        windowCount: ReportService.dailyLimit,
      );
      final daily = await fileReport().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );

      expect(
        (cooldown! as StateError).message,
        isNot((daily! as StateError).message),
      );
    });

    test('a clear allowance files the report', () async {
      await seedTarget();
      await fileReport();

      final stored = await db
          .collection('reports')
          .doc(
            ReportService.reportIdFor(
              reporterId: uid,
              targetType: ReportTargetType.user,
              targetId: targetUid,
            ),
          )
          .get();
      expect(stored.exists, isTrue);
      expect(stored.data()!['status'], 'open');
      expect(stored.data()!['reporterId'], uid);
    });
  });

  group('a refused write is explained without reading the report back', () {
    test('a duplicate reads as "already reported", not as a permission '
        'error', () async {
      await seedTarget();
      final reportId = ReportService.reportIdFor(
        reporterId: uid,
        targetType: ReportTargetType.user,
        targetId: targetUid,
      );

      // Production faithfulness, and the regression pin. `reports` is
      // staff-read-only, so if the service ever goes back to reading its
      // own report to classify the failure, it gets THIS — and the old
      // `.catchError((_) => false)` then swallowed it and rethrew the
      // raw FirebaseException.
      whenCalling(Invocation.method(#get, null))
          .on(db.collection('reports').doc(reportId))
          .thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message:
                  'The caller does not have permission to execute the '
                  'specified operation.',
            ),
          );
      whenCalling(Invocation.method(#set, null))
          .on(db.collection('reports').doc(reportId))
          .thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message:
                  'The caller does not have permission to execute the '
                  'specified operation.',
            ),
          );

      try {
        await fileReport();
        fail('expected the duplicate to be refused');
      } on ReportAlreadyFiledException catch (error) {
        expect(error.message, contains('already reported this'));
        expect(intentionalOrFriendly(error), error.message);
        // The strings the reporter used to get instead.
        expect(intentionalOrFriendly(error), isNot(contains('permission')));
        expect(intentionalOrFriendly(error), isNot(contains('caller')));
      }
    });

    test('a non-permission failure keeps its own friendly copy', () async {
      await seedTarget();
      final reportId = ReportService.reportIdFor(
        reporterId: uid,
        targetType: ReportTargetType.user,
        targetId: targetUid,
      );
      whenCalling(Invocation.method(#set, null))
          .on(db.collection('reports').doc(reportId))
          .thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );

      // Not misreported as a duplicate: an outage is not "you already
      // reported this", and telling someone their report is on file when
      // it is not would be the worst failure on this path.
      await expectLater(
        fileReport(),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
      expect(
        friendlyErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        contains('try again'),
      );
    });
  });

  group('reporting yourself and oversized context are refused locally', () {
    test('self-report', () async {
      await expectLater(
        service.report(
          targetType: ReportTargetType.user,
          targetId: uid,
          reportedUserId: uid,
          reason: ReportReason.spam,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cannot report yourself'),
          ),
        ),
      );
    });

    test('a context path longer than rules allow', () async {
      await seedTarget();
      await expectLater(
        service.report(
          targetType: ReportTargetType.user,
          targetId: targetUid,
          reportedUserId: targetUid,
          reason: ReportReason.spam,
          contextPath: 'x' * (ReportService.maxContextPathLength + 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the profile report asks for a reason', () {
    Future<void> openMenu(
      WidgetTester tester,
      _RecordingReportService recorder, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: UserActionsMenu(
              targetUid: targetUid,
              targetName: 'Ola',
              currentUid: uid,
              capabilities: const StaffCapabilities(staffRole: 'user'),
              reportService: recorder,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('every reason is offered, and the chosen one is what is '
        'filed', (tester) async {
      final recorder = _RecordingReportService();
      await openMenu(tester, recorder);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();

      expect(find.text('Report Ola'), findsOneWidget);
      for (final reason in ReportReason.values) {
        expect(find.text(reportReasonLabel(reason)), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('report-reason-selfHarm')));
      await tester.pumpAndSettle();

      // Not `harassment`. A queue where every row says the same thing
      // cannot be triaged, and self-harm is the row that must not wait
      // behind a spam complaint.
      expect(recorder.reasons, [ReportReason.selfHarm]);
      // Provenance belongs in contextPath; `note` is the reporter's own
      // words and stays empty rather than carrying a sentence they never
      // wrote.
      expect(recorder.notes.single, isEmpty);
      expect(recorder.contextPaths.single, 'users/$targetUid');
      expect(find.textContaining('Reported Ola'), findsOneWidget);
    });

    testWidgets('dismissing the reason picker files nothing', (tester) async {
      final recorder = _RecordingReportService();
      await openMenu(tester, recorder);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Report Ola'))).pop();
      await tester.pumpAndSettle();

      expect(recorder.reasons, isEmpty);
    });

    testWidgets('a refusal shows its own sentence, never a raw code', (
      tester,
    ) async {
      final recorder = _RecordingReportService(
        failure: ReportRateLimitedException(
          retryAfter: const Duration(seconds: 12),
          atDailyLimit: false,
        ),
      );
      await openMenu(tester, recorder);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
      await tester.pumpAndSettle();

      expect(find.textContaining('12 seconds'), findsOneWidget);
      expect(find.textContaining('permission'), findsNothing);
      expect(find.textContaining('cloud_firestore'), findsNothing);
    });

    for (final size in <String, Size>{
      'mobile': Size(390, 844),
      'tablet': Size(834, 1112),
      'desktop': Size(1440, 900),
    }.entries) {
      testWidgets('the picker renders on ${size.key}', (tester) async {
        final recorder = _RecordingReportService();
        await openMenu(tester, recorder, size: size.value);

        await tester.tap(find.text('Report user'));
        await tester.pumpAndSettle();

        expect(find.text('Report Ola'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// A real [ReportService] over a fake Firestore whose `report` is
/// recorded rather than written, so the menu's contract can be pinned
/// without exercising the write path twice.
class _RecordingReportService extends ReportService {
  _RecordingReportService({this.failure})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'reporter-uid'),
        ),
      );

  final Object? failure;
  final reasons = <ReportReason>[];
  final notes = <String>[];
  final contextPaths = <String?>[];

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required String reportedUserId,
    required ReportReason reason,
    String note = '',
    String? contextPath,
  }) async {
    reasons.add(reason);
    notes.add(note);
    contextPaths.add(contextPath);
    if (failure != null) throw failure!;
  }
}
