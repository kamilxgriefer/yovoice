import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';

void main() {
  test(
    'the app typography covers every selectable non-Latin script family',
    () {
      expect(
        AppTypography.fontFamilyFallback,
        containsAll(<String>[
          'Noto Sans Arabic',
          'Noto Sans Hebrew',
          'Noto Sans Devanagari',
          'Noto Sans Bengali',
          'Noto Sans Thai',
          'Noto Sans SC',
          'Noto Sans TC',
          'Noto Sans JP',
          'Noto Sans KR',
        ]),
      );

      for (final style in <TextStyle>[
        AppTypography.displayLarge,
        AppTypography.headlineMedium,
        AppTypography.titleMedium,
        AppTypography.bodyMedium,
        AppTypography.labelMedium,
      ]) {
        expect(style.fontFamilyFallback, AppTypography.fontFamilyFallback);
      }
    },
  );

  testWidgets(
    'the global theme propagates script fallbacks to inherited text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Text('العربية · हिन्दी · বাংলা · 日本語')),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      final context = tester.element(find.byWidget(text));
      expect(
        DefaultTextStyle.of(context).style.fontFamilyFallback,
        AppTypography.fontFamilyFallback,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
