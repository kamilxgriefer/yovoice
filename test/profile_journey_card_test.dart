import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';

const _sizes = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];

void main() {
  for (final size in _sizes) {
    testWidgets('journey remains a compact list at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: ProfileJourneyCard(
                  communitiesCount: 3,
                  messageCount: 42,
                  voiceMinutes: 125,
                  roomCount: 7,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final card = find.byKey(const ValueKey('profile-journey-card'));
      expect(card, findsOneWidget);
      expect(find.text('Your YO Voice journey'), findsOneWidget);
      expect(find.text('Servers joined'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Voice time'), findsOneWidget);
      expect(find.text('Servers created'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('2h 5m'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      final cardRect = tester.getRect(card);
      expect(cardRect.left, greaterThanOrEqualTo(0));
      expect(cardRect.right, lessThanOrEqualTo(size.width));
      expect(
        cardRect.width,
        moreOrLessEquals(size.width - 36, epsilon: 0.01),
        reason:
            'the journey panel must use the same full content width as '
            'the neighbouring profile panels',
      );
      // Refine-look §8.5: from a 560 px card the four counters sit side by
      // side (a glyph and label over a 22 px value); below it the card
      // keeps one compact row per counter.
      final cells = cardRect.width >= ProfileLayout.journeyCellsFromWidth;
      expect(
        find.byKey(const ValueKey('profile-journey-cells')),
        cells ? findsOneWidget : findsNothing,
      );
      final rects = <Rect>[];
      for (final keyName in const [
        'communities',
        'messages',
        'voice-time',
        'rooms-created',
      ]) {
        final row = find.byKey(ValueKey('profile-journey-row-$keyName'));
        expect(row, findsOneWidget);
        final rect = tester.getRect(row);
        rects.add(rect);
        // A cell's label may take two lines on a narrow cell; a row never
        // grows past its 48 px.
        expect(rect.height, lessThanOrEqualTo(cells ? 64 : 48));
      }
      for (final rect in rects.skip(1)) {
        if (cells) {
          expect(rect.top, rects.first.top, reason: 'one line of cells');
          expect(rect.left, greaterThan(rects.first.left));
          expect(rect.width, moreOrLessEquals(rects.first.width, epsilon: 1));
        } else {
          expect(rect.top, greaterThan(rects.first.top), reason: 'rows');
        }
      }

      expect(
        cardRect.height,
        lessThanOrEqualTo(290),
        reason: 'wide layouts must not stretch list rows vertically',
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a wide card falls back to rows at 150% text', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(18),
              child: ProfileJourneyCard(
                communitiesCount: 3,
                messageCount: 42,
                voiceMinutes: 125,
                roomCount: 7,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-journey-cells')), findsNothing);
    final first = tester.getRect(
      find.byKey(const ValueKey('profile-journey-row-communities')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('profile-journey-row-rooms-created')),
    );
    expect(last.top, greaterThan(first.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cells keep the real value text and a long duration fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileJourneyCard(
              communitiesCount: 3,
              messageCount: 12345,
              voiceMinutes: 1265,
              roomCount: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-journey-cells')), findsOneWidget);
    // The value is one text run (its units drawn smaller), so the plain
    // string and the screen reader value stay exactly the formatted count.
    expect(find.text('21h 5m'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('profile-journey-row-voice-time')),
          )
          .getSemanticsData()
          .value,
      '21h 5m',
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('journey reflows without clipping at 200% text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ProfileJourneyCard(
                communitiesCount: 99,
                messageCount: 12345,
                voiceMinutes: 601,
                roomCount: 101,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Your YO Voice journey'), findsOneWidget);
    expect(find.text('Servers created'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
