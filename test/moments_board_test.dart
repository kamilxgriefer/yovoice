// The Voice Moments single-card feed: the ranking seam the surface renders,
// per-recording author-chain entry, the story viewer with its chains, the
// per-viewer viewed-state, the live counters, and the filter chips.
//
// HISTORY: this file used to pin the Discover AVATAR BOARD (circle tiles,
// a bottom player, a shuffle control). The stories redesign replaced that
// surface with a stories feed. The approved 2026-09-11 handoff now removes
// duplicate Featured/Recent cards and the automatic wide detail panel. These
// tests target one readable card per recording; public story/detail/sheet
// contracts survive through explicit actions. What each old test PROVED stays:
//
//  * most-engaged-first ordering is asserted where the feed claims it
//    (the "Most engaged" filter, not a duplicate Featured rail);
//  * live like/comment counters still update without a reload;
//  * inline play really plays the selected recording, with no arrival grant;
//  * the avatar opens the real author chain at the first unheard recording;
//  * the Following slice still opens the full card (playback, like,
//    comment, offline download) via the Moment sheet;
//  * every width lays out without overflow as a bounded, lazy reading list.
//
// DELETED, not silently dropped: "the shuffle is still there, and it is
// a different order". The weighted-shuffle board order was a property of
// the removed avatar board; the feed's Discover filter now renders
// newest-first, with a separate engagement filter, and the shuffle
// arithmetic itself is still proven in moments_discovery_test.dart. The
// re-target that survives is that the reload control performs a real
// second load.
//
// `moments_discovery_test.dart` still owns the ranking arithmetic, the
// shuffle, the safety/expiry filter and the five feed states; this file
// owns what the surface does with them.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

const _me = 'me';

/// One fixed "now" for the run: every live fixture sits inside its
/// 24-hour life the way `finalizeMomentDraft` writes it, because a
/// Moment without a future `expiresAt` is (correctly) filtered out of
/// every feed before it can render.
final DateTime _anchor = DateTime.now();

VoiceMoment _moment(
  String id, {
  String author = 'author',
  String? authorName,
  int likes = 0,
  int comments = 0,
  int durationSeconds = 12,
  bool published = true,
  Duration age = const Duration(hours: 2),
}) => VoiceMoment(
  id: id,
  authorId: author,
  authorName: authorName ?? 'Author $author',
  authorPhotoUrl: null,
  caption: 'caption $id',
  audioUrl: null,
  mediaGeneration: '1700000000000001',
  durationSeconds: durationSeconds,
  likeCount: likes,
  commentCount: comments,
  isPublished: published,
  createdAt: _anchor.subtract(age),
  expiresAt: _anchor.subtract(age).add(const Duration(hours: 24)),
  schemaVersion: 2,
  status: 'published',
  isDeleted: false,
);

Map<String, dynamic> _doc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'mediaGeneration': moment.mediaGeneration,
  'mediaContentType': 'audio/mp4',
  'mediaSize': 4096,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

