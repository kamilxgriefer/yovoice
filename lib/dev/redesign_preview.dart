// Local-only visual preview of the approved Home / Voice Moments / Reels
// redesign (slice F1, docs/agent_handoffs/2026-09-11-approved-home-moments-reels.md).
//
// No sign-in, no network, no writes: every surface is fed by in-memory
// fixtures through the same injection seams the redesign tests use
// (fake_cloud_firestore + firebase_auth_mocks + the services' constructor
// seams), so the real widgets can be rendered on a Simulator without an
// account. Reel footage is a still stand-in (the same approach as
// test/reels_immersive_redesign_test.dart); the Voice player is a simulated
// clock that advances progress without producing audio.
//
//   flutter run -t lib/dev/redesign_preview.dart -d <simulator>
//
// Optional launch configuration (all have runtime toggles in the dock's
// More sheet / the desktop rail's More item):
//   --dart-define=YO_PREVIEW_STATE=populated|empty|loading|error|denied
//   --dart-define=YO_PREVIEW_TAB=home|moments|reels
//   --dart-define=YO_PREVIEW_LOCALE=pl|en
//   --dart-define=YO_PREVIEW_THEME=system|dark|pearl
//   --dart-define=YO_PREVIEW_TEXT=100|200
//   --dart-define=YO_PREVIEW_LONG_NAMES=true|false
//
// Not referenced by lib/main.dart; never part of a shipped build.
//
// The two ignores below exist for the same reason profile_preview.dart has
// the first one: this harness deliberately reuses the test-only fakes and the
// widgets' @visibleForTesting injection seams (player factory, still video
// builder) so nothing here can reach a backend or a real decoder.
// ignore_for_file: depend_on_referenced_packages
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/firebase_options.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const _me = 'preview-me';

/// One data state, applied to all three surfaces at once.
enum _State { populated, empty, loading, error, denied }

enum _Theme { system, dark, pearl }

class _Config {
  const _Config({
    required this.state,
    required this.polish,
    required this.theme,
    required this.bigText,
    required this.longNames,
    required this.initialTab,
    required this.initialReels,
  });

  factory _Config.fromEnvironment() {
    const state = String.fromEnvironment(
      'YO_PREVIEW_STATE',
      defaultValue: 'populated',
    );
    const tab = String.fromEnvironment('YO_PREVIEW_TAB', defaultValue: 'home');
    const locale = String.fromEnvironment(
      'YO_PREVIEW_LOCALE',
      defaultValue: 'pl',
    );
    const theme = String.fromEnvironment(
      'YO_PREVIEW_THEME',
      defaultValue: 'system',
    );
    const text = String.fromEnvironment('YO_PREVIEW_TEXT', defaultValue: '100');
    const longNames = bool.fromEnvironment('YO_PREVIEW_LONG_NAMES');
    return _Config(
      state: _State.values.firstWhere(
        (value) => value.name == state,
        orElse: () => _State.populated,
      ),
      polish: locale != 'en',
      theme: _Theme.values.firstWhere(
        (value) => value.name == theme,
        orElse: () => _Theme.system,
      ),
      bigText: text == '200',
      longNames: longNames,
      initialTab: tab == 'home' ? 0 : _momentsSlot,
      initialReels: tab == 'reels',
    );
  }

  final _State state;
  final bool polish;
  final _Theme theme;
  final bool bigText;
  final bool longNames;
  final int initialTab;
  final bool initialReels;

  /// Fixtures are rebuilt only when the data they hold would differ.
  String get fixtureId => '${state.name}-$longNames';

  _Config copyWith({
    _State? state,
    bool? polish,
    _Theme? theme,
    bool? bigText,
    bool? longNames,
  }) => _Config(
    state: state ?? this.state,
    polish: polish ?? this.polish,
    theme: theme ?? this.theme,
    bigText: bigText ?? this.bigText,
    longNames: longNames ?? this.longNames,
    initialTab: initialTab,
    initialReels: initialReels,
  );
}

/// The shell's stable content identities (docs/UI.md, "Floating mobile
/// navigation"): Home 0, Chats 1, Rooms 3, Your Moments 5.
const _chatsSlot = 1;
const _roomsSlot = 3;
const _momentsSlot = 5;

/// Callbacks the real screens fire (join room, open chat, record...) are
/// reported here instead of navigating, so a tap is visibly acknowledged and
/// nothing leaves the preview.
final ValueNotifier<String?> _lastAction = ValueNotifier<String?>(null);

void _report(String action) => _lastAction.value = action;

/// The selected shell tab and the YO Moments format live outside the shell:
/// a fixture rebuild recreates the shell, and the settings sheet's GO TO
/// buttons can outlive the shell that opened them, so both read these.
final ValueNotifier<int> _tabRequest = ValueNotifier<int>(0);
final ValueNotifier<bool> _reelsRequest = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same rationale as the other previews: plugin registrants expect an app
  // to exist. Nothing here signs in, reads or writes.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Preview: continuing without Firebase ($error)');
  }
  // Identity badges resolve through this repository; the fake fetcher answers
  // every uid locally so no badge lookup can leave the device.
  PublicIdentityRepository.instance = PublicIdentityRepository(
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
    fetchOverride: (uids) async => {
      for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
    },
    flushDelay: const Duration(milliseconds: 1),
  );
  final config = _Config.fromEnvironment();
  _tabRequest.value = config.initialTab;
  _reelsRequest.value = config.initialReels;
  runApp(_PreviewApp(initial: config));
}

