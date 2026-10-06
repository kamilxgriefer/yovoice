// ignore_for_file: avoid_print
// Developer-only capture harness for "Zacznij tutaj" (firstSteps A,
// 2026-10-03). Not a *_test.dart file, so the regular suite ignores it.
//
// It renders the REAL widgets (MobileHome / DesktopHome with the real dock
// and rail, ServerWorkspaceScreen + the invite sheet, NotificationsScreen,
// FriendsScreen) from in-memory fixtures through their constructor seams, at
// exact logical viewports, and writes one PNG per frame:
//
//   flutter test test/first_steps_capture.dart --concurrency=1 \
//     --dart-define=FIRST_STEPS_CAPTURE_OUT=<dir> \
//     [--dart-define=ONLY=<regexp over frame names>]
//
// Frames: Start at 390 / 768 / 1440 (1 z 5, 4 z 5, Gotowe, 1 z 4 with Treści
// off), the three dead ends at 390 / 768 / 1440, plus Pearl, 200 % text and
// Arabic (RTL) spot frames. The account's photo is drawn as its initial: the
// test renderer has no network, and the avatar is not what these frames are
// about (the photo step is ticked from the avatar grant, which is real here).

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/audio/call_tone_service.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/data/first_steps_store.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_invite_sheet.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import 'server_community_test.dart' as community;
import 'server_test_support.dart';
import 'support/first_steps_fixtures.dart';
import 'support/material_icons_font.dart';

const _out = String.fromEnvironment(
  'FIRST_STEPS_CAPTURE_OUT',
  defaultValue: 'build/first_steps_capture',
);
const _only = String.fromEnvironment('ONLY');

const _phone = Size(390, 844);
const _tablet = Size(768, 1024);
const _desk = Size(1440, 900);

/// The 200 % text desktop frame. At 1440 x 900 the rail itself (not Start)
/// overflows by 5 px with enlarged text and the Treści row, so that frame
/// uses a taller window to show Start's own layout without the rail's
/// warning stripes.
const _deskTall = Size(1440, 1100);

/// A desktop window narrow enough that Start has ONE column beside the rail
/// (slot 916 < 1000): the card sits under the greeting, rows in two columns.
const _deskNarrow = Size(1180, 820);
const _safePhone = EdgeInsets.only(top: 47, bottom: 34);
const _safeTablet = EdgeInsets.only(top: 24, bottom: 20);

const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
const _arabicFont = '/System/Library/Fonts/SFArabic.ttf';

final _capture = GlobalKey();

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
    ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  await loadMaterialIconsFont();
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final bytes = ByteData.sublistView(emoji.readAsBytesSync());
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final arabic = File(_arabicFont);
  if (arabic.existsSync()) {
    await (FontLoader('Noto Sans Arabic')..addFont(
          Future.value(ByteData.sublistView(arabic.readAsBytesSync())),
        ))
        .load();
  }
}

Widget _app(
  Widget home, {
  required Brightness brightness,
  required Locale locale,
  required EdgeInsets safe,
  required double text,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(text),
        disableAnimations: true,
        padding: safe,
        viewPadding: safe,
      ),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var r = 0; r < rounds; r++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _shoot(WidgetTester tester, String name, double dpr) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final layer = boundary.debugLayer! as OffsetLayer;
    final rect = Offset.zero & boundary.size;
    final warm = await layer.toImage(rect, pixelRatio: dpr);
    warm.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await layer.toImage(rect, pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
    print('wrote ${file.path}');
  });
}

/// One frame: async fixture, pump, optional interaction, shoot. Layout
/// errors (an overflow) are collected and fail the frame after the shot, so
/// the PNG of a broken frame still exists to look at.
void _frame(
  String name,
  Size size,
  Future<Widget> Function() home, {
  Brightness brightness = Brightness.dark,
  Locale locale = const Locale('pl'),
  double text = 1,
  Future<void> Function(WidgetTester tester)? then,
}) {
  if (_only.isNotEmpty && !RegExp(_only).hasMatch(name)) return;
  testWidgets(name, (tester) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        errors.add(details.exceptionAsString().split('\n').first);
    final dpr = size.width >= 1440 ? 1.0 : 2.0;
    // The test framework paints every BoxShadow as a hard block for golden
    // stability; a capture wants the Pearl lifts and the CTA glow as on a
    // device. Restored before the framework checks its debug variables.
    debugDisableShadows = false;
    try {
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      final safe = size == _phone
          ? _safePhone
          : size == _tablet
          ? _safeTablet
          : EdgeInsets.zero;
      final widget = (await tester.runAsync(home))!;
      await tester.pumpWidget(
        _app(
          widget,
          brightness: brightness,
          locale: locale,
          safe: safe,
          text: text,
        ),
      );
      await _settle(tester);
      if (then != null) {
        await then(tester);
        await _settle(tester);
      }
      await _shoot(tester, name, dpr);
    } finally {
      FlutterError.onError = previous;
      debugDisableShadows = true;
    }
    Object? error;
    while ((error = tester.takeException()) != null) {
      errors.add('$error'.split('\n').first);
    }
    print('$name errors=${errors.length} ${errors.toSet().join(' | ')}');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    tester.view.reset();
    expect(errors, isEmpty, reason: name);
  });
}

