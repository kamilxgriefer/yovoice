import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

void main() {
  const me = 'privacy-me';
  const friend = 'privacy-friend';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: me,
        email: 'me@private.invalid',
        displayName: 'Private Me',
      ),
    );
    await db.collection('users').doc(me).set({
      'uid': me,
      'email': 'me@private.invalid',
      'displayName': 'Private Me',
      'notificationPreferences': {'directMessage': false},
      'role': 'user',
      'isOnline': true,
    });
    await db.collection('users').doc(friend).set({
      'uid': friend,
      'email': 'friend@private.invalid',
      'displayName': 'Private Name Must Not Render',
      'role': 'moderator',
      'isOnline': false,
    });
    await db.collection('publicProfiles').doc(friend).set({
      'uid': friend,
      'displayName': 'Public Friend',
      'username': 'public.friend',
      'photoUrl': 'https://cdn.example/friend.jpg',
      'bio': 'Public bio',
      'accountType': 'personal',
      'premiumIdentity': true,
      'friendCount': 4,
      'followerCount': 8,
      'followingCount': 2,
    });
    await db.collection('socialPresence').doc(friend).set({
      'uid': friend,
      'isOnline': true,
      'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 8, 16)),
    });
    await db.collection('users').doc(me).collection('friends').doc(friend).set({
      'userId': friend,
    });
  });

  tearDown(ProfileService.resetCurrentProfileCache);

  test(
    'current profile stays private while foreign profile uses projection',
    () async {
      final service = ProfileService(firestore: db, auth: auth);

      final mine = await service.watchCurrentProfile().first;
      final theirs = await service.watchProfile(friend).first;

      expect(mine.email, 'me@private.invalid');
      expect(theirs.displayName, 'Public Friend');
      expect(theirs.email, isEmpty);
      expect(theirs.isOnline, isFalse);
      expect(theirs.premiumIdentity, isTrue);
    },
  );

  test('friends join public identity with friend-only presence', () async {
    final service = FriendService(firestore: db, auth: auth);
    final friends = await service
        .watchFriends()
        .firstWhere((items) => items.length == 1 && items.single.isOnline)
        .timeout(const Duration(seconds: 3));

    expect(friends.single.id, friend);
    expect(friends.single.displayName, 'Public Friend');
    expect(friends.single.username, 'public.friend');
    expect(friends.single.email, isEmpty);
    expect(friends.single.isOnline, isTrue);
    expect(friends.single.premiumIdentity, isTrue);
  });

  test(
    'ordinary search is callable-only and discards injected email fields',
    () async {
      String? searched;
      final service = FriendService(
        firestore: db,
        auth: auth,
        searchInvoker: (query, limit) async {
          searched = '$query:$limit';
          return [
            {
              'uid': friend,
              'displayName': 'Public Friend',
              'username': 'public.friend',
              'photoUrl': 'https://cdn.example/friend.jpg',
              'premiumIdentity': true,
              'email': 'must-not-survive@private.invalid',
              'isOnline': true,
              'role': 'superAdmin',
            },
          ];
        },
      );

      final results = await service.searchUsers('@public');

      expect(searched, '@public:20');
      expect(results, hasLength(1));
      expect(results.single.email, isEmpty);
      expect(results.single.isOnline, isFalse);
      expect(results.single.displayName, 'Public Friend');
      expect(results.single.username, 'public.friend');
    },
  );

  test(
    'presence stream never reads presence from the private user document',
    () async {
      final presence = await MessageService(
        firestore: db,
        auth: auth,
      ).watchUserPresence(friend).first;

      expect(presence.isOnline, isTrue);
      expect(presence.lastSeen?.toUtc(), DateTime.utc(2026, 8, 16));
    },
  );

  test('new conversations persist no participant email snapshots', () async {
    final service = MessageService(firestore: db, auth: auth);
    final conversationId = await service.openOrCreateConversation(
      otherUserId: friend,
      otherDisplayName: 'Public Friend',
      otherEmail: 'friend@private.invalid',
      otherPhotoUrl: 'https://cdn.example/friend.jpg',
    );

    final conversation =
        (await db.collection('conversations').doc(conversationId).get())
            .data()!;
    expect(conversation.containsKey('participantEmails'), isFalse);
    expect(conversation.toString(), isNot(contains('@private.invalid')));
  });

  test(
    'legacy email snapshots are parsed only for compatibility and ignored',
    () async {
      await db.collection('conversations').doc('legacy-email-conversation').set(
        {
          'participantIds': [me, friend],
          'participantNames': {me: 'Private Me', friend: ''},
          'participantEmails': {
            me: 'me@private.invalid',
            friend: 'friend@private.invalid',
          },
        },
      );
      final conversation = Conversation.fromFirestore(
        await db
            .collection('conversations')
            .doc('legacy-email-conversation')
            .get(),
      );
      expect(conversation.displayNameFor(friend), 'YO Voice user');
      expect(conversation.emailFor(friend), isEmpty);

      await db
          .collection('users')
          .doc(me)
          .collection('friendRequests')
          .doc(friend)
          .set({
            'senderId': friend,
            'senderName': '',
            'senderEmail': 'friend@private.invalid',
          });
      final request = FriendRequest.fromFirestore(
        await db
            .collection('users')
            .doc(me)
            .collection('friendRequests')
            .doc(friend)
            .get(),
      );
      expect(request.senderName, 'YO Voice user');
      expect(request.senderEmail, isEmpty);
      expect(request.toMap().containsKey('senderEmail'), isFalse);
    },
  );

  test(
    'follow lists resolve identity from public profiles, never stale edges',
    () async {
      await db
          .collection('users')
          .doc(me)
          .collection('following')
          .doc(friend)
          .set({
            'uid': friend,
            'followedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 16)),
            'displayName': 'Stale Private Name',
            'username': 'stale.private',
            'photoUrl': 'https://stale.invalid/private.jpg',
          });

      final users = await FollowService(
        firestore: db,
        auth: auth,
      ).watchFollowing(me).first;
      expect(users, hasLength(1));
      expect(users.single.uid, friend);
      expect(users.single.displayName, 'Public Friend');
      expect(users.single.username, 'public.friend');
      expect(users.single.photoUrl, 'https://cdn.example/friend.jpg');
    },
  );
}
