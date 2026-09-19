// Developer-only VISUAL capture for Slim redesign phase 2 (Serwery): the
// directory as a compact list, the workspace with its server rail on a
// desktop and on a phone (the `Kanały` sheet), Dark and Pearl, pl, populated.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/slim_servers_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-09-19/slim-2-servers-frames/after/.
// Layout exceptions are recorded in _exceptions.log next to the frames.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';

const _outputDirectory =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-19/'
    'slim-2-servers-frames/after';

final _exceptions = File('$_outputDirectory/_exceptions.log');

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

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  String description = '',
}) => Server(
  id: id,
  name: name,
  description: description,
  ownerId: 'owner',
  type: type,
  privacy: ServerPrivacy.private,
  memberCount: members,
  defaultChannelId: null,
  schemaVersion: 1,
  activationState: 'active',
  status: 'active',
);

/// The account's servers: the open one first (id `s`, which the board
/// channels belong to) and four more for the rail and the directory.
List<Server> _servers() => [
  boards.boardServer(ServerType.friends, members: 12),
  _server(
    'k',
    'Klub książki',
    ServerType.community,
    members: 184,
    description: 'Co miesiąc jedna książka i jedna długa rozmowa o niej.',
  ),
  _server('r', 'Rodzina Nowaków', ServerType.family, members: 6),
  _server('p', 'Nocne audycje', ServerType.podcast, members: 42),
  _server('f', 'Studio Północ', ServerType.company, members: 23),
];

final _surfaces = <String, Widget Function()>{
  'directory': () => ServersScreen(
    key: UniqueKey(),
    isRootTab: true,
    repository: TestServerRepository()..servers = _servers(),
    chatService: boards.boardChat(),
    connector: FakeServerMediaConnector(),
  ),
  'workspace': () => ServerWorkspaceScreen(
    key: UniqueKey(),
    serverId: 's',
    repository: TestServerRepository()
      ..servers = _servers()
      ..channels = boards.boardChannels(
        ServerType.friends,
        liveness: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 19, 19, 40),
        ),
      ),
    isRootTab: true,
    initialChannelId: 'lounge',
    chatService: boards.boardChat(),
    connector: FakeServerMediaConnector(),
  ),
};

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  required ThemeData theme,
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
        theme: theme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: size, disableAnimations: true),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle();
  } on Object {
    for (var pump = 0; pump < 6; pump++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
}

Future<void> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
  required double width,
}) async {
  final failure = tester.takeException();
  if (failure != null) {
    final headline = failure.toString().split('\n').take(2).join(' | ');
    _exceptions.writeAsStringSync(
      '$name :: $headline\n',
      mode: FileMode.append,
    );
  }
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: width <= 768 ? 2 : 1);
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
  setUpAll(() async {
    await _loadRealFonts();
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  for (final entry in _surfaces.entries) {
    for (final (width, height) in const [
      (390.0, 844.0),
      (768.0, 1024.0),
      (1440.0, 900.0),
    ]) {
      for (final (themeLabel, light) in const [
        ('dark', false),
        ('pearl', true),
      ]) {
        final name =
            '${entry.key}-${width.toInt()}x${height.toInt()}-$themeLabel-1x-pl';
        testWidgets(name, (tester) async {
          final captureKey = GlobalKey();
          await _render(
            tester,
            captureKey: captureKey,
            size: Size(width, height),
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            child: entry.value(),
          );
          await _shoot(
            tester,
            captureKey: captureKey,
            name: name,
            width: width,
          );
          // The phone's server rail lives in the `Kanały` sheet.
          if (entry.key == 'workspace' && width < 768) {
            await tester.tap(
              find.byKey(const ValueKey('server-open-channels')),
            );
            await _settle(tester);
            await _shoot(
              tester,
              captureKey: captureKey,
              name:
                  'workspace-channels-sheet-'
                  '${width.toInt()}x${height.toInt()}-$themeLabel-1x-pl',
              width: width,
            );
          }
        });
      }
    }
  }
}
