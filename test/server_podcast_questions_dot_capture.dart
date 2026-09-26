// Developer-only VISUAL capture for the podcast host's "new listener
// questions" dot.
//
// Not a golden test (see server_podcast_capture.dart for why): it renders the
// real widgets with the real Inter face through the fake repository and
// writes PNGs so a human can look at what the code draws. It is not a device
// or simulator frame. Run explicitly:
//
//   YOVOICE_CAPTURE_DIR=<evidence dir> flutter test test/server_podcast_questions_dot_capture.dart
//
// PNGs land in $YOVOICE_CAPTURE_DIR as questions-dot-*; without it every
// capture is skipped.

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
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_podcast_test.dart' as board;
import 'server_test_support.dart';

/// Where the PNGs go. Nothing is written, and every capture is skipped, unless
/// the person running it names a directory outside the repository:
///
/// `YOVOICE_CAPTURE_DIR=/path/to/evidence flutter test` on this file.
final String? _outputDirectory = () {
  final value = Platform.environment['YOVOICE_CAPTURE_DIR']?.trim();
  return value == null || value.isEmpty ? null : value;
}();

/// The Flutter SDK's own Material fonts, found from `FLUTTER_ROOT` or the two
/// usual Homebrew locations; null (and the captures skipped) when none has
/// them.
final String? _fontRoot = () {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (flutterRoot != null && flutterRoot.isNotEmpty)
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  for (final path in candidates) {
    if (File('$path/Roboto-Regular.ttf').existsSync()) return path;
  }
  return null;
}();

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
    roboto.addFont(Future.value(_read('$_fontRoot!/$face')));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(_read('$_fontRoot!/MaterialIcons-Regular.otf')));
  await icons.load();
}

final _key = GlobalKey();

Future<void> _render(
  WidgetTester tester,
  Widget home, {
  required Size size,
  bool light = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
  addTearDown(() => debugServerVoiceDeviceOverride = null);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDirectory!/questions-dot-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

final _question = ServerPodcastQuestion(
  id: 'q1',
  serverId: 's',
  channelId: 'questions',
  authorId: 'listener-1',
  authorName: 'Ola',
  body: 'Jak wybieracie gości?',
  status: ServerPodcastQuestionStatus.queued,
  voteCount: 3,
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 25, 18),
  updatedAt: DateTime.utc(2026, 9, 25, 18),
);

const _friends = Server(
  id: 'f',
  name: 'Ekipa',
  description: 'Po godzinach',
  ownerId: 'owner',
  type: ServerType.friends,
  privacy: ServerPrivacy.private,
  memberCount: 6,
  defaultChannelId: 'general',
  schemaVersion: 1,
  activationState: 'active',
  directoryRole: ServerMemberRole.owner,
);

TestServerRepository _repository() => TestServerRepository()
  ..servers = [
    board.podcastServer().withDirectoryRole(ServerMemberRole.owner),
    _friends,
  ]
  ..channels = [
    ...board.podcastChannels(studio: board.live),
    const ServerChannel(
      id: 'general',
      serverId: 'f',
      name: 'ogólny',
      kind: ServerChannelKind.text,
      position: 0,
      schemaVersion: 1,
    ),
  ]
  ..myRole = ServerMemberRole.owner
  ..podcastQuestions = [_question];

Widget _workspace(TestServerRepository repository, String channelId) =>
    ServerWorkspaceScreen(
      serverId: 's',
      repository: repository,
      isRootTab: true,
      initialChannelId: channelId,
      chatService: board.podcastChat(),
      connector: FakeServerMediaConnector(),
      podcastEpisodeRepository: repository,
    );

Widget _directory(TestServerRepository repository) => ServersScreen(
  repository: repository,
  isRootTab: true,
  chatService: board.podcastChat(),
  connector: FakeServerMediaConnector(),
);

void main() {
  if (_outputDirectory == null || _fontRoot == null) {
    test(
      'visual capture',
      () {},
      skip:
          'Developer-only: set YOVOICE_CAPTURE_DIR to a directory outside '
          'the repository (and have the Flutter SDK Material fonts).',
    );
    return;
  }
  setUpAll(_loadRealFonts);

  for (final (label, size, light, scale) in const [
    ('studio-390x844', Size(390, 844), false, 1.0),
    ('studio-390x844-pearl', Size(390, 844), true, 1.0),
    ('studio-320x700-scale2', Size(320, 700), false, 2.0),
    ('studio-768x1024', Size(768, 1024), false, 1.0),
  ]) {
    testWidgets('Pytania tab $label', (tester) async {
      await _render(
        tester,
        _workspace(_repository(), 'studio'),
        size: size,
        light: light,
        textScale: scale,
      );
      await _shoot(tester, 'tab-$label');
    });
  }

  testWidgets('phone on another channel: Kanały, then the sheet', (
    tester,
  ) async {
    await _render(
      tester,
      _workspace(_repository(), 'discussion'),
      size: const Size(390, 844),
    );
    await _shoot(tester, 'kanaly-390x844');
    await tester.tap(find.byKey(const ValueKey('server-open-channels')));
    await tester.pumpAndSettle();
    await _shoot(tester, 'sheet-row-390x844');
  });

  for (final light in [false, true]) {
    testWidgets('desktop Questions row ${light ? 'Pearl' : 'Dark'}', (
      tester,
    ) async {
      await _render(
        tester,
        _workspace(_repository(), 'discussion'),
        size: const Size(1440, 900),
        light: light,
      );
      await _shoot(tester, 'row-1440x900${light ? '-pearl' : ''}');
    });
  }

  testWidgets('directory tiles and the rail', (tester) async {
    final repository = _repository();
    await _render(tester, _directory(repository), size: const Size(1440, 900));
    await _shoot(tester, 'directory-1440x900');
    await tester.tap(find.byKey(const ValueKey('server-directory-f')));
    await tester.pumpAndSettle();
    await _shoot(tester, 'rail-1440x900');
  });

  testWidgets('directory on a phone at 200 percent', (tester) async {
    await _render(
      tester,
      _directory(_repository()),
      size: const Size(390, 844),
      textScale: 2,
    );
    await _shoot(tester, 'directory-390x844-scale2');
  });
}
