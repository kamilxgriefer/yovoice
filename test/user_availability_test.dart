import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

void main() {
  test('availability parses tolerantly and round-trips its wire value', () {
    expect(UserAvailability.fromWire('busy'), UserAvailability.busy);
    expect(UserAvailability.fromWire('invisible'), UserAvailability.invisible);
    expect(UserAvailability.fromWire(null), UserAvailability.available);
    expect(UserAvailability.fromWire('party'), UserAvailability.available);
    for (final value in UserAvailability.values) {
      expect(UserAvailability.fromWire(value.wire), value);
    }
  });

  test('projected presence maps to one ring colour per state', () {
    expect(
      PeopleStatus.fromPresence(isOnline: true, availability: 'available'),
      PeopleStatus.online,
    );
    expect(
      PeopleStatus.fromPresence(isOnline: true, availability: null),
      PeopleStatus.online,
    );
    expect(
      PeopleStatus.fromPresence(isOnline: true, availability: 'away'),
      PeopleStatus.brb,
    );
    expect(
      PeopleStatus.fromPresence(isOnline: true, availability: 'busy'),
      PeopleStatus.busy,
    );
    // Offline always wins, whatever the projection says.
    expect(
      PeopleStatus.fromPresence(isOnline: false, availability: 'busy'),
      PeopleStatus.away,
    );
    expect(
      PeopleStatus.fromPresence(isOnline: true, availability: 'offline'),
      PeopleStatus.away,
    );
    expect(
      PeopleStatus.fromOwnAvailability(UserAvailability.invisible),
      PeopleStatus.away,
    );
  });

  test(
    'setAvailability merges the choice and heartbeats preserve it',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me'),
      );
      final service = PresenceService(auth: auth, firestore: db);
      await db.collection('users').doc('me').set({'displayName': 'Me'});

      await service.setAvailability(UserAvailability.busy);
      var data = (await db.collection('users').doc('me').get()).data()!;
      expect(data['availability'], 'busy');
      expect(data['displayName'], 'Me');
      expect(data['presenceUpdatedAt'], isA<Timestamp>());

      await service.setOnline();
      await service.setOfflineForUser('me');
      data = (await db.collection('users').doc('me').get()).data()!;
      expect(data['availability'], 'busy');
      expect(data['isOnline'], isFalse);
    },
  );

  testWidgets('the chip opens the picker and the choice is written', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me'),
    );
    final service = PresenceService(auth: auth, firestore: db);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(
            child: AvailabilityChip(
              availability: UserAvailability.available,
              presenceService: service,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Available'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('availability-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Your availability'), findsOneWidget);
    expect(find.text('Do not disturb'), findsOneWidget);
    expect(find.text('Invisible'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('availability-option-busy')));
    await tester.pumpAndSettle();
    final data = (await db.collection('users').doc('me').get()).data();
    expect(data?['availability'], 'busy');
    expect(tester.takeException(), isNull);
  });
}
