// Developer-only VISUAL capture for the whole Servers slice: the template
// selector, the configuration form, the servers shell (root tab) and all five
// templates, across the full acceptance matrix of contract §4.3 —
// 320 / 390 / 768 / 1100 / 1440 / 1920, Dark and Pearl, 1x and 2x text.
//
// Not a golden test: platform font rasterisation is not stable enough for a
// pixel baseline. This renders the real widgets with the real product font and
// writes PNGs so the Senior Visual Quality Specialist can LOOK at what the code
// actually draws. Run explicitly:
//
//   flutter test test/server_visual_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-09-12/servers-frames/.
// Layout exceptions (overflow) are captured into _exceptions.log next to the
// frames rather than failing the run — an overflow is a finding to look at, and
// the frame that shows it is the evidence.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_template_selector.dart';

import 'server_community_test.dart' as community;
import 'server_company_test.dart' as company;
import 'server_podcast_test.dart' as podcast;
import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';

const _outputDirectory =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-12/servers-frames';

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

/// Real text and real glyphs. Inter is the product face and lives in the
/// repository; Roboto and the icon face come from the Flutter cache.
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

/// The acceptance widths and a realistic viewport height for each, so a frame
/// shows what a person would actually see — including what falls below the
/// fold — rather than an artificially tall canvas that hides every clip.
const _viewports = <(double, double)>[
  (320, 568),
  (390, 844),
  (768, 1024),
  (1100, 800),
  (1440, 900),
  (1920, 1080),
];

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  ThemeData? theme,
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
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
  try {
    await tester.pumpAndSettle();
  } on Object {
    // A scene that never settles still has to be looked at.
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
  // Record, do not rethrow: an overflow is the finding, and the frame that
  // shows it is the evidence. Failing here would destroy the evidence.
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
    // Narrow frames are captured at 2x so small type stays readable; wide ones
    // at 1x, because a 3840 px PNG is downsampled before anybody sees it.
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

final _live = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 12, 19, 40),
);

final _meetingLive = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 12, 19, 40),
);

/// The eight surfaces, each built fresh per frame.
final _surfaces = <String, Widget Function()>{
  'selector': () => Scaffold(body: ServerTemplateSelector(onSelected: (_) {})),
  'configuration': () => CreateServerScreen(
    key: UniqueKey(),
    repository: TestServerRepository(),
    initialType: ServerType.friends,
    isRootTab: true,
  ),
  'shell': () => ServersScreen(
    key: UniqueKey(),
    isRootTab: true,
    repository: TestServerRepository()
      ..servers = [
        boards.boardServer(ServerType.friends, members: 12),
        boards.boardServer(ServerType.family),
      ],
    chatService: boards.boardChat(),
    connector: FakeServerMediaConnector(),
  ),
  'friends': () => ServerWorkspaceScreen(
    key: UniqueKey(),
    serverId: 's',
    repository: TestServerRepository()
      ..servers = [boards.boardServer(ServerType.friends, members: 12)]
      ..channels = boards.boardChannels(ServerType.friends),
    isRootTab: true,
    initialChannelId: 'lounge',
    chatService: boards.boardChat(),
    connector: FakeServerMediaConnector(),
  ),
  'community': () => community.communityWorkspace(
    TestServerRepository()
      ..servers = [community.communityServer()]
      ..channels = community.communityChannels(stage: _live),
  ),
  'podcast': () => podcast.podcastWorkspace(
    TestServerRepository()
      ..servers = [podcast.podcastServer()]
      ..channels = podcast.podcastChannels(studio: podcast.live),
  ),
  'family': () => ServerWorkspaceScreen(
    key: UniqueKey(),
    serverId: 's',
    repository: TestServerRepository()
      ..servers = [boards.boardServer(ServerType.family)]
      ..channels = boards.boardChannels(ServerType.family),
    isRootTab: true,
    chatService: boards.boardChat(),
    connector: FakeServerMediaConnector(),
  ),
  'company': () => company.companyWorkspace(
    TestServerRepository()
      ..servers = [company.companyServer()]
      ..channels = company.companyChannels(meeting: _meetingLive),
  ),
};

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  for (final entry in _surfaces.entries) {
    for (final (width, height) in _viewports) {
      for (final (themeLabel, light) in const [('dark', false), ('pearl', true)]) {
        for (final scale in const [1.0, 2.0]) {
          final name =
              '${entry.key}-${width.toInt()}x${height.toInt()}'
              '-$themeLabel-${scale.toInt()}x';
          testWidgets(name, (tester) async {
            final captureKey = GlobalKey();
            await _render(
              tester,
              captureKey: captureKey,
              size: Size(width, height),
              textScale: scale,
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              child: entry.value(),
            );
            await _shoot(
              tester,
              captureKey: captureKey,
              name: name,
              width: width,
            );
          });
        }
      }
    }

    // One English frame per surface, so the localized copy convention is on
    // the record beside the Polish boards.
    testWidgets('${entry.key}-1440x900-dark-1x-en', (tester) async {
      final captureKey = GlobalKey();
      await _render(
        tester,
        captureKey: captureKey,
        size: const Size(1440, 900),
        locale: const Locale('en'),
        child: entry.value(),
      );
      await _shoot(
        tester,
        captureKey: captureKey,
        name: '${entry.key}-1440x900-dark-1x-en',
        width: 1440,
      );
    });
  }
}
