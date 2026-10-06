// Developer-only VISUAL capture for Slim redesign phase 2 (Serwery): the
// directory as a compact list, the workspace with its server rail on a
// desktop and on a phone (the `Kanały` sheet), Dark and Pearl, pl, populated.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/slim_servers_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-09-19/slim-2-servers-frames/after/
// unless `--dart-define=YO_CAPTURE_DIR=<absolute dir>` points elsewhere.
// Layout exceptions are recorded in _exceptions.log next to the frames.
// Every frame is named `<screen>_<width>_<dark|pearl>_pl_<text>_<state>`
// (`-hc` for high contrast): the default set is the directory populated,
// the workspace live and not joined, and the phone's `Kanały` sheet.
//
// `--dart-define=YO_SERVERS_EXTENDED=true` adds the refine-look matrix
// (spec §11, Servers) on top of the default frames, named
// `<screen>_<width>_<dark|pearl>_pl_<text>_<state>.png`:
//
// * 200 % text for the directory, the live workspace and the phone sheet at
//   390 / 768 / 1440;
// * the empty directory (first-run logo);
// * the workspace quiet, connected (a real roster with one person speaking,
//   the conversation bar up and the local microphone opened from the bar's
//   own control, so the bar, the orb and the "Ty" tile agree) and held;
// * all five templates on their own board channel, LIVE;
// * high contrast for the live and connected workspace, the phone sheet and
//   the directory;
// * keyboard focus on the create action, a directory row, the join and a
//   panel row; pointer hover on a directory row;
// * the shared waiting dot: a podcast host's directory row (listener
//   questions) and a host's connected studio with a raised hand (the
//   channel row and the bar's requests control);
// * the directory loading and failing, and 768 quiet / held / empty;
// * right-to-left spot frames (Polish copy under `TextDirection.rtl`: the
//   host has no Arabic font, the point is the mirroring);
// * the 1440 directory inside the desktop shell's composition (the real
//   `DesktopSidebar` beside the slot), where the rail owns the one lift.
//
// Every frame renders with Reduce Motion on (as the default frames always
// did), so the header lamp and the badge dot are at rest, and with real
// blurred shadows (see `_captureWidgets`).

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/models/server_session_hand.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import 'server_independent_qa_support.dart' as qa;
import 'server_podcast_test.dart' as podcast;
import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';

const _outputDirectory = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-19/'
      'slim-2-servers-frames/after',
);

const _extended = bool.fromEnvironment('YO_SERVERS_EXTENDED');

final _exceptions = File('$_outputDirectory/_exceptions.log');

String get _fontRoot {
  final candidates = [
    // `flutter test` exports the SDK it runs from; a Linux or CI host has
    // its fonts there rather than under a Homebrew prefix.
    if (Platform.environment['FLUTTER_ROOT'] case final root?
        when root.isNotEmpty)
      '$root/bin/cache/artifacts/material_fonts',
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
List<Server> _servers({bool held = false}) => [
  boards.boardServer(ServerType.friends, members: 12, held: held),
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

final _liveSince = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 19, 19, 40),
);

Widget _directory({List<Server>? servers, TestServerRepository? repository}) =>
    ServersScreen(
      key: UniqueKey(),
      isRootTab: true,
      repository:
          repository ??
          (TestServerRepository()..servers = servers ?? _servers()),
      chatService: boards.boardChat(),
      connector: FakeServerMediaConnector(),
    );

/// A directory whose server list never arrives ([loading]) or fails.
class _DirectoryStateRepository extends TestServerRepository {
  _DirectoryStateRepository({required this.loading});
  final bool loading;

  @override
  Stream<List<Server>> watchMyServers() => loading
      // Never emits and never closes: the first frame's wait, held.
      ? StreamController<List<Server>>().stream
      : Stream<List<Server>>.error(StateError('permission-denied'));
}

Widget _workspace({
  bool live = true,
  bool held = false,
  FakeServerMediaConnector? connector,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: TestServerRepository()
    ..servers = _servers(held: held)
    ..channels = boards.boardChannels(
      ServerType.friends,
      liveness: live ? _liveSince : ServerChannelLiveness.idle,
    ),
  isRootTab: true,
  initialChannelId: 'lounge',
  chatService: boards.boardChat(),
  connector: connector ?? FakeServerMediaConnector(),
);

/// The default frames: each surface with the state it opens in.
final _surfaces = <String, (String, Widget Function())>{
  'directory': ('populated', _directory),
  'workspace': ('live', _workspace),
};

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  required ThemeData theme,
  double textScale = 1,
  bool highContrast = false,
  TextDirection? direction,
}) async {
  // The view's pixel ratio is the capture's, so a raster (the logo) decodes
  // at the resolution it is shot at, as it would on a device.
  final ratio = _pixelRatio(size.width);
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  // The workspace's join path asks the platform for the microphone; the
  // capture host has none, so the tests' fake device answers.
  debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
  addTearDown(() => debugServerVoiceDeviceOverride = null);
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
        builder: (context, inner) {
          final media = MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
              highContrast: highContrast,
            ),
            child: inner!,
          );
          return direction == null
              ? media
              : Directionality(textDirection: direction, child: media);
        },
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

