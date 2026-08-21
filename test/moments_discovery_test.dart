// The Moments discovery surface: the ranking seam, the shuffle, the
// safety filter (including the 24-hour expiry contract), and the five
// states of the stories-style feed.
//
// This suite deliberately tests the SEAM, not Firestore. The ranking and
// shuffle are pure functions over VoiceMoment lists, which is the whole
// reason they were written as static methods: the arithmetic Firestore
// cannot do (order by a computed sum, randomise) is provable here, and
// the parts only Firestore can prove — that the composite indexes are
// actually deployed — are called out in the report as production checks
// rather than pretended at with an emulator that does not enforce them.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// One fixed reading of "now" for the whole file, so every fixture's
/// `createdAt`/`expiresAt` relation to the clock is stable for the life
/// of a run. Every live fixture sits 2 hours into its 24-hour life —
/// the shape `finalizeMomentDraft` really writes — because since the
/// expiry contract landed, a Moment with no future `expiresAt` is
/// (correctly) filtered out of every feed before it can render.
final DateTime _anchor = DateTime.now();
final DateTime _created = _anchor.subtract(const Duration(hours: 2));
final DateTime _expires = _created.add(const Duration(hours: 24));

VoiceMoment _moment(
  String id, {
  String author = 'author',
  int likes = 0,
  int comments = 0,
  String? audioUrl = 'https://cdn.example/$_defaultAudio',
  bool deleted = false,
  bool published = true,
  int schemaVersion = 2,
  String status = 'published',
  DateTime? expiresAt,

  /// A pre-expiry legacy document: no `expiresAt` at all. Reads as
  /// already expired per the contract, never as immortal.
  bool withoutExpiry = false,
}) {
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: 'Author $author',
    authorPhotoUrl: null,
    caption: 'caption $id',
    audioUrl: audioUrl,
    durationSeconds: 12,
    likeCount: likes,
    commentCount: comments,
    isPublished: published,
    createdAt: _created,
    expiresAt: withoutExpiry ? null : (expiresAt ?? _expires),
    schemaVersion: schemaVersion,
    status: status,
    isDeleted: deleted,
  );
}

const _defaultAudio = 'a.m4a';

Map<String, dynamic> _doc(
  String id, {
  String author = 'author',
  int likes = 0,
  int comments = 0,
  String? audioUrl = 'https://cdn.example/a.m4a',
  bool deleted = false,
  bool published = true,
  DateTime? createdAt,
  DateTime? expiresAt,
  bool withoutExpiry = false,
}) => <String, dynamic>{
  'authorId': author,
  'authorName': 'Author $author',
  'authorPhotoUrl': null,
  'caption': 'caption $id',
  'audioUrl': audioUrl,
  'durationSeconds': 12,
  'likeCount': likes,
  'commentCount': comments,
  'isPublished': published,
  'createdAt': Timestamp.fromDate(createdAt ?? _created),
  if (!withoutExpiry)
    'expiresAt': Timestamp.fromDate(expiresAt ?? _expires),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': deleted,
};

