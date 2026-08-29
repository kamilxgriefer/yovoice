// Developer-only VISUAL harness for the exact production Voice identity card.
//
// NOT a normal test; run explicitly:
//
//   flutter test test/profile_vibe_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';

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
  Future<ByteData> readMaterialFont(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.view(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync().buffer,
        ),
      ),
    )
    ..addFont(
      Future.value(
        ByteData.view(
          File(
            'assets/fonts/InterVariable-Italic.ttf',
          ).readAsBytesSync().buffer,
        ),
      ),
    );
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(readMaterialFont('MaterialIcons-Regular.otf'));
  await icons.load();
}

UserProfile _profile() => UserProfile(
  uid: 'vibe-preview',
  email: 'vibe@yovoice.app',
  displayName: 'CeoGriefer',
  username: 'ceogriefer',
  statusMessage:
      'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4?si=YOvoice',
  bio: 'CEO.',
  country: 'Poland',
  nativeLanguage: 'Polish',
  spokenLanguages: const ['English'],
  learningLanguages: const ['Japanese'],
  photoUrl: null,
  bannerUrl: null,
  website: 'yovoice.app',
  accountType: AccountType.creator,
  friendCount: 2,
  followerCount: 2,
  followingCount: 2,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

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

Future<void> _pump(WidgetTester tester, {required ThemeData theme}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: ProfileVoiceIdentityCard(profile: _profile()),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(_loadRealFonts);

  for (final theme in <(String, ThemeData)>[
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets(
        'voice-identity-${theme.$1}-${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await _pump(tester, theme: theme.$2);
          await _shoot(
            tester,
            'profile-voice-identity-${theme.$1}-${size.width.toInt()}',
          );
        },
      );
    }

    testWidgets('voice-identity-${theme.$1}-320-scale2', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _pump(tester, theme: theme.$2);
      await _shoot(tester, 'profile-voice-identity-${theme.$1}-320-scale2');
    });
  }
}
