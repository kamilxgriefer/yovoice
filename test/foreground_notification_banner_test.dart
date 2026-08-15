import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/app/app.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';

void main() {
  for (final size in const [Size(320, 640), Size(390, 844), Size(430, 932)]) {
    testWidgets('foreground notification banner fits ${size.width}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      messengerKey.currentState!.showSnackBar(
        buildForegroundNotificationBanner(
          title: 'Alex sent you a message with a deliberately long title',
          body: 'Tap to open YO Voice and see the full conversation.',
          type: NotificationType.directMessage,
          targetId: 'conversation-1',
          actorId: 'alex',
        ),
      );
      await tester.pump();

      expect(find.text('Open'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
