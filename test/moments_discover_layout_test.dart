// Approved YO Moments -> Voice -> Discover: one readable card per
// recording, no featured duplicate or auto-selected desktop detail panel.
// Widths straddle 320 / 390 / 768 / 1440; 200 % text must preserve the
// real caption, duration, inline transport and author-chain entry.
// The old tile helper's pure contract remains independently covered.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discover_tiles.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

final DateTime _anchor = DateTime.now();

VoiceMoment _moment(
  String id, {
  required String author,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),
}) {
  final createdAt = _anchor.subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: 'Author $author',
    authorPhotoUrl: null,
    caption: 'A caption for $id that is long enough to need truncating.',
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 63,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
  );
}

/// Same timestamps retain a deterministic recent-order tie-break by ID.
/// Real engagement remains distinct from that ordering.
final _pool = <VoiceMoment>[
  _moment('a', author: 'p1', likes: 90, comments: 30),
  _moment('b', author: 'p2', likes: 70, comments: 20),
  _moment('c', author: 'p3', likes: 50, comments: 10),
  _moment('d', author: 'p4', likes: 30, comments: 5),
  _moment('e', author: 'p5', likes: 10, comments: 1),
  _moment('f', author: 'p6'),
];

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;
  int loadCalls = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
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
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticViews implements MomentViewsService {
  _StaticViews(this.viewed);

  // Null deliberately means the listener has NOT emitted, not an empty
  // but resolved viewed set. Both states must avoid false "heard" rings.
  final Set<String>? viewed;
  int watchCalls = 0;
  final List<String> markedIds = <String>[];

  @override
  Stream<Set<String>> watchViewedMomentIds() {
    watchCalls += 1;
    return viewed == null
        ? const Stream<Set<String>>.empty()
        : Stream<Set<String>>.value(viewed!);
  }

  @override
  Future<void> markViewed(String momentId) async {
    markedIds.add(momentId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpFeed(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  Set<String>? viewed = const <String>{},
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'layout-viewer'),
  );
  final discovery = _StaticDiscovery(_pool);
  final views = _StaticViews(viewed);
  var playerCreations = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            discoveryService: discovery,
            viewsService: views,
            playerFactory: () {
              playerCreations += 1;
              throw StateError(
                'Rendering a recording must not start a player.',
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(discovery.loadCalls, 1, reason: 'The fixture must reach discovery.');
  expect(views.watchCalls, 1, reason: 'Viewed state must actually subscribe.');
  expect(views.markedIds, isEmpty, reason: 'Arriving is not listening.');
  expect(playerCreations, 0, reason: 'There is no autoplay on arrival.');
  expect(find.byKey(const ValueKey('moments-discovery-error')), findsNothing);
}

Finder _feedScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('moments-feed-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

double _listWidth(Size size) =>
    size.width < ResponsiveContentWidth.list.maxWidth
    ? size.width
    : ResponsiveContentWidth.list.maxWidth;

double _gutter(Size size) => size.width < 600
    ? 16
    : size.width < 1100
    ? 24
    : 32;

void _expectSingleColumn(WidgetTester tester, Size size) {
  final list = tester.getRect(
    find.byKey(const ValueKey('moments-feed-scroll')),
  );
  expect(list.width, _listWidth(size));
  expect(list.left, (size.width - _listWidth(size)) / 2);
  final a = tester.getRect(find.byKey(const ValueKey('moment-row-a')));
  final b = tester.getRect(find.byKey(const ValueKey('moment-row-b')));
  expect(a.left, list.left + _gutter(size));
  expect(a.width, list.width - 2 * _gutter(size));
  expect(b.left, a.left);
  expect(b.width, a.width);
  expect(a.bottom, lessThanOrEqualTo(b.top));
  expect(find.byKey(const ValueKey('moments-detail-panel')), findsNothing);
  for (final moment in _pool) {
    expect(find.byKey(ValueKey('moment-featured-${moment.id}')), findsNothing);
    expect(
      find.byKey(ValueKey('moments-chain-${moment.authorId}')),
      findsNothing,
    );
  }
}

Future<void> _expectReadableCard(
  WidgetTester tester,
  Size size, {
  String id = 'a',
}) async {
  final card = find.byKey(ValueKey('moment-row-$id'));
  await tester.scrollUntilVisible(card, 240, scrollable: _feedScrollable());
  expect(card, findsOneWidget);
  final moment = _pool.singleWhere((item) => item.id == id);
  expect(
    find.descendant(of: card, matching: find.text(moment.caption)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: card, matching: find.text('1:03')),
    findsOneWidget,
  );
  final progress = tester.widget<Slider>(
    find.byKey(ValueKey('moment-row-progress-$id')),
  );
  expect(progress.max, 63000);
  expect(progress.value, 0);
  expect(
    progress.onChanged,
    isNull,
    reason: 'No implicit playback or seeking.',
  );
  for (final control in ['chain', 'menu', 'play']) {
    final finder = find.byKey(ValueKey('moment-row-$control-$id'));
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder.hitTestable(), findsOneWidget);
    final target = tester.getRect(finder);
    final rect = tester.getRect(card);
    expect(target.width, greaterThanOrEqualTo(44));
    expect(target.height, greaterThanOrEqualTo(44));
    expect(rect.contains(target.topLeft), isTrue);
    expect(rect.contains(target.bottomRight), isTrue);
    expect(rect.width, _listWidth(size) - 2 * _gutter(size));
    expect(rect.left, (size.width - _listWidth(size)) / 2 + _gutter(size));
  }
  final play = tester.widget<IconButton>(
    find.byKey(ValueKey('moment-row-play-$id')),
  );
  expect(play.onPressed, isNotNull);
  expect(play.tooltip, 'Play');
  expect(tester.takeException(), isNull);
}

void main() {
  group('the retained tile helper reads available width, not a device', () {
    test('four phone/tablet/desktop measures resolve to 1, 2, 3 and 4', () {
      // The width the grid receives: the viewport minus the feed's own
      // gutter (16 compact / 24 otherwise), and on 1100+ minus the detail
      // panel and past the canonical content measure.
      expect(momentFeaturedColumns(320 - 32), 1);
      expect(momentFeaturedColumns(390 - 32), 2);
      expect(momentFeaturedColumns(768 - 48), 3);
      expect(momentFeaturedColumns(1040 - 48), 4);
    });

    test('a 200 % text preference costs a column, never an overflow', () {
      expect(momentFeaturedColumns(390 - 32, textScale: 2), 1);
      expect(momentFeaturedColumns(768 - 48, textScale: 2), 2);
      expect(momentFeaturedColumns(1040 - 48, textScale: 2), 2);
      // A modest preference does not reshuffle the grid.
      expect(momentFeaturedColumns(390 - 32, textScale: 1.3), 2);
    });
  });

  group('the Discover structure at every width', () {
    testWidgets('320: one column keeps all six recordings reachable once', (
      tester,
    ) async {
      const size = Size(320, 800);
      await _pumpFeed(tester, size: size);
      _expectSingleColumn(tester, size);
      for (final moment in _pool) {
        await _expectReadableCard(tester, size, id: moment.id);
      }
    });

    testWidgets(
      '390: full-width recording cards have equal width and never overlap',
      (tester) async {
        const size = Size(390, 844);
        await _pumpFeed(tester, size: size);
        _expectSingleColumn(tester, size);
        await _expectReadableCard(tester, size);
      },
    );

    testWidgets('768: tablet cards use one column with 24 pt page gutters', (
      tester,
    ) async {
      const size = Size(768, 1024);
      await _pumpFeed(tester, size: size);
      _expectSingleColumn(tester, size);
      await _expectReadableCard(tester, size);
    });

    testWidgets(
      '1440: the centered list stops at 880 pt without an automatic detail panel',
      (tester) async {
        const size = Size(1440, 900);
        await _pumpFeed(tester, size: size);
        _expectSingleColumn(tester, size);
        await _expectReadableCard(tester, size);
      },
    );

    testWidgets(
      '390 at 200 % text preserves caption, duration and reachable controls',
      (tester) async {
        const size = Size(390, 1400);
        await _pumpFeed(tester, size: size, textScale: 2);
        _expectSingleColumn(tester, size);
        await _expectReadableCard(tester, size);
      },
    );

    testWidgets(
      '320 at 200 % text keeps a complete single-card transport in bounds',
      (tester) async {
        const size = Size(320, 1400);
        await _pumpFeed(tester, size: size, textScale: 2);
        _expectSingleColumn(tester, size);
        await _expectReadableCard(tester, size);
      },
    );
  });

  group('each recording has real transport within the readable measure', () {
    for (final size in const [
      Size(320, 800),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets(
        'at ${size.width.toInt()} a card keeps exact duration, progress and 44 pt controls',
        (tester) async {
          await _pumpFeed(tester, size: size, viewed: const {'a'});
          await _expectReadableCard(tester, size);
        },
      );
    }
  });

  group(
    'heard reads as heard in Discover, in the story tiles\' vocabulary',
    () {
      MomentSeenAvatar avatarIn(WidgetTester tester, Key key) =>
          tester.widget<MomentSeenAvatar>(
            find
                .descendant(
                  of: find.byKey(key),
                  matching: find.byType(MomentSeenAvatar),
                )
                .first,
          );

      testWidgets('a heard Moment dims on its single-card chain entry; '
          'an unheard one does not', (tester) async {
        await _pumpFeed(tester, size: const Size(390, 844), viewed: {'a'});

        expect(
          avatarIn(tester, const ValueKey('moment-row-chain-a')).seen,
          isTrue,
        );
        expect(avatarIn(tester, const ValueKey('moment-row-a')).seen, isTrue);
        expect(
          avatarIn(tester, const ValueKey('moment-row-chain-b')).seen,
          isFalse,
        );
        expect(avatarIn(tester, const ValueKey('moment-row-b')).seen, isFalse);
      });

      testWidgets('unknown viewed state stays unheard: nothing is greyed out '
          'before the momentViews listener has said anything', (tester) async {
        await _pumpFeed(tester, size: const Size(390, 844), viewed: null);
        for (final id in ['a', 'b']) {
          expect(
            avatarIn(tester, ValueKey('moment-row-chain-$id')).seen,
            isFalse,
          );
          expect(avatarIn(tester, ValueKey('moment-row-$id')).seen, isFalse);
        }
      });

      testWidgets('the ring stops are the story tile\'s own definition, so the '
          'two surfaces cannot drift apart', (tester) async {
        await _pumpFeed(tester, size: const Size(390, 844), viewed: {'a'});
        final context = tester.element(find.byType(MomentsFeedView));
        expect(
          MomentStoryTile.ringColors(context, seen: true),
          hasLength(2),
          reason: 'the seen ring is a flat two-stop quiet line',
        );
        expect(
          MomentStoryTile.ringColors(context, seen: true).first,
          MomentStoryTile.ringColors(context, seen: true).last,
        );
        expect(
          MomentStoryTile.ringColors(context, seen: false).first,
          isNot(MomentStoryTile.ringColors(context, seen: false).last),
          reason: 'the unheard ring is the brand gradient',
        );
      });
    },
  );
}
