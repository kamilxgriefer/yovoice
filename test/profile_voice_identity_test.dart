import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';

UserProfile _profile({
  String vibe = '',
  String bio = '',
  String website = '',
}) => UserProfile(
  uid: 'profile-vibe-test',
  email: 'vibe@yovoice.app',
  displayName: 'Vibe Tester',
  username: 'vibetester',
  statusMessage: vibe,
  bio: bio,
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: website,
  accountType: AccountType.personal,
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

Future<void> _pumpCard(
  WidgetTester tester,
  UserProfile profile, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF09050F),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ProfileVoiceIdentityCard(profile: profile),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a saved vibe as its own profile section', (
    tester,
  ) async {
    const vibe = 'Linkin Park · In the End · on repeat tonight';
    await _pumpCard(tester, _profile(vibe: vibe, bio: 'CEO.'));

    expect(find.byKey(const ValueKey('profile-vibe')), findsOneWidget);
    expect(find.text('VIBE'), findsOneWidget);
    expect(find.text(vibe), findsOneWidget);
    expect(find.text('CEO.'), findsOneWidget);
    expect(
      find.text('Add your vibe, bio or languages so people know you.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('vibe alone is a complete identity and remains visible at 200%', (
    tester,
  ) async {
    const longVibe =
        'Linkin Park - In the End https://youtu.be/eVTXPUF4Oz4 playing on repeat tonight!';
    expect(longVibe.length, 80, reason: 'exercise the editor field limit');
    await _pumpCard(tester, _profile(vibe: longVibe), width: 320, textScale: 2);

    expect(
      find.text('Linkin Park - In the End playing on repeat tonight!'),
      findsOneWidget,
    );
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('youtu.be'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-vibe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long website alone stays bounded at 320px and 200%', (
    tester,
  ) async {
    const website =
        'https://yovoice.app/creators/a-very-long-profile-address-that-must-not-overflow';
    await _pumpCard(
      tester,
      _profile(website: website),
      width: 320,
      textScale: 2,
    );

    expect(find.text(website), findsOneWidget);
    expect(
      find.text('Add your vibe, bio or languages so people know you.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
