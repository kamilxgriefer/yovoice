// Premium Pages C3: the Page profile B, create A, Page settings A and the
// Premium "Twoja strona" block (spec premium-pages §2.2, §2.5, §4.3, §4.4;
// renders profile B, create A, R2, R6, R8-R10, R12, R13, R15).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_catalog.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_account_actions.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_profile_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

// ---------------------------------------------------------------- fixtures

final DateTime _now = DateTime.utc(2026, 9, 28, 12);

String _postId(int n) => 'pp_${n.toRadixString(16).padLeft(40, '0')}';
String _mediaId(int n) => 'pm_${n.toRadixString(16).padLeft(40, '0')}';

Map<String, Object?> _post(
  int n, {
  String pageId = 'cafe',
  String kind = 'text',
  String state = 'published',
  bool pinned = false,
  String? text,
  List<Map<String, Object?>> media = const [],
}) => {
  'postId': _postId(n),
  'pageId': pageId,
  'pageName': 'Kawiarnia Ziarno',
  'pageKind': 'business',
  'kind': kind,
  'text': text ?? 'Od 1 października otwieramy o 7:00.',
  'media': media,
  'createdAtMs': _now.subtract(Duration(hours: n)).millisecondsSinceEpoch,
  'likeCount': 86,
  'commentCount': 12,
  'callerLiked': false,
  'commentsEnabled': true,
  'state': state,
  'pinned': pinned,
};

Map<String, Object?> _image(int n) => {
  'mediaId': _mediaId(n),
  'type': 'image',
  'contentType': 'image/jpeg',
  'width': 1600,
  'height': 1200,
  'durationMs': null,
};

Map<String, Object?> _business({
  String? website = 'https://kawiarniaziarno.pl',
  String? legal,
}) => {
  'website': website,
  'email': 'czesc@kawiarniaziarno.pl',
  'phone': '+48585550127',
  'address': 'ul. Grunwaldzka 57, Gdańsk',
  'hours': 'Pn–Pt 7:00–19:00',
  'legalNotice': legal,
};

Map<String, Object?> _header({
  String pageId = 'cafe',
  String kind = 'business',
  String state = 'active',
  int followers = 1200,
  String description =
      'Kawa speciality, domowe wypieki i duży stół do pracy. '
      'Grunwaldzka 57, codziennie od 7:00.',
  Map<String, Object?>? business,
  Map<String, Object?>? community,
}) => {
  'pageId': pageId,
  'displayName': 'Kawiarnia Ziarno',
  'kind': kind,
  'category': kind == 'business' ? 'cafe_restaurant' : 'sport',
  'description': description,
  'followerCount': followers,
  'postCount': 3,
  'onYoVoiceSinceMs': DateTime.utc(2025, 3, 10).millisecondsSinceEpoch,
  'about': {
    'business': kind == 'business' ? (business ?? _business()) : null,
    'community': kind == 'community'
        ? (community ??
              {
                'rules': 'Biegamy razem.\nBez reklam w komentarzach.',
                'linkedServer': {
                  'serverId': 'srv1',
                  'name': 'Biegacze Mokotowa',
                  'serverType': 'community',
                },
              })
        : null,
  },
  'state': state,
};

Map<String, Object?> _viewer({
  bool owner = false,
  bool following = false,
  bool canFollow = true,
  bool canMessage = true,
}) => {
  'isOwner': owner,
  'following': following,
  'canFollow': canFollow,
  'canMessage': canMessage,
};

Map<String, Object?> _page({
  Map<String, Object?>? header,
  Map<String, Object?>? viewer,
  Map<String, Object?>? pinned,
  List<Map<String, Object?>>? posts,
  String? next,
}) => {
  'schemaVersion': 1,
  'page': header ?? _header(),
  'viewer': viewer ?? _viewer(),
  'pinned': pinned,
  'posts': posts ?? [_post(2), _post(3)],
  'nextCursor': next,
  'hasMore': next != null,
};

FirebaseFunctionsException _refusal(String code, [String? reason]) =>
    FirebaseFunctionsException(
      code: code,
      message: 'refused',
      details: reason == null ? null : {'reason': reason},
    );

class _Backend {
  _Backend(this.handlers);

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final List<(String, Map<String, Object?>)> calls = [];

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add((name, payload));
    final handler = handlers[name];
    if (handler == null) throw _refusal('not-found');
    return handler(payload);
  }

  List<Map<String, Object?>> payloadsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];
}

PagesService _service(_Backend backend) => PagesService(
  invoker: backend.call,
  requestIdFactory: () => 'pg_test_request_0001',
  clock: () => _now,
);

class _Actions implements PageAccountActions {
  _Actions({this.status});

  final FriendRelationshipStatus? status;
  final List<String> log = [];

  @override
  Future<FriendRelationshipStatus?> relationship(String uid) async => status;

  @override
  Future<void> openChat(
    BuildContext context, {
    required String uid,
    required String name,
    bool recordVoice = false,
  }) async => log.add('chat:$uid:$recordVoice');

  @override
  Future<void> call(
    BuildContext context, {
    required String uid,
    required String name,
  }) async => log.add('call:$uid');

  @override
  Future<void> inviteToServer(
    BuildContext context, {
    required String uid,
    required String name,
  }) async => log.add('invite:$uid');

  @override
  Future<void> removeFriend(String uid) async => log.add('remove:$uid');

  @override
  Future<void> block(String uid) async => log.add('block:$uid');

  @override
  Future<void> openPersonalProfile(
    BuildContext context, {
    required String uid,
    String? name,
  }) async => log.add('personal:$uid');
}

UserProfile _profile({
  String uid = 'me',
  bool ageVerified = false,
  int followers = 1214,
  ProfileVisibility visibility = ProfileVisibility.public,
}) => UserProfile(
  uid: uid,
  email: 'me@example.com',
  displayName: 'Kawiarnia Ziarno',
  username: 'ziarno',
  bio: '',
  country: 'PL',
  nativeLanguage: 'pl',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  creatorAgeVerified: ageVerified,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: followers,
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
  profileVisibility: visibility,
);

