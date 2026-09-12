// Developer-only VISUAL capture for the FRIENDS (board 01) and FAMILY
// (board 03) templates on the server shell.
//
// Not a golden test: platform font rasterisation is not stable enough for a
// pixel baseline, which is why `dock_visual_qa_screenshot.dart` established
// this harness instead. It renders the real widgets at the shipping widths
// and writes PNGs so a human — and the Senior Visual Quality Specialist —
// can look at what the code actually draws. Run explicitly:
//
//   flutter test test/server_templates_capture.dart
//
// PNGs land in yovoice-evidence/2026-09-12/ff-frames/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';

const _outputDirectory =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-12/ff-frames';

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

ByteData _read(String path) =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

/// Real text and real glyphs. Inter is the product face and lives in the
/// repository, so it is loaded from there; Roboto and the icon face come
/// from the Flutter cache exactly as the dock harness loads them.
Future<void> _loadRealFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(Future.value(_read('assets/fonts/InterVariable.ttf')));
  await inter.load();

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(Future.value(_read('$_fontRoot/$face')));
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(_read('$_fontRoot/MaterialIcons-Regular.otf')));
  await icons.load();
}

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        theme: theme ?? AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
}) async {
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDirectory/$name.png');
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
  setUpAll(_loadRealFonts);

  for (final (label, size, scale, light)
      in <(String, Size, double, bool)>[
        ('390x844', Size(390, 844), 1, false),
        ('768x1024', Size(768, 1024), 1, false),
        ('1440x900', Size(1440, 900), 1, false),
        ('320x760-scale2', Size(320, 760), 2, false),
        ('1440x900-pearl', Size(1440, 900), 1, true),
      ]) {
    testWidgets('friends salon $label', (tester) async {
      final captureKey = GlobalKey();
      await _render(
        tester,
        captureKey: captureKey,
        size: size,
        textScale: scale,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        child: ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boards.boardServer(ServerType.friends, members: 12)]
            ..channels = boards.boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boards.boardChat(),
          connector: FakeServerMediaConnector(),
        ),
      );
      await _shoot(tester, captureKey: captureKey, name: 'friends-salon-$label');
    });

    testWidgets('family board $label', (tester) async {
      final captureKey = GlobalKey();
      await _render(
        tester,
        captureKey: captureKey,
        size: size,
        textScale: scale,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        child: ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boards.boardServer(ServerType.family)]
            ..channels = boards.boardChannels(ServerType.family),
          isRootTab: true,
          chatService: boards.boardChat(),
          connector: FakeServerMediaConnector(),
        ),
      );
      await _shoot(tester, captureKey: captureKey, name: 'family-board-$label');
    });
  }

  for (final (label, size) in <(String, Size)>[
    ('390x844', Size(390, 844)),
    ('1440x900', Size(1440, 900)),
  ]) {
    testWidgets('friends salon in session $label', (tester) async {
      final captureKey = GlobalKey();
      final connector = FakeServerMediaConnector();
      await _render(
        tester,
        captureKey: captureKey,
        size: size,
        child: ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boards.boardServer(ServerType.friends, members: 12)]
            ..channels = boards.boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boards.boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('server-join')));
      await tester.pumpAndSettle();
      connector.links.single.setRoster(boards.foursome);
      await tester.pumpAndSettle();
      await _shoot(
        tester,
        captureKey: captureKey,
        name: 'friends-salon-in-session-$label',
      );
    });

    testWidgets('family lounge in session $label', (tester) async {
      final captureKey = GlobalKey();
      final connector = FakeServerMediaConnector();
      await _render(
        tester,
        captureKey: captureKey,
        size: size,
        child: ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boards.boardServer(ServerType.family)]
            ..channels = boards.boardChannels(ServerType.family),
          isRootTab: true,
          chatService: boards.boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('server-join')));
      await tester.pumpAndSettle();
      connector.links.single.setRoster(boards.foursome.take(3).toList());
      await tester.pumpAndSettle();
      await _shoot(
        tester,
        captureKey: captureKey,
        name: 'family-lounge-in-session-$label',
      );
    });
  }
}
