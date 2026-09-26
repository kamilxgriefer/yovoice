import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';

/// Refine-look batch 3, "shared controls": hairline controls app-wide
/// (spec §3 R5 / R8 / R9 / R11, §6 `app_theme.dart`, §7).
void main() {
  final themes = <(String, ThemeData, AppPalette)>[
    ('Dark', AppTheme.darkTheme, AppPalette.dark),
    ('Pearl', AppTheme.lightTheme, AppPalette.light),
  ];

  group('theme', () {
    for (final (name, theme, palette) in themes) {
      test('$name chips and cards take hairlines; nothing else moves', () {
        expect(
          theme.chipTheme.side,
          BorderSide(color: palette.hairlineControl),
        );
        // Selected keeps its container and checkmark (R8).
        expect(
          theme.chipTheme.selectedColor,
          theme.colorScheme.primaryContainer,
        );
        final card = theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(card.side, BorderSide(color: palette.hairline));
        expect(card.borderRadius, AppRadius.lg);

        // §6: no iconButtonTheme / outlinedButtonTheme / input change (the
        // desktop rail reads the themed IconButton).
        expect(
          theme.outlinedButtonTheme.style?.side?.resolve(const {}),
          BorderSide(color: palette.borderStrong),
        );
        expect(
          theme.iconButtonTheme.style?.side?.resolve(const {}),
          BorderSide.none,
        );
        expect(
          theme.inputDecorationTheme.enabledBorder?.borderSide.color,
          palette.borderStrong,
        );
      });
    }
  });

  group('high-contrast theme twins', () {
    for (final (name, base, twin, palette)
        in <(String, ThemeData, ThemeData, AppPalette)>[
          (
            'Dark',
            AppTheme.darkTheme,
            AppTheme.darkHighContrastTheme,
            AppPalette.dark,
          ),
          (
            'Pearl',
            AppTheme.lightTheme,
            AppTheme.lightHighContrastTheme,
            AppPalette.light,
          ),
        ]) {
      test('$name restores borderStrong on chips and cards only', () {
        expect(twin.chipTheme.side, BorderSide(color: palette.borderStrong));
        expect(
          (twin.cardTheme.shape! as RoundedRectangleBorder).side,
          BorderSide(color: palette.borderStrong),
        );
        expect(twin.colorScheme, base.colorScheme);
        expect(twin.extension<AppPalette>(), base.extension<AppPalette>());
        expect(twin.chipTheme.selectedColor, base.chipTheme.selectedColor);
        expect(
          twin.inputDecorationTheme.enabledBorder,
          base.inputDecorationTheme.enabledBorder,
        );
      });
    }

    test('the app hands both twins to MaterialApp', () {
      final source = File('lib/app/app.dart').readAsStringSync();
      expect(
        source,
        contains('highContrastTheme: AppTheme.lightHighContrastTheme'),
      );
      expect(
        source,
        contains('highContrastDarkTheme: AppTheme.darkHighContrastTheme'),
      );
    });
  });

  group('YoButton primary (R5)', () {
    for (final (name, theme, _) in themes) {
      testWidgets('$name paints primaryAction under the rail lift', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(YoButton(label: 'Stwórz serwer', onPressed: () {}), theme),
        );
        final decoration = _buttonDecoration(tester);
        final gradient = decoration.gradient! as LinearGradient;
        final expected = AppGradients.primaryAction(theme.colorScheme);
        expect(gradient.colors, expected.colors);
        expect(gradient.begin, expected.begin);
        expect(gradient.end, expected.end);
        expect(decoration.color, isNull);
        expect(decoration.boxShadow, AppFinish.actionLift(AppColors.primary));
        final label = tester.widget<Text>(find.text('Stwórz serwer'));
        expect(label.style!.letterSpacing, .2);
      });
    }

    testWidgets('hover strengthens the lift and draws no outline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(YoButton(label: 'Go', onPressed: () {}), AppTheme.darkTheme),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(YoButton)));
      addTearDown(mouse.removePointer);
      await tester.pumpAndSettle();

      final decoration = _buttonDecoration(tester);
      expect(
        decoration.boxShadow,
        AppFinish.actionLift(AppColors.primary, hovered: true),
      );
      expect(decoration.border, isNull);
    });

    testWidgets('a touch press sinks the lift and scales to .98', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(YoButton(label: 'Go', onPressed: () {}), AppTheme.lightTheme),
      );
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(YoButton)),
      );
      // The first frame starts the ticker's clock; the second advances it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        _buttonDecoration(tester).boxShadow,
        AppFinish.actionLift(AppColors.primary, pressed: true),
      );
      expect(
        _scaleOf(tester, find.byType(YoButton)),
        closeTo(YoButton.pressScale, 1e-9),
      );

      await touch.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, find.byType(YoButton)), 1);
      expect(
        _buttonDecoration(tester).boxShadow,
        AppFinish.actionLift(AppColors.primary),
      );
    });

    testWidgets('no press scale with a mouse or under Reduce Motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(YoButton(label: 'Go', onPressed: () {}), AppTheme.darkTheme),
      );
      final mouse = await tester.startGesture(
        tester.getCenter(find.byType(YoButton)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scaleOf(tester, find.byType(YoButton)), 1);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host(
          YoButton(label: 'Still', onPressed: () {}),
          AppTheme.darkTheme,
          disableAnimations: true,
        ),
      );
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(YoButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scaleOf(tester, find.byType(YoButton)), 1);
      await touch.up();
      await tester.pump();
    });

    testWidgets('loading keeps the gradient and half the lift', (tester) async {
      await tester.pumpWidget(
        _host(
          YoButton(label: 'Zapisz', onPressed: () {}, isLoading: true),
          AppTheme.darkTheme,
        ),
      );
      final decoration = _buttonDecoration(tester);
      expect(decoration.gradient, isNotNull);
      expect(
        decoration.boxShadow,
        AppFinish.actionLift(AppColors.primary, strength: .5),
      );
      // A white spinner with no theme track: `surfaceSunken` drew a dark
      // ring on the gradient.
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, AppTheme.darkTheme.colorScheme.onPrimary);
      expect(spinner.backgroundColor, Colors.transparent);
    });

    testWidgets('busy stays busy when the caller also nulls onPressed', (
      tester,
    ) async {
      // The media review's Send and the Yeel composer's Publish pass
      // `onPressed: null` while they work; that must not turn the busy
      // gradient into the disabled look.
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const YoButton(label: 'Wyślij', onPressed: null, isLoading: true),
          AppTheme.lightTheme,
        ),
      );
      final decoration = _buttonDecoration(tester);
      expect(
        (decoration.gradient! as LinearGradient).colors,
        AppGradients.primaryAction(AppTheme.lightTheme.colorScheme).colors,
      );
      expect(
        decoration.boxShadow,
        AppFinish.actionLift(AppColors.primary, strength: .5),
      );
      expect(decoration.border, isNull);
      expect(_innerSide(tester), BorderSide.none);
      expect(
        tester.widget<Text>(find.text('Wyślij')).style!.color,
        AppTheme.lightTheme.colorScheme.onPrimary,
      );
      // Still refuses presses and says it is loading.
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester.getSemantics(find.byType(YoButton)),
        matchesSemantics(
          label: 'Wyślij, loading',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('disabled is quiet and high contrast drops the lift', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const YoButton(label: 'Off', onPressed: null),
          AppTheme.darkTheme,
        ),
      );
      var decoration = _buttonDecoration(tester);
      expect(decoration.gradient, isNull);
      // R5: a disabled primary action is `surfaceSunken` with a
      // `textTertiary` label, no lift and no outline.
      expect(decoration.color, AppPalette.dark.surfaceSunken);
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isEmpty);
      expect(
        tester.widget<Text>(find.text('Off')).style!.color,
        AppPalette.dark.textTertiary,
      );

      await tester.pumpWidget(
        _host(
          YoButton(label: 'On', onPressed: () {}),
          AppTheme.darkTheme,
          highContrast: true,
        ),
      );
      decoration = _buttonDecoration(tester);
      // R5 under high contrast: the gradient IS the control (white label
      // ≥ 5.79:1 on both stops), so it stays; only the lift drops.
      final gradient = decoration.gradient! as LinearGradient;
      expect(
        gradient.colors,
        AppGradients.primaryAction(AppTheme.darkTheme.colorScheme).colors,
      );
      expect(decoration.boxShadow, isEmpty);
    });

    testWidgets('the inner button never paints a side of its own', (
      tester,
    ) async {
      // Loading, disabled and focused are exactly the states in which the
      // theme's `elevatedButtonTheme.side` would draw a ring (a pale seam on
      // the busy gradient, a second concentric edge when disabled, a doubled
      // 2 px ring on focus).
      for (final (name, button) in <(String, YoButton)>[
        (
          'loading',
          YoButton(label: 'Zapisz', isLoading: true, onPressed: () {}),
        ),
        ('disabled', const YoButton(label: 'Zapisz', onPressed: null)),
        (
          'disabled secondary',
          const YoButton(
            label: 'Zapisz',
            variant: YoButtonVariant.secondary,
            onPressed: null,
          ),
        ),
      ]) {
        for (final (_, theme, _) in themes) {
          await tester.pumpWidget(_host(button, theme));
          expect(_innerSide(tester), BorderSide.none, reason: name);
        }
      }

      // A loading primary shows its gradient with no edge at all.
      await tester.pumpWidget(
        _host(
          YoButton(label: 'Zapisz', isLoading: true, onPressed: () {}),
          AppTheme.lightTheme,
        ),
      );
      expect(_buttonDecoration(tester).border, isNull);
      expect(_ringColor(tester), Colors.transparent);
    });

    for (final (name, theme, palette) in themes) {
      testWidgets('$name focus rings in the foreground without a shift', (
        tester,
      ) async {
        final pressed = <String>[];
        await tester.pumpWidget(
          _host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoButton(
                  label: 'Główny',
                  onPressed: () => pressed.add('Główny'),
                ),
                const SizedBox(height: 12),
                YoButton(
                  label: 'Drugi',
                  variant: YoButtonVariant.secondary,
                  onPressed: () => pressed.add('Drugi'),
                ),
              ],
            ),
            theme,
          ),
        );
        final primary = find.widgetWithText(YoButton, 'Główny');
        final secondary = find.widgetWithText(YoButton, 'Drugi');
        final primaryRect = tester.getRect(primary);
        final secondaryRect = tester.getRect(secondary);
        final primaryLabel = tester.getRect(find.text('Główny'));
        final secondaryLabel = tester.getRect(find.text('Drugi'));

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        // The ring arriving must not rebuild the button under the focus it
        // just took: focus stays on it and Enter activates it.
        expect(_holdsFocus(tester, primary), isTrue);
        expect(_innerSide(tester, of: primary), BorderSide.none);
        var ring = _buttonForeground(tester, of: primary)!.border! as Border;
        expect(ring.top.color, theme.colorScheme.onPrimary);
        expect(ring.top.width, 2);
        expect(_buttonDecoration(tester, of: primary).border, isNull);
        expect(tester.getRect(primary), primaryRect);
        expect(tester.getRect(find.text('Główny')), primaryLabel);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(pressed, ['Główny']);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(_holdsFocus(tester, secondary), isTrue);
        expect(_ringColor(tester, of: primary), Colors.transparent);
        expect(_innerSide(tester, of: secondary), BorderSide.none);
        ring = _buttonForeground(tester, of: secondary)!.border! as Border;
        expect(ring.top.color, palette.focus);
        expect(ring.top.width, 2);
        // The secondary's own 1 px edge stays where it was, under the ring.
        expect(
          (_buttonDecoration(tester, of: secondary).border! as Border).top,
          BorderSide(color: palette.borderStrong),
        );
        expect(tester.getRect(secondary), secondaryRect);
        expect(tester.getRect(find.text('Drugi')), secondaryLabel);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(pressed, ['Główny', 'Drugi']);
      });
    }

    testWidgets('a disabled primary is as tall as an enabled one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoButton(label: 'On', onPressed: () {}),
              const YoButton(label: 'Off', onPressed: null),
            ],
          ),
          AppTheme.darkTheme,
        ),
      );
      expect(
        tester.getSize(find.widgetWithText(YoButton, 'Off')).height,
        tester.getSize(find.widgetWithText(YoButton, 'On')).height,
      );
    });

    testWidgets('secondary keeps its strong edge and has no lift', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          YoButton(
            label: 'Spróbuj ponownie',
            variant: YoButtonVariant.secondary,
            onPressed: () {},
          ),
          AppTheme.lightTheme,
        ),
      );
      final decoration = _buttonDecoration(tester);
      expect(
        (decoration.border! as Border).top.color,
        AppPalette.light.borderStrong,
      );
      expect(decoration.boxShadow, isEmpty);
    });
  });

  group('YoIconButton (R9)', () {
    for (final (name, theme, palette) in themes) {
      testWidgets('$name default is glass with a control hairline', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            YoIconButton(icon: Icons.settings_rounded, onPressed: () {}),
            theme,
          ),
        );
        final decoration = _iconDecoration(tester);
        expect(decoration.color, palette.glass);
        expect(decoration.borderRadius, AppRadius.md);
        final edge = (decoration.border! as Border).top;
        expect(edge.color, palette.hairlineControl);
        expect(edge.width, 1);
      });

      testWidgets('$name hover firms the hairline; focus rings it', (
        tester,
      ) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _host(
            YoIconButton(
              icon: Icons.settings_rounded,
              focusNode: focus,
              onPressed: () {},
            ),
            theme,
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(find.byType(YoIconButton)),
        );
        addTearDown(mouse.removePointer);
        await tester.pumpAndSettle();
        expect(
          (_iconDecoration(tester).border! as Border).top.color,
          palette.hairlineHover,
        );

        focus.requestFocus();
        await tester.pumpAndSettle();
        final ring = (_iconDecoration(tester).border! as Border).top;
        expect(ring.color, palette.focus);
        expect(ring.width, 2);
      });
    }

    testWidgets('a caller fill and edge still win', (tester) async {
      final palette = AppPalette.dark;
      await tester.pumpWidget(
        _host(
          YoIconButton(
            icon: Icons.close_rounded,
            backgroundColor: palette.surface,
            borderColor: palette.border,
            onPressed: () {},
          ),
          AppTheme.darkTheme,
        ),
      );
      final decoration = _iconDecoration(tester);
      expect(decoration.color, palette.surface);
      expect((decoration.border! as Border).top.color, palette.border);
    });

    testWidgets('high contrast restores surface and borderStrong', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          YoIconButton(icon: Icons.add_rounded, onPressed: () {}),
          AppTheme.lightTheme,
          highContrast: true,
        ),
      );
      final decoration = _iconDecoration(tester);
      expect(decoration.color, AppPalette.light.surface);
      expect(
        (decoration.border! as Border).top.color,
        AppPalette.light.borderStrong,
      );
    });

    testWidgets('high contrast makes a caller edge strong unless it is none', (
      tester,
    ) async {
      final palette = AppPalette.dark;
      // Settings / Friends / Discover pass `palette.border` for their Back
      // buttons; media plates and the sheet close pass transparent (no edge
      // by design).
      await tester.pumpWidget(
        _host(
          YoIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            backgroundColor: palette.surface,
            borderColor: palette.border,
            onPressed: () {},
          ),
          AppTheme.darkHighContrastTheme,
          highContrast: true,
        ),
      );
      expect(
        (_iconDecoration(tester).border! as Border).top.color,
        palette.borderStrong,
      );
      expect(_iconDecoration(tester).color, palette.surface);

      await tester.pumpWidget(
        _host(
          YoIconButton(
            icon: Icons.close_rounded,
            borderColor: Colors.transparent,
            onPressed: () {},
          ),
          AppTheme.darkHighContrastTheme,
          highContrast: true,
        ),
      );
      expect(
        (_iconDecoration(tester).border! as Border).top.color,
        Colors.transparent,
      );
    });

    testWidgets('disabled keeps its quiet sunken look', (tester) async {
      await tester.pumpWidget(
        _host(
          const YoIconButton(icon: Icons.add_rounded, onPressed: null),
          AppTheme.darkTheme,
        ),
      );
      final decoration = _iconDecoration(tester);
      expect(decoration.color, AppPalette.dark.surfaceMuted);
      expect((decoration.border! as Border).top.color, AppPalette.dark.border);
    });
  });

  group('YoSearchField (R9)', () {
    for (final (name, theme, palette) in themes) {
      testWidgets('$name is a 44 px pill with a 1 px border and no lift', (
        tester,
      ) async {
        await tester.pumpWidget(_host(const YoSearchField(), theme));

        final box = find.descendant(
          of: find.byType(YoTextField),
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(box).height, YoTextField.searchHeight);
        final container = tester.widget<AnimatedContainer>(box);
        final fill = container.decoration! as BoxDecoration;
        expect(
          fill.color,
          palette.isDark ? palette.surface : palette.surfaceRaised,
        );
        expect(fill.borderRadius, AppRadius.pill);
        expect(fill.boxShadow, isNull);
        expect(fill.border, isNull);
        final edge = container.foregroundDecoration! as BoxDecoration;
        expect(edge.borderRadius, AppRadius.pill);
        expect((edge.border! as Border).top.color, palette.border);
        expect((edge.border! as Border).top.width, 1);

        final glyph = IconTheme.of(
          tester.element(find.byIcon(Icons.search_rounded)),
        );
        expect(glyph.color, palette.textTertiary);
        expect(glyph.size, 20);
      });

      testWidgets('$name focus rings the pill without moving the text', (
        tester,
      ) async {
        await tester.pumpWidget(_host(const YoSearchField(), theme));
        final box = find.descendant(
          of: find.byType(YoTextField),
          matching: find.byType(AnimatedContainer),
        );
        final restText = tester.getTopLeft(find.byType(EditableText));

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        final container = tester.widget<AnimatedContainer>(box);
        final ring =
            (container.foregroundDecoration! as BoxDecoration).border!
                as Border;
        expect(ring.top.color, palette.focus);
        expect(ring.top.width, 2);
        expect((container.decoration! as BoxDecoration).boxShadow, isNull);
        expect(tester.getSize(box).height, YoTextField.searchHeight);
        expect(tester.getTopLeft(find.byType(EditableText)), restText);
      });
    }

    testWidgets('high contrast restores the borderStrong edge', (tester) async {
      await tester.pumpWidget(
        _host(const YoSearchField(), AppTheme.darkTheme, highContrast: true),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoTextField),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        ((container.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        AppPalette.dark.borderStrong,
      );
    });

    testWidgets('the clear action follows the text and clears it', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var cleared = 0;
      final changes = <String>[];
      await tester.pumpWidget(
        _host(
          YoSearchField(
            controller: controller,
            onChanged: changes.add,
            onClear: () => cleared++,
          ),
          AppTheme.darkTheme,
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // No parent rebuild: the field itself shows the clear action.
      await tester.enterText(find.byType(TextField), 'Ola');
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      final box = find.descendant(
        of: find.byType(YoTextField),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(box).height, YoTextField.searchHeight);
      expect(
        tester.getSize(
          find.ancestor(
            of: find.byIcon(Icons.close_rounded),
            matching: find.byType(IconButton),
          ),
        ),
        const Size(44, 44),
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(cleared, 1);
      expect(changes.last, '');
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('Clear from the keyboard hands focus back to the field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var cleared = 0;
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () {}, child: const Text('Przed')),
              YoSearchField(
                controller: controller,
                onClear: () => cleared++,
              ),
              TextButton(onPressed: () {}, child: const Text('Po')),
            ],
          ),
          AppTheme.darkTheme,
        ),
      );
      await tester.enterText(find.byType(TextField), 'Ola');
      await tester.pump();

      // Tab from the field reaches the clear action; Enter activates it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final clear = find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(IconButton),
      );
      expect(
        FocusManager.instance.primaryFocus?.context,
        isNotNull,
      );
      expect(
        find.descendant(
          of: clear,
          matching: find.byElementPredicate(
            (element) =>
                element == FocusManager.instance.primaryFocus?.context,
          ),
        ),
        findsOneWidget,
        reason: 'Tab from the field lands on "Wyczyść wyszukiwanie"',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(cleared, 1);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasPrimaryFocus, isTrue);

      // The next Tab continues after the field, not from the route's start.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        find.descendant(
          of: find.widgetWithText(TextButton, 'Po'),
          matching: find.byElementPredicate(
            (element) =>
                element == FocusManager.instance.primaryFocus?.context,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a caller focus node is the one that gets focus back', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Ola');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          YoSearchField(controller: controller, focusNode: focus),
          AppTheme.lightTheme,
        ),
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(focus.hasPrimaryFocus, isTrue);
    });

    for (final (name, theme, palette) in themes) {
      testWidgets('$name disabled reads as disabled', (tester) async {
        await tester.pumpWidget(
          _host(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoSearchField(key: ValueKey('on'), hint: 'Szukaj'),
                YoSearchField(
                  key: ValueKey('off'),
                  hint: 'Szukaj',
                  enabled: false,
                ),
              ],
            ),
            theme,
          ),
        );
        Color glyph(String key) => IconTheme.of(
          tester.element(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byIcon(Icons.search_rounded),
            ),
          ),
        ).color!;
        Color hint(String key) => tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintStyle!
            .color!;
        BoxDecoration edge(String key) =>
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(ValueKey(key)),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .foregroundDecoration!
                as BoxDecoration;

        expect(glyph('on'), palette.textTertiary);
        expect(hint('on'), palette.textTertiary);
        expect((edge('on').border! as Border).top.color, palette.border);

        final dimmed = palette.textTertiary.withValues(
          alpha: YoTextField.searchDisabledInkAlpha,
        );
        expect(glyph('off'), dimmed);
        expect(hint('off'), dimmed);
        expect((edge('off').border! as Border).top.color, palette.hairline);
      });
    }

    testWidgets('a search pill without a glyph keeps the strong edge', (
      tester,
    ) async {
      // Its only identifier would otherwise be the hint, which typing
      // removes (WCAG 1.4.11).
      final controller = TextEditingController(text: 'Ola');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          YoTextField(
            variant: YoTextFieldVariant.search,
            hint: 'Szukaj',
            controller: controller,
          ),
          AppTheme.darkTheme,
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoTextField),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        ((container.foregroundDecoration! as BoxDecoration).border! as Border)
            .top
            .color,
        AppPalette.dark.borderStrong,
      );
    });

    testWidgets('the glyphs follow large text, capped at 28 px', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Ola');
      addTearDown(controller.dispose);
      for (final (scale, size) in const <(double, double)>[
        (1, 20),
        (1.3, 26),
        (2, 28),
      ]) {
        await tester.pumpWidget(
          _host(
            YoSearchField(controller: controller),
            AppTheme.darkTheme,
            textScale: scale,
          ),
        );
        // The IconButton cross-fades its icon theme (AnimatedTheme, 200 ms).
        await tester.pumpAndSettle();
        expect(
          IconTheme.of(tester.element(find.byIcon(Icons.search_rounded))).size,
          size,
          reason: 'magnifier at $scale×',
        );
        expect(
          tester.getSize(find.byIcon(Icons.close_rounded)),
          Size.square(size),
          reason: 'clear glyph at $scale×',
        );
        // The clear target stays 44 px (the pill rests at 44).
        expect(
          tester.getSize(
            find.ancestor(
              of: find.byIcon(Icons.close_rounded),
              matching: find.byType(IconButton),
            ),
          ),
          const Size(44, 44),
        );
      }
    });

    testWidgets('grows at 320 px and 200 % text without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController(text: 'Zuzanna Lewandowska');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: YoSearchField(controller: controller),
          ),
          AppTheme.lightTheme,
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      final box = find.descendant(
        of: find.byType(YoTextField),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(box).height, greaterThan(YoTextField.searchHeight));
    });

    testWidgets('a standard form field is unchanged', (tester) async {
      await tester.pumpWidget(
        _host(
          const YoTextField(label: 'Nazwa', hint: 'Twoja nazwa'),
          AppTheme.darkTheme,
        ),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(YoTextField),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, AppRadius.lg);
      expect(
        (decoration.border! as Border).top.color,
        AppPalette.dark.borderStrong,
      );
      expect(container.foregroundDecoration, isNull);
    });
  });

  group('YoBadge tonal (R11)', () {
    for (final (name, theme, _) in themes) {
      testWidgets('$name tonal edges are the ink at .32', (tester) async {
        for (final variant in YoBadgeVariant.values) {
          if (variant == YoBadgeVariant.live) continue;
          await tester.pumpWidget(
            _host(YoBadge(label: variant.name, variant: variant), theme),
          );
          final decoration = _badgeDecoration(tester);
          final ink = tester
              .widget<Text>(find.text(variant.name))
              .style!
              .color!;
          expect(
            (decoration.border! as Border).top.color,
            ink.withValues(alpha: YoBadge.tonalEdgeAlpha),
            reason: '$name ${variant.name}',
          );
        }
      });

      testWidgets('$name high contrast restores the full ink edge', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            const YoBadge(label: 'info', variant: YoBadgeVariant.info),
            theme,
            highContrast: true,
          ),
        );
        final ink = tester.widget<Text>(find.text('info')).style!.color!;
        expect((_badgeDecoration(tester).border! as Border).top.color, ink);
      });
    }

    testWidgets('the live pill keeps no edge', (tester) async {
      await tester.pumpWidget(
        _host(
          const YoBadge(label: 'NA ŻYWO', variant: YoBadgeVariant.live),
          AppTheme.darkTheme,
        ),
      );
      expect(_badgeDecoration(tester).border, isNull);
      expect(_badgeDecoration(tester).color, AppColors.live);
    });
  });
}

