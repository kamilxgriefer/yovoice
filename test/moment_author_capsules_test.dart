import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

import 'moments_overview_test_support.dart';

/// The author capsule strip of board 06: exactly the loaded authors, the
/// unheard/heard fact on the border, a decorative motif that is never cyan
/// and never animates, full-bleed horizontal scrolling, ≥ 3 visible at 320.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<void> pumpFeed(
    WidgetTester tester, {
    required Size size,
    Set<String> viewed = const <String>{},
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            discoveryService: StaticDiscovery(populatedPool()),
            feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
            viewsService: StaticViews(viewed),
            playerFactory: SilentPlayer.new,
          ),
        ),
        size: size,
      ),
    );
    await settleOverview(tester);
  }

  testWidgets('capsules are exactly the authors of the loaded list, newest '
      'author first, one per author', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024));
    final strip = find.byKey(const ValueKey('moments-author-capsules'));
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).height, MomentAuthorCapsule.height);
    for (final author in const ['maja', 'kamil', 'ola', 'bartek']) {
      expect(find.byKey(ValueKey('moments-capsule-$author')), findsOneWidget);
    }
    expect(find.byType(MomentAuthorCapsule), findsNWidgets(4));
    // Newest Moment first: Bartek (40 min) · Maja (1 h) · Kamil (5 h) · Ola.
    final lefts = <String, double>{
      for (final author in const ['bartek', 'maja', 'kamil', 'ola'])
        author: tester.getTopLeft(find.byKey(ValueKey('moments-capsule-$author'))).dx,
    };
    expect(lefts['bartek']!, lessThan(lefts['maja']!));
    expect(lefts['maja']!, lessThan(lefts['kamil']!));
    expect(lefts['kamil']!, lessThan(lefts['ola']!));
    // The old story-tile strip does not come back beside it.
    expect(find.byType(MomentStoryStrip), findsNothing);
    expect(find.byType(MomentStoryTile), findsNothing);
  });

  testWidgets('unheard = 2 px brand gradient border; heard = 1 px quiet '
      'hairline, dimmed avatar, and the state is spoken', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024), viewed: {'m2', 'm6'});
    final context = tester.element(find.byType(MomentsFeedView));

    DecoratedBox borderOf(String author) => tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(ValueKey('moments-capsule-$author')),
        matching: find.byKey(MomentAuthorCapsule.borderKey),
      ),
    );
    final unheard = (borderOf('maja').decoration as BoxDecoration).gradient
        as LinearGradient;
    expect(unheard.colors, MomentStoryTile.ringColors(context, seen: false));
    final heard = (borderOf('kamil').decoration as BoxDecoration).gradient
        as LinearGradient;
    expect(heard.colors, MomentStoryTile.ringColors(context, seen: true));
    expect(heard.colors.first, heard.colors.last);

    Opacity avatarOpacity(String author) => tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(ValueKey('moments-capsule-$author')),
        matching: find.byType(Opacity),
      ),
    );
    expect(avatarOpacity('kamil').opacity, lessThan(1));
    expect(avatarOpacity('maja').opacity, 1);

    final semantics = tester.ensureSemantics();
    try {
      final kamil = tester
          .getSemantics(find.byKey(const ValueKey('moments-capsule-kamil')))
          .getSemanticsData();
      expect(kamil.label, contains('Kamil'));
      expect(kamil.label, contains('already heard'));
      expect(kamil.label, contains('2 Moments'));
      expect(kamil.flagsCollection.isButton, isTrue);
      final maja = tester
          .getSemantics(find.byKey(const ValueKey('moments-capsule-maja')))
          .getSemanticsData();
      expect(maja.label, contains('not heard yet'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the motif is five static primary-wash bars: never cyan, never '
      'animated, never read aloud', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024));
    final capsule = find.byKey(const ValueKey('moments-capsule-maja'));
    final bars = find.descendant(
      of: capsule,
      matching: find.byKey(MomentAuthorCapsule.barsKey),
    );
    expect(bars, findsOneWidget);
    final palette = AppPalette.of(tester.element(capsule));
    expect(MomentCapsuleBars.color(), isNot(AppColors.accent));
    expect(MomentCapsuleBars.color(), isNot(palette.audioAccent));
    expect(MomentCapsuleBars.color(), AppColors.primary.withValues(alpha: .32));
    expect(MomentCapsuleBars.amplitudes, hasLength(5));
    expect(
      find.descendant(of: bars, matching: find.byType(AnimatedContainer)),
      findsNothing,
    );
    expect(
      find.descendant(of: bars, matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );
    final paintedBefore = tester
        .widgetList<Container>(
          find.descendant(of: bars, matching: find.byType(Container)),
        )
        .map((c) => (c.decoration as BoxDecoration).color)
        .toList();
    await tester.pump(const Duration(seconds: 2));
    final paintedAfter = tester
        .widgetList<Container>(
          find.descendant(of: bars, matching: find.byType(Container)),
        )
        .map((c) => (c.decoration as BoxDecoration).color)
        .toList();
    expect(paintedAfter, paintedBefore);
    expect(tester.getSize(bars), const Size(24, 16));
  });

  testWidgets('the strip scrolls horizontally, is full-bleed with the gutter '
      'as its padding, and keeps ≥ 3 capsules visible at 320 without bars',
      (tester) async {
    await pumpFeed(tester, size: const Size(320, 800));
    final strip = find.byKey(const ValueKey('moments-author-capsules'));
    final stripRect = tester.getRect(strip);
    expect(stripRect.left, 0, reason: 'full-bleed');
    expect(stripRect.width, 320);
    final first = tester.getRect(find.byKey(const ValueKey('moments-capsule-bartek')));
    expect(first.left, 16, reason: 'the gutter is the scroll padding');
    expect(find.byKey(MomentAuthorCapsule.barsKey), findsNothing);
    // "Visible" = inside the viewport, wholly or partly: the third capsule
    // peeking in is what tells a thumb the strip scrolls.
    final visible = find
        .byType(MomentAuthorCapsule)
        .evaluate()
        .where((element) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          return rect.left < 320 && rect.right > 0;
        })
        .length;
    expect(visible, greaterThanOrEqualTo(3));

    final ola = find.byKey(const ValueKey('moments-capsule-ola'));
    await tester.drag(strip, const Offset(-300, 0));
    await tester.pump();
    expect(tester.getRect(ola).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a capsule opens that author\'s chain without a player',
      (tester) async {
    await pumpFeed(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('moments-capsule-maja')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
