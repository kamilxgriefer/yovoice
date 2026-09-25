import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// Pins the refine-look foundations (spec §3 / §6): the derived palette
/// getters, the new gradients, radii, motion and type roles, and every
/// `AppFinish` recipe value. Existing token values must not move — the dock
/// and the desktop rail read them and must stay byte-identical.
void main() {
  const dark = AppPalette.dark;
  const pearl = AppPalette.light;

  group('existing tokens are unchanged', () {
    test('radius family', () {
      expect(AppRadius.sm, BorderRadius.circular(8));
      expect(AppRadius.card, BorderRadius.circular(12));
      expect(AppRadius.md, BorderRadius.circular(14));
      expect(AppRadius.lg, BorderRadius.circular(20));
      expect(AppRadius.xl, BorderRadius.circular(28));
      expect(AppRadius.pill, BorderRadius.circular(999));
    });

    test('motion timings', () {
      expect(AppMotion.quick, const Duration(milliseconds: 140));
      expect(AppMotion.standard, const Duration(milliseconds: 180));
      expect(AppMotion.entrance, const Duration(milliseconds: 320));
      expect(AppMotion.standardCurve, Curves.easeOut);
      expect(AppMotion.entranceCurve, Curves.easeOutCubic);
    });

    test('the logo gradient', () {
      expect(AppGradients.primary.colors, const [
        AppColors.primary,
        AppColors.secondary,
      ]);
      expect(AppGradients.primary.begin, Alignment.topLeft);
      expect(AppGradients.primary.end, Alignment.bottomRight);
    });

    test('existing type roles', () {
      expect(AppTypography.titleMedium.fontSize, 16);
      expect(AppTypography.titleMedium.fontWeight, FontWeight.w600);
      expect(AppTypography.headlineMedium.fontSize, 22);
      expect(AppTypography.labelLarge.letterSpacing, .2);
    });
  });

  group('new tokens', () {
    test('radius aliases', () {
      expect(AppRadius.block, AppRadius.lg);
      expect(AppRadius.tile, BorderRadius.circular(16));
    });

    test('motion', () {
      expect(AppMotion.press, const Duration(milliseconds: 90));
      expect(AppMotion.release, const Duration(milliseconds: 240));
      expect(AppMotion.releaseCurve, Curves.easeOutBack);
      expect(AppMotion.glint, const Duration(milliseconds: 900));
      expect(AppMotion.glintCurve, Curves.easeInOutCubic);
    });

    test('type roles (w700 cap, tight headings)', () {
      void role(TextStyle s, double size, FontWeight w, [double? tracking]) {
        expect(s.fontFamily, AppTypography.fontFamily);
        expect(s.fontSize, size);
        expect(s.fontWeight, w);
        if (tracking != null) expect(s.letterSpacing, tracking);
      }

      role(AppTypography.screenTitle, 22, FontWeight.w700, -.5);
      expect(AppTypography.screenTitle.height, 1.15);
      role(AppTypography.greetingWide, 30, FontWeight.w700, -.8);
      expect(AppTypography.greetingWide.height, 1.1);
      role(AppTypography.sectionTitle, 17, FontWeight.w700, -.25);
      role(AppTypography.sectionTitleExpanded, 19, FontWeight.w700, -.25);
      role(AppTypography.rowTitle, 15, FontWeight.w600);
      role(AppTypography.rowTitleUnread, 15, FontWeight.w700);
      role(AppTypography.rowPreview, 13, FontWeight.w400);
      role(AppTypography.rowPreviewUnread, 13, FontWeight.w500);
      role(AppTypography.count, 11, FontWeight.w700);
      expect(
        AppTypography.count.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      role(AppTypography.overline, 11, FontWeight.w600, .6);
    });

    test('icon aliases are outline glyphs', () {
      expect(AppIcons.compose, Icons.edit_outlined);
      expect(AppIcons.addFriend, Icons.person_add_alt_outlined);
      expect(AppIcons.chat, Icons.chat_bubble_outline_rounded);
      expect(AppIcons.archive, Icons.archive_outlined);
      expect(AppIcons.notifications, Icons.notifications_none_rounded);
    });
  });

  group('derived palette getters', () {
    test('isDark follows the canvas', () {
      expect(dark.isDark, isTrue);
      expect(pearl.isDark, isFalse);
    });

    test('hairlines and glass', () {
      expect(dark.hairline, dark.textPrimary.withValues(alpha: .09));
      expect(pearl.hairline, pearl.shadow.withValues(alpha: .12));
      expect(dark.hairlineControl, dark.textPrimary.withValues(alpha: .14));
      expect(pearl.hairlineControl, pearl.textPrimary.withValues(alpha: .16));
      expect(dark.hairlineHover, dark.borderStrong.withValues(alpha: .55));
      expect(dark.glass, dark.textPrimary.withValues(alpha: .07));
      // Review D1 (deliberate spec change): Pearl's glass is a lit surface,
      // not an ink tint — surfaceRaised @ .80 instead of textPrimary @ .05.
      expect(pearl.glass, pearl.surfaceRaised.withValues(alpha: .80));
      // Lighter than the canvas it sits on, never darker.
      expect(
        Color.alphaBlend(pearl.glass, pearl.background).computeLuminance(),
        greaterThan(pearl.background.computeLuminance()),
      );
    });

    test('block fill is the spec\'s #1C1626 → #17121F / #FFFFFF → #FCFAFD', () {
      _expectHex(dark.blockTop, 0xFF1C1626);
      expect(dark.blockGradient.colors.last, dark.surface);
      expect(pearl.blockTop, const Color(0xFFFFFFFF));
      expect(pearl.blockGradient.colors, [pearl.surfaceRaised, pearl.surface]);
      expect(dark.blockGradient.begin, Alignment.topCenter);
      expect(dark.blockGradient.end, Alignment.bottomCenter);
    });

    test('block shadows: none in Dark, the plum pair in Pearl', () {
      expect(dark.blockShadows, isEmpty);
      final pair = pearl.blockShadows;
      expect(pair, hasLength(2));
      expect(pair[0].color, pearl.shadow.withValues(alpha: .06));
      expect(pair[0].blurRadius, 2);
      expect(pair[0].offset, const Offset(0, 1));
      expect(pair[1].color, pearl.shadow.withValues(alpha: .16));
      expect(pair[1].blurRadius, 24);
      expect(pair[1].offset, const Offset(0, 10));
      expect(pair[1].spreadRadius, -14);
    });

    test('light roles', () {
      expect(dark.tintAlpha, .16);
      expect(pearl.tintAlpha, .09);
      expect(dark.contactShadow, dark.shadow.withValues(alpha: .28));
      expect(pearl.contactShadow, pearl.shadow.withValues(alpha: .12));
      expect(dark.brandGlow, AppColors.secondary.withValues(alpha: .42));
      expect(pearl.brandGlow, AppColors.primary.withValues(alpha: .22));
      expect(dark.liveGlow, AppColors.live.withValues(alpha: .34));
      expect(pearl.liveGlow, AppColors.live.withValues(alpha: .18));
      expect(dark.specular, AppColors.white.withValues(alpha: .22));
      expect(dark.waveUnplayed, dark.textPrimary.withValues(alpha: .22));
      expect(pearl.waveUnplayed, pearl.textPrimary.withValues(alpha: .22));
    });

    test('canvasGlow is the Chats / Friends radial, unchanged', () {
      for (final (palette, primary, mix) in [
        (dark, AppTheme.darkTheme.colorScheme.primary, .18),
        (pearl, AppTheme.lightTheme.colorScheme.primary, .055),
      ]) {
        final glow = palette.canvasGlow(primary);
        expect(glow.center, const Alignment(-.86, -.96));
        expect(glow.radius, 1.25);
        expect(glow.stops, const [0, .38, 1]);
        expect(glow.colors, [
          Color.lerp(palette.backgroundTop, primary, mix)!,
          palette.backgroundTop,
          palette.background,
        ]);
      }
    });

    test('derived roles lerp with the palette', () {
      final mid = dark.lerp(pearl, 1);
      expect(mid.hairline, pearl.hairline);
      expect(mid.blockShadows, hasLength(2));
    });

    test('the variant B played sweep holds 3:1 against the unplayed bars at '
        'both ends, on the block top and the surface (review D3)', () {
      for (final (palette, scheme) in [
        (dark, AppTheme.darkTheme.colorScheme),
        (pearl, AppTheme.lightTheme.colorScheme),
      ]) {
        final played = AppGradients.voicePlayed(scheme, palette);
        expect(played.colors, hasLength(2));
        for (final base in [palette.blockTop, palette.surface]) {
          final unplayed = Color.alphaBlend(palette.waveUnplayed, base);
          for (final stop in played.colors) {
            expect(
              _contrast(stop, unplayed),
              greaterThanOrEqualTo(3),
              reason: '$stop vs $unplayed',
            );
          }
        }
      }
      // Pearl is the primaryAction pair; Dark lifts the logo violet and the
      // logo magenta toward white, keeping the violet → magenta read.
      expect(
        AppGradients.voicePlayed(AppTheme.lightTheme.colorScheme, pearl).colors,
        AppGradients.primaryAction(AppTheme.lightTheme.colorScheme).colors,
      );
      _expectHex(
        AppGradients.voicePlayed(AppTheme.darkTheme.colorScheme, dark)
            .colors
            .first,
        0xFFB082FA,
      );
      _expectHex(
        AppGradients.voicePlayed(AppTheme.darkTheme.colorScheme, dark)
            .colors
            .last,
        0xFFD46BFF,
      );
    });

    test('ink on the outgoing bubble holds AA text and 3:1 bars on both stops '
        'of primaryAction in both themes (review D5)', () {
      for (final scheme in [
        AppTheme.darkTheme.colorScheme,
        AppTheme.lightTheme.colorScheme,
      ]) {
        for (final stop in AppGradients.primaryAction(scheme).colors) {
          expect(
            _contrast(Color.alphaBlend(AppFinish.outgoingMeta, stop), stop),
            greaterThanOrEqualTo(4.5),
            reason: 'meta text on $stop',
          );
          expect(
            _contrast(
              Color.alphaBlend(AppFinish.outgoingWavePlayed, stop),
              Color.alphaBlend(AppFinish.outgoingWaveUnplayed, stop),
            ),
            greaterThanOrEqualTo(3),
            reason: 'played vs unplayed bars on $stop',
          );
        }
      }
    });

    test('played vs unplayed bars hold 3:1 at both ends of the sweep', () {
      for (final palette in [dark, pearl]) {
        final unplayed = Color.alphaBlend(
          palette.waveUnplayed,
          palette.blockTop,
        );
        for (final played in palette.audioProgressGradient.colors) {
          expect(
            _contrast(played, unplayed),
            greaterThanOrEqualTo(3),
            reason: '$played on $unplayed',
          );
        }
      }
    });
  });

  group('gradients', () {
    test('primaryAction is the scheme pair, left to right', () {
      final darkAction = AppGradients.primaryAction(
        AppTheme.darkTheme.colorScheme,
      );
      expect(darkAction.colors, const [Color(0xFF7B2FF7), Color(0xFFA117D8)]);
      expect(darkAction.begin, Alignment.centerLeft);
      expect(darkAction.end, Alignment.centerRight);
      final pearlAction = AppGradients.primaryAction(
        AppTheme.lightTheme.colorScheme,
      );
      expect(pearlAction.colors, const [Color(0xFF6F1FD1), Color(0xFFA117D8)]);
      for (final stop in [...darkAction.colors, ...pearlAction.colors]) {
        expect(_contrast(AppColors.white, stop), greaterThanOrEqualTo(5.78));
      }
    });

    test('letterAvatar is #6542B8 → #6D1894 with AA+ white initials', () {
      final colors = AppGradients.letterAvatar.colors;
      _expectHex(colors.first, 0xFF6542B8);
      _expectHex(colors.last, 0xFF6D1894);
      expect(_contrast(AppColors.white, colors.first), greaterThan(6.9));
      expect(_contrast(AppColors.white, colors.last), greaterThan(9.45));
    });
  });

  group('AppFinish recipes', () {
    test('block: gradient + hairline, Pearl lift, hover, high contrast', () {
      final d = AppFinish.block(dark);
      expect(d.gradient, dark.blockGradient);
      expect(d.color, isNull);
      expect((d.border! as Border).top.color, dark.hairline);
      expect(d.borderRadius, AppRadius.block);
      expect(d.boxShadow, isEmpty);

      final p = AppFinish.block(pearl);
      expect(p.boxShadow, pearl.blockShadows);
      final hovered = AppFinish.block(pearl, hovered: true);
      expect((hovered.border! as Border).top.color, pearl.hairlineHover);
      expect(hovered.boxShadow!.last.offset, const Offset(0, 14));
      expect(AppFinish.block(pearl, elevated: false).boxShadow, isEmpty);

      final hc = AppFinish.block(pearl, highContrast: true);
      expect(hc.gradient, isNull);
      expect(hc.color, pearl.surface);
      expect((hc.border! as Border).top.color, pearl.borderStrong);
      expect(hc.boxShadow, isEmpty);
    });

    test('corner tint geometry and alpha', () {
      expect(AppFinish.cornerTintSize, 240);
      expect(AppFinish.cornerTintTop, -90);
      expect(AppFinish.cornerTintEnd, -70);
      final tint = AppFinish.cornerTint(AppColors.primary, dark);
      expect(tint.stops, const [0, .68]);
      expect(tint.colors.first, AppColors.primary.withValues(alpha: .16));
      expect(tint.colors.last.a, 0);
      expect(
        AppFinish.cornerTint(AppColors.primary, pearl).colors.first,
        AppColors.primary.withValues(alpha: .09),
      );
    });

    test('live corner light is capped at 200 px of reach', () {
      final small = AppFinish.liveCorner(
        AppColors.accent,
        dark,
        shortestSide: 158,
      );
      expect(small.radius, 1);
      expect(small.center, const AlignmentDirectional(.9, -1));
      expect(small.stops, const [0, .72]);
      expect(small.colors.first, AppColors.accent.withValues(alpha: .28));
      final large = AppFinish.liveCorner(
        AppColors.accent,
        pearl,
        shortestSide: 400,
      );
      expect(large.radius, .5);
      expect(large.colors.first, AppColors.accent.withValues(alpha: .14));
    });

    test('live rim, glow and specular', () {
      expect(
        AppFinish.liveRim(dark).top.color,
        AppColors.live.withValues(alpha: .30),
      );
      expect(
        AppFinish.liveRim(pearl).top.color,
        AppColors.live.withValues(alpha: .28),
      );
      expect(
        AppFinish.liveRim(dark, hovered: true).top.color,
        AppColors.live.withValues(alpha: .45),
      );
      final hc = AppFinish.liveRim(dark, highContrast: true).top;
      expect(hc.color, AppColors.live);
      expect(hc.width, 1.5);

      final glow = AppFinish.liveGlow(dark);
      expect(glow, hasLength(1));
      expect(glow.single.color, dark.liveGlow);
      expect(glow.single.blurRadius, 32);
      expect(glow.single.offset, const Offset(0, 14));
      expect(glow.single.spreadRadius, -12);
      expect(
        AppFinish.liveGlow(dark, pressed: true).single.offset,
        const Offset(0, 8),
      );
      final pearlGlow = AppFinish.liveGlow(pearl);
      expect(pearlGlow, hasLength(2));
      expect(pearlGlow.last.color, pearl.shadow.withValues(alpha: .10));
      expect(pearlGlow.last.blurRadius, 16);
      expect(pearlGlow.last.offset, const Offset(0, 6));
      expect(pearlGlow.last.spreadRadius, -8);
      expect(AppFinish.liveGlow(dark, highContrast: true), isEmpty);

      final specular = AppFinish.liveSpecular(dark)!;
      expect(specular.colors.first, dark.specular);
      expect(specular.stops, const [0, .7]);
      expect(AppFinish.liveSpecular(pearl), isNull);
    });

    test('action lift is the rail CTA\'s values', () {
      final rest = AppFinish.actionLift(AppColors.primary).single;
      expect(rest.color, AppColors.primary.withValues(alpha: .32));
      expect(rest.blurRadius, 18);
      expect(rest.offset, const Offset(0, 5));
      final hover = AppFinish.actionLift(AppColors.primary, hovered: true);
      expect(hover.single.color, AppColors.primary.withValues(alpha: .40));
      expect(hover.single.blurRadius, 22);
      final pressed = AppFinish.actionLift(AppColors.primary, pressed: true);
      expect(pressed.single.offset, const Offset(0, 3));
      expect(pressed.single.color.a, closeTo(.32 * .6, 1e-3));
      final busy = AppFinish.actionLift(AppColors.primary, strength: .5);
      expect(busy.single.color.a, closeTo(.16, 1e-3));
    });

    test('disc shadows scale with the disc', () {
      final rest = AppFinish.discShadow(dark, 48, YoDiscEmphasis.rest);
      expect(rest.single.color, dark.contactShadow);
      expect(rest.single.blurRadius, 4);
      expect(rest.single.offset, const Offset(0, 2));

      final lit48 = AppFinish.discShadow(dark, 48, YoDiscEmphasis.lit).last;
      expect(lit48.color, dark.brandGlow);
      expect(lit48.blurRadius, closeTo(22, .5));
      expect(lit48.offset.dy, closeTo(9, .5));
      expect(lit48.spreadRadius, closeTo(-6, .5));
      final lit72 = AppFinish.discShadow(dark, 72, YoDiscEmphasis.lit).last;
      expect(lit72.blurRadius, closeTo(32, .5));
      expect(lit72.offset.dy, closeTo(13, .5));
      expect(lit72.spreadRadius, closeTo(-9, .5));

      final lift = AppFinish.discShadow(pearl, 48, YoDiscEmphasis.lift).single;
      expect(lift.color.a, closeTo(pearl.brandGlow.a * .6, 1e-3));
      expect(lift.blurRadius, closeTo(48 * .36, 1e-6));
      expect(lift.offset.dy, closeTo(48 * .14, 1e-6));
      expect(lift.spreadRadius, closeTo(-48 * .14, 1e-6));

      final hovered = AppFinish.discShadow(
        dark,
        48,
        YoDiscEmphasis.rest,
        hovered: true,
      );
      expect(hovered.single.color.a, closeTo(dark.contactShadow.a + .06, 1e-3));
    });

    test('glass states and the tonal / chip values', () {
      expect(AppFinish.glass(dark), dark.glass);
      expect(AppFinish.glass(dark, hovered: true).a, closeTo(.07 * 1.6, 1e-3));
      expect(AppFinish.glass(dark, pressed: true).a, closeTo(.11, 1e-3));
      // Pearl's lit glass never darkens on hover (the edge moves instead);
      // a press lays the block's pressed wash over it.
      expect(AppFinish.glass(pearl, hovered: true), pearl.glass);
      expect(
        AppFinish.glass(pearl, pressed: true),
        Color.alphaBlend(AppFinish.blockPressedWash(pearl), pearl.glass),
      );
      final pearlNeutral = AppFinish.tonalNeutral(pearl);
      expect(pearlNeutral.backgroundColor!.resolve({}), pearl.glass);
      expect(
        pearlNeutral.backgroundColor!.resolve({WidgetState.hovered}),
        pearl.glass,
      );
      expect(
        pearlNeutral.side!.resolve({WidgetState.hovered})!.color,
        pearl.hairlineHover,
      );
      expect(pearlNeutral.side!.resolve({})!.color, pearl.hairlineControl);
      expect(
        AppFinish.tonalNeutral(dark).side!.resolve({WidgetState.hovered})!.color,
        dark.hairlineControl,
        reason: 'Dark keeps its fill-only hover',
      );

      final neutral = AppFinish.tonalNeutral(dark);
      expect(neutral.backgroundColor!.resolve({}), dark.glass);
      expect(neutral.side!.resolve({})!.color, dark.hairlineControl);
      expect(
        neutral.side!.resolve({WidgetState.focused})!.width,
        2,
        reason: 'focus is a 2 px ring',
      );
      expect(
        neutral.foregroundColor!.resolve({WidgetState.disabled}),
        dark.textTertiary,
      );
      expect(neutral.side!.resolve({WidgetState.disabled})!.color, dark.border);

      // The style replaces the theme's label style, so it must carry Inter
      // itself (a bare TextStyle fell back to the platform font).
      expect(
        neutral.textStyle!.resolve({})!.fontFamily,
        AppTypography.fontFamily,
      );

      final accent = AppFinish.tonalAccent(pearl);
      expect(
        accent.textStyle!.resolve({})!.fontWeight,
        FontWeight.w700,
      );
      expect(
        accent.textStyle!.resolve({})!.fontFamily,
        AppTypography.fontFamily,
      );
      expect(
        accent.backgroundColor!.resolve({}),
        pearl.interactiveForeground.withValues(alpha: .06),
      );
      expect(accent.side!.resolve({})!.width, 1.5);
      expect(
        accent.side!.resolve({})!.color,
        pearl.interactiveForeground.withValues(alpha: .55),
      );

      expect(AppFinish.chipHeight, 36);
      expect(AppFinish.chipFill(dark, selected: true), dark.textPrimary);
      expect(AppFinish.chipLabel(dark, selected: true), dark.background);
      expect(AppFinish.chipLabel(dark, selected: false), dark.textSecondary);
      expect(AppFinish.chipBorder(dark, selected: true), isNull);
      expect(
        AppFinish.chipBorder(dark, selected: false)!.top.color,
        dark.hairlineControl,
      );
      expect(
        _contrast(dark.background, dark.textPrimary),
        greaterThan(15),
        reason: 'the ink inversion reads ~18.5:1',
      );
    });
  });

  group('AppMotion.decorative', () {
    Future<bool> read(
      WidgetTester tester, {
      bool disableAnimations = false,
      bool accessibleNavigation = false,
      bool tickers = true,
    }) async {
      late bool value;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: TickerMode(
            enabled: tickers,
            child: Builder(
              builder: (context) {
                value = AppMotion.decorative(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return value;
    }

    testWidgets('is off under Reduce Motion, accessible nav or TickerMode', (
      tester,
    ) async {
      expect(await read(tester), isTrue);
      expect(await read(tester, disableAnimations: true), isFalse);
      expect(await read(tester, accessibleNavigation: true), isFalse);
      expect(await read(tester, tickers: false), isFalse);
    });
  });
}

void _expectHex(Color actual, int expected) {
  final e = Color(expected);
  int c(double v) => (v * 255).round();
  expect(
    (c(actual.r) - c(e.r)).abs() <= 1 &&
        (c(actual.g) - c(e.g)).abs() <= 1 &&
        (c(actual.b) - c(e.b)).abs() <= 1,
    isTrue,
    reason:
        '${actual.toARGB32().toRadixString(16)} vs '
        '${expected.toRadixString(16)}',
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}
