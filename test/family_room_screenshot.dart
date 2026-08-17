// Developer-only visual QA harness for the Family Room selector and form.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/family_room_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';

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

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: RepaintBoundary(key: _capture, child: child),
);

ClubService _familyService() {
  final firestore = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: 'family-preview',
      email: 'family-preview@yovoice.app',
      displayName: 'Family Organizer',
    ),
  );
  return ClubService(
    firestore: firestore,
    auth: auth,
    storage: MockFirebaseStorage(),
    notificationService: NotificationService(firestore: firestore, auth: auth),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

void main() {
  setUpAll(_loadFonts);

  for (final viewport in const [
    (320.0, 844.0),
    (390.0, 844.0),
    (768.0, 1024.0),
    (1100.0, 800.0),
  ]) {
    testWidgets('Family selector ${viewport.$1.toInt()}px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport.$1, viewport.$2);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const RoomTypeSelectorScreen()));
      await _settle(tester);
      await tester.ensureVisible(find.text('Family Room'));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      await _shoot(
        tester,
        'family-selector-${viewport.$1.toInt()}x${viewport.$2.toInt()}',
      );
    });

    testWidgets('Family create form ${viewport.$1.toInt()}px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport.$1, viewport.$2);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          CreateClubScreen(
            type: ClubType.family,
            clubService: _familyService(),
          ),
        ),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      await _shoot(
        tester,
        'family-create-${viewport.$1.toInt()}x${viewport.$2.toInt()}',
      );
    });
  }
}
