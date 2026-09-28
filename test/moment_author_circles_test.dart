import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_circles_strip.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import 'moments_overview_test_support.dart';

/// The G4 author circles of the Głos feed (they replaced the author capsule
/// strip): exactly the loaded authors, "Nagraj" first, the unheard/heard
/// fact on the ring (logo gradient 3 px vs a 1 px hairline), the name's
/// weight and ink, the spoken state, full-bleed horizontal scrolling, high
/// contrast, and the two actions — open the chain, open the recorder.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<void> pumpFeed(
    WidgetTester tester, {
    required Size size,
    Set<String> viewed = const <String>{},
    VoidCallback? onRecord,
    double textScale = 1,
    bool highContrast = false,
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    Widget child = Scaffold(
      body: MomentsFeedView(
        auth: auth,
        onRecord: onRecord ?? () {},
        discoveryService: StaticDiscovery(populatedPool()),
        feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
        viewsService: StaticViews(viewed),
        playerFactory: SilentPlayer.new,
      ),
    );
    if (highContrast) {
      final plain = child;
      child = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: true),
          child: plain,
        ),
      );
    }
    await tester.pumpWidget(
      overviewHost(child, size: size, textScale: textScale),
    );
    await settleOverview(tester);
  }

  Finder circle(String author) =>
      find.byKey(ValueKey('moments-circle-$author'));

  BoxDecoration ringOf(WidgetTester tester, String author) =>
      tester
              .widget<Container>(
                find.descendant(
                  of: circle(author),
                  matching: find.byKey(MomentCircle.ringKey),
                ),
              )
              .decoration!
          as BoxDecoration;

  // The last Text of an item is its name (the avatar's initial comes first).
  Text nameOf(WidgetTester tester, String author) => tester.widget<Text>(
    find.descendant(of: circle(author), matching: find.byType(Text)).last,
  );

  testWidgets('the circles are exactly the authors of the loaded list, newest '
      'author first, one per author, with "Nagraj" leading', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024));
    final strip = find.byKey(const ValueKey('moments-author-circles'));
    expect(strip, findsOneWidget);
    // ~110 px including the names at 100 %.
    expect(tester.getSize(strip).height, inInclusiveRange(104, 112));
    for (final author in const ['maja', 'kamil', 'ola', 'bartek']) {
      expect(circle(author), findsOneWidget);
    }
    expect(find.byType(MomentCircle), findsNWidgets(4));
    final record = find.byKey(const ValueKey('moments-circle-record'));
    expect(record, findsOneWidget);
    // Nagraj · Bartek (40 min) · Maja (1 h) · Kamil (5 h) · Ola.
    final lefts = <String, double>{
      for (final author in const ['bartek', 'maja', 'kamil', 'ola'])
        author: tester.getTopLeft(circle(author)).dx,
    };
    expect(tester.getTopLeft(record).dx, lessThan(lefts['bartek']!));
    expect(lefts['bartek']!, lessThan(lefts['maja']!));
    expect(lefts['maja']!, lessThan(lefts['kamil']!));
    expect(lefts['kamil']!, lessThan(lefts['ola']!));
    // Each item is 68 wide with a 64 px circle.
    expect(tester.getSize(circle('maja')).width, 68);
    expect(
      tester.getSize(
        find.descendant(
          of: circle('maja'),
          matching: find.byKey(MomentCircle.ringKey),
        ),
      ),
      const Size.square(64),
    );
    // Neither the capsules nor the old story-tile strip come back beside it.
    expect(find.byType(MomentStoryStrip), findsNothing);
    expect(find.byType(MomentStoryTile), findsNothing);
  });

  testWidgets('unheard = the 3 px logo gradient; heard = a 1 px border '
      'line and a dimmed face (the one seen-avatar, ADR-155); the name '
      'carries the state too, and it is spoken', (tester) async {
    await pumpFeed(tester, size: const Size(768, 1024), viewed: {'m2', 'm6'});
    final context = tester.element(find.byType(MomentsFeedView));
    final palette = AppPalette.of(context);

    // The circle IS the shared primitive, not a look-alike.
    expect(
      find.descendant(
        of: circle('maja'),
        matching: find.byType(MomentSeenAvatar),
      ),
      findsOneWidget,
    );
    Container ringBox(String author) => tester.widget<Container>(
      find.descendant(
        of: circle(author),
        matching: find.byKey(MomentCircle.ringKey),
      ),
    );
    UserAvatar faceOf(String author) => tester.widget<UserAvatar>(
      find.descendant(of: circle(author), matching: find.byType(UserAvatar)),
    );
    Opacity dimOf(String author) => tester.widget<Opacity>(
      find.descendant(of: circle(author), matching: find.byType(Opacity)),
    );

    final unheard = ringOf(tester, 'maja');
    final gradient = unheard.gradient! as LinearGradient;
    expect(gradient.colors, AppGradients.primary.colors);
    expect(gradient.colors, MomentStoryTile.ringColors(context, seen: false));
    expect(ringBox('maja').padding, const EdgeInsets.all(3), reason: '3 px');
    expect(dimOf('maja').opacity, 1);

    final heard = ringOf(tester, 'kamil');
    final quiet = heard.gradient! as LinearGradient;
    expect(quiet.colors, MomentStoryTile.ringColors(context, seen: true));
    expect(quiet.colors, <Color>[palette.border, palette.border]);
    expect(ringBox('kamil').padding, const EdgeInsets.all(1), reason: '1 px');
    expect(dimOf('kamil').opacity, lessThan(1), reason: 'the dimmed face');
    // The face keeps one diameter in both states: nothing moves on a flip.
    expect(MomentCircle.avatarDiameter, 54);
    expect(faceOf('maja').radius, 27);
    expect(faceOf('kamil').radius, 27);
    expect(
      tester.getSize(find.byKey(MomentCircle.ringKey).first),
      const Size.square(64),
    );

    expect(nameOf(tester, 'maja').style!.color, palette.textPrimary);
    expect(nameOf(tester, 'maja').style!.fontWeight, FontWeight.w700);
    expect(nameOf(tester, 'kamil').style!.color, palette.textTertiary);
    expect(nameOf(tester, 'kamil').style!.fontWeight, FontWeight.w600);
    expect(nameOf(tester, 'maja').style!.fontSize, 12);

    // No ring is ever cyan: cyan means audio PROGRESS.
    expect(gradient.colors, isNot(contains(AppColors.accent)));
    expect(gradient.colors, isNot(contains(palette.audioAccent)));

    final semantics = tester.ensureSemantics();
    try {
      final kamil = tester.getSemantics(circle('kamil')).getSemanticsData();
      expect(kamil.label, contains('Kamil'));
      expect(kamil.label, contains('already heard'));
      expect(kamil.label, contains('2 Moments'));
      expect(kamil.flagsCollection.isButton, isTrue);
      expect(kamil.hasAction(SemanticsAction.tap), isTrue);
      final maja = tester.getSemantics(circle('maja')).getSemanticsData();
      expect(maja.label, contains('not heard yet'));
      final record = tester
          .getSemantics(find.byKey(const ValueKey('moments-circle-record')))
          .getSemanticsData();
      expect(record.label, 'Record a Voice Moment');
      expect(record.flagsCollection.isButton, isTrue);
      expect(record.hasAction(SemanticsAction.tap), isTrue);
      // The strip is a named group.
      expect(find.bySemanticsLabel("Authors' Moments"), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('high contrast: a solid primary band and a borderStrong line, '
      'no gradient anywhere in the strip', (tester) async {
    await pumpFeed(
      tester,
      size: const Size(390, 844),
      viewed: {'m2', 'm6'},
      highContrast: true,
    );
    final context = tester.element(find.byType(MomentsFeedView));
    final palette = AppPalette.of(context);
    final unheard = ringOf(tester, 'maja');
    expect(unheard.gradient, isNull);
    expect(unheard.color, Theme.of(context).colorScheme.primary);
    final heard = ringOf(tester, 'kamil');
    expect(heard.gradient, isNull);
    expect(heard.color, palette.borderStrong);
    final badge =
        tester
                .widget<Container>(find.byKey(MomentRecordCircle.badgeKey))
                .decoration!
            as BoxDecoration;
    expect(badge.gradient, isNull);
  });

  testWidgets('the viewer\'s own chain stays reachable as "You", never '
      'unheard, and says so', (tester) async {
    useSurface(tester, const Size(768, 1024));
    final auth = authAs();
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            discoveryService: StaticDiscovery(<VoiceMoment>[
              overviewMoment(
                'own',
                author: viewerUid,
                authorName: 'Me',
                caption: 'Mine.',
                age: const Duration(minutes: 5),
              ),
              ...populatedPool(),
            ]),
            feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
            // Never played back: ADR-155's own tile would stay ringed.
            viewsService: StaticViews(const <String>{}),
            playerFactory: SilentPlayer.new,
          ),
        ),
        size: const Size(768, 1024),
      ),
    );
    await settleOverview(tester);
    final context = tester.element(find.byType(MomentsFeedView));
    final own = circle(viewerUid);
    expect(own, findsOneWidget);
    expect(nameOf(tester, viewerUid).data, 'You');
    expect(
      (ringOf(tester, viewerUid).gradient! as LinearGradient).colors,
      MomentStoryTile.ringColors(context, seen: true),
      reason: 'never the unheard ring',
    );
    final semantics = tester.ensureSemantics();
    try {
      final label = tester.getSemantics(own).getSemanticsData().label;
      expect(label, 'Open your story chain');
      expect(label, isNot(contains('not heard yet')));
      // The own row's avatar says the same, and the row has no "new".
      final chain = tester
          .getSemantics(find.byKey(const ValueKey('moment-row-chain-own')))
          .getSemanticsData();
      expect(chain.label, 'Open your story chain');
      expect(
        find.byKey(const ValueKey('moment-row-unheard-own')),
        findsNothing,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('"Nagraj" is the viewer\'s face with the gradient "+" and opens '
      'the existing recorder entry', (tester) async {
    var recorded = 0;
    await pumpFeed(
      tester,
      size: const Size(390, 844),
      onRecord: () => recorded += 1,
    );
    final record = find.byKey(const ValueKey('moments-circle-record'));
    final badge = find.byKey(MomentRecordCircle.badgeKey);
    expect(tester.getSize(badge), const Size.square(22));
    final fill = tester.widget<Container>(badge).decoration! as BoxDecoration;
    expect(fill.gradient, AppGradients.primary);
    expect(
      find.descendant(of: record, matching: find.text('Record')),
      findsOneWidget,
    );
    await tester.tap(record);
    await tester.pump();
    expect(recorded, 1);
  });

  testWidgets('the strip scrolls horizontally, is full-bleed with the first '
      'circle on the gutter, and shows four items at 320', (tester) async {
    await pumpFeed(tester, size: const Size(320, 800));
    final strip = find.byKey(const ValueKey('moments-author-circles'));
    final stripRect = tester.getRect(strip);
    expect(stripRect.left, 0, reason: 'full-bleed');
    expect(stripRect.width, 320);
    final firstRing = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('moments-circle-record')),
            matching: find.byType(Stack),
          )
          .first,
    );
    expect(firstRing.left, closeTo(16 - 2, 0.5));
    final visible = find
        .byWidgetPredicate((w) => w is MomentCircle || w is MomentRecordCircle)
        .evaluate()
        .where((element) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          return rect.left < 320 && rect.right > 0;
        })
        .length;
    expect(visible, greaterThanOrEqualTo(4));

    final ola = circle('ola');
    await tester.drag(strip, const Offset(-300, 0));
    await tester.pump();
    expect(tester.getRect(ola).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 200 % text the names stay one line inside wider items and '
      'nothing overflows at 320', (tester) async {
    await pumpFeed(tester, size: const Size(320, 800), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(circle('maja')).width, 92);
    expect(nameOf(tester, 'bartek').maxLines, 1);
    expect(nameOf(tester, 'bartek').overflow, TextOverflow.ellipsis);
    final strip = find.byKey(const ValueKey('moments-author-circles'));
    final item = tester.getRect(circle('maja'));
    expect(item.bottom, lessThanOrEqualTo(tester.getRect(strip).bottom));
  });

  testWidgets('keyboard focus draws a 2 px rounded RECTANGLE around the '
      'circle and its name, clear of the ring, on a heard circle too', (
    tester,
  ) async {
    await pumpFeed(tester, size: const Size(390, 844), viewed: {'m2', 'm6'});
    final palette = AppPalette.of(tester.element(find.byType(MomentsFeedView)));
    for (final author in const ['maja', 'kamil']) {
      final ring = find.descendant(
        of: circle(author),
        matching: find.byKey(MomentCircle.focusRingKey),
      );
      BoxDecoration focusOf() =>
          tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
      expect((focusOf().border! as Border).top.color, Colors.transparent);

      // The InkWell wraps its child in its own Focus: ask that node.
      Focus.of(
        tester.element(
          find.descendant(of: circle(author), matching: find.byType(Column)),
        ),
      ).requestFocus();
      // One frame lands the focus change, the next draws its rebuild.
      await tester.pump();
      await tester.pump();

      final decoration = focusOf();
      final side = (decoration.border! as Border).top;
      expect(side.color, palette.focus, reason: author);
      expect(side.width, 2);
      // A rounded rectangle, not a circle: no shape a ring state uses.
      expect(decoration.shape, BoxShape.rectangle);
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(MomentCircle.focusRadius)),
      );
      final item = tester.getRect(circle(author));
      final focusRect = tester.getRect(ring);
      expect(focusRect, item.inflate(MomentCircle.focusOutset));
      // It holds the circle AND the name, and its inner edge stays 2 px
      // clear of the ring on either side.
      final band = tester.getRect(
        find.descendant(
          of: circle(author),
          matching: find.byKey(MomentCircle.ringKey),
        ),
      );
      final name = tester.getRect(
        find.descendant(of: circle(author), matching: find.byType(Text)).last,
      );
      expect(focusRect.contains(band.topLeft), isTrue);
      expect(focusRect.contains(name.bottomRight - const Offset(1, 1)), isTrue);
      expect(
        band.left - (focusRect.left + side.width),
        greaterThanOrEqualTo(2),
      );
      expect(
        (focusRect.right - side.width) - band.right,
        greaterThanOrEqualTo(2),
      );
      // The item keeps its 68 px footprint: nothing around it moves.
      expect(tester.getSize(circle(author)).width, 68);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a circle opens that author\'s chain without a player', (
    tester,
  ) async {
    await pumpFeed(tester, size: const Size(390, 844));
    await tester.tap(circle('maja'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
