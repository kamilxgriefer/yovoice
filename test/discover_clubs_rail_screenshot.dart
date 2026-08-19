// Developer-only VISUAL harness for Home's "Discover clubs" rail.
//
// Same reason as test/desktop_screenshot.dart: layout and state claims are
// proven from the widget layer with real widgets, real fonts and an exact
// viewport, because the screen that hosts this rail cannot currently be
// reached in the running app (MainShell renders MobileHome/DesktopHome in
// slot 0, not HomeScreen).
//
// NOT a test; the name has no `_test` suffix so `flutter test` skips it.
// Run explicitly:
//
//   flutter test test/discover_clubs_rail_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/discover_clubs_rail.dart';

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

Club _club(String id, String name, int memberCount) => Club(
  id: id,
  name: name,
  description: 'A club',
  ownerId: 'owner',
  ownerName: 'Owner',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.public,
  defaultLanguage: 'English',
  memberCount: memberCount,
  onlineCount: 0,
  defaultChatChannelId: 'chat',
  defaultVoiceChannelId: 'voice',
  announcementChannelId: 'announcements',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  setUpAll(_loadRealFonts);

  final populated = <Club>[
    _club('a', 'Night Owls', 128),
    _club('b', 'Morning Coffee', 42),
    _club('c', 'Producers Lounge', 17),
    _club(
      'd',
      'The Extremely Long Late Night Voice Club For People Who Cannot Sleep',
      1,
    ),
    _club('e', 'Language Exchange', 310),
  ];

  final states = <String, AsyncSnapshot<List<Club>>>{
    'loading': const AsyncSnapshot<List<Club>>.waiting(),
    'error': AsyncSnapshot<List<Club>>.withError(
      ConnectionState.active,
      Exception('permission-denied'),
    ),
    'empty': const AsyncSnapshot<List<Club>>.withData(
      ConnectionState.active,
      <Club>[],
    ),
    'populated': AsyncSnapshot<List<Club>>.withData(
      ConnectionState.active,
      populated,
    ),
  };

  final sizes = <String, Size>{
    'narrow': const Size(390, 420),
    'medium': const Size(834, 640),
    'wide': const Size(1280, 640),
  };

  for (final size in sizes.entries) {
    for (final state in states.entries) {
      for (final scale in const <double>[1, 2]) {
        testWidgets('${size.key} ${state.key} x$scale', (tester) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            RepaintBoundary(
              key: _capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  brightness: Brightness.dark,
                  useMaterial3: true,
                  fontFamily: 'Roboto',
                ),
                home: Scaffold(
                  backgroundColor: const Color(0xFF080711),
                  body: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: SingleChildScrollView(
                        child: DiscoverClubsRail(
                          snapshot: state.value,
                          onOpenClub: (_) {},
                          onRetry: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 120));

          await _shoot(
            tester,
            'discover_clubs_${size.key}_${state.key}_x${scale.toInt()}',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
