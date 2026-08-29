import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/data/services/creator_directory_service.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_posts_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

VoiceRoom _room() => VoiceRoom(
  id: 'room',
  hostId: 'owner',
  hostName: 'Owner',
  hostPhotoUrl: null,
  name: 'Dark island',
  description: 'A deliberately immersive room.',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 25,
  participantCount: 1,
  memberCount: 1,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

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

VoiceMoment _moment() => VoiceMoment(
  id: 'moment',
  authorId: 'member',
  authorName: 'Member',
  authorPhotoUrl: null,
  caption: 'Pinned story',
  audioUrl: 'https://example.invalid/moment.m4a',
  durationSeconds: 12,
  likeCount: 0,
  commentCount: 0,
  isPublished: true,
  createdAt: DateTime(2026),
  schemaVersion: 2,
  status: 'published',
);

class _NoStaffCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Future<void> _expectImmersiveDarkRoute(
  WidgetTester tester,
  Widget route,
) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: route));
  await tester.pump();

  final island = find.byType(YoImmersiveDarkSurface);
  expect(island, findsOneWidget);
  final scaffoldContext = tester.element(find.byType(Scaffold).first);
  expect(Theme.of(scaffoldContext).brightness, Brightness.dark);
  expect(scaffoldContext.appPalette.background, AppPalette.dark.background);

  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find
        .descendant(
          of: island,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .first,
  );
  expect(region.value.statusBarIconBrightness, Brightness.light);
  expect(region.value.systemNavigationBarColor, AppPalette.dark.background);
  expect(region.value.systemNavigationBarIconBrightness, Brightness.light);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('Room type selector is an immersive dark route from Pearl', (
    tester,
  ) async {
    await _expectImmersiveDarkRoute(tester, const RoomTypeSelectorScreen());
  });

  testWidgets('Create room is an immersive dark route from Pearl', (
    tester,
  ) async {
    await _expectImmersiveDarkRoute(tester, const CreateRoomScreen());
  });

  testWidgets('Room settings is an immersive dark route from Pearl', (
    tester,
  ) async {
    await _expectImmersiveDarkRoute(tester, RoomSettingsScreen(room: _room()));
  });

  testWidgets('Achievements is an immersive dark route from Pearl', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);
    await _expectImmersiveDarkRoute(
      tester,
      AchievementsScreen(
        profile: _profile(),
        achievementService: AchievementService(firestore: db, auth: auth),
      ),
    );
  });

  testWidgets('Find creators is an immersive dark route from Pearl', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);
    await _expectImmersiveDarkRoute(
      tester,
      FindCreatorsScreen(
        isRootTab: true,
        directoryService: CreatorDirectoryService(
          searchInvoker: (_) async => const {'profiles': <dynamic>[]},
        ),
        followService: FollowService(
          firestore: db,
          auth: auth,
          mutationInvoker: (_) async => const {},
        ),
      ),
    );
  });

  testWidgets('Creator Studio is an immersive dark route from Pearl', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'member'),
    );
    final storage = MockFirebaseStorage();
    await _expectImmersiveDarkRoute(
      tester,
      CreatorStudioScreen(
        profileService: ProfileService(
          firestore: db,
          auth: auth,
          storage: storage,
        ),
        roomService: RoomService(firestore: db, auth: auth),
        clubService: ClubService(firestore: db, auth: auth, storage: storage),
        momentService: MomentService(
          firestore: db,
          auth: auth,
          storage: storage,
        ),
      ),
    );
  });

  testWidgets('Pinned Moment is an immersive dark route from Pearl', (
    tester,
  ) async {
    await _expectImmersiveDarkRoute(
      tester,
      CreatorPinnedMomentScreen(moment: _moment()),
    );
  });

  testWidgets('Pinned posts are an immersive dark route from Pearl', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'member'),
    );
    await _expectImmersiveDarkRoute(
      tester,
      CreatorPinnedPostsScreen(
        pinnedPostService: CreatorPinnedPostService(firestore: db, auth: auth),
        momentService: MomentService(
          firestore: db,
          auth: auth,
          storage: MockFirebaseStorage(),
        ),
      ),
    );
  });

  testWidgets('Staff Center is an immersive dark route from Pearl', (
    tester,
  ) async {
    await _expectImmersiveDarkRoute(
      tester,
      StaffCenterScreen(
        capabilityService: _NoStaffCapabilities(),
        currentUid: 'member',
      ),
    );
  });
}
