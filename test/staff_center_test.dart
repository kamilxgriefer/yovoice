// The redesigned Staff Center: seven capability-gated sections, the
// owner's directory search, and the user detail drawer's privileged
// actions — everything against fakes, with the server contracts pinned.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_users_section.dart';

const _ownerCaps = StaffCapabilities(
  staffRole: 'superAdmin',
  isOwner: true,
  manageRoles: true,
  fullAuditAccess: true,
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  endAnyRoom: true,
  permanentBan: true,
  liftSuspensions: true,
);

const _modCaps = StaffCapabilities(
  staffRole: 'moderator',
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  endPublicRoomWithReason: true,
);

DirectoryUser _sieeema({String role = 'user', bool vip = false}) =>
    DirectoryUser(
      uid: 'sieeema-uid',
      displayName: 'Sieeema',
      username: 'Sieeema',
      email: 'sieeema@example.com',
      photoUrl: null,
      staffRole: role,
      isVip: vip,
      banned: false,
      restricted: false,
      createdAt: DateTime(2026, 1, 5),
    );

class _FakeCapabilities extends StaffCapabilityService {
  _FakeCapabilities(this.capabilities);
  final StaffCapabilities capabilities;
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => capabilities;
}

/// A scripted directory: records queries, answers from a handler, and
/// can fail on demand with a typed error.
class _FakeDirectory implements StaffDirectoryService {
  _FakeDirectory(this.handler);

  DirectorySearchPage Function(String query, String filter) handler;
  final queries = <(String, String)>[];
  DirectorySearchException? failWith;

