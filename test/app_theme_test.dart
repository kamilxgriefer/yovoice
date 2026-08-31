import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_social_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/cards/yo_glass_card.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

void main() {
  group('AppTheme semantic palette', () {
    for (final entry in <(String, ThemeData, AppPalette)>[
      ('dark', AppTheme.darkTheme, AppPalette.dark),
      ('Pearl light', AppTheme.lightTheme, AppPalette.light),
    ]) {
      test('${entry.$1} keeps essential colour pairs accessible', () {
        final scheme = entry.$2.colorScheme;
        final palette = entry.$3;

        _expectContrast(
          '${entry.$1} primary label',
          scheme.onPrimary,
          scheme.primary,
          4.5,
        );
        _expectContrast(
          '${entry.$1} secondary label',
          scheme.onSecondary,
          scheme.secondary,
          4.5,
        );
        _expectContrast(
          '${entry.$1} error label',
          scheme.onError,
          scheme.error,
          4.5,
        );
        _expectContrast(
          '${entry.$1} body',
          palette.textPrimary,
          palette.background,
          4.5,
        );
        _expectContrast(
          '${entry.$1} secondary copy',
          palette.textSecondary,
          palette.surface,
          4.5,
        );
        _expectContrast(
          '${entry.$1} tertiary copy',
          palette.textTertiary,
          palette.surface,
          4.5,
        );
        _expectContrast(
          '${entry.$1} tertiary copy on sunken surfaces',
          palette.textTertiary,
          palette.surfaceSunken,
          4.5,
        );
        _expectContrast(
          '${entry.$1} inactive navigation',
          palette.navigationInactive,
          palette.navigationSurface,
          4.5,
        );
        _expectContrast(
          '${entry.$1} control boundary',
          palette.borderStrong,
          palette.surface,
          3,
        );
        _expectContrast(
          '${entry.$1} navigation outline',
          palette.navigationOutline,
          palette.navigationSurface,
          3,
        );
        _expectContrast(
          '${entry.$1} interactive copy',
          palette.interactiveForeground,
          palette.surface,
          4.5,
        );
        _expectContrast(
          '${entry.$1} focus ring',
          palette.focus,
          palette.surfaceRaised,
          3,
        );
        _expectContrast(
          '${entry.$1} primary-button focus boundary',
          scheme.onPrimary,
          scheme.primary,
          3,
        );
        _expectContrast(
          '${entry.$1} gradient-button focus boundary',
          scheme.onPrimary,
          scheme.secondary,
          3,
        );
        _expectContrast(
          '${entry.$1} danger-button focus boundary',
          scheme.onError,
          scheme.error,
          3,
        );
        for (final status in <(String, Color, Color)>[
          ('danger', palette.dangerForeground, palette.dangerSurface),
          ('success', palette.successForeground, palette.successSurface),
          ('warning', palette.warningForeground, palette.warningSurface),
          ('info', palette.infoForeground, palette.infoSurface),
        ]) {
          _expectContrast(
            '${entry.$1} ${status.$1} container',
            status.$2,
            status.$3,
            4.5,
          );
        }
        expect(
          palette.navigationOutline,
          isNot(palette.focus),
          reason: 'Navigation chrome must not borrow the focus token.',
        );

        expect(scheme.surfaceContainerLowest, palette.surfaceSunken);
        expect(scheme.surfaceContainerLow, palette.surfaceMuted);
        expect(scheme.surfaceContainer, palette.surface);
        expect(scheme.surfaceContainerHigh, palette.surfaceRaised);
        expect(scheme.surfaceContainerHighest, palette.surfaceRaised);
        expect(scheme.surfaceBright, palette.surfaceRaised);
        expect(scheme.surfaceDim, palette.surfaceSunken);
        expect(scheme.surfaceTint, Colors.transparent);
      });
    }

    test('system chrome follows theme brightness', () {
      final dark = AppTheme.systemOverlayStyle(
        Brightness.dark,
        AppPalette.dark,
      );
      final light = AppTheme.systemOverlayStyle(
        Brightness.light,
        AppPalette.light,
      );

      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      expect(light.statusBarColor, Colors.transparent);
      expect(light.systemNavigationBarColor, AppPalette.light.background);
      expect(
        dark.systemNavigationBarDividerColor,
        AppPalette.dark.navigationOutline,
      );
      expect(
        light.systemNavigationBarDividerColor,
        AppPalette.light.navigationOutline,
      );
    });

    test('copyWith and lerp preserve every refined semantic role', () {
      const marker = Color(0xFF123456);
      final copy = AppPalette.dark.copyWith(
        navigationOutline: marker,
        interactiveForeground: marker,
        dangerSurface: marker,
        dangerForeground: marker,
        successSurface: marker,
        successForeground: marker,
        warningSurface: marker,
        warningForeground: marker,
        infoSurface: marker,
        infoForeground: marker,
      );

      for (final value in <Color>[
        copy.navigationOutline,
        copy.interactiveForeground,
        copy.dangerSurface,
        copy.dangerForeground,
        copy.successSurface,
        copy.successForeground,
        copy.warningSurface,
        copy.warningForeground,
        copy.infoSurface,
        copy.infoForeground,
      ]) {
        expect(value, marker);
      }

      expect(
        _paletteValues(AppPalette.dark.lerp(AppPalette.light, 0)),
        _paletteValues(AppPalette.dark),
      );
      expect(
        _paletteValues(AppPalette.dark.lerp(AppPalette.light, 1)),
        _paletteValues(AppPalette.light),
      );
    });

    for (final entry in <(String, ThemeData, AppPalette)>[
      ('dark', AppTheme.darkTheme, AppPalette.dark),
      ('Pearl light', AppTheme.lightTheme, AppPalette.light),
    ]) {
      test('${entry.$1} component states stay semantic', () {
        final theme = entry.$2;
        final palette = entry.$3;
        final disabled = <WidgetState>{WidgetState.disabled};
        final focused = <WidgetState>{WidgetState.focused};
        final selected = <WidgetState>{WidgetState.selected};

        expect(
          theme.filledButtonTheme.style?.backgroundColor?.resolve(disabled),
          palette.surfaceSunken,
        );
        expect(
          theme.filledButtonTheme.style?.foregroundColor?.resolve(disabled),
          palette.textTertiary,
        );
        expect(
          theme.filledButtonTheme.style?.side?.resolve(focused)?.color,
          theme.colorScheme.onPrimary,
        );
        expect(
          theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
          palette.interactiveForeground,
        );
        expect(
          theme.outlinedButtonTheme.style?.side?.resolve(focused)?.color,
          palette.focus,
        );
        expect(
          theme.textButtonTheme.style?.foregroundColor?.resolve({}),
          palette.interactiveForeground,
        );
        expect(
          theme.inputDecorationTheme.focusedBorder?.borderSide.color,
          palette.focus,
        );
        expect(
          theme.switchTheme.trackColor?.resolve(disabled),
          palette.surfaceSunken,
        );
        expect(
          theme.switchTheme.trackColor?.resolve(selected),
          theme.colorScheme.primary,
        );
        expect(theme.tabBarTheme.labelColor, palette.interactiveForeground);
      });
    }
  });

  group('shared component theme matrix', () {
    for (final brightness in Brightness.values) {
      for (final width in <double>[320, 768, 1440]) {
        testWidgets(
          '${brightness.name} renders at ${width.toInt()}px and 200% text',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: brightness == Brightness.light
                    ? ThemeMode.light
                    : ThemeMode.dark,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: const _ComponentGallery(),
                ),
              ),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
            final context = tester.element(find.byType(_ComponentGallery));
            final palette = context.appPalette;
            expect(
              Theme.of(context).scaffoldBackgroundColor,
              palette.background,
            );
            expect(find.text('Primary action'), findsOneWidget);
            await tester.scrollUntilVisible(
              find.text('A quiet empty state'),
              240,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.text('A quiet empty state'), findsOneWidget);
          },
        );
      }
    }
  });
}

