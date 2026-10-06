// ignore_for_file: avoid_print
// Developer-only VISUAL capture for Page deletion (ADR-236; owner's choice
// pageDeleteWhat B "Dwa działania" + pageDeleteHow B "30 dni na powrót",
// sheets 6_pageDeleteWhat / 6_pageDeleteHow): the danger zone of Page
// settings, the "Usuń wszystkie posty" confirmation, the "Usuń stronę"
// screen, the pending banner on the owner's Page and in settings, "Usuń
// teraz, nie czekaj", the "Trwa usuwanie postów" wall and what a follower
// sees. The REAL screens with the shipped Inter font.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/page_delete_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-10-03/w42/page-delete/. Layout
// exceptions are recorded in _exceptions.log next to the frames.
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
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/page_deletion_center.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_account_actions.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/screens/page_delete_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/material_icons_font.dart';

const _out =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-10-03/w42/'
    'page-delete';
const _only = String.fromEnvironment('ONLY');
const _arabicFont = '/System/Library/Fonts/SFArabic.ttf';
const _dpr = 2.0;
final _capture = GlobalKey();
final List<String> _log = [];

/// The sheets' fixture: "Pracownia Glina", Firma, 128 obserwujących, 14
/// postów; deletion requested on 2 October 2026, so the date is 1 November.
final DateTime _now = DateTime(2026, 10, 2, 12);
final DateTime _deleteAt = _now.add(PageDeleteScreen.window);
const _pageName = 'Pracownia Glina';
const _desc =
    'Ręcznie toczona ceramika użytkowa: kubki, miski i wazony. Warsztaty '
    'toczenia na kole w każdy czwartek o 18:00 i w soboty o 11:00.';

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
  // The RTL frames: Inter has no Arabic, and a phone resolves the app's
  // first fallback family ('Noto Sans Arabic') to a system Arabic face. The
  // host's Arabic system font stands in for it under that name (the
  // slim_start_capture pattern), so the Arabic copy is drawn, not boxes.
  final arabic = File(_arabicFont);
  if (arabic.existsSync()) {
    final loader = FontLoader('Noto Sans Arabic')
      ..addFont(Future.value(ByteData.sublistView(arabic.readAsBytesSync())));
    await loader.load();
    print('arabic font registered: $_arabicFont');
  } else {
    print('arabic font NOT available on this host: RTL frames show boxes');
  }
}

String _postId(int n) => 'pp_${n.toRadixString(16).padLeft(40, '0')}';

Map<String, Object?> _post(
  int n, {
  required String text,
  required Duration age,
  int likes = 0,
  int comments = 0,
  bool pinned = false,
}) => {
  'postId': _postId(n),
  'pageId': 'me',
  'pageName': _pageName,
  'pageKind': 'business',
  'kind': 'text',
  'text': text,
  'media': <Object>[],
  'createdAtMs': _now.subtract(age).millisecondsSinceEpoch,
  'likeCount': likes,
  'commentCount': comments,
  'callerLiked': false,
  'commentsEnabled': true,
  'state': 'published',
  'pinned': pinned,
};

final _pinned = _post(
  101,
  text:
      'Zapisy na jesienne warsztaty toczenia ruszyły. Grupy do 6 osób, '
      'czwartki o 18:00. Glina, fartuch i herbata w cenie.',
  likes: 34,
  comments: 6,
  age: const Duration(days: 3),
  pinned: true,
);
final _text = _post(
  104,
  text:
      'W sobotę otwarta pracownia od 10:00. Można przyjść, popatrzeć i '
      'spróbować toczenia.',
  likes: 18,
  comments: 2,
  age: const Duration(hours: 26),
);

Map<String, Object?> _header({String state = 'active', int posts = 14}) => {
  'pageId': 'me',
  'displayName': _pageName,
  'kind': 'business',
  'category': 'music_arts',
  'description': _desc,
  'followerCount': 128,
  'postCount': posts,
  'onYoVoiceSinceMs': DateTime.utc(2026, 3, 10).millisecondsSinceEpoch,
  'about': {
    'business': {
      'website': 'https://pracowniaglina.pl',
      'email': 'kontakt@pracowniaglina.pl',
      'phone': '+48585550142',
      'address': 'ul. Garncarska 8, 80-894 Gdańsk',
      'hours': 'Wt–Pt 11:00–18:00 · Sb 10:00–14:00',
      'legalNotice': null,
    },
    'community': null,
  },
  'state': state,
};