Finder _feedScrollable() => find.descendant(
  of: find.byKey(const ValueKey('moments-feed-scroll')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

/// Lazy cards must be reached through the actual list. Callers walk forward
/// through the expected order instead of requiring every recording to mount.
Future<void> _revealFeedRow(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey('moment-row-$id'));
  if (row.evaluate().isEmpty) {
    await tester.scrollUntilVisible(row, 220, scrollable: _feedScrollable());
  }
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  expect(row, findsOneWidget);
}

Future<double> _rowContentTop(WidgetTester tester, String id) async {
  await _revealFeedRow(tester, id);
  final scroll = tester.state<ScrollableState>(_feedScrollable());
  return tester.getTopLeft(find.byKey(ValueKey('moment-row-$id'))).dy +
      scroll.position.pixels;
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  MockFirebaseAuth authMe() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));

  MomentService privateMoments({
    FakeFirebaseFirestore? firestore,
    List<Map<String, Object?>>? mediaRequests,
  }) {
    final database = firestore ?? FakeFirebaseFirestore();
    return MomentService(
      firestore: database,
      auth: authMe(),
      storage: MockFirebaseStorage(),
      mediaAccessInvoker: fakeMomentMediaAccessInvoker(requests: mediaRequests),
      readService: VoiceMomentReadService(
        viewInvoker: fakeVoiceMomentViewInvoker(
          firestore: database,
          viewerUid: _me,
        ),
      ),
    );
  }

  _QuietFeed feed({List<VoiceMoment> social = const []}) => _QuietFeed(
    firestore: FakeFirebaseFirestore(),
    auth: authMe(),
    social: social,
  );

  group('the ranking the feed renders', () {
    test('the most-engaged Moment is first, and the order is total and '
        'deterministic', () {
      final quiet = _moment('quiet', author: 'a');
      final loud = _moment('loud', author: 'b', likes: 40);
      final talked = _moment('talked', author: 'c', likes: 2, comments: 6);

      final ranked = MomentDiscoveryService.rankByEngagement([
        quiet,
        loud,
        talked,
      ]);
      expect(ranked.map((m) => m.id), ['loud', 'talked', 'quiet']);

      // Same input in a different order must produce the same ranking;
      // otherwise "most engaged at the top" would depend on which pool
      // query happened to answer first.
      expect(
        MomentDiscoveryService.rankByEngagement([
          talked,
          quiet,
          loud,
        ]).map((m) => m.id),
        ['loud', 'talked', 'quiet'],
      );
    });

    test('comments count, and nothing is dropped', () {
      final input = [
        for (var i = 0; i < 20; i++) _moment('m$i', author: 'a$i', comments: i),
      ];
      final ranked = MomentDiscoveryService.rankByEngagement(input);
      expect(ranked.length, input.length);
      expect(ranked.map((m) => m.id).toSet(), input.map((m) => m.id).toSet());
      expect(ranked.first.id, 'm19');
    });
  });

  group('the story chain model', () {
    test('one author\'s chain runs oldest → newest, ties broken on id', () {
      final chains = buildMomentChains([
        _moment('new', author: 'a', age: const Duration(hours: 1)),
        _moment('old', author: 'a', age: const Duration(hours: 5)),
        _moment('mid', author: 'a', age: const Duration(hours: 3)),
      ]);
      expect(chains, hasLength(1));
      expect(chains.single.moments.map((m) => m.id), ['old', 'mid', 'new']);
    });

    test('the strip orders authors by their NEWEST Moment, freshest first', () {
      final chains = buildMomentChains([
        _moment('a1', author: 'a', age: const Duration(hours: 6)),
        _moment('b1', author: 'b', age: const Duration(hours: 1)),
        _moment('a2', author: 'a', age: const Duration(hours: 4)),
      ]);
      expect(chains.map((c) => c.authorId), ['b', 'a']);
    });

    test('viewed state: a chain is unviewed while ANY link is unheard, and '
        'the viewer opens at the first unheard one', () {
      final chain = buildMomentChains([
        _moment('c1', author: 'a', age: const Duration(hours: 5)),
        _moment('c2', author: 'a', age: const Duration(hours: 3)),
        _moment('c3', author: 'a', age: const Duration(hours: 1)),
      ]).single;

      expect(chain.hasUnviewed(const {'c1'}), isTrue);
      expect(chain.firstUnviewedIndex(const {'c1'}), 1);
      expect(chain.hasUnviewed(const {'c1', 'c2', 'c3'}), isFalse);
      // Everything heard: re-open from the start rather than nowhere.
      expect(chain.firstUnviewedIndex(const {'c1', 'c2', 'c3'}), 0);
    });
  });

  group('the Discover feed', () {
    testWidgets('Discover has no duplicate Featured rail, and the Most '
        'engaged filter orders every recording by engagement — '
        'regardless of the order the pool was handed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            // Deliberately worst case: the pool handed the feed the
            // most-liked Moment LAST. This is exactly the old reported
            // "a popular one gets buried".
            discoveryService: _StaticDiscovery([
              _moment('quiet', author: 'a', age: const Duration(hours: 1)),
              _moment('talked', author: 'c', likes: 2, comments: 6),
              _moment(
                'loud',
                author: 'b',
                likes: 40,
                age: const Duration(hours: 3),
              ),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Discover is newest first; popularity has its own explicit filter.
      expect(find.byKey(const ValueKey('moment-row-quiet')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-featured-loud')), findsNothing);

      // The Most engaged filter re-orders the entire list. The chip may
      // sit past the fold of the horizontal chip scroller on a phone.
      await tester.ensureVisible(
        find.byKey(const ValueKey('moments-filter-mostEngaged')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('moments-filter-mostEngaged')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final loudTop = await _rowContentTop(tester, 'loud');
      // The real count travels with the actual action, not decorative copy.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-like-loud')),
          matching: find.text('Likes: 40'),
        ),
        findsOneWidget,
      );
      final talkedTop = await _rowContentTop(tester, 'talked');
      final quietTop = await _rowContentTop(tester, 'quiet');
      expect(
        loudTop,
        lessThan(talkedTop),
        reason: 'Likes: 40 must sit ahead of Likes: 2 and Comments: 6',
      );
      expect(
        talkedTop,
        lessThan(quietTop),
        reason: 'engagement of any kind must sit ahead of none',
      );
    });

    testWidgets('a feed of ONE renders composed, with an honest total and '
        'the creation entry reachable', (tester) async {
      // Production reality when this was written: exactly one live
      // Moment. A feed that only looks composed when it is full is a
      // feed that is broken on day one.
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            discoveryService: _StaticDiscovery([
              _moment('solo', author: _me, likes: 1, comments: 1),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('moment-row-solo')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-row-chain-solo')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moments-chain-me')), findsNothing);
      expect(find.byKey(const ValueKey('moments-create-cta')), findsOneWidget);
      expect(
        find.text('That is the only live Moment right now.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('yo-moments-create-sheet')),
        findsOneWidget,
      );
      expect(find.text('Create Voice Moment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the older recording has one reachable card whose inline '
        'play targets that exact Moment, without opening a story', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final player = _FakeAudioPlayer();
      final mediaRequests = <Map<String, Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            momentService: privateMoments(mediaRequests: mediaRequests),
            playerFactory: () => player,
            discoveryService: _StaticDiscovery([
              _moment(
                'first',
                author: 'a',
                likes: 9,
                age: const Duration(hours: 4),
              ),
              _moment('second', author: 'a', age: const Duration(hours: 1)),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(player.playCount, 0);
      expect(mediaRequests, isEmpty);

      await _revealFeedRow(tester, 'first');
      final play = find.byKey(const ValueKey('moment-row-play-first'));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(player.playCount, 1);
      expect(mediaRequests.map((request) => request['momentId']), ['first']);
      expect(
        player.lastUrl,
        'https://storage.googleapis.com/yovoice-test/'
        'first.m4a?X-Goog-Signature=test',
      );
      expect(find.byType(MomentStoryViewer), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-first')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-featured-first')), findsNothing);
      expect(
        find.descendant(of: play, matching: find.byIcon(Icons.pause_rounded)),
        findsOneWidget,
      );
    });

    testWidgets(
      'nothing requests media or records a view on arrival; row '
      'play starts the exact recording inline and marks only that one heard',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final player = _FakeAudioPlayer();
        final mediaRequests = <Map<String, Object?>>[];
        final db = FakeFirebaseFirestore();
        final views = MomentViewsService(firestore: db, auth: authMe());
        await tester.pumpWidget(
          MaterialApp(
            home: MomentsScreen(
              feedService: feed(),
              auth: authMe(),
              momentService: privateMoments(mediaRequests: mediaRequests),
              viewsService: views,
              playerFactory: () => player,
              discoveryService: _StaticDiscovery([
                _moment(
                  'first',
                  author: 'a',
                  likes: 9,
                  age: const Duration(hours: 4),
                ),
                _moment('second', author: 'a', age: const Duration(hours: 1)),
              ]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Audio that starts by itself is how a person closes the tab.
        expect(player.playCount, 0);
        expect(mediaRequests, isEmpty);
        expect(
          (await db
                  .collection('users')
                  .doc(_me)
                  .collection('momentViews')
                  .get())
              .docs,
          isEmpty,
        );

        await tester.tap(find.byKey(const ValueKey('moment-row-play-second')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 100));

        expect(player.playCount, 1);
        expect(mediaRequests.map((request) => request['momentId']), ['second']);
        expect(
          player.lastUrl,
          'https://storage.googleapis.com/yovoice-test/'
          'second.m4a?X-Goog-Signature=test',
        );
        expect(find.byType(MomentStoryViewer), findsNothing);
        final heard = await db
            .collection('users')
            .doc(_me)
            .collection('momentViews')
            .get();
        expect(heard.docs.map((doc) => doc.id), ['second']);
        expect(heard.docs.single.data().keys.toList(), ['viewedAt']);
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('moment-row-progress-second')),
              )
              .value,
          120,
        );
      },
    );

    testWidgets('likes and comments go live WITHOUT a reload — the reported '
        'defect', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final counters = StreamController<Map<String, MomentEngagement>>();
      addTearDown(counters.close);
      final discovery = _StaticDiscovery([
        _moment('solo', author: 'a', likes: 1),
      ], counters: counters.stream);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            discoveryService: discovery,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final like = find.byKey(const ValueKey('moment-row-like-solo'));
      final comments = find.byKey(const ValueKey('moment-row-comments-solo'));
      // First paint already shows the real loaded count...
      expect(
        find.descendant(of: like, matching: find.text('Likes: 1')),
        findsOneWidget,
      );
      // ...and zero comments have an honest action label, no invented count.
      expect(
        find.descendant(of: comments, matching: find.text('Comments')),
        findsOneWidget,
      );
      expect(find.text('Comments: 0'), findsNothing);
      expect(discovery.loads, 1);

      // A like landing afterwards arrives without any reload.
      counters.add(<String, MomentEngagement>{
        'solo': const MomentEngagement(likeCount: 7, commentCount: 3),
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: like, matching: find.text('Likes: 7')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: comments, matching: find.text('Comments: 3')),
        findsOneWidget,
      );
      expect(
        discovery.loads,
        1,
        reason: 'live counters cannot require a reload',
      );
    });

    testWidgets('a counter stream that fails leaves the loaded counts alone '
        'rather than taking the feed down', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            discoveryService: _StaticDiscovery(
              [_moment('solo', author: 'a', likes: 4)],
              counters: Stream<Map<String, MomentEngagement>>.error(
                StateError('counter stream down'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final row = find.byKey(const ValueKey('moment-row-solo'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Likes: 4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reload control performs a real second load', (
      tester,
    ) async {
      // What survives of the old shuffle test: the control that redraws
      // the feed really asks the service again — it is not a no-op.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final discovery = _StaticDiscovery([
        for (var i = 0; i < 6; i++) _moment('m$i', author: 'a$i', likes: i),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            discoveryService: discovery,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(discovery.loads, 1);

      await tester.tap(find.byKey(const ValueKey('moments-discovery-refresh')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(discovery.loads, 2);
    });

    for (final width in <double>[390, 768, 1100, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('lays out with no overflow at ${width.toInt()} px and '
            '${scale}x text', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: MomentsScreen(
                  feedService: feed(),
                  auth: authMe(),
                  discoveryService: _StaticDiscovery([
                    for (var i = 0; i < 24; i++)
                      _moment(
                        'm$i',
                        author: 'a$i',
                        authorName:
                            'Aleksandra-Konstantina Wielkopolska-Nowakowska $i',
                        likes: i,
                        comments: i * 2,
                      ),
                  ]),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(tester.takeException(), isNull);
          // At 200% text the header legitimately consumes more than one
          // phone viewport, so a lazy ListView does not build the first row
          // until it is approached. Prove reachability by actually scrolling
          // the feed instead of equating "not mounted yet" with "missing".
          final firstRow = find.byKey(const ValueKey('moment-row-m0'));
          if (firstRow.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              firstRow,
              240,
              scrollable: find.descendant(
                of: find.byKey(const ValueKey('moments-feed-scroll')),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                ),
              ),
            );
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
          // Every width is the approved bounded reading list. The automatic
          // wide panel was removed, not the card's transport/detail actions.
          expect(firstRow, findsOneWidget);
          expect(
            find.byKey(const ValueKey('moments-detail-panel')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('moment-featured-m0')),
            findsNothing,
          );
          final cardBounds = tester.getRect(firstRow);
          expect(cardBounds.left, greaterThanOrEqualTo(0));
          expect(cardBounds.right, lessThanOrEqualTo(width));
          expect(cardBounds.width, lessThanOrEqualTo(880));
          final play = find.byKey(const ValueKey('moment-row-play-m0'));
          await tester.ensureVisible(play);
          await tester.pump();
          expect(play.hitTestable(), findsOneWidget);
          expect(tester.getSize(play).shortestSide, greaterThanOrEqualTo(44));
          expect(
            find.byKey(const ValueKey('moment-row-progress-m0')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('moment-row-title-m0')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          // Rows mounted by the accessibility scroll queue identity-badge
          // resolution on a one-millisecond batch timer. Drain that real
          // post-mount work rather than leaving a timer past tree disposal.
          await tester.pump(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        });
      }
    }
  });

  group('the story viewer', () {
    List<VoiceMoment> chainOfThree() => [
      _moment(
        'c1',
        author: 'a',
        age: const Duration(hours: 5),
        likes: 58,
        comments: 6,
      ),
      _moment('c2', author: 'a', age: const Duration(hours: 3)),
      _moment('c3', author: 'a', age: const Duration(hours: 1)),
    ];

    testWidgets('tells the chain oldest → newest with a live "1 of 3", and '
        'the visible next control walks it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chain = buildMomentChains(chainOfThree()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MomentStoryViewer(
              chain: chain,
              feedService: feed(),
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Opens on the OLDEST link: a story is told in the order it was
      // recorded.
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('caption c1'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-progress-bars')), findsOneWidget);
      // The document's REAL counts are visible on the action chips — a
      // flex regression once squeezed the like count to nothing while
      // free space sat next to it.
      expect(find.text('58'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);

      // The visible next control — the chain is never tap-zone-only.
      await tester.tap(find.byKey(const ValueKey('story-next')));
      await tester.pump();
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('caption c2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('story-previous')));
      await tester.pump();
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('auto-advances when a Moment finishes, and finishing the '
        'last one closes the viewer', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final player = _FakeAudioPlayer();
      final chain = buildMomentChains(chainOfThree()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  key: const ValueKey('open-viewer'),
                  onPressed: () => showMomentStoryViewer(
                    context,
                    chain: chain,
                    feedService: feed(),
                    momentService: privateMoments(),
                    playerFactory: () => player,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-viewer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      // Opening a chain plays it — that is what the tap meant.
      expect(player.playCount, 1);
      expect(
        player.lastUrl,
        'https://storage.googleapis.com/yovoice-test/'
        'c1.m4a?X-Goog-Signature=test',
      );
      expect(find.text('1 of 3'), findsOneWidget);

      // The first Moment finishes: the next one starts by itself.
      player.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(player.playCount, 2);
      expect(
        player.lastUrl,
        'https://storage.googleapis.com/yovoice-test/'
        'c2.m4a?X-Goog-Signature=test',
      );
      expect(find.text('2 of 3'), findsOneWidget);

      player.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(player.playCount, 3);
      expect(
        player.lastUrl,
        'https://storage.googleapis.com/yovoice-test/'
        'c3.m4a?X-Goog-Signature=test',
      );

      // The LAST completion closes the viewer: the chain has been told
      // in full. (The route pop animates, hence the settle.)
      player.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(MomentStoryViewer), findsNothing);
    });

    testWidgets('starting playback writes the caller\'s viewed-mark at '
        'users/{uid}/momentViews/{momentId} — and only then', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = FakeFirebaseFirestore();
      final views = MomentViewsService(firestore: db, auth: authMe());
      final player = _FakeAudioPlayer();
      final chain = buildMomentChains(chainOfThree()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MomentStoryViewer(
              chain: chain,
              feedService: feed(),
              momentService: privateMoments(),
              viewsService: views,
              playerFactory: () => player,
              autoPlay: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Merely OPENING the viewer marks nothing.
      var snapshot = await db
          .collection('users')
          .doc(_me)
          .collection('momentViews')
          .get();
      expect(snapshot.docs, isEmpty);

      await tester.tap(find.byKey(const ValueKey('story-play-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      snapshot = await db
          .collection('users')
          .doc(_me)
          .collection('momentViews')
          .get();
      expect(snapshot.docs.map((doc) => doc.id), ['c1']);
      // The rules-pinned shape: exactly one key, a server timestamp.
      expect(snapshot.docs.single.data().keys.toList(), ['viewedAt']);
    });

    testWidgets('a chain opened from a card avatar starts at the first Moment '
        'this account has NOT heard', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = FakeFirebaseFirestore();
      // The oldest link was already heard on some earlier visit.
      await db
          .collection('users')
          .doc(_me)
          .collection('momentViews')
          .doc('c1')
          .set(<String, dynamic>{'viewedAt': Timestamp.now()});
      final views = MomentViewsService(firestore: db, auth: authMe());
      final player = _FakeAudioPlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            momentService: privateMoments(),
            viewsService: views,
            playerFactory: () => player,
            discoveryService: _StaticDiscovery(chainOfThree()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(player.playCount, 0);
      expect(
        (await db.collection('users').doc(_me).collection('momentViews').get())
            .docs
            .map((doc) => doc.id),
        ['c1'],
      );
      await tester.tap(find.byKey(const ValueKey('moment-row-chain-c3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('2 of 3'), findsOneWidget);
      expect(
        player.lastUrl,
        'https://storage.googleapis.com/yovoice-test/'
        'c2.m4a?X-Goog-Signature=test',
      );
      expect(player.playCount, 1);
      final heard = await db
          .collection('users')
          .doc(_me)
          .collection('momentViews')
          .get();
      expect(heard.docs.map((doc) => doc.id), unorderedEquals(['c1', 'c2']));
    });
  });

  group('the filter chips switch data sources', () {
    testWidgets('Discover and Following draw from different pools, and Most '
        'engaged vs Recent order the same pool differently', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: feed(
              social: [
                _moment(
                  'social-1',
                  author: 'friend',
                  age: const Duration(hours: 6),
                ),
              ],
            ),
            auth: authMe(),
            discoveryService: _StaticDiscovery([
              // `pool-liked` is older but far more engaged; `pool-new`
              // is fresher. The two orderings disagree on purpose.
              _moment(
                'pool-liked',
                author: 'a',
                likes: 30,
                age: const Duration(hours: 8),
              ),
              _moment('pool-new', author: 'b', age: const Duration(hours: 1)),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      Offset at(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('moment-row-$id')));

      // Discover: the global pool, newest first — the social slice is
      // not in it.
      expect(find.byKey(const ValueKey('moment-row-pool-new')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-row-pool-liked')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moment-row-social-1')), findsNothing);
      expect(at('pool-new').dy, lessThan(at('pool-liked').dy));

      // Most engaged: same pool, engagement order — the disagreement is
      // the proof the chip changed the ordering, not just the title.
      // (Chips past the fold of the horizontal scroller are brought in
      // first — a missed tap must not pass as a no-op.)
      await tester.ensureVisible(
        find.byKey(const ValueKey('moments-filter-mostEngaged')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('moments-filter-mostEngaged')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(at('pool-liked').dy, lessThan(at('pool-new').dy));

      // Recent: back to createdAt descending.
      await tester.ensureVisible(
        find.byKey(const ValueKey('moments-filter-recent')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-filter-recent')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(at('pool-new').dy, lessThan(at('pool-liked').dy));

      // Following: the personal slice, not the pool.
      await tester.ensureVisible(
        find.byKey(const ValueKey('moments-filter-following')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-filter-following')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('moment-row-social-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-row-pool-new')), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-pool-liked')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-social-1')),
          matching: find.text('Author friend'),
        ),
        findsOneWidget,
      );
    });
  });

  group('the Following filter', () {
    late FakeFirebaseFirestore db;

    Future<MomentService> seeded(List<VoiceMoment> mine) async {
      db = FakeFirebaseFirestore();
      for (final moment in mine) {
        await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
      }
      return privateMoments(firestore: db);
    }

    Future<void> pumpFollowing(
      WidgetTester tester, {
      required MomentService moments,
      List<VoiceMoment> social = const [],
      Size size = const Size(390, 844),
      _QuietFeed? feedService,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            auth: authMe(),
            feedService: feedService ?? feed(social: social),
            discoveryService: _StaticDiscovery(const []),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('renders my Moments and my circle\'s as rows — mine with '
        'Delete in the menu, theirs with Report', (tester) async {
      // ADAPTED with the availability amendment: every row now carries an
      // overflow menu (Details for all), and its ownership half changed —
      // Delete on my own rows (the author's exit, the ONLY one for a
      // permanent Moment), Report only on someone else's.
      final moments = await seeded([
        _moment(
          'mine-1',
          author: _me,
          likes: 1,
          comments: 1,
          age: const Duration(hours: 1),
        ),
        _moment('mine-2', author: _me, age: const Duration(hours: 2)),
      ]);

      await pumpFollowing(
        tester,
        moments: moments,
        social: [_moment('theirs', author: 'friend', likes: 3)],
      );

      // My own row: Delete offered, Report absent.
      await _revealFeedRow(tester, 'mine-1');
      await tester.tap(find.byKey(const ValueKey('moment-row-menu-mine-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-delete-mine-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-row-report-mine-1')),
        findsNothing,
      );
      await tester.tapAt(Offset.zero); // dismiss the menu
      await tester.pumpAndSettle();

      // The third complete card can be outside the lazy viewport. Reach all
      // three actual recordings; do not shrink the pool to fit the old rows.
      for (final id in ['mine-2', 'theirs']) {
        await _revealFeedRow(tester, id);
      }

      // Someone else's row: Report offered, Delete absent.
      await tester.ensureVisible(
        find.byKey(const ValueKey('moment-row-menu-theirs')),
      );
      await tester.tap(find.byKey(const ValueKey('moment-row-menu-theirs')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-report-theirs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-row-delete-theirs')),
        findsNothing,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a row opens the full card in the sheet — playback, '
        'like, comment and the offline download all survive the redesign', (
      tester,
    ) async {
      final moments = await seeded([
        _moment('mine-1', author: _me, age: const Duration(hours: 1)),
      ]);

      await pumpFollowing(tester, moments: moments);

      expect(find.byType(MomentCard), findsNothing);

      await tester.tap(find.byKey(const ValueKey('moment-row-mine-1')));
      await tester.pumpAndSettle();

      expect(find.byType(MomentCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey('download-moment-mine-1')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    });

    testWidgets('the open sheet uses the v2 snapshot and a like made inside '
        'it moves its own counter without a foreign Firestore listener', (
      tester,
    ) async {
      final moments = await seeded([
        _moment(
          'mine-1',
          author: _me,
          likes: 2,
          comments: 0,
          age: const Duration(hours: 1),
        ),
      ]);
      final interactionFeed = _QuietFeed(firestore: db, auth: authMe());

      await pumpFollowing(
        tester,
        moments: moments,
        feedService: interactionFeed,
      );

      await tester.tap(find.byKey(const ValueKey('moment-row-mine-1')));
      await tester.pumpAndSettle();

      final card = find.byType(MomentCard);
      expect(
        find.descendant(of: card, matching: find.text('2')),
        findsOneWidget,
      );

      // Build 20 intentionally does not subscribe to another account's
      // Firestore document. The desired-state callable is issued once and
      // the sheet owns the optimistic counter until its next safe refresh.
      await tester.tap(find.byKey(const ValueKey('like-moment-2-false')));
      await tester.pump();
      await tester.pump();

      expect(interactionFeed.likeWrites, const ['mine-1:true']);
      expect(
        find.descendant(of: card, matching: find.text('3')),
        findsOneWidget,
      );
    });

    for (final width in <double>[390, 768, 1100, 1440]) {
      testWidgets('the personal feed lays out with no overflow at '
          '${width.toInt()} px', (tester) async {
        final moments = await seeded([
          for (var i = 0; i < 9; i++)
            _moment(
              'mine-$i',
              author: _me,
              likes: i,
              age: Duration(hours: 1, minutes: i),
            ),
        ]);

        await pumpFollowing(
          tester,
          moments: moments,
          size: Size(width, 900),
          social: [
            for (var i = 0; i < 7; i++)
              _moment(
                'theirs-$i',
                author: 'friend$i',
                authorName: 'A very long display name number $i',
                likes: i,
                age: Duration(hours: 2, minutes: i),
              ),
          ],
        );

        expect(tester.takeException(), isNull);
        // Mine lead the list; the circle's rows queue below them and are
        // reachable by scrolling the (lazy) feed.
        expect(find.byKey(const ValueKey('moment-row-mine-0')), findsOneWidget);
        // The feed's own vertical scrollable, not horizontal format/filters.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('moment-row-theirs-0')),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('moments-feed')),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        );
        expect(
          find.byKey(const ValueKey('moment-row-theirs-0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        // Rows mounted during the scroll queue identity-badge lookups on
        // a short timer; drain them so no timer outlives the tree.
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      });
    }
  });
}

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments, {this.counters});

  final List<VoiceMoment> moments;
  final Stream<Map<String, MomentEngagement>>? counters;

  int loads = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loads += 1;
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: moments.length,
      drops: const <String, MomentDropReason>{},
      seed: seed ?? 0,
      poolExhausted: false,
    );
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => counters ?? const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth, this.social = const []});

  final List<VoiceMoment> social;
  final List<String> likeWrites = <String>[];

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(social);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    likeWrites.add('$momentId:$liked');
  }
}

/// An [audio.AudioPlayer] that reports a real position shortly after play
/// and lets a test fire the completion event, so auto-advance is driven
/// the way a finished recording drives it on a device.
class _FakeAudioPlayer implements audio.AudioPlayer {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  int playCount = 0;
  int stopCount = 0;
  String? lastUrl;

  /// The finished-playing signal, under the test's control.
  void complete() {
    if (!_completions.isClosed) _completions.add(null);
  }

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    playCount += 1;
    lastUrl = source is audio.UrlSource ? source.url : null;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (_positions.isClosed) return;
        _durations.add(const Duration(seconds: 12));
        _positions.add(const Duration(milliseconds: 120));
      }),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
