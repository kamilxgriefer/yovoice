// Developer-only VISUAL capture for the Servers tab's board (owner's choice
// 2026-10-03: option A of sheet `2_hub`, without the "Na żywo" section;
// ADR-239). The real `ServersScreen` over the test repository: "Twoje
// serwery" with the LIVE lamp, "Serwery publiczne", the first-run block, the
// "+" sheet, "Dołącz z linku" and the name filter.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/servers_board_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-10-03/w42/hub/ unless
// `--dart-define=YO_CAPTURE_DIR=<absolute dir>` points elsewhere; layout
// exceptions are recorded in `_exceptions.log` next to the frames. Frames are
// named `board_<width>_<dark|pearl>_<locale>_<text>_<state>`:
//
// * 390 × 844 inside the phone shell (the six-tab dock), 768 × 1024 with the
//   dock, 1440 × 900 beside the real `DesktopSidebar`;
// * Dark and Pearl; 200 % text; right-to-left spot frames (Polish copy under
//   `TextDirection.rtl` and a real Arabic frame);
// * populated (one server live), scrolled to the public cards, a brand-new
//   account, no public servers, a failed public listing, many servers
//   ("Pokaż wszystkie"), the "+" sheet, the link sheet, the filter, a row
//   under the pointer (the `…` button) and a long-locale spot frame.
//
// `--dart-define=YO_BOARD_ONLY=<prefix,prefix>` renders only matching frames.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_test_support.dart';
import 'support/material_icons_font.dart';

const _out = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-10-03/w42/hub',
);
const _only = String.fromEnvironment('YO_BOARD_ONLY');

final _exceptions = File('$_out/_exceptions.log');

const _phone = Size(390, 844);
const _tablet = Size(768, 1024);
const _desktop = Size(1440, 900);
const _phoneSafe = EdgeInsets.only(top: 47, bottom: 34);

Future<void> _fonts() async {
  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ),
      ),
    );
  await inter.load();
  await loadMaterialIconsFont();
  // The app's first fallback family, so the Arabic frame shows real glyphs
  // where the capture host has the system face (a Mac); elsewhere the frame
  // still proves the mirroring.
  final arabic = File('/System/Library/Fonts/SFArabic.ttf');
  if (arabic.existsSync()) {
    final loader = FontLoader('Noto Sans Arabic')
      ..addFont(Future.value(ByteData.sublistView(arabic.readAsBytesSync())));
    await loader.load();
  }
}

// ------------------------------------------------------------------ fixtures

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  ServerPrivacy? privacy,
  ServerMemberRole? role,
  String owner = 'owner',
}) => Server(
  id: id,
  name: name,
  description: '',
  ownerId: owner,
  type: type,
  privacy:
      privacy ??
      (type == ServerType.family
          ? ServerPrivacy.inviteOnly
          : ServerPrivacy.private),
  memberCount: members,
  schemaVersion: 1,
  activationState: 'active',
  status: 'active',
  directoryRole: role,
);

/// The sample account's four servers (the names on the owner's sheet).
List<Server> _mine() => [
  _server(
    's',
    'Nocne Granie',
    ServerType.community,
    members: 128,
    privacy: ServerPrivacy.public,
    role: ServerMemberRole.owner,
  ),
  _server('p', 'Paczka z liceum', ServerType.friends, members: 12),
  _server('r', 'Rodzina Nowaków', ServerType.family, members: 6),
  _server('f', 'Studio Fala', ServerType.podcast, members: 42),
];

/// Thirteen servers: enough for "Pokaż wszystkie" at every width.
List<Server> _many() => [
  ..._mine(),
  _server('m1', 'Klub książki', ServerType.community, members: 184),
  _server('m2', 'Biuro projektowe', ServerType.company, members: 23),
  _server('m3', 'Wtorkowe planszówki', ServerType.friends, members: 9),
  _server('m4', 'Podcast o górach', ServerType.podcast, members: 310),
  _server('m5', 'Sąsiedzi z Lipowej', ServerType.community, members: 47),
  _server('m6', 'Ekipa z siłowni', ServerType.friends, members: 5),
  _server('m7', 'Kino domowe', ServerType.friends, members: 4),
  _server('m8', 'Warsztat Rowerowy', ServerType.company, members: 11),
  _server('m9', 'Chór kameralny', ServerType.community, members: 31),
];

List<Server> _public() => [
  for (final (id, name, members, type) in const [
    ('pub-f', 'Fotografia po godzinach', 312, ServerType.community),
    ('pub-j', 'Języki przy kawie', 89, ServerType.community),
    ('pub-k', 'Kuchnia bez spiny', 57, ServerType.community),
    ('pub-b', 'Biegamy razem', 41, ServerType.community),
    ('pub-n', 'Nocna audycja z winyli', 26, ServerType.podcast),
  ])
    _server(
      id,
      name,
      type,
      members: members,
      privacy: ServerPrivacy.public,
      owner: 'someone',
    ),
];