// ------------------------------------------------------------------ shells

/// The phone / tablet shell's chrome around a root tab: the real dock (six
/// tabs while Treści is on, as in the app).
Widget _mobileShell(Widget body, {required int tab, bool content = true}) =>
    Builder(
      builder: (context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoFloatingNavigationDock(
              selectedTabIndex: tab,
              roomsTabIndex: 13,
              momentsTabIndex: 5,
              contentTabIndex: content ? MainShell.contentSlot : null,
              unreadConversationCount: 0,
              onDestinationSelected: (_) {},
              onVoicePressed: () {},
              onMorePressed: () {},
            ),
          ],
        ),
      ),
    );

/// The desktop shell's chrome around a content slot: the real rail.
Widget _desktopShell(
  FirstStepsWorld world,
  Widget child, {
  required DesktopNavItem active,
  bool frame = false,
}) => Builder(
  builder: (context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Row(
      children: [
        DesktopSidebar(
          active: active,
          unreadConversationCount: 0,
          unreadNotificationCount: 0,
          onSelect: (_) {},
          onCreateRoom: () {},
          onCreateMoment: () {},
          onOpenProfile: () {},
          onOpenProfileSettings: () {},
          profileService: world.profileService,
          showContent: true,
        ),
        Expanded(
          child: frame
              ? ResponsiveContentFrame(
                  width: ResponsiveContentWidth.workbench,
                  child: child,
                )
              : child,
        ),
      ],
    ),
  ),
);

class _NoSuggestions implements SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];

  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ------------------------------------------------------------------- Start

Future<FirstStepsWorld> _world({
  List<FriendUser> friends = const <FriendUser>[],
  List<Server> servers = const <Server>[],
  int moments = 0,
  int following = 0,
  FirstStepsOutcome? stored,
}) async {
  final world = FirstStepsWorld(
    friends: friends,
    servers: servers,
    moments: moments,
    following: following,
    store: MemoryFirstStepsStore(stored),
  );
  await world.seed();
  return world;
}

Future<FirstStepsWorld> _newcomer() => _world();

Future<FirstStepsWorld> _fourOfFive() => _world(
  friends: [firstStepsFriend()],
  servers: [firstStepsServer()],
  moments: 1,
);

/// Everything done by an account whose checklist this device showed before:
/// the one-line "Gotowe" state.
Future<FirstStepsWorld> _allDone() => _world(
  friends: [firstStepsFriend()],
  servers: [firstStepsServer()],
  moments: 1,
  following: 1,
  stored: FirstStepsOutcome.started,
);

