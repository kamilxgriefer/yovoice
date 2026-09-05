import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';

/// The staff Moderation Center, client side.
///
/// AUTHORIZATION lives in firestore.rules (queue reads) and in the
/// moderateReport callable (every mutation) — both covered by their own
/// suites against the real rules and the real handler. What is pinned
/// here is what this code owns: that the destination is staff-gated, that
/// a non-staff visitor is refused WITHOUT loading report data, and that
/// no action ever paints an outcome the server did not confirm.
void main() {
  const mod = 'mod-uid';
  const plain = 'plain-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid, {String? role}) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@yovoice.app',
      displayName: 'Tester',
      // firebase_auth_mocks surfaces these as the ID token's claims.
      customClaim: role == null ? null : {'role': role},
    ),
  );

  Future<void> seedAccount(
    String uid, {
    String? role,
    bool banned = false,
  }) async {
    await db.collection('users').doc(uid).set(<String, dynamic>{
      'uid': uid,
      'displayName': uid,
      'role': ?role,
      if (banned) 'banned': true,
    });
  }

  Future<void> seedReport({
    required String id,
    String status = 'open',
    String reason = 'harassment',
    String targetType = 'globalMessage',
    String note = '',
    String? assignedTo,
    Duration age = const Duration(minutes: 5),
  }) async {
    await db.collection('reports').doc(id).set({
      'reporterId': 'reporter-uid',
      'targetType': targetType,
      'targetId': 'msg-$id',
      'reportedUserId': 'author-uid',
      'contextPath': 'globalChat/main/messages/msg-$id',
      'reason': reason,
      'note': note,
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
      'status': status,
      'assignedTo': ?assignedTo,
    });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
  });

  ModerationService service(String uid, {String? role}) => ModerationService(
    firestore: db,
    auth: authFor(uid, role: role),
  );

  /// A real desktop surface. MaterialApp's `home` is laid out against
  /// the test WINDOW, so a SizedBox alone would still be squeezed into
  /// the default 800x600 and take the panel's narrow branch.
  void useDesktop(WidgetTester tester, {Size size = const Size(1440, 1200)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) => MaterialApp(home: child);

  /// Filter pills and queue rows deliberately share reason labels, so
  /// row assertions look for the row's own target line instead.
  Finder rowsWithTarget(String label) => find.text(label);

  group('desktop navigation placement', () {
    test('Moderation is a More destination, never a primary rail item', () {
      // Moderation stays out of the rail. Moments joined it when it was
      // promoted to primary navigation; that is the only change here.
      expect(desktopRailDestinations, {
        MoreDestination.moments,
        MoreDestination.discover,
        MoreDestination.findCreators,
        MoreDestination.friends,
      });
      expect(
        desktopRailDestinations.contains(MoreDestination.moderation),
        isFalse,
      );
      expect(
        MoreDestination.values.contains(MoreDestination.moderation),
        isTrue,
      );
    });

    test('every pre-existing More destination still resolves to a screen', () {
      for (final destination in MoreDestination.values) {
        expect(
          () => moreDestinationScreen(destination),
          returnsNormally,
          reason: '$destination became unreachable',
        );
      }
    });
  });

  group('access', () {
    testWidgets('an ordinary user is refused and NO report is loaded', (
      tester,
    ) async {
      useDesktop(tester);
      await seedAccount(plain);
      await seedReport(id: 'r1', note: 'secret evidence');

      await tester.pumpWidget(
        host(ModerationCenterScreen(moderationService: service(plain))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation is staff only'), findsOneWidget);
      // Nothing from the queue may render, not even a reason label.
      expect(find.text('Harassment or bullying'), findsNothing);
      expect(find.text('secret evidence'), findsNothing);
    });

    testWidgets('a role CLAIM alone is not enough — the server record '
        'must agree', (tester) async {
      useDesktop(tester);
      // Claim says moderator; users/{uid}.role does not. This is a
      // revoked moderator holding a stale token.
      await seedAccount(mod, role: 'user');
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service(mod, role: 'moderator'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation is staff only'), findsOneWidget);
    });

    testWidgets('a BANNED moderator is refused', (tester) async {
      useDesktop(tester);
      await seedAccount(mod, role: 'moderator', banned: true);
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service(mod, role: 'moderator'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation is staff only'), findsOneWidget);
    });

    testWidgets('an active moderator gets the workspace', (tester) async {
      useDesktop(tester);
      await seedAccount(mod, role: 'moderator');
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service(mod, role: 'moderator'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('Moderation is staff only'), findsNothing);
      // The badge speaks human, never the internal claim vocabulary.
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('moderator'), findsNothing);
    });

    testWidgets('a super moderator gets the embedded workspace', (
      tester,
    ) async {
      useDesktop(tester);
      await seedAccount('super-mod-uid', role: 'superModerator');
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            embedded: true,
            moderationService: service('super-mod-uid', role: 'superModerator'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation is staff only'), findsNothing);
      expect(find.text('Harassment or bullying'), findsOneWidget);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('the legacy admin role is refused fail-closed', (tester) async {
      useDesktop(tester);
      await seedAccount('legacy-admin-uid', role: 'admin');
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service('legacy-admin-uid', role: 'admin'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation is staff only'), findsOneWidget);
      expect(find.text('Harassment or bullying'), findsNothing);
    });
  });

  group('queue', () {
    Future<void> openAsStaff(WidgetTester tester) async {
      useDesktop(tester);
      await seedAccount(mod, role: 'moderator');
      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service(mod, role: 'moderator'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an empty queue says so rather than showing nothing', (
      tester,
    ) async {
      await openAsStaff(tester);
      expect(find.text('No reports here'), findsOneWidget);
      expect(
        find.textContaining('New community reports will appear here'),
        findsOneWidget,
      );
      // ONE coherent empty state: the detail pane stays quiet rather
      // than competing with its own "Select a report".
      expect(find.text('Select a report'), findsNothing);
    });

    testWidgets('real reports render with reason, target and status', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam', note: 'buying followers');
      await openAsStaff(tester);

      // The permanent pill wall is gone: the reason appears ONLY on
      // the row itself now.
      expect(find.text('Spam or scam'), findsOneWidget);
      expect(rowsWithTarget('Message'), findsWidgets);
      expect(find.text('buying followers'), findsOneWidget);
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('a Reel report has a human label, filter and hide action', (
      tester,
    ) async {
      await seedReport(id: 'reel-report', targetType: 'reel');
      await openAsStaff(tester);

      expect(rowsWithTarget('Reel'), findsOneWidget);

      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Reel'), findsNWidgets(2));

      await tester.tap(find.text('Reel').last);
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      expect(rowsWithTarget('Reel'), findsNWidgets(2));
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hide Reel and resolve'), findsOneWidget);
      expect(find.text('Remove message and resolve'), findsNothing);
    });

    testWidgets('a self-contained Voice comment renders without its source and '
        'calls removeAndResolve', (tester) async {
      useDesktop(tester);
      await seedAccount(mod, role: 'moderator');
      await db.collection('reports').doc('voice-comment-report').set({
        'schemaVersion': 2,
        'reporterId': 'reporter-uid',
        'targetType': 'voiceMomentComment',
        'targetId': 'comment-1',
        'reportedUserId': 'voice-author',
        'contextPath': 'voiceMoments/moment-1/comments/comment-1',
        'conversationId': null,
        'messageId': null,
        'momentId': 'moment-1',
        'commentId': 'comment-1',
        'roomId': null,
        'clubId': null,
        'channelId': null,
        'reason': 'harassment',
        'note': 'immutable report evidence',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'status': 'open',
      });
      final recordingService = _RecordingVoiceModerationService(
        firestore: db,
        auth: authFor(mod, role: 'moderator'),
      );

      await tester.pumpWidget(
        host(ModerationCenterScreen(moderationService: recordingService)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'Harassment or bullying, Open')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reported Voice Moment comment'), findsOneWidget);
      expect(find.textContaining('Moment ID: moment-1'), findsOneWidget);
      expect(find.textContaining('Comment ID: comment-1'), findsOneWidget);
      expect(
        find.text('voiceMoments/moment-1/comments/comment-1'),
        findsOneWidget,
      );
      expect(find.text('voice-author'), findsOneWidget);

      final remove = find.text('Remove Voice Moment comment and resolve');
      expect(remove, findsOneWidget);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(find.text('Remove this Voice Moment comment?'), findsOneWidget);
      await tester.tap(find.text('Remove comment'));
      await tester.pumpAndSettle();

      expect(recordingService.removedReportId, 'voice-comment-report');
      expect(recordingService.removalRequestId, isNotNull);
      expect(recordingService.removalRequestId, isNotEmpty);
      expect(recordingService.removalNote, isEmpty);
      expect(
        find.text('Voice Moment comment removed and report resolved.'),
        findsOneWidget,
      );
    });

    testWidgets('a self-contained Voice Moment exposes its removal action', (
      tester,
    ) async {
      useDesktop(tester);
      await seedAccount(mod, role: 'moderator');
      await db.collection('reports').doc('voice-moment-report').set({
        'schemaVersion': 2,
        'reporterId': 'reporter-uid',
        'targetType': 'voiceMoment',
        'targetId': 'moment-2',
        'reportedUserId': 'voice-author',
        'contextPath': 'voiceMoments/moment-2',
        'conversationId': null,
        'messageId': null,
        'momentId': 'moment-2',
        'commentId': null,
        'roomId': null,
        'clubId': null,
        'channelId': null,
        'reason': 'spam',
        'note': '',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'status': 'open',
      });

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: _RecordingVoiceModerationService(
              firestore: db,
              auth: authFor(mod, role: 'moderator'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp(r'Spam or scam, Open')));
      await tester.pumpAndSettle();

      expect(find.text('Reported Voice Moment'), findsOneWidget);
      expect(find.textContaining('Moment ID: moment-2'), findsOneWidget);
      expect(find.text('voiceMoments/moment-2'), findsOneWidget);
      expect(find.text('Remove Voice Moment and resolve'), findsOneWidget);
    });

    testWidgets('the status filter narrows to that status only', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam');
      await seedReport(id: 'r2', reason: 'hate', status: 'resolved');
      await openAsStaff(tester);

      // Reasons render only on rows now: open shows spam, not hate.
      expect(find.text('Spam or scam'), findsOneWidget);
      expect(find.text('Hate speech'), findsNothing);

      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();

      expect(find.text('Hate speech'), findsOneWidget);
      expect(find.text('Spam or scam'), findsNothing);
    });

    testWidgets('the reason filter narrows within a status', (tester) async {
      await seedReport(id: 'r1', reason: 'spam');
      await seedReport(id: 'r2', reason: 'harassment');
      await openAsStaff(tester);

      expect(rowsWithTarget('Message'), findsNWidgets(2));

      // Filters live behind the toolbar's Filters door now: open it,
      // pick the reason, Apply.
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam or scam').last);
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      // One matching row remains, plus the removable active-filter
      // chip under the toolbar; the other reason is gone entirely.
      expect(rowsWithTarget('Message'), findsOneWidget);
      expect(find.text('Spam or scam'), findsNWidgets(2));
      expect(find.text('Harassment or bullying'), findsNothing);
    });

    testWidgets('selecting a report opens its detail with the report id', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam', note: 'context here');
      await openAsStaff(tester);

      await tester.tap(rowsWithTarget('Message'));
      await tester.pumpAndSettle();

      expect(find.text('r1'), findsOneWidget);
      expect(find.text('context here'), findsWidgets);
      expect(find.text('Claim and review'), findsOneWidget);
    });

    testWidgets('a report row can be focused and opened with Enter', (
      tester,
    ) async {
      await seedReport(id: 'keyboard-report', reason: 'spam');
      await openAsStaff(tester);
      final semantics = tester.ensureSemantics();

      final row = find.bySemanticsLabel(RegExp(r'Spam or scam, Open'));
      expect(row, findsOneWidget);
      final inkWell = find.descendant(of: row, matching: find.byType(InkWell));
      expect(inkWell, findsOneWidget);

      final control = tester.widget<InkWell>(inkWell);
      expect(control.focusNode, isNotNull);
      control.focusNode!.requestFocus();
      await tester.pump();
      expect(control.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('keyboard-report'), findsOneWidget);
      expect(find.text('Claim and review'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a live update does not move the selection', (tester) async {
      await seedReport(id: 'r1', reason: 'spam', age: const Duration(hours: 2));
      await openAsStaff(tester);

      await tester.tap(rowsWithTarget('Message'));
      await tester.pumpAndSettle();
      expect(find.text('r1'), findsOneWidget);

      // A newer report arrives at the head of the queue.
      await seedReport(
        id: 'r2',
        reason: 'hate',
        age: const Duration(minutes: 1),
      );
      await tester.pumpAndSettle();

      // Still showing r1's detail, even though a newer row arrived.
      expect(find.text('r1'), findsOneWidget);
      expect(rowsWithTarget('Message'), findsNWidgets(2));
    });
  });

  group('report model', () {
    test(
      'a self-contained v2 Voice comment keeps immutable target identity',
      () async {
        await db.collection('reports').doc('voice-comment-v2').set({
          'schemaVersion': 2,
          'reporterId': 'reporter-uid',
          'targetType': 'voiceMomentComment',
          'targetId': 'comment-1',
          'reportedUserId': 'comment-author',
          'contextPath': 'voiceMoments/moment-1/comments/comment-1',
          'momentId': 'moment-1',
          'commentId': 'comment-1',
          'reason': 'harassment',
          'note': '',
          'createdAt': Timestamp.now(),
          'status': 'open',
        });

        final report = ModerationReport.fromFirestore(
          await db.collection('reports').doc('voice-comment-v2').get(),
        );

        expect(report.schemaVersion, 2);
        expect(report.targetType, ReportTargetType.voiceMomentComment);
        expect(report.targetId, 'comment-1');
        expect(report.momentId, 'moment-1');
        expect(report.commentId, 'comment-1');
        expect(report.reportedUserId, 'comment-author');
        expect(report.contextPath, 'voiceMoments/moment-1/comments/comment-1');
      },
    );

    test('an earlier v2 Voice report derives a safe reference without '
        'loading its target', () async {
      await db.collection('reports').doc('voice-legacy-v2').set({
        'schemaVersion': 2,
        'reporterId': 'reporter-uid',
        'targetType': 'voiceMoment',
        'momentId': 'moment-legacy',
        'commentId': null,
        'reason': 'spam',
        'note': '',
        'createdAt': Timestamp.now(),
        'status': 'open',
      });

      final report = ModerationReport.fromFirestore(
        await db.collection('reports').doc('voice-legacy-v2').get(),
      );

      expect(report.targetType, ReportTargetType.voiceMoment);
      expect(report.targetId, 'moment-legacy');
      expect(report.momentId, 'moment-legacy');
      expect(report.commentId, isNull);
      expect(report.reportedUserId, isEmpty);
      expect(report.contextPath, 'voiceMoments/moment-legacy');
    });

    test('an earlier v2 Voice comment derives its comment reference', () async {
      await db.collection('reports').doc('voice-comment-legacy-v2').set({
        'schemaVersion': 2,
        'reporterId': 'reporter-uid',
        'targetType': 'voiceMomentComment',
        'momentId': 'moment-legacy',
        'commentId': 'comment-legacy',
        'reason': 'spam',
        'note': '',
        'createdAt': Timestamp.now(),
        'status': 'open',
      });

      final report = ModerationReport.fromFirestore(
        await db.collection('reports').doc('voice-comment-legacy-v2').get(),
      );

      expect(report.targetType, ReportTargetType.voiceMomentComment);
      expect(report.targetId, 'comment-legacy');
      expect(report.reportedUserId, isEmpty);
      expect(
        report.contextPath,
        'voiceMoments/moment-legacy/comments/comment-legacy',
      );
    });

    test(
      'a canonical Reel target remains typed in the moderation queue',
      () async {
        await db.collection('reports').doc('reel').set({
          'reporterId': 'reporter-uid',
          'targetType': 'reel',
          'targetId': 'reel-1',
          'reportedUserId': 'author-uid',
          'reason': 'spam',
          'note': '',
          'createdAt': Timestamp.now(),
          'status': 'open',
        });

        final report = ModerationReport.fromFirestore(
          await db.collection('reports').doc('reel').get(),
        );

        expect(report.targetType, ReportTargetType.reel);
      },
    );

    test('a report with NO status field is treated as Open, so nothing '
        'needs migrating', () async {
      await db.collection('reports').doc('legacy').set({
        'reporterId': 'reporter-uid',
        'targetType': 'globalMessage',
        'targetId': 'msg-legacy',
        'reportedUserId': 'author-uid',
        'reason': 'spam',
        'note': '',
        'createdAt': Timestamp.now(),
      });

      final snapshot = await db.collection('reports').doc('legacy').get();
      final report = ModerationReport.fromFirestore(snapshot);

      expect(report.status, ReportStatus.open);
      expect(report.assignedTo, isNull);
      expect(report.contentRemoved, isFalse);
      expect(report.reason, ReportReason.spam);
    });

    test(
      'an unknown status or reason degrades safely instead of throwing',
      () async {
        await db.collection('reports').doc('odd').set({
          'reporterId': 'r',
          'targetType': 'somethingNew',
          'targetId': 't',
          'reportedUserId': 'a',
          'reason': 'somethingNew',
          'note': '',
          'createdAt': Timestamp.now(),
          'status': 'somethingNew',
        });

        final report = ModerationReport.fromFirestore(
          await db.collection('reports').doc('odd').get(),
        );
        expect(report.status, ReportStatus.open);
        expect(report.reason, isNull);
        expect(report.targetType, isNull);
      },
    );
  });

  group('idempotency keys', () {
    test('each user action gets a distinct request id', () {
      final ids = List.generate(50, (_) => ModerationService.newRequestId());
      expect(ids.toSet(), hasLength(50));
      expect(ids.every((id) => id.length >= 16), isTrue);
    });
  });
}

class _RecordingVoiceModerationService extends ModerationService {
  _RecordingVoiceModerationService({
    required FakeFirebaseFirestore firestore,
    required MockFirebaseAuth auth,
  }) : super(firestore: firestore, auth: auth);

  String? removedReportId;
  String? removalRequestId;
  String? removalNote;

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) async => ModerationAuditPage.empty;

  @override
  Future<ModerationResult> removeContentAndResolve(
    String reportId, {
    required String requestId,
    String note = '',
  }) async {
    removedReportId = reportId;
    removalRequestId = requestId;
    removalNote = note;
    return const ModerationResult(
      status: ReportStatus.resolved,
      contentRemoved: true,
      replayed: false,
    );
  }
}
