// One account's world for the "Zacznij tutaj" tests and the developer
// capture harness (firstSteps A): a fake Firestore holding the signed-in
// profile, and the services the real Home takes through its constructor
// seams. Nothing here is rendered as production content; the names are the
// fixture names of the option sheet (Kamil, Ola Nowak, Nocne Granie).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/first_steps_store.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

const String firstStepsUid = 'me';

Stream<T> _replay<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
});

/// The card's local memory, in memory.
class MemoryFirstStepsStore implements FirstStepsStore {
  MemoryFirstStepsStore([FirstStepsOutcome? initial]) {
    if (initial != null) values[firstStepsUid] = initial;
  }

  final Map<String, FirstStepsOutcome> values = <String, FirstStepsOutcome>{};
  final List<FirstStepsOutcome> writes = <FirstStepsOutcome>[];

  @override
  Future<FirstStepsOutcome?> read(String userId) async => values[userId];

  @override
  Future<void> write(String userId, FirstStepsOutcome outcome) async {
    values[userId] = outcome;
    writes.add(outcome);
  }
}

class _Friends extends FriendService {
  _Friends(
    this.list, {
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  }) : super(
         firestore: db,
         auth: auth,
         mutationInvoker: (name, data) async => <String, dynamic>{
           'outcome': 'requested',
         },
       );

  final List<FriendUser> list;

  @override
  Stream<List<FriendUser>> watchFriends() => _replay<List<FriendUser>>(list);
}

class _Messages extends MessageService {
  _Messages({required FirebaseFirestore db, required FirebaseAuth auth})
    : super(firestore: db, auth: auth);

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => _replay<List<Conversation>>(const <Conversation>[]);
}

class _Feed extends HomeFeedService {
  _Feed({required FirebaseFirestore db, required FirebaseAuth auth})
    : super(firestore: db, auth: auth);

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
}

class _Follows extends FollowService {
  _Follows({required FirebaseFirestore db, required FirebaseAuth auth})
    : super(
        firestore: db,
        auth: auth,
        mutationInvoker: (data) async => <String, dynamic>{'following': true},
      );

  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      Stream<List<FollowUser>>.value(const <FollowUser>[]);
}

class _NoStaff extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

class _Servers implements ServerRepository {
  _Servers(this.list);

  final List<Server> list;

  @override
  String get currentUserId => firstStepsUid;

