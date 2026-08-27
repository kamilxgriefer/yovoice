import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';

/// THE LOAD-BEARING SCREEN ASSERTION.
///
/// A room screen must not ask for a LiveKit token while the room document
/// says the session does not exist, and must not offer a mute control into
/// one. Both are observable here because the audio service is now
/// substitutable: the production singleton hides behind a private
/// constructor, and `VoiceCallService.forTesting()` is the seam that lets a
/// recording stand-in answer "was a token requested?".
class _RecordingVoice extends VoiceCallService {
  _RecordingVoice({this.muted = false}) : super.forTesting();

  final bool muted;
  final List<String> joins = [];
  final List<bool> joinSoundFlags = [];
  final List<String> disconnects = [];
  bool _connected = false;
  String? _joinedRoom;

  @override
  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
    bool playSound = true,
  }) async {
    joins.add(roomId);
    joinSoundFlags.add(playSound);
    _joinedRoom = roomId;
    _connected = true;
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool playSound = true}) async {
    disconnects.add(_joinedRoom ?? '');
    _connected = false;
    _joinedRoom = null;
    notifyListeners();
  }

  @override
  String? get roomId => _joinedRoom;

  @override
  bool get isConnected => _connected;

  @override
  bool get isMuted => muted;

  @override
  MicState get micState => _connected
      ? (muted ? MicState.muted : MicState.on)
      : MicState.unavailable;

  @override
  List<VoiceParticipantViewData> get participants =>
      const <VoiceParticipantViewData>[];
}

