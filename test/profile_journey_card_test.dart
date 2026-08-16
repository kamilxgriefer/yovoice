import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';

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
      expect(find.text('Communities'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Voice time'), findsOneWidget);
      expect(find.text('Rooms created'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('2h 5m'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      final cardRect = tester.getRect(card);
      expect(cardRect.left, greaterThanOrEqualTo(0));
      expect(cardRect.right, lessThanOrEqualTo(size.width));
      expect(cardRect.width, lessThanOrEqualTo(720));
      for (final keyName in const [
        'communities',
        'messages',
        'voice-time',
        'rooms-created',
      ]) {
        final row = find.byKey(ValueKey('profile-journey-row-$keyName'));
        expect(row, findsOneWidget);
        expect(tester.getRect(row).height, lessThanOrEqualTo(48));
      }

      expect(
        cardRect.height,
        lessThanOrEqualTo(290),
        reason: 'wide layouts must not stretch list rows vertically',
      );

      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.text('Rooms created'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
