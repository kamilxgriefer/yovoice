import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';

Widget _host(ThemeData theme, Widget child, {double textScale = 1}) =>
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Center(child: child),
        ),
      ),
    );

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return (high + .05) / (low + .05);
}

void main() {
  for (final themeCase in <({String name, ThemeData theme})>[
    (name: 'dark', theme: AppTheme.darkTheme),
    (name: 'Pearl', theme: AppTheme.lightTheme),
  ]) {
    testWidgets('${themeCase.name}: every tone pairs AA-safe ink and fill', (
      tester,
    ) async {
      for (final tone in YoMetricPillTone.values) {
        await tester.pumpWidget(
          _host(
            themeCase.theme,
            YoMetricPill(
              value: '42',
              icon: Icons.people_alt_rounded,
              tone: tone,
            ),
          ),
        );
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(YoMetricPill),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;
        // The overlay plate is translucent: judge it over the worst case,
        // pure white artwork.
        final fill = Color.alphaBlend(decoration.color!, AppColors.white);
        final text = tester.widget<Text>(find.text('42'));
        final icon = tester.widget<Icon>(find.byIcon(Icons.people_alt_rounded));
        expect(
          _contrast(text.style!.color!, fill),
          greaterThanOrEqualTo(4.5),
          reason: '${themeCase.name} ${tone.name} value',
        );
        expect(
          _contrast(icon.color!, fill),
          greaterThanOrEqualTo(3),
          reason: '${themeCase.name} ${tone.name} glyph',
        );
        expect(decoration.borderRadius, BorderRadius.circular(999));
        expect(
          decoration.border != null,
          tone == YoMetricPillTone.outlined,
          reason: 'only the outlined tone draws a border',
        );
      }
    });
  }

  testWidgets('the icon is optional and the value renders verbatim', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AppTheme.darkTheme, const YoMetricPill(value: '99+')),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);

    await tester.pumpWidget(
      _host(
        AppTheme.darkTheme,
        const YoMetricPill(value: '2.4K', icon: Icons.headphones_rounded),
      ),
    );
    expect(find.text('2.4K'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.headphones_rounded));
    expect(icon.size, YoMetricPill.iconSize);
  });

  testWidgets('iconColor tints the glyph only', (tester) async {
    await tester.pumpWidget(
      _host(
        AppTheme.darkTheme,
        const YoMetricPill(
          value: '3',
          icon: Icons.people_alt_rounded,
          iconColor: AppColors.accent,
        ),
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.people_alt_rounded)).color,
      AppColors.accent,
    );
    expect(
      tester.widget<Text>(find.text('3')).style!.color,
      isNot(AppColors.accent),
    );
  });

  testWidgets('a semantic label replaces the visible value', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        AppTheme.darkTheme,
        const YoMetricPill(value: '842', semanticLabel: '842 listening'),
      ),
    );
    expect(find.bySemanticsLabel('842 listening'), findsOneWidget);
    expect(find.bySemanticsLabel('842'), findsNothing);

    await tester.pumpWidget(
      _host(AppTheme.darkTheme, const YoMetricPill(value: '7')),
    );
    expect(
      find.bySemanticsLabel('7'),
      findsOneWidget,
      reason: 'without a label the value itself is read',
    );
    handle.dispose();
  });

  testWidgets('one line at 320 px and 200 percent text, no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        AppTheme.lightTheme,
        const SizedBox(
          width: 90,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: YoMetricPill(
              value: '12,345,678',
              icon: Icons.people_alt_rounded,
              tone: YoMetricPillTone.outlined,
            ),
          ),
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('12,345,678'));
    expect(text.maxLines, 1);
    expect(
      tester.getSize(find.byType(YoMetricPill)).width,
      lessThanOrEqualTo(90),
    );
  });
}
