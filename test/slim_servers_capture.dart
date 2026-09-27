// Developer-only VISUAL capture for the Servers area: the directory, the
// workspace with its server rail on a desktop and on a phone (the `Kanały`
// sheet), Dark and Pearl, pl.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/slim_servers_capture.dart --concurrency=1 \
//     --dart-define=SLIM_CAPTURE_OUT=<absolute dir> \
//     --dart-define=SLIM_SERVERS_MATRIX=slim|refine|all
//
// * `slim` (the default) renders the original Slim phase 2 set under its
//   original names (`directory-390x844-dark-1x-pl.png`, …, 14 frames), so a
//   run on an older checkout and a run on this one compare file for file.
// * `refine` renders the refine-look matrix (spec §11, Servers), named
//   `<screen>_<width>_<dark|pearl>_pl_<text>_<state>.png`:
//   - `directory`: populated at 390 (one column) and 768 / 1440 (row-major
//     pairs) at 100 % and 200 % text; `empty` (the first-run logo); `long`
//     (names and descriptions nobody sized for — equal-height pairs and the
//     200 % stacked rows); `focus` (keyboard focus on the first row, 1440);
//   - `workspace`: `live` (not joined: the lit session card, the gem, the
//     header lamp) at every width and at 100 % / 200 %; `quiet`;
//     `connected` (a real join through `server-join`, then the roster the
//     provider reports — one person speaking — with the microphone open: the
//     conversation bar, the voice stage, the accent edge and tint);
//     `held`; `admission` (a public server before membership); `invite`
//     (the invite introduction after creation);
//   - `workspace-sheet`: the phone `Kanały` sheet (390, 100 % / 200 %);
//   - `template-<type>`: each of the five boards on its own destination,
//     LIVE, at 390 and 1440; and the four boards beside the friends
//     workspace (family lounge, podcast studio, community stage, company
//     shared screen) also `quiet` and `connected` (a real join through
//     their own `server-join`, then the provider's roster) at 390 and 1440,
//     plus one `connected-hc` frame each (390, Dark, high contrast) — the
//     re-check of spec §13, B4 (every live surface, every state);
//   - `*-hc`: system high contrast for the live and connected workspace and
//     the directory;
//   - review round (accessibility A11Y-1 / A11Y-2): `connected-muted` (the
//     microphone off and the headphones deafened, so the conversation bar
//     shows its NEUTRAL glass controls) at 390 / 1440, 100 % / 200 %;
//     keyboard focus (`focus-join`, `focus-channels`, `focus-invite`,
//     `connected-muted-focus`, the directory's `focus-actions`) at 390 and
//     1440; `connected-muted-focus-hc` (the A11Y-1 ring under high
//     contrast); `admission-busy` (the public join while it runs); more
//     high contrast (`live-hc` Pearl and 200 %, the Dark directory, the
//     muted bar); one RTL frame (`workspace_390_dark_ar_100_live`, the
//     host's Arabic system face standing in for the app's 'Noto Sans
//     Arabic' fallback) and a 320 px live frame at 200 %. Every focus case
//     prints `FOCUSRECT <frame> <key> <l> <t> <r> <b>` (logical px) so the
//     ring can be measured against the fill it is painted on.
// * `all` renders both.
//
// PNGs land in SLIM_CAPTURE_OUT (default: the Slim phase 2 folder,
// yovoice-evidence/2026-09-19/slim-2-servers-frames/after). Layout exceptions
// are recorded in `_exceptions.log` next to the frames.
// `--dart-define=SLIM_CAPTURE_DRY=true` runs every case (renders, joins,
// opens the sheet, focuses) and prints the frame names and any layout
// exception, but writes nothing: a harness self-check. Every refine case
// also asserts that the state it is named for is really on screen (e.g. a
// `connected` frame fails rather than showing a join that did not happen).
// The session card's light layers (`server-session-glow`, `-corner`,
// `-tint`) are always in the tree since spec §13 (B4, one tree shape in
// every state), so for them "shown" means lit and "hidden" means dark
// (test/support/server_session_lights.dart).
//
// Every frame renders with Reduce Motion on (the header lamp's pulse and the
// session card's one-time ignite are at rest, exactly as they settle), with
// real fonts, and with REAL shadows: the test framework paints every
// BoxShadow as a hard, unblurred block by default (`debugDisableShadows`,
// meant for golden stability), which would misrepresent Pearl's block
// shadows, the CTA lift and the live under-glow; it is switched off while a
// frame is captured and restored before the case ends.
//
// Refine frames also render with the view's pixel ratio equal to the PNG's
// (2 up to 768 px, 1 at 1440), so a DPR-aware image such as the empty
// directory's logo is decoded for the pixels it lands on rather than
// upscaled; the slim frames keep ratio 1, exactly as build 36 was captured.
// The `-hc` frames use the app's high-contrast theme twins
// (`AppTheme.*HighContrastTheme`), as lib/app/app.dart hands them over.

