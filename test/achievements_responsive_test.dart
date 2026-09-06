import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

UserProfile _profile() => UserProfile(
  uid: 'member',
  email: 'member@yovoice.app',
  displayName: 'Member',
  username: 'member',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 7,
  followerCount: 12,
  followingCount: 4,
  roomCount: 2,
  communityCount: 1,
  voiceMinutes: 145,
  messageCount: 42,
  activeDays: 5,
  momentCount: 3,
  reactionCount: 8,
  hostMinutes: 30,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

void main() {
  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(768, 1024),
    Size(1100, 800),
    Size(1440, 900),
  ]) {
    testWidgets('achievements reflows at ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            profile: _profile(),
            achievementService: AchievementService(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Categories'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pump();
      expect(find.text('First Word'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('achievements supports 200% text on the narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AchievementsScreen(
            profile: _profile(),
            achievementService: AchievementService(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // At 200% text on a 320 px phone the selected-title hero, level card and
    // stats row legitimately fill the first screen, so the category filter is
    // reached by scrolling. What must hold is that it exists, is reachable,
    // and nothing overflows on the way.
    await tester.scrollUntilVisible(
      find.text('Categories'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Categories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