  @override
  Future<DirectorySearchPage> search({
    String query = '',
    String filter = 'all',
    String? cursor,
  }) async {
    queries.add((query, filter));
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
    return handler(query, filter);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOverview implements StaffOverviewService {
  @override
  Future<StaffOverview> load() async => StaffOverview.fromMap({
    'counts': {
      'totalUsers': 42,
      'activeRooms': 3,
      'openReports': 2,
      'restrictedAccounts': 1,
      'staffMembers': 5,
      'vipUsers': 7,
      'securityAlerts': 1,
    },
    'latestOpenReports': [
      {
        'id': 'r1',
        'targetType': 'globalMessage',
        'reason': 'spam',
        'status': 'open',
        'createdAt': DateTime(2026, 8, 14).toIso8601String(),
      },
    ],
    'activeRooms': [
      {'id': 'room1', 'name': 'Cosmic Lounge', 'participantCount': 9},
    ],
    'recentSanctions': <Map<String, dynamic>>[],
    'recentRoleChanges': <Map<String, dynamic>>[],
    'securityAlerts': <Map<String, dynamic>>[],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudit implements StaffAuditService {
  @override
  Future<StaffAuditPage> list({
    String? action,
    String? actorUid,
    String? targetId,
    String? cursorId,
    int limit = 50,
  }) async => const StaffAuditPage(entries: [], cursorId: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLookup implements StaffUserLookup {
  _FakeLookup(this.result);
  final ManagedUser result;
  @override
  Future<ManagedUser?> lookup(String rawInput) async => result;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingFunctions implements FirebaseFunctions {
  final calls = <(String, Map<String, dynamic>)>[];
  bool failNext = false;
  int callDelayMs = 0;

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
    if (owner.callDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: owner.callDelayMs));
    }
    owner.calls.add((name, Map<String, dynamic>.from(parameters as Map)));
    if (owner.failNext) {
      owner.failNext = false;
      throw Exception('rejected by the server');
    }
    return _FakeResult<T>(
      {
        'users': <Map<String, dynamic>>[],
        'nextCursor': null,
        'mode': 'name',
      } as T,
    );
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

void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget host(Widget child) => MaterialApp(home: child);

StaffCenterScreen screen({
  StaffCapabilities caps = _ownerCaps,
  _FakeDirectory? directory,
  _RecordingFunctions? functions,
  StaffUserLookup? lookup,
  FakeFirebaseFirestore? firestore,
}) {
  final db = firestore ?? FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'owner-uid'),
  );
  return StaffCenterScreen(
    capabilityService: _FakeCapabilities(caps),
    directoryService:
        directory ??
        _FakeDirectory((q, f) => const DirectorySearchPage(
          users: [],
          nextCursor: null,
          mode: 'browse',
        )),
    overviewService: _FakeOverview(),
    auditService: _FakeAudit(),
    moderationService: ModerationService(firestore: db, auth: auth),
    roomService: RoomService(firestore: db, auth: auth),
    lookup: lookup,
    functions: functions ?? _RecordingFunctions(),
    firestore: db,
    currentUid: 'owner-uid',
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('capability gating', () {
    testWidgets('the owner sees all seven sections in the rail',
        (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(host(screen()));
      await settle(tester);

      for (final label in [
        'Overview',
        'Users',
        'Reports',
        'Rooms & Spaces',
        'Sanctions',
        'Staff & Roles',
        'Audit Log',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a moderator sees exactly their sections — no Users, no '
        'Overview, no Audit Log', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(host(screen(caps: _modCaps)));
      await settle(tester);

      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Rooms & Spaces'), findsWidgets);
      expect(find.text('Sanctions'), findsWidgets);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Overview'), findsNothing);
      expect(find.text('Audit Log'), findsNothing);
    });

    testWidgets('an ordinary account is refused', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(host(screen(caps: StaffCapabilities.none)));
      await settle(tester);
      expect(
        find.textContaining('reserved for the application owner'),
        findsOneWidget,
      );
    });
  });

  group('overview', () {
    testWidgets('shows the real server counts and opens filtered sections',
        (tester) async {
      useSize(tester, const Size(1440, 900));
      final directory = _FakeDirectory(
        (q, f) => const DirectorySearchPage(
          users: [],
          nextCursor: null,
          mode: 'browse',
        ),
      );
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);

      expect(find.text('42'), findsOneWidget); // total users
      expect(find.text('Cosmic Lounge'), findsOneWidget); // real room row

      // The VIP card navigates to Users with the vip filter active.
      await tester.tap(find.text('VIP users'));
      await settle(tester);
      expect(find.byType(StaffUsersSection), findsOneWidget);
      expect(directory.queries.last.$2, 'vip');
    });
  });

  group('users search', () {
    testWidgets('the production case: Sieeema resolves and renders with '
        'badges, uid and status', (tester) async {
      useSize(tester, const Size(1440, 900));
      final directory = _FakeDirectory((query, filter) {
        final q = query.trim().toLowerCase().replaceFirst('@', '');
        if (q.isEmpty) {
          return const DirectorySearchPage(
            users: [],
            nextCursor: null,
            mode: 'browse',
          );
        }
        return DirectorySearchPage(
          users: 'sieeema'.startsWith(q) || q == 'sieeema-uid'
              ? [_sieeema(vip: true)]
              : const [],
          nextCursor: null,
          mode: 'name',
        );
      });
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);

      // Typed with the wrong case and padding — Enter submits at once.
      await tester.enterText(find.byType(TextField).first, '  sIeEeMa  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      expect(find.text('Sieeema'), findsWidgets);
      expect(find.text('@Sieeema'), findsOneWidget);
      expect(find.text('USER'), findsWidgets);
      expect(find.text('VIP'), findsWidgets);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.textContaining('1 result'), findsOneWidget);
      expect(find.text('sieeema-uid'), findsOneWidget);
    });

    testWidgets('typing debounces; two characters trigger the search',
        (tester) async {
      useSize(tester, const Size(1440, 900));
      final directory = _FakeDirectory(
        (q, f) => DirectorySearchPage(
          users: q.isEmpty ? const [] : [_sieeema()],
          nextCursor: null,
          mode: q.isEmpty ? 'browse' : 'name',
        ),
      );
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);
      final before = directory.queries.length;

      await tester.enterText(find.byType(TextField).first, 's');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        directory.queries.length,
        before,
        reason: 'one character must not query',
      );
      expect(
        find.textContaining('at least 2 characters'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, 'si');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        directory.queries.length,
        before,
        reason: 'debounce holds for 350ms',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(directory.queries.length, before + 1);
    });

    testWidgets('duplicate display names render as a list', (tester) async {
      useSize(tester, const Size(1440, 900));
      final twinA = DirectoryUser(
        uid: 'twin-a',
        displayName: 'Twin Voice',
        username: 'twin.one',
        email: null,
        photoUrl: null,
        staffRole: 'user',
        isVip: false,
        banned: false,
        restricted: false,
        createdAt: DateTime(2026),
      );
      final twinB = DirectoryUser(
        uid: 'twin-b',
        displayName: 'Twin Voice',
        username: 'twin.two',
        email: null,
        photoUrl: null,
        staffRole: 'moderator',
        isVip: false,
        banned: false,
        restricted: false,
        createdAt: DateTime(2026),
      );
      final directory = _FakeDirectory(
        (q, f) => DirectorySearchPage(
          users: q.isEmpty ? const [] : [twinA, twinB],
          nextCursor: null,
          mode: 'name',
        ),
      );
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'twin voice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      expect(find.text('Twin Voice'), findsNWidgets(2));
      expect(find.text('@twin.one'), findsOneWidget);
      expect(find.text('@twin.two'), findsOneWidget);
      expect(find.text('MODERATOR'), findsOneWidget);
    });

    testWidgets('a network failure says so, offers Retry, and never claims '
        '"no results"', (tester) async {
      useSize(tester, const Size(1440, 900));
      final directory = _FakeDirectory(
        (q, f) => DirectorySearchPage(
          users: [_sieeema()],
          nextCursor: null,
          mode: 'name',
        ),
      );
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);

      directory.failWith = const DirectorySearchException(
        DirectorySearchErrorKind.network,
        'unreachable',
      );
      await tester.enterText(find.byType(TextField).first, 'sieeema');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      expect(
        find.textContaining('could not be reached'),
        findsOneWidget,
      );
      expect(find.textContaining('No account matches'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('Sieeema'), findsWidgets);
    });

    testWidgets('a permission failure names itself', (tester) async {
      useSize(tester, const Size(1440, 900));
      final directory = _FakeDirectory(
        (q, f) => const DirectorySearchPage(
          users: [],
          nextCursor: null,
          mode: 'browse',
        ),
      );
      directory.failWith = const DirectorySearchException(
        DirectorySearchErrorKind.permission,
        'denied',
      );
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);

      expect(
        find.textContaining('reserved for the application owner'),
        findsOneWidget,
      );
    });

    testWidgets('pagination renders Load more only while a cursor exists',
        (tester) async {
      useSize(tester, const Size(1440, 900));
      // Counts only the pager query itself — mount-time browses and
      // filter reloads must not consume the pages.
      var pagerPage = 0;
      final directory = _FakeDirectory((q, f) {
        if (q != 'pager') {
          return const DirectorySearchPage(
            users: [],
            nextCursor: null,
            mode: 'browse',
          );
        }
        pagerPage += 1;
        final page = pagerPage;
        return DirectorySearchPage(
          users: [
            for (var i = 0; i < 3; i++)
              DirectoryUser(
                uid: 'page$page-$i',
                displayName: 'Pager $page-$i',
                username: 'pager.$page.$i',
                email: null,
                photoUrl: null,
                staffRole: 'user',
                isVip: false,
                banned: false,
                restricted: false,
                createdAt: DateTime(2026),
              ),
          ],
          nextCursor: page < 2 ? 'cursor-1' : null,
          mode: 'name',
        );
      });
      await tester.pumpWidget(host(screen(directory: directory)));
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'pager');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      expect(find.textContaining('more available'), findsOneWidget);
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await settle(tester);

      expect(find.textContaining('6 results'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });
  });

  group('user detail drawer', () {
    Future<_RecordingFunctions> openDrawer(WidgetTester tester) async {
      useSize(tester, const Size(1440, 900));
      final functions = _RecordingFunctions();
      final directory = _FakeDirectory(
        (q, f) => DirectorySearchPage(
          users: [_sieeema()],
          nextCursor: null,
          mode: 'name',
        ),
      );
      await tester.pumpWidget(
        host(
          screen(
            directory: directory,
            functions: functions,
            lookup: _FakeLookup(
              const ManagedUser(
                uid: 'sieeema-uid',
                displayName: 'Sieeema',
                username: 'Sieeema',
                role: 'user',
                banned: false,
                isVip: false,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Users').first);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'sieeema');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      await tester.tap(find.text('View'));
      await settle(tester);
      return functions;
    }

    testWidgets('shows identity, authoritative status and owner actions',
        (tester) async {
      await openDrawer(tester);

      expect(find.text('User detail'), findsOneWidget);
      expect(find.text('Authoritative status'), findsOneWidget);
      expect(find.text('Owner actions'), findsOneWidget);
      expect(find.text('Change staff role'), findsOneWidget);
      expect(find.text('Ban account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('role change: picker → required reason → exact payload with '
        'the stale-role guard', (tester) async {
      final functions = await openDrawer(tester);

      await tester.tap(find.text('Change staff role'));
      await settle(tester);
      await tester.tap(find.text('MODERATOR').last);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await settle(tester);

      // No reason yet — confirm must be disabled.
      final confirm = find.widgetWithText(FilledButton, 'Confirm change');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'passed the interview',
      );
      await tester.pump();
      await tester.tap(confirm);
      await settle(tester);

      final assignCalls =
          functions.calls.where((c) => c.$1 == 'assignUserRole').toList();
      expect(assignCalls, hasLength(1));
      expect(assignCalls.single.$2, {
        'uid': 'sieeema-uid',
        'role': 'moderator',
        'reason': 'passed the interview',
        'expectedRole': 'user',
      });
    });

    testWidgets('ban requires a reason and cannot double-submit',
        (tester) async {
      final functions = await openDrawer(tester);
      functions.callDelayMs = 300;

      await tester.tap(find.text('Ban account'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'abuse',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
      await tester.pump(const Duration(milliseconds: 50));

      // While the first call is in flight the action is disabled.
      final banButton = find.widgetWithText(OutlinedButton, 'Ban account');
      expect(tester.widget<OutlinedButton>(banButton).onPressed, isNull);

      await settle(tester);
      final banCalls =
          functions.calls.where((c) => c.$1 == 'setUserBan').toList();
      expect(banCalls, hasLength(1));
      expect(banCalls.single.$2['banned'], true);
      expect(banCalls.single.$2['reason'], 'abuse');

      // Drain the delayed refresh calls the success path fires.
      functions.callDelayMs = 0;
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    });
  });

  group('layout', () {
    testWidgets('1100px desktop keeps the rail without overflow',
        (tester) async {
      useSize(tester, const Size(1100, 800));
      await tester.pumpWidget(host(screen()));
      await settle(tester);
      expect(find.text('Audit Log'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile width falls back to tabs without overflow',
        (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(host(screen()));
      await settle(tester);
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
