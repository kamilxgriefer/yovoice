// Build 42, invites option A ("Mój link" + QR + link repair, ADR-238):
// frame harness.
//
// Renders the REAL widgets through their constructor seams (no Firebase app,
// no network, no callable):
//
//   * FriendsScreen with its new header action and empty-state pill, and
//     "Mój link" opened from it by tapping that action — a bottom sheet at
//     390 / 768, a 420 px dialog inside the desktop shell at 1440 — also for
//     an account whose profile is not public (the honest sentence);
//   * the profile preview a `?user=` link opens (a person, and an id that
//     does not resolve);
//   * the sign-in screen a signed-out visitor of a profile link sees;
//   * the Voice Moment link destination's gone-state;
//   * the own profile with its "Mój link" entry points.
//
// Dark and Pearl, locale pl, plus 200 % text, Greek (the longest labels) and
// Arabic (RTL) spot frames.
//
// No `_test` suffix, so the ordinary suite skips it. Run explicitly:
//
//   flutter test test/w42_invites_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/w42/invites
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_entry_link.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_link_destination_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/my_link_sheet.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

import 'support/material_icons_font.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/w42-invites',
);
const _only = String.fromEnvironment('ONLY');

/// A real-looking Firebase uid: 28 characters, so the link wraps and the QR
/// code has the density production has.
const _me = 'Zx8qT1mVbN4kLp0sWe7uYh2RcA93';

final _capture = GlobalKey();

const _phone = Size(390, 844);
const _small = Size(320, 690);
const _tablet = Size(768, 1024);
const _desk = Size(1440, 900);

Future<void> _loadFonts() async {
  ByteData read(String path) =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final inter = FontLoader('Inter')
    ..addFont(Future.value(read('assets/fonts/InterVariable.ttf')))
    ..addFont(Future.value(read('assets/fonts/InterVariable-Italic.ttf')));
  await inter.load();
  await loadMaterialIconsFont();
  // The Arabic spot frame: the phone resolves the app's first fallback family
  // from the system; the test engine has none, so the Mac's own Arabic face
  // stands in under that name.
  // The link under the code asks for the platform's monospace face, which
  // the test engine does not have either; the Mac's stands in.
  for (final (family, path) in const [
    ('monospace', '/System/Library/Fonts/Menlo.ttc'),
    ('Noto Sans Arabic', '/System/Library/Fonts/GeezaPro.ttc'),
    (
      'Arial Unicode MS',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    ),
  ]) {
    if (File(path).existsSync()) {
      await (FontLoader(family)..addFont(Future.value(read(path)))).load();
    }
  }
}

Stream<T> _replay<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
  unawaited(controller.close());
});

class _P {
  const _P(this.id, this.name, {this.online = false, this.availability});
  final String id;
  final String name;
  final bool online;
  final String? availability;
}

const _people = <_P>[
  _P('marta', 'Marta Zielińska', online: true, availability: 'busy'),
  _P('ola', 'Ola Nowak', online: true, availability: 'available'),
  _P('tomek', 'Tomek Kowalczyk'),
  _P('kuba', 'Kuba Wiśniewski', online: true, availability: 'away'),
  _P('iga', 'Iga Malinowska', online: true),
  _P('pawel', 'Paweł Dąbrowski'),
  _P('ania', 'Ania Lewandowska', online: true),
  _P('piotr', 'Piotr Wójcik'),
  _P('zosia', 'Zosia Kamińska'),
  _P('bartek', 'Bartek Lis', online: true),
  _P('magda', 'Magda Sikora'),
  _P('julia', 'Julia Krawczyk'),
];

List<FriendUser> _friends() => [
  for (final p in _people)
    FriendUser(
      id: p.id,
      displayName: p.name,
      email: '',
      photoUrl: null,
      isOnline: p.online,
      lastSeen: p.online
          ? null
          : DateTime.now().subtract(const Duration(hours: 5)),
      availability: p.availability,
    ),
];

class _FriendsSvc extends FriendService {
  _FriendsSvc(
    this.list, {
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  }) : super(
         firestore: db,
         auth: auth,
         mutationInvoker: (name, data) async => <String, dynamic>{
           'outcome': 'requested',
         },
       );
  final List<FriendUser> list;

  @override
  Stream<List<FriendUser>> watchFriends() => _replay<List<FriendUser>>(list);
}

