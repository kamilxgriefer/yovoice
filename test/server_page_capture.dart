// Developer-only VISUAL capture for the server page (`Strona serwera`,
// ADR-240): the page a server opens on, at the shipping widths.
//
// Not a golden test: platform font rasterisation is not stable enough for a
// pixel baseline. It renders the real workspace with the real Inter face and
// writes PNGs so a human can look at what the code actually draws and compare
// it with the chosen row of the option sheet (`2_serverHome.jpg`, option A).
// Run explicitly:
//
//   flutter test test/server_page_capture.dart
//
// PNGs land in yovoice-evidence/2026-10-03/w42/serverpage/ unless
// `--dart-define=YO_CAPTURE_DIR=/path` names another directory.
//
// Frames (`page_<width>_<theme>_pl_<text>_<state>`):
//
// * A1 — a community seen by its owner while the stage is quiet: `Nadaj LIVE`,
//   `Zaproś`, the share glyph and the `Następny LIVE` card of the next event;
// * A2 — the same server seen by a member while the stage is LIVE, at the
//   top and scrolled to the sections and `Wszystkie kanały`;
// * A3 — a friends server: the lounge is the main thing;
// * A2 at 768 (rail + channel column + the page) and at 1440 inside the
//   desktop shell's composition (the real `DesktopSidebar`, then rail,
//   channel column, the page and the `Czat · #ogólny` context panel);
// * Pearl, 200 % text, a 320 px phone and a right-to-left spot frame;
// * the family (`Dom` board as the main thing), podcast (the next episode
//   with its real reminder) and company (the meeting) pages;
// * the states around the page: a quiet stage without an event, a held
//   server, the lounge joined in place, a channel opened from the page with
//   its way back, the `Wszystkie kanały` sheet, the `⋯` menu and the page a
//   non-member of a public server sees (`Dołącz`).
//
// * another language: German (long labels in the action row, the family
//   board and the channel column's group headings) and Arabic in its own
//   script, right to left by locale. The Arabic frames need an Arabic face;
//   the harness registers the host's `SFArabic.ttf` under the theme's own
//   fallback family (`Noto Sans Arabic`) and skips those frames on a host
//   that has none, rather than writing tofu.
//
// Every frame renders with Reduce Motion on and with real blurred shadows.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';

import 'server_page_support.dart';
import 'server_test_support.dart';

const _outputDirectory = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-10-03/w42/'
      'serverpage',
);

final _exceptions = File('$_outputDirectory/_exceptions.log');

