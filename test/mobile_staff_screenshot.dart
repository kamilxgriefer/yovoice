// Renders the MOBILE staff surfaces at 390x844 with real fonts and
// writes PNGs to test/.screenshots/ so the "look at it" step of the
// mobile-parity milestone is an actual look:
//
//   mobile_more_owner            owner's More sheet (crimson Staff Center)
//   mobile_more_moderator        moderator's sheet (violet Moderation Center)
//   mobile_staff_center_owner    Staff Center tabs as the owner
//   mobile_staff_center_moderator  the moderation tier's three sections
//
//   flutter test test/mobile_staff_screenshot.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_audit_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/data/staff_directory_service.dart';
import 'package:yovoice/features/staff/data/staff_overview_service.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const String _fontRoot =
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts';

final _capture = GlobalKey();

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
}

const _ownerCaps = StaffCapabilities(
  staffRole: 'superAdmin',
  isOwner: true,
  isVip: true,
  manageRoles: true,
  fullAuditAccess: true,
  handleAssignedReports: true,
  warnUsers: true,
  suspendUsers: true,
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

class _FakeDirectory implements StaffDirectoryService {
  @override
  Future<DirectorySearchPage> search({
    String query = '',
    String filter = 'all',
    String? cursor,
  }) async => DirectorySearchPage(
    users: [
      DirectoryUser(
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
      ),
    ],
    nextCursor: null,
    mode: 'browse',
  );
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
      'activeRooms': 4,
      'openReports': 0,
      'restrictedAccounts': 0,
      'staffMembers': 1,
      'vipUsers': 1,
      'securityAlerts': 0,
    },
    'latestOpenReports': <Map<String, dynamic>>[],
    'activeRooms': [
      {'id': 'r1', 'name': 'Cosmic Lounge', 'participantCount': 9},
    ],
    'recentSanctions': <Map<String, dynamic>>[],
    'recentRoleChanges': <Map<String, dynamic>>[],
    'securityAlerts': <Map<String, dynamic>>[],
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('test/.screenshots/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path}');
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Roboto',
  ),
  home: home,
);

void main() {
  setUpAll(_loadRealFonts);

  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer'),
      ),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          if (uid == 'owner-uid')
            uid: {'staffRole': 'superAdmin', 'isVip': true}
          else if (uid == 'mod-uid')
            uid: {'staffRole': 'moderator', 'isVip': false}
          else if (uid == 'sieeema-uid')
            uid: {'staffRole': 'user', 'isVip': true},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  for (final (name, caps, uid) in [
    ('mobile_more_owner', _ownerCaps, 'owner-uid'),
    ('mobile_more_moderator', _modCaps, 'mod-uid'),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: _app(
            Scaffold(
              backgroundColor: const Color(0xFF0D0618),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  child: MoreSheet(
                    capabilityService: _FakeCapabilities(caps),
                    currentUid: uid,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, name);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, caps, uid) in [
    ('mobile_staff_center_owner', _ownerCaps, 'owner-uid'),
    ('mobile_staff_center_moderator', _modCaps, 'mod-uid'),
  ]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: _app(
            StaffCenterScreen(
              capabilityService: _FakeCapabilities(caps),
              directoryService: _FakeDirectory(),
              overviewService: _FakeOverview(),
              auditService: _FakeAudit(),
              moderationService: ModerationService(firestore: db, auth: auth),
              roomService: RoomService(firestore: db, auth: auth),
              firestore: db,
              currentUid: uid,
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, name);
      expect(tester.takeException(), isNull);
    });
  }
}