void _startFrames() {
  Future<Widget> phone(
    Future<FirstStepsWorld> Function() make, {
    bool content = true,
  }) async {
    final world = await make();
    return _mobileShell(
      world.mobileHome(contentEnabled: content),
      tab: 0,
      content: content,
    );
  }

  Future<Widget> desktop(Future<FirstStepsWorld> Function() make) async {
    final world = await make();
    return _desktopShell(
      world,
      world.desktopHome(),
      active: DesktopNavItem.home,
    );
  }

  _frame('start_390_dark_1of5', _phone, () => phone(_newcomer));
  _frame('start_390_dark_4of5', _phone, () => phone(_fourOfFive));
  _frame('start_390_dark_done', _phone, () => phone(_allDone));
  _frame(
    'start_390_dark_1of4_no_content',
    _phone,
    () => phone(_newcomer, content: false),
  );
  _frame('start_768_dark_1of5', _tablet, () => phone(_newcomer));
  _frame('start_768_dark_done', _tablet, () => phone(_allDone));
  _frame('start_1440_dark_1of5', _desk, () => desktop(_newcomer));
  _frame('start_1440_dark_4of5', _desk, () => desktop(_fourOfFive));
  _frame('start_1440_dark_done', _desk, () => desktop(_allDone));
  _frame('start_1180_dark_1of5', _deskNarrow, () => desktop(_newcomer));
  _frame('start_1180_dark_done', _deskNarrow, () => desktop(_allDone));

  _frame(
    'start_390_pearl_1of5',
    _phone,
    () => phone(_newcomer),
    brightness: Brightness.light,
  );
  _frame(
    'start_390_pearl_done',
    _phone,
    () => phone(_allDone),
    brightness: Brightness.light,
  );
  _frame(
    'start_1440_pearl_1of5',
    _desk,
    () => desktop(_newcomer),
    brightness: Brightness.light,
  );
  _frame('start_390_dark_1of5_t200', _phone, () => phone(_newcomer), text: 2);
  _frame('start_768_dark_1of5_t200', _tablet, () => phone(_newcomer), text: 2);
  _frame(
    'start_1440_dark_1of5_t200',
    _deskTall,
    () => desktop(_newcomer),
    text: 2,
  );
  _frame(
    'start_390_dark_1of5_ar',
    _phone,
    () => phone(_newcomer),
    locale: const Locale('ar'),
  );
  _frame(
    'start_390_dark_1of5_de',
    _phone,
    () => phone(_newcomer),
    locale: const Locale('de'),
  );
}

// ------------------------------------------------------------ invite sheet

late TestServerRepository _inviteRepository;
late Server _inviteServer;

Future<Widget> _workspace({
  ServerPrivacy privacy = ServerPrivacy.public,
}) async {
  _inviteServer = Server(
    id: 's',
    name: 'Nocne Granie',
    description: 'Wieczorne granie, rozmowy i transmisje.',
    ownerId: 'owner',
    type: ServerType.community,
    privacy: privacy,
    memberCount: 128,
    defaultChannelId: 'general',
    schemaVersion: 1,
    activationState: 'active',
    status: 'active',
  );
  _inviteRepository = TestServerRepository()
    ..servers = [_inviteServer]
    ..channels = community.communityChannels();
  return ServerWorkspaceScreen(
    key: UniqueKey(),
    serverId: 's',
    repository: _inviteRepository,
    isRootTab: true,
    initialChannelId: 'general',
    chatService: community.communityChat(),
    connector: FakeServerMediaConnector(),
  );
}

Future<void> _openInvite(WidgetTester tester, {bool shareFails = false}) async {
  final context = tester.element(find.byType(ServerWorkspaceScreen));
  unawaited(
    showServerInviteSheet(
      context,
      server: _inviteServer,
      repository: _inviteRepository,
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'owner')),
      shareServer: (_) async {
        if (shareFails) throw StateError('share sheet unavailable');
      },
      onAddFriends: () {},
    ),
  );
}

