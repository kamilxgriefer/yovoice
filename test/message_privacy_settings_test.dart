import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/settings/data/models/message_privacy.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/message_privacy_screen.dart';
import 'package:yovoice/features/settings/presentation/widgets/message_privacy_settings_tile.dart';

const _uid = 'message-privacy-owner';

Future<({FakeFirebaseFirestore firestore, MessagePrivacyService service})>
_fixture({Object? stored = 'absent'}) async {
  final firestore = FakeFirebaseFirestore();
  final data = <String, Object?>{'uid': _uid, 'displayName': 'Privacy owner'};
  if (stored != 'absent') data['messagePrivacy'] = stored;
  await firestore.collection('users').doc(_uid).set(data);
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _uid, email: 'privacy@yovoice.app'),
  );
  return (
    firestore: firestore,
    service: MessagePrivacyService(firestore: firestore, auth: auth),
  );
}

void main() {
  test('missing defaults to everyone while unknown values fail closed', () {
    expect(
      MessagePrivacyOption.fromStoredValue(null),
      MessagePrivacyOption.everyone,
    );
    expect(
      MessagePrivacyOption.fromStoredValue('future-mode'),
      MessagePrivacyOption.nobody,
    );
    expect(
      MessagePrivacyOption.fromStoredValue('peopleYouFollow'),
      MessagePrivacyOption.peopleYouFollow,
    );
  });

  test('service watches and persists the exact storage enum', () async {
    final fixture = await _fixture();
    expect(
      await fixture.service.watchCurrent().first,
      MessagePrivacyOption.everyone,
    );
    await fixture.service.setCurrent(MessagePrivacyOption.friends);
    expect(
      (await fixture.firestore.collection('users').doc(_uid).get())
          .data()?['messagePrivacy'],
      'friends',
    );
    expect(
      await fixture.service.watchCurrent().first,
      MessagePrivacyOption.friends,
    );
  });

  for (final size in [const Size(320, 700), const Size(1024, 820)]) {
    testWidgets('privacy screen is usable at ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _fixture();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MessagePrivacyScreen(service: fixture.service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose your inbox boundary'), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('People you follow'), findsOneWidget);
      expect(find.text('Friends only'), findsOneWidget);
      expect(find.text('Nobody'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('message-privacy-peopleYouFollow')),
      );
      await tester.pumpAndSettle();
      expect(
        (await fixture.firestore.collection('users').doc(_uid).get())
            .data()?['messagePrivacy'],
        'peopleYouFollow',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('drop-in Settings tile shows state and opens the real screen', (
    tester,
  ) async {
    final fixture = await _fixture(stored: 'friends');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: MessagePrivacySettingsTile(service: fixture.service),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Who can message you'), findsOneWidget);
    expect(find.text('Friends only'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('message-privacy-settings-tile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose your inbox boundary'), findsOneWidget);
  });
}