class _MsgSvc extends MessageService {
  _MsgSvc({required FirebaseFirestore db, required FirebaseAuth auth})
    : super(firestore: db, auth: auth);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        ChatPresence(
          isOnline: false,
          lastSeen: DateTime.now().subtract(const Duration(hours: 5)),
          availability: null,
        ),
      );
}

class _Graph implements SocialGraphService {
  @override
  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async =>
      const <SuggestedFriend>[];
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Caps extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

class _VisualAuthService extends AuthService {
  _VisualAuthService()
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;
}

/// One account's world: a fake Firestore with the signed-in profile, and the
/// services the real screens take through their constructor seams.
class _Fx {
  _Fx({
    this.friends = const [],
    this.uid = _me,
    this.name = 'Kamil',
    this.profileVisibility,
  });

  final List<FriendUser> friends;
  final String uid;
  final String name;

  /// The account's stored `profileVisibility`; null leaves it absent (the
  /// public default).
  final String? profileVisibility;

  final db = FakeFirebaseFirestore();
  late final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      isEmailVerified: true,
      displayName: name,
      email: 'account@example.com',
    ),
  );
  late final friendService = _FriendsSvc(friends, db: db, auth: auth);
  late final messageService = _MsgSvc(db: db, auth: auth);
  late final profileService = ProfileService(firestore: db, auth: auth);
  late final media = ProfileMediaService(
    auth: auth,
    invoker: (callable, request) async => <Object?, Object?>{
      'schemaVersion': 1,
      'available': false,
      'expiresAtMillis': DateTime.now()
          .add(const Duration(seconds: 60))
          .millisecondsSinceEpoch,
    },
  );

  Future<void> seed() async {
    await db.doc('users/$uid').set({
      'uid': uid,
      'displayName': name,
      'username': name.toLowerCase(),
      'availability': 'available',
      'profileVisibility': ?profileVisibility,
    });
    for (final friend in friends) {
      await db.doc('publicProfiles/${friend.id}').set({
        'uid': friend.id,
        'displayName': friend.displayName,
        'username': friend.id,
      });
    }
  }

  Widget friendsScreen() => FriendsScreen(
    isRootTab: true,
    friendService: friendService,
    messageService: messageService,
    socialGraphService: _Graph(),
    profileMediaService: media,
    firestore: db,
    auth: auth,
  );
}

/// The mobile shell's chrome around a root tab: the real floating dock.
Widget _shell(Widget body) => Builder(
  builder: (context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: body,
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        YoFloatingNavigationDock(
          selectedTabIndex: 2,
          roomsTabIndex: 13,
          momentsTabIndex: 5,
          unreadConversationCount: 0,
          onDestinationSelected: (_) {},
          onVoicePressed: () {},
          onMorePressed: () {},
        ),
      ],
    ),
  ),
);

/// The desktop shell's chrome: the real rail beside the content slot.
Widget _deskShell(_Fx fx, Widget child) => Builder(
  builder: (context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Row(
      children: [
        DesktopSidebar(
          active: DesktopNavItem.more,
          unreadConversationCount: 0,
          unreadNotificationCount: 0,
          onSelect: (_) {},
          onCreateRoom: () {},
          onCreateMoment: () {},
          onOpenProfile: () {},
          onOpenProfileSettings: () {},
          profileService: fx.profileService,
          capabilityService: _Caps(),
        ),
        Expanded(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.workbench,
            child: child,
          ),
        ),
      ],
    ),
  ),
);

Widget _hostFor(_Fx fx, Size size, Widget screen) =>
    size.width >= 1100 ? _deskShell(fx, screen) : _shell(screen);

Widget _app(
  Widget home, {
  required Size size,
  bool pearl = false,
  double text = 1,
  Locale locale = const Locale('pl'),
}) {
  final safe = size.width < 600
      ? const EdgeInsets.only(top: 47, bottom: 34)
      : size.width < 1100
      ? const EdgeInsets.only(top: 24, bottom: 20)
      : EdgeInsets.zero;
  return RepaintBoundary(
    key: _capture,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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
}

Future<void> _settle(WidgetTester tester, {int rounds = 3}) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var r = 0; r < rounds; r++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 220)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

final List<String> _log = <String>[];

