import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/models/moderation_report.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_audit_timeline.dart';

/// The report audit timeline, and the claim that the queue's filters are
/// what the SERVER actually ran.
///
/// The audit trail's authorization and scoping live in the
/// `listReportAuditTrail` callable and are covered against the real
/// handler in functions/test/report_audit.test.js (plus an end-to-end
/// pass in functions/test/moderation_trigger.smoke.js). What is pinned
/// here is what the client owns: that a moderator is never shown a
/// history that is stale, duplicated, silently truncated, or left on
/// screen after their access goes away — and that a narrowed queue is a
/// narrowed QUERY, not a locally sieved page.
void main() {
  const mod = 'mod-uid';

  // ---------------------------------------------------------------
  // Server response shapes, built the way listReportAuditTrail
  // serialises them, so the parsing is exercised too rather than
  // hand-constructing model objects.
  // ---------------------------------------------------------------

  Map<String, dynamic> workflowEvent({
    required String id,
    required String at,
    String action = 'report_resolve',
    String? previousStatus = 'open',
    String? newStatus = 'resolved',
    String? resolution,
    String? note,
    bool contentRemoved = false,
  }) => <String, dynamic>{
    'id': id,
    'kind': 'reportWorkflow',
    'action': action,
    'actorId': mod,
    'actorName': 'Mod One',
    'actorRole': 'moderator',
    'previousStatus': previousStatus,
    'newStatus': newStatus,
    'resolution': resolution,
    'note': note,
    'contentRemoved': contentRemoved,
    'removedContent': null,
    'createdAt': at,
  };

  Map<String, dynamic> contentEvent({
    required String id,
    required String at,
    required String removed,
  }) => <String, dynamic>{
    'id': id,
    'kind': 'contentModeration',
    'action': 'globalMessage_moderated',
    'actorId': mod,
    'actorName': 'Mod One',
    'actorRole': 'moderator',
    'previousStatus': null,
    'newStatus': null,
    'resolution': null,
    'note': null,
    'contentRemoved': true,
    'removedContent': removed,
    'createdAt': at,
  };

  ModerationAuditPage page(
    List<Map<String, dynamic>> events, {
    bool hasMore = false,
    String? nextCursor,
  }) => ModerationAuditPage.fromResponse(<String, dynamic>{
    'events': events,
    'hasMore': hasMore,
    'nextCursor': nextCursor,
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF0B0713),
      body: SingleChildScrollView(child: SizedBox(width: 460, child: child)),
    ),
  );

  group('audit timeline', () {
    late _FakeAuditService service;
    late List<String> expired;

    setUp(() {
      // Never read from, but the base service resolves a Firestore
      // instance eagerly and there is no Firebase app under test.
      service = _FakeAuditService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: mod)),
      );
      expired = <String>[];
    });

    Widget timeline(String reportId, {int refreshToken = 0}) => host(
      ReportAuditTimeline(
        reportId: reportId,
        service: service,
        refreshToken: refreshToken,
        onAccessExpired: () => expired.add(reportId),
      ),
    );

    testWidgets('a spinner shows while the first page is in flight, and '
        'no empty state flashes before it lands', (tester) async {
      final gate = Completer<ModerationAuditPage>();
      service.handler = (_, _) => gate.future;

      await tester.pumpWidget(timeline('r1'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // "No recorded activity" while still loading would be a lie.
      expect(find.text('No recorded activity yet.'), findsNothing);

      gate.complete(
        page([workflowEvent(id: 'a', at: '2026-08-11T10:00:00.000Z')]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('a report with no history says so', (tester) async {
      service.handler = (_, _) async => page(const []);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();

      expect(find.text('No recorded activity yet.'), findsOneWidget);
      expect(find.text('Load earlier activity'), findsNothing);
    });

    testWidgets('events keep the newest-first order the server sent', (
      tester,
    ) async {
      service.handler = (_, _) async => page([
        workflowEvent(
          id: 'b',
          at: '2026-08-11T12:00:00.000Z',
          action: 'report_resolve',
        ),
        workflowEvent(
          id: 'a',
          at: '2026-08-11T09:00:00.000Z',
          action: 'report_claim',
          previousStatus: 'open',
          newStatus: 'inReview',
        ),
      ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();

      final newest = tester.getTopLeft(find.text('Resolved')).dy;
      final oldest = tester.getTopLeft(find.text('Claimed for review')).dy;
      expect(newest, lessThan(oldest));
    });

    testWidgets('a report event and a content-removal event are told apart, '
        'never merged into one row', (tester) async {
      service.handler = (_, _) async => page([
        workflowEvent(
          id: 'w',
          at: '2026-08-11T12:00:01.000Z',
          action: 'report_removeAndResolve',
          resolution: 'contentRemoved',
          note: 'repeat offender',
          contentRemoved: true,
        ),
        contentEvent(
          id: 'c',
          at: '2026-08-11T12:00:00.000Z',
          removed: 'the offending text',
        ),
      ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();

      // One row of each kind, each labelled for what it answers.
      expect(find.text('Removed content and resolved'), findsOneWidget);
      expect(find.text('Message removed'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);

      // The workflow row carries the transition and the note recorded
      // with THAT action; the content row carries the evidence.
      expect(
        find.text('open › resolved · contentRemoved · content removed'),
        findsOneWidget,
      );
      expect(find.text('repeat offender'), findsOneWidget);
      expect(find.text('the offending text'), findsOneWidget);
    });

    testWidgets('load earlier activity appends the next page, sends the '
        'cursor back, and repeats nothing', (tester) async {
      service.handler = (_, cursor) async => cursor == null
          ? page(
              [
                workflowEvent(
                  id: 'b',
                  at: '2026-08-11T12:00:00.000Z',
                  action: 'report_claim',
                  newStatus: 'inReview',
                ),
              ],
              hasMore: true,
              nextCursor: '2026-08-11T12:00:00.000Z',
            )
          : page([
              // The boundary event repeated by a careless server must
              // still not render twice.
              workflowEvent(
                id: 'b',
                at: '2026-08-11T12:00:00.000Z',
                action: 'report_claim',
                newStatus: 'inReview',
              ),
              workflowEvent(
                id: 'a',
                at: '2026-08-11T09:00:00.000Z',
                action: 'report_release',
                previousStatus: 'inReview',
                newStatus: 'open',
              ),
            ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();

      expect(find.text('Claimed for review'), findsOneWidget);
      expect(find.text('Load earlier activity'), findsOneWidget);

      await tester.tap(find.text('Load earlier activity'));
      await tester.pumpAndSettle();

      expect(service.calls, [
        'r1|first',
        'r1|2026-08-11T12:00:00.000Z',
      ]);
      expect(find.text('Claim released'), findsOneWidget);
      expect(find.text('Claimed for review'), findsOneWidget);
      // Exhausted: no button offering a page that does not exist.
      expect(find.text('Load earlier activity'), findsNothing);
    });

    testWidgets('a failure while paging keeps the history already loaded '
        'and retries from the same cursor', (tester) async {
      var attempt = 0;
      service.handler = (_, cursor) async {
        if (cursor == null) {
          return page(
            [workflowEvent(id: 'b', at: '2026-08-11T12:00:00.000Z')],
            hasMore: true,
            nextCursor: '2026-08-11T12:00:00.000Z',
          );
        }
        if (++attempt == 1) {
          throw const ModerationException(
            ModerationFailure.unknown,
            'The activity history could not be loaded.',
          );
        }
        return page([
          workflowEvent(
            id: 'a',
            at: '2026-08-11T09:00:00.000Z',
            action: 'report_claim',
            newStatus: 'inReview',
          ),
        ]);
      };

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load earlier activity'));
      await tester.pumpAndSettle();

      // The page that failed must not take the history down with it.
      expect(find.text('Resolved'), findsOneWidget);
      expect(
        find.text('The activity history could not be loaded.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Claimed for review'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      // Resumed from the same cursor rather than restarting.
      expect(service.calls, [
        'r1|first',
        'r1|2026-08-11T12:00:00.000Z',
        'r1|2026-08-11T12:00:00.000Z',
      ]);
    });

    testWidgets('an expired role clears the history that was on screen and '
        'hands off to the panel', (tester) async {
      service.handler = (_, _) async => page([
        contentEvent(
          id: 'c',
          at: '2026-08-11T12:00:00.000Z',
          removed: 'sensitive removed text',
        ),
      ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();
      expect(find.text('sensitive removed text'), findsOneWidget);

      // The role is revoked; the next refresh comes back denied.
      service.handler = (_, _) async => throw const ModerationException(
        ModerationFailure.accessExpired,
        'Your moderator access has been removed.',
      );
      await tester.pumpWidget(timeline('r1', refreshToken: 1));
      await tester.pumpAndSettle();

      expect(expired, ['r1']);
      expect(find.text('sensitive removed text'), findsNothing);
    });

    testWidgets('selecting another report never shows the previous '
        "report's history", (tester) async {
      service.handler = (reportId, _) async => page([
        workflowEvent(
          id: '$reportId-event',
          at: '2026-08-11T12:00:00.000Z',
          note: 'note for $reportId',
        ),
      ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();
      expect(find.text('note for r1'), findsOneWidget);

      await tester.pumpWidget(timeline('r2'));
      await tester.pumpAndSettle();

      expect(find.text('note for r1'), findsNothing);
      expect(find.text('note for r2'), findsOneWidget);
    });

    testWidgets('a slow response for the previous report cannot repaint '
        'under the new one', (tester) async {
      final slow = Completer<ModerationAuditPage>();
      service.handler = (reportId, _) =>
          reportId == 'r1'
              ? slow.future
              : Future.value(
                  page([
                    workflowEvent(
                      id: 'r2-event',
                      at: '2026-08-11T12:00:00.000Z',
                      note: 'note for r2',
                    ),
                  ]),
                );

      await tester.pumpWidget(timeline('r1'));
      await tester.pump();

      // The moderator moves on before r1's history arrives.
      await tester.pumpWidget(timeline('r2'));
      await tester.pumpAndSettle();
      expect(find.text('note for r2'), findsOneWidget);

      slow.complete(
        page([
          workflowEvent(
            id: 'r1-event',
            at: '2026-08-11T12:00:00.000Z',
            note: 'note for r1',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('note for r1'), findsNothing);
      expect(find.text('note for r2'), findsOneWidget);
    });

    testWidgets('a confirmed action reloads the trail once, and the new '
        'event appears exactly once', (tester) async {
      final events = <Map<String, dynamic>>[
        workflowEvent(
          id: 'claim',
          at: '2026-08-11T09:00:00.000Z',
          action: 'report_claim',
          newStatus: 'inReview',
        ),
      ];
      service.handler = (_, _) async => page(List.of(events.reversed));

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();
      expect(find.text('Claimed for review'), findsOneWidget);

      // The server confirms a resolve; the panel bumps the token.
      events.add(
        workflowEvent(
          id: 'resolve',
          at: '2026-08-11T12:00:00.000Z',
          resolution: 'noActionNeeded',
        ),
      );
      await tester.pumpWidget(timeline('r1', refreshToken: 1));
      await tester.pumpAndSettle();

      expect(service.calls, ['r1|first', 'r1|first']);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Claimed for review'), findsOneWidget);
    });

    testWidgets('an entry this build does not recognise is shown as such, '
        'never silently dropped', (tester) async {
      service.handler = (_, _) async => page([
        <String, dynamic>{
          'id': 'x',
          'kind': 'somethingNewer',
          'action': 'report_somethingNewer',
          'createdAt': '2026-08-11T12:00:00.000Z',
        },
      ]);

      await tester.pumpWidget(timeline('r1'));
      await tester.pumpAndSettle();

      expect(find.text('No recorded activity yet.'), findsNothing);
      expect(
        find.text('This entry has a shape this version does not recognise.'),
        findsOneWidget,
      );
    });
  });

  // -----------------------------------------------------------------
  // Filters and paging, at the level where the claim is made: the
  // query. A locally sieved page would pass a "the row disappeared"
  // assertion while being untrue about the whole matching set.
  // -----------------------------------------------------------------

  group('the queue narrows the QUERY, not the page', () {
    late FakeFirebaseFirestore db;
    late ModerationService service;

    Future<void> seed({
      required String id,
      String status = 'open',
      String reason = 'spam',
      String targetType = 'globalMessage',
      required Duration age,
    }) async {
      await db.collection('reports').doc(id).set(<String, dynamic>{
        'reporterId': 'reporter-$id',
        'targetType': targetType,
        'targetId': 'target-$id',
        'reportedUserId': 'author-$id',
        'reason': reason,
        'note': '',
        'status': status,
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
      });
    }

    setUp(() async {
      db = FakeFirebaseFirestore();
      service = ModerationService(
        firestore: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: mod)),
      );

      // A full page of noise in front, and one match hiding behind it.
      for (var i = 0; i < ModerationService.pageSize; i++) {
        await seed(id: 'noise-$i', age: Duration(minutes: i + 1));
      }
    });

    test('a reason filter finds a match that sits behind a full page of '
        'other reports', () async {
      await seed(id: 'old-harassment', reason: 'harassment', age: const Duration(days: 3));

      final results = await service
          .watchQueue(status: ReportStatus.open, reason: ReportReason.harassment)
          .first;

      // Client-side filtering of the newest 20 would return nothing here.
      expect(results.map((r) => r.id), ['old-harassment']);
    });

    test('a target-type filter is a server clause too', () async {
      await seed(
        id: 'old-account',
        targetType: 'user',
        age: const Duration(days: 3),
      );

      final results = await service
          .watchQueue(
            status: ReportStatus.open,
            targetType: ReportTargetType.user,
          )
          .first;

      expect(results.map((r) => r.id), ['old-account']);
    });

    test('status, target type and reason all apply together', () async {
      await seed(
        id: 'wanted',
        status: 'resolved',
        reason: 'hate',
        targetType: 'user',
        age: const Duration(days: 4),
      );
      await seed(
        id: 'wrong-status',
        reason: 'hate',
        targetType: 'user',
        age: const Duration(days: 4),
      );
      await seed(
        id: 'wrong-reason',
        status: 'resolved',
        reason: 'spam',
        targetType: 'user',
        age: const Duration(days: 4),
      );

      final results = await service
          .watchQueue(
            status: ReportStatus.resolved,
            targetType: ReportTargetType.user,
            reason: ReportReason.hate,
          )
          .first;

      expect(results.map((r) => r.id), ['wanted']);
    });

    test('the page window is a real limit, and raising it returns more',
        () async {
      await seed(id: 'extra', age: const Duration(days: 1));

      final firstPage = await service
          .watchQueue(status: ReportStatus.open)
          .first;
      expect(firstPage, hasLength(ModerationService.pageSize));
      expect(firstPage.map((r) => r.id), isNot(contains('extra')));

      final widened = await service
          .watchQueue(
            status: ReportStatus.open,
            limit: ModerationService.pageSize * 2,
          )
          .first;
      expect(widened, hasLength(ModerationService.pageSize + 1));
      expect(widened.map((r) => r.id), contains('extra'));
    });

    test('every filter combination the UI can produce has a declared '
        'composite index', () async {
      final declared = json.decode(
        File('firestore.indexes.json').readAsStringSync(),
      );
      final reportIndexes = (declared['indexes'] as List)
          .cast<Map<String, dynamic>>()
          .where((index) => index['collectionGroup'] == 'reports')
          .map((index) {
            final fields = (index['fields'] as List)
                .cast<Map<String, dynamic>>();
            return (
              equality: fields
                  .sublist(0, fields.length - 1)
                  .map((f) => f['fieldPath'] as String)
                  .toSet(),
              last: fields.last,
            );
          })
          .toList();

      // Exactly the four shapes watchQueue can build.
      final required = <Set<String>>[
        {'status'},
        {'status', 'targetType'},
        {'status', 'reason'},
        {'status', 'targetType', 'reason'},
      ];

      for (final combination in required) {
        final match = reportIndexes.where(
          (index) =>
              index.equality.length == combination.length &&
              index.equality.containsAll(combination),
        );
        expect(
          match,
          hasLength(1),
          reason:
              'no composite index for ${combination.toList()..sort()} — that '
              'query fails in production even though it passes here',
        );
        expect(match.first.last['fieldPath'], 'createdAt');
        expect(match.first.last['order'], 'DESCENDING');
      }
    });

    test('the scoped audit callable has its index too', () async {
      final declared = json.decode(
        File('firestore.indexes.json').readAsStringSync(),
      );
      final audit = (declared['indexes'] as List)
          .cast<Map<String, dynamic>>()
          .where((index) => index['collectionGroup'] == 'adminAuditLogs')
          .map(
            (index) => (index['fields'] as List)
                .cast<Map<String, dynamic>>()
                .map((f) => '${f['fieldPath']}:${f['order']}')
                .join(','),
          );

      expect(
        audit,
        contains(
          'targetType:ASCENDING,targetId:ASCENDING,createdAt:DESCENDING',
        ),
      );
    });
  });

  group('the Moderation Center asks the server for what it displays', () {
    late FakeFirebaseFirestore db;
    late _RecordingService service;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('users').doc(mod).set(<String, dynamic>{
        'uid': mod,
        'displayName': 'Mod One',
        'role': 'moderator',
      });
      service = _RecordingService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: mod, customClaim: {'role': 'moderator'}),
        ),
      );
    });

    Future<void> seedReports(int count, {String reason = 'spam'}) async {
      for (var i = 0; i < count; i++) {
        await db.collection('reports').doc('r$i').set(<String, dynamic>{
          'reporterId': 'reporter-$i',
          'targetType': 'globalMessage',
          'targetId': 'msg-$i',
          'reportedUserId': 'author-$i',
          'reason': reason,
          'note': '',
          'status': 'open',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(minutes: i + 1)),
          ),
        });
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ModerationCenterScreen(moderationService: service)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every visible filter reaches watchQueue as a real argument',
        (tester) async {
      await seedReports(2);
      await open(tester);

      expect(service.queries.last.status, ReportStatus.open);
      expect(service.queries.last.targetType, isNull);
      expect(service.queries.last.reason, isNull);

      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();
      expect(service.queries.last.status, ReportStatus.resolved);

      // Target and reason live behind the toolbar's Filters door now;
      // both are picked in one visit and land on Apply.
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account'));
      await tester.pump();
      await tester.tap(find.text('Spam or scam').last);
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      expect(service.queries.last.reason, ReportReason.spam);
      // Still carrying the earlier ones — filters compose server-side.
      expect(service.queries.last.status, ReportStatus.resolved);
      expect(service.queries.last.targetType, ReportTargetType.user);
    });

    testWidgets('changing a filter resets the page window instead of '
        'claiming to have paged through the new set', (tester) async {
      await seedReports(ModerationService.pageSize);
      await open(tester);

      expect(service.queries.last.limit, ModerationService.pageSize);

      await tester.scrollUntilVisible(
        find.text('Load more'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(service.queries.last.limit, ModerationService.pageSize * 2);

      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message').last);
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      expect(service.queries.last.targetType, ReportTargetType.globalMessage);
      expect(service.queries.last.limit, ModerationService.pageSize);
    });
  });
}

/// Stands in for the `listReportAuditTrail` callable. The callable itself
/// is covered against the real handler in functions/test.
class _FakeAuditService extends ModerationService {
  _FakeAuditService({super.firestore, super.auth});

  final List<String> calls = <String>[];
  Future<ModerationAuditPage> Function(String reportId, String? cursor)?
  handler;

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) {
    calls.add('$reportId|${cursor ?? 'first'}');
    return handler!(reportId, cursor);
  }
}

typedef _Query = ({
  ReportStatus status,
  ReportTargetType? targetType,
  ReportReason? reason,
  int limit,
});

/// Records what the screen asked the SERVER for, then delegates to the
/// real query so the recording cannot drift from the behaviour.
class _RecordingService extends ModerationService {
  _RecordingService({super.firestore, super.auth});

  final List<_Query> queries = <_Query>[];

  @override
  Stream<List<ModerationReport>> watchQueue({
    required ReportStatus status,
    ReportTargetType? targetType,
    ReportReason? reason,
    int limit = ModerationService.pageSize,
  }) {
    queries.add((
      status: status,
      targetType: targetType,
      reason: reason,
      limit: limit,
    ));
    return super.watchQueue(
      status: status,
      targetType: targetType,
      reason: reason,
      limit: limit,
    );
  }

  @override
  Future<ModerationAuditPage> reportAuditTrail(
    String reportId, {
    int limit = ModerationService.auditPageSize,
    String? cursor,
  }) async => ModerationAuditPage.empty;
}
