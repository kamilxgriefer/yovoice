import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_visibility_service.dart';
import 'package:yovoice/features/settings/presentation/screens/profile_visibility_screen.dart';

void main() {
  test('legacy and canonical visibility values decode safely', () async {
    expect(ProfileVisibility.fromValue(null), ProfileVisibility.public);
    expect(ProfileVisibility.fromValue('public'), ProfileVisibility.public);
    expect(ProfileVisibility.fromValue('friends'), ProfileVisibility.friends);
    expect(ProfileVisibility.fromValue('private'), ProfileVisibility.private);
    expect(ProfileVisibility.fromValue('future'), ProfileVisibility.private);

    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('legacy').set({'displayName': 'Legacy'});
    await db.collection('users').doc('private').set({
      'displayName': 'Private',
      'profileVisibility': 'private',
    });
    expect(
      UserProfile.fromFirestore(
        await db.collection('users').doc('legacy').get(),
      ).profileVisibility,
      ProfileVisibility.public,
    );
    expect(
      UserProfile.fromFirestore(
        await db.collection('users').doc('private').get(),
      ).profileVisibility,
      ProfileVisibility.private,
    );
  });

  test('service sends an exact enum and validates the response', () async {
    Map<String, dynamic>? sent;
    final service = ProfileVisibilityService(
      mutationInvoker: (data) async {
        sent = data;
        return {'visibility': 'friends', 'changed': true};
      },
    );

    expect(
      await service.setVisibility(ProfileVisibility.friends),
      ProfileVisibility.friends,
    );
    expect(sent, {'visibility': 'friends'});

    for (final response in <Map<String, dynamic>>[
      {'visibility': 'friends'},
      {'visibility': 'future', 'changed': true},
      {'visibility': 'friends', 'changed': 'yes'},
      {'visibility': 'friends', 'changed': true, 'extra': true},
    ]) {
      final invalid = ProfileVisibilityService(
        mutationInvoker: (_) async => response,
      );
      expect(
        () => invalid.setVisibility(ProfileVisibility.friends),
        throwsA(isA<ProfileVisibilityException>()),
      );
    }
  });

  testWidgets('screen stays bounded from 320 to 1440 and at 200% text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = ProfileVisibilityService(
      mutationInvoker: (data) async => {
        'visibility': data['visibility'],
        'changed': true,
      },
    );

    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(768, 1024),
      Size(1100, 800),
      Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ProfileVisibilityScreen(
              key: ValueKey(size.width),
              initialVisibility: ProfileVisibility.public,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = tester.getRect(
        find.byKey(const ValueKey('profile-visibility-content')),
      );
      expect(frame.width, lessThanOrEqualTo(880));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppPalette.light.background,
      );
      expect(tester.takeException(), isNull, reason: '$size at 200%');
    }
  });

  testWidgets('selection is server-confirmed and exposes accessible options', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final service = ProfileVisibilityService(
      mutationInvoker: (data) async {
        calls.add(data);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return {'visibility': data['visibility'], 'changed': true};
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileVisibilityScreen(
          initialVisibility: ProfileVisibility.public,
          service: service,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('profile-visibility-friends')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(calls, [
      {'visibility': 'friends'},
    ]);
    expect(
      find.text('Profile visibility set to Friends only.'),
      findsOneWidget,
    );
  });
}
