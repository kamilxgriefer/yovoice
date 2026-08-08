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
import 'package:yovoice/firebase_options.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

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
            _HeaderPreview(profile: _fakeProfile),
            EditProfileScreen(profile: _fakeProfile),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the Profile screen's responsive header composition (the real
/// _ProfileHero is private to profile_screen.dart and is driven by live
/// streams; this reproduces its banner geometry 1:1 for layout checks).
class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final scrim = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .05),
                const Color(0xFF09050F),
              ],
            );

            return SizedBox(
              height: isWide ? 300 : 320,
              child: Stack(
                children: [
                  if (isWide)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: ProfileBanner(
                                bannerUrl: profile.bannerUrl,
                                overlay: scrim,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: ProfileBanner(
                        bannerUrl: profile.bannerUrl,
                        overlay: scrim,
                      ),
                    ),
                  Positioned(
                    left: 40,
                    bottom: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
                            ),
                          ),
                          child: UserAvatar(
                            radius: 55,
                            photoUrl: profile.photoUrl,
                            displayName: profile.displayName,
                            backgroundColor: const Color(0xFF281133),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          profile.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 400),
      ],
    );
  }
}
