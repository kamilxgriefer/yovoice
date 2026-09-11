import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

// Home's people rail passes a 62.4 px label column (avatar radius 26 x 2.4).
// "przeszkadzać" is wider than that, and Flutter breaks a word that does not
// fit its line, so "Nie przeszkadzać" rendered as "Nie przesz / kadzać" on an
// iPhone 17 Pro (seen in the Simulator on 2026-09-11). The column must grow to
// the status's longest word instead.
const double _homeRadius = 26;
const double _homeLabelWidth = _homeRadius * 2.4;

Widget _host({
  required String displayName,
  required String status,
  double textScale = 1,
  bool showCaret = false,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PeopleStatusAvatar(
            displayName: displayName,
            status: PeopleStatus.online,
            statusLabel: status,
            radius: _homeRadius,
            labelWidth: _homeLabelWidth,
            showChangeBadge: showCaret,
            tilePadding: EdgeInsets.zero,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

/// Two neighbouring letters of one word must sit on the same line.
void _expectNoWordBrokenAcrossLines(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  double topOf(int index) => paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      )
      .first
      .top;
  for (var index = 1; index < text.length; index++) {
    if (text[index] == ' ' || text[index - 1] == ' ') continue;
    expect(
      topOf(index),
      closeTo(topOf(index - 1), 0.5),
      reason: '"$text" broke inside a word before offset $index',
    );
  }
}

void main() {
  // The default test font draws every glyph as a square, which makes every
  // word far wider than Inter does; widths are only meaningful in the font
  // the app actually ships.
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await loader.load();
  });

  for (final scale in <double>[1, 1.3, 2]) {
    for (final caret in <bool>[false, true]) {
      for (final status in <String>[
        'Nie przeszkadzać',
        'Do not disturb',
        'Zaraz wracam',
        'Nicht stören',
      ]) {
        testWidgets('"$status" never breaks inside a word at ${scale}x text '
            '(caret: $caret)', (tester) async {
          await tester.pumpWidget(
            _host(
              displayName: 'Marek',
              status: status,
              textScale: scale,
              showCaret: caret,
            ),
          );
          expect(tester.takeException(), isNull);
          _expectNoWordBrokenAcrossLines(tester, status);
        });
      }
    }
  }

  testWidgets('a short status keeps the rail pitch the column already had', (
    tester,
  ) async {
    await tester.pumpWidget(_host(displayName: 'Ola', status: 'Dostępny'));
    final column = find
        .ancestor(of: find.text('Ola'), matching: find.byType(SizedBox))
        .first;
    expect(tester.getSize(column).width, closeTo(_homeLabelWidth, 0.01));
  });

  testWidgets('a long status widens only as far as its longest word', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(displayName: 'Marek', status: 'Nie przeszkadzać'),
    );
    final column = find
        .ancestor(of: find.text('Marek'), matching: find.byType(SizedBox))
        .first;
    final width = tester.getSize(column).width;
    expect(width, greaterThan(_homeLabelWidth));
    // Two short words fit side by side in no more than twice the old column.
    expect(width, lessThan(_homeLabelWidth * 2));
  });
}
