import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + .05) / (darker.computeLuminance() + .05);
}

Widget _host({
  required ThemeData theme,
  PeopleStatus status = PeopleStatus.online,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PeopleStatusAvatar(
            displayName: 'Ada Lovelace',
            status: status,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('PeopleStatusAvatar semantic colour system', () {
    for (final fixture in <(String, ThemeData, AppPalette)>[
      ('Dark', AppTheme.darkTheme, AppPalette.dark),
      ('Pearl', AppTheme.lightTheme, AppPalette.light),
    ]) {
      testWidgets('${fixture.$1} uses palette-owned copy and ring surface', (
        tester,
      ) async {
        await tester.pumpWidget(_host(theme: fixture.$2));

        final name = tester.widget<Text>(find.text('Ada Lovelace'));
        final status = tester.widget<Text>(find.text('Online'));
        final ring = tester
            .widgetList<Container>(find.byType(Container))
            .where(
              (container) =>
                  container.decoration is BoxDecoration &&
                  (container.decoration! as BoxDecoration).shape ==
                      BoxShape.circle,
            )
            .single;
        final ringDecoration = ring.decoration! as BoxDecoration;

        expect(name.style?.color, fixture.$3.textPrimary);
        expect(status.style?.color, fixture.$3.successForeground);
        expect(ringDecoration.color, fixture.$3.surfaceRaised);
        expect(
          (ringDecoration.border! as Border).top.color,
          fixture.$3.successForeground,
        );
        expect(ringDecoration.boxShadow?.single.color.a, closeTo(.18, .001));
      });

      test('${fixture.$1} status copy and rings meet WCAG contrast', () {
        final palette = fixture.$3;

        expect(
          _contrastRatio(palette.textPrimary, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        for (final status in PeopleStatus.values) {
          final foreground = status.foreground(palette);
          expect(
            _contrastRatio(foreground, palette.background),
            greaterThanOrEqualTo(4.5),
            reason: '${status.name} label on ${fixture.$1} canvas',
          );
          expect(
            _contrastRatio(foreground, palette.surfaceRaised),
            greaterThanOrEqualTo(3),
            reason: '${status.name} ring on ${fixture.$1} surface',
          );
        }
      });
    }

    testWidgets('status meaning is exposed as text and semantics, not colour', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(theme: AppTheme.lightTheme, status: PeopleStatus.inClub),
      );

      expect(find.text('In a club'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(PeopleStatusAvatar))
          .getSemanticsData();
      expect(data.label, 'Ada Lovelace');
      expect(data.value, 'In a club');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('320px at 200% text remains overflow-free in both themes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
        await tester.pumpWidget(_host(theme: theme, textScale: 2));
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(PeopleStatusAvatar)).width,
          lessThanOrEqualTo(320),
        );
      }
    });
  });
}
