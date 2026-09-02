// Developer-only visual QA harness for the room VOICE LIFECYCLE states.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/room_voice_states_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// Covers every state this change introduced or altered, at narrow, medium and
// wide widths: dormant-with-authority ("Start voice"), dormant-without
// ("Not live"), live-and-muted ("Unmute"), the Family Room lounge variants,
// the broadcast equivalents, and the entry screen's loading and ended states.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();

  // The app's real typeface. Without it, anything styled through
  // AppTypography (the entry screen's loading message, for one) renders as
  // missing-glyph boxes and the screenshot proves nothing about the copy.
  final inter = FontLoader('Inter');
  inter.addFont(
    Future.value(
      ByteData.view(
        Uint8List.fromList(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ).buffer,
      ),
    ),
  );
  await inter.load();
}

/// A stand-in for the audio session. Nothing here contacts LiveKit: the
/// screenshots are of the ROOM's states, and the audio service only supplies
/// the mic state each one should render.
class _ScreenshotPermissionGateway implements AppPermissionPlatformGateway {
  const _ScreenshotPermissionGateway();

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async => AppPermissionAccess.granted;

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async =>
      AppPermissionAccess.granted;
}

class _StubVoice extends VoiceCallService {
  _StubVoice({this.state = MicState.unavailable, this.connected = false})
    : super.forTesting(
        permissionReadiness: PermissionReadinessService(
          platform: const _ScreenshotPermissionGateway(),
        ),
      );

  final MicState state;
  final bool connected;

