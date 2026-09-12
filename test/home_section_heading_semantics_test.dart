// The Home section titles must be HEADINGS to assistive technology.
//
// Without `header: true`, VoiceOver's Headings rotor and TalkBack's heading
// navigation are empty on a long scrolling page, so the only way through Home
// is to swipe every element in turn. WCAG 1.3.1, Level A. This was the last
// blocker on the Home slice (principal round 2, H6). discover_clubs_rail.dart
// already did it correctly; Home's shared section header did not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';

Future<void> _expectHeading(
  WidgetTester tester,
  String title, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: HomeSectionHeader(title: title)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final data = tester.getSemantics(find.text(title)).getSemanticsData();
  expect(
    data.flagsCollection.isHeader,
    isTrue,
    reason:
        '"$title" at ${textScale}x must be a heading, or the Headings rotor '
        'is empty and Home can only be read by swiping every element.',
  );
  expect(data.label, title);
}

void main() {
  testWidgets('every Home section title is a heading', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      for (final title in const <String>[
        'Twoi znajomi',
        'Tu i teraz',
        'W Twoich serwerach',
        'Twoje miejsca',
      ]) {
        await _expectHeading(tester, title);
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('a section title keeps its heading role at 200 % text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await _expectHeading(tester, 'W Twoich serwerach', textScale: 2);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
}