double _pixelRatio(double width) => width <= 768 ? 2 : 1;

/// Decodes every image on screen for real (the fake clock never lets an
/// asset finish loading), so a frame never shows an empty logo slot.
Future<void> _decodeImages(WidgetTester tester) async {
  final images = find.byType(Image).evaluate().toList();
  if (images.isEmpty) return;
  await tester.runAsync(
    () => Future.wait([
      for (final element in images)
        precacheImage(
          (element.widget as Image).image,
          element,
          onError: (_, _) {},
        ),
    ]),
  );
  await tester.pump();
}

Future<void> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
  required double width,
}) async {
  await _decodeImages(tester);
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
    final image = await boundary.toImage(pixelRatio: _pixelRatio(width));
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

/// The refine-look frame name (spec §11).
String _name(
  String screen,
  double width,
  bool light,
  double textScale,
  String state,
) =>
    '${screen}_${width.toInt()}_${light ? 'pearl' : 'dark'}_pl_'
    '${(textScale * 100).round()}_$state';

/// A capture case. The test framework paints every BoxShadow as a hard,
/// unblurred block (`debugDisableShadows`, meant for golden stability); a
/// capture switches that off so Pearl's block shadows, the CTA lift and the
/// LIVE under-glow render as they do on a device, and restores it before
/// the case ends (the framework verifies it).
void _captureWidgets(String name, WidgetTesterCallback body) =>
    testWidgets(name, (tester) async {
      debugDisableShadows = false;
      try {
        await body(tester);
      } finally {
        debugDisableShadows = true;
      }
    });

const _sizes = [(390.0, 844.0), (768.0, 1024.0), (1440.0, 900.0)];
const _themes = [('dark', false), ('pearl', true)];

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  for (final entry in _surfaces.entries) {
    final (state, surface) = entry.value;
    for (final (width, height) in _sizes) {
      for (final (_, light) in _themes) {
        final name = _name(entry.key, width, light, 1, state);
        _captureWidgets(name, (tester) async {
          final captureKey = GlobalKey();
          await _render(
            tester,
            captureKey: captureKey,
            size: Size(width, height),
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            child: surface(),
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
              name: _name('workspace-sheet', width, light, 1, state),
              width: width,
            );
          }
        });
      }
    }
  }

  if (!_extended) return;

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required double width,
    required double height,
    required bool light,
    required Widget child,
    double textScale = 1,
    bool highContrast = false,
    TextDirection? direction,
    Future<void> Function(WidgetTester tester)? before,
    String? sheetName,
  }) async {
    final captureKey = GlobalKey();
    await _render(
      tester,
      captureKey: captureKey,
      size: Size(width, height),
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      child: child,
      textScale: textScale,
      highContrast: highContrast,
      direction: direction,
    );
    if (before != null) await before(tester);
    await _shoot(tester, captureKey: captureKey, name: name, width: width);
    if (sheetName != null) {
      await tester.tap(find.byKey(const ValueKey('server-open-channels')));
      await _settle(tester);
      await _shoot(
        tester,
        captureKey: captureKey,
        name: sheetName,
        width: width,
      );
    }
  }

  // 200 % text: the directory, the live workspace and the phone sheet.
  for (final (width, height) in _sizes) {
    for (final (_, light) in _themes) {
      _captureWidgets(_name('directory', width, light, 2, 'populated'), (
        tester,
      ) async {
        await capture(
          tester,
          name: _name('directory', width, light, 2, 'populated'),
          width: width,
          height: height,
          light: light,
          textScale: 2,
          child: _directory(),
        );
      });
      _captureWidgets(_name('workspace', width, light, 2, 'live'), (
        tester,
      ) async {
        await capture(
          tester,
          name: _name('workspace', width, light, 2, 'live'),
          width: width,
          height: height,
          light: light,
          textScale: 2,
          child: _workspace(),
          sheetName: width < 768
              ? _name('workspace-sheet', width, light, 2, 'live')
              : null,
        );
      });
    }
  }

  // The empty directory: the first-run invitation with the real logo.
  for (final (width, height) in _sizes) {
    for (final (_, light) in _themes) {
      final name = _name('directory', width, light, 1, 'empty');
      _captureWidgets(name, (tester) async {
        await capture(
          tester,
          name: name,
          width: width,
          height: height,
          light: light,
          child: _directory(servers: const []),
        );
      });
    }
  }

  // The workspace's other states: quiet, connected and held.
  for (final (width, height) in _sizes) {
    for (final (_, light) in _themes) {
      {
        final quiet = _name('workspace', width, light, 1, 'quiet');
        _captureWidgets(quiet, (tester) async {
          await capture(
            tester,
            name: quiet,
            width: width,
            height: height,
            light: light,
            child: _workspace(live: false),
          );
        });
        final held = _name('workspace', width, light, 1, 'held');
        _captureWidgets(held, (tester) async {
          await capture(
            tester,
            name: held,
            width: width,
            height: height,
            light: light,
            child: _workspace(held: true),
          );
        });
      }
      final connected = _name('workspace', width, light, 1, 'connected');
      _captureWidgets(connected, (tester) async {
        final connector = FakeServerMediaConnector();
        await capture(
          tester,
          name: connected,
          width: width,
          height: height,
          light: light,
          child: _workspace(connector: connector),
          before: (tester) => _connect(tester, connector),
        );
      });
    }
  }

  // All five templates on their own board channel, LIVE.
  for (final type in ServerType.values) {
    for (final (width, height) in [_sizes.first, _sizes.last]) {
      for (final (_, light) in _themes) {
        final name = _name('template-${type.name}', width, light, 1, 'live');
        _captureWidgets(name, (tester) async {
          final repository = TestServerRepository()
            ..servers = [qa.qaServer(type)]
            ..channels = qa.qaChannels(
              type,
              liveness: _liveSince,
              activeSessionId: 'session-live',
            );
          await capture(
            tester,
            name: name,
            width: width,
            height: height,
            light: light,
            child: qa.qaWorkspace(
              repository,
              channelId: qa.qaJoinableChannel(type),
            ),
          );
        });
      }
    }
  }

  // High contrast: no gradient, tint or glow; `borderStrong` edges.
  _captureWidgets(_name('workspace', 390, false, 1, 'live-hc'), (tester) async {
    await capture(
      tester,
      name: _name('workspace', 390, false, 1, 'live-hc'),
      width: 390,
      height: 844,
      light: false,
      highContrast: true,
      child: _workspace(),
    );
  });
  _captureWidgets(_name('directory', 1440, true, 1, 'populated-hc'), (
    tester,
  ) async {
    await capture(
      tester,
      name: _name('directory', 1440, true, 1, 'populated-hc'),
      width: 1440,
      height: 900,
      light: true,
      highContrast: true,
      child: _directory(),
    );
  });
  for (final (_, light) in _themes) {
    for (final (width, height) in [_sizes.first, _sizes.last]) {
      final directoryHc = _name('directory', width, light, 1, 'populated-hc');
      if (!(width == 1440 && light)) {
        _captureWidgets(directoryHc, (tester) async {
          await capture(
            tester,
            name: directoryHc,
            width: width,
            height: height,
            light: light,
            highContrast: true,
            child: _directory(),
          );
        });
      }
      final liveHc = _name('workspace', width, light, 1, 'live-hc');
      if (!(width == 390 && !light)) {
        _captureWidgets(liveHc, (tester) async {
          await capture(
            tester,
            name: liveHc,
            width: width,
            height: height,
            light: light,
            highContrast: true,
            child: _workspace(),
            sheetName: width < 768
                ? _name('workspace-sheet', width, light, 1, 'live-hc')
                : null,
          );
        });
      }
      final connectedHc = _name('workspace', width, light, 1, 'connected-hc');
      _captureWidgets(connectedHc, (tester) async {
        final connector = FakeServerMediaConnector();
        await capture(
          tester,
          name: connectedHc,
          width: width,
          height: height,
          light: light,
          highContrast: true,
          child: _workspace(connector: connector),
          before: (tester) => _connect(tester, connector),
        );
      });
    }
  }
  // The Dark phone sheet under high contrast (the Pearl one is shot with
  // its workspace above).
  _captureWidgets(_name('workspace-sheet', 390, false, 1, 'live-hc'), (
    tester,
  ) async {
    await capture(
      tester,
      name: _name('workspace', 390, false, 1, 'live-hc'),
      width: 390,
      height: 844,
      light: false,
      highContrast: true,
      child: _workspace(),
      sheetName: _name('workspace-sheet', 390, false, 1, 'live-hc'),
    );
  });

  // Keyboard focus, as a keyboard user reaches it (Tab), and pointer hover.
  for (final (_, light) in _themes) {
    for (final (width, height) in [_sizes.first, _sizes.last]) {
      final focusCta = _name('directory', width, light, 1, 'focus-cta');
      _captureWidgets(focusCta, (tester) async {
        _traditionalFocus();
        await capture(
          tester,
          name: focusCta,
          width: width,
          height: height,
          light: light,
          child: _directory(),
          before: (tester) =>
              _tabTo(tester, find.byKey(const ValueKey('servers-add'))),
        );
      });
      final focusRow = _name('directory', width, light, 1, 'focus-row');
      _captureWidgets(focusRow, (tester) async {
        _traditionalFocus();
        await capture(
          tester,
          name: focusRow,
          width: width,
          height: height,
          light: light,
          child: _directory(),
          before: (tester) =>
              _tabTo(tester, find.byKey(const ValueKey('server-directory-s'))),
        );
      });
      // Final review (A11Y-02): Tab past the row onto its own "…" button;
      // only the button is ringed, never the row around it too.
      final focusRowMore = _name(
        'directory',
        width,
        light,
        1,
        'focus-row-more',
      );
      _captureWidgets(focusRowMore, (tester) async {
        _traditionalFocus();
        await capture(
          tester,
          name: focusRowMore,
          width: width,
          height: height,
          light: light,
          child: _directory(),
          before: (tester) => _tabTo(
            tester,
            find.byKey(const ValueKey('server-directory-actions-s')),
          ),
        );
      });
      final focusJoin = _name('workspace', width, light, 1, 'focus-join');
      _captureWidgets(focusJoin, (tester) async {
        _traditionalFocus();
        await capture(
          tester,
          name: focusJoin,
          width: width,
          height: height,
          light: light,
          child: _workspace(),
          before: (tester) =>
              _tabTo(tester, find.byKey(const ValueKey('server-join'))),
        );
      });
    }
    final rowFocus = _name('workspace', 1440, light, 1, 'focus-row');
    _captureWidgets(rowFocus, (tester) async {
      _traditionalFocus();
      await capture(
        tester,
        name: rowFocus,
        width: 1440,
        height: 900,
        light: light,
        child: _workspace(),
        before: (tester) async {
          // The selected row (Salon), then its neighbour below: focus on a
          // selected and on a plain row.
          tester
              .widget<ListTile>(
                find.byKey(const ValueKey('server-channel-lounge')),
              )
              .focusNode!
              .requestFocus();
          await _settle(tester);
        },
      );
    });
    final hover = _name('directory', 1440, light, 1, 'hover');
    _captureWidgets(hover, (tester) async {
      await capture(
        tester,
        name: hover,
        width: 1440,
        height: 900,
        light: light,
        child: _directory(),
        before: (tester) async {
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(
            tester.getCenter(find.byKey(const ValueKey('server-directory-r'))),
          );
          await _settle(tester);
        },
      );
    });
  }

  // The shared waiting dot on the new finishes.
  for (final (_, light) in _themes) {
    for (final (width, height) in [_sizes.first, _sizes.last]) {
      final questions = _name('directory', width, light, 1, 'waiting');
      _captureWidgets(questions, (tester) async {
        final repository = TestServerRepository()
          ..servers = [
            podcast.podcastServer().withDirectoryRole(ServerMemberRole.owner),
            ..._servers().skip(1),
          ]
          // The questions channel the host reads, and one question it has
          // not seen yet.
          ..channels = podcast.podcastChannels()
          ..myRole = ServerMemberRole.owner
          ..podcastQuestions = [_question('q1')];
        await capture(
          tester,
          name: questions,
          width: width,
          height: height,
          light: light,
          child: _directory(repository: repository),
        );
      });
      final hands = _name(
        'workspace-podcast',
        width,
        light,
        1,
        'hands-waiting',
      );
      _captureWidgets(hands, (tester) async {
        final connector = FakeServerMediaConnector();
        final repository = TestServerRepository()
          ..servers = [podcast.podcastServer(), ..._servers().skip(1)]
          ..channels = podcast.podcastChannels(
            studio: podcast.live,
            activeSessionId: 'gen-7',
          )
          ..myRole = ServerMemberRole.member
          ..sessionRole = 'host'
          ..sessionHands = [
            ServerSessionHand(
              userId: 'ola',
              displayName: 'Ola',
              role: 'listener',
              raisedAt: DateTime.now().subtract(const Duration(minutes: 3)),
            ),
          ];
        await capture(
          tester,
          name: hands,
          width: width,
          height: height,
          light: light,
          child: podcast.podcastWorkspace(repository, connector: connector),
          before: (tester) async {
            final join = find.byKey(const ValueKey('server-join'));
            await tester.ensureVisible(join.first);
            await tester.tap(join.first);
            await _settle(tester);
            connector.links.single.setRoster(const [
              // The host joined muted, as the bar says.
              ServerMediaParticipant(
                identity: 'owner',
                name: 'Kasia',
                isLocal: true,
              ),
              ServerMediaParticipant(
                identity: 'ola',
                name: 'Ola',
                isLocal: false,
                sessionRole: 'listener',
              ),
            ]);
            await _settle(tester);
          },
        );
      });
    }
  }

  // The directory before its list arrives, and when it cannot be read.
  for (final (_, light) in _themes) {
    for (final loading in [true, false]) {
      final state = loading ? 'loading' : 'error';
      final name = _name('directory', 390, light, 1, state);
      _captureWidgets(name, (tester) async {
        await capture(
          tester,
          name: name,
          width: 390,
          height: 844,
          light: light,
          child: _directory(
            repository: _DirectoryStateRepository(loading: loading),
          ),
        );
      });
    }
  }

  // Right to left: the corner light, the tint, the row wash and the lamp
  // mirror (Polish copy; the point is the direction, not the script).
  for (final (_, light) in _themes) {
    for (final (width, height) in [_sizes.first, _sizes.last]) {
      final live = _name('workspace', width, light, 1, 'live-rtl');
      _captureWidgets(live, (tester) async {
        await capture(
          tester,
          name: live,
          width: width,
          height: height,
          light: light,
          direction: TextDirection.rtl,
          child: _workspace(),
        );
      });
      final connected = _name('workspace', width, light, 1, 'connected-rtl');
      _captureWidgets(connected, (tester) async {
        final connector = FakeServerMediaConnector();
        await capture(
          tester,
          name: connected,
          width: width,
          height: height,
          light: light,
          direction: TextDirection.rtl,
          child: _workspace(connector: connector),
          before: (tester) => _connect(tester, connector),
        );
      });
    }
    final directoryRtl = _name('directory', 390, light, 1, 'populated-rtl');
    _captureWidgets(directoryRtl, (tester) async {
      await capture(
        tester,
        name: directoryRtl,
        width: 390,
        height: 844,
        light: light,
        direction: TextDirection.rtl,
        child: _directory(),
      );
    });
  }

  // The desktop shell's composition: the real rail beside the directory
  // slot, where the rail's "Stwórz serwer" is the screen's one lift.
  for (final (_, light) in _themes) {
    final name = _name('directory-shell', 1440, light, 1, 'populated');
    _captureWidgets(name, (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('owner').set(<String, dynamic>{
        'uid': 'owner',
        'displayName': 'Kamil',
        'username': 'kamil',
      });
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner', displayName: 'Kamil'),
      );
      await capture(
        tester,
        name: name,
        width: 1440,
        height: 900,
        light: light,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Row(
              children: [
                DesktopSidebar(
                  active: DesktopNavItem.servers,
                  unreadConversationCount: 0,
                  unreadNotificationCount: 0,
                  onSelect: (_) {},
                  onCreateRoom: () {},
                  onCreateMoment: () {},
                  onOpenProfile: () {},
                  onOpenProfileSettings: () {},
                  profileService: ProfileService(firestore: db, auth: auth),
                ),
                Expanded(
                  child: ResponsiveContentFrame(
                    width: ResponsiveContentWidth.workbench,
                    child: _directory(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// A real join through the scene's own action, the roster the provider
/// reports (one person speaking, the local participant publishing), and the
/// local microphone opened from the bar's own control — so the bar, the
/// stage orb and the "Ty" tile all say the same thing.
Future<void> _connect(
  WidgetTester tester,
  FakeServerMediaConnector connector,
) async {
  await tester.tap(find.byKey(const ValueKey('server-join')));
  await _settle(tester);
  connector.links.single.setRoster(qa.qaRoster);
  await _settle(tester);
  final microphone = find.byKey(const ValueKey('server-dock-microphone'));
  if (microphone.evaluate().isNotEmpty) {
    await tester.tap(microphone);
    await _settle(tester);
  }
}

/// Focus is drawn as it is for a keyboard user, whatever the last input was.
void _traditionalFocus() {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
}

/// Presses Tab until the primary focus sits inside [target].
Future<void> _tabTo(WidgetTester tester, Finder target) async {
  bool inside() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final goal = target.evaluate().toSet();
    if (goal.contains(focused)) return true;
    var found = false;
    focused.visitAncestorElements((element) {
      found = goal.contains(element);
      return !found;
    });
    return found;
  }

  for (var tabs = 0; tabs < 40 && !inside(); tabs++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  await _settle(tester);
}

ServerPodcastQuestion _question(String id) => ServerPodcastQuestion(
  id: id,
  serverId: 's',
  channelId: 'questions',
  authorId: 'listener-1',
  authorName: 'Ola',
  body: 'Pytanie $id',
  status: ServerPodcastQuestionStatus.queued,
  voteCount: 0,
  revision: 1,
  createdAt: DateTime(2026, 9, 19, 19, 41),
  updatedAt: DateTime(2026, 9, 19, 19, 41),
);
