import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import 'semantics_probe.dart';

void main() {
  testWidgets('legacy external image is not fetched without a canonical uid', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 57,
            child: UserAvatar(
              key: ValueKey('avatar-under-test'),
              radius: 25,
              photoUrl: 'https://example.invalid/avatar.png',
              displayName: 'Avatar Test',
            ),
          ),
        ),
      ),
    );

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey('avatar-under-test')),
    );
    expect(avatarRect.size, const Size.square(57));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);

    final clip = tester.widget<ClipOval>(find.byType(ClipOval));
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Premium uses the canonical shimmer frame and reduced motion settles statically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Center(
              child: UserAvatar(
                radius: 25,
                displayName: 'Premium Member',
                premium: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PremiumAvatarFrame), findsOneWidget);
      expect(find.byKey(premiumAvatarRingKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: UserAvatar(radius: 25, displayName: 'Free Member'),
          ),
        ),
      );
      expect(find.byType(PremiumAvatarFrame), findsNothing);
    },
  );

  group('the fallback initial is a whole grapheme cluster', () {
    // `name[0]` returns a single UTF-16 code unit. For any display name that
    // does not start with a BMP character that is the *first half of a
    // surrogate pair*, which renders as a tofu box, and for a decomposed
    // accent it silently drops the accent. Display names starting with an
    // emoji are ordinary in this product, and this widget is the one avatar
    // in the app, so every surface inherits the result.
    Future<String?> pumpInitial(WidgetTester tester, String displayName) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: UserAvatar(radius: 19, displayName: displayName)),
        ),
      );
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byType(UserAvatar),
              matching: find.byType(Text),
            ),
          )
          .data;
    }

    testWidgets('an emoji display name keeps the whole emoji', (tester) async {
      expect(await pumpInitial(tester, '🦊 Maja'), '🦊');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flag is two code points and stays one initial', (
      tester,
    ) async {
      expect(await pumpInitial(tester, '🇵🇱 Kamil'), '🇵🇱');
    });

    testWidgets('a decomposed accent is not dropped', (tester) async {
      // "Źaneta" written as Z + U+0301 COMBINING ACUTE ACCENT.
      expect(await pumpInitial(tester, 'Źaneta'), 'Ź');
    });

    testWidgets('plain and empty names are unchanged', (tester) async {
      expect(await pumpInitial(tester, 'maja'), 'M');
      expect(await pumpInitial(tester, 'Żaneta'), 'Ż');
      expect(await pumpInitial(tester, '   '), '?');
    });
  });

  group('the fallback mark is decoration, not an announced label', () {
    // Every list in the app pairs this avatar with the same name in the
    // adjacent title. While the initial contributed a label of its own, a
    // screen reader read the row as "K, Kamil, online" — the identity twice,
    // once as a meaningless letter.
    testWidgets('a row announces the name, never the initial', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListTile(
              leading: UserAvatar(radius: 20, displayName: 'Kamil'),
              title: Text('Kamil'),
              subtitle: Text('online'),
            ),
          ),
        ),
      );

      // The letter is still painted: this is about what is announced, not
      // about what is drawn.
      expect(find.text('K'), findsOneWidget);

      final labels = [
        for (final node in compiledSemanticsNodes(tester))
          node.getSemanticsData().label,
      ];
      expect(
        labels,
        isNot(contains('K')),
        reason: 'The initial must not be a node of its own.',
      );
      expect(
        labels,
        everyElement(isNot(startsWith('K\n'))),
        reason: 'The initial must not be merged in front of the name either.',
      );
      expect(labels, contains('Kamil\nonline'));
      semantics.dispose();
    });

    testWidgets('the placeholder icon is silent too', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserAvatar(radius: 20, fallbackIcon: Icons.person),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
      // An unlabelled Icon announces nothing today, so the structural
      // assertion is the one that holds: the placeholder is excluded for the
      // same reason the initial is, and cannot regress into a label later.
      expect(
        find.ancestor(
          of: find.byIcon(Icons.person),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(
        [
          for (final node in compiledSemanticsNodes(tester))
            node.getSemanticsData().label,
        ].where((label) => label.isNotEmpty),
        isEmpty,
      );
      semantics.dispose();
    });
  });

  group('the fallback foreground follows the fill', () {
    // Eleven list surfaces pass `palette.surfaceSunken`, which is near-white
    // in Pearl. White-on-near-white made the initial disappear; Dark must be
    // byte-identical to what it was.
    Future<Color?> pumpInitialColor(WidgetTester tester, Color fill) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: UserAvatar(
              radius: 25,
              displayName: 'Ola',
              backgroundColor: fill,
            ),
          ),
        ),
      );
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byType(UserAvatar),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color;
    }

    testWidgets('a light fill takes readable ink', (tester) async {
      expect(
        await pumpInitialColor(tester, AppPalette.light.surfaceSunken),
        AppColors.contrastInk,
      );
    });

    testWidgets('every dark fill keeps white', (tester) async {
      expect(
        await pumpInitialColor(tester, AppPalette.dark.surfaceSunken),
        AppColors.white,
      );
      // The widget's own default brand fill.
      expect(
        await pumpInitialColor(
          tester,
          const UserAvatar(radius: 1).backgroundColor,
        ),
        AppColors.white,
      );
    });

    testWidgets('the placeholder icon follows the same rule', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: UserAvatar(
              radius: 20,
              fallbackIcon: Icons.person,
              backgroundColor: AppPalette.light.surfaceSunken,
            ),
          ),
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.person)).color,
        AppColors.contrastInk,
      );
    });

    // `ThemeData.estimateBrightnessForColor` reads RGB and ignores alpha.
    // Nine Servers surfaces pass `ServerIdentityVisuals.iconSurface`, which
    // in Dark is a bright accent at 12 % alpha: judged unblended it reads
    // "light" and took dark ink, on a disc that composites to near-black.
    // The fill must be resolved against the surface it is painted on before
    // the estimate sees it.
    group('a translucent fill is judged after it composites', () {
      Future<Color?> pumpInitialColorInTheme(
        WidgetTester tester, {
        required Color fill,
        required ThemeData theme,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: UserAvatar(
                  radius: 25,
                  displayName: 'Ola',
                  backgroundColor: fill,
                ),
              ),
            ),
          ),
        );
        return tester
            .widget<Text>(
              find.descendant(
                of: find.byType(UserAvatar),
                matching: find.byType(Text),
              ),
            )
            .style
            ?.color;
      }

      testWidgets('the real server member fill keeps a legible initial in '
          'Dark, and stays legible in Pearl', (tester) async {
        for (final type in ServerType.values) {
          final darkFill = ServerIdentity.of(
            type,
          ).resolve(Brightness.dark).iconSurface;
          expect(
            darkFill.a,
            lessThan(1),
            reason:
                '$type: the Dark server fill must still be translucent, '
                'otherwise this test proves nothing',
          );
          expect(
            await pumpInitialColorInTheme(
              tester,
              fill: darkFill,
              theme: AppTheme.darkTheme,
            ),
            AppColors.white,
            reason:
                '$type: a 12 % accent over the dark surface composites to a '
                'near-black disc and needs white ink',
          );

          expect(
            await pumpInitialColorInTheme(
              tester,
              fill: ServerIdentity.of(
                type,
              ).resolve(Brightness.light).iconSurface,
              theme: AppTheme.lightTheme,
            ),
            AppColors.contrastInk,
            reason: '$type: the Pearl fill is a light container',
          );
        }
      });

      testWidgets('an opaque fill is unchanged by the resolution', (
        tester,
      ) async {
        // `Color.alphaBlend` is the identity for an opaque top colour, so
        // every constant-colour caller resolves exactly as it did before.
        for (final theme in <ThemeData>[
          AppTheme.darkTheme,
          AppTheme.lightTheme,
        ]) {
          expect(
            await pumpInitialColorInTheme(
              tester,
              fill: AppPalette.light.surfaceSunken,
              theme: theme,
            ),
            AppColors.contrastInk,
          );
          expect(
            await pumpInitialColorInTheme(
              tester,
              fill: AppPalette.dark.surfaceSunken,
              theme: theme,
            ),
            AppColors.white,
          );
        }
      });
    });
  });
}
