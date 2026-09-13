import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_created_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_invite_response_screen.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';

void main() {
  const sizes = <Size>[
    Size(320, 568),
    Size(390, 844),
    Size(768, 1024),
    Size(1100, 800),
    Size(1440, 900),
  ];

  Widget host(Widget child, {double textScale = 1}) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    );
  }

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const club = Club(
    id: 'club-1',
    name: 'The longest multilingual creator community in YO Voice',
    description: 'A real community.',
    ownerId: 'owner',
    ownerName: 'Owner',
    avatarUrl: null,
    bannerUrl: null,
    privacy: ClubPrivacy.inviteOnly,
    defaultLanguage: 'Polish and English',
    memberCount: 1,
    onlineCount: 1,
    defaultChatChannelId: 'general',
    defaultVoiceChannelId: 'lounge',
    announcementChannelId: 'announcements',
    createdAt: null,
    updatedAt: null,
  );
  const family = Club(
    id: 'family-owner',
    name: 'Our Family',
    description: 'Our private home.',
    ownerId: 'owner',
    ownerName: 'Owner',
    avatarUrl: null,
    bannerUrl: null,
    privacy: ClubPrivacy.inviteOnly,
    defaultLanguage: 'Polish',
    memberCount: 1,
    onlineCount: 1,
    defaultChatChannelId: 'general',
    defaultVoiceChannelId: 'lounge',
    announcementChannelId: 'announcements',
    createdAt: null,
    updatedAt: null,
    type: ClubType.family,
  );

  group('Club created responsive composition', () {
    for (final size in sizes) {
      testWidgets('renders without overflow at ${size.width.toInt()} px', (
        tester,
      ) async {
        useSurface(tester, size);
        await tester.pumpWidget(host(const ClubCreatedScreen(club: club)));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Your Club is ready'), findsOneWidget);
        expect(
          tester.getSize(find.widgetWithText(FilledButton, 'Open Club')).width,
          lessThanOrEqualTo(560),
        );
      });
    }

    testWidgets(
      'scrolls instead of overflowing at 320 px and 200 percent text',
      (tester) async {
        useSurface(tester, const Size(320, 568));
        await tester.pumpWidget(
          host(const ClubCreatedScreen(club: club), textScale: 2),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Open Club'),
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Open Club'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('uses Family copy, identity and a direct open action', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(host(const ClubCreatedScreen(club: family)));
      await tester.pump();

      expect(find.text('Your Family Room is ready'), findsOneWidget);
      expect(find.textContaining('Family Lounge'), findsOneWidget);
      expect(find.textContaining('Organizer'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Open Family Room'),
        findsOneWidget,
      );
      expect(find.text('Your Club is ready'), findsNothing);
      expect(find.textContaining('Stage 6.3'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Club invitation is compact and stacks actions for large text', (
    tester,
  ) async {
    useSurface(tester, const Size(320, 568));
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'invitee', email: 'invitee@yovoice.app'),
    );
    await firestore
        .collection('clubs')
        .doc('club-1')
        .collection('invites')
        .doc('invitee')
        .set({
          'clubId': 'club-1',
          'clubName': 'A community with a deliberately long name',
          'inviteeId': 'invitee',
          'inviterId': 'owner',
          'inviterName': 'A creator with a deliberately long name',
          'status': 'pending',
        });
    final service = ClubService(
      firestore: firestore,
      auth: auth,
      storage: MockFirebaseStorage(),
      notificationService: NotificationService(
        firestore: firestore,
        auth: auth,
      ),
    );

    await tester.pumpWidget(
      host(
        ClubInviteResponseScreen(
          clubId: 'club-1',
          firestore: firestore,
          auth: auth,
          clubService: service,
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final accept = tester.getTopLeft(
      find.byKey(const ValueKey('accept-club-invite')),
    );
    final decline = tester.getTopLeft(
      find.byKey(const ValueKey('decline-club-invite')),
    );
    expect(accept.dy, lessThan(decline.dy));
  });

  testWidgets('blocked-user rows reflow safely at 320 px and large text', (
    tester,
  ) async {
    useSurface(tester, const Size(320, 568));
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
    );
    await firestore.collection('users').doc('me').set({'uid': 'me'});
    await firestore.collection('users').doc('blocked-user').set({
      'uid': 'blocked-user',
      'displayName': 'A blocked person with a deliberately long name',
      'email': 'blocked@yovoice.app',
    });
    // Foreign identity is intentionally served from the server-owned public
    // projection. Keeping this fixture on the private users document would
    // mask the production privacy boundary and render the honest empty state.
    await firestore.collection('publicProfiles').doc('blocked-user').set({
      'uid': 'blocked-user',
      'displayName': 'A blocked person with a deliberately long name',
      'username': 'blocked-person',
      'photoUrl': null,
      'premiumIdentity': false,
    });
    await firestore
        .collection('users')
        .doc('me')
        .collection('blocked')
        .doc('blocked-user')
        .set({'blockedAt': Timestamp.now()});
    final service = FriendService(
      firestore: firestore,
      auth: auth,
      notificationService: NotificationService(
        firestore: firestore,
        auth: auth,
      ),
    );

    await tester.pumpWidget(
      host(BlockedUsersScreen(friendService: service), textScale: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unblock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('follow rows wrap long identity copy at 320 px and large text', (
    tester,
  ) async {
    useSurface(tester, const Size(320, 568));
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
    );
    await firestore
        .collection('users')
        .doc('me')
        .collection('followers')
        .doc('follower')
        .set({
          'uid': 'follower',
          'displayName': 'A follower with a deliberately long display name',
          'username': 'a_deliberately_long_username_for_zoom',
          'followedAt': Timestamp.now(),
        });

    await tester.pumpWidget(
      host(
        FollowListScreen(
          userId: 'me',
          type: FollowListType.followers,
          service: FollowService(firestore: firestore, auth: auth),
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('A follower'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room settings remain a scrollable 720 px form at zoom', (
    tester,
  ) async {
    useSurface(tester, const Size(320, 568));
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'host', email: 'host@yovoice.app'),
    );
    const room = VoiceRoom(
      id: 'room-1',
      hostId: 'host',
      hostName: 'Host',
      hostPhotoUrl: null,
      name: 'A room with a deliberately long title',
      description: 'A detailed description of this room.',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 50,
      participantCount: 1,
      memberCount: 1,
      isLive: false,
      roomType: RoomType.community,
      status: RoomStatus.active,
      imageUrl: null,
      approvalRequired: true,
      slowModeSeconds: 10,
      autoMuteNewUsers: true,
      membersCanStartVoice: false,
      createdAt: null,
      updatedAt: null,
    );

    await tester.pumpWidget(
      host(
        RoomSettingsScreen(
          room: room,
          roomService: RoomService(firestore: firestore, auth: auth),
          roomImageService: RoomImageService(
            storage: MockFirebaseStorage(),
            auth: auth,
          ),
        ),
        textScale: 2,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    for (var attempt = 0; attempt < 3; attempt += 1) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }
    expect(find.text('Delete room'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
