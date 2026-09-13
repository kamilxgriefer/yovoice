import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';

void main() {
  testWidgets('Pearl preferences fit 320px at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'preferences-owner'),
    );
    await firestore.collection('users').doc('preferences-owner').set({
      'uid': 'preferences-owner',
      'notificationPreferences': {'directCall': false},
    });
    final service = NotificationService(firestore: firestore, auth: auth);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: NotificationPreferencesScreen(
            isRootTab: true,
            notificationService: service,
            creatorAudienceVisibleStream: Stream.value(false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppPalette.light.background,
    );
    expect(find.text('Notification preferences'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final label in const ['Friends', 'Servers', 'Calls', 'Messages']) {
      await tester.scrollUntilVisible(
        find.text(label),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('New followers'), findsNothing);
  });

  testWidgets(
    'new follower preference exists only for a visible Creator audience',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'creator-owner'),
      );
      await firestore.collection('users').doc('creator-owner').set({
        'uid': 'creator-owner',
        'notificationPreferences': <String, bool>{},
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: NotificationPreferencesScreen(
            isRootTab: true,
            notificationService: NotificationService(
              firestore: firestore,
              auth: auth,
            ),
            creatorAudienceVisibleStream: Stream.value(true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Friends & follows'), findsOneWidget);
      expect(find.text('New followers'), findsOneWidget);
    },
  );
}
