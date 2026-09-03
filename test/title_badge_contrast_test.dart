import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final light = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final dark = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (light + .05) / (dark + .05);
}

AchievementDefinition _definition(AchievementRarity rarity) {
  return AchievementDefinition(
    id: 'badge_${rarity.name}',
    title: rarity.name,
    description: 'Contrast fixture',
    metric: 'messages',
    threshold: 1,
    rarity: rarity,
  );
}

void main() {
  for (final themeEntry in <String, ThemeData>{
    'Dark': AppTheme.darkTheme,
    'Pearl': AppTheme.lightTheme,
  }.entries) {
    for (final rarity in AchievementRarity.values) {
      testWidgets(
        '${themeEntry.key} compact ${rarity.name} title is AA across gradient',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: themeEntry.value,
              home: Scaffold(
                body: Center(
                  child: TitleBadge(
                    achievement: _definition(rarity),
                    compact: true,
                  ),
                ),
              ),
            ),
          );

          final title = tester.widget<Text>(find.text(rarity.name));
          expect(title.style?.fontSize, 9.5);

          final decoratedBoxes = tester.widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(TitleBadge),
              matching: find.byType(DecoratedBox),
            ),
          );
          final decoration = decoratedBoxes
              .map((widget) => widget.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((value) => value.gradient != null);
          final gradient = decoration.gradient! as LinearGradient;
          final foreground = title.style!.color!;

          // Sample the complete rendered gradient, not only its stops.
          for (var step = 0; step <= 100; step += 1) {
            final t = step / 100;
            final scaled = t * (gradient.colors.length - 1);
            final start = scaled.floor().clamp(0, gradient.colors.length - 1);
            final end = (start + 1).clamp(0, gradient.colors.length - 1);
            final background = Color.lerp(
              gradient.colors[start],
              gradient.colors[end],
              scaled - start,
            )!;
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${rarity.name} failed at ${(t * 100).round()}% of gradient',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