Map<String, Object?> _ownerPage({
  String state = 'active',
  bool withPosts = true,
}) => {
  'schemaVersion': 1,
  'page': _header(state: state, posts: withPosts ? 14 : 0),
  'viewer': {
    'isOwner': true,
    'following': false,
    'canFollow': false,
    'canMessage': false,
  },
  'pinned': withPosts ? _pinned : null,
  'posts': withPosts ? [_text] : <Object>[],
  'nextCursor': null,
  'hasMore': false,
};

/// What `managePageDeletionV1` answers in each captured state ('deleted':
/// the purge finished, a new Page waits 7 days).
Map<String, Object?> _deletionWire(String state) => {
  'schemaVersion': 1,
  'pageId': 'me',
  'pageExists': state != 'deleted',
  'deletion': switch (state) {
    'pending' || 'purging' => {
      'state': state,
      'requestedAtMs': _now.millisecondsSinceEpoch,
      'deleteAtMs': _deleteAt.millisecondsSinceEpoch,
    },
    _ => null,
  },
  'postsClearing': state == 'clearing'
      ? {'requestedAtMs': _now.millisecondsSinceEpoch}
      : null,
  'recreateAllowedAtMs': state == 'deleted'
      ? _now.add(const Duration(days: 7)).millisecondsSinceEpoch
      : null,
};

PagesService _service(Object? page, {String deletion = ''}) => PagesService(
  clock: () => _now,
  invoker: (name, payload) async {
    if (name == PagesService.pageCallable) {
      if (page is Exception) throw page;
      return page;
    }
    if (name == PagesService.deletionCallable) return _deletionWire(deletion);
    return {'ok': true};
  },
);

PageDeletionCenter _center(PagesService service) => PageDeletionCenter(
  service: service,
  store: MemoryPageDeletionStore(),
  userId: () => 'me',
);

class _Actions implements PageAccountActions {
  const _Actions();
  @override
  Future<FriendRelationshipStatus?> relationship(String uid) async =>
      FriendRelationshipStatus.none;
  @override
  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  }) async {}
  @override
  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {}
  @override
  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  }) async {}
  @override
  Future<void> removeFriend(String uid) async {}
  @override
  Future<void> block(String uid) async {}
  @override
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  }) async {}
}

Future<void> _nopCtx(BuildContext context) async {}
Future<void> _nopPost(BuildContext context, PagePostView post) async {}
Future<void> _nopPage(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) async {}
Future<void> _nopOpenPost(
  BuildContext context, {
  required String pageId,
  required String postId,
  PagePostView? initial,
  bool focusComposer = false,
  bool pageReadOnly = false,
}) async {}
Future<PagePostView?> _nopCompose(
  BuildContext context, {
  required PageComposerOwner owner,
  PagePostKind initialKind = PagePostKind.text,
}) async => null;

const _flows = PagesFlows(
  openPage: _nopPage,
  openPost: _nopOpenPost,
  openLikers: _nopPost,
  playVoice: _nopPost,
  openCreatePage: _nopCtx,
  openComposer: _nopCompose,
);

OwnPage _own({bool paused = false, int posts = 14}) => OwnPage(
  kind: PageKind.business,
  status: 'active',
  ownerPaused: paused,
  suspended: false,
  category: 'music_arts',
  description: _desc,
  business: const PageBusinessInfo(
    website: 'https://pracowniaglina.pl',
    email: 'kontakt@pracowniaglina.pl',
    phone: '+48585550142',
    address: 'ul. Garncarska 8, 80-894 Gdańsk',
    hours: 'Wt–Pt 11:00–18:00 · Sb 10:00–14:00',
    legalNotice: null,
  ),
  displayName: _pageName,
  postCount: posts,
);