void main() {
  group('ranking weight', () {
    test('zero engagement still carries a real, non-zero weight', () {
      // The +1 floor is what keeps a brand new Moment reachable. Without
      // it, a pre-launch corpus where almost everything has zero likes
      // would render as a frozen hall of fame.
      expect(MomentDiscoveryService.discoveryWeight(_moment('a')), 1.0);
    });

    test('more likes and more comments both strictly increase the weight — '
        'this is what "the popular surface more" means', () {
      final none = MomentDiscoveryService.discoveryWeight(_moment('a'));
      final liked = MomentDiscoveryService.discoveryWeight(
        _moment('b', likes: 5),
      );
      final commented = MomentDiscoveryService.discoveryWeight(
        _moment('c', comments: 5),
      );
      final both = MomentDiscoveryService.discoveryWeight(
        _moment('d', likes: 5, comments: 5),
      );
      expect(liked, greaterThan(none));
      expect(commented, greaterThan(none));
      expect(both, greaterThan(liked));
      // Comments count for less than likes: `commentCount` is the weaker
      // signal, because the Firestore rule guarding it does not require
      // a comment document to exist.
      expect(commented, lessThan(liked));
    });

    test('a forged counter cannot buy an unbounded advantage', () {
      // Neither counter is currently bound tightly enough in
      // firestore.rules for a LINEAR weight to be safe. The logarithm is
      // the ceiling: a million fabricated likes must not be a million
      // times the odds.
      final honest = MomentDiscoveryService.discoveryWeight(
        _moment('a', likes: 10),
      );
      final forged = MomentDiscoveryService.discoveryWeight(
        _moment('b', likes: 1000000),
      );
      expect(forged, greaterThan(honest));
      expect(
        forged / honest,
        lessThan(10),
        reason: 'a million fake likes must not be a jackpot',
      );
    });
  });

  group('weighted shuffle', () {
    test('is stable for a given seed and different across seeds', () {
      final moments = [for (var i = 0; i < 12; i++) _moment('m$i', likes: i)];
      final a = MomentDiscoveryService.weightedShuffle(moments, Random(7));
      final b = MomentDiscoveryService.weightedShuffle(moments, Random(7));
      final c = MomentDiscoveryService.weightedShuffle(moments, Random(8));
      expect(a.map((m) => m.id), b.map((m) => m.id));
      expect(a.map((m) => m.id), isNot(c.map((m) => m.id)));
    });

    test('loses nothing: every Moment appears exactly once', () {
      final moments = [for (var i = 0; i < 30; i++) _moment('m$i', likes: i)];
      final shuffled = MomentDiscoveryService.weightedShuffle(
        moments,
        Random(3),
      );
      expect(shuffled.length, moments.length);
      expect(
        shuffled.map((m) => m.id).toSet(),
        moments.map((m) => m.id).toSet(),
      );
    });

    test('the popular Moment leads far more often than the unknown one, '
        'without the unknown one ever being unreachable', () {
      final moments = [
        _moment('popular', author: 'a', likes: 500),
        for (var i = 0; i < 9; i++) _moment('quiet$i', author: 'q$i'),
      ];

      var popularFirst = 0;
      var quietFirst = 0;
      for (var seed = 0; seed < 400; seed++) {
        final first = MomentDiscoveryService.weightedShuffle(
          moments,
          Random(seed),
        ).first;
        if (first.id == 'popular') {
          popularFirst++;
        } else {
          quietFirst++;
        }
      }

      // Weighted, so popularity really does win more often than the 1-in-10
      // a flat shuffle would give.
      expect(popularFirst, greaterThan(120));
      // But never a fixed "most popular" list: the rest of the corpus
      // still leads most of the time, and nothing is frozen out.
      expect(quietFirst, greaterThan(0));
    });
  });

  group('author spacing', () {
    test('no author takes more than 2 of any 10 consecutive positions', () {
      // Enough distinct authors that the constraint is satisfiable all
      // the way through. (The unsatisfiable case is the next test, and
      // it appends rather than dropping real content.)
      final ranked = [
        for (var i = 0; i < 10; i++) _moment('hog$i', author: 'hog'),
        for (var i = 0; i < 50; i++) _moment('other$i', author: 'other$i'),
      ];
      final spaced = MomentDiscoveryService.spaceAuthors(ranked);

      for (var start = 0; start + 10 <= spaced.length; start++) {
        final window = spaced.sublist(start, start + 10);
        final counts = <String, int>{};
        for (final moment in window) {
          counts.update(moment.authorId, (v) => v + 1, ifAbsent: () => 1);
        }
        expect(
          counts.values.every((occurrences) => occurrences <= 2),
          isTrue,
          reason: 'window at $start is dominated by one author',
        );
      }
    });

    test('an unsatisfiable constraint appends rather than dropping real '
        'content', () {
      // One author, many Moments: the spacing rule cannot be met. A
      // discovery feed must never silently lose real content to a
      // cosmetic rule.
      final ranked = [
        for (var i = 0; i < 20; i++) _moment('solo$i', author: 'solo'),
      ];
      final spaced = MomentDiscoveryService.spaceAuthors(ranked);
      expect(spaced.length, 20);
      expect(spaced.map((m) => m.id).toSet(), ranked.map((m) => m.id).toSet());
    });
  });

  group('safety and playability filter', () {
    test('drops deleted, unplayable, blocked, expired and expiry-less — '
        'and says which is which', () {
      final result = MomentDiscoveryService.filterPlayable(
        [
          _moment('ok'),
          _moment('gone', deleted: true),
          _moment('draft', audioUrl: null),
          _moment('blank', audioUrl: '   '),
          _moment('blocked', author: 'villain'),
          // The two halves of the expiry claim: a deadline in the past,
          // and no deadline at all — BOTH must read as dead, because a
          // legacy document treated as immortal would outlive every
          // Moment published under the 24-hour contract.
          _moment(
            'dead',
            expiresAt: _anchor.subtract(const Duration(minutes: 1)),
          ),
          _moment('clockless', withoutExpiry: true),
        ],
        blockedAuthorIds: {'villain'},
        now: _anchor,
      );

      expect(result.kept.map((m) => m.id), ['ok']);
      expect(result.drops['gone'], MomentDropReason.deleted);
      expect(result.drops['draft'], MomentDropReason.unplayable);
      expect(result.drops['blank'], MomentDropReason.unplayable);
      expect(result.drops['blocked'], MomentDropReason.blockedAuthor);
      expect(result.drops['dead'], MomentDropReason.expired);
      expect(result.drops['clockless'], MomentDropReason.expired);
    });

    test('expiry is exclusive: a Moment whose expiresAt IS now is already '
        'dead', () {
      // `expiresAt <= now` hides, `expiresAt > now` shows — the boundary
      // itself must fail closed or a Moment flickers back for one frame
      // at the stroke of its own death.
      final result = MomentDiscoveryService.filterPlayable(
        [_moment('boundary', expiresAt: _anchor)],
        now: _anchor,
      );
      expect(result.kept, isEmpty);
      expect(result.drops['boundary'], MomentDropReason.expired);
    });

    test('the sweeper\'s mark is final: status expired hides a Moment even '
        'when its expiresAt is still in the future', () {
      final result = MomentDiscoveryService.filterPlayable(
        [_moment('swept', status: 'expired')],
        now: _anchor,
      );
      expect(result.kept, isEmpty);
      expect(result.drops['swept'], MomentDropReason.expired);
    });

    test('a LEGACY Moment with a live expiresAt survives — filtering on '
        'canonical status would be invisible data loss', () {
      // VoiceMoment.isCanonicalPublished demands schemaVersion == 2 and
      // status == 'published'; pre-Stage-B documents default to
      // schemaVersion 0 / status 'legacy'. Filtering on that would make
      // every one of them vanish with no error and no empty state.
      //
      // ADAPTED for the expiry contract: the legacy fixture now carries a
      // future `expiresAt`, because a legacy document WITHOUT one is
      // dropped as expired by design (asserted above) — that part of the
      // old "legacy always survives" claim no longer applies.
      final legacy = _moment('old', schemaVersion: 0, status: 'legacy');
      expect(legacy.isCanonicalPublished, isFalse);
      expect(
        MomentDiscoveryService.filterPlayable(
          [legacy],
          now: _anchor,
        ).kept.map((m) => m.id),
        ['old'],
      );
    });
  });

  group('loadDiscoveryFeed against a fake Firestore', () {
    ({MomentDiscoveryService service, FakeFirebaseFirestore db}) build() {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me'),
      );
      return (
        service: MomentDiscoveryService(firestore: db, auth: auth),
        db: db,
      );
    }

    test('unions the popularity and recency pools and de-duplicates', () async {
      final harness = build();
      for (var i = 0; i < 5; i++) {
        await harness.db
            .collection('voiceMoments')
            .doc('m$i')
            .set(_doc('m$i', author: 'a$i', likes: i));
      }

      final feed = await harness.service.loadDiscoveryFeed(seed: 1);
      expect(feed.fetchedCount, 5);
      expect(feed.moments.length, 5);
      expect(feed.moments.map((m) => m.id).toSet().length, 5);
    });

    test('unpublished Moments never enter the feed', () async {
      final harness = build();
      await harness.db.collection('voiceMoments').doc('live').set(_doc('live'));
      await harness.db
          .collection('voiceMoments')
          .doc('draft')
          .set(_doc('draft', published: false));

      final feed = await harness.service.loadDiscoveryFeed(seed: 1);
      expect(feed.moments.map((m) => m.id), ['live']);
    });

    test('expired and expiry-less documents never enter the feed, and are '
        'recorded as expired drops', () async {
      final harness = build();
      await harness.db.collection('voiceMoments').doc('live').set(_doc('live'));
      await harness.db
          .collection('voiceMoments')
          .doc('dead')
          .set(
            _doc(
              'dead',
              author: 'b',
              createdAt: _anchor.subtract(const Duration(hours: 30)),
              expiresAt: _anchor.subtract(const Duration(hours: 6)),
            ),
          );
      await harness.db
          .collection('voiceMoments')
          .doc('clockless')
          .set(_doc('clockless', author: 'c', withoutExpiry: true));

      final feed = await harness.service.loadDiscoveryFeed(seed: 1);
      expect(feed.moments.map((m) => m.id), ['live']);
      expect(feed.drops['dead'], MomentDropReason.expired);
      expect(feed.drops['clockless'], MomentDropReason.expired);
      // All three WERE fetched: the empty-state arithmetic depends on
      // the distinction between "not published" and "published but dead".
      expect(feed.fetchedCount, 3);
    });

    test('an EMPTY corpus and an ALL-UNPLAYABLE corpus are different '
        'states — collapsing them hides an upload failure', () async {
      final empty = build();
      final emptyFeed = await empty.service.loadDiscoveryFeed(seed: 1);
      expect(emptyFeed.corpusIsEmpty, isTrue);
      expect(emptyFeed.everythingFiltered, isFalse);

      final broken = build();
      await broken.db
          .collection('voiceMoments')
          .doc('x')
          .set(_doc('x', audioUrl: null));
      final brokenFeed = await broken.service.loadDiscoveryFeed(seed: 1);
      expect(brokenFeed.isEmpty, isTrue);
      expect(
        brokenFeed.corpusIsEmpty,
        isFalse,
        reason: 'published Moments DO exist; this is not a quiet launch week',
      );
      expect(brokenFeed.everythingFiltered, isTrue);
      expect(brokenFeed.fetchedCount, 1);
    });

    test('a blocked author is excluded before anything renders', () async {
      final harness = build();
      await harness.db
          .collection('voiceMoments')
          .doc('fine')
          .set(_doc('fine', author: 'friend'));
      await harness.db
          .collection('voiceMoments')
          .doc('nope')
          .set(_doc('nope', author: 'villain'));
      await harness.db
          .collection('users')
          .doc('me')
          .collection('blocked')
          .doc('villain')
          .set(<String, dynamic>{'blockedAt': Timestamp.now()});

      final feed = await harness.service.loadDiscoveryFeed(seed: 1);
      expect(feed.moments.map((m) => m.id), ['fine']);
      expect(feed.drops['nope'], MomentDropReason.blockedAuthor);
    });

    test('the same seed produces the same order — the stack does not '
        'reshuffle under the user between rebuilds', () async {
      final harness = build();
      for (var i = 0; i < 8; i++) {
        await harness.db
            .collection('voiceMoments')
            .doc('m$i')
            .set(_doc('m$i', author: 'a$i', likes: i));
      }
      final first = await harness.service.loadDiscoveryFeed(seed: 42);
      final again = await harness.service.loadDiscoveryFeed(seed: 42);
      expect(first.moments.map((m) => m.id), again.moments.map((m) => m.id));
    });
  });

  group('discovery states render', () {
    late PublicIdentityRepository originalIdentity;
    late _CountingFeedService feed;

    setUp(() {
      // Identity badges resolve through the shared singleton; point it at
      // a scripted fetcher so no Firebase app is needed.
      originalIdentity = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        fetchOverride: (uids) async => <String, dynamic>{
          for (final uid in uids)
            uid: {'role': 'user', 'vip': false, 'uid': uid},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      feed = _CountingFeedService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      );
    });

    tearDown(() {
      PublicIdentityRepository.instance = originalIdentity;
    });

    Widget host(Widget child) => MaterialApp(home: child);

    testWidgets('a FAILING load renders a real error state, not an empty '
        'one — the single test that would have caught both prior defects', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _ThrowingDiscovery(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('moments-discovery-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-discovery-empty')),
        findsNothing,
        reason: 'a failed load must never read as "nobody has posted"',
      );
      expect(find.text('Moments could not load'), findsOneWidget);
    });

    testWidgets('an EMPTY corpus renders the empty state, and it is NOT the '
        'loading state', (tester) async {
      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _StaticDiscovery(
              const [],
              delay: const Duration(milliseconds: 30),
            ),
          ),
        ),
      );

      // Before the load resolves: the skeleton.
      await tester.pump();
      expect(
        find.byKey(const ValueKey('moments-discovery-loading')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('moments-discovery-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-discovery-loading')),
        findsNothing,
        reason: 'loading and empty must be visually distinct states',
      );
      expect(find.text('No Voice Moments yet'), findsOneWidget);
      // Nothing invented to fill the space.
      expect(find.textContaining('people listening'), findsNothing);
    });

    testWidgets('an all-unplayable corpus does NOT claim nobody has posted', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _StaticDiscovery(
              const [],
              fetchedCount: 4,
              drops: const {
                'x1': MomentDropReason.unplayable,
                'x2': MomentDropReason.unplayable,
                'x3': MomentDropReason.unplayable,
                'x4': MomentDropReason.unplayable,
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nothing playable right now'), findsOneWidget);
      expect(find.text('No Voice Moments yet'), findsNothing);
      expect(find.textContaining('4 published Moments'), findsOneWidget);
    });

    testWidgets('an all-EXPIRED corpus is the third distinct empty state: '
        'not "nobody posted", not "pipeline broken" — just the 24-hour '
        'life doing its job, with the recorder offered', (tester) async {
      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _StaticDiscovery(
              const [],
              fetchedCount: 2,
              drops: const {
                'x1': MomentDropReason.expired,
                'x2': MomentDropReason.expired,
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nothing live right now'), findsOneWidget);
      expect(find.text('No Voice Moments yet'), findsNothing);
      expect(find.text('Nothing playable right now'), findsNothing);
      expect(find.textContaining('expired'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Record a Moment'),
        findsOneWidget,
      );
    });

    testWidgets('the loading skeleton itself holds a 390 pt phone — the '
        'strip bones clip instead of overflowing 54 px past the edge', (
      tester,
    ) async {
      // Pins the exact defect this file's redesign shipped with: the
      // skeleton drew five fixed 80-pt bones in a Row, which is 400 pt
      // of content inside the 346 pt a padded 390 pt phone leaves.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _StaticDiscovery(
              const [],
              delay: const Duration(milliseconds: 30),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('moments-discovery-loading')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('a populated feed shows the story strip, one row per '
        'Moment with its real counts, and the creation entry — and '
        'fabricates nothing for a zero counter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          MomentsScreen(
            feedService: feed,
            discoveryService: _StaticDiscovery([
              _moment('one', author: 'a', likes: 3, comments: 0),
              _moment('two', author: 'b'),
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The strip: one circle per author chain.
      expect(find.byKey(const ValueKey('moments-chain-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('moments-chain-b')), findsOneWidget);
      // The list: one row per Moment, each with a real play control.
      expect(find.byKey(const ValueKey('moment-row-one')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-row-two')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-row-play-one')),
        findsOneWidget,
      );
      // The real count on the row that owns it…
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-one')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      // …and no fabricated "0" anywhere for the zero counters.
      expect(find.text('0'), findsNothing);
      // The creation entry the recorder tile used to own lives in the
      // header now, and reload is a visible control.
      expect(find.byKey(const ValueKey('moments-create-cta')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moments-discovery-refresh')),
        findsOneWidget,
      );
      // The label under every live Moment is derived from the document's
      // real expiresAt.
      expect(find.textContaining('Expires in'), findsWidgets);
    });

    for (final size in <Size>[
      Size(390, 844), // phone
      Size(834, 1112), // tablet
      Size(1440, 900), // desktop
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          host(
            MomentsScreen(
              feedService: feed,
              discoveryService: _StaticDiscovery([
                _moment('long', author: 'a', likes: 12),
                _moment('two', author: 'b'),
              ]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        // The transport is pinned: the play control is reachable at every
        // width regardless of caption length.
        expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
        // The wide layout is a real desktop composition, not a stretched
        // phone: the detail panel appears at 1100+ and only there.
        if (size.width >= 1100) {
          expect(
            find.byKey(const ValueKey('moments-detail-panel')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const ValueKey('moments-detail-panel')),
            findsNothing,
          );
        }
      });
    }
  });

  group('the Following feed is not lost', () {
    testWidgets('the personal feed is still reachable from the Moments '
        'destination', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            feedService: _CountingFeedService(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: 'me'),
              ),
            ),
            discoveryService: _StaticDiscovery(const []),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // ADAPTED to the stories redesign: Following is a filter chip on
      // the one feed now, not a second tab with its own section
      // headings ("Your Moments" / "From people you follow" no longer
      // exist). The claim that survives is the one that matters: the
      // personal slice is reachable from the destination, and an empty
      // circle renders its own honest state with the recorder offered.
      expect(find.text('Following'), findsOneWidget);
      await tester.tap(find.text('Following'));
      // The personal slice is a composite stream (friends + following +
      // moments); give the fake Firestore listeners a few frames to
      // deliver before asserting the resolved state.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byKey(const ValueKey('moments-following-empty')),
        findsOneWidget,
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Record a Moment'),
        findsOneWidget,
      );
    });
  });

  group('dock contract', () {
    Widget dockHost({required int selectedIndex, ValueChanged<int>? onSelect}) {
      return MaterialApp(
        home: MoreDestinationHost(
          body: const Center(child: Text('BODY')),
          selectedIndex: selectedIndex,
          unreadConversationCount: 0,
          onDestinationSelected: onSelect ?? (_) {},
          onVoicePressed: () {},
          onMorePressed: () {},
        ),
      );
    }

    final momentsSlot = MainShell.desktopSlots.entries
        .firstWhere((entry) => entry.value == MoreDestination.moments)
        .key;

    testWidgets('the dock carries exactly five slots, and Moments is one of '
        'them', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(dockHost(selectedIndex: 0));
      await tester.pumpAndSettle();

      // Four labelled destinations plus the unlabelled voice action.
      for (final label in ['Home', 'Chats', 'Moments', 'More']) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
      expect(
        find.text('Friends'),
        findsNothing,
        reason: 'Friends gave up its dock slot; it did not lose its tab',
      );
    });

    testWidgets('selecting Moments lights the fourth slot; Friends — still '
        'selectable from Home — lights none rather than lying', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(dockHost(selectedIndex: momentsSlot));
      await tester.pumpAndSettle();
      final lit = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      );
      expect(lit, findsOneWidget);
      expect(tester.widget<Semantics>(lit).properties.label, 'Moments');

      // Friends is primary tab 2 and mobile Home's "Your circle" selects
      // it. It owns no dock slot, so the bar must light NOTHING rather
      // than highlight a neighbour and misreport where you are.
      await tester.pumpWidget(dockHost(selectedIndex: 2));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
        findsNothing,
      );
    });

    testWidgets('tapping Moments reports the Moments slot to the shell', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int? selected;
      await tester.pumpWidget(
        dockHost(selectedIndex: 0, onSelect: (index) => selected = index),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      expect(selected, momentsSlot);
    });
  });

  group('the like control is real', () {
    testWidgets('tapping the heart calls toggleLike exactly once', (
      tester,
    ) async {
      // The defect this pins: the Moments screen rendered a heart and a
      // like count as static text with NO tap target, while
      // HomeFeedService.toggleLike worked and Home already used it.
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me'),
      );
      final feed = _CountingFeedService(firestore: db, auth: auth);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MomentCard(
              moment: _moment('m1', likes: 4),
              feedService: feed,
              onComments: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final heart = find.byIcon(Icons.favorite_border_rounded);
      expect(heart, findsOneWidget, reason: 'the heart must be present');
      await tester.tap(heart);
      await tester.pump();

      expect(feed.toggleCalls, ['m1']);
    });

    testWidgets('with no feed service the heart is inert rather than a '
        'button that silently does nothing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MomentCard(moment: _moment('m1'), onComments: () {}),
          ),
        ),
      );
      await tester.pump();

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.byIcon(Icons.favorite_border_rounded),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}

/// Always fails, the way a missing composite index fails in production.
class _ThrowingDiscovery implements MomentDiscoveryService {
  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => Stream<Map<String, MomentEngagement>>.error(
    StateError('pool query failed'),
  );

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    throw StateError('pool query failed');
  }

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      throw StateError('pool query failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(
    this.moments, {
    int? fetchedCount,
    this.delay,
    this.drops = const <String, MomentDropReason>{},
  }) : fetchedCount = fetchedCount ?? moments.length;

  final List<VoiceMoment> moments;
  final int fetchedCount;

  /// Why the fetched-but-not-shown Moments were dropped. The feed's three
  /// empty states are told apart by these reasons, so a test that claims
  /// one must say why.
  final Map<String, MomentDropReason> drops;

  /// Lets a test observe the loading state, which otherwise resolves
  /// inside the same microtask drain as the first pump.
  final Duration? delay;

  /// No counter stream at all — what the board must survive without
  /// losing the counts it loaded. `moments_board_test.dart` owns the
  /// live-counter behaviour itself.
  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    if (delay != null) await Future<void>.delayed(delay!);
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: fetchedCount,
      drops: drops,
      seed: seed ?? 0,
      poolExhausted: false,
    );
  }

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingFeedService extends HomeFeedService {
  _CountingFeedService({super.firestore, super.auth});

  final List<String> toggleCalls = <String>[];

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {
    toggleCalls.add(momentId);
  }
}