OwnPage _own({
  String status = 'active',
  bool paused = false,
  bool suspended = false,
  PageKind kind = PageKind.business,
  PageBusinessInfo? business,
  DateTime? lapsedAt,
}) => OwnPage(
  kind: kind,
  status: status,
  ownerPaused: paused,
  suspended: suspended,
  category: kind == PageKind.business ? 'cafe_restaurant' : 'sport',
  description: 'Kawa speciality.',
  business: kind == PageKind.business
      ? (business ??
            const PageBusinessInfo(
              website: 'https://kawiarniaziarno.pl',
              phone: '+48585550127',
            ))
      : null,
  rules: kind == PageKind.community ? 'Biegamy razem.' : null,
  displayName: 'Kawiarnia Ziarno',
  lapsedAt: lapsedAt,
  suspensionReason: suspended ? 'spam' : null,
);

Stream<PageAccessState> Function() _access({bool vip = true, OwnPage? own}) =>
    () => Stream<PageAccessState>.value(
      PageAccessState(resolved: true, hasVipGrant: vip, ownPage: own),
    );

Widget _app(Widget home, {Locale locale = const Locale('pl')}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

/// Compact counts use a no-break space ("1,2 tys."): match any space.
Finder _meta(String text) => find.textContaining(
  RegExp('^${RegExp.escape(text).replaceAll(' ', r'\s')}\$'),
);

/// Scrolls the first scrollable until [finder] is built, then fully on
/// screen (a sliver list builds ahead of the viewport).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child,
        ),
      ),
      locale: locale,
    ),
  );
  await _settle(tester);
}

/// A shell-less route stack: a root page that pushes [screen], so Back and
/// the fallback have somewhere to go.
Widget _pushed(Widget screen) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey('open'),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => screen)),
        child: const Text('ROOT'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await _settle(tester);
}

PageProfileScreen _screen(
  _Backend backend, {
  _Actions? actions,
  bool fromLink = false,
  String userId = 'viewer',
  String pageId = 'cafe',
  OwnPage? own,
  PagesFlows flows = const PagesFlows(),
  List<Uri>? shared,
}) => PageProfileScreen(
  key: UniqueKey(),
  pageId: pageId,
  displayName: 'Kawiarnia Ziarno',
  fromLink: fromLink,
  service: _service(backend),
  actions: actions ?? _Actions(),
  flows: flows,
  userId: userId,
  clock: () => _now,
  accessStream: _access(own: own),
  shareLink: (link) async => shared?.add(link),
);

