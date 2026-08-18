// Developer-only VISUAL harness for the compact profile header.
//
// Same reason as test/desktop_screenshot.dart: the in-app browser cannot
// rasterise Flutter's CanvasKit output, so layout claims are proven from
// the widget layer instead — real widgets, real fonts, exact viewport.
//
// NOT a test; the name has no `_test` suffix so `flutter test` skips it.
// Run explicitly:
//
//   flutter test test/profile_header_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

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
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

UserProfile _profile() => UserProfile(
  uid: 'preview',
  email: 'ada@yovoice.app',
  displayName: 'Ada Lovelace',
  username: 'ada',
  bio: 'Hosting late-night rooms about synths, space and stories.',
  country: 'Poland',
  nativeLanguage: 'Polish',
  spokenLanguages: const ['Polish', 'English'],
  learningLanguages: const ['Spanish'],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.creator,
  premiumIdentity: true,
  friendCount: 12,
  followerCount: 340,
  followingCount: 51,
  roomCount: 4,
  communityCount: 2,
  voiceMinutes: 1240,
  messageCount: 210,
  activeDays: 33,
  momentCount: 9,
  reactionCount: 87,
  hostMinutes: 300,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

/// A stand-in for the content panels below the header, so alignment of
/// the toolbar/banner against the page gutter is visible in the shots.
Widget _contentPanel() => Padding(
  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
  child: Container(
    height: 110,
    decoration: BoxDecoration(
      color: const Color(0xFF17101F),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF3C2C45)),
    ),
    alignment: Alignment.center,
    child: const Text(
      'content panel',
      style: TextStyle(color: Color(0xFFA99DB3)),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
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

Future<void> _pump(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF09050F),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              children: [
                ProfileHeader(profile: _profile(), onEdit: () {}),
                _contentPanel(),
                _contentPanel(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(_loadRealFonts);

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(768, 1024),
    Size(1100, 800),
    Size(1440, 900),
  ]) {
    testWidgets('header-${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester);
      await _shoot(tester, 'profile-header-${size.width.toInt()}');
    });
  }

  testWidgets('header-390-scale2', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _pump(tester);
    await _shoot(tester, 'profile-header-390-scale2');
  });
}