UserProfile _me() => UserProfile(
  uid: 'me',
  email: 'me@example.com',
  displayName: _pageName,
  username: 'pracowniaglina',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  creatorAgeVerified: false,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 128,
  accountFollowerCount: 128,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: null,
  profileVisibility: ProfileVisibility.public,
);

// ---------------------------------------------------------------- screens

/// Page settings in [deletion] state: '' (running), 'pending', 'purging',
/// 'deleted' (the purge finished while the screen was open).
Widget _settings({String deletion = ''}) {
  final service = _service(null, deletion: deletion);
  return PageSettingsScreen(
    service: service,
    deletion: _center(service),
    accessStream: () => Stream.value(
      PageAccessState(
        resolved: true,
        hasVipGrant: true,
        ownPage: deletion == 'deleted'
            ? null
            : _own(paused: deletion.isNotEmpty),
      ),
    ),
    profileStream: () => Stream.value(_me()),
    serverStream: () => Stream.value(const []),
    userId: 'me',
    clock: () => _now,
  );
}

Widget _profile(
  Object? page, {
  bool owner = true,
  String deletion = '',
  bool fromLink = false,
}) {
  final service = _service(page, deletion: deletion);
  return PageProfileScreen(
    pageId: 'me',
    displayName: _pageName,
    service: service,
    deletion: _center(service),
    actions: const _Actions(),
    flows: _flows,
    userId: owner ? 'me' : 'viewer',
    clock: () => _now,
    fromLink: fromLink,
    accessStream: () => Stream.value(
      PageAccessState(
        resolved: true,
        hasVipGrant: owner,
        ownPage: owner
            ? _own(paused: deletion == 'pending' || deletion == 'purging')
            : null,
      ),
    ),
  );
}

Widget _delete() {
  final service = _service(null, deletion: 'pending');
  return PageDeleteScreen(
    pageId: 'me',
    name: _pageName,
    kind: PageKind.business,
    postCount: 14,
    followerCount: 128,
    deletion: _center(service),
    clock: () => _now,
  );
}

Widget _dock() => YoFloatingNavigationDock(
  selectedTabIndex: 14,
  roomsTabIndex: 13,
  momentsTabIndex: 5,
  contentTabIndex: 14,
  unreadConversationCount: 2,
  onDestinationSelected: (_) {},
  onVoicePressed: () {},
  onMorePressed: () {},
);

Widget _phone(Widget body) =>
    Scaffold(body: body, bottomNavigationBar: _dock());

class _SidebarProfile extends ProfileService {
  _SidebarProfile()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      );
  @override
  Stream<UserProfile> watchCurrentProfile() => Stream.value(_me());
}

/// The desktop shell's sidebar beside the content slot.
Widget _desktop(Widget body) => Scaffold(
  body: Row(
    children: [
      DesktopSidebar(
        profileService: _SidebarProfile(),
        active: DesktopNavItem.content,
        showContent: true,
        unreadConversationCount: 2,
        unreadNotificationCount: 3,
        onSelect: (_) {},
        onCreateRoom: () {},
        onCreateMoment: () {},
        onOpenProfile: () {},
        onOpenProfileSettings: () {},
      ),
      Expanded(child: body),
    ],
  ),
);

/// Pushes [child] over a blank route, so screens that draw Back only when
/// they can pop (settings, the delete screen) show it.
Widget _pushed(Widget child) => Navigator(
  onGenerateInitialRoutes: (navigator, _) => [
    PageRouteBuilder<void>(
      pageBuilder: (context, _, _) =>
          ColoredBox(color: context.appPalette.background),
    ),
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => child,
      transitionDuration: Duration.zero,
    ),
  ],
);

class _Look {
  const _Look({
    this.pearl = false,
    this.locale = const Locale('pl'),
    this.textScale = 1,
  });

  final bool pearl;
  final Locale locale;
  final double textScale;
}

Widget _app(Widget home, {required EdgeInsets safe, required _Look look}) =>
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: look.pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: look.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(look.textScale),
            disableAnimations: true,
            padding: safe,
            viewPadding: safe,
          ),
          child: child!,
        ),
        home: home,
      ),
    );

