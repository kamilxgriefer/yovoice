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
          3,
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
    });
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
