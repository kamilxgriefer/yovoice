import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_count_badge.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// Refine-look batch 1 primitives (spec §7): behaviour and recipe wiring.
/// What they LOOK like is proven by the rendered sample sheet
/// (`test/refine_sheet_capture.dart`), not here.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  MediaQueryData media = const MediaQueryData(),
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: MediaQuery(
        data: media,
        child: Directionality(
          textDirection: direction,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  // Let a theme change (MaterialApp animates it) and any cross-fade from
  // the previous pump finish, so each check reads the state it set up.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('YoCard (R2 / R3)', () {
    testWidgets('paints the block recipe with a foreground hairline', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(width: 300, child: YoCard(child: Text('Block'))),
      );
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.gradient, AppPalette.dark.blockGradient);
      expect(decoration.borderRadius, AppRadius.block);
      final edge = (box.foregroundDecoration! as BoxDecoration).border!;
      expect((edge as Border).top.color, AppPalette.dark.hairline);
      expect(find.byType(YoCornerTint), findsNothing);
      // A static card is not a button and does not scale.
      expect(find.byType(YoPressFeedback), findsNothing);
    });

    testWidgets('focus ring and selection never shift the layout', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pump(
        tester,
        SizedBox(
          width: 300,
          child: YoCard(
            onTap: () {},
            child: Focus(focusNode: focus, child: const Text('Tap me')),
          ),
        ),
      );
      final before = tester.getRect(find.text('Tap me'));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: YoCard(
                  onTap: () {},
                  selected: true,
                  child: Focus(focusNode: focus, child: const Text('Tap me')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Tap me')), before);
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final edge =
          (box.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(edge.top.width, 2);
      expect(edge.top.color, AppPalette.dark.interactiveForeground);
    });

    testWidgets('interactive card is one button that scales on touch', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        SizedBox(
          width: 300,
          child: YoCard(onTap: () => taps++, child: const Text('Open')),
        ),
      );
      expect(find.byType(YoPressFeedback), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        tester.getSemantics(find.byType(YoCard)),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          label: 'Open',
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('tint is a fixed 240 px circle at the top-end corner', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 320,
          child: YoCard(tint: AppColors.primary, child: SizedBox(height: 150)),
        ),
        direction: TextDirection.rtl,
      );
      final tint = find.byType(YoCornerTint);
      expect(tint, findsOneWidget);
      final card = tester.getRect(find.byType(YoCard));
      final circle = tester.getRect(
        find.descendant(of: tint, matching: find.byType(DecoratedBox)),
      );
      expect(circle.size, const Size.square(240));
      expect(circle.top, card.top - 90);
      // RTL: the "end" corner is the left edge.
      expect(circle.left, card.left - 70);
    });

    testWidgets('high contrast drops gradient, tint and shadow', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 300,
          child: YoCard(tint: AppColors.primary, child: Text('HC')),
        ),
        theme: AppTheme.lightTheme,
        media: const MediaQueryData(highContrast: true),
      );
      expect(find.byType(YoCornerTint), findsNothing);
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, AppPalette.light.surface);
      expect(decoration.boxShadow, isEmpty);
      final edge =
          (box.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(edge.top.color, AppPalette.light.borderStrong);
    });
  });

  group('YoPressFeedback', () {
    Matrix4 transformOf(WidgetTester tester) => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(YoPressFeedback),
            matching: find.byType(Transform),
          ),
        )
        .transform;

    // ScaleTransition scales x and y only, so read the x scale directly
    // (getMaxScaleOnAxis would report the untouched z axis, 1).
    double scaleOf(WidgetTester tester) => transformOf(tester).storage[0];

    testWidgets('touch scales to .94 and releases; taps still land', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        YoPressFeedback(
          scale: YoPressFeedback.disc,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.square(dimension: 60),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(YoPressFeedback)),
      );
      // The first frame starts the ticker's clock; the second advances it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf(tester), closeTo(.94, .001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), closeTo(1, .001));
      expect(taps, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('mouse presses and Reduce Motion do not scale', (tester) async {
      await _pump(
        tester,
        const YoPressFeedback(child: SizedBox.square(dimension: 60)),
      );
      final mouse = await tester.startGesture(
        tester.getCenter(find.byType(YoPressFeedback)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf(tester), 1);
      await mouse.up();

      await _pump(
        tester,
        const YoPressFeedback(child: SizedBox.square(dimension: 60)),
        media: const MediaQueryData(disableAnimations: true),
      );
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(YoPressFeedback)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf(tester), 1);
      await touch.up();
      await tester.pump();
    });
  });

  group('YoGradientFilledButton (R5)', () {
    testWidgets('is a real FilledButton with the gradient and the lift', (
      tester,
    ) async {
      var presses = 0;
      await _pump(
        tester,
        YoGradientFilledButton(
          key: const ValueKey('home-create-server'),
          onPressed: () => presses++,
          child: const Text('Stwórz serwer'),
        ),
      );
      expect(find.byKey(const ValueKey('home-create-server')), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(presses, 1);

      final lift = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoGradientFilledButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final shadows = (lift.decoration! as ShapeDecoration).shadows!;
      expect(shadows.single.color, AppColors.primary.withValues(alpha: .32));
      expect(shadows.single.blurRadius, 18);
      expect(shadows.single.offset, const Offset(0, 5));

      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Ink),
        ),
      );
      expect(
        (ink.decoration! as BoxDecoration).gradient,
        AppGradients.primaryAction(AppTheme.darkTheme.colorScheme),
      );
      expect(tester.getSize(find.byType(FilledButton)).height, 44);
      // FilledButton defaults to Clip.none; without the clip the gradient
      // Ink painted as a rectangle past the stadium (seen on the sheet).
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).clipBehavior,
        Clip.antiAlias,
      );
    });

    testWidgets('disabled is flat and unlit; busy keeps the gradient', (
      tester,
    ) async {
      await _pump(
        tester,
        const YoGradientFilledButton(onPressed: null, child: Text('Zapisz')),
      );
      final disabledLift = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoGradientFilledButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((disabledLift.decoration! as ShapeDecoration).shadows, isEmpty);
      expect(find.byType(Ink), findsNothing);

      var presses = 0;
      await _pump(
        tester,
        YoGradientFilledButton(
          onPressed: () => presses++,
          busy: true,
          child: const Text('Zapisz'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Ink), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(presses, 0);
      final busyLift = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoGradientFilledButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (busyLift.decoration! as ShapeDecoration).shadows!.single.color.a,
        closeTo(.16, 1e-3),
      );
    });
  });

  group('YoGradientDisc (R6 / R14)', () {
    testWidgets('draw-only, exact box, lit glow and focus ring outside', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const YoGradientDisc(
          size: 48,
          icon: Icons.play_arrow_rounded,
          emphasis: YoDiscEmphasis.lit,
          gloss: true,
          focused: true,
        ),
      );
      expect(tester.getSize(find.byType(YoGradientDisc)), const Size(48, 48));
      expect(
        find.descendant(
          of: find.byType(YoGradientDisc),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      final fill = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoGradientDisc),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = fill.decoration! as BoxDecoration;
      expect(decoration.gradient, AppGradients.primary);
      expect(
        decoration.boxShadow,
        AppFinish.discShadow(AppPalette.dark, 48, YoDiscEmphasis.lit),
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(
        tester.getSize(find.byIcon(Icons.play_arrow_rounded)).width,
        closeTo(48 * .42, .01),
      );
      handle.dispose();
    });

    testWidgets('busy, disabled and high contrast states', (tester) async {
      await _pump(
        tester,
        const YoGradientDisc(size: 34, status: YoDiscStatus.busy),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(18, 18),
      );

      await _pump(
        tester,
        const YoGradientDisc(
          size: 48,
          icon: Icons.mic_rounded,
          status: YoDiscStatus.disabled,
          gloss: true,
        ),
      );
      final disabled =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(YoGradientDisc),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(disabled.gradient, isNull);
      expect(disabled.color, AppPalette.dark.surfaceMuted);
      expect(disabled.boxShadow, isEmpty);

      await _pump(
        tester,
        const YoGradientDisc(
          size: 48,
          icon: Icons.mic_rounded,
          gloss: true,
          emphasis: YoDiscEmphasis.lit,
        ),
        media: const MediaQueryData(highContrast: true),
      );
      final hc =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(YoGradientDisc),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(hc.gradient, AppGradients.primary);
      expect(hc.boxShadow, isEmpty);
      expect(
        find.descendant(
          of: find.byType(YoGradientDisc),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'no rim under high contrast',
      );
    });
  });

  group('YoCountBadge (R11) and YoProgressRing (R12)', () {
    testWidgets('caps at 99+, keeps a 20 px floor and a host ring', (
      tester,
    ) async {
      await _pump(tester, const YoCountBadge(count: 123, ring: Colors.black));
      expect(find.text('99+'), findsOneWidget);
      await _pump(tester, const YoCountBadge(count: 3));
      // A single digit hugs its content (11 px count + 2 × 5 px padding),
      // even in a loose parent: 20 high, barely wider than the floor.
      final size = tester.getSize(find.byType(YoCountBadge));
      expect(size.height, 20);
      expect(size.width, inInclusiveRange(20, 24));
      expect(YoCountBadge.label(99), '99');

      // Like the dock badge, the count does not balloon at 200 % text.
      await _pump(
        tester,
        const YoCountBadge(count: 7),
        media: const MediaQueryData(textScaler: TextScaler.linear(2)),
      );
      expect(tester.getSize(find.byType(YoCountBadge)).height, 20);
      expect(YoCountBadge.label(100), '99+');
    });

    testWidgets('ring is draw-only at its size', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const YoProgressRing(
          value: .96,
          trackColor: Colors.grey,
          arcColor: Colors.purple,
        ),
      );
      expect(tester.getSize(find.byType(YoProgressRing)), const Size(14, 14));
      expect(
        find.descendant(
          of: find.byType(YoProgressRing),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('YoBrandMark / YoBrandLockup / YoLogo (§4)', () {
    testWidgets('mark box is exactly its size; bloom in Dark, contact in '
        'Pearl, none under high contrast', (tester) async {
      const bloomKey = ValueKey('startup-logo-bloom');
      await _pump(
        tester,
        const YoBrandMark(
          key: ValueKey('home-brand-mark'),
          size: 32,
          bloomKey: bloomKey,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-brand-mark'))),
        const Size(32, 32),
      );
      expect(find.byKey(bloomKey), findsOneWidget);
      expect(tester.getSize(find.byKey(bloomKey)), const Size(51.2, 51.2));
      expect(find.byType(ColorFiltered), findsNothing);

      await _pump(
        tester,
        const YoBrandMark(size: 32, bloomKey: bloomKey),
        theme: AppTheme.lightTheme,
      );
      expect(find.byKey(bloomKey), findsNothing);
      expect(find.byType(ColorFiltered), findsOneWidget);

      await _pump(
        tester,
        const YoBrandMark(
          size: 32,
          light: YoBrandLight.bloom,
          bloomKey: bloomKey,
        ),
        media: const MediaQueryData(highContrast: true),
      );
      expect(find.byKey(bloomKey), findsNothing);
      expect(find.byType(ColorFiltered), findsNothing);

      final images = tester.widgetList<Image>(find.byType(Image));
      for (final image in images) {
        expect(image.excludeFromSemantics, isTrue);
      }
    });

    testWidgets('lockup is one "YO Voice" node and the mark follows 200 % '
        'text', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const YoBrandLockup(
          key: ValueKey('home-brand-lockup'),
          markKey: ValueKey('home-brand-mark'),
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('home-brand-lockup'))),
        matchesSemantics(label: 'YO Voice'),
      );
      expect(find.text('YO Voice'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('home-brand-mark'))),
        const Size(32, 32),
      );

      await _pump(
        tester,
        const YoBrandLockup(markKey: ValueKey('home-brand-mark')),
        media: const MediaQueryData(textScaler: TextScaler.linear(2)),
      );
      // 1.1 × the 2× wordmark line (16 × 1.2 × 2 = 38.4) = 42.24, ≤ 48.
      expect(
        tester.getSize(find.byKey(const ValueKey('home-brand-mark'))).width,
        closeTo(42.24, .01),
      );
      handle.dispose();
    });

    testWidgets('YoLogo renders the real lockup (no SVG crash path)', (
      tester,
    ) async {
      await _pump(tester, const YoLogo());
      expect(find.byType(YoBrandLockup), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('UserAvatar finish', () {
    testWidgets('flat stays the default disc with the w900 initial', (
      tester,
    ) async {
      await _pump(tester, const UserAvatar(radius: 24, displayName: 'Ada'));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(UserAvatar),
          matching: find.byType(Container),
        ),
      );
      expect(container.color, UserAvatar.defaultFill);
      expect(UserAvatar.defaultFill, const Color(0xFF64258E));
      final text = tester.widget<Text>(find.text('A'));
      expect(text.style!.fontWeight, FontWeight.w900);
      expect(text.style!.fontSize, 24 * .9);
    });

    testWidgets('brand uses the letter gradient and the calm initial', (
      tester,
    ) async {
      await _pump(
        tester,
        const UserAvatar(
          radius: 24,
          displayName: 'Ada',
          finish: UserAvatarFinish.brand,
        ),
      );
      expect(tester.getSize(find.byType(UserAvatar)), const Size(48, 48));
      final fill = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipOval),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (fill.decoration as BoxDecoration).gradient,
        AppGradients.letterAvatar,
      );
      final text = tester.widget<Text>(find.text('A'));
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.style!.fontSize, closeTo(48 * .38, 1e-9));
      expect(text.style!.letterSpacing, -.3);
      expect(text.style!.shadows, isNotEmpty);
      expect(text.style!.color, AppColors.white);
      expect(text.textScaler, TextScaler.noScaling);
    });

    testWidgets('brand keeps a translucent identity fill flat', (tester) async {
      final translucent = AppColors.accent.withValues(alpha: .12);
      await _pump(
        tester,
        UserAvatar(
          radius: 20,
          displayName: 'W',
          backgroundColor: translucent,
          finish: UserAvatarFinish.brand,
        ),
      );
      final fill = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipOval),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = fill.decoration as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, translucent);
    });
  });

  group('YoEmptyState leading', () {
    testWidgets('replaces the 76 px circle when set', (tester) async {
      await _pump(
        tester,
        const YoEmptyState(
          icon: Icons.hub_outlined,
          title: 'Twoje miejsce na wspólne rozmowy',
          leading: SizedBox(key: ValueKey('leading'), width: 72, height: 72),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leading')), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsNothing);
    });
  });

  group('YoWaveform opt-ins (R13)', () {
    Future<Uint8List> render(WidgetTester tester, YoWaveform wave) async {
      await _pump(tester, SizedBox(width: 100, height: 10, child: wave));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(
          of: find.byType(YoWaveform),
          matching: find.byType(RepaintBoundary),
        ),
      );
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        bytes = data!.buffer.asUint8List();
        image.dispose();
      });
      return bytes;
    }

    int red(Uint8List rgba, int x, {int y = 5, int width = 100}) =>
        rgba[(y * width + x) * 4];

    const idle = Color(0xFF0000FF);
    const played = Color(0xFFFF0000);

    testWidgets('continuousProgress pours into the bar under the playhead', (
      tester,
    ) async {
      final pour = await render(
        tester,
        const YoWaveform(
          color: idle,
          playedColor: played,
          progress: .4,
          continuousProgress: true,
          silhouette: [1],
          barCount: 1,
          barGap: 0,
          barRadius: 0,
          height: 10,
        ),
      );
      expect(red(pour, 20), greaterThan(200));
      expect(red(pour, 60), lessThan(40));

      final stepped = await render(
        tester,
        const YoWaveform(
          color: idle,
          playedColor: played,
          progress: .4,
          silhouette: [1],
          barCount: 1,
          barGap: 0,
          barRadius: 0,
          height: 10,
        ),
      );
      // The default still fills whole bars only: .4 < the bar's midpoint.
      expect(red(stepped, 20), lessThan(40));
    });

    testWidgets('gradientSpan full reveals one fixed sweep', (tester) async {
      const sweep = LinearGradient(colors: [played, idle]);
      final full = await render(
        tester,
        const YoWaveform(
          color: Color(0xFF00FF00),
          playedGradient: sweep,
          progress: .5,
          continuousProgress: true,
          gradientSpan: YoWaveformGradientSpan.full,
          silhouette: [1],
          barCount: 1,
          barGap: 0,
          barRadius: 0,
          height: 10,
        ),
      );
      final compressed = await render(
        tester,
        const YoWaveform(
          color: Color(0xFF00FF00),
          playedGradient: sweep,
          progress: .5,
          continuousProgress: true,
          silhouette: [1],
          barCount: 1,
          barGap: 0,
          barRadius: 0,
          height: 10,
        ),
      );
      // At x = 45 the full sweep is only 45 % of the way to blue; the
      // played-width sweep is already 90 % there.
      expect(red(full, 45), greaterThan(120));
      expect(red(compressed, 45), lessThan(60));
    });
  });
}