import 'dart:async';
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
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_independent_qa_support.dart' as qa;
import 'server_templates_test.dart' as boards;
import 'server_test_support.dart';
import 'support/material_icons_font.dart';
import 'support/server_session_lights.dart';

const _outputDirectory = String.fromEnvironment(
  'SLIM_CAPTURE_OUT',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-19/'
      'slim-2-servers-frames/after',
);

const _matrix = String.fromEnvironment(
  'SLIM_SERVERS_MATRIX',
  defaultValue: 'slim',
);

const _dry = bool.fromEnvironment('SLIM_CAPTURE_DRY');

bool get _slim => _matrix == 'slim' || _matrix == 'all';
bool get _refine => _matrix == 'refine' || _matrix == 'all';

final _exceptions = File('$_outputDirectory/_exceptions.log');

String get _fontRoot {
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?
        when root.isNotEmpty)
      '$root/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return roots.firstWhere(
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
  await loadMaterialIconsFont();
  // The RTL frame: Inter has no Arabic, and a phone resolves the app's
  // first fallback family ('Noto Sans Arabic') to a system Arabic face. The
  // host's Arabic system font stands in for it under that name (the same
  // stand-in `slim_start_capture.dart` uses), so the frame shows Arabic
  // copy instead of tofu boxes.
  final arabic = File(_arabicFont);
  if (arabic.existsSync()) {
    final loader = FontLoader('Noto Sans Arabic')
      ..addFont(Future.value(ByteData.sublistView(arabic.readAsBytesSync())));
    await loader.load();
  }
}

const _arabicFont = '/System/Library/Fonts/SFArabic.ttf';

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

/// Names and descriptions nobody sized for, beside short ones — the case
/// the directory's equal-height pairs and 200 % stacked rows exist for.
List<Server> _longServers() => [
  _server(
    'l1',
    'Wieczorne rozmowy o książkach, filmach i wszystkim pomiędzy',
    ServerType.community,
    members: 1248,
    description:
        'Raz w tygodniu jedna książka, raz w miesiącu jeden film i zawsze '
        'jedna długa rozmowa o tym, co z nich w nas zostało.',
  ),
  _server('l2', 'Ekipa', ServerType.friends, members: 4),
  _server(
    'l3',
    'Studio Północ — zespół produktowy i wszyscy, którzy z nim pracują',
    ServerType.company,
    members: 57,
    description: 'Planowanie, przeglądy i codzienne spotkania zespołu.',
  ),
  _server('l4', 'Dom', ServerType.family, members: 5),
  _server(
    'l5',
    'Nocne audycje',
    ServerType.podcast,
    members: 42,
    description: 'Rozmowy po północy.',
  ),
];

final _liveSince = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 19, 19, 40),
);

Widget _directory({List<Server>? servers}) => ServersScreen(
  key: UniqueKey(),
  isRootTab: true,
  repository: TestServerRepository()..servers = servers ?? _servers(),
  chatService: boards.boardChat(),
  connector: FakeServerMediaConnector(),
);