/// A live stage in `s` ("Nocne Granie"): the projection the lamp reads.
List<ServerChannel> _channels() => [
  const ServerChannel(
    id: 'general',
    serverId: 's',
    name: 'ogólny',
    kind: ServerChannelKind.text,
    schemaVersion: 1,
  ),
  ServerChannel(
    id: 'stage',
    serverId: 's',
    name: 'Scena',
    kind: ServerChannelKind.stage,
    position: 1,
    roomId: 'room-stage',
    experience: RoomExperience.broadcast,
    mediaMode: ServerMediaMode.video,
    schemaVersion: 1,
    liveness: ServerChannelLiveness(
      isLive: true,
      startedAt: DateTime(2026, 10, 3, 21, 4),
    ),
  ),
];

class _FailingPublicRepository extends TestServerRepository {
  @override
  Stream<List<Server>> watchPublicServers({
    int limit = ServerService.publicDirectoryReadLimit,
  }) => Stream<List<Server>>.error(StateError('permission-denied'));
}

TestServerRepository _repository({
  List<Server>? mine,
  List<Server>? public,
  bool live = true,
  bool publicFails = false,
}) => (publicFails ? _FailingPublicRepository() : TestServerRepository())
  ..servers = mine ?? _mine()
  ..publicServers = public ?? _public()
  ..channels = live ? _channels() : const [];

Widget _board(TestServerRepository repository) => ServersScreen(
  key: UniqueKey(),
  isRootTab: true,
  repository: repository,
  connector: FakeServerMediaConnector(),
);

// --------------------------------------------------------------------- shell

Widget _dock() => YoFloatingNavigationDock(
  selectedTabIndex: 13,
  roomsTabIndex: 13,
  momentsTabIndex: 5,
  contentTabIndex: 14,
  unreadConversationCount: 2,
  onDestinationSelected: (_) {},
  onVoicePressed: () {},
  onMorePressed: () {},
);

late ProfileService _profiles;

Future<void> _seedBackends() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('owner').set(<String, dynamic>{
    'uid': 'owner',
    'displayName': 'Kamil',
    'username': 'kamil',
  });
  _profiles = ProfileService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'owner', displayName: 'Kamil'),
    ),
  );
}

/// The shell a width gets in the app: the dock under the tab below the
/// desktop breakpoint, the real rail beside the slot from it.
Widget _shell(Widget board, Size size) => size.width >= 1100
    ? Builder(
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Row(
            children: [
              DesktopSidebar(
                active: DesktopNavItem.servers,
                showContent: true,
                unreadConversationCount: 2,
                unreadNotificationCount: 0,
                onSelect: (_) {},
                onCreateRoom: () {},
                onCreateMoment: () {},
                onOpenProfile: () {},
                onOpenProfileSettings: () {},
                profileService: _profiles,
              ),
              Expanded(child: board),
            ],
          ),
        ),
      )
    : Scaffold(body: board, bottomNavigationBar: _dock());

// ------------------------------------------------------------------- capture

double _ratio(Size size) => size.width <= 768 ? 2 : 1;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _shoot(
  WidgetTester tester,
  GlobalKey captureKey,
  String name,
  Size size,
) async {
  await _decodeImages(tester);
  Object? failure;
  while ((failure = tester.takeException()) != null) {
    _exceptions.writeAsStringSync(
      '$name :: ${failure.toString().split('\n').take(2).join(' | ')}\n',
      mode: FileMode.append,
    );
  }
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio(size));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote $_out/$name.png');
    } finally {
      image.dispose();
    }
  });
}

String _name(
  Size size,
  String state, {
  bool light = false,
  double textScale = 1,
  String locale = 'pl',
}) =>
    'board_${size.width.toInt()}_${light ? 'pearl' : 'dark'}_${locale}_'
    '${(textScale * 100).round()}_$state';