// ---------------------------------------------------------------- capture

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    print('wrote $name ${image.width}x${image.height}');
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

const _safe390 = EdgeInsets.only(top: 47, bottom: 34);
const _safeTab = EdgeInsets.only(top: 24, bottom: 20);
const _p390 = Size(390, 844);
const _tab = Size(768, 1024);
const _desk = Size(1440, 900);

void _drain(WidgetTester tester, String name) {
  Object? error;
  final errors = <String>[];
  while ((error = tester.takeException()) != null) {
    errors.add('$error'.split('\n').take(3).join(' / '));
  }
  if (errors.isNotEmpty) {
    print('EXCEPTION in $name: ${errors.join(' | ')}');
    _log.add('EXCEPTION $name: ${errors.join(' | ')}');
  }
}

void _t(
  String name,
  Size size,
  Widget Function() home, {
  Future<void> Function(WidgetTester t)? then,
  _Look look = const _Look(),
}) {
  if (_only.isNotEmpty && !_only.split(',').any(name.startsWith)) return;
  testWidgets(name, (tester) async {
    tester.view.physicalSize = size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    final safe = size.width >= 1000
        ? EdgeInsets.zero
        : size.width >= 600
        ? _safeTab
        : _safe390;
    await tester.pumpWidget(_app(home(), safe: safe, look: look));
    await _settle(tester);
    _drain(tester, name);
    if (then != null) {
      await then(tester);
      await _settle(tester);
    }
    _drain(tester, name);
    await _shoot(tester, name);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    _drain(tester, '$name (teardown)');
    debugDisableShadows = true;
  });
}

Future<void> _settingsBottom(WidgetTester t) async {
  await t.drag(
    find.byKey(const ValueKey('page-settings-list')),
    const Offset(0, -3000),
  );
}

Future<void> _deleteBottom(WidgetTester t) async {
  await t.enterText(find.byKey(const ValueKey('page-delete-name')), _pageName);
  await t.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
  await t.drag(
    find.byKey(const ValueKey('page-delete-list')),
    const Offset(0, -3000),
  );
}