Widget _workspace({
  bool live = true,
  bool held = false,
  bool justCreated = false,
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
  justCreated: justCreated,
  chatService: boards.boardChat(),
  connector: connector ?? FakeServerMediaConnector(),
);

/// A public community before membership: the admission card and its join.
Widget _admission() {
  final repository = TestServerRepository()
    ..servers = [qa.qaServer(ServerType.community, members: 248)]
    ..channels = qa.qaChannels(ServerType.community)
    ..myRole = null;
  return qa.qaWorkspace(repository);
}

/// Each board on the destination it is about, LIVE unless [live] is false.
/// [connector] is the provider a `connected` frame joins through.
Widget _template(
  ServerType type, {
  bool live = true,
  FakeServerMediaConnector? connector,
}) {
  final repository = TestServerRepository()
    ..servers = [qa.qaServer(type)]
    ..channels = qa.qaChannels(
      type,
      liveness: live ? _liveSince : ServerChannelLiveness.idle,
      activeSessionId: live ? 'session-live' : null,
    );
  return qa.qaWorkspace(
    repository,
    channelId: qa.qaBoardChannel(type),
    connector: connector,
  );
}

final _surfaces = <String, Widget Function()>{
  'directory': _directory,
  'workspace': _workspace,
};

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  required ThemeData theme,
  double textScale = 1,
  bool highContrast = false,
  double devicePixelRatio = 1,
  Locale locale = const Locale('pl'),
}) async {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  // The workspace's join path asks the platform for the microphone and the
  // audio route; the capture host has neither, so the tests' fake answers.
  debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
  addTearDown(() => debugServerVoiceDeviceOverride = null);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: theme,
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
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
            highContrast: highContrast,
          ),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await _settle(tester);
  // Asset decodes (the brand mark and its bloom) complete on the real event
  // loop; give them real turns so the frame is not captured before them.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
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
    if (_dry) {
      // ignore: avoid_print
      print('EXCEPTION $name :: $headline');
    } else {
      _exceptions.writeAsStringSync(
        '$name :: $headline\n',
        mode: FileMode.append,
      );
    }
  }
  if (_dry) {
    // ignore: avoid_print
    print('dry $name');
    return;
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

/// The refine-look frame name (spec §11).
String _name(
  String screen,
  double width,
  bool light,
  double textScale,
  String state, {
  String language = 'pl',
}) =>
    '${screen}_${width.toInt()}_${light ? 'pearl' : 'dark'}_${language}_'
    '${(textScale * 100).round()}_$state';

const _sizes = [(390.0, 844.0), (768.0, 1024.0), (1440.0, 900.0)];

/// What a real join with a roster puts on screen.
const _connectedKeys = [
  'server-session-tint',
  'server-conversation-dock',
  'server-voice-orb',
  'server-participant-ring-ola',
];
const _phoneAndDesktop = [(390.0, 844.0), (1440.0, 900.0)];

/// The four boards whose live surface is not the friends session card: the
/// family lounge, the podcast studio, the community stage and the company
/// meeting's shared screen.
final _otherTemplates = [
  for (final type in ServerType.values)
    if (type != ServerType.friends) type,
];
const _themes = [false, true];

/// Real shadows for the duration of one capture case. Restored inside the
/// test body: the framework verifies its painting debug variables before
/// any tear-down runs.
Future<void> _withRealShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Joins the Salon through its own `server-join`, then reports the roster a
/// provider really would — one person speaking — with the microphone open,
/// and scrolls the scene back to its top.
Future<void> _joinWithRoster(
  WidgetTester tester,
  FakeServerMediaConnector connector,
) async {
  final join = find.byKey(const ValueKey('server-join'));
  await tester.ensureVisible(join);
  await _settle(tester);
  await tester.tap(join);
  await _settle(tester);
  final link = connector.links.single;
  link
    ..microphone = true
    ..setRoster(qa.qaRoster);
  await _settle(tester);
  // Every vertical scroller the join moved (the tap brought the join into
  // view; at 200 % text that scrolls the scene) goes back to its start, so
  // the frame opens on the voice stage.
  for (final element in find.byType(Scrollable).evaluate().toList()) {
    final state = (element as StatefulElement).state as ScrollableState;
    final position = state.position;
    if (state.widget.axis == Axis.vertical &&
        position.hasPixels &&
        position.pixels != position.minScrollExtent) {
      position.jumpTo(position.minScrollExtent);
    }
  }
  await _settle(tester);
}

/// Keyboard focus on the first directory row, in the keyboard highlight
/// mode — the 2 px ring painted over the block without moving it.
Future<void> _focusFirstRow(WidgetTester tester) async {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final row = find.byKey(const ValueKey('server-directory-s'));
  final inner = find
      .descendant(
        of: find.descendant(of: row, matching: find.byType(InkWell)).first,
        matching: find.byType(Padding),
      )
      .first;
  Focus.of(tester.element(inner)).requestFocus();
  await _settle(tester);
}

/// Joins with the roster, then turns the microphone OFF and the headphones
/// DEAFENED — the two controls every connected frame so far showed only lit
/// — so the conversation bar shows its neutral glass controls.
Future<void> _joinMuted(
  WidgetTester tester,
  FakeServerMediaConnector connector,
) async {
  await _joinWithRoster(tester, connector);
  final link = connector.links.single
    ..microphone = false
    ..deafened = true;
  link.report(link.state);
  await _settle(tester);
}

/// Keyboard focus on the control keyed [key], in the keyboard highlight
/// mode, and its rect printed for the ring measurement.
Future<void> _focusKey(WidgetTester tester, String frame, String key) async {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await _settle(tester);
  // The control's own focus node is the `Focus` inside its `InkWell`.
  final ink = find
      .descendant(of: target, matching: find.byType(InkWell), matchRoot: true)
      .first;
  final focus = find.descendant(of: ink, matching: find.byType(Focus)).first;
  final inside = find
      .descendant(of: focus, matching: find.byWidgetPredicate((_) => true))
      .first;
  // No dependency on the focus scope from the test's side.
  Focus.maybeOf(tester.element(inside), createDependency: false)!
      .requestFocus();
  await _settle(tester);
  final rect = tester.getRect(target);
  // ignore: avoid_print
  print(
    'FOCUSRECT $frame $key ${rect.left} ${rect.top} ${rect.right} '
    '${rect.bottom}',
  );
}

/// A public server's admission whose join never answers: the busy state.
class _PendingJoinRepository extends TestServerRepository {
  final _never = Completer<void>();

  @override
  Future<void> joinServer({
    required String serverId,
    required String requestId,
  }) {
    calls.add(('joinServerV1', {'serverId': serverId, 'requestId': requestId}));
    return _never.future;
  }
}

Widget _admissionPending() {
  final repository = _PendingJoinRepository()
    ..servers = [qa.qaServer(ServerType.community, members: 248)]
    ..channels = qa.qaChannels(ServerType.community)
    ..myRole = null;
  return qa.qaWorkspace(repository);
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    if (_dry) return;
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  if (_slim) _slimMatrix();
  if (_refine) _refineMatrix();
}

/// The original Slim phase 2 frames, under their original names.
void _slimMatrix() {
  for (final entry in _surfaces.entries) {
    for (final (width, height) in _sizes) {
      for (final (themeLabel, light) in const [
        ('dark', false),
        ('pearl', true),
      ]) {
        final name =
            '${entry.key}-${width.toInt()}x${height.toInt()}-$themeLabel-1x-pl';
        testWidgets(name, (tester) async {
          await _withRealShadows(
            () => _slimCase(
              tester,
              surface: entry.key,
              build: entry.value,
              width: width,
              height: height,
              light: light,
              themeLabel: themeLabel,
              name: name,
            ),
          );
        });
      }
    }
  }
}

Future<void> _slimCase(
  WidgetTester tester, {
  required String surface,
  required Widget Function() build,
  required double width,
  required double height,
  required bool light,
  required String themeLabel,
  required String name,
}) async {
  final captureKey = GlobalKey();
  await _render(
    tester,
    captureKey: captureKey,
    size: Size(width, height),
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    child: build(),
  );
  await _shoot(tester, captureKey: captureKey, name: name, width: width);
  // The phone's server rail lives in the `Kanały` sheet.
  if (surface == 'workspace' && width < 768) {
    await tester.tap(find.byKey(const ValueKey('server-open-channels')));
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
}

/// The refine-look matrix (spec §11, Servers).
void _refineMatrix() {
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required double width,
    required double height,
    required bool light,
    required Widget child,
    double textScale = 1,
    bool highContrast = false,
    Future<void> Function(WidgetTester tester)? before,
    String? sheetName,
    List<String> shows = const [],
    List<String> hides = const [],
    Locale locale = const Locale('pl'),
  }) => _withRealShadows(() async {
    final captureKey = GlobalKey();
    await _render(
      tester,
      captureKey: captureKey,
      locale: locale,
      size: Size(width, height),
      // Under high contrast the app hands MaterialApp its high-contrast
      // twins (lib/app/app.dart); the frame uses the same theme.
      theme: switch ((light, highContrast)) {
        (true, true) => AppTheme.lightHighContrastTheme,
        (false, true) => AppTheme.darkHighContrastTheme,
        (true, false) => AppTheme.lightTheme,
        (false, false) => AppTheme.darkTheme,
      },
      child: child,
      textScale: textScale,
      highContrast: highContrast,
      // The view's pixel ratio matches the PNG's, so DPR-aware images
      // (the empty directory's logo decodes at `size × dpr`) are decoded
      // for the pixels they land on instead of being upscaled 2×. Layout
      // is in logical pixels and does not change.
      devicePixelRatio: width <= 768 ? 2 : 1,
    );
    if (before != null) await before(tester);
    // The state this frame is named for is really on screen (or really
    // absent): a join that silently failed must not produce a frame that
    // claims "connected".
    // A session card light is always in the tree; it counts as shown only
    // while it paints.
    for (final key in shows) {
      final light = ServerSessionLight.byKey(key);
      if (light != null) {
        expect(light.isLit(tester), isTrue, reason: '$name: $key not lit');
        continue;
      }
      expect(
        find.byKey(ValueKey(key)),
        findsWidgets,
        reason: '$name: $key missing',
      );
    }
    for (final key in hides) {
      final light = ServerSessionLight.byKey(key);
      if (light != null) {
        expect(light.isLit(tester), isFalse, reason: '$name: $key lit');
        continue;
      }
      expect(find.byKey(ValueKey(key)), findsNothing, reason: '$name: $key');
    }
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
  });

  void frame(
    String screen,
    String state, {
    required (double, double) size,
    required bool light,
    required Widget Function() child,
    double text = 1,
    bool highContrast = false,
    Future<void> Function(WidgetTester tester)? before,
    String? sheetState,
    List<String> shows = const [],
    List<String> hides = const [],
    String language = 'pl',
    Future<void> Function(WidgetTester tester, String name)? beforeNamed,
  }) {
    final (width, height) = size;
    final name = _name(screen, width, light, text, state, language: language);
    testWidgets(name, (tester) async {
      await capture(
        tester,
        name: name,
        width: width,
        height: height,
        light: light,
        textScale: text,
        highContrast: highContrast,
        child: child(),
        before: beforeNamed == null
            ? before
            : (tester) async {
                if (before != null) await before(tester);
                await beforeNamed(tester, name);
              },
        shows: shows,
        hides: hides,
        locale: Locale(language),
        sheetName: sheetState == null
            ? null
            : _name(
                'workspace-sheet',
                width,
                light,
                text,
                sheetState,
                language: language,
              ),
      );
    });
  }

  for (final light in _themes) {
    for (final size in _sizes) {
      final phone = size.$1 < 768;
      for (final text in const [1.0, 2.0]) {
        // The directory: one column on a phone, pairs from 768 up.
        frame(
          'directory',
          'populated',
          size: size,
          light: light,
          text: text,
          child: _directory,
        );
        // The live workspace, and on a phone its `Kanały` sheet.
        frame(
          'workspace',
          'live',
          size: size,
          light: light,
          text: text,
          child: _workspace,
          sheetState: phone ? 'live' : null,
          shows: const ['server-session-glow', 'server-live-lamp'],
        );
      }
      frame(
        'directory',
        'empty',
        size: size,
        light: light,
        child: () => _directory(servers: const []),
        shows: const ['servers-empty-logo'],
      );
      frame(
        'workspace',
        'quiet',
        size: size,
        light: light,
        child: () => _workspace(live: false),
        hides: const ['server-session-glow', 'server-live-lamp'],
      );
      final connector = FakeServerMediaConnector();
      frame(
        'workspace',
        'connected',
        size: size,
        light: light,
        child: () => _workspace(connector: connector),
        before: (tester) => _joinWithRoster(tester, connector),
        shows: _connectedKeys,
        hides: const ['server-session-glow'],
      );
    }

    for (final size in _phoneAndDesktop) {
      for (final text in const [1.0, 2.0]) {
        frame(
          'directory',
          'long',
          size: size,
          light: light,
          text: text,
          child: () => _directory(servers: _longServers()),
        );
      }
      final connector = FakeServerMediaConnector();
      frame(
        'workspace',
        'connected',
        size: size,
        light: light,
        text: 2,
        child: () => _workspace(connector: connector),
        before: (tester) => _joinWithRoster(tester, connector),
        shows: _connectedKeys,
        hides: const ['server-session-glow'],
      );
      frame(
        'workspace',
        'held',
        size: size,
        light: light,
        child: () => _workspace(held: true),
        hides: const ['server-session-glow'],
      );
      frame(
        'workspace',
        'admission',
        size: size,
        light: light,
        child: _admission,
        shows: const ['server-public-admission', 'server-public-join'],
      );
      frame(
        'workspace',
        'invite',
        size: size,
        light: light,
        child: () => _workspace(live: false, justCreated: true),
        shows: const ['server-invite-introduction'],
      );
      for (final type in ServerType.values) {
        frame(
          'template-${type.name}',
          'live',
          size: size,
          light: light,
          child: () => _template(type),
          shows: const ['server-session-glow', 'server-session-corner'],
        );
      }
      // Spec §13 (B4): the four live surfaces beside the friends session
      // card, quiet and in the conversation (the friends card is the
      // `workspace` quiet / connected frames above).
      for (final type in _otherTemplates) {
        frame(
          'template-${type.name}',
          'quiet',
          size: size,
          light: light,
          child: () => _template(type, live: false),
          hides: const [
            'server-session-glow',
            'server-session-corner',
            'server-session-tint',
          ],
        );
        final connector = FakeServerMediaConnector();
        frame(
          'template-${type.name}',
          'connected',
          size: size,
          light: light,
          child: () => _template(type, connector: connector),
          before: (tester) => _joinWithRoster(tester, connector),
          shows: const ['server-session-tint', 'server-conversation-dock'],
          hides: const ['server-session-glow', 'server-session-corner'],
        );
      }
    }

    frame(
      'directory',
      'focus',
      size: _sizes.last,
      light: light,
      child: _directory,
      before: _focusFirstRow,
    );
  }

  // System high contrast: no gradient, tint or glow; `borderStrong` edges.
  frame(
    'workspace',
    'live-hc',
    size: _sizes.first,
    light: false,
    highContrast: true,
    child: _workspace,
    shows: const ['server-live-lamp'],
    hides: const ['server-session-glow', 'server-session-corner'],
  );
  final hcConnector = FakeServerMediaConnector();
  frame(
    'workspace',
    'connected-hc',
    size: _sizes.last,
    light: true,
    highContrast: true,
    child: () => _workspace(connector: hcConnector),
    before: (tester) => _joinWithRoster(tester, hcConnector),
    // High contrast keeps the accent edge and drops the tint and every glow.
    shows: [
      for (final key in _connectedKeys)
        if (key != 'server-session-tint') key,
    ],
    hides: const ['server-session-tint', 'server-session-glow'],
  );
  frame(
    'directory',
    'populated-hc',
    size: _sizes.last,
    light: true,
    highContrast: true,
    child: _directory,
  );
  // One connected high-contrast frame per other template: the solid
  // `audioAccent` edge, no tint and no glow.
  for (final type in _otherTemplates) {
    final connector = FakeServerMediaConnector();
    frame(
      'template-${type.name}',
      'connected-hc',
      size: _sizes.first,
      light: false,
      highContrast: true,
      child: () => _template(type, connector: connector),
      before: (tester) => _joinWithRoster(tester, connector),
      shows: const ['server-conversation-dock'],
      hides: const [
        'server-session-tint',
        'server-session-glow',
        'server-session-corner',
      ],
    );
  }

  _reviewRoundFrames(frame);
}

