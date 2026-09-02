import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

/// THE LOAD-BEARING SCREEN ASSERTION.
///
/// A room screen must not ask for a LiveKit token while the room document
/// says the session does not exist, and must not offer a mute control into
/// one. Both are observable here because the audio service is now
/// substitutable: the production singleton hides behind a private
/// constructor, and `VoiceCallService.forTesting()` is the seam that lets a
/// recording stand-in answer "was a token requested?".
class _PermissionGateway implements AppPermissionPlatformGateway {
  const _PermissionGateway(this.access, [this.requests, this.requestAccess]);

  final AppPermissionAccess access;
  final List<AppPermissionKind>? requests;
  final AppPermissionAccess? requestAccess;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    requests?.add(permission);
    return requestAccess ?? access;
  }

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async =>
      access;
}

class _RecordingVoice extends VoiceCallService {
  _RecordingVoice({
    this.muted = false,
    this.cast = const <VoiceParticipantViewData>[],
    AppPermissionAccess permission = AppPermissionAccess.granted,
    List<AppPermissionKind>? permissionRequests,
    AppPermissionAccess? permissionRequestResult,
    bool? canPublish,
    this.publishOnReconnect = false,
  }) : _canPublishOverride = canPublish,
       super.forTesting(
         permissionReadiness: PermissionReadinessService(
           platform: _PermissionGateway(
             permission,
             permissionRequests,
             permissionRequestResult,
           ),
         ),
       );

  final bool muted;
  final List<VoiceParticipantViewData> cast;
  final List<String> joins = [];
  final List<bool> joinSoundFlags = [];
  final List<bool> joinMutedFlags = [];
  final List<String> disconnects = [];
  final bool publishOnReconnect;
  bool _connected = false;
  String? _joinedRoom;
  bool? _canPublishOverride;

  @override
  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
    bool playSound = true,
    bool startMuted = false,
  }) async {
    joins.add(roomId);
    joinSoundFlags.add(playSound);
    joinMutedFlags.add(startMuted);
    if (publishOnReconnect && joins.length > 1) {
      _canPublishOverride = true;
    }
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
  bool get canPublish => _canPublishOverride ?? super.canPublish;

  @override
  bool get isMuted => muted;

  @override
  MicState get micState {
    if (!_connected) return MicState.unavailable;
    if (_canPublishOverride == false) return MicState.listenOnly;
    return muted ? MicState.muted : MicState.on;
  }

  @override
  List<VoiceParticipantViewData> get participants => cast;

  void replaceSessionForTest(String roomId) {
    _joinedRoom = roomId;
    _connected = true;
    notifyListeners();
  }
}

class _ServerRefusal extends FirebaseFunctionsException {
  _ServerRefusal(String code) : super(code: code, message: 'refused');
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
    roomVoiceStartInvoker: (request) async {
      final targetRoomId = request['roomId']! as String;
      await db.collection('rooms').doc(targetRoomId).update({
        'isLive': true,
        'voiceSessionId': request['sessionId'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return <Object?, Object?>{
        'schemaVersion': 1,
        'started': true,
        'roomId': targetRoomId,
        'sessionId': request['sessionId'],
      };
    },
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
        joinRoom: (id, {startMuted = false}) async {
          events.add('join');
          return result.room;
        },
      ),
      events: events,
    );
  }