String get _fontRoot {
  final candidates = [
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
  // The theme falls back to `Noto Sans Arabic` for Arabic script
  // (`AppTypography.fontFamilyFallback`); a test host has no such family, so
  // the system's Arabic face stands in under that name.
  final arabic = _arabicFace;
  if (arabic != null) {
    final loader = FontLoader('Noto Sans Arabic')
      ..addFont(Future.value(_read(arabic)));
    await loader.load();
  }
}

/// A system Arabic face, or null on a host without one.
String? get _arabicFace => const [
  '/System/Library/Fonts/SFArabic.ttf',
  '/System/Library/Fonts/Supplemental/Tahoma.ttf',
  '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
].where((path) => File(path).existsSync()).firstOrNull;

double _pixelRatio(double width) => width <= 768 ? 2 : 1;

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle();
  } on Object {
    for (var pump = 0; pump < 6; pump++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
}

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  required bool light,
  double textScale = 1,
  TextDirection? direction,
  Locale locale = const Locale('pl'),
}) async {
  final ratio = _pixelRatio(size.width);
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
  addTearDown(() => debugServerVoiceDeviceOverride = null);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
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

String _name(
  double width,
  bool light,
  double textScale,
  String state, {
  String screen = 'page',
  String language = 'pl',
}) =>
    '${screen}_${width.toInt()}_${light ? 'pearl' : 'dark'}_${language}_'
    '${(textScale * 100).round()}_$state';

void _captureWidgets(String name, WidgetTesterCallback body) =>
    testWidgets(name, (tester) async {
      debugDisableShadows = false;
      try {
        await body(tester);
      } finally {
        debugDisableShadows = true;
      }
    });

/// The account's other servers, for the rail and the phone sheet.
List<Server> _others() => [
  pageServer(ServerType.friends, id: 'p'),
  pageServer(ServerType.family, id: 'r'),
  pageServer(ServerType.company, id: 'f'),
];

TestServerRepository _community({
  required ServerMemberRole role,
  bool live = false,
  bool events = true,
}) => pageRepository(
  ServerType.community,
  role: role,
  live: live ? pageLive : ServerChannelLiveness.idle,
  others: _others(),
  events: events
      ? [
          pageEvent(
            ServerType.community,
            id: 'e1',
            title: 'Wieczór pytań',
            startsAt: pageDay(1, 20),
          ),
          pageEvent(
            ServerType.community,
            id: 'e2',
            title: 'Turniej drużynowy',
            startsAt: pageDay(3, 19),
          ),
        ]
      : const [],
);

/// The chosen A3 frame carries `Zaproś`, which a private friends server
/// gives to a role with invite authority — so the frame is its owner's.
TestServerRepository _friends() => pageRepository(
  ServerType.friends,
  role: ServerMemberRole.owner,
  events: [
    pageEvent(
      ServerType.friends,
      id: 'e1',
      title: 'Ognisko u Kuby',
      startsAt: pageDay(7, 18),
    ),
  ],
);

TestServerRepository _family() => pageRepository(
  ServerType.family,
  events: [
    pageEvent(
      ServerType.family,
      id: 'e1',
      title: 'Obiad u babci',
      startsAt: pageDay(2, 14),
    ),
  ],
);

TestServerRepository _podcast({ServerMemberRole? role}) => pageRepository(
  ServerType.podcast,
  role: role ?? ServerMemberRole.member,
  events: [
    pageEvent(
      ServerType.podcast,
      id: 'e1',
      title: 'Rozmowa o nocnych pociągach',
      startsAt: pageDay(1, 21),
    ),
  ],
);

TestServerRepository _company() =>
    pageRepository(ServerType.company, role: ServerMemberRole.member);

/// A few real messages for the desktop context panel, and the viewer's own
/// membership row: without it the thread resolves to "read-only for your
/// role" and the frame would show a member who cannot write in `ogólny`.
Future<FakeFirebaseFirestore> _chat() async {
  final db = FakeFirebaseFirestore();
  await db.collection('clubs').doc('s').set(<String, dynamic>{
    'ownerId': 'owner',
  });
  await db.collection('clubs').doc('s').collection('members').doc('owner').set(
    <String, dynamic>{'role': 'owner'},
  );
  final messages = db
      .collection('clubs')
      .doc('s')
      .collection('channels')
      .doc('general')
      .collection('messages');
  var minute = 41;
  for (final (author, name, text) in const [
    ('kuba', 'Kuba Wiśniewski', 'Ktoś gra dziś wieczorem?'),
    ('ola', 'Ola Nowak', 'Tak! Startuję o 21:00, wpadajcie na scenę.'),
    ('maja', 'Maja Zielińska', 'Będę, tylko skończę kolację.'),
    ('kuba', 'Kuba Wiśniewski', 'To ja rozstawiam bazę od północy.'),
  ]) {
    await messages.add(<String, dynamic>{
      'senderId': author,
      'senderName': name,
      'content': text,
      'sentAt': DateTime(2026, 10, 3, 20, minute),
    });
    minute += 3;
  }
  return db;
}

/// The viewer's own membership row and nothing else: the desktop context
/// panel of a server without seeded messages then shows the empty thread
/// with its composer, as a member sees it, instead of "read-only for your
/// role" (which is what a missing row resolves to).
Future<FakeFirebaseFirestore> _membership(ServerMemberRole role) async {
  final db = FakeFirebaseFirestore();
  await db.collection('clubs').doc('s').set(<String, dynamic>{
    'ownerId': role == ServerMemberRole.owner ? 'owner' : 'somebody-else',
  });
  await db.collection('clubs').doc('s').collection('members').doc('owner').set(
    <String, dynamic>{'role': role.name},
  );
  return db;
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required double width,
    required double height,
    required Widget child,
    bool light = false,
    double textScale = 1,
    TextDirection? direction,
    Locale locale = const Locale('pl'),
    Future<void> Function(WidgetTester tester)? before,
  }) async {
    final captureKey = GlobalKey();
    await _render(
      tester,
      captureKey: captureKey,
      size: Size(width, height),
      light: light,
      child: child,
      textScale: textScale,
      direction: direction,
      locale: locale,
    );
    if (before != null) await before(tester);
    await _shoot(tester, captureKey: captureKey, name: name, width: width);
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('server-page')),
      const Offset(0, -420),
    );
    await _settle(tester);
  }

  // ------------------------------------------------- the chosen frames, A1–A3
  for (final light in [false, true]) {
    final a1 = _name(390, light, 1, 'A1-community-owner-offline');
    _captureWidgets(a1, (tester) async {
      await capture(
        tester,
        name: a1,
        width: 390,
        height: 844,
        light: light,
        child: pageWorkspace(_community(role: ServerMemberRole.owner)),
      );
    });

    final a2 = _name(390, light, 1, 'A2-community-member-live');
    _captureWidgets(a2, (tester) async {
      await capture(
        tester,
        name: a2,
        width: 390,
        height: 844,
        light: light,
        child: pageWorkspace(
          _community(role: ServerMemberRole.member, live: true),
        ),
      );
    });

    final a2s = _name(390, light, 1, 'A2-community-member-live-scrolled');
    _captureWidgets(a2s, (tester) async {
      await capture(
        tester,
        name: a2s,
        width: 390,
        height: 844,
        light: light,
        child: pageWorkspace(
          _community(role: ServerMemberRole.member, live: true),
        ),
        before: scrollToEnd,
      );
    });

    final a3 = _name(390, light, 1, 'A3-friends');
    _captureWidgets(a3, (tester) async {
      await capture(
        tester,
        name: a3,
        width: 390,
        height: 844,
        light: light,
        child: pageWorkspace(_friends()),
      );
    });

    final tablet = _name(768, light, 1, 'A2-community-member-live');
    _captureWidgets(tablet, (tester) async {
      await capture(
        tester,
        name: tablet,
        width: 768,
        height: 1024,
        light: light,
        child: pageWorkspace(
          _community(role: ServerMemberRole.owner, live: true),
        ),
      );
    });

    final desktop = _name(1440, light, 1, 'A2-community-member-live');
    _captureWidgets(desktop, (tester) async {
      final profiles = FakeFirebaseFirestore();
      await profiles.collection('users').doc('owner').set(<String, dynamic>{
        'uid': 'owner',
        'displayName': 'Kamil',
        'username': 'kamil',
      });
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner', displayName: 'Kamil'),
      );
      final chat = await _chat();
      await capture(
        tester,
        name: desktop,
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
                  profileService: ProfileService(
                    firestore: profiles,
                    auth: auth,
                  ),
                ),
                Expanded(
                  child: pageWorkspace(
                    _community(role: ServerMemberRole.owner, live: true),
                    chat: pageChat(chat),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ------------------------------------------------------------ 200 % text
  for (final (state, repository) in [
    (
      'A1-community-owner-offline',
      () => _community(role: ServerMemberRole.owner),
    ),
    (
      'A2-community-member-live',
      () => _community(role: ServerMemberRole.member, live: true),
    ),
    ('A3-friends', _friends),
  ]) {
    final name = _name(390, false, 2, state);
    _captureWidgets(name, (tester) async {
      await capture(
        tester,
        name: name,
        width: 390,
        height: 844,
        textScale: 2,
        child: pageWorkspace(repository()),
      );
    });
    final scrolled = _name(390, false, 2, '$state-scrolled');
    _captureWidgets(scrolled, (tester) async {
      await capture(
        tester,
        name: scrolled,
        width: 390,
        height: 844,
        textScale: 2,
        child: pageWorkspace(repository()),
        before: (tester) async {
          await scrollToEnd(tester);
          await scrollToEnd(tester);
        },
      );
    });
  }

  for (final (width, height) in [(768.0, 1024.0), (1440.0, 900.0)]) {
    final name = _name(width, false, 2, 'A2-community-member-live');
    _captureWidgets(name, (tester) async {
      await capture(
        tester,
        name: name,
        width: width,
        height: height,
        textScale: 2,
        child: pageWorkspace(
          _community(role: ServerMemberRole.owner, live: true),
          chat: pageChat(await _chat()),
        ),
      );
    });
  }

  // ------------------------------------------------ narrow and right-to-left
  final narrow = _name(320, false, 1, 'A1-community-owner-offline');
  _captureWidgets(narrow, (tester) async {
    await capture(
      tester,
      name: narrow,
      width: 320,
      height: 700,
      child: pageWorkspace(_community(role: ServerMemberRole.owner)),
    );
  });

  final rtl = _name(390, false, 1, 'A1-community-owner-offline-rtl');
  _captureWidgets(rtl, (tester) async {
    await capture(
      tester,
      name: rtl,
      width: 390,
      height: 844,
      direction: TextDirection.rtl,
      child: pageWorkspace(_community(role: ServerMemberRole.owner)),
    );
  });

  final rtlWide = _name(1440, false, 1, 'A2-community-member-live-rtl');
  _captureWidgets(rtlWide, (tester) async {
    await capture(
      tester,
      name: rtlWide,
      width: 1440,
      height: 900,
      direction: TextDirection.rtl,
      // The same seeded conversation as the left-to-right desktop frame, so
      // the mirrored context panel shows messages and a composer rather than
      // an empty, read-only thread.
      child: pageWorkspace(
        _community(role: ServerMemberRole.owner, live: true),
        chat: pageChat(await _chat()),
      ),
    );
  });

  // ------------------------------------------------------ the other templates
  for (final (state, repository) in [
    ('family', _family),
    ('podcast-next-episode', _podcast),
    ('company', _company),
  ]) {
    for (final (width, height) in [
      (390.0, 844.0),
      (768.0, 1024.0),
      (1440.0, 900.0),
    ]) {
      final name = _name(width, false, 1, state);
      _captureWidgets(name, (tester) async {
        final fixture = repository();
        await capture(
          tester,
          name: name,
          width: width,
          height: height,
          child: pageWorkspace(
            fixture,
            chat: pageChat(await _membership(fixture.myRole!)),
          ),
        );
      });
    }
    final scrolled = _name(390, false, 1, '$state-scrolled');
    _captureWidgets(scrolled, (tester) async {
      await capture(
        tester,
        name: scrolled,
        width: 390,
        height: 844,
        child: pageWorkspace(repository()),
        before: (tester) async {
          await scrollToEnd(tester);
          if (state == 'family') await scrollToEnd(tester);
        },
      );
    });
  }

  final podcastLive = _name(390, false, 1, 'podcast-live');
  _captureWidgets(podcastLive, (tester) async {
    await capture(
      tester,
      name: podcastLive,
      width: 390,
      height: 844,
      child: pageWorkspace(
        pageRepository(
          ServerType.podcast,
          role: ServerMemberRole.member,
          live: pageLive,
        ),
      ),
    );
  });

  // The podcast's host: `Nadaj LIVE` with the stage's own glyph (an audio
  // studio is not a camera) beside the next episode.
  final podcastHost = _name(390, false, 1, 'podcast-host-quiet');
  _captureWidgets(podcastHost, (tester) async {
    await capture(
      tester,
      name: podcastHost,
      width: 390,
      height: 844,
      child: pageWorkspace(_podcast(role: ServerMemberRole.owner)),
    );
  });

  final familyPearl = _name(390, true, 1, 'family');
  _captureWidgets(familyPearl, (tester) async {
    await capture(
      tester,
      name: familyPearl,
      width: 390,
      height: 844,
      light: true,
      child: pageWorkspace(_family()),
    );
  });

  // -------------------------------------------------- states around the page
  final quiet = _name(390, false, 1, 'community-member-quiet-no-event');
  _captureWidgets(quiet, (tester) async {
    await capture(
      tester,
      name: quiet,
      width: 390,
      height: 844,
      child: pageWorkspace(
        _community(role: ServerMemberRole.member, events: false),
      ),
    );
  });

  final held = _name(390, false, 1, 'friends-held');
  _captureWidgets(held, (tester) async {
    await capture(
      tester,
      name: held,
      width: 390,
      height: 844,
      child: pageWorkspace(pageRepository(ServerType.friends, held: true)),
    );
  });

  for (final (width, height) in [(390.0, 844.0), (1440.0, 900.0)]) {
    final joined = _name(width, false, 1, 'friends-lounge-joined');
    _captureWidgets(joined, (tester) async {
      final connector = FakeServerMediaConnector();
      await capture(
        tester,
        name: joined,
        width: width,
        height: height,
        child: pageWorkspace(
          _friends(),
          connector: connector,
          chat: pageChat(await _membership(ServerMemberRole.owner)),
        ),
        before: (tester) async {
          await tester.tap(find.byKey(const ValueKey('server-join')));
          await _settle(tester);
          connector.links.single.setRoster(const [
            ServerMediaParticipant(
              identity: 'maja',
              name: 'Maja',
              isLocal: false,
              isSpeaking: true,
              isMicrophoneEnabled: true,
            ),
            ServerMediaParticipant(
              identity: 'owner',
              name: 'Kamil',
              isLocal: true,
              isMicrophoneEnabled: true,
            ),
          ]);
          await _settle(tester);
        },
      );
    });
  }

  final channel = _name(390, false, 1, 'channel-opened-from-page');
  _captureWidgets(channel, (tester) async {
    await capture(
      tester,
      name: channel,
      width: 390,
      height: 844,
      child: pageWorkspace(
        _community(role: ServerMemberRole.member, live: true),
        chat: pageChat(await _chat()),
      ),
      before: (tester) async {
        await scrollToEnd(tester);
        await tester.tap(
          find.byKey(const ValueKey('server-page-channel-general')),
        );
        await _settle(tester);
      },
    );
  });

  final sheet = _name(390, false, 1, 'all-channels-sheet');
  _captureWidgets(sheet, (tester) async {
    await capture(
      tester,
      name: sheet,
      width: 390,
      height: 844,
      child: pageWorkspace(
        _community(role: ServerMemberRole.owner, live: true),
      ),
      before: (tester) async {
        await scrollToEnd(tester);
        await scrollToEnd(tester);
        await tester.tap(find.byKey(const ValueKey('server-open-channels')));
        await _settle(tester);
      },
    );
  });

  final menu = _name(390, false, 1, 'more-menu');
  _captureWidgets(menu, (tester) async {
    await capture(
      tester,
      name: menu,
      width: 390,
      height: 844,
      child: pageWorkspace(_community(role: ServerMemberRole.owner)),
      before: (tester) async {
        await tester.tap(find.byKey(const ValueKey('server-page-more')));
        await _settle(tester);
      },
    );
  });

  // Channel and server management stay one step from the page.
  final settings = _name(390, false, 1, 'settings-from-menu');
  _captureWidgets(settings, (tester) async {
    await capture(
      tester,
      name: settings,
      width: 390,
      height: 844,
      child: pageWorkspace(_community(role: ServerMemberRole.owner)),
      before: (tester) async {
        await tester.tap(find.byKey(const ValueKey('server-page-more')));
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('server-page-menu-settings')),
        );
        await _settle(tester);
      },
    );
  });

  // Somebody who has not joined a public server yet: the same page, with
  // `Dołącz` as its one action and nothing a channel would show.
  for (final (width, height, light, scale) in [
    (390.0, 844.0, false, 1.0),
    (390.0, 844.0, true, 1.0),
    (390.0, 844.0, false, 2.0),
    (1440.0, 900.0, false, 1.0),
  ]) {
    final name = _name(width, light, scale, 'community-non-member');
    _captureWidgets(name, (tester) async {
      final repository = pageRepository(ServerType.community)..myRole = null;
      await capture(
        tester,
        name: name,
        width: width,
        height: height,
        light: light,
        textScale: scale,
        child: pageWorkspace(repository),
      );
    });
  }

  // ------------------------------------------- review pass (2026-10-06)
  // A member while the stage is quiet and an event has the hero: the stage
  // is a row under `Głos`, one tap away (its `Obserwuj` lives there).
  final memberQuiet = _name(390, false, 1, 'A1-community-member-offline');
  _captureWidgets(memberQuiet, (tester) async {
    await capture(
      tester,
      name: memberQuiet,
      width: 390,
      height: 844,
      child: pageWorkspace(_community(role: ServerMemberRole.member)),
    );
  });
  final memberQuietScrolled = _name(
    390,
    false,
    1,
    'A1-community-member-offline-scrolled',
  );
  _captureWidgets(memberQuietScrolled, (tester) async {
    await capture(
      tester,
      name: memberQuietScrolled,
      width: 390,
      height: 844,
      child: pageWorkspace(_community(role: ServerMemberRole.member)),
      before: scrollToEnd,
    );
  });

  // `Przypomnij mi` pressed: the bell is on and the page says which answer
  // went with it.
  for (final scale in [1.0, 2.0]) {
    final reminded = _name(390, false, scale, 'podcast-reminder-set');
    _captureWidgets(reminded, (tester) async {
      await capture(
        tester,
        name: reminded,
        width: 390,
        height: 844,
        textScale: scale,
        child: pageWorkspace(_podcast()),
        before: (tester) async {
          final respond = find.byKey(
            const ValueKey('server-page-event-respond'),
          );
          await tester.ensureVisible(respond);
          await _settle(tester);
          await tester.tap(respond);
          await _settle(tester);
        },
      );
    });
  }

  // Right after creation: the invitation card above the main thing.
  final created = _name(390, false, 1, 'friends-just-created');
  _captureWidgets(created, (tester) async {
    await capture(
      tester,
      name: created,
      width: 390,
      height: 844,
      child: pageWorkspace(_friends(), justCreated: true),
    );
  });

  // Another language, in the chrome the page and its neighbours draw.
  for (final (language, direction) in const [
    ('de', TextDirection.ltr),
    ('ar', TextDirection.rtl),
  ]) {
    if (language == 'ar' && _arabicFace == null) continue;
    final locale = Locale(language);
    for (final (state, width, height, scale, repository, scrolls) in [
      (
        'A1-community-owner-offline',
        390.0,
        844.0,
        1.0,
        () => _community(role: ServerMemberRole.owner),
        0,
      ),
      (
        'A1-community-owner-offline-scrolled',
        390.0,
        844.0,
        1.0,
        () => _community(role: ServerMemberRole.owner),
        1,
      ),
      (
        'A1-community-owner-offline',
        390.0,
        844.0,
        2.0,
        () => _community(role: ServerMemberRole.owner),
        0,
      ),
      (
        'A2-community-member-live',
        768.0,
        1024.0,
        1.0,
        () => _community(role: ServerMemberRole.owner, live: true),
        0,
      ),
      ('family', 390.0, 844.0, 1.0, _family, 0),
      ('family-scrolled', 390.0, 844.0, 1.0, _family, 1),
      ('family-scrolled-2', 390.0, 844.0, 1.0, _family, 3),
      ('family', 768.0, 1024.0, 1.0, _family, 0),
      (
        'friends-held',
        390.0,
        844.0,
        1.0,
        () => pageRepository(ServerType.friends, held: true),
        0,
      ),
    ]) {
      final name = _name(width, false, scale, state, language: language);
      _captureWidgets(name, (tester) async {
        await capture(
          tester,
          name: name,
          width: width,
          height: height,
          textScale: scale,
          locale: locale,
          // The locale already sets the direction; saying it again keeps the
          // frame honest if a delegate ever resolved it differently.
          direction: direction,
          child: pageWorkspace(repository()),
          before: (tester) async {
            for (var index = 0; index < scrolls; index++) {
              await scrollToEnd(tester);
            }
          },
        );
      });
    }
  }

  final pushed = _name(390, false, 1, 'A1-pushed-route-status-bar');
  _captureWidgets(pushed, (tester) async {
    await capture(
      tester,
      name: pushed,
      width: 390,
      height: 844,
      child: Builder(
        builder: (context) => MediaQuery(
          // A phone's status bar and home indicator, so the cover's inset
          // and the page's bottom padding are seen as a device draws them.
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: pageWorkspace(
            _community(role: ServerMemberRole.owner),
            isRootTab: false,
            onBack: () {},
          ),
        ),
      ),
    );
  });
}