// ---------------------------------------------------------------------------
// Home fixtures — mirrors test/home_redesign_test.dart.
// ---------------------------------------------------------------------------

/// A replayable source that models one Firestore listener: late listeners
/// get the last value (or error), retries after a failure can recover.
class _Source<T> {
  _Source() {
    stream = Stream<T>.multi((sink) {
      listens++;
      final recovery = _recovery;
      if (_error != null && recovery != null && listens > _failedAtListen) {
        // A retry after a failure: show the section loading, then recover.
        Timer(const Duration(milliseconds: 900), () {
          if (!_closed) add(recovery);
        });
      } else {
        if (_hasValue) sink.add(_value as T);
        if (_error != null) sink.addError(_error!);
      }
      final subscription = _events.stream.listen(
        sink.add,
        onError: sink.addError,
      );
      sink.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  final _events = StreamController<T>.broadcast();
  late final Stream<T> stream;
  T? _value;
  Object? _error;
  T? _recovery;
  bool _hasValue = false;
  bool _closed = false;
  int listens = 0;
  int _failedAtListen = 0;

  void add(T value) {
    _value = value;
    _error = null;
    _recovery = null;
    _hasValue = true;
    if (!_closed) _events.add(value);
  }

  /// Fails every current and future listener with a Firestore [code]. When
  /// [recovery] is given, the next NEW listener (a local retry) recovers with
  /// that value after a short loading phase.
  void fail(String code, {T? recovery}) {
    _value = null;
    _hasValue = false;
    _recovery = recovery;
    _failedAtListen = listens;
    _error = FirebaseException(plugin: 'cloud_firestore', code: code);
    if (!_closed) _events.addError(_error!);
  }

  Future<void> close() {
    _closed = true;
    return _events.close();
  }
}

class _Rooms extends RoomService {
  _Rooms(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _HomeFixture fixture;
  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() => fixture.rooms.stream;
  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() => fixture.owned.stream;
}

class _Friends extends FriendService {
  _Friends(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _HomeFixture fixture;
  @override
  Stream<List<FriendUser>> watchFriends() => fixture.friends.stream;
}

class _Following extends FollowService {
  _Following(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _HomeFixture fixture;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      fixture.following.stream;
}

class _HomeFeed extends HomeFeedService {
  _HomeFeed(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _HomeFixture fixture;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      // New stream identity models a new one-shot provider request on retry.
      fixture.moments.stream.map((value) => value);
}

class _Messages extends MessageService {
  _Messages(this.fixture) : super(firestore: fixture.db, auth: fixture.auth);
  final _HomeFixture fixture;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => fixture.chats.stream.map((value) => value);
}

class _Capabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

typedef _Person = ({
  String id,
  String short,
  String long,
  bool online,
  String? availability,
});

const List<_Person> _people = [
  (
    id: 'qa-ola',
    short: 'Ola',
    long: 'Aleksandra Ola Wiśniewska',
    online: true,
    availability: 'available',
  ),
  (
    id: 'qa-marek',
    short: 'Marek',
    long: 'Marek Antoni Nowakowski-Zieliński',
    online: true,
    availability: 'busy',
  ),
  (
    id: 'qa-ada',
    short: 'Ada',
    long: 'Ada Lovelace-Kowalczyk',
    online: true,
    availability: 'away',
  ),
  (
    id: 'qa-szymon',
    short: 'Szymon',
    long: 'Szymon Bartłomiej Krzyżanowski',
    online: false,
    availability: null,
  ),
  (
    id: 'qa-kasia',
    short: 'Kasia',
    long: 'Katarzyna Wiśniewska-Jabłońska',
    online: true,
    availability: 'available',
  ),
  (
    id: 'qa-tomek',
    short: 'Tomek',
    long: 'Tomasz Przemysław Wojciechowski',
    online: false,
    availability: null,
  ),
];

const _longCaptionPl =
    'Krótka historia o tym, co dziś było ważne. Rozmowa może zacząć się od '
    'jednego zdania — a dalszą część przeczytasz i usłyszysz w szczegółach.';
const _longCaptionEn =
    'Evening stories from our little corner of the city. A longer caption '
    'stays readable when you open it, without hiding the video controls.';

class _HomeFixture {
  _HomeFixture({required this.state, required this.longNames}) {
    ready = _initialize();
  }

  final _State state;
  final bool longNames;
  final db = FakeFirebaseFirestore();
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _me, isEmailVerified: true),
  );
  final rooms = _Source<List<VoiceRoom>>();
  final owned = _Source<List<VoiceRoom>>();
  final friends = _Source<List<FriendUser>>();
  final following = _Source<List<FollowUser>>();
  final moments = _Source<List<VoiceMoment>>();
  final chats = _Source<List<Conversation>>();
  late final roomService = _Rooms(this);
  late final friendService = _Friends(this);
  late final followService = _Following(this);
  late final feedService = _HomeFeed(this);
  late final messageService = _Messages(this);
  late final profileService = ProfileService(firestore: db, auth: auth);
  late final presenceService = PresenceService(auth: auth, firestore: db);
  late final profileMediaService = ProfileMediaService(
    auth: auth,
    invoker: (callable, request) async =>
        throw StateError('Preview has no media callable ($callable).'),
  );
  late final clubService = ClubService(firestore: db, auth: auth);
  late final clubChatService = ClubChatService(firestore: db, auth: auth);
  late final Future<void> ready;
  Timer? _failure;

  String _name(_Person person) => longNames ? person.long : person.short;

  Future<void> _initialize() async {
    await db.doc('users/$_me').set({
      'uid': _me,
      'displayName': longNames ? 'Aleksandra Nowakowska-Kowalska' : 'Aleksandra',
      'username': 'aleksandra',
      'availability': 'available',
    });
    for (final person in _people) {
      await db.doc('publicProfiles/${person.id}').set({
        'uid': person.id,
        'displayName': _name(person),
        'username': person.short.toLowerCase(),
      });
    }
    final now = Timestamp.now();
    final roomSeeds = <String, Map<String, Object?>>{
      'qa-live': {
        'hostId': 'qa-ola',
        'hostName': _name(_people[0]),
        'name': longNames
            ? 'Wieczorne rozmowy o muzyce, podcastach i wszystkim, co nas dziś poruszyło'
            : 'Wieczorne rozmowy',
        'description': 'Rozmowy, pomysły i codzienne historie.',
        'category': 'talk',
        'visibility': 'public',
        'language': 'Polish',
        'participantCount': 3,
        'memberCount': 0,
        'isLive': true,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': now,
      },
      'qa-live-2': {
        'hostId': 'qa-marek',
        'hostName': _name(_people[1]),
        'name': 'Late night broadcast: stories from the studio floor',
        'description': 'A weekly English broadcast with listener questions.',
        'category': 'broadcast',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 12,
        'memberCount': 40,
        'isLive': true,
        'roomType': 'broadcast',
        'status': 'active',
        'experience': 'broadcast',
        'createdAt': now,
      },
      'qa-owned': {
        'hostId': _me,
        'hostName': 'Aleksandra',
        'name': longNames
            ? 'Twój pokój o bardzo długiej nazwie, która musi się zawijać'
            : 'Twój pokój',
        'description': 'Rozmowy, pomysły i codzienne historie.',
        'category': 'talk',
        'visibility': 'public',
        'language': 'Polish',
        'participantCount': 0,
        'memberCount': 0,
        'isLive': false,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': now,
      },
    };
    for (final entry in roomSeeds.entries) {
      await db.doc('rooms/${entry.key}').set(entry.value);
    }
    final participantSeeds = <String, List<(_Person, String, bool)>>{
      'qa-live': [
        (_people[0], 'host', true),
        (_people[2], 'speaker', true),
        (_people[3], 'listener', false),
      ],
      'qa-live-2': [
        (_people[1], 'host', true),
        (_people[4], 'listener', false),
        (_people[5], 'listener', false),
      ],
    };
    for (final entry in participantSeeds.entries) {
      for (final (person, role, speaker) in entry.value) {
        await db.doc('rooms/${entry.key}/participants/${person.id}').set({
          'userId': person.id,
          'displayName': _name(person),
          'role': role,
          'isSpeaker': speaker,
          'isMuted': !speaker,
          'isHandRaised': false,
          'joinedAt': now,
        });
      }
    }
    final chatSeeds = <String, (_Person, String, String, int)>{
      'qa-chat-1': (_people[0], 'Masz chwilę na rozmowę?', 'text', 2),
      'qa-chat-2': (
        _people[1],
        'Wysłałem Ci notatki z wczorajszego pokoju — zerknij, kiedy będziesz '
            'mieć chwilę, bo jest tam kilka rzeczy do przegadania.',
        'text',
        0,
      ),
      'qa-chat-3': (_people[2], 'Voice message', 'voice', 1),
    };
    for (final entry in chatSeeds.entries) {
      final (person, message, type, unread) = entry.value;
      await db.doc('conversations/${entry.key}').set({
        'participantIds': [_me, person.id],
        'participantNames': {_me: 'Aleksandra', person.id: _name(person)},
        'unreadCounts': {_me: unread},
        'lastMessage': message,
        'lastMessageType': type,
        'lastMessageSenderId': person.id,
        'updatedAt': now,
        'createdAt': now,
      });
    }
    final liveRooms = <VoiceRoom>[
      VoiceRoom.fromFirestore(await db.doc('rooms/qa-live').get()),
      VoiceRoom.fromFirestore(await db.doc('rooms/qa-live-2').get()),
    ];
    final ownedRoom = VoiceRoom.fromFirestore(
      await db.doc('rooms/qa-owned').get(),
    );
    final conversations = <Conversation>[
      for (final id in chatSeeds.keys)
        Conversation.fromFirestore(await db.doc('conversations/$id').get()),
    ];
    if (state == _State.loading) return;
    final populated = state != _State.empty;
    final followed = <VoiceMoment>[
      _moment(
        'qa-moment-ola',
        author: _people[0],
        caption: 'Małe rzeczy cieszą',
        seconds: 12,
        likes: 2,
        comments: 1,
        age: const Duration(minutes: 40),
      ),
      _moment(
        'qa-moment-marek',
        author: _people[1],
        caption: _longCaptionPl,
        seconds: 58,
        likes: 12,
        comments: 3,
        age: const Duration(hours: 3),
      ),
      _moment(
        'qa-moment-ada',
        author: _people[2],
        caption: 'Morning walk thoughts before the first coffee',
        seconds: 24,
        likes: 5,
        comments: 0,
        age: const Duration(hours: 6),
      ),
      VoiceMoment(
        id: 'qa-moment-me',
        authorId: _me,
        authorName: 'Aleksandra',
        authorPhotoUrl: null,
        caption: 'Własna historia',
        audioUrl: null,
        durationSeconds: 9,
        likeCount: 0,
        commentCount: 0,
        isPublished: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expiresAt: DateTime.now().add(const Duration(hours: 20)),
        schemaVersion: 2,
        status: 'published',
        hasAuthorizedMedia: true,
      ),
    ];
    rooms.add(populated ? liveRooms : const []);
    owned.add(populated ? [ownedRoom] : const []);
    friends.add(
      populated
          ? [
              for (final person in _people)
                FriendUser(
                  id: person.id,
                  displayName: _name(person),
                  email: '',
                  photoUrl: null,
                  isOnline: person.online,
                  lastSeen: null,
                  availability: person.availability,
                ),
            ]
          : const [],
    );
    following.add(
      populated
          ? [
              for (final person in _people.take(3))
                FollowUser(
                  uid: person.id,
                  displayName: _name(person),
                  username: person.short.toLowerCase(),
                  photoUrl: null,
                  followedAt: null,
                ),
            ]
          : const [],
    );
    moments.add(populated ? followed : const []);
    chats.add(populated ? conversations : const []);
    if (state == _State.error || state == _State.denied) {
      // Content first, then the failure, so the "denied cached content is
      // removed" behavior is observable rather than assumed. Retry recovers.
      final code = state == _State.denied ? 'permission-denied' : 'unavailable';
      _failure = Timer(const Duration(milliseconds: 1500), () {
        rooms.fail(code, recovery: liveRooms);
        moments.fail(code, recovery: followed);
        chats.fail(code, recovery: conversations);
      });
    }
  }

  VoiceMoment _moment(
    String id, {
    required _Person author,
    required String caption,
    required int seconds,
    required int likes,
    required int comments,
    required Duration age,
  }) => VoiceMoment(
    id: id,
    authorId: author.id,
    authorName: _name(author),
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: null,
    durationSeconds: seconds,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: DateTime.now().subtract(age),
    expiresAt: DateTime.now().add(const Duration(hours: 20)),
    schemaVersion: 2,
    status: 'published',
    hasAuthorizedMedia: true,
  );

  Widget home({
    required bool desktop,
    required ValueListenable<bool> visible,
  }) => desktop
      ? DesktopHome(
          key: const ValueKey('redesign-home'),
          currentUserId: _me,
          onOpenRoom: (r) => _report('room:${r.id} (prejoin flow)'),
          onSeeAllRooms: () => _report('discover'),
          onFindCreators: () => _report('find-creators'),
          onViewAllFriends: () => _report('friends'),
          onStartRoom: () => _report('create-room'),
          onOpenMoment: (m) => _report('moment:${m.id}'),
          onOpenChain: (m) => _report('chain:${m.first.id}'),
          onCreateMoment: () => _report('record-moment'),
          onSeeAllMoments: () => _report('moments'),
          onOpenConversation: (c) => _report('chat:${c.id}'),
          onSeeAllChats: () => _report('chats'),
          onOpenClub: (club) => _report('club:${club.id}'),
          onOpenClubs: () => _report('clubs'),
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          profileMediaService: profileMediaService,
          feedService: feedService,
          messageService: messageService,
          clubService: clubService,
          clubChatService: clubChatService,
          firebaseAuth: auth,
          capabilityService: _Capabilities(),
          presenceService: presenceService,
          isVisible: visible,
        )
      : MobileHome(
          key: const ValueKey('redesign-home'),
          currentUserId: _me,
          onOpenRoom: (r) => _report('room:${r.id} (prejoin flow)'),
          onOpenDiscover: () => _report('discover'),
          onOpenFindCreators: () => _report('find-creators'),
          onOpenFriends: () => _report('friends'),
          onCreateRoom: () => _report('create-room'),
          onOpenNotifications: () => _report('notifications'),
          onOpenProfile: () => _report('profile'),
          unreadNotificationCount: 2,
          onOpenMoment: (m) => _report('moment:${m.id}'),
          onOpenChain: (m) => _report('chain:${m.first.id}'),
          onCreateMoment: () => _report('record-moment'),
          onSeeAllMoments: () => _report('moments'),
          onOpenComments: (m) => _report('comments:${m.id}'),
          onOpenConversation: (c) => _report('chat:${c.id}'),
          onSeeAllChats: () => _report('chats'),
          roomService: roomService,
          friendService: friendService,
          followService: followService,
          profileService: profileService,
          profileMediaService: profileMediaService,
          feedService: feedService,
          messageService: messageService,
          capabilityService: _Capabilities(),
          presenceService: presenceService,
          isVisible: visible,
        );

  Future<void> dispose() async {
    _failure?.cancel();
    await Future.wait([
      rooms.close(),
      owned.close(),
      friends.close(),
      following.close(),
      moments.close(),
      chats.close(),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Voice Moments fixtures — mirrors test/voice_moments_redesign_test.dart.
// ---------------------------------------------------------------------------

class _Discovery implements MomentDiscoveryService {
  _Discovery(this.fixture);
  final _VoiceFixture fixture;
  final counters = StreamController<Map<String, MomentEngagement>>.broadcast();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = 60,
    int? seed,
  }) => fixture.load();

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      counters.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VoiceFeed implements HomeFeedService {
  _VoiceFeed(this.fixture);
  final _VoiceFixture fixture;
  final events = StreamController<List<VoiceMoment>>.broadcast();

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.multi((sink) {
        switch (fixture.state) {
          case _State.loading:
            break;
          case _State.error:
            sink.addError(StateError('Preview: simulated provider failure.'));
          case _State.denied:
            sink.addError(FirebaseAuthException(code: 'permission-denied'));
          case _State.empty:
            sink.add(const []);
          case _State.populated:
            sink.add(fixture.social);
        }
        final subscription = events.stream.listen(
          sink.add,
          onError: sink.addError,
        );
        sink.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    fixture.likes[momentId] = liked;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Moments implements MomentService {
  _Moments(this.fixture);
  final _VoiceFixture fixture;

  @override
  Stream<VoiceMoment> watchMoment(String momentId) => Stream.value(
    fixture.all.firstWhere((moment) => moment.id == momentId),
  );

  @override
  Stream<List<VoiceMoment>> watchMyMoments() => Stream.value(fixture.mine);

  @override
  Stream<List<MomentComment>> watchComments(
    String momentId, {
    int limit = 80,
  }) => Stream.value(const []);

  @override
  Future<Uri> resolveMediaUri({required String momentId, String? commentId}) =>
      Future.value(Uri.parse('https://example.invalid/$momentId.m4a'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Views implements MomentViewsService {
  final viewed = <String>{};

  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(const {});

  @override
  Future<void> markViewed(String momentId) async => viewed.add(momentId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A simulated audio player: no sound, but a real clock so play/pause, the
/// progress control and the elapsed/total readout behave as they would.
class _SimPlayer implements audio.AudioPlayer {
  _SimPlayer(this.fixture);
  final _VoiceFixture fixture;
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _states = StreamController<audio.PlayerState>.broadcast();
  Timer? _ticker;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(seconds: 24);
  bool _closed = false;

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Stream<audio.PlayerState> get onPlayerStateChanged => _states.stream;

  void _emit(audio.PlayerState state) {
    if (!_closed) _states.add(state);
  }

  void _start() {
    _emit(audio.PlayerState.playing);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_closed) return;
      _position += const Duration(milliseconds: 250);
      if (_position >= _duration) {
        _position = _duration;
        _positions.add(_position);
        _ticker?.cancel();
        _emit(audio.PlayerState.completed);
        _completions.add(null);
        return;
      }
      _positions.add(_position);
    });
  }

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    final uri = (source as audio.UrlSource).url;
    _duration = fixture.durationFor(uri);
    _position = position ?? Duration.zero;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_closed) return;
    _durations.add(_duration);
    _positions.add(_position);
    _start();
  }

  @override
  Future<void> pause() async {
    _ticker?.cancel();
    _emit(audio.PlayerState.paused);
  }

  @override
  Future<void> resume() async => _start();

  @override
  Future<void> stop() async {
    _ticker?.cancel();
    _position = Duration.zero;
    _emit(audio.PlayerState.stopped);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    if (!_closed) _positions.add(position);
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    _ticker?.cancel();
    await _positions.close();
    await _durations.close();
    await _completions.close();
    await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VoiceFixture {
  _VoiceFixture({required this.state, required this.longNames}) {
    final now = DateTime.now();
    VoiceMoment item(
      String id,
      _Person author,
      String caption,
      int seconds, {
      int likes = 0,
      int comments = 0,
      Duration age = const Duration(hours: 1),
      bool permanent = false,
    }) => VoiceMoment(
      id: id,
      authorId: author.id,
      authorName: longNames ? author.long : author.short,
      authorPhotoUrl: null,
      caption: caption,
      audioUrl: null,
      durationSeconds: seconds,
      likeCount: likes,
      commentCount: comments,
      isPublished: true,
      createdAt: now.subtract(age),
      expiresAt: permanent ? null : now.add(const Duration(hours: 20)),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: true,
    );
    final own = VoiceMoment(
      id: 'v-own',
      authorId: _me,
      authorName: 'Aleksandra',
      authorPhotoUrl: null,
      caption: 'Własna historia z dzisiejszego poranka',
      audioUrl: null,
      durationSeconds: 9,
      likeCount: 1,
      commentCount: 0,
      isPublished: true,
      createdAt: now.subtract(const Duration(minutes: 20)),
      expiresAt: now.add(const Duration(hours: 20)),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: true,
    );
    all = [
      item(
        'v-ola',
        _people[0],
        'Małe rzeczy cieszą',
        12,
        likes: 4,
        comments: 1,
        age: const Duration(minutes: 35),
      ),
      item(
        'v-marek',
        _people[1],
        _longCaptionPl,
        58,
        likes: 12,
        comments: 3,
        age: const Duration(hours: 2),
      ),
      item(
        'v-ada',
        _people[2],
        'Morning walk thoughts before the first coffee',
        24,
        likes: 5,
        age: const Duration(hours: 5),
        permanent: true,
      ),
      own,
      item(
        'v-szymon',
        _people[3],
        'Dziś bez planu — tylko dźwięki z ulicy.',
        31,
        likes: 2,
        comments: 2,
        age: const Duration(hours: 9),
      ),
      item(
        'v-kasia',
        _people[4],
        _longCaptionEn,
        44,
        likes: 27,
        comments: 8,
        age: const Duration(hours: 16),
      ),
    ];
    social = [all[0], all[1], own];
    mine = [own];
  }

  final _State state;
  final bool longNames;
  final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));
  late final List<VoiceMoment> all;
  late final List<VoiceMoment> social;
  late final List<VoiceMoment> mine;
  final likes = <String, bool>{};
  late final discovery = _Discovery(this);
  late final feed = _VoiceFeed(this);
  late final moments = _Moments(this);
  final views = _Views();
  final _players = <_SimPlayer>[];

  Duration durationFor(String uri) {
    final id = uri.split('/').last.replaceAll('.m4a', '');
    for (final moment in all) {
      if (moment.id == id) return Duration(seconds: moment.durationSeconds);
    }
    return const Duration(seconds: 24);
  }

  audio.AudioPlayer newPlayer() {
    final player = _SimPlayer(this);
    _players.add(player);
    return player;
  }

  Future<MomentDiscoveryFeed> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    switch (state) {
      case _State.loading:
        return Completer<MomentDiscoveryFeed>().future;
      case _State.error:
        throw StateError('Preview: simulated provider failure.');
      case _State.denied:
        throw FirebaseAuthException(code: 'permission-denied');
      case _State.empty:
        return const MomentDiscoveryFeed(
          moments: [],
          fetchedCount: 0,
          drops: {},
          seed: 7,
          poolExhausted: true,
        );
      case _State.populated:
        return MomentDiscoveryFeed(
          moments: all,
          fetchedCount: all.length,
          drops: const {},
          seed: 7,
          poolExhausted: true,
        );
    }
  }

  Future<void> dispose() async {
    await discovery.counters.close();
    await feed.events.close();
    for (final player in _players) {
      if (!player._closed) await player.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// Reels fixtures — mirrors test/reels_immersive_redesign_test.dart.
// ---------------------------------------------------------------------------

class _ReelsFixture {
  _ReelsFixture({required this.state}) {
    service = ReelService(auth: auth, callableInvoker: _invoke);
  }

  final _State state;
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _me, isEmailVerified: true),
  );
  late final ReelService service;
  final likeCounts = <String, int>{
    'immersive_1': 12,
    'immersive_2': 340,
    'immersive_3': 0,
  };
  final liked = <String, bool>{'immersive_2': true};

  Map<String, Object?> _wire(String id) {
    final (author, name, caption, comments, stickers) = switch (id) {
      'immersive_1' => ('author_1', 'Marek Nowak', _longCaptionPl, 3, true),
      'immersive_2' => (
        'author_2',
        'Marta Zielińska-Kowalczyk',
        _longCaptionEn,
        28,
        false,
      ),
      _ => (_me, 'Aleksandra', 'Own Reel — owner actions live in More.', 0, false),
    };
    return {
      'id': id,
      'authorId': author,
      'authorName': name,
      'media': {
        'kind': 'video',
        'contentType': 'video/mp4',
        'size': 1024,
        'generation': '1',
        'durationMs': 15000,
      },
      'backingAudio': null,
      'composition': ReelComposition(
        trimEndMs: 15000,
        caption: caption,
        linkOverlays: stickers
            ? [
                ReelLinkOverlay(
                  id: 'top',
                  label: 'Top link',
                  uri: Uri.parse('https://example.com/top'),
                  x: .5,
                  y: 0,
                ),
                ReelLinkOverlay(
                  id: 'bottom',
                  label: 'Bottom link',
                  uri: Uri.parse('https://example.com/bottom'),
                  x: .5,
                  y: 1,
                ),
              ]
            : const [],
      ).toWire(),
      'publishedAtMillis': 1900000000000,
      'sortKey': '1900000000000_$id',
      'availability': {
        'schemaVersion': 1,
        'availabilityHours': 'permanent',
        'expiresAtMillis': null,
      },
      'likeCount': likeCounts[id] ?? 0,
      'commentCount': comments,
      'callerLiked': liked[id] ?? false,
    };
  }

  Future<Map<Object?, Object?>> _invoke(
    String name,
    Map<String, Object?> payload,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    switch (name) {
      case 'listReelsV2':
        switch (state) {
          case _State.loading:
            return Completer<Map<Object?, Object?>>().future;
          case _State.error:
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'preview',
            );
          case _State.denied:
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'preview',
            );
          case _State.empty:
            return {'schemaVersion': 2, 'items': [], 'nextCursor': null};
          case _State.populated:
            return {
              'schemaVersion': 2,
              'items': [
                _wire('immersive_1'),
                _wire('immersive_2'),
                _wire('immersive_3'),
              ],
              'nextCursor': null,
            };
        }
      case 'getReelMediaAccessV2':
        return {
          'schemaVersion': 2,
          // ReelService only accepts https grants on this host; nothing is
          // fetched because the still stand-in never opens the URL.
          'url':
              'https://storage.googleapis.com/yovoice-preview/${payload['reelId']}.mp4',
          'expiresAtMillis': DateTime.now()
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          'generation': '1',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      case 'getReelViewV2':
        final id = payload['reelId'] as String;
        return {
          'schemaVersion': 2,
          'reel': _wire(id),
          'comments': [
            {
              'schemaVersion': 1,
              'commentId': 'c1',
              'type': 'text',
              'authorId': 'author_2',
              'authorName': 'Marta Zielińska-Kowalczyk',
              'authorPhotoUrl': null,
              'text': 'Świetne ujęcie, aż chce się tam wrócić!',
              'durationSeconds': null,
              'createdAtMillis': 1900000100000,
            },
            {
              'schemaVersion': 1,
              'commentId': 'c2',
              'type': 'text',
              'authorId': 'author_1',
              'authorName': 'Marek Nowak',
              'authorPhotoUrl': null,
              'text':
                  'A longer comment that wraps onto several lines so the thread '
                  'layout can be checked with the keyboard open.',
              'durationSeconds': null,
              'createdAtMillis': 1900000200000,
            },
          ],
          'commentsTruncated': false,
          'nextCommentCursor': null,
        };
      case 'setReelLike':
        final id = payload['reelId'] as String;
        final wanted = payload['liked'] as bool;
        final changed = (liked[id] ?? false) != wanted;
        liked[id] = wanted;
        if (changed) likeCounts[id] = (likeCounts[id] ?? 0) + (wanted ? 1 : -1);
        return {
          'reelId': id,
          'liked': wanted,
          'changed': changed,
          'likeCount': likeCounts[id] ?? 0,
        };
      case 'recordReelViewedV2':
        return {'schemaVersion': 2};
      default:
        throw FirebaseFunctionsException(
          code: 'unimplemented',
          message: 'Preview has no "$name" callable.',
        );
    }
  }
}

/// The still stand-in for footage: no decoder runs in this preview.
Widget _still(BuildContext context, Uri mediaUri, Reel reel) {
  final seed = reel.id.hashCode % 3;
  final colors = switch (seed) {
    0 => const [Color(0xFF788B9A), Color(0xFFB18570), Color(0xFF263D3B)],
    1 => const [Color(0xFF3B2A5A), Color(0xFF8C4E7A), Color(0xFF1B1430)],
    _ => const [Color(0xFF244B5A), Color(0xFF6FA5A0), Color(0xFF14262B)],
  };
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.landscape_outlined, color: Colors.white54, size: 160),
          Text(
            'Fixture still · no decoder',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// App + shell
// ---------------------------------------------------------------------------

class _Fixtures {
  _Fixtures(_Config config)
    : id = config.fixtureId,
      home = _HomeFixture(state: config.state, longNames: config.longNames),
      voice = _VoiceFixture(state: config.state, longNames: config.longNames),
      reels = _ReelsFixture(state: config.state) {
    // Static caches keyed by uid / reel id would otherwise bleed the previous
    // fixture set into this one.
    ProfileService.resetCurrentProfileCache();
    ReelService.clearAllMediaAccessCaches();
  }

  final String id;
  final _HomeFixture home;
  final _VoiceFixture voice;
  final _ReelsFixture reels;

  Future<void> dispose() async {
    await home.dispose();
    await voice.dispose();
  }
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp({required this.initial});
  final _Config initial;

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  late _Config _config = widget.initial;
  late _Fixtures _fixtures = _Fixtures(_config);

  void _update(_Config next) {
    final rebuild = next.fixtureId != _config.fixtureId;
    setState(() {
      _config = next;
      if (rebuild) {
        unawaited(_fixtures.dispose());
        _fixtures = _Fixtures(next);
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: switch (_config.theme) {
      _Theme.system => ThemeMode.system,
      _Theme.dark => ThemeMode.dark,
      _Theme.pearl => ThemeMode.light,
    },
    locale: Locale(_config.polish ? 'pl' : 'en'),
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [appRouteObserver],
    // 200% is applied above the Navigator so sheets and dialogs scale too.
    // At 100% the system text size is left untouched, so the Simulator's
    // own Dynamic Type setting remains a valid second path.
    builder: (context, child) => _config.bigText
        ? MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          )
        : child!,
    home: _Shell(
      key: ValueKey(_fixtures.id),
      fixtures: _fixtures,
      config: _config,
      onConfig: _update,
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({
    required this.fixtures,
    required this.config,
    required this.onConfig,
    super.key,
  });

  final _Fixtures fixtures;
  final _Config config;
  final ValueChanged<_Config> onConfig;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late int _tab = _tabRequest.value;
  late final ValueNotifier<bool> _homeVisible = ValueNotifier<bool>(
    _tab == 0,
  );
  late final ValueNotifier<bool> _momentsVisible = ValueNotifier<bool>(
    _tab == _momentsSlot,
  );
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _lastAction.addListener(_showAction);
    _tabRequest.addListener(_syncTab);
    _reelsRequest.addListener(_syncFormat);
  }

  @override
  void dispose() {
    _lastAction.removeListener(_showAction);
    _tabRequest.removeListener(_syncTab);
    _reelsRequest.removeListener(_syncFormat);
    _homeVisible.dispose();
    _momentsVisible.dispose();
    super.dispose();
  }

  void _showAction() {
    final action = _lastAction.value;
    if (action == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Preview callback: $action'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _syncTab() {
    if (mounted && _tabRequest.value != _tab) _select(_tabRequest.value);
  }

  void _syncFormat() {
    if (mounted) setState(() {});
  }

  void _select(int index) {
    setState(() => _tab = index);
    _homeVisible.value = index == 0;
    _momentsVisible.value = index == _momentsSlot;
    _tabRequest.value = index;
  }

  Future<void> _openSettings() async {
    setState(() => _sheetOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      builder: (_) => _SettingsSheet(
        config: widget.config,
        onConfig: widget.onConfig,
        onSelectTab: (index, {reels}) {
          if (reels != null) _reelsRequest.value = reels;
          _tabRequest.value = index;
        },
      ),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  int get _stackIndex => switch (_tab) {
    0 => 0,
    _roomsSlot => 1,
    _chatsSlot => 2,
    _ => 3,
  };

  Widget _content({required bool desktop}) => FutureBuilder<void>(
    future: widget.fixtures.home.ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      final f = widget.fixtures;
      return IndexedStack(
        index: _stackIndex,
        children: [
          f.home.home(desktop: desktop, visible: _homeVisible),
          const _OutOfScope('Rooms'),
          const _OutOfScope('Chats'),
          MomentsScreen(
            key: ValueKey(
              'redesign-moments-${_reelsRequest.value ? 'reels' : 'voice'}',
            ),
            isRootTab: true,
            isVisible: _momentsVisible,
            initialFormat: _reelsRequest.value
                ? YoMomentsFormat.reels
                : YoMomentsFormat.voice,
            momentService: f.voice.moments,
            feedService: f.voice.feed,
            discoveryService: f.voice.discovery,
            viewsService: f.voice.views,
            auth: f.voice.auth,
            playerFactory: f.voice.newPlayer,
            onOpenDetail: (moment) => _report('moment-detail:${moment.id}'),
            reelService: f.reels.service,
            reelVideoBuilder: _still,
            onCreateReel: () async => _report('create-reel'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    // The production shell's predicate (MainShell.usesDesktopLayout), spelled
    // out: the rail also needs enough logical height.
    final desktop =
        viewport.width >= MainShell.desktopBreakpoint &&
        viewport.height >= DesktopSidebar.minimumSupportedHeight;
    final background = Theme.of(context).scaffoldBackgroundColor;
    if (desktop) {
      return Scaffold(
        backgroundColor: background,
        body: Row(
          children: [
            DesktopSidebar(
              active: switch (_tab) {
                0 => DesktopNavItem.home,
                _momentsSlot => DesktopNavItem.moments,
                _chatsSlot => DesktopNavItem.chats,
                _roomsSlot => DesktopNavItem.discover,
                _ => null,
              },
              unreadConversationCount: 2,
              unreadNotificationCount: 2,
              onSelect: (item) => switch (item) {
                DesktopNavItem.home => _select(0),
                DesktopNavItem.moments => _select(_momentsSlot),
                DesktopNavItem.chats => _select(_chatsSlot),
                DesktopNavItem.discover => _select(_roomsSlot),
                DesktopNavItem.more => unawaited(_openSettings()),
                _ => _report('rail:${item.name}'),
              },
              onCreateRoom: () => _report('create-room'),
              onCreateMoment: () => _report('record-moment'),
              onOpenProfile: () => _report('profile'),
              onOpenProfileSettings: () => _report('profile-settings'),
              profileService: widget.fixtures.home.profileService,
              capabilityService: _Capabilities(),
            ),
            Expanded(
              child: ResponsiveContentFrame(
                width: ResponsiveContentWidth.workbench,
                child: _content(desktop: true),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: background,
      body: _content(desktop: false),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The production shell mounts RoomMiniBar (the active-call capsule)
          // above the dock here; it renders nothing without a live room
          // connection, which this preview never creates.
          YoFloatingNavigationDock(
            selectedTabIndex: _tab,
            roomsTabIndex: _roomsSlot,
            momentsTabIndex: _momentsSlot,
            unreadConversationCount: 2,
            onDestinationSelected: _select,
            onVoicePressed: () => _report('voice'),
            onMorePressed: () => unawaited(_openSettings()),
            moreSelected: _sheetOpen,
          ),
        ],
      ),
    );
  }
}

class _OutOfScope extends StatelessWidget {
  const _OutOfScope(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '$label is outside slice F1 — preview placeholder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary),
        ),
      ),
    );
  }
}

/// Harness controls, kept out of the reviewed screens' own chrome.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.config,
    required this.onConfig,
    required this.onSelectTab,
  });

  final _Config config;
  final ValueChanged<_Config> onConfig;
  final void Function(int index, {bool? reels}) onSelectTab;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late _Config _config = widget.config;

  void _apply(_Config next) {
    setState(() => _config = next);
    widget.onConfig(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final label = TextStyle(
      color: palette.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Redesign preview — fixtures only',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text('DATA STATE', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final state in _State.values)
                  ChoiceChip(
                    label: Text(state.name),
                    selected: _config.state == state,
                    onSelected: (_) => _apply(_config.copyWith(state: state)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('THEME', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final theme in _Theme.values)
                  ChoiceChip(
                    label: Text(theme.name),
                    selected: _config.theme == theme,
                    onSelected: (_) => _apply(_config.copyWith(theme: theme)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('LANGUAGE', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Polski'),
                  selected: _config.polish,
                  onSelected: (_) => _apply(_config.copyWith(polish: true)),
                ),
                ChoiceChip(
                  label: const Text('English'),
                  selected: !_config.polish,
                  onSelected: (_) => _apply(_config.copyWith(polish: false)),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('200% text'),
              value: _config.bigText,
              onChanged: (value) => _apply(_config.copyWith(bigText: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Long names and titles'),
              value: _config.longNames,
              onChanged: (value) => _apply(_config.copyWith(longNames: value)),
            ),
            const SizedBox(height: 8),
            Text('GO TO', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: () {
                    widget.onSelectTab(0);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Home'),
                ),
                OutlinedButton(
                  onPressed: () {
                    widget.onSelectTab(_momentsSlot, reels: false);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Voice'),
                ),
                OutlinedButton(
                  onPressed: () {
                    widget.onSelectTab(_momentsSlot, reels: true);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Reels'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
