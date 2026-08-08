import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';

/// Regression suite for the production mobile bug where the avatar was
/// drawn above the top of the page: the header's inner Stack was returned
/// unpositioned on <900px widths, collapsed to the title row's height,
/// and the identity row's `bottom: 20` anchored to that collapsed box.
///
/// Runs the REAL ProfileHeader (the same widget profile_screen renders)
/// across the full device matrix and asserts the avatar rect sits fully
/// inside the header at every size.
UserProfile _profile({AccountType accountType = AccountType.creator}) {
  return UserProfile(
    uid: 'u1',
    email: 'ada@yovoice.app',
    displayName: 'Ada Lovelace',
    username: 'ada',
    bio: 'bio',
    country: '',
    nativeLanguage: '',
    spokenLanguages: const [],
    learningLanguages: const [],
    photoUrl: null,
    bannerUrl: null,
    website: '',
    accountType: accountType,
    friendCount: 0,
    followerCount: 0,
    followingCount: 0,
    roomCount: 0,
    communityCount: 0,
    voiceMinutes: 0,
    messageCount: 0,
    activeDays: 0,
    momentCount: 0,
    reactionCount: 0,
    hostMinutes: 0,
    selectedTitleId: null,
    unlockedTitleIds: const [],
    unlockedTitleTimestamps: const {},
    createdAt: DateTime(2026),
  );
}

// The user-reported device matrix plus tablet/desktop widths.
const sizes = <Size>[
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(393, 852),
  Size(430, 932),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];

void main() {
  for (final size in sizes) {
    testWidgets('avatar is fully visible inside the header at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [ProfileHeader(profile: _profile(), onEdit: () {})],
            ),
          ),
        ),
      );
      await tester.pump();

      final headerFinder = find.byType(ProfileHeader);
      final avatarFinder = find.byKey(const Key('profile-header-avatar'));
      expect(headerFinder, findsOneWidget);
      expect(avatarFinder, findsOneWidget);

      final headerRect = tester.getRect(headerFinder);
      final avatarRect = tester.getRect(avatarFinder);

      expect(
        avatarRect.top,
        greaterThanOrEqualTo(headerRect.top),
        reason:
            'avatar must not poke above the header (the clipped-avatar '
            'production bug)',
      );
      expect(avatarRect.bottom, lessThanOrEqualTo(headerRect.bottom));
      expect(avatarRect.left, greaterThanOrEqualTo(headerRect.left));
      expect(avatarRect.right, lessThanOrEqualTo(headerRect.right));

      // The avatar must sit in the LOWER portion of the header — being
      // technically inside but pinned near the top (the regression's
      // symptom) still fails.
      expect(
        avatarRect.center.dy,
        greaterThan(headerRect.top + headerRect.height / 2),
        reason: 'avatar belongs in the bottom half of the banner area',
      );

      // Header itself must be on-screen and full-width with no
      // horizontal overflow.
      expect(headerRect.width, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('name and username render next to the avatar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [ProfileHeader(profile: _profile(), onEdit: () {})],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
    expect(find.text('Creator'), findsOneWidget);

    // Both must be inside the header, below its top edge.
    final headerRect = tester.getRect(find.byType(ProfileHeader));
    final nameRect = tester.getRect(find.text('Ada Lovelace'));
    expect(nameRect.top, greaterThan(headerRect.top + 100));
  });
}
