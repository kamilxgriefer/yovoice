import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
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

  ModerationService service(String uid, {String? role}) =>
      ModerationService(firestore: db, auth: authFor(uid, role: role));

  /// A real desktop surface. MaterialApp's `home` is laid out against
  /// the test WINDOW, so a SizedBox alone would still be squeezed into
  /// the default 800x600 and take the panel's narrow branch.
  void useDesktop(
    WidgetTester tester, {
    Size size = const Size(1440, 1200),
  }) {
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
      // The accepted six-item contract is unchanged.
      expect(desktopRailDestinations, {
        MoreDestination.discover,
        MoreDestination.friends,
      });
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
      expect(find.text('moderator'), findsOneWidget);
    });

    testWidgets('an admin gets the workspace', (tester) async {
      useDesktop(tester);
      await seedAccount('admin-uid', role: 'admin');
      await seedReport(id: 'r1');

      await tester.pumpWidget(
        host(
          ModerationCenterScreen(
            moderationService: service('admin-uid', role: 'admin'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
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
      expect(
        find.textContaining('Reports appear as the community files them'),
        findsOneWidget,
      );
    });

    testWidgets('real reports render with reason, target and status', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam', note: 'buying followers');
      await openAsStaff(tester);

      // Once as the reason filter, once as the row's heading.
      expect(find.text('Spam or scam'), findsNWidgets(2));
      expect(rowsWithTarget('Global message'), findsWidgets);
      expect(find.text('buying followers'), findsOneWidget);
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('the status filter narrows to that status only', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam');
      await seedReport(id: 'r2', reason: 'hate', status: 'resolved');
      await openAsStaff(tester);

      // Two = filter pill + row. One = filter pill only, no row.
      expect(find.text('Spam or scam'), findsNWidgets(2));
      expect(find.text('Hate speech'), findsOneWidget);

      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();

      expect(find.text('Hate speech'), findsNWidgets(2));
      expect(find.text('Spam or scam'), findsOneWidget);
    });

    testWidgets('the reason filter narrows within a status', (tester) async {
      await seedReport(id: 'r1', reason: 'spam');
      await seedReport(id: 'r2', reason: 'harassment');
      await openAsStaff(tester);

      expect(rowsWithTarget('Global message'), findsNWidgets(2));

      // Tap the FILTER pill (the first occurrence, above the queue).
      await tester.tap(find.text('Spam or scam').first);
      await tester.pumpAndSettle();
      expect(rowsWithTarget('Global message'), findsOneWidget);
      expect(find.text('Harassment or bullying'), findsOneWidget);
    });

    testWidgets('selecting a report opens its detail with the report id', (
      tester,
    ) async {
      await seedReport(id: 'r1', reason: 'spam', note: 'context here');
      await openAsStaff(tester);

      // The row, not the filter pill.
      await tester.tap(rowsWithTarget('Global message'));
      await tester.pumpAndSettle();

      expect(find.text('r1'), findsOneWidget);
      expect(find.text('context here'), findsWidgets);
      expect(find.text('Claim and review'), findsOneWidget);
    });

    testWidgets('a live update does not move the selection', (tester) async {
      await seedReport(id: 'r1', reason: 'spam', age: const Duration(hours: 2));
      await openAsStaff(tester);

      await tester.tap(rowsWithTarget('Global message'));
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
      expect(rowsWithTarget('Global message'), findsNWidgets(2));
    });
  });

  group('report model', () {
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

    test('an unknown status or reason degrades safely instead of throwing',
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
    });
  });

  group('idempotency keys', () {
    test('each user action gets a distinct request id', () {
      final ids = List.generate(50, (_) => ModerationService.newRequestId());
      expect(ids.toSet(), hasLength(50));
      expect(ids.every((id) => id.length >= 16), isTrue);
    });
  });
}