void main() {
  const roomId = 'room-1';
  late FakeFirebaseFirestore db;

  RoomService serviceFor(String uid) => RoomService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: uid),
    ),
  );

  /// A coordinator that records rather than writing, so a screen-level test
  /// can assert on the ORDER without a backend.
  ({RoomVoiceEntryCoordinator coordinator, List<String> events}) recorder({
    required RoomVoiceEntry result,
  }) {
    final events = <String>[];
    return (
      coordinator: RoomVoiceEntryCoordinator(
        readRoom: (id) async {
          events.add('read');
          return result.room;
        },
        resolveAuthority: (_) async {
          events.add('authority');
          return result.authority;
        },
        startVoice: (id) async => events.add('start'),
        joinRoom: (id) async {
          events.add('join');
          return result.room;
        },
      ),
      events: events,
    );
  }

  Future<void> seedRoom({required bool isLive, String? clubId}) async {
    await db.collection('rooms').doc(clubId ?? roomId).set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'The Family Lounge',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 0,
      'memberCount': 0,
      'isLive': isLive,
      'status': 'active',
    });
  }

  VoiceRoom roomModel({
    required bool isLive,
    String id = roomId,
    String? clubId,
  }) => VoiceRoom(
    id: id,
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: 'The Family Lounge',
    description: '',
    category: 'talk',
    visibility: 'public',
    language: 'English',
    maxParticipants: null,
    participantCount: 0,
    memberCount: 0,
    isLive: isLive,
    roomType: RoomType.community,
    status: RoomStatus.active,
    imageUrl: null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: true,
    membersCanStartVoice: true,
    createdAt: null,
    updatedAt: null,
    clubId: clubId,
  );

  Future<void> pumpCommunity(
    WidgetTester tester, {
    required RoomVoiceEntry entry,
    required _RecordingVoice voice,
    required String uid,
    RoomVoiceEntryCoordinator? coordinator,
    ClubService? clubService,
    bool playInitialJoinSound = true,
    Size size = const Size(420, 900),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CommunityVoiceRoomScreen(
          room: entry.room,
          voiceEntry: entry,
          roomService: serviceFor(uid),
          voiceService: voice,
          entryCoordinator: coordinator,
          clubService: clubService,
          playInitialJoinSound: playInitialJoinSound,
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('relative').set({
      'displayName': 'relative',
      'photoUrl': null,
    });
  });

  group('community room', () {
    testWidgets(
      'a dormant room this account cannot start requests NO token and offers '
      'NO mute control',
      (tester) async {
        await seedRoom(isLive: false);
        final voice = _RecordingVoice();

        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: voice,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.none,
            message: 'Voice has not started here yet.',
          ),
        );

        expect(
          voice.joins,
          isEmpty,
          reason:
              'createLiveKitToken refuses a dormant room; asking anyway is '
              'the reported "This room is not currently live."',
        );
        expect(find.text('Mute'), findsNothing);
        expect(find.text('Unmute'), findsNothing);
        expect(find.text('Not live'), findsOneWidget);
        expect(find.text('NOT LIVE YET'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the honest not-live control explains instead of failing',
      (tester) async {
        await seedRoom(isLive: false);
        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: _RecordingVoice(),
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.none,
          ),
        );

        await tester.tap(find.text('Not live'));
        await tester.pump();

        expect(
          find.text(
            'Voice has not started here yet — the host opens the mics.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a dormant room this account MAY start offers exactly one control, and '
      'the transition runs before any token is requested',
      (tester) async {
        await seedRoom(isLive: false);
        final voice = _RecordingVoice();
        final rec = recorder(
          result: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.started,
            room: roomModel(isLive: true),
            authority: RoomVoiceStartAuthority.clubMember,
          ),
        );

        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: voice,
          coordinator: rec.coordinator,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.clubMember,
          ),
        );

        expect(find.text('Start voice'), findsOneWidget);
        expect(find.text('Mute'), findsNothing);
        expect(voice.joins, isEmpty);

        await tester.tap(find.text('Start voice'));
        await tester.pump();
        await tester.pump();

        expect(rec.events, ['read', 'join']);
        expect(
          voice.joins,
          [roomId],
          reason: 'the token is requested only after the entry path resolved',
        );
      },
    );

    testWidgets('a live room that is muted offers Unmute — the control the '
        'product owner pressed, now against a room that really is live', (
      tester,
    ) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice(muted: true);

      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Not live'), findsNothing);
    });

    testWidgets('a live room connects and offers the real mute control', (
      tester,
    ) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice();

      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Not live'), findsNothing);
      expect(find.text('Start voice'), findsNothing);
    });

    testWidgets('room creation can consume the initial join cue', (
      tester,
    ) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice();

      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.none,
        ),
        playInitialJoinSound: false,
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(voice.joinSoundFlags, [false]);
    });

    testWidgets(
      'a Family Room lounge keeps its identity line and still says it is not '
      'live',
      (tester) async {
        await db.collection('rooms').doc('club_lounge_family_host').set({
          'hostId': 'host',
          'hostName': 'Host',
          'name': 'The Family Lounge',
          'description': '',
          'category': 'club',
          'visibility': 'private',
          'language': 'English',
          'participantCount': 0,
          'memberCount': 0,
          'isLive': false,
          'status': 'active',
        });
        await db.collection('clubs').doc('family_host').set({
          'name': 'The Family',
          'description': 'Our private place',
          'ownerId': 'host',
          'ownerName': 'Host',
          'avatarUrl': null,
          'bannerUrl': null,
          'privacy': 'inviteOnly',
          'type': 'family',
          'defaultLanguage': 'English',
          'memberCount': 2,
          'onlineCount': 1,
        });

        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: _RecordingVoice(),
          clubService: ClubService(
            firestore: db,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'relative'),
            ),
            storage: MockFirebaseStorage(),
          ),
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(
              isLive: false,
              id: 'club_lounge_family_host',
              clubId: 'family_host',
            ),
            authority: RoomVoiceStartAuthority.clubMember,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('FAMILY ROOM · NOT LIVE YET'), findsOneWidget);
        expect(find.text('Start voice'), findsOneWidget);
      },
    );
    testWidgets(
      'a refused entry says why on arrival instead of failing silently',
      (tester) async {
        await seedRoom(isLive: false);
        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: _RecordingVoice(),
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.failed,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.roomMember,
            message: 'This room is full.',
          ),
        );
        await tester.pump();

        expect(find.text('This room is full.'), findsOneWidget);
        // The authority is real, so the retry stays offered.
        expect(find.text('Start voice'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'a room that ENDS underneath shows the ended state, never a Start '
    'control on a dead room',
    (tester) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice();
      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.roomMember,
        ),
      );
      await tester.pump();
      expect(find.text('Mute'), findsOneWidget);

      // The host closes it. `isActive` is false AND `isLive` is false, and
      // the second must not be read as "dormant, you may start it".
      await db.collection('rooms').doc(roomId).update({
        'status': 'closed',
        'isLive': false,
      });
      await tester.pump();
      await tester.pump();

      expect(find.text('This room has ended'), findsOneWidget);
      expect(find.text('Start voice'), findsNothing);
      expect(find.text('NOT LIVE YET'), findsNothing);
    },
  );

  testWidgets(
    'a room going live in the BACKGROUND never steals the audio session '
    'the user is having somewhere else',
    (tester) async {
      await seedRoom(isLive: false);
      // The user is live in another room; VoiceCallService is a singleton
      // and join() disconnects whatever is connected.
      final voice = _RecordingVoice();
      await voice.join(
        roomId: 'a-room-the-user-is-actually-in',
        roomName: 'Elsewhere',
        participantName: 'Kamil',
      );
      voice.joins.clear();

      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: roomModel(isLive: false),
          authority: RoomVoiceStartAuthority.roomMember,
        ),
      );

      await db.collection('rooms').doc(roomId).update({'isLive': true});
      await tester.pump();
      await tester.pump();

      expect(
        voice.joins,
        isEmpty,
        reason: 'this screen does not own the session and must not take it',
      );
      expect(voice.roomId, 'a-room-the-user-is-actually-in');
    },
  );

  testWidgets(
    'a room going dormant in the BACKGROUND never hangs up the session the '
    'user is having somewhere else',
    (tester) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice();

      // The real sequence: this screen mounts and connects, the user then
      // walks into another room (whose join() takes the singleton over),
      // and THIS room — still mounted underneath the pushed route — goes
      // dormant behind them.
      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.roomMember,
        ),
      );
      await tester.pump();
      expect(voice.joins, [roomId]);

      await voice.join(
        roomId: 'a-room-the-user-walked-into',
        roomName: 'Elsewhere',
        participantName: 'Kamil',
      );
      voice.disconnects.clear();

      await db.collection('rooms').doc(roomId).update({'isLive': false});
      await tester.pump();
      await tester.pump();

      expect(
        voice.disconnects,
        isEmpty,
        reason: 'this screen no longer owns the session and must not cut it',
      );
      expect(voice.roomId, 'a-room-the-user-walked-into');
      expect(voice.isConnected, isTrue);
    },
  );

  testWidgets('a room it DOES own is disconnected when voice ends', (
    tester,
  ) async {
    await seedRoom(isLive: true);
    final voice = _RecordingVoice();

    await pumpCommunity(
      tester,
      uid: 'relative',
      voice: voice,
      entry: RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.live,
        room: roomModel(isLive: true),
        authority: RoomVoiceStartAuthority.roomMember,
      ),
    );
    await tester.pump();
    expect(voice.joins, [roomId]);

    await db.collection('rooms').doc(roomId).update({'isLive': false});
    await tester.pump();
    await tester.pump();

    expect(voice.disconnects, [roomId]);
    expect(find.text('Start voice'), findsOneWidget);
  });

  group('responsive', () {
    // Every width the product supports, plus the accessibility case. The
    // dormant states are new, so they carry the same "no overflow, control
    // still reachable" bar every other room control already meets.
    for (final width in const [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
      testWidgets('a startable dormant room fits ${width.toInt()}px', (
        tester,
      ) async {
        await seedRoom(isLive: false);
        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: _RecordingVoice(),
          size: Size(width, 900),
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.roomMember,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Start voice'), findsOneWidget);
      });

      testWidgets('a waiting dormant room fits ${width.toInt()}px', (
        tester,
      ) async {
        await seedRoom(isLive: false);
        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: _RecordingVoice(),
          size: Size(width, 900),
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.none,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Not live'), findsOneWidget);
      });
    }

    testWidgets(
      'the narrowest supported width at 200% text still shows the control',
      (tester) async {
        await seedRoom(isLive: false);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 844);
        addTearDown(tester.view.reset);

        final model = roomModel(isLive: false);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CommunityVoiceRoomScreen(
              room: model,
              voiceEntry: RoomVoiceEntry(
                outcome: RoomVoiceEntryOutcome.dormant,
                room: model,
                authority: RoomVoiceStartAuthority.clubMember,
              ),
              roomService: serviceFor('relative'),
              voiceService: _RecordingVoice(),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Start voice'), findsOneWidget);
      },
    );
  });

  group('broadcast room', () {
    Future<void> pumpBroadcast(
      WidgetTester tester, {
      required RoomVoiceEntry entry,
      required _RecordingVoice voice,
      Size size = const Size(420, 900),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: BroadcastRoomScreen(
            room: entry.room,
            voiceEntry: entry,
            roomService: serviceFor('relative'),
            voiceService: voice,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'a dormant broadcast offers neither a mic nor a raise-hand into a show '
      'that has not started',
      (tester) async {
        await seedRoom(isLive: false);
        final voice = _RecordingVoice();

        await pumpBroadcast(
          tester,
          voice: voice,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false),
            authority: RoomVoiceStartAuthority.none,
          ),
        );

        expect(voice.joins, isEmpty);
        expect(find.text('Not live'), findsOneWidget);
        expect(find.text('Mute'), findsNothing);
        expect(find.text('Unmute'), findsNothing);
        expect(find.text('Raise hand'), findsNothing);
      },
    );

    testWidgets('a dormant broadcast its host may start says so', (
      tester,
    ) async {
      await seedRoom(isLive: false);

      await pumpBroadcast(
        tester,
        voice: _RecordingVoice(),
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: roomModel(isLive: false),
          authority: RoomVoiceStartAuthority.host,
        ),
      );

      expect(find.text('Start voice'), findsOneWidget);
      expect(find.text('Mute'), findsNothing);
    });

    testWidgets('a live broadcast connects', (tester) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice();

      await pumpBroadcast(
        tester,
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(find.text('Not live'), findsNothing);
    });
  });
}