/// One frame: fixture, pump, optional interaction, collect errors, shoot.
void _frame(
  String name,
  Size size,
  Future<Widget> Function() home, {
  bool pearl = false,
  double text = 1,
  Locale locale = const Locale('pl'),
  Future<void> Function(WidgetTester t)? then,
}) {
  if (_only.isNotEmpty && !RegExp(_only).hasMatch(name)) return;
  testWidgets(name, (t) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        errors.add(details.exceptionAsString().split('\n').first);
    try {
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      final widget = (await t.runAsync(home))!;
      await t.pumpWidget(
        _app(widget, size: size, pearl: pearl, text: text, locale: locale),
      );
      await _settle(t);
      if (then != null) {
        await then(t);
        await _settle(t);
      }
      await _shoot(t, name);
    } finally {
      FlutterError.onError = previous;
    }
    Object? e;
    while ((e = t.takeException()) != null) {
      errors.add('$e'.split('\n').first);
    }
    final line =
        '$name errors=${errors.length}'
        '${errors.isEmpty ? '' : ': ${errors.toSet().join(' | ')}'}';
    print(line);
    _log.add(line);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 1));
    t.view.reset();
  });
}

String _tag(Size size) => '${size.width.toInt()}';

UserProfile _ownProfile() => UserProfile(
  uid: _me,
  email: 'account@example.com',
  displayName: 'Kamil',
  username: 'kamil',
  bio: 'Nagrywam poranne Momenty i prowadzę wieczorne rozmowy o muzyce.',
  statusMessage: 'Muzyka + nocne rozmowy',
  country: 'Polska',
  nativeLanguage: 'polski',
  spokenLanguages: const ['angielski'],
  learningLanguages: const ['hiszpański'],
  photoUrl: null,
  bannerUrl: null,
  website: 'yovoice.app',
  accountType: AccountType.personal,
  friendCount: 12,
  followerCount: 0,
  followingCount: 0,
  roomCount: 1,
  communityCount: 2,
  voiceMinutes: 1265,
  messageCount: 842,
  activeDays: 64,
  momentCount: 27,
  reactionCount: 310,
  hostMinutes: 420,
  selectedTitleId: null,
  unlockedTitleIds: const <String>[],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

const _servers = <Server>[
  Server(
    id: 's1',
    name: 'Nocne Granie',
    description: '',
    ownerId: _me,
    type: ServerType.community,
    privacy: ServerPrivacy.public,
    memberCount: 128,
  ),
  Server(
    id: 's2',
    name: 'Ekipa z liceum',
    description: '',
    ownerId: 'ola',
    type: ServerType.friends,
    privacy: ServerPrivacy.private,
    memberCount: 9,
  ),
];

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(() async {
    await _loadFonts();
    Directory(_outDir).createSync(recursive: true);
  });
  tearDownAll(() {
    File(
      '$_outDir/capture_log${_only.isEmpty ? '' : '_part'}.txt',
    ).writeAsStringSync('${_log.join('\n')}\n');
  });
  setUp(() {
    ProfileService.resetCurrentProfileCache();
    FriendService.clearSharedReadCaches();
    ProfileMediaService.clearAllMediaAccessCaches();
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<Widget> Function() friendsHome(
    Size size, {
    bool empty = false,
    String? profileVisibility,
  }) => () async {
    final fx = _Fx(
      friends: empty ? const [] : _friends(),
      profileVisibility: profileVisibility,
    );
    await fx.seed();
    return _hostFor(fx, size, fx.friendsScreen());
  };

  Future<void> openMyLink(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('friends-my-link')));
  }

  // ---- Friends: the header action (populated) -----------------------------
  for (final size in const [_phone, _tablet, _desk]) {
    _frame('friends_populated_${_tag(size)}_dark_pl', size, friendsHome(size));
  }
  _frame(
    'friends_populated_390_pearl_pl',
    _phone,
    friendsHome(_phone),
    pearl: true,
  );

  // ---- A1: "Mój link", opened by tapping the Friends header action --------
  for (final size in const [_phone, _tablet, _desk]) {
    _frame(
      'a1_my-link_${_tag(size)}_dark_pl',
      size,
      friendsHome(size),
      then: openMyLink,
    );
    _frame(
      'a1_my-link_${_tag(size)}_pearl_pl',
      size,
      friendsHome(size),
      pearl: true,
      then: openMyLink,
    );
  }
  _frame(
    'a1_my-link_320_dark_pl',
    _small,
    friendsHome(_small),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_pl_200',
    _phone,
    friendsHome(_phone),
    text: 2,
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_pl_200_scrolled',
    _phone,
    friendsHome(_phone),
    text: 2,
    then: (t) async {
      await openMyLink(t);
      await _settle(t);
      await t.drag(
        find.byKey(const ValueKey('my-link-scroll')),
        const Offset(0, -900),
      );
    },
  );
  _frame(
    'a1_my-link_1440_dark_pl_200',
    _desk,
    friendsHome(_desk),
    text: 2,
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_el',
    _phone,
    friendsHome(_phone),
    locale: const Locale('el'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_de',
    _phone,
    friendsHome(_phone),
    locale: const Locale('de'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_ar_rtl',
    _phone,
    friendsHome(_phone),
    locale: const Locale('ar'),
    then: openMyLink,
  );
  // A profile that is "Friends only" / "Only me": the sentence says the link
  // will not open it for everyone instead of promising that it will.
  _frame(
    'a1_my-link_390_dark_pl_not-public',
    _phone,
    friendsHome(_phone, profileVisibility: 'friends'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_pearl_pl_not-public',
    _phone,
    friendsHome(_phone, profileVisibility: 'private'),
    pearl: true,
    then: openMyLink,
  );
  _frame(
    'a1_my-link_1440_dark_pl_not-public',
    _desk,
    friendsHome(_desk, profileVisibility: 'friends'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_hu_not-public',
    _phone,
    friendsHome(_phone, profileVisibility: 'friends'),
    locale: const Locale('hu'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_pl_200_not-public',
    _phone,
    friendsHome(_phone, profileVisibility: 'friends'),
    text: 2,
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_ar_rtl_not-public',
    _phone,
    friendsHome(_phone, profileVisibility: 'friends'),
    locale: const Locale('ar'),
    then: openMyLink,
  );
  _frame(
    'a1_my-link_390_dark_pl_copied',
    _phone,
    () async {
      final fx = _Fx(friends: _friends());
      await fx.seed();
      return _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              fx.friendsScreen(),
              // The same sheet, with a clipboard seam so "Kopiuj link"
              // answers in the frame.
              Positioned(
                left: 0,
                top: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: GestureDetector(
                    key: const ValueKey('capture-open'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showMyLink(
                      context,
                      auth: fx.auth,
                      profileService: fx.profileService,
                      mediaService: fx.media,
                      clipboardWriter: (_) async {},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    then: (t) async {
      await t.tap(
        find.byKey(const ValueKey('capture-open')),
        warnIfMissed: false,
      );
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('my-link-copy')));
    },
  );

  // ---- A2: an empty friends list offers the own link ----------------------
  for (final size in const [_phone, _tablet, _desk]) {
    _frame(
      'a2_friends-empty_${_tag(size)}_dark_pl',
      size,
      friendsHome(size, empty: true),
    );
  }
  _frame(
    'a2_friends-empty_390_pearl_pl',
    _phone,
    friendsHome(_phone, empty: true),
    pearl: true,
  );
  _frame(
    'a2_friends-empty_390_dark_pl_200',
    _phone,
    friendsHome(_phone, empty: true),
    text: 2,
  );
  _frame(
    'a2_friends-empty_390_dark_pl_200_scrolled',
    _phone,
    friendsHome(_phone, empty: true),
    text: 2,
    then: (t) async {
      await t.drag(
        find.byKey(const ValueKey('friends-coordinated-scroll')),
        const Offset(0, -420),
      );
    },
  );
  _frame(
    'a2_friends-empty_390_dark_el',
    _phone,
    friendsHome(_phone, empty: true),
    locale: const Locale('el'),
  );

  // ---- A3: what a `?user=` link opens for a signed-in recipient -----------
  Future<void> Function(WidgetTester) openPreview(
    _Fx Function() fx,
    String id,
  ) => (t) async {
    unawaited(
      showProfilePreview(
        t.element(find.byType(FriendsScreen)),
        userId: id,
        firestore: fx().db,
        auth: fx().auth,
        friendService: fx().friendService,
        messageService: fx().messageService,
        profileMediaService: fx().media,
        resolvePages: false,
      ),
    );
  };

  for (final size in const [_phone, _desk]) {
    late _Fx recipient;
    Future<Widget> home() async {
      recipient = _Fx(
        uid: 'ola',
        name: 'Ola',
        friends: _friends().take(3).toList(),
      );
      await recipient.seed();
      await recipient.db.doc('publicProfiles/$_me').set({
        'uid': _me,
        'displayName': 'Kamil',
        'username': 'kamil',
      });
      return _hostFor(recipient, size, recipient.friendsScreen());
    }

    _frame(
      'a3_profile-from-link_${_tag(size)}_dark_pl',
      size,
      home,
      then: openPreview(() => recipient, _me),
    );
    _frame(
      'a3_profile-unavailable_${_tag(size)}_dark_pl',
      size,
      home,
      then: openPreview(() => recipient, 'nobodyWithThisIdExists0000'),
    );
  }

  // ---- A3b: a signed-out visitor of a profile / Voice link ----------------
  for (final size in const [_phone, _tablet, _desk]) {
    _frame(
      'a3b_signed-out_profile-link_${_tag(size)}_dark_pl',
      size,
      () async => LoginScreen(
        authService: _VisualAuthService(),
        entryLink: AuthEntryLink.profile,
      ),
    );
  }
  _frame(
    'a3b_signed-out_profile-link_390_pearl_pl',
    _phone,
    () async => LoginScreen(
      authService: _VisualAuthService(),
      entryLink: AuthEntryLink.profile,
    ),
    pearl: true,
  );
  _frame(
    'a3b_signed-out_profile-link_390_dark_pl_200',
    _phone,
    () async => LoginScreen(
      authService: _VisualAuthService(),
      entryLink: AuthEntryLink.profile,
    ),
    text: 2,
  );
  _frame(
    'a3b_signed-out_voice-link_390_dark_pl',
    _phone,
    () async => LoginScreen(
      authService: _VisualAuthService(),
      entryLink: AuthEntryLink.voiceMoment,
    ),
  );

  // ---- A `?moment=` link that does not resolve ----------------------------
  for (final size in const [_phone, _tablet, _desk]) {
    _frame(
      'moment-link_gone_${_tag(size)}_dark_pl',
      size,
      () async => MomentLinkDestinationScreen(
        momentId: 'momentThatIsGone',
        loader: (id) async => throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'not-found',
        ),
      ),
    );
  }
  _frame(
    'moment-link_gone_390_pearl_pl',
    _phone,
    () async => MomentLinkDestinationScreen(
      momentId: 'momentThatIsGone',
      loader: (id) async => throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'not-found',
      ),
    ),
    pearl: true,
  );

  // ---- Profile: the three entry points ------------------------------------
  Future<Widget> Function() profileHome() => () async {
    final fx = _Fx();
    await fx.seed();
    return Builder(
      builder: (context) => ProfileScreenView(
        profile: _ownProfile(),
        servers: _servers,
        serversLoading: false,
        onEdit: () {},
        onAchievements: () {},
        onOpenServer: (_) {},
        showSuperAdminActivation: false,
        isActivatingSuperAdmin: false,
        currentRole: 'user',
        onActivateSuperAdmin: () async {},
        onLogout: () async {},
        onMyLink: () => showMyLink(
          context,
          auth: fx.auth,
          profileService: fx.profileService,
          mediaService: fx.media,
          seedProfile: _ownProfile(),
        ),
        identityRepository: PublicIdentityRepository.instance,
        mediaService: fx.media,
      ),
    );
  };

  for (final size in const [_phone, _tablet, _desk]) {
    _frame('profile_entry_${_tag(size)}_dark_pl', size, profileHome());
  }
  _frame('profile_entry_390_pearl_pl', _phone, profileHome(), pearl: true);
  _frame(
    'profile_my-link_390_dark_pl',
    _phone,
    profileHome(),
    then: (t) async {
      await t.tap(find.byKey(const ValueKey('profile-my-link')));
    },
  );
  _frame(
    'profile_more-sheet_390_dark_pl',
    _phone,
    profileHome(),
    then: (t) async {
      await t.tap(find.byKey(const ValueKey('profile-more-button')));
    },
  );
  _frame(
    'profile_account-row_390_dark_pl',
    _phone,
    profileHome(),
    then: (t) async {
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('profile-account-my-link')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
    },
  );
}