void _inviteFrames() {
  _frame('invite_390_dark_public', _phone, _workspace, then: _openInvite);
  _frame(
    'invite_390_dark_private',
    _phone,
    () => _workspace(privacy: ServerPrivacy.inviteOnly),
    then: _openInvite,
  );
  _frame('invite_768_dark_public', _tablet, _workspace, then: _openInvite);
  _frame('invite_1440_dark_public', _desk, _workspace, then: _openInvite);
  _frame(
    'invite_390_pearl_public',
    _phone,
    _workspace,
    brightness: Brightness.light,
    then: _openInvite,
  );
  _frame(
    'invite_390_dark_public_t200',
    _phone,
    _workspace,
    text: 2,
    then: _openInvite,
  );
  _frame(
    'invite_390_dark_public_t200_scrolled',
    _phone,
    _workspace,
    text: 2,
    then: (tester) async {
      await _openInvite(tester);
      await _settle(tester, rounds: 1);
      await tester.drag(
        find.descendant(
          of: find.byType(ServerInviteSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(0, -900),
      );
    },
  );
  _frame(
    'invite_390_dark_public_share_failed',
    _phone,
    _workspace,
    then: (tester) async {
      await _openInvite(tester, shareFails: true);
      await _settle(tester, rounds: 1);
      await tester.tap(find.byKey(const ValueKey('server-invite-share-link')));
    },
  );
  _frame(
    'invite_390_dark_public_ar',
    _phone,
    _workspace,
    locale: const Locale('ar'),
    then: _openInvite,
  );
}

// ----------------------------------------------------------- notifications

NotificationsScreen _notifications(
  FirstStepsWorld world, {
  required bool pages,
  bool rootTab = false,
}) => NotificationsScreen(
  isRootTab: rootTab,
  acknowledgeOnVisible: false,
  friendService: FriendService(
    firestore: world.db,
    auth: world.auth,
    mutationInvoker: (name, data) async => <String, dynamic>{
      'outcome': 'accepted',
    },
  ),
  messageService: world.messageService,
  notificationService: NotificationService(
    firestore: world.db,
    auth: world.auth,
  ),
  currentUserId: firstStepsUid,
  firestore: world.db,
  auth: world.auth,
  openNotification: (_) async {},
  pagesEnabled: ValueNotifier<bool>(pages),
  onFindPages: (_) async {},
  onAddFriends: () {},
);

void _notificationFrames() {
  Future<Widget> base() async => const Scaffold(body: SizedBox.expand());

  Future<void> Function(WidgetTester) push({required bool pages}) =>
      (tester) async {
        final world = (await tester.runAsync(_newcomer))!;
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => _notifications(world, pages: pages),
            ),
          ),
        );
      };

  Future<Widget> desktop() async {
    final world = await _newcomer();
    return _desktopShell(
      world,
      _notifications(world, pages: true, rootTab: true),
      active: DesktopNavItem.notifications,
    );
  }

  _frame('notifications_390_dark', _phone, base, then: push(pages: true));
  _frame(
    'notifications_390_dark_no_content',
    _phone,
    base,
    then: push(pages: false),
  );
  _frame('notifications_768_dark', _tablet, base, then: push(pages: true));
  _frame('notifications_1440_dark', _desk, desktop);
  _frame(
    'notifications_390_pearl',
    _phone,
    base,
    brightness: Brightness.light,
    then: push(pages: true),
  );
  _frame(
    'notifications_390_dark_t200',
    _phone,
    base,
    text: 2,
    then: push(pages: true),
  );
  _frame(
    'notifications_390_dark_ar',
    _phone,
    base,
    locale: const Locale('ar'),
    then: push(pages: true),
  );
}

// ----------------------------------------------------------------- friends

FriendsScreen _friends(FirstStepsWorld world) => FriendsScreen(
  isRootTab: true,
  friendService: world.friendService,
  messageService: world.messageService,
  socialGraphService: _NoSuggestions(),
  profileMediaService: world.profileMediaService,
  firestore: world.db,
  auth: world.auth,
);

void _friendsFrames() {
  Future<Widget> phone() async {
    final world = await _newcomer();
    return _mobileShell(_friends(world), tab: 2);
  }

  Future<Widget> desktop() async {
    final world = await _newcomer();
    return _desktopShell(
      world,
      _friends(world),
      active: DesktopNavItem.more,
      frame: true,
    );
  }

  _frame('friends_390_dark_empty', _phone, phone);
  _frame('friends_768_dark_empty', _tablet, phone);
  _frame('friends_1440_dark_empty', _desk, desktop);
  _frame(
    'friends_390_pearl_empty',
    _phone,
    phone,
    brightness: Brightness.light,
  );
  _frame('friends_390_dark_empty_t200', _phone, phone, text: 2);
  _frame(
    'friends_390_dark_empty_t200_scrolled',
    _phone,
    phone,
    text: 2,
    then: (tester) async {
      await tester.drag(
        find
            .descendant(
              of: find.byKey(const ValueKey('friends-coordinated-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -700),
      );
    },
  );
  _frame(
    'friends_390_dark_empty_ar',
    _phone,
    phone,
    locale: const Locale('ar'),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    Directory(_out).createSync(recursive: true);
  });
  setUp(() {
    ProfileService.resetCurrentProfileCache();
    FriendService.clearSharedReadCaches();
    ProfileMediaService.clearAllMediaAccessCaches();
    debugServerVoiceDeviceOverride = FakeServerVoiceDevice();
    debugCallToneServiceOverride = CallToneService(enabled: () => false);
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: firstStepsUid),
      ),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() {
    debugServerVoiceDeviceOverride = null;
    debugCallToneServiceOverride = null;
  });

  _startFrames();
  _inviteFrames();
  _notificationFrames();
  _friendsFrames();
}
