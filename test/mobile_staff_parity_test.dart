// Mobile parity for Staff Center, moderation tools and identity badges.
//
// What must hold:
//  1. An ordinary (or VIP-only) account's More sheet is EXACTLY the
//     layout it always was — no staff section, no gap.
//  2. Every available mobile staff destination is derived from server
//     capabilities alone. Owner/super moderator retain Staff Center and
//     also get the violet Moderation destination available on desktop.
//  3. A forged non-owner superAdmin — whose SERVER capabilities are the
//     super-moderation tier — never receives the owner entry or the
//     owner sections.
//  4. Switching accounts clears cached capabilities.
//  5. The Staff Center flows (search, drawer confirmations,
//     double-submit) work at phone widths, and 320/390/430 lay out
//     without overflow, safe areas and keyboard included.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _ownerCaps = StaffCapabilities(
  staffRole: 'superAdmin',
  isOwner: true,
  manageRoles: true,
  fullAuditAccess: true,
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  endAnyRoom: true,
  liftSuspensions: true,
  viewAllQueues: true,
  permanentBan: true,
);

SubscriptionEntitlements _activePremium() => SubscriptionEntitlements(
  plan: PremiumPlan.monthly,
  status: 'active',
  currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
  isPremium: true,
  creatorEnabled: true,
  canCreateClubs: true,
  premiumIdentityEnabled: true,
  maxOwnedClubs: 3,
);

/// What the SERVER actually derives for a forged non-owner superAdmin:
/// the super-moderation tier — manageRoles, fullAuditAccess and
/// permanentBan stay false, isOwner stays false.
const _forgedSuperAdminCaps = StaffCapabilities(
  staffRole: 'superAdmin',
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  suspensionLimitHours: 720,
  endAnyRoom: true,
  liftSuspensions: true,
  viewAllQueues: true,
);

const _superModCaps = StaffCapabilities(
  staffRole: 'superModerator',
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  suspensionLimitHours: 720,
  endAnyRoom: true,
  liftSuspensions: true,
  viewAllQueues: true,
);

const _modCaps = StaffCapabilities(
  staffRole: 'moderator',
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
  suspensionLimitHours: 24,
  endPublicRoomWithReason: true,
);

class _FakeCapabilities extends StaffCapabilityService {
  _FakeCapabilities(this.capabilities);
  final StaffCapabilities capabilities;
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => capabilities;
}