  @override
  Stream<List<Server>> watchMyServers() => _replay<List<Server>>(list);

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) =>
      Stream<List<ServerChannel>>.value(const <ServerChannel>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FriendUser firstStepsFriend({String id = 'ola', String name = 'Ola Nowak'}) =>
    FriendUser(
      id: id,
      displayName: name,
      email: '',
      photoUrl: null,
      isOnline: true,
      lastSeen: null,
      availability: 'available',
    );

Server firstStepsServer({
  String id = 's',
  String name = 'Nocne Granie',
  ServerPrivacy privacy = ServerPrivacy.public,
  ServerType type = ServerType.community,
}) => Server(
  id: id,
  name: name,
  description: 'Wieczorne granie, rozmowy i transmisje.',
  ownerId: firstStepsUid,
  type: type,
  privacy: privacy,
  defaultLanguage: 'Polish',
  memberCount: 128,
  defaultChannelId: 'general',
  schemaVersion: 1,
  templateVersion: 1,
  activationState: 'active',
);

/// What the Home callbacks were asked to do, in order.
class FirstStepsTaps {
  final List<String> log = <String>[];
  UserProfile? photoProfile;
}

class FirstStepsWorld {
  FirstStepsWorld({
    this.friends = const <FriendUser>[],
    this.servers = const <Server>[],
    this.photo = true,
    this.moments = 0,
    this.following = 0,
    this.name = 'Kamil',
    FirstStepsStore? store,
  }) : store = store ?? MemoryFirstStepsStore();

  final List<FriendUser> friends;
  final List<Server> servers;

  /// Whether the account has a profile photo (the avatar grant answers
  /// `available`).
  final bool photo;
  final int moments;
  final int following;
  final String name;
  final FirstStepsStore store;

  final FakeFirebaseFirestore db = FakeFirebaseFirestore();
  late final MockFirebaseAuth auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: firstStepsUid,
      isEmailVerified: true,
      displayName: name,
      email: '$firstStepsUid@example.com',
    ),
  );
  late final FriendService friendService = _Friends(
    friends,
    db: db,
    auth: auth,
  );
  late final MessageService messageService = _Messages(db: db, auth: auth);
  late final FollowService followService = _Follows(db: db, auth: auth);
  late final HomeFeedService feedService = _Feed(db: db, auth: auth);
  late final ProfileService profileService = ProfileService(
    firestore: db,
    auth: auth,
  );
  late final PresenceService presenceService = PresenceService(
    auth: auth,
    firestore: db,
  );
  late final ProfileMediaService profileMediaService = ProfileMediaService(
    auth: auth,
    invoker: (callable, request) async {
      final expiry = DateTime.now()
          .add(const Duration(seconds: 60))
          .millisecondsSinceEpoch;
      final available = photo && request['kind'] == 'avatar';
      return <Object?, Object?>{
        'schemaVersion': 1,
        'available': available,
        'expiresAtMillis': expiry,
        if (available) ...<Object?, Object?>{
          'url':
              'https://storage.googleapis.com/b/users/me/profile/avatar_1.jpg',
          'generation': '1700000000000001',
          'contentType': 'image/jpeg',
          'size': 4096,
        },
      };
    },
  );
  late final ServerRepository serverRepository = _Servers(servers);

  Future<void> seed() async {
    await db.doc('users/$firstStepsUid').set(<String, dynamic>{
      'uid': firstStepsUid,
      'displayName': name,
      'username': name.toLowerCase(),
      'availability': 'available',
      'momentCount': moments,
      'followingCount': following,
      // Kept by the social-graph callables beside the friend rows. The card
      // does not read it (the rows are the truth); seeded so the profile
      // document looks like production.
      'friendCount': friends.length,
    });
    for (final friend in friends) {
      await db.doc('publicProfiles/${friend.id}').set(<String, dynamic>{
        'uid': friend.id,
        'displayName': friend.displayName,
        'username': friend.id,
      });
    }
  }

  MobileHome mobileHome({
    bool? contentEnabled = true,
    FirstStepsTaps? taps,
    bool withContentDestination = true,
    bool withPhotoDestination = true,
  }) => MobileHome(
    currentUserId: firstStepsUid,
    onOpenDiscover: () => taps?.log.add('servers'),
    onOpenServers: () => taps?.log.add('servers'),
    onOpenFriends: () => taps?.log.add('friends'),
    onCreateRoom: () => taps?.log.add('create-server'),
    onOpenNotifications: () => taps?.log.add('notifications'),
    onOpenProfile: () => taps?.log.add('profile'),
    onOpenMoment: (_) {},
    onOpenChain: (_) {},
    onCreateMoment: () => taps?.log.add('record'),
    onSeeAllMoments: () {},
    onOpenComments: (_) {},
    onOpenConversation: (_) {},
    onSeeAllChats: () {},
    friendService: friendService,
    followService: followService,
    profileService: profileService,
    profileMediaService: profileMediaService,
    feedService: feedService,
    messageService: messageService,
    serverRepository: serverRepository,
    capabilityService: _NoStaff(),
    presenceService: presenceService,
    isVisible: ValueNotifier<bool>(true),
    contentEnabled: contentEnabled,
    onOpenContent: withContentDestination
        ? () => taps?.log.add('content')
        : null,
    onAddProfilePhoto: withPhotoDestination
        ? (profile) {
            taps?.log.add('edit-profile');
            taps?.photoProfile = profile;
          }
        : null,
    firstStepsStore: store,
  );

  DesktopHome desktopHome({
    bool? contentEnabled = true,
    FirstStepsTaps? taps,
  }) => DesktopHome(
    currentUserId: firstStepsUid,
    onSeeAllRooms: () => taps?.log.add('servers'),
    onOpenServers: () => taps?.log.add('servers'),
    onViewAllFriends: () => taps?.log.add('friends'),
    onStartRoom: () => taps?.log.add('create-server'),
    onOpenMoment: (_) {},
    onOpenChain: (_) {},
    onCreateMoment: () => taps?.log.add('record'),
    onSeeAllMoments: () {},
    onOpenConversation: (_) {},
    onSeeAllChats: () {},
    onOpenClubs: () => taps?.log.add('servers'),
    onOpenProfile: () => taps?.log.add('profile'),
    onOpenNotifications: () => taps?.log.add('notifications'),
    friendService: friendService,
    followService: followService,
    profileService: profileService,
    profileMediaService: profileMediaService,
    feedService: feedService,
    messageService: messageService,
    serverRepository: serverRepository,
    capabilityService: _NoStaff(),
    presenceService: presenceService,
    firebaseAuth: auth,
    isVisible: ValueNotifier<bool>(true),
    contentEnabled: contentEnabled,
    onOpenContent: () => taps?.log.add('content'),
    onAddProfilePhoto: (profile) {
      taps?.log.add('edit-profile');
      taps?.photoProfile = profile;
    },
    firstStepsStore: store,
  );
}
