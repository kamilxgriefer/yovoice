// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';

/// The client half of the capability model.
///
/// The server decides; these tests pin that the CLIENT renders exactly
/// what was decided — a shield for the tiers that hold room actions, the
/// right colour per tier, and byte-for-byte the ordinary UI for everyone
/// else. Authorization itself lives server-side and is covered by the
/// Functions suite.
void main() {
  VoiceRoom room({String id = 'r1', String name = 'Evening Talks'}) {
    final doc = _FakeDoc(id, {
      'hostId': 'host',
      'hostName': 'Host',
      'name': name,
      'description': 'Real talk',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 5,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
    });
    return VoiceRoom.fromFirestore(doc);
  }

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  const owner = StaffCapabilities(
    staffRole: 'superAdmin',
    isOwner: true,
    permanentDeleteSpaces: true,
    deleteAnyMessage: true,
    permanentBan: true,
    manageRoles: true,
    fullAuditAccess: true,
    viewAllQueues: true,
    quarantineSpaces: true,
    endAnyRoom: true,
    handleAssignedReports: true,
    removeReportedContent: true,
    warnUsers: true,
    endPublicRoomWithReason: true,
    suspendUsers: true,
  );

  const superMod = StaffCapabilities(
    staffRole: 'superModerator',
    permanentDeleteSpaces: true,
    viewAllQueues: true,
    quarantineSpaces: true,
    endAnyRoom: true,
    handleAssignedReports: true,
    removeReportedContent: true,
    warnUsers: true,
    endPublicRoomWithReason: true,
    suspendUsers: true,
    suspensionLimitHours: 720,
  );

  const moderator = StaffCapabilities(
    staffRole: 'moderator',
    handleAssignedReports: true,
    removeReportedContent: true,
    warnUsers: true,
    endPublicRoomWithReason: true,
    suspendUsers: true,
    suspensionLimitHours: 24,
  );

  group('shield per tier', () {
    testWidgets('the owner gets a crimson shield with permanent deletion', (
      tester,
    ) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(RoomStaffMenu(room: room(), capabilities: owner)),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.shield_rounded));
      expect(icon.color, RoleIdentity.ownerColor);

      await tester.tap(find.byIcon(Icons.shield_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Delete permanently…'), findsOneWidget);
      expect(find.text('End room…'), findsOneWidget);
      expect(find.text('Quarantine…'), findsOneWidget);
    });

    testWidgets('a super moderator gets coral, close/quarantine and '
        'permanent room deletion', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(RoomStaffMenu(room: room(), capabilities: superMod)),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.shield_rounded));
      expect(icon.color, RoleIdentity.superModeratorColor);

      await tester.tap(find.byIcon(Icons.shield_rounded));
      await tester.pumpAndSettle();
      expect(find.text('End room…'), findsOneWidget);
      expect(find.text('Quarantine…'), findsOneWidget);
      expect(find.text('Delete permanently…'), findsOneWidget);
    });

    testWidgets('a moderator gets violet and ONLY the end-public-room '
        'action', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(RoomStaffMenu(room: room(), capabilities: moderator)),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.shield_rounded));
      expect(icon.color, RoleIdentity.moderatorColor);

      await tester.tap(find.byIcon(Icons.shield_rounded));
      await tester.pumpAndSettle();
      expect(find.text('End public room…'), findsOneWidget);
      expect(find.text('Quarantine…'), findsNothing);
      expect(find.text('Delete permanently…'), findsNothing);
    });

    testWidgets('auditor, support, guideMaster, VIP and user get NO shield '
        'at all', (tester) async {
      useSize(tester, const Size(1440, 900));
      const nonRoomRoles = [
        StaffCapabilities(staffRole: 'auditor', readAuditLogs: true),
        StaffCapabilities(staffRole: 'support', supportLookup: true),
        StaffCapabilities(staffRole: 'guideMaster', guideMode: true),
        StaffCapabilities(staffRole: 'user', isVip: true),
        StaffCapabilities.none,
      ];
      for (final caps in nonRoomRoles) {
        await tester.pumpWidget(
          host(RoomStaffMenu(room: room(), capabilities: caps)),
        );
        expect(
          find.byIcon(Icons.shield_rounded),
          findsNothing,
          reason: '${caps.staffRole} must render nothing',
        );
      }
    });
  });

  group('banner integration', () {
    testWidgets('a regular host can manage and delete only their own room '
        'from the phone banner', (tester) async {
      useSize(tester, const Size(390, 844));
      var managed = 0;
      var deleted = 0;
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: room(),
              onJoin: (_) {},
              compact: true,
              currentUserId: 'host',
              onManageOwnedRoom: () => managed++,
              onDeleteOwnedRoom: () async => deleted++,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      expect(find.text('Room settings'), findsOneWidget);
      expect(find.text('Delete room…'), findsOneWidget);

      await tester.tap(find.text('Room settings'));
      await tester.pumpAndSettle();
      expect(managed, 1);

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete room…'));
      await tester.pumpAndSettle();
      // Simple destructive confirm: the room's name in the title, the
      // irreversibility statement, no typed-name hurdle.
      expect(find.text('Delete "Evening Talks"?'), findsOneWidget);
      expect(find.textContaining('This cannot be undone'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, 1);

      await tester.pumpWidget(
        host(
          HomeRoomBanner(
            room: room(),
            onJoin: (_) {},
            compact: true,
            currentUserId: 'someone-else',
            onManageOwnedRoom: () {},
            onDeleteOwnedRoom: () async {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Manage your room'), findsNothing);
    });

    testWidgets('an ordinary account\'s banner is unchanged — no shield, '
        'no gaps', (tester) async {
      useSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        host(HomeRoomBanner(room: room(), onJoin: (_) {})),
      );
      await tester.pump();
      expect(find.byIcon(Icons.shield_rounded), findsNothing);
      expect(find.byType(RoomStaffMenu), findsNothing);

      // With explicit none-capabilities: byte-for-byte the same.
      await tester.pumpWidget(
        host(
          HomeRoomBanner(
            room: room(),
            onJoin: (_) {},
            staffCapabilities: StaffCapabilities.none,
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.shield_rounded), findsNothing);
    });

    testWidgets('a staff banner shows the shield without disturbing the '
        'layout, desktop and mobile', (tester) async {
      for (final size in const [Size(1440, 900), Size(390, 844)]) {
        useSize(tester, size);
        await tester.pumpWidget(
          host(
            SingleChildScrollView(
              child: HomeRoomBanner(
                room: room(),
                onJoin: (_) {},
                compact: size.width < 500,
                staffCapabilities: superMod,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(RoomStaffMenu), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size overflowed');
      }
    });
  });

  group('owner permanent-delete dialog', () {
    testWidgets('requires a reason AND the exact name, protects against '
        'double submission, and surfaces errors', (tester) async {
      useSize(tester, const Size(1440, 900));
      final functions = _RecordingFunctions();
      await tester.pumpWidget(
        host(OwnerDeleteRoomDialog(room: room(), functions: functions)),
      );
      await tester.pump();

      final deleteButton = find.byType(FilledButton);

      // Nothing filled: disabled.
      expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

      // Reason but WRONG name: still disabled.
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (required)'),
        'spam room',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Type the room name to confirm'),
        'Evening Talk', // one letter short
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

      // Exact name: enabled. First call fails — the dialog stays, the
      // error shows, and the button re-enables for a retry.
      functions.failNext = true;
      await tester.enterText(
        find.widgetWithText(TextField, 'Type the room name to confirm'),
        'Evening Talks',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);

      await tester.tap(deleteButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(functions.calls, hasLength(1));
      expect(
        find.text('Could not permanently delete the room. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('rejected'), findsNothing);
      expect(find.byType(OwnerDeleteRoomDialog), findsOneWidget);

      // Retry succeeds; the payload carries the id contract and the
      // reason; exactly one more call — no double submission.
      await tester.tap(deleteButton);
      await tester.pump();
      // While busy the button is disabled, so a second tap cannot fire.
      await tester.tap(deleteButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(functions.calls, hasLength(2));
      expect(functions.calls.last['roomId'], 'r1');
      expect(functions.calls.last['confirmation'], 'r1');
      expect(functions.calls.last['reason'], 'spam room');
    });
  });

  group('role identity', () {
    test('the owner label outranks SUPER ADMIN and every tier has its '
        'colour', () {
      expect(
        RoleIdentity.labelFor('superAdmin', isOwner: true),
        'OWNER · SUPER ADMIN',
      );
      expect(RoleIdentity.labelFor('superAdmin'), 'SUPER ADMIN');
      expect(
        RoleIdentity.colorFor('superAdmin', isOwner: true),
        RoleIdentity.ownerColor,
      );
      expect(
        RoleIdentity.colorFor('superModerator'),
        RoleIdentity.superModeratorColor,
      );
      expect(RoleIdentity.colorFor('moderator'), RoleIdentity.moderatorColor);
      expect(RoleIdentity.colorFor('auditor'), RoleIdentity.auditorColor);
      expect(RoleIdentity.colorFor('support'), RoleIdentity.supportColor);
      expect(
        RoleIdentity.colorFor('guideMaster'),
        RoleIdentity.guideMasterColor,
      );
      expect(RoleIdentity.labelFor('user'), '');
    });

    test('capabilities parse defensively from a server map', () {
      final caps = StaffCapabilities.fromMap({
        'staffRole': 'moderator',
        'endPublicRoomWithReason': true,
        'suspensionLimitHours': 24,
        'permanentDeleteSpaces': 'yes', // not a bool: refused
      });
      expect(caps.staffRole, 'moderator');
      expect(caps.endPublicRoomWithReason, true);
      expect(caps.suspensionLimitHours, 24);
      expect(caps.permanentDeleteSpaces, false);
      expect(StaffCapabilities.fromMap(const {}).hasRoomModeration, false);
    });
  });
}

/// Minimal DocumentSnapshot stand-in for building a VoiceRoom fixture.
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records callable payloads; optionally fails the next call. The dialog
/// only uses `httpsCallable(...).call(...)`, so everything else is
/// noSuchMethod.
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
    return _FakeResult<T>({'ok': true} as T);
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
