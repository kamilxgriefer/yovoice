// Developer-only harness for the DESKTOP Home surface, POPULATED.
//
// lib/dev/desktop_preview.dart can show the rail and the right column
// without a session, but Home's modules are all data-driven: with no
// signed-in user every one of them renders its empty state, so the real
// composition — Moments strip, live rooms, Featured, For you,
// Conversations, followed creators — could never actually be looked at
// before shipping. This harness fills that gap by wiring the production
// widgets to fake_cloud_firestore instead of a real project.
//
// It lives under test/ rather than lib/dev/ for one reason: the fakes are
// dev_dependencies and must never be importable from shipped code.
//
// Run with:
//   flutter run -d web-server -t test/desktop_home_preview.dart \
//     --web-hostname 127.0.0.1 --web-port 5609
//
// The DATA below is seeded, obviously fictional preview content — it
// exists so the layout can be judged at desktop widths. Nothing here is
// wired into the app; production Home reads only the real services.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

const String _uid = 'preview-me';

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  DateTime ago(Duration d) => DateTime.now().subtract(d);

  await db.collection('users').doc(_uid).set({
    'uid': _uid,
    'displayName': 'CeoGriefer',
    'username': 'ceogriefer',
    'email': 'preview@yovoice.app',
  });

  // ?empty=1 seeds nothing else: the brand-new account view, where every
  // module has to hold its own with an empty state instead of a gap.
  if (Uri.base.queryParameters['empty'] == '1') return db;

  Future<void> person(String id, String name, {bool online = false}) =>
      db.collection('users').doc(id).set({
        'uid': id,
        'displayName': name,
        'username': name.toLowerCase().replaceAll(' ', ''),
        'email': '$id@yovoice.app',
        'isOnline': online,
      });

  Future<void> friend(String id) => db
      .collection('users')
      .doc(_uid)
      .collection('friends')
      .doc(id)
      .set({'friendId': id, 'createdAt': Timestamp.now()});

  Future<void> following(String id, String name) => db
      .collection('users')
      .doc(_uid)
      .collection('following')
      .doc(id)
      .set({
        'uid': id,
        'displayName': name,
        'username': name.toLowerCase().replaceAll(' ', ''),
        'followedAt': Timestamp.now(),
      });

  Future<void> room({
    required String id,
    required String name,
    required String description,
    required String hostId,
    required String hostName,
    required int participants,
    required Duration age,
    String category = 'talk',
    String language = 'English',
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': hostId,
      'hostName': hostName,
      'name': name,
      'description': description,
      'category': category,
      'visibility': 'public',
      'language': language,
      'participantCount': participants,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.fromDate(ago(age)),
    });
    for (var i = 0; i < (participants < 4 ? participants : 4); i++) {
      await db
          .collection('rooms')
          .doc(id)
          .collection('participants')
          .doc('$id-p$i')
          .set({
            'userId': '$id-p$i',
            'displayName': 'Guest $i',
            'role': i == 0 ? 'host' : 'speaker',
            'isMuted': i > 1,
            'isSpeaker': i < 2,
          });
    }
  }

  Future<void> moment(
    String id,
    String authorId,
    String authorName,
    String caption,
    Duration age,
    int seconds,
  ) => db.collection('voiceMoments').doc(id).set({
    'authorId': authorId,
    'authorName': authorName,
    'caption': caption,
    'audioUrl': 'https://example.invalid/$id.m4a',
    'durationSeconds': seconds,
    'likeCount': 0,
    'commentCount': 0,
    'isPublished': true,
    'createdAt': Timestamp.fromDate(ago(age)),
  });

  Future<void> conversation(
    String id,
    String otherId,
    String otherName,
    String last,
    int unread,
    Duration age,
  ) => db.collection('conversations').doc(id).set({
    'participantIds': [_uid, otherId],
    'participantNames': {_uid: 'CeoGriefer', otherId: otherName},
    'participantEmails': {
      _uid: 'preview@yovoice.app',
      otherId: '$otherId@yovoice.app',
    },
    'participantPhotoUrls': <String, String>{},
    'unreadCounts': {_uid: unread, otherId: 0},
    'lastMessage': last,
    'lastMessageType': 'text',
    'lastMessageSenderId': otherId,
    'updatedAt': Timestamp.fromDate(ago(age)),
    'createdAt': Timestamp.fromDate(ago(const Duration(days: 20))),
    'archivedBy': <String>[],
    'mutedBy': <String>[],
  });

  Future<void> club(String id, String name, String last, Duration age) async {
    await db.collection('clubs').doc(id).set({
      'name': name,
      'description': 'A club',
      'ownerId': 'owner-$id',
      'ownerName': 'Owner',
      'privacy': 'public',
      'defaultLanguage': 'English',
      'memberCount': 41,
      'onlineCount': 6,
      'defaultChatChannelId': 'general',
      'defaultVoiceChannelId': 'lounge',
      'announcementChannelId': 'announcements',
      'createdAt': Timestamp.now(),
    });
    await db.collection('users').doc(_uid).collection('clubs').doc(id).set({
      'clubId': id,
      'joinedAt': Timestamp.now(),
    });
    await db
        .collection('clubs')
        .doc(id)
        .collection('channels')
        .doc('general')
        .collection('messages')
        .doc('m1')
        .set({
          'senderId': 'sieeema',
          'senderName': 'Sieeema',
          'content': last,
          'sentAt': Timestamp.fromDate(ago(age)),
          'isDeleted': false,
        });
  }

  await person('sieeema', 'Sieeema', online: true);
  await person('ola', 'Ola Kwiatkowska', online: true);
  await person('bartek', 'Bartek');
  await person('marta', 'Marta Nowak', online: true);
  await person('jonas', 'Jonas');
  await person('piotr', 'Piotr');
  for (final id in ['sieeema', 'ola', 'bartek', 'marta', 'jonas']) {
    await friend(id);
  }
  await following('marta', 'Marta Nowak');
  await following('jonas', 'Jonas');
  await following('ola', 'Ola Kwiatkowska');
  await following('bartek', 'Bartek');

  await room(
    id: 'r1',
    name: 'Late night conversations',
    description: 'Real people. Honest talks. No scripts.',
    hostId: 'sieeema',
    hostName: 'Sieeema',
    participants: 186,
    age: Duration.zero,
    language: 'Polish',
  );
  await room(
    id: 'r2',
    name: 'Design critique',
    description: 'Bring your work, get honest notes',
    hostId: 'marta',
    hostName: 'Marta Nowak',
    participants: 24,
    age: const Duration(minutes: 6),
    category: 'design',
  );
  await room(
    id: 'r3',
    name: 'Sunday freestyle',
    description: 'Open mic, anything goes',
    hostId: 'jonas',
    hostName: 'Jonas',
    participants: 11,
    age: const Duration(minutes: 12),
    category: 'music',
  );

  await moment('m1', 'ola', 'Ola Kwiatkowska', 'Morning thoughts',
      const Duration(minutes: 24), 42);
  await moment('m2', 'marta', 'Marta Nowak', 'Studio update',
      const Duration(hours: 3), 95);
  await moment('m3', 'sieeema', 'Sieeema', 'Tonight at nine',
      const Duration(hours: 9), 18);
  await moment('m4', 'bartek', 'Bartek', 'Track preview',
      const Duration(days: 2), 57);
  await moment('m5', 'jonas', 'Jonas', 'Answering questions',
      const Duration(days: 4), 131);
  await moment('m6', _uid, 'CeoGriefer', 'Shipping notes',
      const Duration(hours: 5), 33);

  await conversation('c1', 'sieeema', 'Sieeema', 'See you in the room tonight',
      3, const Duration(minutes: 4));
  await conversation('c2', 'ola', 'Ola Kwiatkowska', 'You: sent the draft over',
      0, const Duration(hours: 2));
  await conversation(
      'c3', 'piotr', 'Piotr', 'Hey — saw your Moment', 1, const Duration(hours: 7));
  await conversation('c4', 'bartek', 'Bartek', 'Voice message', 0,
      const Duration(days: 2));
  await club('club-1', 'Night Owls', 'Welcome everyone 👋',
      const Duration(minutes: 40));

  Future<void> globalMessage(
    String id,
    String senderId,
    String senderName,
    String content,
    Duration age, {
    bool creator = false,
    bool staff = false,
    bool deleted = false,
  }) => db
      .collection('globalChat')
      .doc(GlobalChatService.channelId)
      .collection('messages')
      .doc(id)
      .set({
        'senderId': senderId,
        'senderName': senderName,
        'senderPhotoUrl': null,
        'senderIsCreator': creator,
        'senderIsStaff': staff,
        'content': deleted ? '' : content,
        'sentAt': Timestamp.fromDate(ago(age)),
        'isDeleted': deleted,
        'deletedBy': deleted ? 'mod-1' : null,
        'deletedAt': null,
      });

  await globalMessage('gm1', 'marta', 'Marta Nowak',
      'Doors open in ten minutes — bring your work.',
      const Duration(minutes: 2), creator: true);
  await globalMessage('gm2', 'ola', 'Ola Kwiatkowska',
      'Just posted a Moment about the redesign, would love notes.',
      const Duration(minutes: 9));
  await globalMessage('gm3', 'sieeema', 'Sieeema',
      'Keep it kind in here, everyone.',
      const Duration(minutes: 21), staff: true);
  await globalMessage('gm4', 'spammer', 'Spammer', '',
      const Duration(minutes: 34), deleted: true);
  await globalMessage('gm5', 'jonas', 'Jonas',
      'Anyone up for a freestyle room tonight?',
      const Duration(hours: 2));
  await globalMessage('gm6', _uid, 'CeoGriefer',
      'Shipping the new desktop Home today.',
      const Duration(hours: 3));

  return db;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_PreviewApp(db: await _seed()));
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp({required this.db});

  final FakeFirebaseFirestore db;

  @override
  Widget build(BuildContext context) {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: _uid,
        email: 'preview@yovoice.app',
        displayName: 'CeoGriefer',
      ),
    );
    final notifications = NotificationService(firestore: db, auth: auth);
    final rooms = RoomService(firestore: db, auth: auth);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF080711),
        body: Row(
          children: [
            DesktopSidebar(
              active: DesktopNavItem.home,
              unreadConversationCount: 4,
              unreadNotificationCount: 2,
              onSelect: (_) {},
              onCreateRoom: () {},
            onCreateMoment: () {},
              onOpenProfile: () {},
              onOpenProfileSettings: () {},
              profileService: ProfileService(firestore: db, auth: auth),
            ),
            Expanded(
              child: DesktopHome(
                currentUserId: _uid,
                onOpenRoom: (_) {},
                onSeeAllRooms: () {},
                onViewAllFriends: () {},
                onStartRoom: () {},
                onOpenMoment: (_) {},
                onCreateMoment: () {},
                onSeeAllMoments: () {},
                onOpenConversation: (_) {},
                onOpenClub: (_) {},
                onSeeAllChats: () {},
                onOpenClubs: () {},
                roomService: rooms,
                friendService: FriendService(firestore: db, auth: auth),
                profileService: ProfileService(firestore: db, auth: auth),
                feedService: HomeFeedService(firestore: db, auth: auth),
                messageService: MessageService(
                  firestore: db,
                  auth: auth,
                  notificationService: notifications,
                ),
                clubService: ClubService(
                  firestore: db,
                  auth: auth,
                  storage: MockFirebaseStorage(),
                  notificationService: notifications,
                ),
                clubChatService: ClubChatService(firestore: db, auth: auth),
                globalChatService: GlobalChatService(
                  firestore: db,
                  auth: auth,
                ),
                firebaseAuth: auth,
              ),
            ),
            SizedBox(
              width: 344,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
                children: [
                  VoiceTrendingCard(
                    roomService: rooms,
                    profileService: ProfileService(firestore: db, auth: auth),
                    onOpenRoom: (_) {},
                    onSeeAll: () {},
                  ),
                  const SizedBox(height: 16),
                  PremiumDesktopCard(onCheckPlans: () {}),
                  const SizedBox(height: 16),
                  FollowedCreatorsCard(
                    currentUserId: _uid,
                    onOpenCreator: (_) {},
                    onViewAll: () {},
                    onDiscover: () {},
                    followService: FollowService(
                      firestore: db,
                      auth: auth,
                      notificationService: notifications,
                    ),
                    feedService: HomeFeedService(firestore: db, auth: auth),
                    roomService: rooms,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
