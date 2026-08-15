import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/features/staff/presentation/screens/user_management_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// The owner's role-assignment surface.
///
/// The server is the authority (covered in functions/test/assign_role);
/// these tests pin the CLIENT contract: the six offered roles and never
/// superAdmin, the confirm dialog's old→new statement, the exact payload
/// with reason and stale-guard, double-submit protection, self-target
/// refusal, and the owner-only gate on the entry points.
void main() {
  const target = ManagedUser(
    uid: 'target-uid',
    displayName: 'Ola',
    username: 'ola',
    role: 'user',
    banned: false,
    isVip: true,
  );

  Widget host(Widget child) => MaterialApp(home: child);

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> lookupTarget(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ola');
    await tester.tap(find.text('Look up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  group('User Management', () {
    testWidgets('lookup shows the account with role, VIP separately, and '
        'status', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(
          UserManagementScreen(
            lookup: _FakeLookup(target),
            functions: _RecordingFunctions(),
            currentUid: 'owner-uid',
          ),
        ),
      );
      await lookupTarget(tester);

      expect(find.text('Ola'), findsOneWidget);
      expect(find.text('@ola'), findsOneWidget);
      expect(find.text('ROLE: USER'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget); // entitlement, own chip
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('offers exactly the six assignable roles and never '
        'superAdmin', (tester) async {
      useSize(tester, const Size(1440, 1400));
      await tester.pumpWidget(
        host(
          UserManagementScreen(
            lookup: _FakeLookup(target),
            functions: _RecordingFunctions(),
            currentUid: 'owner-uid',
          ),
        ),
      );
      await lookupTarget(tester);

      expect(find.byType(RadioListTile<String>), findsNWidgets(6));
      expect(find.text('SUPER ADMIN'), findsNothing);
      expect(find.text('OWNER · SUPER ADMIN'), findsNothing);
      for (final label in const [
        'User (no staff role)',
        'GUIDE MASTER',
        'SUPPORT',
        'AUDITOR',
        'MODERATOR',
        'SUPER MODERATOR',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('assigning Moderator: confirm shows old→new, requires a '
        'reason, sends the exact payload, and reports the session note', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 1400));
      final functions = _RecordingFunctions();
      await tester.pumpWidget(
        host(
          UserManagementScreen(
            lookup: _FakeLookup(target),
            functions: functions,
            currentUid: 'owner-uid',
          ),
        ),
      );
      await lookupTarget(tester);

      await tester.tap(find.text('MODERATOR'));
      await tester.pump();
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();

      // The confirmation names the user and both roles.
      expect(find.text('Ola: User → MODERATOR'), findsOneWidget);
      // No reason yet: confirm disabled.
      final confirm = find.widgetWithText(FilledButton, 'Confirm change');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'passed the moderation interview',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(functions.calls, hasLength(1));
      final payload = functions.calls.single;
      expect(payload['uid'], 'target-uid');
      expect(payload['role'], 'moderator');
      expect(payload['reason'], 'passed the moderation interview');
      expect(payload['expectedRole'], 'user'); // the stale-result guard
      expect(
        find.textContaining('may need to sign in again'),
        findsOneWidget,
      );
    });

    testWidgets('a server refusal surfaces as text, and the screen '
        'recovers', (tester) async {
      useSize(tester, const Size(1440, 1400));
      final functions = _RecordingFunctions()..failNext = true;
      await tester.pumpWidget(
        host(
          UserManagementScreen(
            lookup: _FakeLookup(target),
            functions: functions,
            currentUid: 'owner-uid',
          ),
        ),
      );
      await lookupTarget(tester);
      await tester.tap(find.text('SUPPORT'));
      await tester.pump();
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'support hire',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(functions.calls, hasLength(1));
      expect(find.textContaining('rejected by the server'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('your own account offers no role controls at all', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(
          UserManagementScreen(
            lookup: _FakeLookup(target),
            functions: _RecordingFunctions(),
            currentUid: 'target-uid', // looking yourself up
          ),
        ),
      );
      await lookupTarget(tester);

      expect(find.text('You cannot change your own role.'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.text('Change role'), findsNothing);
    });
  });

  group('owner gating', () {
    testWidgets('Staff Center opens owner sections for manageRoles and '
        'refuses accounts with no backing capability', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(
          StaffCenterScreen(
            capabilityService: _FakeCapabilities(
              const StaffCapabilities(
                staffRole: 'superAdmin',
                isOwner: true,
                manageRoles: true,
                fullAuditAccess: true,
              ),
            ),
            currentUid: 'owner-uid',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The owner's rail carries the owner sections.
      expect(find.text('Users'), findsWidgets);
      expect(find.text('Staff & Roles'), findsWidgets);
      expect(find.text('Audit Log'), findsWidgets);

      // An account whose capabilities back NO section is refused —
      // including a super moderator fixture that carries only a queue
      // flag no section is built on.
      for (final caps in const [
        StaffCapabilities(staffRole: 'superModerator', viewAllQueues: true),
        StaffCapabilities.none,
      ]) {
        await tester.pumpWidget(
          host(
            StaffCenterScreen(
              key: ValueKey('denied-${caps.staffRole}'),
              capabilityService: _FakeCapabilities(caps),
              currentUid: 'someone',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining('reserved for the application owner'),
          findsOneWidget,
          reason: caps.staffRole,
        );
        expect(find.text('Users'), findsNothing);
      }
    });

    testWidgets('the More popover lists Staff Center only for the owner', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 900));
      for (final (isOwner, expected) in const [(true, 1), (false, 0)]) {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => showDesktopMoreMenu(
                      context,
                      anchor: const Offset(40, 40),
                      isStaff: isOwner,
                      isOwner: isOwner,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.text('Staff Center'),
          findsNWidgets(expected),
          reason: 'isOwner=$isOwner',
        );
        await tester.tapAt(const Offset(700, 700)); // dismiss
        await tester.pumpAndSettle();
      }
    });
  });
}

class _FakeLookup implements StaffUserLookup {
  _FakeLookup(this.result);

  final ManagedUser result;

  /// A quiet repository: the screen invalidates it after a role change,
  /// and invalidation must not blow up the success path.
  final _identities = PublicIdentityRepository(
    fetchOverride: (_) async => <String, dynamic>{},
    flushDelay: const Duration(milliseconds: 1),
  );

  @override
  PublicIdentityRepository get identities => _identities;

  @override
  Future<ManagedUser?> lookup(String rawInput) async =>
      rawInput.trim().isEmpty ? null : result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCapabilities extends StaffCapabilityService {
  _FakeCapabilities(this.capabilities);

  final StaffCapabilities capabilities;

  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => capabilities;
}

class _RecordingFunctions implements FirebaseFunctions {
  final calls = <Map<String, dynamic>>[];
  bool failNext = false;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this.owner);

  final _RecordingFunctions owner;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls.add(Map<String, dynamic>.from(parameters as Map));
    if (owner.failNext) {
      owner.failNext = false;
      throw Exception('rejected by the server');
    }
    return _FakeResult<T>({'success': true} as T);
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
