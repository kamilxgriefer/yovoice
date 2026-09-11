import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/layout/status_bar_scrim.dart';

// Seen in the iOS Simulator on 2026-09-11: scrolled Home headings slid under
// the status bar and collided with the clock, because the mobile body pads
// itself below the inset instead of sitting in a SafeArea.
Widget _host({required double topInset, required ThemeData theme}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(402, 874),
        padding: EdgeInsets.only(top: topInset),
      ),
      child: Scaffold(
        body: StatusBarScrim(
          child: ListView(
            padding: EdgeInsets.only(top: topInset + 16),
            children: [
              for (var index = 0; index < 40; index++)
                ListTile(title: Text('Row $index'), onTap: () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  for (final fixture in <(String, ThemeData, AppPalette)>[
    ('Dark', AppTheme.darkTheme, AppPalette.dark),
    ('Pearl', AppTheme.lightTheme, AppPalette.light),
  ]) {
    testWidgets('${fixture.$1}: the band covers exactly the status bar inset', (
      tester,
    ) async {
      _phoneSurface(tester);
      await tester.pumpWidget(_host(topInset: 62, theme: fixture.$2));
      final band = find.byKey(StatusBarScrim.bandKey);
      expect(band, findsOneWidget);
      expect(tester.getRect(band), const Rect.fromLTWH(0, 0, 402, 62));
      final decoration =
          tester.widget<DecoratedBox>(band).decoration as BoxDecoration;
      final colors = (decoration.gradient! as LinearGradient).colors;
      for (final color in colors) {
        expect(color.withValues(alpha: 1), fixture.$3.background);
        expect(color.a, greaterThan(.8));
      }
    });
  }

  testWidgets('scrolled content still receives taps below the band and '
      'the band is invisible to assistive technology', (tester) async {
    _phoneSurface(tester);
    await tester.pumpWidget(_host(topInset: 62, theme: AppTheme.darkTheme));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(IgnorePointer),
        matching: find.byKey(StatusBarScrim.bandKey),
      ),
      findsOneWidget,
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('status-bar-scrim')), findsNothing);
    semantics.dispose();
    final firstVisible = find.byType(ListTile).hitTestable().first;
    await tester.tap(firstVisible);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no top inset paints no band at all', (tester) async {
    await tester.pumpWidget(_host(topInset: 0, theme: AppTheme.darkTheme));
    expect(find.byKey(StatusBarScrim.bandKey), findsNothing);
    expect(tester.renderObject(find.byType(ListView)), isA<RenderBox>());
  });
}
