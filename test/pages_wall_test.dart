// Premium Pages C2: the Treści wall A, its states, the desktop panel and
// Find Pages (spec premium-pages §2.5, §2.7, §4.2, §4.7; renders wall A, R4,
// R5, R15).
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/pages_controllers.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/content_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/content_desktop_panel.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_post_card.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

// ---------------------------------------------------------------- fixtures

final DateTime _now = DateTime.utc(2026, 9, 28, 12);

String _postId(int n) => 'pp_${n.toRadixString(16).padLeft(40, '0')}';
String _mediaId(int n) => 'pm_${n.toRadixString(16).padLeft(40, '0')}';

Map<String, Object?> _post(
  int n, {
  String pageId = 'cafe',
  String pageName = 'Kawiarnia Pod Lipą',
  String pageKind = 'business',
  String kind = 'text',
  String? text,
  List<Map<String, Object?>> media = const [],
  int likes = 48,
  int comments = 12,
  bool liked = false,
  Duration age = const Duration(hours: 2),
}) => {
  'postId': _postId(n),
  'pageId': pageId,
  'pageName': pageName,
  'pageKind': pageKind,
  'kind': kind,
  'text':
      text ??
      'Jesień weszła do karty. Od dziś latte dyniowe z cynamonem i szarlotka '
          'na ciepło z gałką lodów waniliowych.',
  'media': media,
  'createdAtMs': _now.subtract(age).millisecondsSinceEpoch,
  'likeCount': likes,
  'commentCount': comments,
  'callerLiked': liked,
  'commentsEnabled': true,
  'state': 'published',
  'pinned': false,
};

Map<String, Object?> _image(int n) => {
  'mediaId': _mediaId(n),
  'type': 'image',
  'contentType': 'image/jpeg',
  'width': 1600,
  'height': 1200,
  'durationMs': null,
};

Map<String, Object?> _card(
  String id,
  String name, {
  String kind = 'community',
  int followers = 48,
  bool follows = false,
  Duration? lastPost = const Duration(hours: 2),
}) => {
  'pageId': id,
  'displayName': name,
  'kind': kind,
  'category': kind == 'business' ? 'shop' : 'music',
  'followerCount': followers,
  'onYoVoiceSinceMs': _now.millisecondsSinceEpoch,
  'viewerFollows': follows,
  'lastPostAtMs': lastPost == null
      ? null
      : _now.subtract(lastPost).millisecondsSinceEpoch,
};

Map<String, Object?> _feed(
  List<Map<String, Object?>> posts, {
  List<Map<String, Object?>>? suggestions = const [],
  String? next,
}) => {
  'schemaVersion': 1,
  'posts': posts,
  'nextCursor': next,
  'hasMore': next != null,
  'suggestions': suggestions,
};

Map<String, Object?> _find(List<Map<String, Object?>> pages, {String? next}) =>
    {
      'schemaVersion': 1,
      'pages': pages,
      'nextCursor': next,
      'hasMore': next != null,
    };

final _suggestions = [
  _card('glina', 'Pracownia Ceramiki Glina', kind: 'business'),
  _card('chor', 'Chór Gaudium', followers: 210),
  _card('rower', 'Rowerowa Oliwa', followers: 1400),
];

FirebaseFunctionsException _refusal(String code, [String? reason]) =>
    FirebaseFunctionsException(
      code: code,
      message: 'refused',
      details: reason == null ? null : {'reason': reason},
    );

/// Records every call and answers from [handlers].
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

Stream<PageAccessState> Function() _access({bool vip = false, OwnPage? own}) =>
    () => Stream<PageAccessState>.value(
      PageAccessState(resolved: true, hasVipGrant: vip, ownPage: own),
    );