/// One frame (and any [more] frames after further steps).
void _scene(
  String state, {
  required TestServerRepository Function() repository,
  Size size = _phone,
  bool light = false,
  double textScale = 1,
  String locale = 'pl',
  TextDirection? direction,
  Future<void> Function(WidgetTester tester)? before,
  List<(String, Future<void> Function(WidgetTester tester))> more = const [],
}) {
  final name = _name(
    size,
    state,
    light: light,
    textScale: textScale,
    locale: locale,
  );
  if (_only.isNotEmpty && !_only.split(',').any(name.contains)) return;
  testWidgets(name, timeout: const Timeout(Duration(seconds: 90)), (
    tester,
  ) async {
    // The test framework paints shadows as hard blocks; a capture wants the
    // real blur (restored below, the framework verifies it).
    debugDisableShadows = false;
    final captureKey = GlobalKey();
    final ratio = _ratio(size);
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
    final safe = size.width < 700 ? _phoneSafe : EdgeInsets.zero;
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(locale),
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final media = MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(textScale),
                  padding: safe,
                  viewPadding: safe,
                ),
                child: child!,
              );
              return direction == null
                  ? media
                  : Directionality(textDirection: direction, child: media);
            },
            home: _shell(_board(repository()), size),
          ),
        ),
      );
      await _settle(tester);
      if (before != null) {
        await before(tester);
        await _settle(tester);
      }
      await _shoot(tester, captureKey, name, size);
      for (final (suffix, step) in more) {
        await step(tester);
        await _settle(tester);
        await _shoot(tester, captureKey, '$name-$suffix', size);
      }
    } finally {
      debugServerVoiceDeviceOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.reset();
      debugDisableShadows = true;
    }
  });
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  ScrollableState? board;
  var tallest = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis != Axis.vertical) continue;
    final height = (element.renderObject! as RenderBox).size.height;
    if (height > tallest) {
      tallest = height;
      board = state;
    }
  }
  for (var i = 0; i < 4; i++) {
    board!.position.jumpTo(board.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
}

void main() {
  setUpAll(() async {
    await _fonts();
    await _seedBackends();
    Directory(_out).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  // The chosen frames at 390 / 768 / 1440, Dark and Pearl.
  for (final size in const [_phone, _tablet, _desktop]) {
    for (final light in const [false, true]) {
      _scene(
        'populated',
        size: size,
        light: light,
        repository: _repository,
        more: [('scrolled', _scrollToEnd)],
      );
      _scene(
        'newcomer',
        size: size,
        light: light,
        repository: () => _repository(mine: const [], live: false),
      );
    }
    _scene(
      'populated',
      size: size,
      textScale: 2,
      repository: _repository,
      more: [('scrolled', _scrollToEnd)],
    );
    _scene(
      'newcomer',
      size: size,
      textScale: 2,
      repository: () => _repository(mine: const [], live: false),
    );
    _scene(
      'populated-rtl',
      size: size,
      direction: TextDirection.rtl,
      repository: _repository,
      more: [('scrolled', _scrollToEnd)],
    );
    _scene(
      'no-public',
      size: size,
      repository: () => _repository(public: const []),
    );
    _scene(
      'many',
      size: size,
      repository: () => _repository(mine: _many()),
      more: [
        (
          'expanded',
          (tester) async {
            await tester.ensureVisible(
              find.byKey(const ValueKey('servers-show-all')),
            );
            await _tap(tester, 'servers-show-all');
          },
        ),
      ],
    );
    _scene(
      'add-sheet',
      size: size,
      repository: _repository,
      before: (tester) => _tap(tester, 'servers-add'),
    );
    _scene(
      'join-link',
      size: size,
      repository: _repository,
      before: (tester) async {
        await _tap(tester, 'servers-add');
        await _settle(tester);
        await _tap(tester, 'servers-join-link');
      },
      more: [
        (
          'invalid',
          (tester) async {
            await tester.enterText(
              find.byKey(const ValueKey('servers-join-link-field')),
              'https://example.com/zaproszenie',
            );
            await _tap(tester, 'servers-join-link-open');
          },
        ),
      ],
    );
    _scene(
      'search',
      size: size,
      repository: _repository,
      before: (tester) async {
        if (find
            .byKey(const ValueKey('servers-search'))
            .evaluate()
            .isNotEmpty) {
          await _tap(tester, 'servers-search');
          await _settle(tester);
        }
        await tester.enterText(
          find.byKey(const ValueKey('servers-search-field')),
          'fa',
        );
      },
      more: [
        (
          'none',
          (tester) => tester.enterText(
            find.byKey(const ValueKey('servers-search-field')),
            'zzz',
          ),
        ),
      ],
    );
  }

  // States that only need one width.
  _scene('public-error', repository: () => _repository(publicFails: true));
  _scene(
    'public-error',
    size: _desktop,
    repository: () => _repository(publicFails: true),
  );
  _scene(
    'public-admission',
    repository: () => _repository()..myRole = null,
    before: (tester) async {
      await _scrollToEnd(tester);
      await _tap(tester, 'server-public-pub-f');
    },
  );
  _scene(
    'public-admission',
    size: _desktop,
    repository: () => _repository()..myRole = null,
    before: (tester) => _tap(tester, 'server-public-pub-f'),
  );

  // A row under the pointer: the `…` button takes the chevron's place.
  for (final light in const [false, true]) {
    _scene(
      'row-hover',
      size: _desktop,
      light: light,
      repository: _repository,
      before: (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('server-directory-p'))),
        );
      },
    );
  }
  _scene(
    'row-focus',
    size: _desktop,
    repository: _repository,
    before: (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final row = find.byKey(const ValueKey('server-directory-p'));
      Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(Row)).first,
        ),
      ).requestFocus();
    },
  );

  // Real locales: Arabic for right-to-left, and the two longest label sets.
  for (final locale in const ['ar', 'de', 'fi', 'ru']) {
    _scene(
      'populated',
      locale: locale,
      repository: _repository,
      more: [('scrolled', _scrollToEnd)],
    );
    _scene(
      'newcomer',
      locale: locale,
      repository: () => _repository(mine: const [], live: false),
    );
    _scene(
      'add-sheet',
      locale: locale,
      repository: _repository,
      before: (tester) => _tap(tester, 'servers-add'),
    );
  }
}