typedef _Frame =
    void Function(
      String screen,
      String state, {
      required (double, double) size,
      required bool light,
      required Widget Function() child,
      double text,
      bool highContrast,
      Future<void> Function(WidgetTester tester)? before,
      String? sheetState,
      List<String> shows,
      List<String> hides,
      String language,
      Future<void> Function(WidgetTester tester, String name)? beforeNamed,
    });

/// The review round's frames (accessibility A11Y-1 / A11Y-2): the states
/// the first matrix never rendered.
void _reviewRoundFrames(_Frame frame) {
  const muted = ['server-conversation-dock', 'server-dock-microphone'];
  for (final light in _themes) {
    for (final size in _phoneAndDesktop) {
      final phone = size.$1 < 768;
      // The neutral glass controls: microphone off, headphones deafened.
      for (final text in const [1.0, 2.0]) {
        final connector = FakeServerMediaConnector();
        frame(
          'workspace',
          'connected-muted',
          size: size,
          light: light,
          text: text,
          child: () => _workspace(connector: connector),
          before: (tester) => _joinMuted(tester, connector),
          shows: muted,
        );
      }
      // Keyboard focus on each lit and neutral action.
      frame(
        'workspace',
        'focus-join',
        size: size,
        light: light,
        child: _workspace,
        beforeNamed: (tester, name) => _focusKey(tester, name, 'server-join'),
      );
      if (phone) {
        frame(
          'workspace',
          'focus-channels',
          size: size,
          light: light,
          child: _workspace,
          beforeNamed: (tester, name) =>
              _focusKey(tester, name, 'server-open-channels'),
        );
        // On a phone `Zaproś` lives in the `Kanały` sheet.
        frame(
          'workspace-sheet',
          'focus-invite',
          size: size,
          light: light,
          child: _workspace,
          beforeNamed: (tester, name) async {
            await tester.tap(
              find.byKey(const ValueKey('server-open-channels')),
            );
            await _settle(tester);
            await _focusKey(tester, name, 'server-invite-action');
          },
        );
      } else {
        frame(
          'workspace',
          'focus-invite',
          size: size,
          light: light,
          child: _workspace,
          beforeNamed: (tester, name) =>
              _focusKey(tester, name, 'server-invite-action'),
        );
      }
      final barConnector = FakeServerMediaConnector();
      frame(
        'workspace',
        'connected-muted-focus',
        size: size,
        light: light,
        child: () => _workspace(connector: barConnector),
        before: (tester) => _joinMuted(tester, barConnector),
        beforeNamed: (tester, name) =>
            _focusKey(tester, name, 'server-dock-microphone'),
        shows: muted,
      );
      frame(
        'directory',
        'focus-actions',
        size: size,
        light: light,
        child: _directory,
        beforeNamed: (tester, name) =>
            _focusKey(tester, name, 'server-directory-actions-s'),
      );
      // The public join while it runs.
      frame(
        'workspace',
        'admission-busy',
        size: size,
        light: light,
        child: _admissionPending,
        before: (tester) async {
          await tester.tap(find.byKey(const ValueKey('server-public-join')));
          await tester.pump();
          // Past the tap's own splash, into the spinner's sweep.
          for (var i = 0; i < 7; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
        shows: const ['server-public-join'],
      );
    }
    // A11Y-1: the muted microphone focused under high contrast — the whole
    // 2 px ring, not a ring half covered by the resting edge.
    final hcConnector = FakeServerMediaConnector();
    frame(
      'workspace',
      'connected-muted-focus-hc',
      size: _sizes.last,
      light: light,
      highContrast: true,
      child: () => _workspace(connector: hcConnector),
      before: (tester) => _joinMuted(tester, hcConnector),
      beforeNamed: (tester, name) =>
          _focusKey(tester, name, 'server-dock-microphone'),
      shows: muted,
    );
  }

  // More high contrast: the Pearl live card, the Dark directory, the muted
  // bar and 200 % text.
  frame(
    'workspace',
    'live-hc',
    size: _sizes.first,
    light: true,
    highContrast: true,
    child: _workspace,
    hides: const ['server-session-glow', 'server-session-corner'],
  );
  frame(
    'workspace',
    'live-hc',
    size: _sizes.first,
    light: false,
    text: 2,
    highContrast: true,
    child: _workspace,
    hides: const ['server-session-glow', 'server-session-corner'],
  );
  for (final size in _phoneAndDesktop) {
    frame(
      'directory',
      'populated-hc',
      size: size,
      light: false,
      highContrast: true,
      child: _directory,
    );
    final connector = FakeServerMediaConnector();
    frame(
      'workspace',
      'connected-muted-hc',
      size: size,
      light: false,
      highContrast: true,
      child: () => _workspace(connector: connector),
      before: (tester) => _joinMuted(tester, connector),
      shows: muted,
    );
  }

  // RTL (Arabic) and the narrowest phone at 200 %.
  frame(
    'workspace',
    'live',
    size: _sizes.first,
    light: false,
    language: 'ar',
    child: _workspace,
    shows: const ['server-session-glow', 'server-live-lamp'],
  );
  frame(
    'workspace',
    'live',
    size: (320, 640),
    light: false,
    text: 2,
    child: _workspace,
    sheetState: 'live',
    shows: const ['server-session-glow'],
  );
}
