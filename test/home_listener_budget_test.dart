import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// Home reads a lot of the account's world. This pins how MUCH.
///
/// The budget is not an optimisation: an unbounded fan-out of Firestore
/// listeners for decoration is what turns a browsing screen into a cost and a
/// battery drain, and a rebuild that re-subscribes is what makes a tab switch
/// blank the page. Every number here is a contract.
class _CountingRooms extends RoomService {
  _CountingRooms({required super.firestore, required super.auth});

  int live = 0;
  int owned = 0;
  int lounges = 0;
  int participants = 0;
  final Set<String> loungeIds = {};
  final Set<String> participantRoomIds = {};

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    live++;
    return const Stream<List<VoiceRoom>>.empty();
  }

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() {
    owned++;
    return const Stream<List<VoiceRoom>>.empty();
  }

  @override
  Stream<VoiceRoom?> watchClubLounge(String clubId) {
    lounges++;
    loungeIds.add(clubId);
    return const Stream<VoiceRoom?>.empty();
  }

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    participants++;
    participantRoomIds.add(roomId);
    return const Stream<List<RoomParticipant>>.empty();
  }
}

class _CountingFriends extends FriendService {
  _CountingFriends({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<FriendUser>> watchFriends() {
    calls++;
    return const Stream<List<FriendUser>>.empty();
  }
}

class _CountingFollow extends FollowService {
  _CountingFollow({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) {
    calls++;
    return const Stream<List<FollowUser>>.empty();
  }
}

class _CountingMessages extends MessageService {
  _CountingMessages({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    calls++;
    return const Stream<List<Conversation>>.empty();
  }
}

class _CountingFeed extends HomeFeedService {
  _CountingFeed({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    calls++;
    return const Stream<List<VoiceMoment>>.empty();
  }
}

class _CountingViews extends MomentViewsService {
  _CountingViews({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<Set<String>> watchViewedMomentIds() {
    calls++;
    return const Stream<Set<String>>.empty();
  }
}

class _CountingClubs extends ClubService {
  _CountingClubs({
    required super.firestore,
    required super.auth,
    required super.storage,
  });
  int calls = 0;
  List<Club> clubs = const [];
  @override
  Stream<List<Club>> watchMyClubs() {
    calls++;
    return Stream<List<Club>>.value(clubs);
  }
}

class _Capabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Club _club(String id) => Club(
  id: id,
  name: 'Miejsce $id',
  description: '',
  ownerId: 'owner',
  ownerName: 'Owner',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.private,
  defaultLanguage: 'Polish',
  memberCount: 4,
  onlineCount: 0,
  defaultChatChannelId: '',
  defaultVoiceChannelId: '',
  announcementChannelId: '',
  createdAt: null,
  updatedAt: null,
);

void main() {
  const uid = 'budget-me';
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  testWidgets('one listener per source, and at most four rosters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rooms = _CountingRooms(firestore: db, auth: auth);
    final friends = _CountingFriends(firestore: db, auth: auth);
    final follow = _CountingFollow(firestore: db, auth: auth);
    final messages = _CountingMessages(firestore: db, auth: auth);
    final feed = _CountingFeed(firestore: db, auth: auth);
    final views = _CountingViews(firestore: db, auth: auth);
    final clubs = _CountingClubs(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
    )..clubs = [for (var i = 0; i < 7; i++) _club('c$i')];
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    Widget home() => MaterialApp(
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: MobileHome(
          key: const ValueKey('budget-home'),
          currentUserId: uid,
          onOpenRoom: (_) {},
          onOpenDiscover: () {},
          onOpenFriends: () {},
          onOpenNotifications: () {},
          onOpenProfile: () {},
          onCreateMoment: () {},
          onCreateRoom: () {},
          onOpenMoment: (_) {},
          onOpenComments: (_) {},
          onOpenConversation: (_) {},
          onSeeAllChats: () {},
          roomService: rooms,
          clubService: clubs,
          friendService: friends,
          followService: follow,
          profileService: ProfileService(firestore: db, auth: auth),
          feedService: feed,
          messageService: messages,
          momentViewsService: views,
          capabilityService: _Capabilities(),
          isVisible: visible,
        ),
      ),
    );

    await tester.pumpWidget(home());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(rooms.live, 1, reason: 'watchLivePublicRooms');
    expect(rooms.owned, 1, reason: 'watchOwnedRooms');
    expect(friends.calls, 1, reason: 'watchFriends');
    expect(follow.calls, 1, reason: 'watchFollowing');
    expect(messages.calls, 1, reason: 'watchConversations');
    expect(feed.calls, 1, reason: 'watchSocialMoments');
    expect(views.calls, 1, reason: 'momentViews');
    expect(clubs.calls, 1, reason: 'watchMyClubs');
    // Seven memberships, four lounge listeners: Home shows at most three
    // live rows, so a fourth is the most the hero can add.
    expect(rooms.loungeIds, hasLength(4), reason: 'watchClubLounge');
    expect(
      rooms.participantRoomIds.length,
      lessThanOrEqualTo(4),
      reason: 'watchParticipants',
    );

    // A rebuild of the same tree must not re-subscribe anything.
    await tester.pumpWidget(home());
    await tester.pump(const Duration(milliseconds: 60));
    expect(rooms.live, 1);
    expect(rooms.owned, 1);
    expect(friends.calls, 1);
    expect(follow.calls, 1);
    expect(messages.calls, 1);
    expect(clubs.calls, 1);
    expect(rooms.loungeIds, hasLength(4));

    // Returning to the retained Home refreshes the one-shot Moments page and
    // nothing else: the Firestore listeners stay exactly as they were.
    final feedReads = feed.calls;
    visible.value = false;
    await tester.pump(const Duration(milliseconds: 60));
    visible.value = true;
    await tester.pump(const Duration(milliseconds: 60));
    expect(feed.calls, feedReads + 1);
    expect(rooms.live, 1);
    expect(clubs.calls, 1);
    expect(rooms.loungeIds, hasLength(4));
    expect(views.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening Home never joins audio and never writes a roster row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await db.collection('rooms').doc('r1').set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'Evening Talks',
      'description': '',
      'category': 'community',
      'visibility': 'public',
      'language': 'Polish',
      'participantCount': 2,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.now(),
    });
    final writes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MobileHome(
            currentUserId: uid,
            onOpenRoom: (_) => writes.add('open'),
            onOpenDiscover: () {},
            onOpenFriends: () {},
            onOpenNotifications: () {},
            onOpenProfile: () {},
            onCreateMoment: () {},
            onCreateRoom: () {},
            onOpenMoment: (_) {},
            onOpenComments: (_) {},
            onOpenConversation: (_) {},
            onSeeAllChats: () {},
            roomService: RoomService(firestore: db, auth: auth),
            clubService: _CountingClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
            ),
            friendService: FriendService(firestore: db, auth: auth),
            followService: FollowService(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            feedService: _CountingFeed(firestore: db, auth: auth),
            messageService: MessageService(firestore: db, auth: auth),
            momentViewsService: _CountingViews(firestore: db, auth: auth),
            capabilityService: _Capabilities(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Merely rendering Home resolves a featured room and its roster — and
    // writes nothing: no participant document, no voice session.
    final participants = await db
        .collection('rooms')
        .doc('r1')
        .collection('participants')
        .get();
    expect(participants.docs, isEmpty);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
