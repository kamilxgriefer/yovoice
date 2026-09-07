// The STRUCTURE of YO Moments -> Voice -> Discover after the density
// rework: a featured GRID whose column count comes from the width it
// actually has, and a recent list of tight rows rather than a card each.
//
// These are the assertions that would have caught the reported defect
// ("huge blocks, very weak"): a 210 pt cover slab in a rail that showed
// one and a half of four cards, and a bordered ~100 pt card per Moment.
// Widths straddle the feed's own breakpoints — 320 / 390 / 768 / 1440 —
// and the 200 % text frame proves the grid degrades to one column instead
// of overflowing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discover_tiles.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

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

/// Engagement descends with the letter, so the featured order is
/// deterministic: a, b, c, d, then the rest.
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

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 0,
    poolExhausted: false,
  );

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

  final Set<String> viewed;

  @override
  Stream<Set<String>> watchViewedMomentIds() =>
      Stream<Set<String>>.value(viewed);

  @override
  Future<void> markViewed(String momentId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('the featured column rule reads available width, not a device', () {
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
    Future<void> pump(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
      Set<String> viewed = const <String>{},
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
                onRecord: () {},
                discoveryService: _StaticDiscovery(_pool),
                viewsService: _StaticViews(viewed),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Featured tile rectangles grouped into visual rows by their top edge.
    List<List<String>> gridRows(WidgetTester tester) {
      final byTop = <double, List<(double, String)>>{};
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
        final finder = find.byKey(ValueKey('moment-featured-$id'));
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder);
        byTop.putIfAbsent(rect.top, () => []).add((rect.left, id));
      }
      final tops = byTop.keys.toList()..sort();
      return [
        for (final top in tops)
          (byTop[top]!..sort((a, b) => a.$1.compareTo(b.$1)))
              .map((entry) => entry.$2)
              .toList(),
      ];
    }

    testWidgets('320: one column, capped at two tiles so the recent list is '
        'not pushed off the first screen', (tester) async {
      await pump(tester, size: const Size(320, 800));
      expect(gridRows(tester), [
        ['a'],
        ['b'],
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('390: a two-by-two grid, not a rail with a card and a half', (
      tester,
    ) async {
      await pump(tester, size: const Size(390, 844));
      expect(gridRows(tester), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      // Every tile of a row shares its top and sits left of the next.
      final a = tester.getRect(find.byKey(const ValueKey('moment-featured-a')));
      final b = tester.getRect(find.byKey(const ValueKey('moment-featured-b')));
      expect(a.top, b.top);
      expect(a.width, closeTo(b.width, 0.5));
      expect(a.right, lessThanOrEqualTo(b.left));
      // Compact by construction: the slab this replaced was 236 x 210.
      expect(a.width, lessThan(200));
      expect(a.height, lessThan(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('768: three columns and one complete row — never an orphan '
        'cell in a second row', (tester) async {
      await pump(tester, size: const Size(768, 1024));
      expect(gridRows(tester), [
        ['a', 'b', 'c'],
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1440: four columns beside the detail panel, and the list '
        'stops at the canonical measure instead of stretching', (tester) async {
      await pump(tester, size: const Size(1440, 900));
      expect(gridRows(tester), [
        ['a', 'b', 'c', 'd'],
      ]);
      expect(
        find.byKey(const ValueKey('moments-detail-panel')),
        findsOneWidget,
      );
      // Desktop is not a stretched phone: the scrolling content is bounded
      // well inside the 1080 pt the feed column receives.
      final list = tester.getRect(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      expect(list.width, lessThanOrEqualTo(1040));
      expect(list.width, greaterThan(600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('200 % text on a phone: one column, and the row facts stack '
        'under the caption rather than overflowing', (tester) async {
      await pump(tester, size: const Size(390, 1400), textScale: 2);
      expect(gridRows(tester), [
        ['a'],
        ['b'],
      ]);
      expect(find.byKey(const ValueKey('moment-row-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-row-play-a')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 at 200 % text still renders without an overflow', (
      tester,
    ) async {
      await pump(tester, size: const Size(320, 1400), textScale: 2);
      expect(find.byKey(const ValueKey('moment-row-a')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a recent entry is a row, not a card', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: MomentsFeedView(
              onRecord: () {},
              discoveryService: _StaticDiscovery(_pool),
              viewsService: _StaticViews(const {'a'}),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    for (final size in const [
      Size(320, 800),
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      testWidgets('at ${size.width.toInt()} a row stays tight and keeps a '
          '44 pt transport target', (tester) async {
        await pump(tester, size);

        final row = tester.getRect(find.byKey(const ValueKey('moment-row-a')));
        expect(
          row.height,
          lessThan(90),
          reason: 'the bordered card per Moment was roughly 100 pt tall',
        );
        final play = tester.getRect(
          find.byKey(const ValueKey('moment-row-play-a')),
        );
        expect(play.width, greaterThanOrEqualTo(44));
        expect(play.height, greaterThanOrEqualTo(44));
        // The transport sits inside the row, not on a slab of its own.
        expect(row.contains(play.center), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
    'heard reads as heard in Discover, in the story tiles\' vocabulary',
    () {
      Future<void> pump(WidgetTester tester, Set<String> viewed) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: MomentsFeedView(
                onRecord: () {},
                discoveryService: _StaticDiscovery(_pool),
                viewsService: _StaticViews(viewed),
              ),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      MomentSeenAvatar avatarIn(WidgetTester tester, Key key) =>
          tester.widget<MomentSeenAvatar>(
            find
                .descendant(
                  of: find.byKey(key),
                  matching: find.byType(MomentSeenAvatar),
                )
                .first,
          );

      testWidgets('a heard Moment dims on BOTH its featured tile and its row; '
          'an unheard one does not', (tester) async {
        await pump(tester, {'a'});

        expect(
          avatarIn(tester, const ValueKey('moment-featured-a')).seen,
          isTrue,
        );
        expect(avatarIn(tester, const ValueKey('moment-row-a')).seen, isTrue);
        expect(
          avatarIn(tester, const ValueKey('moment-featured-b')).seen,
          isFalse,
        );
        expect(avatarIn(tester, const ValueKey('moment-row-b')).seen, isFalse);
      });

      testWidgets('unknown viewed state fails OPEN: nothing is greyed out '
          'before the momentViews listener has said anything', (tester) async {
        await pump(tester, const <String>{});
        for (final id in ['a', 'b']) {
          expect(
            avatarIn(tester, ValueKey('moment-featured-$id')).seen,
            isFalse,
          );
          expect(avatarIn(tester, ValueKey('moment-row-$id')).seen, isFalse);
        }
      });

      testWidgets('the ring stops are the story tile\'s own definition, so the '
          'two surfaces cannot drift apart', (tester) async {
        await pump(tester, {'a'});
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