  @override
  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
    bool playSound = true,
    bool startMuted = false,
  }) async {}

  @override
  Future<void> disconnect({bool playSound = true}) async {}

  @override
  bool get isConnected => connected;

  @override
  bool get isMuted => state == MicState.muted;

  @override
  MicState get micState => state;

  @override
  VoiceCallStatus get status =>
      connected ? VoiceCallStatus.connected : VoiceCallStatus.disconnected;

  @override
  List<VoiceParticipantViewData> get participants =>
      const <VoiceParticipantViewData>[];
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  home: RepaintBoundary(key: _capture, child: child),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void main() {
  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@yovoice.app',
      displayName: 'Kamil',
    ),
  );

  RoomService roomsFor(String uid) =>
      RoomService(firestore: db, auth: authFor(uid));

  VoiceRoom room({
    required String id,
    required bool isLive,
    String? clubId,
    String name = 'Sunday Morning Talk',
    String description = 'A calm place to talk about anything.',
    String experience = 'community',
    String topic = '',
    ShowFormat? showFormat,
    bool handRaisingEnabled = true,
  }) => VoiceRoom(
    id: id,
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: name,
    description: description,
    category: 'talk',
    visibility: clubId == null ? 'public' : 'private',
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
    experience: experience,
    clubId: clubId,
    topic: topic,
    showFormat: showFormat,
    handRaisingEnabled: handRaisingEnabled,
  );

  Future<void> seed(VoiceRoom model, {int participantCount = 0}) async {
    await db.collection('rooms').doc(model.id).set({
      'hostId': model.hostId,
      'hostName': model.hostName,
      'name': model.name,
      'description': model.description,
      'category': model.category,
      'visibility': model.visibility,
      'language': model.language,
      'participantCount': participantCount,
      'memberCount': 0,
      'isLive': model.isLive,
      'status': 'active',
      'experience': model.experience,
      'topic': model.topic,
      if (model.showFormat != null) 'showFormat': model.showFormat!.value,
      'handRaisingEnabled': model.handRaisingEnabled,
      'stageLimit': model.stageLimit,
      if (model.clubId != null) 'clubId': model.clubId,
    });
  }

  Future<void> seedFamily() async {
    await db.collection('clubs').doc('family_host').set({
      'name': 'The Jaguszewski Family',
      'description': 'Our private place',
      'ownerId': 'host',
      'ownerName': 'Host',
      'avatarUrl': null,
      'bannerUrl': null,
      'privacy': 'inviteOnly',
      'type': 'family',
      'defaultLanguage': 'English',
      'memberCount': 4,
      'onlineCount': 2,
    });
  }

  /// A COMMUNITY club, not a family one — this is what selects the gold
  /// identity. Without it the harness photographed three of the four room
  /// types the operator asked for and left Club unproven.
  Future<void> seedClub() async {
    await db.collection('clubs').doc('grief').set({
      'name': 'Club Grieferowski',
      'description': 'Opis klubu grieferowskiego',
      'ownerId': 'host',
      'ownerName': 'Host',
      'avatarUrl': null,
      'bannerUrl': null,
      'privacy': 'inviteOnly',
      'type': 'community',
      'defaultLanguage': 'English',
      'memberCount': 34,
      'onlineCount': 12,
    });
  }

  /// Extra people on the stage and in the audience. The stage must compose
  /// at one speaker AND at several, and the audience strip must show real
  /// faces with a +N chip rather than a number alone.
  Future<void> seedCast(
    String roomId, {
    int speakers = 0,
    int listeners = 0,
  }) async {
    final participants = db
        .collection('rooms')
        .doc(roomId)
        .collection('participants');
    for (var i = 0; i < speakers; i++) {
      await participants.doc('spk$i').set({
        'userId': 'spk$i',
        'displayName': i.isEven ? 'Zosia Wieczorek' : 'Bartek K.',
        'role': 'speaker',
        'isMuted': i.isOdd,
        'isSpeaker': true,
        'isHandRaised': false,
      });
    }
    for (var i = 0; i < listeners; i++) {
      await participants.doc('lst$i').set({
        'userId': 'lst$i',
        'displayName': 'Listener $i',
        'role': 'listener',
        'isMuted': true,
        'isSpeaker': false,
        'isHandRaised': false,
      });
    }
  }

  ClubService clubs(String uid) => ClubService(
    firestore: db,
    auth: authFor(uid),
    storage: MockFirebaseStorage(),
  );

  setUpAll(_loadFonts);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('relative').set({
      'displayName': 'Kamil',
      'photoUrl': null,
    });
    await db.collection('users').doc('host').set({
      'displayName': 'Host',
      'photoUrl': null,
    });
  });

  Future<void> shootCommunity(
    WidgetTester tester, {
    required String name,
    required VoiceRoom model,
    required RoomVoiceEntry entry,
    required Size viewport,
    MicState micState = MicState.unavailable,
    bool connected = false,
    String uid = 'relative',
    bool withClub = false,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: _capture, child: child!),
        ),
        home: CommunityVoiceRoomScreen(
          room: model,
          voiceEntry: entry,
          roomService: roomsFor(uid),
          voiceService: _StubVoice(state: micState, connected: connected),
          clubService: withClub ? clubs(uid) : null,
        ),
      ),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await _shoot(tester, name);
  }

  Future<void> shootBroadcast(
    WidgetTester tester, {
    required String name,
    required VoiceRoom model,
    required RoomVoiceEntry entry,
    required Size viewport,
    MicState micState = MicState.unavailable,
    bool connected = false,
    String uid = 'relative',
    bool openRequests = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        BroadcastRoomScreen(
          room: model,
          voiceEntry: entry,
          roomService: roomsFor(uid),
          voiceService: _StubVoice(state: micState, connected: connected),
        ),
      ),
    );
    await _settle(tester);
    if (openRequests) {
      await tester.tap(find.text('Requests 1').first);
      await _settle(tester);
    }
    expect(tester.takeException(), isNull);
    await _shoot(tester, name);
  }

  const viewports = <String, Size>{
    '320': Size(320, 844),
    '390': Size(390, 844),
    '768': Size(768, 1024),
    '1100': Size(1100, 800),
    '1440': Size(1440, 900),
  };

  for (final entry in viewports.entries) {
    final label = entry.key;
    final size = entry.value;

    testWidgets('community dormant, no authority @$label', (tester) async {
      final model = room(id: 'room-1', isLive: false);
      await seed(model);
      await shootCommunity(
        tester,
        name: 'voice-community-dormant-waiting-$label',
        model: model,
        viewport: size,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
    });

    testWidgets('community dormant, may start @$label', (tester) async {
      final model = room(id: 'room-1', isLive: false);
      await seed(model);
      await shootCommunity(
        tester,
        name: 'voice-community-dormant-startable-$label',
        model: model,
        viewport: size,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: model,
          authority: RoomVoiceStartAuthority.roomMember,
        ),
      );
    });

    testWidgets('community live and muted @$label', (tester) async {
      final model = room(id: 'room-1', isLive: true);
      await seed(model, participantCount: 1);
      await db
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('relative')
          .set({
            'userId': 'relative',
            'displayName': 'Kamil',
            'role': 'listener',
            'isMuted': true,
            'isSpeaker': true,
            'isHandRaised': false,
          });
      await shootCommunity(
        tester,
        name: 'voice-community-live-muted-$label',
        model: model,
        viewport: size,
        micState: MicState.muted,
        connected: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
    });

    testWidgets('family lounge dormant, member may start @$label', (
      tester,
    ) async {
      final model = room(
        id: 'club_lounge_family_host',
        isLive: false,
        clubId: 'family_host',
        name: 'The Jaguszewski Family Lounge',
      );
      await seed(model);
      await seedFamily();
      await shootCommunity(
        tester,
        name: 'voice-family-dormant-startable-$label',
        model: model,
        viewport: size,
        withClub: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: model,
          authority: RoomVoiceStartAuthority.clubMember,
        ),
      );
    });

    testWidgets('family lounge live, unmuted @$label', (tester) async {
      final model = room(
        id: 'club_lounge_family_host',
        isLive: true,
        clubId: 'family_host',
        name: 'The Jaguszewski Family Lounge',
      );
      await seed(model, participantCount: 1);
      await seedFamily();
      await db
          .collection('rooms')
          .doc('club_lounge_family_host')
          .collection('participants')
          .doc('relative')
          .set({
            'userId': 'relative',
            'displayName': 'Kamil',
            'role': 'listener',
            'isMuted': false,
            'isSpeaker': true,
            'isHandRaised': false,
          });
      await shootCommunity(
        tester,
        name: 'voice-family-live-$label',
        model: model,
        viewport: size,
        withClub: true,
        micState: MicState.on,
        connected: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.started,
          room: model,
          authority: RoomVoiceStartAuthority.clubMember,
        ),
      );
    });

    // THE FOURTH ROOM TYPE. Club is a community-type club lounge, which is
    // what resolves the gold identity — the reference the operator supplied
    // and the only one the harness never photographed.
    testWidgets('club lounge live, busy stage and audience @$label', (
      tester,
    ) async {
      final model = room(
        id: 'club_lounge_grief',
        isLive: true,
        clubId: 'grief',
        name: 'Club Grieferowski Lounge',
      );
      await seed(model, participantCount: 9);
      await seedClub();
      await seedCast('club_lounge_grief', speakers: 2, listeners: 8);
      await db
          .collection('rooms')
          .doc('club_lounge_grief')
          .collection('participants')
          .doc('relative')
          .set({
            'userId': 'relative',
            'displayName': 'Kamil',
            'role': 'listener',
            'isMuted': false,
            'isSpeaker': true,
            'isHandRaised': false,
          });
      await shootCommunity(
        tester,
        name: 'voice-club-live-busy-$label',
        model: model,
        viewport: size,
        withClub: true,
        micState: MicState.on,
        connected: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
    });

    // MANY LISTENERS, ONE SPEAKER: the audience strip has to carry real
    // faces and a +N chip without stealing the stage's height.
    testWidgets('community live, many listeners @$label', (tester) async {
      final model = room(id: 'room-crowd', isLive: true);
      await seed(model, participantCount: 15);
      await seedCast('room-crowd', listeners: 14);
      await db
          .collection('rooms')
          .doc('room-crowd')
          .collection('participants')
          .doc('relative')
          .set({
            'userId': 'relative',
            'displayName': 'Kamil',
            'role': 'listener',
            'isMuted': false,
            'isSpeaker': true,
            'isHandRaised': false,
          });
      await shootCommunity(
        tester,
        name: 'voice-community-crowd-$label',
        model: model,
        viewport: size,
        micState: MicState.on,
        connected: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
    });

    testWidgets('broadcast dormant, no authority @$label', (tester) async {
      final model = room(
        id: 'room-1',
        isLive: false,
        experience: 'broadcast',
        name: 'The Sunday Broadcast',
        topic: 'Why independent voices still matter',
        showFormat: ShowFormat.interview,
      );
      await seed(model);
      await shootBroadcast(
        tester,
        name: 'voice-broadcast-dormant-waiting-$label',
        model: model,
        viewport: size,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: model,
          authority: RoomVoiceStartAuthority.none,
        ),
      );
    });

    testWidgets('broadcast dormant, host may start @$label', (tester) async {
      final model = room(
        id: 'room-1',
        isLive: false,
        experience: 'broadcast',
        name: 'The Sunday Broadcast',
        topic: 'Why independent voices still matter',
        showFormat: ShowFormat.interview,
      );
      await seed(model);
      await shootBroadcast(
        tester,
        name: 'voice-broadcast-dormant-startable-$label',
        model: model,
        viewport: size,
        uid: 'host',
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.dormant,
          room: model,
          authority: RoomVoiceStartAuthority.host,
        ),
      );
    });

    testWidgets('broadcast live @$label', (tester) async {
      final model = room(
        id: 'room-1',
        isLive: true,
        experience: 'broadcast',
        name: 'The Sunday Broadcast',
        topic: 'Why independent voices still matter',
        showFormat: ShowFormat.interview,
      );
      await seed(model, participantCount: 6);
      await seedCast('room-1', speakers: 1, listeners: 4);
      await db
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('lst0')
          .update({'isHandRaised': true});
      await db
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('host')
          .set({
            'userId': 'host',
            'displayName': 'Host',
            'role': 'host',
            'isMuted': false,
            'isSpeaker': true,
            'isHandRaised': false,
          });
      await shootBroadcast(
        tester,
        name: 'voice-broadcast-live-$label',
        model: model,
        viewport: size,
        uid: 'host',
        micState: MicState.on,
        connected: true,
        entry: RoomVoiceEntry(
          outcome: RoomVoiceEntryOutcome.live,
          room: model,
          authority: RoomVoiceStartAuthority.host,
        ),
      );
    });
  }

  // THE POPULATED CHAT — the one surface no frame had ever shown. Real
  // seeded messages with reactions and a server timestamp, so the panel's
  // bubbles, role badges, reaction chips and the new per-message clock all
  // have visual evidence.
  testWidgets('community live with a populated chat, 1440', (tester) async {
    final model = room(id: 'room-chat', isLive: true);
    await seed(model, participantCount: 2);
    final messages = db
        .collection('rooms')
        .doc('room-chat')
        .collection('messages');
    await messages.doc('m1').set({
      'senderId': 'host',
      'senderName': 'Host',
      'senderPhotoUrl': null,
      'text': 'Witajcie! Super, ze jestescie.',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 21, 10, 32)),
      'reactions': {
        '❤️': ['relative', 'spk0'],
      },
    });
    await messages.doc('m2').set({
      'senderId': 'relative',
      'senderName': 'Kamil',
      'senderPhotoUrl': null,
      'text': 'Czesc wszystkim! Dobrze was slyszec.',
      'createdAt': Timestamp.fromDate(DateTime(2026, 8, 21, 10, 33)),
      'reactions': <String, List<String>>{},
    });
    await db
        .collection('rooms')
        .doc('room-chat')
        .collection('participants')
        .doc('relative')
        .set({
          'userId': 'relative',
          'displayName': 'Kamil',
          'role': 'listener',
          'isMuted': false,
          'isSpeaker': true,
          'isHandRaised': false,
        });
    await shootCommunity(
      tester,
      name: 'voice-community-chat-populated-1440',
      model: model,
      viewport: const Size(1440, 900),
      micState: MicState.on,
      connected: true,
      entry: RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.live,
        room: model,
        authority: RoomVoiceStartAuthority.none,
      ),
    );
  });

  // THE HOST FILL-GATE REGRESSION FRAME. 1100x800 sits inside the range the
  // review caught overflowing (host fixed content ~570-650px + a filled
  // stage at 720-850px heights); under the corrected gate this height falls
  // back to the scrolling column, and the frame's takeException assertion
  // is what pins "no overflow" rather than a promise.
  testWidgets('broadcast HOST at 1100x800 does not overflow', (tester) async {
    final model = room(
      id: 'room-pod-short',
      isLive: true,
      experience: 'broadcast',
      name: 'The Sunday Broadcast',
    );
    await seed(model, participantCount: 1);
    await shootBroadcast(
      tester,
      name: 'voice-broadcast-host-1100x800',
      model: model,
      viewport: const Size(1100, 800),
      micState: MicState.on,
      connected: true,
      uid: 'host',
      entry: RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.live,
        room: model,
        authority: RoomVoiceStartAuthority.host,
      ),
    );
  });

  testWidgets('broadcast producer request queue, 1440', (tester) async {
    final model = room(
      id: 'room-pod-queue',
      isLive: true,
      experience: 'broadcast',
      name: 'Signal & Story',
      description: 'A clear, moderated conversation with the audience.',
      topic: 'Can independent podcasts stay independent?',
      showFormat: ShowFormat.panel,
    );
    await seed(model, participantCount: 2);
    await seedCast(model.id, listeners: 1);
    await db
        .collection('rooms')
        .doc(model.id)
        .collection('participants')
        .doc('lst0')
        .update({'isHandRaised': true});
    await db
        .collection('rooms')
        .doc(model.id)
        .collection('participants')
        .doc('host')
        .set({
          'userId': 'host',
          'displayName': 'Host',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
          'isHandRaised': false,
        });

    await shootBroadcast(
      tester,
      name: 'voice-broadcast-producer-queue-1440',
      model: model,
      viewport: const Size(1440, 900),
      micState: MicState.on,
      connected: true,
      uid: 'host',
      openRequests: true,
      entry: RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.live,
        room: model,
        authority: RoomVoiceStartAuthority.host,
      ),
    );
    expect(find.text('Stage requests'), findsOneWidget);
  });

  testWidgets('long content: dormant lounge, 320px, 200% text', (tester) async {
    final model = room(
      id: 'club_lounge_family_host',
      isLive: false,
      clubId: 'family_host',
      name:
          'The Extended Jaguszewski Family Sunday Evening Lounge and Storytime',
      description:
          'A very long description that has to wrap gracefully at the '
          'narrowest supported width, at double text scale, without pushing '
          'the control dock off the screen.',
    );
    await seed(model);
    await seedFamily();
    await shootCommunity(
      tester,
      name: 'voice-family-dormant-longcontent-320-x2',
      model: model,
      viewport: const Size(320, 844),
      withClub: true,
      textScale: 2,
      entry: RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.dormant,
        room: model,
        authority: RoomVoiceStartAuthority.clubMember,
      ),
    );
  });

  testWidgets('entry screen: passive prejoin and ended', (tester) async {
    final preview = room(
      id: 'prejoin-preview',
      isLive: true,
      name: 'Sunday Morning Talk',
      description: 'A calm place to talk about anything.',
    );
    for (final size in const [Size(390, 844), Size(1100, 800)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(RoomEntryScreen(room: preview)));
      await _settle(tester);
      await _shoot(tester, 'voice-entry-prejoin-${size.width.toInt()}');

      await tester.pumpWidget(
        _host(
          const Scaffold(
            backgroundColor: AppImmersiveColors.background,
            body: SafeArea(
              child: RoomEndedState(roomName: 'Sunday Morning Talk'),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, 'voice-entry-unavailable-${size.width.toInt()}');
    }
  });
}