void main() {
  setUp(() {
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  // ------------------------------------------------------------ wire

  group('getPageV1 / managePageV1 wire (§2.2, §2.5)', () {
    test('PageResponse requires every known key and ignores unknown ones', () {
      final page = PageProfilePage.fromWire({
        ..._page(pinned: _post(1, pinned: true), posts: [_post(1), _post(2)]),
        'futureKey': true,
      });
      expect(page.header!.displayName, 'Kawiarnia Ziarno');
      expect(page.header!.state, PageHeaderState.active);
      expect(page.header!.business!.website, 'https://kawiarniaziarno.pl');
      expect(page.viewer!.canFollow, isTrue);
      expect(
        page.posts.map((p) => p.postId),
        [_postId(2)],
        reason: 'the pinned post leads the wall once',
      );
      final missing = Map<String, Object?>.of(_page())..remove('pinned');
      expect(
        () => PageProfilePage.fromWire(missing),
        throwsA(isA<PagesContractException>()),
      );
      final aboutMissing = _header()..['about'] = {'business': null};
      expect(
        () => PageProfilePage.fromWire(_page(header: aboutMissing)),
        throwsA(isA<PagesContractException>()),
      );
      expect(
        () => PageProfilePage.fromWire(
          _page(header: {..._header(), 'state': 'banished'}),
        ),
        throwsA(isA<PagesContractException>()),
        reason: 'an unknown header state is not guessed',
      );
    });

    test('cursor pages carry no header, viewer or pinned post', () {
      final page = PageProfilePage.fromWire({
        ..._page(),
        'page': null,
        'viewer': null,
      });
      expect(page.header, isNull);
      expect(page.viewer, isNull);
    });

    test(
      'create, update, pause, resume and post ops send exact inputs',
      () async {
        final backend = _Backend({
          'managePageV1': (payload) => {
            'pageId': 'me',
            'kind': 'business',
            'status': 'active',
            'ownerPaused': payload['op'] == 'pause',
          },
          'managePagePostV1': (payload) => {
            'schemaVersion': 1,
            'op': payload['op'],
            'postId': payload['postId'],
            'deleted': payload['op'] == 'delete',
            'pinned': payload['op'] == 'pin',
            'commentsEnabled': true,
          },
          'getPageV1': (_) => _page(),
        });
        final service = _service(backend);
        await service.createPage(
          requestId: 'pg_create_request_01',
          kind: PageKind.business,
          category: 'cafe_restaurant',
          description: 'Kawa',
          business: const PageBusinessInfo(website: 'https://a.pl'),
          rules: null,
          linkedServerId: null,
          birthDate: '1990-03-14',
        );
        await service.createPage(
          requestId: 'pg_create_request_02',
          kind: PageKind.community,
          category: 'sport',
          description: '',
          business: null,
          rules: 'Zasady',
          linkedServerId: 'srv1',
          birthDate: null,
        );
        await service.updatePage(
          kind: PageKind.business,
          category: 'shop',
          description: 'Nowy opis',
          business: PageBusinessInfo.empty,
          rules: null,
          linkedServerId: null,
        );
        await service.pausePage();
        await service.resumePage();
        await service.managePost(_postId(1), PagePostOp.pin);
        await service.getPage(pageId: 'cafe', tab: PageWallTab.photos);

        final manage = backend.payloadsOf('managePageV1');
        expect(manage[0], {
          'requestId': 'pg_create_request_01',
          'op': 'create',
          'kind': 'business',
          'category': 'cafe_restaurant',
          'description': 'Kawa',
          'business': {
            'website': 'https://a.pl',
            'email': null,
            'phone': null,
            'address': null,
            'hours': null,
            'legalNotice': null,
          },
          'community': null,
          'birthDate': '1990-03-14',
          'consentVersion': 1,
        });
        expect(manage[1]['business'], isNull);
        expect(manage[1]['community'], {
          'rules': 'Zasady',
          'linkedServerId': 'srv1',
        });
        expect(manage[1]['birthDate'], isNull);
        expect(manage[2].keys.toSet(), {
          'requestId',
          'op',
          'category',
          'description',
          'business',
          'community',
        });
        expect(manage[3], {'requestId': 'pg_test_request_0001', 'op': 'pause'});
        expect(manage[4], {
          'requestId': 'pg_test_request_0001',
          'op': 'resume',
        });
        expect(backend.payloadsOf('managePagePostV1').single, {
          'requestId': 'pg_test_request_0001',
          'postId': _postId(1),
          'op': 'pin',
        });
        expect(backend.payloadsOf('getPageV1').single, {
          'pageId': 'cafe',
          'tab': 'photos',
          'cursor': null,
        });
      },
    );

    test('refusals map to C3 failures', () {
      expect(
        PagesService.failureFor(
          _refusal('invalid-argument', 'pageLinkedServerInvalid'),
        ),
        PagesFailure.linkedServerInvalid,
      );
      expect(
        PagesService.failureFor(_refusal('invalid-argument')),
        PagesFailure.invalidInput,
      );
      expect(
        PagesService.failureFor(
          _refusal('failed-precondition', 'pageHasAudience'),
        ),
        PagesFailure.hasAudience,
      );
    });

    test('client field rules mirror the server (§2.2.1)', () {
      expect(PageFieldRules.websiteOk('https://kawiarniaziarno.pl'), isTrue);
      expect(PageFieldRules.websiteOk('http://kawiarnia.pl'), isFalse);
      expect(PageFieldRules.websiteOk('https://user:pw@a.pl'), isFalse);
      expect(PageFieldRules.websiteOk('https://a.pl:8443'), isFalse);
      expect(PageFieldRules.websiteOk('https://localhost'), isFalse);
      expect(PageFieldRules.phoneOk('+48 58 555 01 27'), isTrue);
      expect(PageFieldRules.phoneOk('585550127'), isFalse);
      expect(PageFieldRules.emailOk('czesc@kawiarniaziarno.pl'), isTrue);
      expect(PageFieldRules.emailOk('czesc@'), isFalse);
      expect(PageCatalog.allowed(PageKind.business, 'sport'), isFalse);
      expect(PageCatalog.business, hasLength(11));
      expect(PageCatalog.community, hasLength(9));
    });

    test('the owner doc reads editable fields leniently', () {
      final own = PageAccessService.ownPageFrom({
        'kind': 'community',
        'status': 'readOnly',
        'ownerPaused': false,
        'suspended': false,
        'category': 'sport',
        'description': 'Opis',
        'business': null,
        'community': {'rules': 'R', 'linkedServerId': 'srv1'},
        'displayName': 'Klub',
      })!;
      expect(own.kind, PageKind.community);
      expect(own.rules, 'R');
      expect(own.linkedServerId, 'srv1');
      expect(own.business, isNull);
      expect(own.canPublish, isFalse);
    });
  });

  // ---------------------------------------------------------- profile B

  group('Page profile B (§4.3)', () {
    testWidgets('visitor phone: header, actions, text-only tabs, own wall', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) => _page(pinned: _post(1, pinned: true)),
        'setFollow': (_) => {'ok': true},
      });
      await _pump(tester, _screen(backend));

      expect(find.byKey(const ValueKey('page-name')), findsOneWidget);
      expect(_meta('Firma · 1,2 tys. obserwujących'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-follow')), findsOneWidget);
      expect(find.byKey(const ValueKey('page-message')), findsOneWidget);
      expect(find.text('Tablica'), findsOneWidget);
      expect(find.text('Informacje'), findsOneWidget);
      expect(find.text('Zdjęcia'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('page-tabs')),
          matching: find.byIcon(Icons.view_agenda_outlined),
        ),
        findsNothing,
        reason: 'phone tabs are text only (profile B)',
      );
      expect(find.byKey(const ValueKey('page-post-pinned')), findsOneWidget);
      expect(
        find.text('Firma'),
        findsNothing,
        reason: 'no type chip on the Page\'s own wall',
      );

      await tester.tap(find.byKey(const ValueKey('page-follow')));
      await _settle(tester);
      expect(backend.payloadsOf('setFollow').single, {
        'targetUserId': 'cafe',
        'following': true,
      });
      expect(find.byKey(const ValueKey('page-following')), findsOneWidget);
      expect(_meta('Firma · 1,2 tys. obserwujących'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('follower: Obserwujesz ▾ opens "Przestań obserwować"', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) =>
            _page(viewer: _viewer(following: true, canFollow: false)),
        'setFollow': (_) => {'ok': true},
      });
      await _pump(tester, _screen(backend));
      await tester.tap(find.byKey(const ValueKey('page-following')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-unfollow')));
      await _settle(tester);
      expect(backend.payloadsOf('setFollow').single['following'], isFalse);
      expect(find.byKey(const ValueKey('page-follow')), findsOneWidget);
    });

    for (final (width, scale) in [(320.0, 1.0), (390.0, 2.0)]) {
      testWidgets('R15: the action row stacks at $width px × $scale', (
        tester,
      ) async {
        final backend = _Backend({'getPageV1': (_) => _page()});
        await _pump(
          tester,
          _screen(backend),
          size: Size(width, 844),
          textScale: scale,
        );
        final follow = tester.getRect(
          find.byKey(const ValueKey('page-follow')),
        );
        final message = tester.getRect(
          find.byKey(const ValueKey('page-message')),
        );
        expect(follow.width, closeTo(width - 32, 1));
        expect(message.top, greaterThan(follow.bottom));
        expect(
          tester.getSize(find.byKey(const ValueKey('page-more'))).height,
          greaterThanOrEqualTo(44),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'owner: Nowy post waits for a composer flow, Edytuj stronę, held',
      (tester) async {
        final backend = _Backend({
          'getPageV1': (_) => _page(
            header: _header(pageId: 'me'),
            viewer: _viewer(owner: true, canFollow: false, canMessage: false),
            posts: [
              _post(2, pageId: 'me', state: 'held'),
              _post(3, pageId: 'me'),
            ],
          ),
          'managePagePostV1': (payload) => {
            'schemaVersion': 1,
            'op': 'delete',
            'postId': payload['postId'],
            'deleted': true,
            'pinned': false,
            'commentsEnabled': true,
          },
        });
        await _pump(
          tester,
          _pushed(_screen(backend, userId: 'me', pageId: 'me', own: _own())),
        );
        await _open(tester);
        final newPost = tester.widget<YoGradientFilledButton>(
          find.byKey(const ValueKey('page-new-post')),
        );
        // The injected flows carry no composer, so Nowy post stays disabled;
        // the app's flows do carry it (asserted below).
        expect(newPost.onPressed, isNull);
        expect(PagesFlows.app.openComposer, isNotNull);
        expect(find.byKey(const ValueKey('page-edit')), findsOneWidget);
        expect(find.byKey(const ValueKey('page-follow')), findsNothing);
        expect(find.byKey(const ValueKey('page-post-held')), findsOneWidget);

        await _reveal(
          tester,
          find.byKey(const ValueKey('page-post-delete-held')),
        );
        await tester.tap(find.byKey(const ValueKey('page-post-delete-held')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
        await _settle(tester);
        expect(backend.payloadsOf('managePagePostV1').single['op'], 'delete');
        expect(find.byKey(const ValueKey('page-post-held')), findsNothing);
      },
    );

    testWidgets('owner notices: paused offers Wznów, suspended only settings', (
      tester,
    ) async {
      var state = 'paused';
      final backend = _Backend({
        'getPageV1': (_) => _page(
          header: _header(pageId: 'me', state: state),
          viewer: _viewer(owner: true, canFollow: false, canMessage: false),
        ),
        'managePageV1': (_) => {
          'pageId': 'me',
          'kind': 'business',
          'status': 'active',
          'ownerPaused': false,
        },
      });
      await _pump(
        tester,
        _screen(backend, userId: 'me', pageId: 'me', own: _own(paused: true)),
      );
      expect(find.byKey(const ValueKey('page-notice-paused')), findsOneWidget);
      state = 'active';
      await tester.tap(find.byKey(const ValueKey('page-resume')));
      await _settle(tester);
      expect(backend.payloadsOf('managePageV1').single['op'], 'resume');
      expect(find.byKey(const ValueKey('page-new-post')), findsOneWidget);

      state = 'suspended';
      await _pump(
        tester,
        _screen(
          backend,
          userId: 'me',
          pageId: 'me',
          own: _own(suspended: true),
        ),
      );
      expect(
        find.byKey(const ValueKey('page-notice-suspended')),
        findsOneWidget,
      );
      expect(find.textContaining('Powód: spam'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('page-settings-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('page-new-post')), findsNothing);
    });

    testWidgets('visitor of a read-only Page: no Obserwuj, comments closed', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) => _page(
          header: _header(state: 'readOnly'),
          viewer: _viewer(canFollow: false),
        ),
      });
      await _pump(
        tester,
        _screen(
          backend,
          flows: PagesFlows(
            openPost:
                (
                  context, {
                  required pageId,
                  required postId,
                  initial,
                  focusComposer = false,
                  pageReadOnly = false,
                }) async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('page-follow')), findsNothing);
      expect(
        find.byKey(const ValueKey('page-notice-visitor-read-only')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('page-message')), findsOneWidget);
      final comment = tester.widget<PagesFocusInk>(
        find.byKey(const ValueKey('page-post-comment')).first,
      );
      expect(comment.onTap, isNull, reason: 'D14: comments closed');
    });

    testWidgets('Informacje: business rows, legal notice, not-verified line', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) => _page(
          header: _header(business: _business(legal: 'Ziarno sp. z o.o.')),
        ),
      });
      final actions = _Actions();
      await _pump(tester, _screen(backend, actions: actions));
      await tester.tap(find.byKey(const ValueKey('page-tab-about')));
      await _settle(tester);
      expect(find.text('Kontakt i godziny'), findsOneWidget);
      expect(find.text('Kawiarnia i restauracja'), findsOneWidget);
      expect(find.text('kawiarniaziarno.pl'), findsOneWidget);
      expect(find.text('od marca 2025'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('page-about-report')));
      expect(
        find.text('YO Voice nie weryfikuje tożsamości ani danych firm.'),
        findsOneWidget,
      );
      expect(find.text('Ziarno sp. z o.o.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('page-about-report')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-about-report')));
      await _settle(tester);
      // A Page report (§2.10), not an account report: it reaches Page
      // moderation with the Page's snapshot.
      backend.handlers['createPageReportV1'] = (_) => {'ok': true};
      await tester.tap(
        find.byKey(const ValueKey('report-reason-impersonation')),
      );
      await _settle(tester);
      final report = backend.payloadsOf('createPageReportV1').single;
      expect(report['targetType'], 'page');
      expect(report['pageId'], 'cafe');
      expect(report['postId'], isNull);
      expect(report['commentId'], isNull);
      expect(report['reason'], 'impersonation');
      expect(report['requestId'], isA<String>());
      expect(actions.log, isEmpty);
      expect(find.text('Zgłoszono. Nasz zespół to sprawdzi.'), findsOneWidget);
    });

    testWidgets('Informacje: community rules and the linked server', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) => _page(header: _header(kind: 'community')),
      });
      await _pump(tester, _screen(backend));
      expect(_meta('Społeczność · 1,2 tys. obserwujących'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-tab-about')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('page-about-rules')), findsOneWidget);
      expect(find.text('Bez reklam w komentarzach.'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('page-about-server')));
      expect(find.text('Biegacze Mokotowa'), findsOneWidget);
    });

    testWidgets('Zdjęcia loads the photos tab once, on demand', (tester) async {
      final backend = _Backend({
        'getPageV1': (payload) => payload['tab'] == 'photos'
            ? {
                ..._page(
                  posts: [
                    _post(5, kind: 'photo', media: [_image(1), _image(2)]),
                  ],
                ),
                'page': null,
                'viewer': null,
              }
            : _page(),
        'getPagePostMediaAccessV1': (_) => {'grants': <Object>[]},
      });
      await _pump(tester, _screen(backend));
      await tester.tap(find.byKey(const ValueKey('page-tab-photos')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('page-photos-grid')), findsOneWidget);
      expect(find.byKey(ValueKey('page-photo-${_mediaId(2)}')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-tab-wall')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-tab-photos')));
      await _settle(tester);
      expect(
        backend.payloadsOf('getPageV1').where((p) => p['tab'] == 'photos'),
        hasLength(1),
      );
    });

    testWidgets('R10: the friend ⋯ menu offers call, voice, invite, remove', (
      tester,
    ) async {
      final backend = _Backend({'getPageV1': (_) => _page()});
      final actions = _Actions(status: FriendRelationshipStatus.friends);
      await _pump(tester, _screen(backend, actions: actions));
      await tester.tap(find.byKey(const ValueKey('page-more')));
      await _settle(tester);
      expect(find.text('Firma · Twój znajomy'), findsOneWidget);
      for (final label in [
        'Zadzwoń',
        'Wyślij wiadomość głosową',
        'Zaproś na serwer',
        'Udostępnij stronę',
        'Zgłoś stronę',
        'Usuń ze znajomych',
        'Zablokuj',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Wyślij wiadomość głosową'));
      await _settle(tester);
      expect(actions.log, ['chat:cafe:true']);
    });

    testWidgets('R10: the visitor ⋯ menu shares, reports and blocks', (
      tester,
    ) async {
      final backend = _Backend({'getPageV1': (_) => _page()});
      final actions = _Actions(status: FriendRelationshipStatus.none);
      final shared = <Uri>[];
      await _pump(
        tester,
        _pushed(_screen(backend, actions: actions, shared: shared)),
      );
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('page-more')));
      await _settle(tester);
      expect(find.text('Zadzwoń'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-menu-share')));
      await _settle(tester);
      expect(shared.single.queryParameters['page'], 'cafe');

      await tester.tap(find.byKey(const ValueKey('page-more')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-menu-block')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
      await _settle(tester);
      expect(actions.log, ['block:cafe']);
      expect(
        find.text('ROOT'),
        findsOneWidget,
        reason: 'block leaves the Page',
      );
    });

    for (final (reason, code) in [
      ('pageUnavailable', 'permission-denied'),
      ('pagesNotEnabled', 'failed-precondition'),
    ]) {
      testWidgets('$reason falls back to the personal profile (§4.3)', (
        tester,
      ) async {
        final backend = _Backend({
          'getPageV1': (_) => throw _refusal(code, reason),
        });
        final actions = _Actions();
        await _pump(tester, _pushed(_screen(backend, actions: actions)));
        await _open(tester);
        expect(actions.log, ['personal:cafe']);
        expect(find.text('ROOT'), findsOneWidget);
      });
    }

    testWidgets('a deep link to an unavailable Page shows E7', (tester) async {
      final backend = _Backend({
        'getPageV1': (_) =>
            throw _refusal('permission-denied', 'pageUnavailable'),
      });
      final actions = _Actions();
      await _pump(
        tester,
        _pushed(_screen(backend, actions: actions, fromLink: true)),
      );
      await _open(tester);
      expect(find.byKey(const ValueKey('page-e7')), findsOneWidget);
      expect(actions.log, isEmpty);
    });

    testWidgets('tablet 820: one 640 column with a rounded cover 160', (
      tester,
    ) async {
      final backend = _Backend({'getPageV1': (_) => _page()});
      await _pump(tester, _screen(backend), size: const Size(820, 1180));
      final header = tester.getRect(
        find.byKey(const ValueKey('page-profile-header')),
      );
      expect(header.width, closeTo(640, 1));
      expect(header.left, closeTo(90, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop: header card, two tabs, a 296 about column', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (payload) => payload['tab'] == 'photos'
            ? {..._page(posts: []), 'page': null, 'viewer': null}
            : _page(),
      });
      await _pump(tester, _screen(backend), size: const Size(1280, 900));
      expect(find.byKey(const ValueKey('page-about-column')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('page-about-column'))).width,
        closeTo(296, 1),
      );
      expect(find.byKey(const ValueKey('page-tab-about')), findsNothing);
      expect(
        _meta('Firma · Kawiarnia i restauracja · 1,2 tys. obserwujących'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------ navigation and shell

  group('where the profile opens (§4.3)', () {
    testWidgets('from the feed: on Treści\'s navigator, Back returns to it', (
      tester,
    ) async {
      final backend = _Backend({
        'getPagesFeedV1': (_) => {
          'schemaVersion': 1,
          'posts': [_post(1)],
          'nextCursor': null,
          'hasMore': false,
          'suggestions': <Object>[],
        },
        'getPageV1': (_) => _page(),
      });
      await _pump(
        tester,
        Scaffold(
          body: ContentScreen(
            isRootTab: true,
            service: _service(backend),
            accessStream: _access(vip: false),
            localStore: MemoryPagesLocalStore(),
            userId: 'viewer',
            clock: () => _now,
            flows: PagesFlows(
              openPage: (context, {required pageId, displayName}) {
                expect(PagesNavigatorScope.maybeOf(context), isNotNull);
                return Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    settings: RouteSettings(name: 'pages/page/$pageId'),
                    builder: (_) => _screen(backend),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(
        find.textContaining('Kawiarnia Ziarno', findRichText: true).first,
      );
      await _settle(tester);
      expect(find.byType(PageProfileScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('page-back')));
      await _settle(tester);
      expect(find.byType(PageProfileScreen), findsNothing);
      expect(find.byKey(const ValueKey('content-feed')), findsOneWidget);
    });

    testWidgets('from outside: hosted with the dock showing Treści selected', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = _Backend({'getPageV1': (_) => _page()});
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          theme: AppTheme.darkTheme,
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: Text('SHELL')),
        ),
      );
      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => MoreDestinationHost(
              body: _screen(backend),
              selectedIndex: MainShell.contentSlot,
              unreadConversationCount: 0,
              onDestinationSelected: (_) {},
              onVoicePressed: () {},
              onMorePressed: () {},
              contentEnabled: true,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(PageProfileScreen), findsOneWidget);
      final content = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('yo-destination-3')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(content.properties.selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('page-back')));
      await _settle(tester);
      expect(find.text('SHELL'), findsOneWidget);
    });

    testWidgets('the account redirect opens only Page accounts, only with '
        'Pages on', (tester) async {
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        fetchOverride: (uids) async => {
          for (final uid in uids)
            uid: {
              'staffRole': 'user',
              'isVip': false,
              'page': uid == 'cafe' ? 'business' : null,
            },
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      final opened = <String>[];
      PagesShellBridge.host = (context, {required pageId, displayName}) async =>
          opened.add(pageId);
      addTearDown(() => PagesShellBridge.host = null);
      late BuildContext context;
      await _pump(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      bool? off;
      bool? person;
      bool? page;
      await tester.runAsync(() async {
        off = await redirectToPageProfile(
          context,
          userId: 'cafe',
          enabled: false,
        );
        person = await redirectToPageProfile(
          context,
          userId: 'ola',
          enabled: true,
        );
        page = await redirectToPageProfile(
          context,
          userId: 'cafe',
          enabled: true,
        );
      });
      await tester.pump();
      expect(off, isFalse);
      expect(person, isFalse);
      expect(page, isTrue);
      expect(opened, ['cafe']);
      expect(accountProfileRedirect, isNull, reason: 'nothing registered');
    });
  });

  // -------------------------------------------------------------- create A

  group('create A (§4.4)', () {
    CreatePageScreen create(
      _Backend backend, {
      bool ageVerified = false,
      Stream<UserProfile>? profile,
    }) => CreatePageScreen(
      service: _service(backend),
      profileStream: () =>
          profile ?? Stream.value(_profile(ageVerified: ageVerified)),
      serverStream: () => Stream.value(const []),
      birthDatePicker: (_) async => DateTime(1990, 3, 14),
      userId: 'me',
      clock: () => _now,
    );

    testWidgets('step 1 shows the corrected lines (V1, V2)', (tester) async {
      await _pump(tester, create(_Backend({})));
      expect(find.text('Krok 1 z 3'), findsOneWidget);
      expect(find.text('Przycisk „Wiadomość” na stronie'), findsOneWidget);
      expect(find.textContaining('Kontakt”'), findsNothing);
      await _reveal(tester, find.textContaining('w ustawieniach strony'));
      expect(find.textContaining('w ustawieniach strony'), findsOneWidget);
      expect(find.textContaining('Studio twórcy'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('business: details validate, preview, then create', (
      tester,
    ) async {
      final backend = _Backend({
        'managePageV1': (_) => {
          'pageId': 'me',
          'kind': 'business',
          'status': 'active',
          'ownerPaused': false,
        },
      });
      // Tall enough that the whole form is laid out (no lazy rows).
      await _pump(
        tester,
        _pushed(create(backend)),
        size: const Size(390, 2600),
      );
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.text('Krok 2 z 3'), findsOneWidget);

      // Nothing chosen yet: Dalej shows what is missing and stays.
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.text('Krok 2 z 3'), findsOneWidget);
      expect(find.text('Wybierz kategorię'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('create-category')));
      await _settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('page-category-cafe_restaurant')),
      );
      await _settle(tester);
      expect(find.text('Firma · Kawiarnia i restauracja'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('create-description')),
        'Kawa speciality.',
      );
      await _reveal(tester, find.byKey(const ValueKey('create-website')));
      await tester.enterText(
        find.byKey(const ValueKey('create-website')),
        'http://kawiarnia.pl',
      );
      await tester.pump();
      expect(find.textContaining('https://'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('create-website')),
        'https://kawiarniaziarno.pl',
      );
      await _reveal(tester, find.byKey(const ValueKey('create-phone')));
      await tester.enterText(
        find.byKey(const ValueKey('create-phone')),
        '+48 58 555 01 27',
      );
      await _reveal(tester, find.byKey(const ValueKey('create-birth-date')));
      await tester.tap(find.byKey(const ValueKey('create-birth-date')));
      await _settle(tester);
      await _reveal(tester, find.byKey(const ValueKey('create-consent')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-consent')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.text('Krok 3 z 3'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('create-preview-header')),
        findsOneWidget,
      );
      expect(find.text('Opublikuj stronę'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      final payload = backend.payloadsOf('managePageV1').single;
      expect(payload['op'], 'create');
      expect(payload['kind'], 'business');
      expect(payload['category'], 'cafe_restaurant');
      expect(payload['description'], 'Kawa speciality.');
      expect(payload['birthDate'], '1990-03-14');
      expect(payload['consentVersion'], 1);
      expect(payload['community'], isNull);
      expect(
        (payload['business']! as Map)['website'],
        'https://kawiarniaziarno.pl',
      );
      expect((payload['business']! as Map)['email'], isNull);
      expect(find.text('ROOT'), findsOneWidget, reason: 'pops with the id');
    });

    testWidgets('an attested account is never asked for its birth date', (
      tester,
    ) async {
      await _pump(tester, create(_Backend({}), ageVerified: true));
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('create-birth-date')), findsNothing);
    });

    testWidgets('a legacy pageHasAudience answer is retryable, not a dead '
        'end (owner decision 2026-09-29)', (tester) async {
      var calls = 0;
      final backend = _Backend({
        'managePageV1': (_) {
          calls++;
          if (calls == 1) {
            throw _refusal('failed-precondition', 'pageHasAudience');
          }
          return {
            'pageId': 'me',
            'kind': 'community',
            'status': 'active',
            'ownerPaused': false,
          };
        },
      });
      await _pump(
        tester,
        _pushed(create(backend, ageVerified: true)),
        size: const Size(390, 2600),
      );
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('create-kind-community')));
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-category')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-category-sport')));
      await _settle(tester);
      await _reveal(tester, find.byKey(const ValueKey('create-consent')));
      await tester.tap(find.byKey(const ValueKey('create-consent')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      final payload = backend.payloadsOf('managePageV1').single;
      expect(payload['kind'], 'community');
      expect(payload['business'], isNull);
      expect(payload['community'], {'rules': null, 'linkedServerId': null});
      expect(payload['birthDate'], isNull);
      expect(find.byKey(const ValueKey('create-error')), findsOneWidget);
      expect(
        find.textContaining('ma już obserwujących'),
        findsNothing,
        reason: 'followers never block a Page any more',
      );
      expect(
        find.text('Coś poszło nie tak. Spróbuj ponownie.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('create-close')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(backend.payloadsOf('managePageV1'), hasLength(2));
      expect(
        backend.payloadsOf('managePageV1').last['requestId'],
        payload['requestId'],
        reason: 'the same submission retries under its request id',
      );
      expect(find.text('ROOT'), findsOneWidget, reason: 'pops with the id');
    });

    /// The own users/{uid} document exactly as ProfileService reads it: the
    /// account has 1200 followers and no visible Creator audience, so the
    /// public (gated) followerCount is 0 while the Page will show 1200.
    Future<UserProfile> ownProfileWithFollowers() async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('users/me').set({
        'displayName': 'Kawiarnia Ziarno',
        'username': 'ziarno',
        'creatorAgeVerified': true,
        'followerCount': 1200,
      });
      final profile = UserProfile.fromFirestore(
        await firestore.doc('users/me').get(),
      );
      expect(profile.followerCount, 0, reason: 'the public count stays gated');
      expect(profile.accountFollowerCount, 1200);
      return profile;
    }

    testWidgets('step 3 previews the followers the account already has, as '
        'the Page will show them (ADR-234)', (tester) async {
      final profile = await tester.runAsync(ownProfileWithFollowers);
      await _pump(
        tester,
        create(_Backend({}), profile: Stream.value(profile!)),
        size: const Size(390, 2600),
      );
      await tester.tap(find.byKey(const ValueKey('create-kind-community')));
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-category')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-category-sport')));
      await _settle(tester);
      await _reveal(tester, find.byKey(const ValueKey('create-consent')));
      await tester.tap(find.byKey(const ValueKey('create-consent')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.text('Krok 3 z 3'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('create-preview-header')),
          matching: _meta('Społeczność · 1,2 tys. obserwujących'),
        ),
        findsOneWidget,
      );
      expect(_meta('Społeczność · 0 obserwujących'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide step 2: the profile preview shows the same followers', (
      tester,
    ) async {
      final profile = await tester.runAsync(ownProfileWithFollowers);
      await _pump(
        tester,
        create(_Backend({}), profile: Stream.value(profile!)),
        size: const Size(1280, 1000),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('create-primary')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('create-category')), findsOneWidget);
      expect(find.byKey(const ValueKey('create-preview-wall')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('create-preview-header')),
          matching: _meta('Firma · 1,2 tys. obserwujących'),
        ),
        findsOneWidget,
      );
      expect(_meta('Firma · 0 obserwujących'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: step tabs, side-by-side kinds, actions on the right', (
      tester,
    ) async {
      await _pump(tester, create(_Backend({})), size: const Size(1280, 800));
      expect(find.text('1  Rodzaj'), findsOneWidget);
      final business = tester.getRect(
        find.byKey(const ValueKey('create-kind-business')),
      );
      final community = tester.getRect(
        find.byKey(const ValueKey('create-kind-community')),
      );
      expect(community.top, closeTo(business.top, 1));
      expect(community.left, greaterThan(business.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px at 200 %: every step lays out', (tester) async {
      await _pump(
        tester,
        create(_Backend({})),
        size: const Size(320, 700),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ settings

  group('Page settings A (§4.4, R6)', () {
    PageSettingsScreen settings(
      _Backend backend, {
      OwnPage? own,
      UserProfile? profile,
    }) => PageSettingsScreen(
      service: _service(backend),
      accessStream: _access(own: own ?? _own()),
      profileStream: () => Stream.value(profile ?? _profile()),
      serverStream: () => Stream.value(const []),
      userId: 'me',
    );

    testWidgets('rows, count only, pause with confirmation', (tester) async {
      final backend = _Backend({
        'managePageV1': (_) => {
          'pageId': 'me',
          'kind': 'business',
          'status': 'active',
          'ownerPaused': true,
        },
      });
      await _pump(tester, settings(backend));
      expect(find.text('Ustawienia strony'), findsOneWidget);
      expect(find.text('AKTYWNA'), findsOneWidget);
      expect(find.text('Typ strony'), findsOneWidget);
      expect(find.text('Nie dodano'), findsWidgets);
      expect(find.text('Dodaj'), findsWidgets);
      await _reveal(tester, find.byKey(const ValueKey('settings-pause')));
      expect(_meta('1 214 obserwujących'), findsOneWidget);
      expect(
        find.text(
          'Widzisz tylko liczbę. Lista obserwujących nie jest dostępna.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('settings-pause')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-confirm-action')));
      await _settle(tester);
      expect(backend.payloadsOf('managePageV1').single, {
        'requestId': 'pg_test_request_0001',
        'op': 'pause',
      });
    });

    testWidgets('a contact field edits and clears through one-field sheets', (
      tester,
    ) async {
      final backend = _Backend({
        'managePageV1': (_) => {
          'pageId': 'me',
          'kind': 'business',
          'status': 'active',
          'ownerPaused': false,
        },
      });
      await _pump(tester, settings(backend));
      await tester.tap(find.byKey(const ValueKey('settings-phone')));
      await _settle(tester);
      expect(find.text('Usuń numer ze strony'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('page-field-input')),
        '12345',
      );
      await tester.tap(find.byKey(const ValueKey('page-field-save')));
      await _settle(tester);
      expect(backend.payloadsOf('managePageV1'), isEmpty);
      expect(find.textContaining('+48 58 555 01 27'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('page-field-clear')));
      await _settle(tester);
      final update = backend.payloadsOf('managePageV1').single;
      expect(update['op'], 'update');
      expect((update['business']! as Map)['phone'], isNull);
      expect(
        (update['business']! as Map)['website'],
        'https://kawiarniaziarno.pl',
        reason: 'the other fields are sent unchanged',
      );
      expect(update['community'], isNull);
    });

    testWidgets('paused after going private: resume waits for a public '
        'profile', (tester) async {
      await _pump(
        tester,
        settings(
          _Backend({}),
          own: _own(paused: true),
          profile: _profile(visibility: ProfileVisibility.private),
        ),
      );
      expect(
        find.byKey(const ValueKey('settings-notice-private')),
        findsOneWidget,
      );
      expect(find.text('WSTRZYMANA'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('settings-resume')));
      expect(find.text('Najpierw ustaw profil jako publiczny'), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-resume')),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.onTap, isNull);
    });

    testWidgets('desktop centres one 640 column', (tester) async {
      await _pump(tester, settings(_Backend({})), size: const Size(1280, 900));
      final width = tester
          .getSize(find.byKey(const ValueKey('page-settings')))
          .width;
      expect(width, closeTo(640, 1));
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------- Premium

  group('Premium "Twoja strona" block (R2, R13)', () {
    Future<void> pumpPremium(
      WidgetTester tester, {
      required bool enabled,
      required PageAccessState access,
      List<String>? log,
      bool paid = false,
    }) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      EntitlementService.resetCache();
      ProfileService.resetCurrentProfileCache();
      final db = FakeFirebaseFirestore();
      if (paid) {
        await db.doc('entitlements/me').set(<String, Object?>{
          'isPremium': true,
          'status': 'active',
          'plan': 'monthly',
          'currentPeriodEnd': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
          'premiumIdentityEnabled': true,
        });
      }
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me'),
      );
      await tester.pumpWidget(
        _app(
          PremiumScreen(
            key: UniqueKey(),
            entitlementService: EntitlementService(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            pagesEnabled: ValueNotifier(enabled),
            pagesAccessStream: () => Stream.value(access),
            onCreatePage: (_) => log?.add('create'),
            onOpenPage: (_) => log?.add('open'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a grant VIP without a Page sees "Utwórz stronę" on top', (
      tester,
    ) async {
      final log = <String>[];
      await pumpPremium(
        tester,
        enabled: true,
        access: const PageAccessState(
          resolved: true,
          hasVipGrant: true,
          ownPage: null,
        ),
        log: log,
      );
      expect(find.byKey(const ValueKey('premium-page-block')), findsOneWidget);
      expect(find.text('Dostępna z Twoim VIP'), findsOneWidget);
      expect(find.textContaining('Masz YO Voice Premium'), findsNothing);
      expect(
        find.byKey(const ValueKey('premium-page-benefit')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('premium-page-create')));
      expect(log, ['create']);
      EntitlementService.resetCache();
      ProfileService.resetCurrentProfileCache();
    });

    testWidgets('paid Premium without a VIP grant sees "Utwórz stronę" '
        '(owner decision 2026-09-29)', (tester) async {
      final log = <String>[];
      await pumpPremium(
        tester,
        enabled: true,
        paid: true,
        access: const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          hasPaidPremium: true,
          ownPage: null,
        ),
        log: log,
      );
      expect(find.byKey(const ValueKey('premium-page-block')), findsOneWidget);
      expect(find.text('Dostępna z Twoim VIP'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('premium-page-create')));
      expect(log, ['create']);
      EntitlementService.resetCache();
      ProfileService.resetCurrentProfileCache();
    });

    testWidgets('an owner sees "Otwórz stronę"', (tester) async {
      final log = <String>[];
      await pumpPremium(
        tester,
        enabled: true,
        access: PageAccessState(
          resolved: true,
          hasVipGrant: true,
          ownPage: _own(),
        ),
        log: log,
      );
      await tester.tap(find.byKey(const ValueKey('premium-page-open')));
      expect(log, ['open']);
      EntitlementService.resetCache();
      ProfileService.resetCurrentProfileCache();
    });

    testWidgets('hidden with Pages off, and for a non-VIP', (tester) async {
      await pumpPremium(
        tester,
        enabled: false,
        access: const PageAccessState(
          resolved: true,
          hasVipGrant: true,
          ownPage: null,
        ),
      );
      expect(find.byKey(const ValueKey('premium-page-block')), findsNothing);
      expect(find.byKey(const ValueKey('premium-page-benefit')), findsNothing);
      await pumpPremium(
        tester,
        enabled: true,
        access: const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          ownPage: null,
        ),
      );
      expect(find.byKey(const ValueKey('premium-page-block')), findsNothing);
      EntitlementService.resetCache();
      ProfileService.resetCurrentProfileCache();
    });
  });

  // ------------------------------------------------ review fixes

  group('review fixes: profile and create', () {
    testWidgets('Obserwuj → Obserwujesz keeps keyboard focus', (tester) async {
      final backend = _Backend({
        'getPageV1': (_) => _page(),
        'setFollow': (_) => {'ok': true},
      });
      await _pump(tester, _screen(backend));
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byKey(const ValueKey('page-follow')),
                matching: find.byType(Text),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(backend.payloadsOf('setFollow'), hasLength(1));
      final following = find.byKey(const ValueKey('page-following'));
      expect(following, findsOneWidget);
      expect(
        Focus.of(
          tester.element(
            find.descendant(of: following, matching: find.byType(Text)).first,
          ),
        ).hasPrimaryFocus,
        isTrue,
      );
    });

    testWidgets('Reduce Motion: a wall card header jumps to the top', (
      tester,
    ) async {
      final backend = _Backend({
        'getPageV1': (_) =>
            _page(posts: [for (var i = 2; i < 9; i++) _post(i)]),
      });
      await _pump(tester, _screen(backend));
      final scroll = find.byKey(const ValueKey('page-profile-scroll'));
      await tester.drag(scroll, const Offset(0, -900));
      await tester.pump();
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      expect(state.position.pixels, greaterThan(0));
      final header = find.byKey(const ValueKey('page-post-header')).last;
      await tester.ensureVisible(header);
      await tester.pump();
      await tester.tap(header);
      await tester.pump();
      expect(state.position.pixels, 0);
    });

    testWidgets('the fallback removes the profile route, not the one above', (
      tester,
    ) async {
      final answer = Completer<Object?>();
      final backend = _Backend({'getPageV1': (_) => answer.future});
      final actions = _Actions();
      await _pump(tester, _pushed(_screen(backend, actions: actions)));
      await _open(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('ABOVE')),
        ),
      );
      await _settle(tester);
      answer.completeError(_refusal('permission-denied', 'pageUnavailable'));
      await _settle(tester);
      expect(actions.log, ['personal:cafe']);
      expect(find.text('ABOVE'), findsOneWidget, reason: 'never popped');
      navigator.pop();
      await _settle(tester);
      expect(find.text('ROOT'), findsOneWidget);
      expect(find.byType(PageProfileScreen), findsNothing);
    });

    testWidgets('create step 2: an invalid Dalej focuses and announces', (
      tester,
    ) async {
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              final data = message['data'] as Map<Object?, Object?>;
              announcements.add('${data['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler(SystemChannels.accessibility, null),
      );
      await _pump(
        tester,
        _pushed(
          CreatePageScreen(
            service: _service(_Backend({})),
            profileStream: () => Stream.value(_profile()),
            serverStream: () => Stream.value(const []),
            birthDatePicker: (_) async => DateTime(1990, 3, 14),
            userId: 'me',
            clock: () => _now,
          ),
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(find.text('Krok 2 z 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-primary')));
      await _settle(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'create-category');
      expect(announcements, contains('Wybierz kategorię'));
    });
  });
}
