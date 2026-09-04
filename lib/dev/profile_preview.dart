// Developer-only harness for the profile surfaces.
// ignore_for_file: depend_on_referenced_packages
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
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';
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

UserProfile _fakeProfile({
  AccountType accountType = AccountType.creator,
  bool premiumIdentity = true,
}) => UserProfile(
  uid: 'preview',
  email: 'ada@yovoice.app',
  displayName: 'Ada Lovelace',
  username: 'ada',
  statusMessage: 'Synthwave after midnight · building a room for storytellers',
  bio: 'Hosting late-night rooms about synths, space and stories.',
  country: 'Poland',
  nativeLanguage: 'Polish',
  spokenLanguages: const ['Polish', 'English'],
  learningLanguages: const ['Spanish'],
  photoUrl: null,
  bannerUrl: null,
  website: 'https://yovoice.app',
  accountType: accountType,
  premiumIdentity: premiumIdentity,
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
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFF09050F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF09050F),
          title: const Text('Profile preview'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Header'),
              Tab(text: 'Journey'),
              Tab(text: 'Edit profile'),
              Tab(text: 'Full friend'),
              Tab(text: 'Premium locks'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              children: [
                ProfileHeader(profile: _fakeProfile(), onEdit: () {}),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: ProfileVoiceIdentityCard(profile: _fakeProfile()),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(18),
              children: [
                ProfileJourneyCard(
                  communitiesCount: _fakeProfile().communityCount,
                  messageCount: _fakeProfile().messageCount,
                  voiceMinutes: _fakeProfile().voiceMinutes,
                  roomCount: _fakeProfile().roomCount,
                ),
              ],
            ),
            EditProfileScreen(
              profile: _fakeProfile(
                accountType: AccountType.personal,
                premiumIdentity: false,
              ),
            ),
            const _FriendProfilePreview(),
            const _PremiumLocksPreview(),
          ],
        ),
      ),
    );
  }
}

class _FriendProfilePreview extends StatefulWidget {
  const _FriendProfilePreview();

  @override
  State<_FriendProfilePreview> createState() => _FriendProfilePreviewState();
}

class _FriendProfilePreviewState extends State<_FriendProfilePreview> {
  late final Future<Widget> _screen = _buildScreen();

  Future<Widget> _buildScreen() async {
    const currentUid = 'preview-current';
    const friendUid = 'preview-friend';
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: currentUid, email: 'current@yovoice.app'),
    );
    await firestore.collection('users').doc(currentUid).set({
      'uid': currentUid,
      'displayName': 'Preview account',
      'email': 'current@yovoice.app',
    });
    await firestore.collection('publicProfiles').doc(friendUid).set({
      'uid': friendUid,
      'displayName': 'Alexandra Voice',
      'username': 'alexandra',
      'statusMessage':
          'Linkin Park - In the End · open mic and late-night stories',
      'bio': 'Hosting warm, curious conversations after midnight.',
      'nativeLanguage': 'Polish',
      'spokenLanguages': ['English'],
      'learningLanguages': ['Japanese'],
      'friendCount': 42,
      'followerCount': 128,
      'followingCount': 73,
      'accountType': 'personal',
    });
    await firestore.collection('socialPresence').doc(friendUid).set({
      'uid': friendUid,
      'isOnline': true,
    });

    final notifications = NotificationService(firestore: firestore, auth: auth);
    return FriendProfileScreen(
      friend: const FriendUser(
        id: friendUid,
        displayName: 'Alexandra Voice',
        email: 'alexandra@yovoice.app',
        photoUrl: null,
        isOnline: true,
        lastSeen: null,
      ),
      firestore: firestore,
      auth: auth,
      friendService: FriendService(
        firestore: firestore,
        auth: auth,
        notificationService: notifications,
      ),
      messageService: MessageService(
        firestore: firestore,
        auth: auth,
        notificationService: notifications,
      ),
      profileService: ProfileService(firestore: firestore, auth: auth),
      followService: FollowService(firestore: firestore, auth: auth),
      socialGraphService: _PreviewSocialGraphService(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _screen,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Friend preview failed: ${snapshot.error}'),
          );
        }
        return snapshot.data ??
            const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class _PreviewSocialGraphService implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PremiumLocksPreview extends StatelessWidget {
  const _PremiumLocksPreview();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return const Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(child: MoreSheet()),
          );
        }

        return Center(
          child: FilledButton.icon(
            key: const ValueKey('open-desktop-premium-locks'),
            onPressed: () async {
              await showDesktopMoreMenu(context, anchor: const Offset(72, 160));
            },
            icon: const Icon(Icons.more_horiz_rounded),
            label: const Text('Open desktop More'),
          ),
        );
      },
    );
  }
}
