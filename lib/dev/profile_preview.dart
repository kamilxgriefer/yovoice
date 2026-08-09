// Developer-only harness for the profile surfaces.
//
// Renders EditProfileScreen and the Profile header with a fake, local
// UserProfile so their layout can be inspected at arbitrary widths
// without a signed-in Firebase session. Exists because the desktop
// banner-proportion bug shipped unseen: nothing in the repo could show
// these screens at 1440px without logging in.
//
// Run with:
//   flutter run -d web-server -t lib/dev/profile_preview.dart
//
// Not referenced by lib/main.dart; never part of a shipped build.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same rationale as new_message_preview.dart: the web plugin registrant
  // registers Firebase plugins unconditionally; the preview itself never
  // signs in or talks to a backend.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Preview: continuing without Firebase ($error)');
  }
  runApp(const _PreviewApp());
}

UserProfile get _fakeProfile => UserProfile(
  uid: 'preview',
  email: 'ada@yovoice.app',
  displayName: 'Ada Lovelace',
  username: 'ada',
  bio: 'Hosting late-night rooms about synths, space and stories.',
  country: 'Poland',
  nativeLanguage: 'Polish',
  spokenLanguages: const ['Polish', 'English'],
  learningLanguages: const ['Spanish'],
  photoUrl: null,
  bannerUrl: null,
  website: 'https://yovoice.app',
  accountType: AccountType.creator,
  premiumIdentity: true,
  friendCount: 12,
  followerCount: 340,
  followingCount: 51,
  roomCount: 4,
  communityCount: 2,
  voiceMinutes: 1240,
  messageCount: 210,
  activeDays: 33,
  momentCount: 9,
  reactionCount: 87,
  hostMinutes: 300,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026, 1, 1),
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF09050F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF09050F),
          title: const Text('Profile preview'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Header'),
              Tab(text: 'Edit profile'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              children: [
                ProfileHeader(profile: _fakeProfile, onEdit: () {}),
                const SizedBox(height: 400),
              ],
            ),
            EditProfileScreen(profile: _fakeProfile),
          ],
        ),
      ),
    );
  }
}