Widget _host(
  Widget child,
  ThemeData theme, {
  bool highContrast = false,
  bool disableAnimations = false,
  double textScale = 1,
}) => MaterialApp(
  theme: theme,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      highContrast: highContrast,
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(textScale),
    ),
    child: app!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 300, child: Center(child: child)),
    ),
  ),
);

AnimatedContainer _buttonBox(WidgetTester tester, {Finder? of}) =>
    tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: of ?? find.byType(YoButton),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

BoxDecoration _buttonDecoration(WidgetTester tester, {Finder? of}) =>
    _buttonBox(tester, of: of).decoration! as BoxDecoration;

BoxDecoration? _buttonForeground(WidgetTester tester, {Finder? of}) =>
    _buttonBox(tester, of: of).foregroundDecoration as BoxDecoration?;

/// The colour of the YoButton's state ring (transparent when there is none;
/// the ring is always in the tree so focus never rebuilds the button).
Color _ringColor(WidgetTester tester, {Finder? of}) =>
    (_buttonForeground(tester, of: of)!.border! as Border).top.color;

/// Whether the primary focus sits inside [button].
bool _holdsFocus(WidgetTester tester, Finder button) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return find
      .descendant(
        of: button,
        matching: find.byElementPredicate((element) => element == focused),
      )
      .evaluate()
      .isNotEmpty;
}

/// The side the YoButton's inner [ElevatedButton] actually paints: its
/// `Material` shape after the theme and the widget style are resolved.
BorderSide _innerSide(WidgetTester tester, {Finder? of}) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.descendant(
            of: of ?? find.byType(YoButton),
            matching: find.byType(ElevatedButton),
          ),
          matching: find.byType(Material),
        )
        .first,
  );
  return (material.shape! as OutlinedBorder).side;
}

BoxDecoration _iconDecoration(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byType(YoIconButton),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

BoxDecoration _badgeDecoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(YoBadge),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

double _scaleOf(WidgetTester tester, Finder of) => tester
    .widget<ScaleTransition>(
      find.descendant(of: of, matching: find.byType(ScaleTransition)).first,
    )
    .scale
    .value;