class _ComponentGallery extends StatelessWidget {
  const _ComponentGallery();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Pearl component gallery',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 16),
          YoCard(
            child: Text(
              'Semantic surface',
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          YoGlassCard(
            child: Text(
              'Raised glass surface',
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          YoButton(label: 'Primary action', onPressed: _noop),
          const SizedBox(height: 12),
          YoButton(
            label: 'Secondary action',
            variant: YoButtonVariant.secondary,
            onPressed: _noop,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const YoIconButton(
                icon: Icons.settings_rounded,
                semanticLabel: 'Settings',
                onPressed: _noop,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: YoSocialButton(
                  label: 'Continue securely',
                  icon: Icons.lock_rounded,
                  onPressed: _noop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const YoTextField(label: 'Display name', hint: 'Your name'),
          const YoEmptyState(
            compact: true,
            icon: Icons.auto_awesome_rounded,
            title: 'A quiet empty state',
            subtitle: 'Clear, readable and ready for the next action.',
          ),
          const YoErrorState(message: 'Something needs attention.'),
          const YoLoadingIndicator(message: 'Preparing your space…'),
        ],
      ),
    );
  }
}

void _noop() {}

List<Color> _paletteValues(AppPalette palette) => <Color>[
  palette.background,
  palette.backgroundTop,
  palette.surface,
  palette.surfaceMuted,
  palette.surfaceRaised,
  palette.surfaceSunken,
  palette.border,
  palette.borderStrong,
  palette.textPrimary,
  palette.textSecondary,
  palette.textTertiary,
  palette.navigationSurface,
  palette.navigationOutline,
  palette.navigationInactive,
  palette.interactiveForeground,
  palette.shadow,
  palette.scrim,
  palette.focus,
  palette.dangerSurface,
  palette.dangerForeground,
  palette.successSurface,
  palette.successForeground,
  palette.warningSurface,
  palette.warningForeground,
  palette.infoSurface,
  palette.infoForeground,
];

void _expectContrast(
  String reason,
  Color foreground,
  Color background,
  double minimum,
) {
  final light = foreground.computeLuminance() + .05;
  final dark = background.computeLuminance() + .05;
  final ratio = light > dark ? light / dark : dark / light;
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$reason is ${ratio.toStringAsFixed(2)}:1, expected $minimum:1',
  );
}