void main() {
  setUpAll(() async {
    debugDisableShadows = false;
    await _fonts();
    Directory(_out).createSync(recursive: true);
  });
  tearDownAll(() {
    File('$_out/_exceptions.log').writeAsStringSync(_log.join('\n'));
  });
  setUp(() {
    debugDisableShadows = false;
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  // ============ pageDeleteWhat B: two actions ============
  _t(
    'what_B1_settings_danger_390',
    _p390,
    () => _pushed(_settings()),
    then: _settingsBottom,
  );
  _t(
    'what_B2_clear_posts_confirm_390',
    _p390,
    () => _pushed(_settings()),
    then: (t) async {
      await _settingsBottom(t);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('settings-delete-posts')));
    },
  );
  _t('what_B3_delete_page_top_390', _p390, () => _pushed(_delete()));
  _t(
    'what_B3_delete_page_typed_390',
    _p390,
    () => _pushed(_delete()),
    then: _deleteBottom,
  );
  _t(
    'what_B4_profile_clearing_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(withPosts: false), deletion: 'clearing')),
    ),
  );

  // The same wall scrolled: "Opublikuj pierwszy post" above the dock.
  _t(
    'what_B4b_profile_clearing_scrolled_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(withPosts: false), deletion: 'clearing')),
    ),
    then: (t) async {
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -220));
    },
  );

  // ============ pageDeleteHow B: 30 days to restore ============
  _t(
    'how_B2_profile_pending_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
  );
  _t(
    'how_B3a_settings_pending_top_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
  );
  _t(
    'how_B3b_settings_pending_bottom_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
    then: _settingsBottom,
  );
  _t(
    'how_B3c_delete_now_confirm_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
    then: (t) async {
      await _settingsBottom(t);
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('settings-delete-now')));
    },
  );
  _t(
    'how_B4_follower_unavailable_390',
    _p390,
    () => _phone(
      _pushed(
        _profile(
          const PagesException(PagesFailure.unavailable),
          owner: false,
          fromLink: true,
        ),
      ),
    ),
  );
  _t(
    'how_B5_profile_purging_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'purging')),
    ),
  );
  _t(
    'how_B5_settings_purging_390',
    _p390,
    () => _pushed(_settings(deletion: 'purging')),
  );

  // The purge finished while settings were open: the fact and the date.
  _t(
    'how_B6_settings_deleted_390',
    _p390,
    () => _pushed(_settings(deletion: 'deleted')),
  );

  // ============ tablet 768 ============
  _t(
    'tablet_settings_danger_768',
    _tab,
    () => _pushed(_settings()),
    then: _settingsBottom,
  );
  _t(
    'tablet_delete_page_768',
    _tab,
    () => _pushed(_delete()),
    then: _deleteBottom,
  );
  _t(
    'tablet_profile_pending_768',
    _tab,
    () => _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
  );
  _t(
    'tablet_settings_pending_768',
    _tab,
    () => _pushed(_settings(deletion: 'pending')),
  );

  // ============ desktop 1440 (the shell's content slot) ============
  _t(
    'desktop_settings_danger_1440',
    _desk,
    () => _desktop(_pushed(_settings())),
    then: _settingsBottom,
  );
  _t(
    'desktop_delete_page_1440',
    _desk,
    () => _desktop(_pushed(_delete())),
    then: _deleteBottom,
  );
  _t(
    'desktop_profile_pending_1440',
    _desk,
    () => _desktop(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
  );
  _t(
    'desktop_settings_pending_1440',
    _desk,
    () => _desktop(_pushed(_settings(deletion: 'pending'))),
  );
  _t(
    'desktop_profile_clearing_1440',
    _desk,
    () => _desktop(
      _pushed(_profile(_ownerPage(withPosts: false), deletion: 'clearing')),
    ),
  );

  _t(
    'desktop_settings_deleted_1440',
    _desk,
    () => _desktop(_pushed(_settings(deletion: 'deleted'))),
  );

  // ============ Pearl ============
  const pearl = _Look(pearl: true);
  _t(
    'pearl_settings_danger_390',
    _p390,
    () => _pushed(_settings()),
    then: _settingsBottom,
    look: pearl,
  );
  _t(
    'pearl_delete_page_typed_390',
    _p390,
    () => _pushed(_delete()),
    then: _deleteBottom,
    look: pearl,
  );
  _t(
    'pearl_profile_pending_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
    look: pearl,
  );
  _t(
    'pearl_settings_pending_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
    look: pearl,
  );

  // ============ 200 % text ============
  const large = _Look(textScale: 2);
  _t(
    'text200_settings_danger_390',
    _p390,
    () => _pushed(_settings()),
    then: _settingsBottom,
    look: large,
  );
  _t(
    'text200_delete_page_top_390',
    _p390,
    () => _pushed(_delete()),
    look: large,
  );
  _t(
    'text200_delete_page_typed_390',
    _p390,
    () => _pushed(_delete()),
    then: _deleteBottom,
    look: large,
  );
  _t(
    'text200_profile_pending_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
    look: large,
  );
  _t(
    'text200_settings_pending_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
    look: large,
  );

  // ============ RTL (Arabic) and a long language (German) ============
  const arabic = _Look(locale: Locale('ar'));
  _t(
    'rtl_settings_danger_390',
    _p390,
    () => _pushed(_settings()),
    then: _settingsBottom,
    look: arabic,
  );
  _t(
    'rtl_delete_page_typed_390',
    _p390,
    () => _pushed(_delete()),
    then: _deleteBottom,
    look: arabic,
  );
  _t(
    'rtl_profile_pending_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
    look: arabic,
  );
  const german = _Look(locale: Locale('de'));
  _t(
    'de_settings_danger_390',
    _p390,
    () => _pushed(_settings()),
    then: _settingsBottom,
    look: german,
  );
  _t(
    'de_profile_pending_390',
    _p390,
    () => _phone(
      _pushed(_profile(_ownerPage(state: 'paused'), deletion: 'pending')),
    ),
    look: german,
  );
  _t(
    'en_settings_pending_390',
    _p390,
    () => _pushed(_settings(deletion: 'pending')),
    look: const _Look(locale: Locale('en')),
  );
}
