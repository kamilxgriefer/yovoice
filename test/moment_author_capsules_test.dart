import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

import 'moments_overview_test_support.dart';

/// The author capsule strip of board 06: exactly the loaded authors, the
/// unheard/heard fact on the avatar's ring (refine-look §8.4 moved it off
/// the capsule's border), a decorative motif that is never cyan and never
/// animates, full-bleed horizontal scrolling, ≥ 3 visible at 320.
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
        author: tester
            .getTopLeft(find.byKey(ValueKey('moments-capsule-$author')))
            .dx,
    };
    expect(lefts['bartek']!, lessThan(lefts['maja']!));
    expect(lefts['maja']!, lessThan(lefts['kamil']!));
    expect(lefts['kamil']!, lessThan(lefts['ola']!));
    // The old story-tile strip does not come back beside it.
    expect(find.byType(MomentStoryStrip), findsNothing);
    expect(find.byType(MomentStoryTile), findsNothing);
  });

  // Refine-look §8.4 changed where the state is drawn, deliberately: the
  // capsule is a neutral chip-like block (pill, block fill, hairline) and the
  // unheard/heard stops moved onto a 38 px MomentSeenAvatar ring.
  testWidgets('unheard = brand-gradient ring; heard = quiet ring, dimmed '
      'avatar, quieter name, and the state is spoken; the capsule itself is '
      'a neutral pill block', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024), viewed: {'m2', 'm6'});
    final context = tester.element(find.byType(MomentsFeedView));
    final palette = AppPalette.of(context);

    Container ringOf(String author) => tester.widget<Container>(
      find.descendant(
        of: find.byKey(ValueKey('moments-capsule-$author')),
        matching: find.byKey(MomentAuthorCapsule.ringKey),
      ),
    );
    final unheard =
        (ringOf('maja').decoration as BoxDecoration).gradient as LinearGradient;
    expect(unheard.colors, MomentStoryTile.ringColors(context, seen: false));
    final heard =
        (ringOf('kamil').decoration as BoxDecoration).gradient
            as LinearGradient;
    expect(heard.colors, MomentStoryTile.ringColors(context, seen: true));
    expect(heard.colors.first, heard.colors.last);
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const ValueKey('moments-capsule-maja')),
          matching: find.byKey(MomentAuthorCapsule.ringKey),
        ),
      ),
      const Size.square(MomentAuthorCapsule.avatarDiameter),
    );

    for (final author in const ['maja', 'kamil']) {
      final block =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(ValueKey('moments-capsule-$author')),
                      matching: find.byKey(MomentAuthorCapsule.borderKey),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(block.gradient, palette.blockGradient, reason: author);
      expect(block.border, Border.all(color: palette.hairline));
      expect(block.borderRadius, AppRadius.pill);
      expect(block.boxShadow, isEmpty, reason: 'chip-like: never elevated');
    }

    Text nameOf(String author, String name) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('moments-capsule-$author')),
        matching: find.text(name),
      ),
    );
    expect(nameOf('maja', 'Maja').style!.fontWeight, FontWeight.w700);
    expect(nameOf('maja', 'Maja').style!.color, palette.textPrimary);
    expect(nameOf('kamil', 'Kamil').style!.fontWeight, FontWeight.w600);
    expect(nameOf('kamil', 'Kamil').style!.color, palette.textSecondary);

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

  // Refine-look R13 changed the motif's ink deliberately: one `waveUnplayed`
  // (it was primary @ .32).
  testWidgets('the motif is five static waveUnplayed bars: never cyan, never '
      'the played violet, never animated, never read aloud', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024));
    final capsule = find.byKey(const ValueKey('moments-capsule-maja'));
    final bars = find.descendant(
      of: capsule,
      matching: find.byKey(MomentAuthorCapsule.barsKey),
    );
    expect(bars, findsOneWidget);
    final palette = AppPalette.of(tester.element(capsule));
    expect(MomentCapsuleBars.color(palette), isNot(AppColors.accent));
    expect(MomentCapsuleBars.color(palette), isNot(palette.audioAccent));
    expect(MomentCapsuleBars.color(palette), palette.waveUnplayed);
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
      'as its padding, and keeps ≥ 3 capsules visible at 320 without bars', (
    tester,
  ) async {
    await pumpFeed(tester, size: const Size(320, 800));
    final strip = find.byKey(const ValueKey('moments-author-capsules'));
    final stripRect = tester.getRect(strip);
    expect(stripRect.left, 0, reason: 'full-bleed');
    expect(stripRect.width, 320);
    final first = tester.getRect(
      find.byKey(const ValueKey('moments-capsule-bartek')),
    );
    expect(first.left, 16, reason: 'the gutter is the scroll padding');
    expect(find.byKey(MomentAuthorCapsule.barsKey), findsNothing);
    // "Visible" = inside the viewport, wholly or partly: the third capsule
    // peeking in is what tells a thumb the strip scrolls.
    final visible = find.byType(MomentAuthorCapsule).evaluate().where((
      element,
    ) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      return rect.left < 320 && rect.right > 0;
    }).length;
    expect(visible, greaterThanOrEqualTo(3));

    final ola = find.byKey(const ValueKey('moments-capsule-ola'));
    await tester.drag(strip, const Offset(-300, 0));
    await tester.pump();
    expect(tester.getRect(ola).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a capsule opens that author\'s chain without a player', (
    tester,
  ) async {
    await pumpFeed(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('moments-capsule-maja')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Refine-look B5 review (A11Y-B5-04): the capsule's keyboard focus is a
  // 2 px `focus` ring on its own stadium, not the ≈ 1.3:1 tint wash.
  testWidgets('keyboard focus draws a 2 px focus ring on the capsule; '
      'without focus there is none', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024));
    final capsule = find.byKey(const ValueKey('moments-capsule-maja'));
    final ring = find.descendant(
      of: capsule,
      matching: find.byKey(MomentAuthorCapsule.focusRingKey),
    );
    expect(ring, findsNothing);

    final row = find.descendant(of: capsule, matching: find.byType(Row)).first;
    final node = Focus.of(tester.element(row));
    node.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue, reason: '$node');
    expect(ring, findsOneWidget);
    final palette = AppPalette.of(tester.element(capsule));
    final decoration =
        tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
    expect(decoration.border, Border.all(color: palette.focus, width: 2));
    expect(decoration.borderRadius, AppRadius.pill);
    // The ring is the capsule's own outline, painted over it.
    final pill = tester.getRect(
      find.descendant(
        of: capsule,
        matching: find.byKey(MomentAuthorCapsule.borderKey),
      ),
    );
    expect(tester.getRect(ring), pill);

    node.unfocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
