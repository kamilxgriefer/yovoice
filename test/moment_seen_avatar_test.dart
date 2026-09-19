// The one painted Moments ring (ADR-209, story-tile row).
//
// `MomentStoryTile.ringColors` was always THE definition of the seen/unseen
// stops, but the unheard stop was hardcoded as `AppGradients.primary` in the
// tile's own disc and in the discover `MomentSeenAvatar`, so three places
// could drift. Now every shape — the shared disc, the tile through it and
// the capsule border — paints `MomentStoryTile.ringGradient`, and this file
// pins that: the gradient's angle and stops in both themes, the key
// contract the tile test relies on, and the geometry the tile hands down.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discover_tiles.dart'
    as discover;
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);

LinearGradient _gradientUnder(WidgetTester tester, Key key) {
  final ring = tester.widget<Container>(find.byKey(key));
  return (ring.decoration! as BoxDecoration).gradient! as LinearGradient;
}

void main() {
  for (final (label, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    testWidgets(
      'ringGradient is ringColors at the brand gradient\'s angle, in both '
      'states ($label)',
      (tester) async {
        await tester.pumpWidget(_host(const SizedBox(), theme: theme));
        final context = tester.element(find.byType(Scaffold));

        for (final seen in [false, true]) {
          final gradient = MomentStoryTile.ringGradient(context, seen: seen);
          expect(gradient.colors, MomentStoryTile.ringColors(context, seen: seen));
          expect(
            gradient.begin,
            AppGradients.primary.begin,
            reason: 'the same angle in both states: only the stops change',
          );
          expect(gradient.end, AppGradients.primary.end);
        }
        expect(
          MomentStoryTile.ringGradient(context, seen: false).colors,
          AppGradients.primary.colors,
          reason: 'unheard IS the brand gradient, defined once',
        );
      },
    );
  }

  testWidgets(
    'MomentSeenAvatar paints ringGradient on the container that carries '
    'ringKey, with the feed\'s 2 / 1.5 band by default',
    (tester) async {
      const ringKey = ValueKey('ring-under-test');
      await tester.pumpWidget(
        _host(
          const MomentSeenAvatar(
            seen: false,
            diameter: 48,
            ringKey: ringKey,
            displayName: 'Ola',
          ),
        ),
      );
      final context = tester.element(find.byType(MomentSeenAvatar));

      expect(
        _gradientUnder(tester, ringKey),
        MomentStoryTile.ringGradient(context, seen: false),
      );
      expect(
        tester.getSize(find.byKey(ringKey)),
        const Size(48, 48),
        reason: 'the keyed container is the whole disc',
      );
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).radius,
        (48 - (2 + 1.5) * 2) / 2,
        reason: 'defaultRingWidth 2 + defaultRingInset 1.5 on each side',
      );
      expect(MomentSeenAvatar.defaultRingWidth, 2);
      expect(MomentSeenAvatar.defaultRingInset, 1.5);
      expect(
        tester.widget<Opacity>(find.byType(Opacity).first).opacity,
        1,
      );
    },
  );

  testWidgets('a heard MomentSeenAvatar is the quiet ring and a dimmed avatar', (
    tester,
  ) async {
    const ringKey = ValueKey('ring-under-test');
    await tester.pumpWidget(
      _host(
        const MomentSeenAvatar(
          seen: true,
          diameter: 56,
          ringKey: ringKey,
          displayName: 'Ola',
        ),
      ),
    );
    final context = tester.element(find.byType(MomentSeenAvatar));
    final gradient = _gradientUnder(tester, ringKey);
    expect(gradient, MomentStoryTile.ringGradient(context, seen: true));
    expect(gradient.colors.first, gradient.colors.last);
    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      lessThan(1),
    );
  });

  testWidgets(
    'the discover library still resolves MomentSeenAvatar, as the same class',
    (tester) async {
      expect(
        identical(discover.MomentSeenAvatar, MomentSeenAvatar),
        isTrue,
        reason: 're-exported, not redeclared: one disc, one import path kept',
      );
    },
  );

  testWidgets(
    'MomentStoryTile\'s disc is the shared MomentSeenAvatar with its 2.5 / 2 '
    'band, and MomentStoryTile.ringKey still finds a gradient Container',
    (tester) async {
      await tester.pumpWidget(
        _host(
          MomentStoryTile(
            name: 'Ola',
            seen: false,
            semanticLabel: 'Play Voice Moment from Ola',
            onTap: () {},
            displayName: 'Ola',
          ),
        ),
      );
      final context = tester.element(find.byType(MomentStoryTile));
      final disc = tester.widget<MomentSeenAvatar>(
        find.descendant(
          of: find.byType(MomentStoryTile),
          matching: find.byType(MomentSeenAvatar),
        ),
      );
      expect(disc.ringWidth, 2.5);
      expect(disc.ringInset, 2);
      expect(disc.ringKey, MomentStoryTile.ringKey);
      expect(disc.diameter, MomentStoryTile.discFor(context));

      // The contract test/moment_story_tile_test.dart reads: a Container
      // under ringKey whose BoxDecoration carries the gradient.
      expect(
        _gradientUnder(tester, MomentStoryTile.ringKey),
        MomentStoryTile.ringGradient(context, seen: false),
      );
      expect(
        tester.widget<UserAvatar>(find.byType(UserAvatar)).radius,
        (MomentStoryTile.discFor(context) - (2.5 + 2) * 2) / 2,
      );
    },
  );

  testWidgets(
    'MomentAuthorCapsule\'s border is the same ringGradient, not a plain '
    'left-to-right LinearGradient',
    (tester) async {
      await tester.pumpWidget(
        _host(
          MomentAuthorCapsule(
            name: 'Ola',
            seen: false,
            semanticLabel: 'Play Voice Moment from Ola',
            onTap: () {},
          ),
        ),
      );
      final context = tester.element(find.byType(MomentAuthorCapsule));
      final border = tester.widget<DecoratedBox>(
        find.byKey(MomentAuthorCapsule.borderKey),
      );
      final gradient =
          (border.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient, MomentStoryTile.ringGradient(context, seen: false));
      expect(gradient.begin, AppGradients.primary.begin);
      expect(gradient.end, AppGradients.primary.end);
    },
  );
}