class _CountingFunctions implements FirebaseFunctions {
  int calls = 0;
  Map<String, dynamic> capabilitiesPayload = const {'staffRole': 'user'};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CountingCallable(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingCallable implements HttpsCallable {
  _CountingCallable(this.owner);
  final _CountingFunctions owner;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls += 1;
    return _FakeResult<T>({'capabilities': owner.capabilitiesPayload} as T);
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

class _FakeDirectory implements StaffDirectoryService {
  _FakeDirectory(this.handler);
  final DirectorySearchPage Function(String query, String filter) handler;
  @override
  Future<DirectorySearchPage> search({
    String query = '',
    String filter = 'all',
    String? cursor,
  }) async => handler(query, filter);
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

class _FakeOverview implements StaffOverviewService {
  @override
  Future<StaffOverview> load() async => StaffOverview.fromMap({
    'counts': {
      'totalUsers': 19,
      'activeRooms': 2,
      'openReports': 1,
      'restrictedAccounts': 0,
      'staffMembers': 1,
      'vipUsers': 1,
      'securityAlerts': 0,
    },
    'latestOpenReports': <Map<String, dynamic>>[],
    'activeRooms': <Map<String, dynamic>>[],
    'recentSanctions': <Map<String, dynamic>>[],
    'recentRoleChanges': <Map<String, dynamic>>[],
    'securityAlerts': <Map<String, dynamic>>[],
  });
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

DirectoryUser _sieeema() => DirectoryUser(
  uid: 'sieeema-uid',
  displayName: 'Sieeema',
  username: 'Sieeema',
  email: null,
  photoUrl: null,
  staffRole: 'user',
  isVip: true,
  banned: false,
  restricted: false,
  createdAt: DateTime(2026, 7, 19),
);

void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget sheetHost(Widget sheet) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: sheet),
  ),
);

Widget modalSheetHost({
  SubscriptionEntitlements entitlements = SubscriptionEntitlements.free,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        key: const ValueKey('open-more-sheet'),
        onPressed: () async {
          await showMoreSheet(context, entitlements: entitlements);
        },
        child: const Text('Open More'),
      ),
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('staff entry derivation (capabilities only, never a role string)', () {
    test('tiers map to their doors and theme colors', () {
      final owner = staffEntriesFor(_ownerCaps);
      expect(owner.map((entry) => entry.destination), [
        MoreDestination.moderation,
        MoreDestination.staffCenter,
      ]);
      expect(owner.last.label, 'Staff Center');
      expect(owner.last.color, AppColors.roleOwner);

      final superMod = staffEntriesFor(_superModCaps);
      expect(superMod.map((entry) => entry.destination), [
        MoreDestination.moderation,
        MoreDestination.staffCenter,
      ]);
      expect(superMod.last.color, AppColors.roleSuperModerator);

      final mod = staffEntriesFor(_modCaps).single;
      expect(mod.destination, MoreDestination.moderation);
      expect(mod.label, 'Moderation');
      expect(mod.color, AppColors.roleModerator);

      // Ordinary, VIP-only, and shipped-nothing staff roles get NO entry
      // (their capability flags have no surfaces yet).
      expect(staffEntriesFor(StaffCapabilities.none), isEmpty);
      expect(staffEntriesFor(const StaffCapabilities(isVip: true)), isEmpty);
      expect(
        staffEntriesFor(
          const StaffCapabilities(staffRole: 'auditor', readAuditLogs: true),
        ),
        isEmpty,
      );
      expect(
        staffEntriesFor(
          const StaffCapabilities(staffRole: 'support', supportLookup: true),
        ),
        isEmpty,
      );
      expect(
        staffEntriesFor(
          const StaffCapabilities(staffRole: 'guideMaster', guideMode: true),
        ),
        isEmpty,
      );
    });

    test('a FORGED superAdmin — the tier the server actually grants it — '
        'gets the coral super-moderation entry, never the owner one', () {
      final forged = staffEntriesFor(_forgedSuperAdminCaps);
      expect(forged.last.color, AppColors.roleSuperModerator);
      expect(forged.last.color, isNot(AppColors.roleOwner));
      // Even though the LOCAL role string says superAdmin — proof the
      // string is never consulted.
      expect(_forgedSuperAdminCaps.staffRole, 'superAdmin');
    });
  });

  group('mobile More sheet', () {
    testWidgets("an ordinary account's sheet keeps all product destinations, "
        'Settings, no staff section, no gap', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(modalSheetHost());
      await tester.tap(find.byKey(const ValueKey('open-more-sheet')));
      await settle(tester);

      for (final label in [
        'Profile',
        'Discover',
        'Find creators',
        'Clubs',
        'Moments',
        'Alerts',
        'Awards',
        'Creator',
        'Settings',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Staff Center'), findsNothing);
      expect(find.text('Moderation Center'), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-clubs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-creatorStudio')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a VIP-only account sees the same ordinary sheet', (
      tester,
    ) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        sheetHost(
          MoreSheet(
            capabilityService: _FakeCapabilities(
              const StaffCapabilities(isVip: true),
            ),
            currentUid: 'vip-uid',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-clubs')),
        findsOneWidget,
        reason: 'a complimentary VIP badge is not a paid entitlement',
      );
    });

    testWidgets('paid Premium removes the Clubs and Creator locks', (
      tester,
    ) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(modalSheetHost(entitlements: _activePremium()));
      await tester.tap(find.byKey(const ValueKey('open-more-sheet')));
      await settle(tester);

      expect(find.text('Clubs'), findsOneWidget);
      expect(find.text('Creator'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-clubs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-creatorStudio')),
        findsNothing,
      );
    });

    testWidgets('owner, super moderator and moderator each get their own '
        'entry, with the account badges beside the section title', (
      tester,
    ) async {
      useSize(tester, const Size(390, 844));
      final previous = PublicIdentityRepository.instance;
      addTearDown(() => PublicIdentityRepository.instance = previous);

      for (final (caps, expectedEntry, badgeRole) in [
        (_ownerCaps, 'Staff Center', 'superAdmin'),
        (_superModCaps, 'Staff Center', 'superModerator'),
        (_modCaps, 'Moderation', 'moderator'),
      ]) {
        PublicIdentityRepository.instance = PublicIdentityRepository(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'self-uid'),
          ),
          fetchOverride: (uids) async => {
            for (final uid in uids)
              uid: {'staffRole': badgeRole, 'isVip': true},
          },
          flushDelay: const Duration(milliseconds: 1),
        );
        await tester.pumpWidget(
          sheetHost(
            MoreSheet(
              key: ValueKey(caps.staffRole),
              capabilityService: _FakeCapabilities(caps),
              currentUid: 'self-uid',
            ),
          ),
        );
        await settle(tester);

        expect(find.text('Staff'), findsOneWidget, reason: caps.staffRole);
        expect(
          find.text(expectedEntry),
          findsOneWidget,
          reason: '${caps.staffRole} → $expectedEntry',
        );
        if (caps.handleAssignedReports) {
          expect(find.text('Moderation'), findsOneWidget);
        }
        // The section carries the account's own authoritative badges —
        // official role AND the separate VIP badge.
        expect(find.text('VIP'), findsOneWidget, reason: caps.staffRole);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the forged superAdmin sheet gets the coral entry, and the '
        'sheet fits 320x640 without overflow', (tester) async {
      useSize(tester, const Size(320, 640));
      await tester.pumpWidget(
        sheetHost(
          MoreSheet(
            capabilityService: _FakeCapabilities(_forgedSuperAdminCaps),
            currentUid: 'forged-uid',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Staff Center'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-clubs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-creatorStudio')),
        findsOneWidget,
      );

      final handleBefore = tester.getCenter(
        find.byKey(const ValueKey('more-sheet-drag-handle')),
      );
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('more-sheet-scroll-view')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('more-sheet-scroll-view')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(
        tester.getCenter(find.byKey(const ValueKey('more-sheet-drag-handle'))),
        handleBefore,
        reason: 'the modal drag handle stays fixed while content scrolls',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the production modal remains scrollable with phone safe '
        'areas and an open keyboard', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 59, bottom: 34),
            viewInsets: EdgeInsets.only(bottom: 336),
          ),
          child: modalSheetHost(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-more-sheet')));
      await settle(tester);

      expect(find.byKey(const ValueKey('more-sheet-scroll-view')), findsOne);
      expect(find.byType(ModalBarrier), findsWidgets);
      expect(
        find.byKey(const ValueKey('mobile-premium-lock-clubs')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('capability cache and account switching', () {
    test('switching accounts refetches; signing out forgets', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'account-a'),
      );
      final functions = _CountingFunctions()
        ..capabilitiesPayload = const {'staffRole': 'moderator'};
      final service = StaffCapabilityService(functions: functions, auth: auth);

      await service.load();
      await service.load();
      expect(functions.calls, 1, reason: 'same account is served cached');

      // Sign out: the cache must not answer for the dead session.
      await auth.signOut();
      final signedOut = await service.load();
      expect(signedOut.staffRole, 'user');

      // A different account triggers a fresh fetch, never account A's
      // cached answer.
      await auth.signInWithCustomToken('token-b');
      await service.load();
      expect(functions.calls, greaterThanOrEqualTo(2));
    });
  });

  group('mobile Staff Center', () {
    StaffCenterScreen mobileScreen({
      StaffCapabilities caps = _ownerCaps,
      _FakeDirectory? directory,
      FirebaseFunctions? functions,
    }) {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner-uid'),
      );
      return StaffCenterScreen(
        capabilityService: _FakeCapabilities(caps),
        directoryService:
            directory ??
            _FakeDirectory(
              (q, f) => DirectorySearchPage(
                users: q.isEmpty ? const [] : [_sieeema()],
                nextCursor: null,
                mode: q.isEmpty ? 'browse' : 'name',
              ),
            ),
        overviewService: _FakeOverview(),
        auditService: _FakeAudit(),
        moderationService: ModerationService(firestore: db, auth: auth),
        roomService: RoomService(firestore: db, auth: auth),
        lookup: _FakeLookup(
          const ManagedUser(
            uid: 'sieeema-uid',
            displayName: 'Sieeema',
            username: 'Sieeema',
            role: 'user',
            banned: false,
            isVip: true,
          ),
        ),
        functions: functions ?? _CountingFunctions(),
        firestore: db,
        currentUid: 'owner-uid',
      );
    }

    testWidgets('phone widths use tab chips, and all three sizes lay out '
        'clean for the owner', (tester) async {
      for (final size in const [
        Size(320, 640),
        Size(390, 844),
        Size(430, 932),
      ]) {
        useSize(tester, size);
        await tester.pumpWidget(MaterialApp(home: mobileScreen()));
        await settle(tester);
        expect(find.byType(ChoiceChip), findsWidgets, reason: '$size');
        expect(find.byType(NavigationRail), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Moderation Center'));
        await settle(tester);
        expect(find.byType(ModerationCenterScreen), findsOneWidget);
        expect(find.text('Open Moderation Center'), findsNothing);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('safe areas and an open keyboard do not break the layout', (
      tester,
    ) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 59, bottom: 34), // notch + home bar
            viewInsets: EdgeInsets.only(bottom: 336), // keyboard
          ),
          child: MaterialApp(home: mobileScreen()),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the forged superAdmin sees only Moderation Center, Rooms & Spaces '
      'and Sanctions — no Users, no role management, no audit',
      (tester) async {
        useSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          MaterialApp(home: mobileScreen(caps: _forgedSuperAdminCaps)),
        );
        await settle(tester);

        expect(find.text('Moderation Center'), findsWidgets);
        expect(find.text('Rooms & Spaces'), findsWidgets);
        expect(find.text('Sanctions'), findsWidgets);
        expect(find.text('Users'), findsNothing);
        expect(find.text('Overview'), findsNothing);
        expect(find.text('Staff & Roles'), findsNothing);
        expect(find.text('Audit Log'), findsNothing);
      },
    );

    testWidgets('mobile search renders result cards with badges, and the '
        'drawer confirms actions with a required reason', (tester) async {
      useSize(tester, const Size(390, 844));
      final functions = _CountingFunctions();
      await tester.pumpWidget(
        MaterialApp(home: mobileScreen(functions: functions)),
      );
      await settle(tester);

      final usersTab = find.widgetWithText(ChoiceChip, 'Users');
      await tester.ensureVisible(usersTab);
      await tester.tap(usersTab);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'sieeema');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      // The mobile result card: name, role badge, separate VIP, status.
      expect(find.text('Sieeema'), findsWidgets);
      expect(find.text('USER'), findsWidgets);
      expect(find.text('VIP'), findsWidgets);
      expect(find.text('ACTIVE'), findsOneWidget);

      await tester.tap(find.text('View'));
      await settle(tester);
      // Full-height drawer takes the whole phone width.
      expect(find.text('User detail'), findsOneWidget);

      await tester.tap(find.text('Ban account'));
      await settle(tester);
      final confirm = find.widgetWithText(FilledButton, 'Ban');
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: 'no reason typed yet — confirm stays disabled',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'abuse',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
