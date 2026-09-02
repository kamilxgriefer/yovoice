// Developer-only visual QA harness for the club-lounge delete flow.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/club_delete_dialog_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
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
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

/// The RepaintBoundary wraps the WHOLE MaterialApp (not just `home`) so
/// the dialog overlay is inside the captured tree.
Widget _host(Widget child) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(backgroundColor: const Color(0xFF080711), body: child),
  ),
);

VoiceRoom _lounge() => const VoiceRoom(
  id: 'club_lounge_family',
  hostId: 'me',
  hostName: 'Kamil',
  hostPhotoUrl: null,
  name: 'family Lounge',
  description: 'Private voice lounge for family members.',
  category: 'club',
  visibility: 'private',
  language: 'English',
  maxParticipants: null,
  participantCount: 2,
  memberCount: 4,
  isLive: false,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  clubId: 'family',
  storedClubId: 'family',
);

Future<ClubService> _ownerClubService({Object? failure}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('clubs').doc('family').set({
    'name': 'family',
    'description': 'The family club.',
    'ownerId': 'me',
    'ownerName': 'Kamil',
    'privacy': 'inviteOnly',
    'type': 'family',
    'status': 'active',
    'defaultLanguage': 'English',
    'memberCount': 4,
    'onlineCount': 1,
    'defaultChatChannelId': 'chat',
    'defaultVoiceChannelId': 'voice',
    'announcementChannelId': 'announce',
  });
  return ClubService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
    ),
    storage: MockFirebaseStorage(),
    functions: _StubFunctions(failure: failure),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _openClubDeleteDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byTooltip('Manage your room'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete club…'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  for (final viewport in const [(390.0, 844.0), (1440.0, 900.0)]) {
    final width = viewport.$1.toInt();
    testWidgets('club delete dialog $width px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport.$1, viewport.$2);
      addTearDown(tester.view.reset);

      final clubs = await _ownerClubService();
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HomeRoomBanner(
              room: _lounge(),
              onJoin: (_) {},
              compact: viewport.$1 < 700,
              currentUserId: 'me',
              clubService: clubs,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async {},
            ),
          ),
        ),
      );
      await _openClubDeleteDialog(tester);
      expect(find.text('Delete the Club "family"?'), findsOneWidget);
      await _shoot(tester, 'club_delete_dialog_$width');
    });
  }

  testWidgets('club delete dialog 390 px — server refusal shown in place', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final clubs = await _ownerClubService(
      failure: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'This Club is already being deleted.',
      ),
    );
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: HomeRoomBanner(
            room: _lounge(),
            onJoin: (_) {},
            compact: true,
            currentUserId: 'me',
            clubService: clubs,
            onManageOwnedRoom: () {},
            onDeleteOwnedRoom: () async {},
          ),
        ),
      ),
    );
    await _openClubDeleteDialog(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already being deleted'), findsOneWidget);
    await _shoot(tester, 'club_delete_dialog_390_error');
  });
}

class _StubFunctions implements FirebaseFunctions {
  _StubFunctions({this.failure});

  final Object? failure;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _StubCallable(failure);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubCallable implements HttpsCallable {
  _StubCallable(this.failure);

  final Object? failure;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    if (failure != null) throw failure!;
    return _StubResult<T>(
      <Object?, Object?>{'success': true, 'clubId': 'family'} as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubResult<T> implements HttpsCallableResult<T> {
  _StubResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
