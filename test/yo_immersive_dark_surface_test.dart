import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

void main() {
  testWidgets(
    'inherits dark theme locally and requests light system chrome icons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: YoImmersiveDarkSurface(
              child: Builder(
                key: const ValueKey('immersive-dark-child'),
                builder: (context) => const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      final childContext = tester.element(
        find.byKey(const ValueKey('immersive-dark-child')),
      );
      expect(Theme.of(childContext).brightness, Brightness.dark);
      expect(childContext.appPalette.background, AppPalette.dark.background);
      expect(childContext.appPalette.textPrimary, AppPalette.dark.textPrimary);

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(YoImmersiveDarkSurface),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      final style = region.value;
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(style.systemNavigationBarColor, AppPalette.dark.background);
      expect(
        style.systemNavigationBarDividerColor,
        AppPalette.dark.navigationOutline,
      );
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    },
  );
}