  Future<void> seedRoom({
    required bool isLive,
    String? clubId,
    String experience = 'community',
    String topic = '',
    bool handRaisingEnabled = true,
  }) async {
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
      'experience': experience,
      'topic': topic,
      'showFormat': experience == 'broadcast' ? 'interview' : null,
      'handRaisingEnabled': handRaisingEnabled,
    });
  }

  VoiceRoom roomModel({
    required bool isLive,
    String id = roomId,
    String? clubId,
    String experience = 'community',
    String topic = '',
    bool handRaisingEnabled = true,
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
    experience: experience,
    topic: topic,
    showFormat: experience == 'broadcast' ? ShowFormat.interview : null,
    handRaisingEnabled: handRaisingEnabled,
  );

  Future<void> pumpCommunity(
    WidgetTester tester, {
    required RoomVoiceEntry entry,
    required _RecordingVoice voice,
    required String uid,
    RoomVoiceEntryCoordinator? coordinator,
    RoomMuteCoordinator? muteCoordinator,
    ClubService? clubService,
    bool playInitialJoinSound = true,
    bool startMuted = false,
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
          muteCoordinator: muteCoordinator,
          clubService: clubService,
          playInitialJoinSound: playInitialJoinSound,
          startMuted: startMuted,
        ),
      ),
    );
    await tester.pump();
  }

  group('explicit prejoin', () {
    testWidgets(
      'preview is passive until CTA and repeated taps start one entry flow',
      (tester) async {
        await seedRoom(isLive: true);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final readGate = Completer<VoiceRoom>();
        final joinGate = Completer<VoiceRoom>();
        final events = <String>[];
        bool? rosterStartedMuted;
        final coordinator = RoomVoiceEntryCoordinator(
          readRoom: (id) {
            events.add('read:$id');
            return readGate.future;
          },
          resolveAuthority: (_) async {
            events.add('authority');
            return RoomVoiceStartAuthority.host;
          },
          startVoice: (id) async => events.add('start:$id'),
          joinRoom: (id, {startMuted = false}) async {
            events.add('join:$id');
            rosterStartedMuted = startMuted;
            return joinGate.future;
          },
        );

        final voice = _RecordingVoice();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: RoomEntryScreen(
              room: roomModel(isLive: true),
              coordinator: coordinator,
              roomService: serviceFor('guest'),
              voiceService: voice,
            ),
          ),
        );
        await tester.pump();

        expect(events, isEmpty);
        expect(find.text('The Family Lounge'), findsOneWidget);
        expect(find.text('Host'), findsOneWidget);
        expect(find.text('Live now'), findsOneWidget);
        expect(find.text('Microphone off'), findsOneWidget);
        expect(find.text('Join conversation'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
        await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
        await tester.pump();

        expect(events, ['read:room-1']);
        expect(find.text('Joining…'), findsOneWidget);
        expect(find.byType(CommunityVoiceRoomScreen), findsNothing);

        readGate.complete(roomModel(isLive: true));
        await tester.pump();
        await tester.pump();

        expect(rosterStartedMuted, isTrue);
        expect(find.byType(CommunityVoiceRoomScreen), findsNothing);

        joinGate.complete(roomModel(isLive: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.byType(CommunityVoiceRoomScreen), findsOneWidget);
        expect(voice.joinMutedFlags, <bool>[true]);
      },
    );

    testWidgets('prejoin CTA and mic safety copy are natural in Polish', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final recorded = recorder(
        result: RoomVoiceEntry.unresolved(roomModel(isLive: false)),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData.dark(useMaterial3: true),
          home: RoomEntryScreen(
            room: roomModel(isLive: false),
            coordinator: recorded.coordinator,
          ),
        ),
      );
      await tester.pump();

      expect(recorded.events, isEmpty);
      expect(find.text('Zanim dołączysz'), findsOneWidget);
      expect(find.text('Mikrofon wyłączony'), findsOneWidget);
      expect(find.text('Dołącz do rozmowy'), findsOneWidget);
      expect(find.text('Gotowy, gdy gospodarz rozpocznie'), findsOneWidget);
    });

    testWidgets('failed entry stays on preview and offers a safe retry', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      var reads = 0;
      final liveRoom = roomModel(isLive: true);
      final coordinator = RoomVoiceEntryCoordinator(
        readRoom: (_) async {
          reads += 1;
          return liveRoom;
        },
        resolveAuthority: (_) async => RoomVoiceStartAuthority.none,
        startVoice: (_) async {},
        joinRoom: (_, {startMuted = false}) async =>
            throw StateError('This room is full.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: RoomEntryScreen(
            room: liveRoom,
            coordinator: coordinator,
            voiceService: _RecordingVoice(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
      await tester.pumpAndSettle();

      expect(reads, 1);
      expect(find.byKey(const ValueKey('room-prejoin-error')), findsOneWidget);
      expect(find.text('This room is full.'), findsOneWidget);
      expect(find.text('Join conversation'), findsOneWidget);
      expect(find.byType(CommunityVoiceRoomScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
      await tester.pumpAndSettle();
      expect(reads, 2);
    });

    testWidgets('denied microphone access creates no roster entry', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final recorded = recorder(
        result: RoomVoiceEntry.unresolved(roomModel(isLive: true)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: RoomEntryScreen(
            room: roomModel(isLive: true),
            coordinator: recorded.coordinator,
            voiceService: _RecordingVoice(
              permission: AppPermissionAccess.denied,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
      await tester.pumpAndSettle();

      expect(recorded.events, isEmpty);
      expect(find.byKey(const ValueKey('room-prejoin-error')), findsOneWidget);
      expect(
        find.text(
          'Microphone access is needed to join. Enable it and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'broadcast listener joins listen-only when microphone is denied',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final broadcast = roomModel(isLive: true, experience: 'broadcast');
        final events = <String>[];
        final permissionRequests = <AppPermissionKind>[];
        final coordinator = RoomVoiceEntryCoordinator(
          readRoom: (_) async {
            events.add('read');
            return broadcast;
          },
          resolveAuthority: (_) async => RoomVoiceStartAuthority.none,
          startVoice: (_) async => events.add('start'),
          joinRoom: (_, {startMuted = false}) async {
            events.add('join');
            return broadcast;
          },
          currentUserId: () => 'listener',
        );
        final voice = _RecordingVoice(
          permission: AppPermissionAccess.denied,
          permissionRequests: permissionRequests,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: RoomEntryScreen(
              room: broadcast,
              coordinator: coordinator,
              roomService: serviceFor('listener'),
              voiceService: voice,
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
        await tester.pumpAndSettle();

        expect(events, <String>['read', 'join']);
        expect(find.byType(BroadcastRoomScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('room-prejoin-error')), findsNothing);
        expect(voice.joins, <String>[roomId]);
        expect(voice.canPublish, isFalse);
        expect(permissionRequests, isEmpty);
      },
    );

    testWidgets(
      'broadcast host still needs microphone before the roster write',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final broadcast = roomModel(isLive: true, experience: 'broadcast');
        final events = <String>[];
        final permissionRequests = <AppPermissionKind>[];
        final coordinator = RoomVoiceEntryCoordinator(
          readRoom: (_) async {
            events.add('read');
            return broadcast;
          },
          resolveAuthority: (_) async => RoomVoiceStartAuthority.host,
          startVoice: (_) async => events.add('start'),
          joinRoom: (_, {startMuted = false}) async {
            events.add('join');
            return broadcast;
          },
          currentUserId: () => 'host',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: RoomEntryScreen(
              room: broadcast,
              coordinator: coordinator,
              voiceService: _RecordingVoice(
                permission: AppPermissionAccess.denied,
                permissionRequests: permissionRequests,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('room-prejoin-join')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('room-prejoin-error')),
          findsOneWidget,
        );
        expect(find.byType(BroadcastRoomScreen), findsNothing);
        expect(permissionRequests, <AppPermissionKind>[
          AppPermissionKind.microphone,
        ]);
        expect(events, isEmpty);
      },
    );

    test('RoomEntryScreen defaults every route to a muted entry', () {
      final screen = RoomEntryScreen(room: roomModel(isLive: true));
      expect(screen.startMuted, isTrue);
    });
  });

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('relative').set({
      'displayName': 'relative',
      'photoUrl': null,
    });
  });

  group('community room', () {
    testWidgets('compact chat starts docked and can close and reopen', (
      tester,
    ) async {
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
        size: const Size(390, 844),
      );

      expect(find.byKey(const ValueKey('room-stage-pane')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Back to stage'));
      await tester.pump();
      expect(find.byKey(const ValueKey('room-stage-pane')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsNothing,
      );

      await tester.tap(find.text('Chat'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsOneWidget,
      );
    });

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

    testWidgets('a security-sensitive room entry requests a muted join', (
      tester,
    ) async {
      await seedRoom(isLive: true);
      final voice = _RecordingVoice(muted: true);

      await pumpCommunity(
        tester,
        uid: 'relative',
        voice: voice,
        startMuted: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(voice.joinMutedFlags, [isTrue]);
      expect(find.text('Unmute'), findsOneWidget);
    });

    testWidgets(
      'a delayed Community unmute cannot enable the replacement room mic',
      (tester) async {
        await seedRoom(isLive: true);
        final voice = _RecordingVoice(muted: true);
        final rosterGate = Completer<void>();
        final events = <String>[];
        final muteCoordinator = RoomMuteCoordinator(
          persistRosterState: (roomId, muted) async {
            events.add('persist:$roomId:$muted');
            await rosterGate.future;
          },
          applyMicrophoneState: (muted) async {
            events.add('apply:$muted');
          },
          readCurrentMuted: () => true,
          disconnectStaleSession: () async => events.add('disconnect'),
        );
        addTearDown(muteCoordinator.dispose);

        await pumpCommunity(
          tester,
          uid: 'relative',
          voice: voice,
          muteCoordinator: muteCoordinator,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.live,
            room: roomModel(isLive: true),
            authority: RoomVoiceStartAuthority.none,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Unmute'));
        await tester.pump();
        expect(events, ['persist:$roomId:false']);

        voice.replaceSessionForTest('room-2');
        rosterGate.complete();
        await tester.pump();

        expect(events, [
          'persist:$roomId:false',
        ], reason: 'Room A must not apply its delayed unmute to room B.');
      },
    );

    testWidgets(
      'Community shows one connected people count and no listener layer',
      (tester) async {
        await seedRoom(isLive: true);
        final participants = db
            .collection('rooms')
            .doc(roomId)
            .collection('participants');
        for (final (id, name, role) in const [
          ('host', 'Host', 'host'),
          ('relative', 'Relative', 'speaker'),
          ('ghost', 'Disconnected', 'listener'),
        ]) {
          await participants.doc(id).set({
            'userId': id,
            'displayName': name,
            'role': role,
            'isMuted': false,
            'isSpeaker': role != 'listener',
            'isHandRaised': false,
          });
        }
        final voice = _RecordingVoice(
          cast: const [
            VoiceParticipantViewData(
              identity: 'host',
              displayName: 'Host',
              isLocal: false,
              isSpeaking: false,
              audioLevel: 0,
              isMuted: false,
            ),
            VoiceParticipantViewData(
              identity: 'relative',
              displayName: 'Relative',
              isLocal: true,
              isSpeaking: true,
              audioLevel: .4,
              isMuted: false,
            ),
          ],
        );

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
        await tester.pump();

        expect(find.textContaining('In room'), findsOneWidget);
        expect(find.text('People here'), findsOneWidget);
        expect(find.text('Disconnected'), findsNothing);
        expect(find.text('Listening'), findsNothing);
        expect(find.byIcon(Icons.headphones_rounded), findsNothing);
      },
    );

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
      String uid = 'relative',
      RoomMuteCoordinator? muteCoordinator,
      bool startMuted = false,
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
            roomService: serviceFor(uid),
            voiceService: voice,
            muteCoordinator: muteCoordinator,
            startMuted: startMuted,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('compact podcast chat starts docked and can close and reopen', (
      tester,
    ) async {
      await seedRoom(isLive: false, experience: 'broadcast');
      await pumpBroadcast(
        tester,
        voice: _RecordingVoice(),
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: roomModel(isLive: false, experience: 'broadcast'),
          authority: RoomVoiceStartAuthority.none,
        ),
        size: const Size(390, 844),
      );

      expect(find.byKey(const ValueKey('room-stage-pane')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back to stage'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsNothing,
      );
      await tester.tap(find.text('Chat'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('room-compact-chat-dock')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a dormant broadcast offers neither a mic nor a raise-hand into a show '
      'that has not started',
      (tester) async {
        await seedRoom(isLive: false, experience: 'broadcast');
        final voice = _RecordingVoice();

        await pumpBroadcast(
          tester,
          voice: voice,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.dormant,
            room: roomModel(isLive: false, experience: 'broadcast'),
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
      await seedRoom(isLive: false, experience: 'broadcast');

      await pumpBroadcast(
        tester,
        voice: _RecordingVoice(),
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: roomModel(isLive: false, experience: 'broadcast'),
          authority: RoomVoiceStartAuthority.host,
        ),
      );

      expect(find.text('Start voice'), findsOneWidget);
      expect(find.text('Mute'), findsNothing);
    });

    testWidgets('a live broadcast connects', (tester) async {
      await seedRoom(
        isLive: true,
        experience: 'broadcast',
        topic: 'The future of independent audio',
      );
      final voice = _RecordingVoice();

      await pumpBroadcast(
        tester,
        voice: voice,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(
            isLive: true,
            experience: 'broadcast',
            topic: 'The future of independent audio',
          ),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(find.text('Not live'), findsNothing);
      expect(find.text('The future of independent audio'), findsOneWidget);
      expect(find.textContaining('On stage', findRichText: true), findsWidgets);
      expect(find.textContaining('Audience', findRichText: true), findsWidgets);
    });

    testWidgets('a security-sensitive broadcast entry requests a muted join', (
      tester,
    ) async {
      await seedRoom(isLive: true, experience: 'broadcast');
      final voice = _RecordingVoice(muted: true);

      await pumpBroadcast(
        tester,
        voice: voice,
        startMuted: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: roomModel(isLive: true, experience: 'broadcast'),
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(voice.joins, [roomId]);
      expect(voice.joinMutedFlags, [isTrue]);
    });

    testWidgets(
      'a promoted listener asks for microphone access only from the mic tap',
      (tester) async {
        await seedRoom(isLive: true, experience: 'broadcast');
        await db
            .collection('rooms')
            .doc(roomId)
            .collection('participants')
            .doc('relative')
            .set({
              'userId': 'relative',
              'displayName': 'relative',
              'role': 'speaker',
              'isMuted': true,
              'isSpeaker': true,
              'isHandRaised': false,
            });
        final permissionRequests = <AppPermissionKind>[];
        final voice = _RecordingVoice(
          muted: true,
          permission: AppPermissionAccess.denied,
          permissionRequests: permissionRequests,
          canPublish: false,
        );
        final muteEvents = <String>[];
        final muteCoordinator = RoomMuteCoordinator(
          persistRosterState: (roomId, muted) async {
            muteEvents.add('persist:$roomId:$muted');
          },
          applyMicrophoneState: (muted) async {
            muteEvents.add('apply:$muted');
          },
          readCurrentMuted: () => true,
          disconnectStaleSession: () async {},
        );
        addTearDown(muteCoordinator.dispose);

        await pumpBroadcast(
          tester,
          voice: voice,
          muteCoordinator: muteCoordinator,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.live,
            room: roomModel(isLive: true, experience: 'broadcast'),
            authority: RoomVoiceStartAuthority.none,
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(permissionRequests, isEmpty);
        expect(voice.disconnects, isEmpty);
        expect(find.text('Listening'), findsOneWidget);

        await tester.tap(find.text('Listening'));
        await tester.pump();

        expect(permissionRequests, <AppPermissionKind>[
          AppPermissionKind.microphone,
        ]);
        expect(muteEvents, isEmpty);
        expect(
          find.text(
            'Microphone access is needed to speak. Enable it and try again.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the promoted-listener mic tap grants access before reconnect and roster unmute',
      (tester) async {
        await seedRoom(isLive: true, experience: 'broadcast');
        await db
            .collection('rooms')
            .doc(roomId)
            .collection('participants')
            .doc('relative')
            .set({
              'userId': 'relative',
              'displayName': 'relative',
              'role': 'speaker',
              'isMuted': true,
              'isSpeaker': true,
              'isHandRaised': false,
            });
        final permissionRequests = <AppPermissionKind>[];
        final voice = _RecordingVoice(
          muted: true,
          permission: AppPermissionAccess.denied,
          permissionRequestResult: AppPermissionAccess.granted,
          permissionRequests: permissionRequests,
          canPublish: false,
          publishOnReconnect: true,
        );
        final muteEvents = <String>[];
        final muteCoordinator = RoomMuteCoordinator(
          persistRosterState: (roomId, muted) async {
            muteEvents.add('persist:$roomId:$muted');
          },
          applyMicrophoneState: (muted) async {
            muteEvents.add('apply:$muted');
          },
          readCurrentMuted: () => true,
          disconnectStaleSession: () async {},
        );
        addTearDown(muteCoordinator.dispose);

        await pumpBroadcast(
          tester,
          voice: voice,
          muteCoordinator: muteCoordinator,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.live,
            room: roomModel(isLive: true, experience: 'broadcast'),
            authority: RoomVoiceStartAuthority.none,
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(permissionRequests, isEmpty);
        expect(voice.disconnects, isEmpty);
        expect(muteEvents, isEmpty);
        expect(find.text('Listening'), findsOneWidget);

        await tester.tap(find.text('Listening'));
        await tester.pumpAndSettle();

        expect(permissionRequests, <AppPermissionKind>[
          AppPermissionKind.microphone,
        ]);
        expect(voice.disconnects, <String>[roomId]);
        expect(voice.joins, <String>[roomId, roomId]);
        expect(muteEvents, <String>['persist:$roomId:false', 'apply:false']);
      },
    );

    testWidgets(
      'a delayed Broadcast refusal cannot disconnect the replacement room',
      (tester) async {
        await seedRoom(isLive: true, experience: 'broadcast');
        await db
            .collection('rooms')
            .doc(roomId)
            .collection('participants')
            .doc('relative')
            .set({
              'userId': 'relative',
              'displayName': 'relative',
              'role': 'speaker',
              'isMuted': true,
              'isSpeaker': true,
              'isHandRaised': false,
            });
        final voice = _RecordingVoice(muted: true);
        final rosterGate = Completer<void>();
        final events = <String>[];
        final muteCoordinator = RoomMuteCoordinator(
          persistRosterState: (roomId, muted) async {
            events.add('persist:$roomId:$muted');
            await rosterGate.future;
            throw _ServerRefusal('not-found');
          },
          applyMicrophoneState: (muted) async {
            events.add('apply:$muted');
          },
          readCurrentMuted: () => true,
          disconnectStaleSession: () async => events.add('disconnect'),
        );
        addTearDown(muteCoordinator.dispose);

        await pumpBroadcast(
          tester,
          voice: voice,
          muteCoordinator: muteCoordinator,
          entry: RoomVoiceEntry(
            outcome: RoomVoiceEntryOutcome.live,
            room: roomModel(isLive: true, experience: 'broadcast'),
            authority: RoomVoiceStartAuthority.none,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Unmute'), findsOneWidget);

        await tester.tap(find.text('Unmute'));
        await tester.pump();
        expect(events, ['persist:$roomId:false']);

        voice.replaceSessionForTest('room-2');
        rosterGate.complete();
        await tester.pump();

        expect(events, [
          'persist:$roomId:false',
        ], reason: 'Room A refusal must not disconnect room B.');
        expect(voice.roomId, 'room-2');
      },
    );

    testWidgets('a host can close listener stage requests for an episode', (
      tester,
    ) async {
      await seedRoom(
        isLive: true,
        experience: 'broadcast',
        topic: 'A focused solo episode',
        handRaisingEnabled: false,
      );
      await db
          .collection('rooms')
          .doc(roomId)
          .collection('participants')
          .doc('relative')
          .set({
            'userId': 'relative',
            'displayName': 'relative',
            'role': 'listener',
            'isMuted': true,
            'isSpeaker': false,
            'isHandRaised': false,
          });
      final model = roomModel(
        isLive: true,
        experience: 'broadcast',
        topic: 'A focused solo episode',
        handRaisingEnabled: false,
      );

      await pumpBroadcast(
        tester,
        voice: _RecordingVoice(),
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
      await tester.pump();

      expect(find.text('Listening mode'), findsOneWidget);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Raise hand'), findsNothing);
    });

    testWidgets('the producer can edit episode and audience controls', (
      tester,
    ) async {
      await db.collection('users').doc('host').set({
        'displayName': 'Host',
        'photoUrl': null,
      });
      await seedRoom(
        isLive: true,
        experience: 'broadcast',
        topic: 'Original episode topic',
      );
      final model = roomModel(
        isLive: true,
        experience: 'broadcast',
        topic: 'Original episode topic',
      );

      await pumpBroadcast(
        tester,
        uid: 'host',
        voice: _RecordingVoice(),
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.host,
        ),
      );
      await tester.tap(find.byTooltip('Manage podcast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Podcast settings'));
      await tester.pumpAndSettle();

      expect(find.text('Episode topic'), findsOneWidget);
      expect(find.text('Show format'), findsOneWidget);
      expect(find.text('Listener stage requests'), findsOneWidget);
      expect(find.text('Update podcast'), findsOneWidget);
    });
  });
}