Widget _app(Widget child, {Locale locale = const Locale('pl')}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

ContentScreen _screen(
  _Backend backend, {
  bool vip = false,
  OwnPage? own,
  PagesFlows flows = const PagesFlows(openPage: _noPage),
  PagesLocalStore? store,
  Listenable? reselect,
  List<Uri>? shared,
}) => ContentScreen(
  key: UniqueKey(),
  isRootTab: true,
  service: _service(backend),
  accessStream: _access(vip: vip, own: own),
  localStore: store ?? MemoryPagesLocalStore(),
  flows: flows,
  userId: 'me',
  userDisplayName: 'Ola',
  reselect: reselect,
  clock: () => _now,
  shareLink: (link) async => shared?.add(link),
);

final List<String> _openedPages = [];

Future<void> _noPage(
  BuildContext context, {
  required String pageId,
  String? displayName,
}) async => _openedPages.add(pageId);

Future<void> _noop(BuildContext context) async {}

/// Route transitions (Android's fade-forwards) run up to 800 ms.
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
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child,
      ),
      locale: locale,
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    _openedPages.clear();
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'staffRole': 'user', 'isVip': true, 'page': 'business'},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  group('wire parsers (§2.5)', () {
    test('require every known key and ignore unknown keys', () {
      final wire = {..._post(1), 'futureKey': 'v1.1'};
      final post = PagePostView.fromWire(wire)!;
      expect(post.postId, _postId(1));
      expect(post.pageKind, PageKind.business);
      expect(post.kind, PagePostKind.text);

      final missing = Map<String, Object?>.of(_post(1))..remove('pinned');
      expect(
        () => PagePostView.fromWire(missing),
        throwsA(isA<PagesContractException>()),
      );
      expect(
        () => PagesFeedPage.fromWire({
          'schemaVersion': 1,
          'posts': <Object>[],
          'nextCursor': null,
          'hasMore': false,
        }),
        throwsA(isA<PagesContractException>()),
        reason: 'suggestions is a known key: absent is a contract break',
      );
    });

    test('skip items whose enum value this client does not know', () {
      final page = PagesFeedPage.fromWire(
        _feed(
          [
            _post(1),
            {..._post(2), 'kind': 'video'},
            {..._post(3), 'pageKind': 'shop'},
            {..._post(4), 'state': 'removed'},
            {
              ..._post(5, kind: 'photo'),
              'media': [
                {..._image(1), 'type': 'hologram'},
              ],
            },
          ],
          suggestions: [
            _card('a', 'A'),
            _card('b', 'B', kind: 'club'),
          ],
        ),
      );
      expect(page.posts.map((p) => p.postId), [_postId(1)]);
      expect(page.suggestions!.map((c) => c.pageId), ['a']);
    });

    test(
      'negative or fractional counters read as 0; media must match kind',
      () {
        final post = PagePostView.fromWire({
          ..._post(1),
          'likeCount': -3,
          'commentCount': 1.5,
        })!;
        expect(post.likeCount, 0);
        expect(post.commentCount, 0);
        expect(
          PagePostView.fromWire(_post(2, kind: 'photo')),
          isNull,
          reason: 'a photo post without images cannot be drawn',
        );
        expect(PagePostView.fromWire({..._post(3), 'postId': 'pp_x'}), isNull);
      },
    );

    test('a page without a cursor never offers more', () {
      final page = PagesFeedPage.fromWire({
        ..._feed([]),
        'hasMore': true,
        'nextCursor': null,
      });
      expect(page.hasMore, isFalse);
      expect(
        FindPagesPage.fromWire({..._find([]), 'hasMore': true}).hasMore,
        isFalse,
      );
    });
  });

  group('PagesService (§2)', () {
    test('sends the exact requests', () async {
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([]),
        PagesService.findCallable: (_) => _find([]),
        PagesService.engagementCallable: (_) => {'ok': true},
        PagesService.followCallable: (_) => {'ok': true},
      });
      final service = _service(backend);
      await service.getFeed();
      await service.getFeed(cursor: 'abc');
      await service.findPages(mode: FindPagesMode.suggest, query: 'ignored');
      await service.findPages(mode: FindPagesMode.search, query: '  Pi ');
      await service.findPages(mode: FindPagesMode.following, cursor: 'c2');
      await service.setLiked(_postId(7), liked: true);
      await service.setLiked(_postId(7), liked: false);
      await service.setFollow('cafe', following: true);
      expect(
        [for (final call in backend.calls) call.$1],
        [
          'getPagesFeedV1',
          'getPagesFeedV1',
          'findPagesV1',
          'findPagesV1',
          'findPagesV1',
          'pagePostEngagementV1',
          'pagePostEngagementV1',
          'setFollow',
        ],
      );
      expect(
        [for (final call in backend.calls) call.$2],
        [
          {'cursor': null},
          {'cursor': 'abc'},
          {'mode': 'suggest', 'query': null, 'cursor': null},
          {'mode': 'search', 'query': 'Pi', 'cursor': null},
          {'mode': 'following', 'query': null, 'cursor': 'c2'},
          {
            'requestId': 'pg_test_request_0001',
            'op': 'like',
            'postId': _postId(7),
          },
          {
            'requestId': 'pg_test_request_0001',
            'op': 'unlike',
            'postId': _postId(7),
          },
          {'targetUserId': 'cafe', 'following': true},
        ],
      );
    });

    test('a one-character search never reaches the server', () async {
      final backend = _Backend({});
      await expectLater(
        _service(backend).findPages(mode: FindPagesMode.search, query: ' P '),
        throwsA(isA<PagesException>()),
      );
      expect(backend.calls, isEmpty);
    });

    test('maps refusals (§4.8)', () {
      PagesFailure map(String code, [String? reason]) =>
          PagesService.failureFor(_refusal(code, reason));
      expect(
        map('failed-precondition', 'pagesNotEnabled'),
        PagesFailure.notEnabled,
      );
      expect(
        map('permission-denied', 'pageUnavailable'),
        PagesFailure.unavailable,
      );
      expect(map('permission-denied'), PagesFailure.unavailable);
      expect(
        map('failed-precondition', 'pageAccessRequired'),
        PagesFailure.accessRequired,
      );
      expect(map('resource-exhausted'), PagesFailure.rateLimited);
      expect(map('unavailable'), PagesFailure.network);
      expect(
        map('invalid-argument', 'commentLinks'),
        PagesFailure.commentLinks,
      );
    });

    test('media grants are asked once per post and memoised', () async {
      final expires = _now.add(const Duration(seconds: 90));
      final backend = _Backend({
        PagesService.mediaAccessCallable: (payload) => {
          'grants': [
            for (final id in payload['mediaIds']! as List)
              {
                'mediaId': id,
                'url': 'https://storage.example/$id',
                'expiresAtMs': expires.millisecondsSinceEpoch,
              },
            {
              'mediaId': _mediaId(99),
              'url': 'https://storage.example/other',
              'expiresAtMs': expires.millisecondsSinceEpoch,
            },
          ],
        },
      });
      final service = _service(backend);
      final ids = [_mediaId(1), _mediaId(2), 'not-a-media-id'];
      final first = await service.mediaAccess(_postId(1), ids);
      final second = await service.mediaAccess(_postId(1), ids);
      expect(first.keys, [_mediaId(1), _mediaId(2)]);
      expect(second.keys, first.keys);
      expect(backend.payloadsOf(PagesService.mediaAccessCallable), [
        {
          'postId': _postId(1),
          'mediaIds': [_mediaId(1), _mediaId(2)],
        },
      ]);
      service.clearMediaGrants();
      expect(service.cachedGrantCount, 0);
    });
  });

  group('PagesFeedController', () {
    Future<PagesFeedController> loaded(_Backend backend) async {
      final service = _service(backend);
      final controller = PagesFeedController(
        service: service,
        follows: PagesFollowRegistry(service),
      );
      await controller.load();
      return controller;
    }

    test('E1 / E3 / E4 from an empty first page', () async {
      final e1 = await loaded(
        _Backend({
          PagesService.feedCallable: (_) =>
              _feed([], suggestions: _suggestions),
          PagesService.findCallable: (_) => _find([]),
        }),
      );
      expect(e1.emptyKind, PagesFeedEmptyKind.noFollows);
      final e3 = await loaded(
        _Backend({
          PagesService.feedCallable: (_) => _feed([]),
          PagesService.findCallable: (_) => _find([]),
        }),
      );
      expect(e3.emptyKind, PagesFeedEmptyKind.noPages);
      final e4 = await loaded(
        _Backend({
          PagesService.feedCallable: (_) =>
              _feed([], suggestions: _suggestions),
          PagesService.findCallable: (_) =>
              _find([_card('cafe', 'Kawiarnia', follows: true)]),
        }),
      );
      expect(e4.emptyKind, PagesFeedEmptyKind.noNewPosts);
    });

    test('kill switch → notEnabled; other failures → error', () async {
      final off = await loaded(
        _Backend({
          PagesService.feedCallable: (_) =>
              throw _refusal('failed-precondition', 'pagesNotEnabled'),
        }),
      );
      expect(off.status, PagesFeedStatus.notEnabled);
      final down = await loaded(
        _Backend({
          PagesService.feedCallable: (_) => throw _refusal('unavailable'),
        }),
      );
      expect(down.status, PagesFeedStatus.error);
    });

    test('a refused like rolls back', () async {
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([_post(1, likes: 48)]),
        PagesService.engagementCallable: (_) =>
            throw _refusal('resource-exhausted'),
      });
      final controller = await loaded(backend);
      final pending = controller.toggleLike(_postId(1));
      expect(controller.posts.single.callerLiked, isTrue);
      expect(controller.posts.single.likeCount, 49);
      expect(await pending, PagesFailure.rateLimited);
      expect(controller.posts.single.callerLiked, isFalse);
      expect(controller.posts.single.likeCount, 48);
    });

    test('loadMore appends without duplicates', () async {
      final backend = _Backend({
        PagesService.feedCallable: (payload) => payload['cursor'] == null
            ? _feed([_post(1), _post(2)], next: 'c1')
            : _feed([_post(2), _post(3)]),
      });
      final controller = await loaded(backend);
      expect(controller.hasMore, isTrue);
      await controller.loadMore();
      expect(controller.posts.map((p) => p.postId), [
        _postId(1),
        _postId(2),
        _postId(3),
      ]);
      expect(controller.hasMore, isFalse);
    });

    test('a refresh during loadMore never leaves pagination stuck', () async {
      final pending = Completer<Object?>();
      var cursorCalls = 0;
      final backend = _Backend({
        PagesService.feedCallable: (payload) {
          if (payload['cursor'] == null) {
            return _feed([_post(1), _post(2)], next: 'c1');
          }
          cursorCalls++;
          return cursorCalls == 1 ? pending.future : _feed([_post(3)]);
        },
      });
      final controller = await loaded(backend);
      final first = controller.loadMore();
      expect(controller.loadingMore, isTrue);
      // Pull to refresh / re-tap Treści while the page is in flight.
      await controller.load();
      expect(controller.loadingMore, isFalse);
      pending.complete(_feed([_post(9)]));
      await first;
      expect(controller.loadingMore, isFalse);
      await controller.loadMore();
      expect(cursorCalls, 2);
      expect(controller.posts.map((p) => p.postId), [
        _postId(1),
        _postId(2),
        _postId(3),
      ]);
    });
  });

  group('Treści wall A — phone', () {
    _Backend populated({List<Map<String, Object?>>? posts, String? next}) =>
        _Backend({
          PagesService.feedCallable: (_) => _feed(
            posts ??
                [
                  _post(
                    1,
                    pageId: 'runners',
                    pageName: 'Klub Biegacza Oliwa',
                    pageKind: 'community',
                    kind: 'voice',
                    text: 'Trener Marek o rozgrzewce przed sobotnią dychą.',
                    media: [
                      {
                        'mediaId': _mediaId(9),
                        'type': 'audio',
                        'contentType': 'audio/mp4',
                        'width': null,
                        'height': null,
                        'durationMs': 58000,
                      },
                    ],
                    likes: 19,
                    comments: 4,
                    age: const Duration(minutes: 18),
                  ),
                  _post(2, kind: 'photo', media: [_image(1)], liked: true),
                  _post(
                    3,
                    pageId: 'runners',
                    pageName: 'Klub Biegacza Oliwa',
                    pageKind: 'community',
                    likes: 31,
                    comments: 7,
                    age: const Duration(hours: 30),
                  ),
                ],
            suggestions: _suggestions,
            next: next,
          ),
          PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
          PagesService.findCallable: (_) => _find(_suggestions),
        });

    testWidgets('header, cards, rail after the 2nd post and Wczytaj więcej', (
      tester,
    ) async {
      final backend = populated(next: 'c1');
      await _pump(tester, _screen(backend), size: const Size(390, 2400));
      expect(
        find.byKey(const ValueKey('content-screen-title')),
        findsOneWidget,
      );
      expect(find.byTooltip('Znajdź strony'), findsOneWidget);
      expect(
        find.textContaining('Klub Biegacza Oliwa', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('18 min'), findsOneWidget);
      expect(find.text('0:58'), findsOneWidget);
      // Labels or icon + tooltip, whichever fits (R15); the test font is
      // wider than Inter, so assert the tooltip both modes carry.
      expect(find.byTooltip('Lubię to'), findsWidgets);
      expect(find.byTooltip('Komentuj · Wkrótce'), findsWidgets);
      expect(find.byTooltip('Udostępnij'), findsWidgets);

      final rail = find.byKey(const ValueKey('pages-suggestion-rail'));
      expect(rail, findsOneWidget);
      final second = find.byKey(ValueKey('page-post-${_postId(2)}'));
      expect(
        tester.getTopLeft(rail).dy,
        greaterThan(tester.getTopLeft(second).dy),
      );
      expect(find.text('Obserwuj więcej stron'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pages-load-more')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('content-feed')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('pages-load-more')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.payloadsOf(PagesService.feedCallable).last, {
        'cursor': 'c1',
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('flows not built yet leave their controls disabled', (
      tester,
    ) async {
      await _pump(tester, _screen(populated()));
      final comment = tester.widget<PagesFocusInk>(
        find.byKey(const ValueKey('page-post-comment')).first,
      );
      expect(comment.onTap, isNull, reason: 'post detail arrives in C4');
      expect(find.byKey(const ValueKey('page-post-likers')), findsNothing);
      expect(
        find.text('48 polubień\u00A0·\u00A012 komentarzy'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pages-composer-entry')), findsNothing);
    });

    testWidgets('like toggles with the §4.5 semantics and the exact request', (
      tester,
    ) async {
      final backend = populated();
      backend.handlers[PagesService.engagementCallable] = (_) => {'ok': true};
      await _pump(tester, _screen(backend));
      final handle = tester.ensureSemantics();
      final like = find.byKey(const ValueKey('page-post-like')).first;
      expect(
        tester.getSemantics(like),
        matchesSemantics(
          label: 'Lubię to, 19 polubień',
          isButton: true,
          hasToggledState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(like);
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.payloadsOf(PagesService.engagementCallable).single, {
        'requestId': 'pg_test_request_0001',
        'op': 'like',
        'postId': _postId(1),
      });
      expect(find.text('20 polubień\u00A0·\u00A04 komentarze'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the likers entry is a ≥ 44 px button when a flow exists', (
      tester,
    ) async {
      final opened = <String>[];
      await _pump(
        tester,
        _screen(
          populated(),
          flows: PagesFlows(
            openPage: _noPage,
            openLikers: (context, post) async => opened.add(post.postId),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      final likers = find.byKey(const ValueKey('page-post-likers')).first;
      final size = tester.getSize(likers);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      // The likes row is only its 44 px target: it ends where the action
      // row's hairline starts, with no padding of its own (deviation §13).
      final like = find.byKey(const ValueKey('page-post-like')).first;
      final gap = tester.getRect(like).top - tester.getRect(likers).bottom;
      expect(gap, inInclusiveRange(0, 1.5));
      // Post 1 is a voice post: its transport is the body's last block.
      final body = find.byType(PageVoiceTransport).first;
      expect(
        tester.getRect(likers).top - tester.getRect(body).bottom,
        inInclusiveRange(0, 0.5),
      );
      expect(
        find.bySemanticsLabel('19 polubień, pokaż kto polubił'),
        findsOneWidget,
      );
      await tester.tap(likers);
      expect(opened, [_postId(1)]);
      handle.dispose();
    });

    testWidgets('share sends the canonical post link', (tester) async {
      final shared = <Uri>[];
      await _pump(tester, _screen(populated(), shared: shared));
      await tester.tap(find.byKey(const ValueKey('page-post-share')).first);
      await tester.pump();
      expect(shared, [buildPageLink('runners', postId: _postId(1))]);
    });

    testWidgets('card header opens the Page through the flow', (tester) async {
      await _pump(tester, _screen(populated()));
      await tester.tap(
        find.textContaining('Klub Biegacza Oliwa', findRichText: true).first,
      );
      await tester.pump();
      expect(_openedPages, ['runners']);
    });

    testWidgets('E1 lists suggestions; E2 adds the create action for a VIP', (
      tester,
    ) async {
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([], suggestions: _suggestions),
        PagesService.findCallable: (_) => _find([]),
      });
      await _pump(tester, _screen(backend));
      expect(find.byKey(const ValueKey('pages-e1')), findsOneWidget);
      expect(find.text('Tu pojawią się posty stron'), findsOneWidget);
      expect(find.text('Proponowane strony'), findsOneWidget);
      expect(find.text('Chór Gaudium'), findsOneWidget);
      expect(find.text('Utwórz swoją stronę'), findsNothing);

      await _pump(
        tester,
        _screen(
          backend,
          vip: true,
          flows: const PagesFlows(openPage: _noPage, openCreatePage: _noop),
        ),
      );
      expect(find.byKey(const ValueKey('pages-e2')), findsOneWidget);
      expect(find.text('Utwórz swoją stronę'), findsOneWidget);
    });

    testWidgets('following a suggestion from E1 reloads the wall', (
      tester,
    ) async {
      var followed = false;
      final backend = _Backend({
        PagesService.feedCallable: (_) =>
            followed ? _feed([_post(1)]) : _feed([], suggestions: _suggestions),
        PagesService.findCallable: (_) => _find([]),
        PagesService.followCallable: (payload) {
          followed = payload['following'] == true;
          return {'ok': true};
        },
      });
      await _pump(tester, _screen(backend));
      await tester.tap(find.bySemanticsLabel('Obserwuj: Chór Gaudium'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(backend.payloadsOf(PagesService.followCallable).single, {
        'targetUserId': 'chor',
        'following': true,
      });
      expect(find.byKey(ValueKey('page-post-${_postId(1)}')), findsOneWidget);
    });

    testWidgets('E3 empty directory; E4 no new posts', (tester) async {
      await _pump(
        tester,
        _screen(
          _Backend({
            PagesService.feedCallable: (_) => _feed([]),
            PagesService.findCallable: (_) => _find([]),
          }),
          vip: true,
          flows: const PagesFlows(openPage: _noPage, openCreatePage: _noop),
        ),
      );
      expect(find.byKey(const ValueKey('pages-e3')), findsOneWidget);
      expect(find.text('Nie ma jeszcze żadnych stron'), findsOneWidget);
      expect(find.text('Utwórz swoją stronę'), findsOneWidget);

      await _pump(
        tester,
        _screen(
          _Backend({
            PagesService.feedCallable: (_) => _feed([]),
            PagesService.findCallable: (_) =>
                _find([_card('cafe', 'Kawiarnia', follows: true)]),
          }),
        ),
      );
      expect(find.byKey(const ValueKey('pages-e4')), findsOneWidget);
      expect(find.text('Brak nowych postów'), findsOneWidget);
      expect(find.text('Znajdź więcej stron'), findsOneWidget);
    });

    testWidgets(
      'E9 under the kill switch hides search and says nothing is lost',
      (tester) async {
        await _pump(
          tester,
          _screen(
            _Backend({
              PagesService.feedCallable: (_) =>
                  throw _refusal('failed-precondition', 'pagesNotEnabled'),
            }),
          ),
        );
        expect(find.byKey(const ValueKey('pages-e9')), findsOneWidget);
        expect(find.text('Treści są chwilowo niedostępne'), findsOneWidget);
        expect(find.text('Chwilowo wyłączone'), findsOneWidget);
        expect(find.byTooltip('Znajdź strony'), findsNothing);
        expect(find.textContaining('Wkrótce'), findsNothing);
      },
    );

    testWidgets('error state retries', (tester) async {
      var fail = true;
      final backend = _Backend({
        PagesService.feedCallable: (_) {
          if (fail) throw _refusal('unavailable');
          return _feed([_post(1)]);
        },
      });
      await _pump(tester, _screen(backend));
      expect(
        find.text('Nie udało się wczytać postów. Sprawdź połączenie.'),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.text('Spróbuj ponownie'));
      await _settle(tester);
      expect(find.byKey(ValueKey('page-post-${_postId(1)}')), findsOneWidget);
    });

    testWidgets('loading shows skeleton cards', (tester) async {
      final gate = Completer<Object?>();
      final backend = _Backend({PagesService.feedCallable: (_) => gate.future});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_screen(backend)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel('Wczytywanie postów'), findsOneWidget);
      gate.complete(_feed([_post(1)]));
      await _settle(tester);
      expect(find.byKey(ValueKey('page-post-${_postId(1)}')), findsOneWidget);
    });

    testWidgets('VIP without a Page gets the dismissible create card', (
      tester,
    ) async {
      final store = MemoryPagesLocalStore();
      await _pump(
        tester,
        _screen(
          populated(),
          vip: true,
          store: store,
          flows: const PagesFlows(openPage: _noPage, openCreatePage: _noop),
        ),
      );
      expect(find.byKey(const ValueKey('pages-create-card')), findsOneWidget);
      await tester.tap(find.byTooltip('Ukryj'));
      await tester.pump();
      expect(find.byKey(const ValueKey('pages-create-card')), findsNothing);
      expect(store.dismissed, {'me'});
    });

    testWidgets('an owner with an active Page gets the composer entry', (
      tester,
    ) async {
      var composed = 0;
      await _pump(
        tester,
        _screen(
          populated(),
          vip: true,
          own: const OwnPage(
            kind: PageKind.business,
            status: 'active',
            ownerPaused: false,
            suspended: false,
          ),
          flows: PagesFlows(
            openPage: _noPage,
            openCreatePage: _noop,
            openComposer:
                (
                  context, {
                  required owner,
                  initialKind = PagePostKind.text,
                }) async {
                  composed++;
                  return null;
                },
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('pages-composer-entry')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pages-create-card')), findsNothing);
      await tester.tap(find.text('Napisz coś…'));
      expect(composed, 1);
    });

    testWidgets('re-tap pops Find back to the feed', (tester) async {
      final reselect = ValueNotifier<int>(0);
      addTearDown(reselect.dispose);
      await _pump(tester, _screen(populated(), reselect: reselect));
      await tester.tap(find.byTooltip('Znajdź strony'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('find-pages-field')), findsOneWidget);
      reselect.value++;
      await _settle(tester);
      expect(find.byKey(const ValueKey('find-pages-field')), findsNothing);
      expect(
        find.byKey(const ValueKey('content-screen-title')),
        findsOneWidget,
      );
    });
  });

  group('Find Pages (§4.7, R4)', () {
    testWidgets('suggestions, then a search, then E10', (tester) async {
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([_post(1)]),
        PagesService.findCallable: (payload) {
          if (payload['mode'] == 'suggest') return _find(_suggestions);
          if (payload['query'] == 'Pi') {
            return _find([
              _card('pilates', 'Pilates Wrzeszcz', kind: 'business'),
              _card('pilkarze', 'Piłkarze Amatorzy', follows: true),
            ]);
          }
          return _find([]);
        },
      });
      await _pump(tester, _screen(backend));
      await tester.tap(find.byTooltip('Znajdź strony'));
      await _settle(tester);
      expect(find.text('PROPONOWANE'), findsOneWidget);
      expect(find.text('Pracownia Ceramiki Glina'), findsOneWidget);
      expect(find.textContaining('post 2 godz. temu'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'P');
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        backend
            .payloadsOf(PagesService.findCallable)
            .where((p) => p['mode'] == 'search'),
        isEmpty,
        reason: 'one character keeps the suggestions',
      );
      await tester.enterText(find.byType(TextField), 'Pi');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.payloadsOf(PagesService.findCallable).last, {
        'mode': 'search',
        'query': 'Pi',
        'cursor': null,
      });
      expect(find.text('STRONY'), findsOneWidget);
      expect(find.text('Pilates Wrzeszcz'), findsOneWidget);
      expect(find.text('Obserwujesz'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Kwiaciarnia Mok');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Nic nie znaleziono'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Treści desktop and tablet', () {
    _Backend backend() => _Backend({
      PagesService.feedCallable: (_) =>
          _feed([_post(1), _post(2)], suggestions: _suggestions),
      PagesService.findCallable: (_) => _find([
        _card('runners', 'Klub Biegacza Oliwa'),
        _card('cafe', 'Kawiarnia Pod Lipą', kind: 'business'),
      ]),
      PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
    });

    testWidgets('desktop: 240 panel beside a 640 feed column, no header', (
      tester,
    ) async {
      await _pump(
        tester,
        SizedBox(
          width: 1176,
          child: _screen(
            backend(),
            vip: true,
            flows: const PagesFlows(openPage: _noPage, openCreatePage: _noop),
          ),
        ),
        size: const Size(1440, 900),
      );
      expect(find.text('Wszystkie posty'), findsOneWidget);
      expect(find.text('OBSERWOWANE'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-panel-page-cafe')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('content-panel-find')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-panel-create')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('content-screen-title')),
        findsNothing,
        reason: 'the panel carries the heading',
      );
      expect(find.byKey(const ValueKey('pages-create-card')), findsNothing);
      final card = find.byKey(ValueKey('page-post-${_postId(1)}'));
      expect(tester.getSize(card).width, 640);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('content-panel-page-cafe')));
      expect(_openedPages, ['cafe']);

      await tester.tap(find.byKey(const ValueKey('content-panel-find')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('find-pages-field')), findsOneWidget);
      expect(
        find.text('Wszystkie posty'),
        findsOneWidget,
        reason: 'panel stays',
      );
      await tester.tap(find.byKey(const ValueKey('content-panel-all-posts')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('find-pages-field')), findsNothing);
    });

    testWidgets('desktop panel shows the D10 dot for posts newer than seen', (
      tester,
    ) async {
      final store = MemoryPagesLocalStore()
        ..baselines['me'] = {
          'runners': _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        };
      await _pump(
        tester,
        SizedBox(width: 1176, child: _screen(backend(), store: store)),
        size: const Size(1440, 900),
      );
      expect(
        find.byKey(const ValueKey('content-panel-dot-runners')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('content-panel-dot-cafe')),
        findsNothing,
        reason: 'a Page seen for the first time takes a baseline, no dot',
      );
      await tester.tap(
        find.byKey(const ValueKey('content-panel-page-runners')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('content-panel-dot-runners')),
        findsNothing,
      );
    });

    testWidgets('tablet: one centred column, phone header', (tester) async {
      await _pump(tester, _screen(backend()), size: const Size(820, 1180));
      expect(
        find.byKey(const ValueKey('content-screen-title')),
        findsOneWidget,
      );
      expect(find.text('Wszystkie posty'), findsNothing);
      final card = find.byKey(ValueKey('page-post-${_postId(1)}'));
      expect(tester.getSize(card).width, 640);
      expect(tester.getCenter(card).dx, closeTo(410, 1));
    });

    testWidgets('desktop at 620 px tall and 200 % does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        SizedBox(width: 1016, child: _screen(backend())),
        size: const Size(1280, 620),
        textScale: 2,
      );
      expect(find.text('Wszystkie posty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('R15: 320 px and 200 %', () {
    testWidgets('card and rail adapt without overflow', (tester) async {
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([
          _post(
            1,
            kind: 'photo',
            media: [_image(1), _image(2), _image(3), _image(4), _image(5)],
          ),
          _post(2),
        ], suggestions: _suggestions),
        PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
      });
      await _pump(
        tester,
        _screen(
          backend,
          flows: PagesFlows(
            openPage: _noPage,
            openLikers: (context, post) async {},
          ),
        ),
        size: const Size(320, 568),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      // Labels drop to icon + tooltip; targets stay 48 tall.
      expect(find.text('Lubię to'), findsNothing);
      expect(find.byTooltip('Lubię to'), findsWidgets);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('page-post-like')).first)
            .height,
        48,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('page-post-likers')).first)
            .height,
        greaterThanOrEqualTo(44),
      );
      // "+N" on the fourth tile.
      expect(find.text('+1'), findsOneWidget);
      // The rail turns into a vertical list at ≥ 1.3×.
      await tester.scrollUntilVisible(
        find.text('Obserwuj więcej stron'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('content-feed')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pages-suggestion-rail')),
          matching: find.byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rail tiles grow with text below 1.3×', (tester) async {
      final backend = _Backend({
        PagesService.feedCallable: (_) =>
            _feed([_post(1), _post(2)], suggestions: _suggestions),
      });
      Future<double> railHeight(double scale) async {
        await _pump(
          tester,
          _screen(backend),
          size: const Size(390, 2400),
          textScale: scale,
        );
        final list = find.descendant(
          of: find.byKey(const ValueKey('pages-suggestion-rail')),
          matching: find.byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal,
          ),
        );
        expect(list, findsOneWidget);
        return tester.getSize(list).height;
      }

      final base = await railHeight(1);
      final bigger = await railHeight(1.2);
      expect(bigger, greaterThan(base));
      expect(tester.takeException(), isNull);
    });
  });

  group('English copy', () {
    testWidgets('counts and actions read in English', (tester) async {
      await _pump(
        tester,
        _screen(
          _Backend({
            PagesService.feedCallable: (_) =>
                _feed([_post(1, likes: 1, comments: 2)]),
          }),
        ),
        locale: const Locale('en'),
      );
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('1 like\u00A0·\u00A02 comments'), findsOneWidget);
      expect(find.byTooltip('Like'), findsOneWidget);
      expect(find.textContaining('Business'), findsWidgets);
      expect(find.textContaining('2 h'), findsOneWidget);
    });
  });

  // ------------------------------------------------ review fixes (a11y)

  group('review fixes: accessibility', () {
    _Backend desktopBackend() => _Backend({
      PagesService.feedCallable: (_) =>
          _feed([_post(1), _post(2)], suggestions: _suggestions),
      PagesService.findCallable: (_) => _find([
        _card('runners', 'Klub Biegacza Oliwa'),
        _card('cafe', 'Kawiarnia Pod Lipą', kind: 'business'),
      ]),
      PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
    });

    List<String> captureAnnouncements(WidgetTester tester) {
      final messages = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              final data = message['data'] as Map<Object?, Object?>;
              messages.add('${data['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler(SystemChannels.accessibility, null),
      );
      return messages;
    }

    testWidgets('desktop: the rail and the panel stay in the semantics tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Row(
          children: [
            DesktopSidebar(
              active: DesktopNavItem.content,
              showContent: true,
              unreadConversationCount: 0,
              unreadNotificationCount: 0,
              onSelect: (_) {},
              onCreateRoom: () {},
              onCreateMoment: () {},
              onOpenProfile: () {},
              onOpenProfileSettings: () {},
            ),
            Expanded(child: _screen(desktopBackend())),
          ],
        ),
        size: const Size(1440, 900),
      );
      expect(find.text('Wszystkie posty'), findsOneWidget);
      for (final label in ['Czaty', 'Treści', 'Wszystkie posty']) {
        expect(
          find.bySemanticsLabel(RegExp(label)),
          findsWidgets,
          reason: '$label must stay reachable by assistive tech',
        );
      }
      expect(find.bySemanticsLabel(RegExp('Znajdź strony')), findsWidgets);
      // A route pushed on Treści's navigator (Find) keeps the panel too.
      await tester.tap(find.byKey(const ValueKey('content-panel-find')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('find-pages-field')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Wszystkie posty')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Czaty')), findsWidgets);
      handle.dispose();
    });

    testWidgets('desktop: Tab reaches the panel from the feed (no trap)', (
      tester,
    ) async {
      await _pump(
        tester,
        SizedBox(width: 1176, child: _screen(desktopBackend())),
        size: const Size(1440, 900),
      );
      final order = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final context = FocusManager.instance.primaryFocus?.context;
        if (context == null) continue;
        final inPanel =
            context.findAncestorWidgetOfExactType<ContentDesktopPanel>() !=
            null;
        order.add(inPanel ? 'panel' : 'feed');
      }
      expect(order, contains('feed'));
      expect(order, contains('panel'), reason: '$order');
      // The whole panel is one run (its rows in order, never interleaved).
      final first = order.indexOf('panel');
      expect(order.sublist(first, first + 5), everyElement('panel'));
    });

    testWidgets('phone: a banner above Treści stays in the semantics tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Column(
          children: [
            const Text('Potwierdź adres e-mail'),
            Expanded(child: _screen(desktopBackend())),
          ],
        ),
      );
      expect(find.bySemanticsLabel('Potwierdź adres e-mail'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('card headers are one labelled button with VIP', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _screen(desktopBackend()));
      final header = find.byKey(const ValueKey('page-post-header')).first;
      expect(
        tester.getSemantics(header),
        isSemantics(isButton: true, hasTapAction: true),
      );
      final label = tester.getSemantics(header).label;
      expect(label, startsWith('Kawiarnia Pod Lipą, Firma, 2 godz.'));
      expect(label, contains('VIP'));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('desktop wall and Find meet the labelled-target guideline', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        SizedBox(width: 1176, child: _screen(desktopBackend())),
        size: const Size(1440, 900),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byKey(const ValueKey('content-panel-find')));
      await _settle(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a trimmed rail name is read whole, with VIP', (tester) async {
      final handle = tester.ensureSemantics();
      const long = 'Pracownia Ceramiki Artystycznej Glina z Oliwy i Sopotu';
      await _pump(
        tester,
        _screen(
          _Backend({
            PagesService.feedCallable: (_) => _feed(
              [_post(1), _post(2)],
              suggestions: [_card('glina', long, kind: 'business')],
            ),
            PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
          }),
        ),
        textScale: 1.2,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('page-rail-open-glina')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final label = tester
          .getSemantics(find.byKey(const ValueKey('page-rail-open-glina')))
          .label;
      expect(label, contains(long));
      expect(label, contains('VIP'));
      expect(label, isNot(contains('…')));
      expect(label, isNot(contains('⁠')));
      handle.dispose();
    });

    testWidgets('Like keeps keyboard focus while the server answers', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      final backend = desktopBackend()
        ..handlers[PagesService.engagementCallable] = (_) => pending.future;
      await _pump(tester, _screen(backend));
      final like = find.byKey(const ValueKey('page-post-like')).first;
      final node = Focus.of(
        tester.element(
          find.descendant(of: like, matching: find.byType(Row)).first,
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(backend.payloadsOf(PagesService.engagementCallable), hasLength(1));
      expect(node.hasPrimaryFocus, isTrue, reason: 'busy stays focusable');
      // A second Enter while busy does nothing (no second request).
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(backend.payloadsOf(PagesService.engagementCallable), hasLength(1));
      pending.complete({'ok': true});
      await _settle(tester);
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets('Wczytaj więcej keeps focus and announces the outcome', (
      tester,
    ) async {
      final announcements = captureAnnouncements(tester);
      final pending = Completer<Object?>();
      final backend = _Backend({
        PagesService.feedCallable: (payload) => payload['cursor'] == null
            ? _feed([_post(1), _post(2)], next: 'c1')
            : pending.future,
        PagesService.mediaAccessCallable: (_) => {'grants': <Object>[]},
      });
      await _pump(tester, _screen(backend));
      final more = find.byKey(const ValueKey('pages-load-more'));
      await tester.scrollUntilVisible(
        more,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final node = Focus.of(
        tester.element(find.descendant(of: more, matching: find.byType(Text))),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Wczytywanie…'), findsOneWidget);
      expect(node.hasPrimaryFocus, isTrue, reason: 'the button stays');
      pending.complete(_feed([_post(3)]));
      await _settle(tester);
      expect(announcements, contains('Wczytano kolejne: 1'));
    });

    testWidgets('Find announces results and its empty state is live', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final announcements = captureAnnouncements(tester);
      final backend = _Backend({
        PagesService.feedCallable: (_) => _feed([_post(1)]),
        PagesService.findCallable: (payload) {
          if (payload['query'] == 'Pi') {
            return _find([_card('pilates', 'Pilates Wrzeszcz')]);
          }
          return _find(payload['mode'] == 'suggest' ? _suggestions : []);
        },
      });
      await _pump(tester, _screen(backend));
      await tester.tap(find.byTooltip('Znajdź strony'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Pi');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(announcements, contains('Wyniki wyszukiwania: 1'));
      await tester.enterText(find.byType(TextField), 'Zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.getSemantics(find.text('Nic nie znaleziono')),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });
  });
}
