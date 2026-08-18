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

  testWidgets(
    'foreground notification stays above a scaled voice-room control dock',
    (tester) async {
      const size = Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      const dockKey = ValueKey('scaled-room-control-dock');
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 160,
                  child: ColoredBox(key: dockKey, color: Color(0xFF120A19)),
                ),
              ],
            ),
          ),
        ),
      );
      messengerKey.currentState!.showSnackBar(
        buildForegroundNotificationBanner(
          title: 'Achievement unlocked: Room Opener',
          body: 'Tap to open YO Voice',
          type: NotificationType.achievementUnlocked,
          targetId: 'room-opener',
          actorId: null,
          bottomClearance: foregroundNotificationBottomClearance(
            const TextScaler.linear(2),
          ),
        ),
      );
      await tester.pump();

      final dockRect = tester.getRect(find.byKey(dockKey));
      final titleRect = tester.getRect(
        find.text('Achievement unlocked: Room Opener'),
      );
      final toastRect = tester.getRect(
        find.byKey(const ValueKey('achievement-toast')),
      );
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.margin, const EdgeInsets.fromLTRB(12, 12, 12, 176));
      expect(snackBar.duration, const Duration(seconds: 2));
      expect(toastRect.width, lessThanOrEqualTo(380));
      expect(find.text('Tap to open YO Voice'), findsNothing);
      expect(find.text('Open'), findsNothing);
      expect(titleRect.overlaps(dockRect), isFalse);
      expect(toastRect.overlaps(dockRect), isFalse);
      expect(titleRect.bottom, lessThanOrEqualTo(dockRect.top));
      expect(toastRect.bottom, lessThanOrEqualTo(dockRect.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('achievement toast disappears after two seconds', (tester) async {
    const size = Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    messengerKey.currentState!.showSnackBar(
      buildForegroundNotificationBanner(
        title: 'Achievement unlocked: First Word',
        body: 'Tap to open YO Voice',
        type: NotificationType.achievementUnlocked,
        targetId: 'first-word',
        actorId: null,
      ),
    );
    await tester.pumpAndSettle();

    final toast = find.byKey(const ValueKey('achievement-toast'));
    expect(toast, findsOneWidget);
    expect(tester.getSize(toast).width, lessThanOrEqualTo(380));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(toast, findsNothing);
  });
}
