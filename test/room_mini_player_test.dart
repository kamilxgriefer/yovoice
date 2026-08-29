// Regression suite for the persistent live-room mini player.
//
// The heart of it is NAVIGATION ISOLATION. The original bar wrapped the
// whole surface in one InkWell(onTap: return-to-room) with IconButtons
// inside; a DISABLED IconButton (mute while a change was in flight) does
// not compete in the gesture arena, so the tap fell through to the parent
// and pressing Mute mid-toggle NAVIGATED INTO THE ROOM. Every control must
// be an isolated tap target and a disabled control must swallow its tap.

import 'dart:ui' show SemanticsAction;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/compact_active_room_bar.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_mini_bar.dart';

/// A controllable stand-in for the one live audio session. Nothing touches
/// LiveKit: the player is a VIEW over this state.
class FakeVoiceService extends VoiceCallService {
  FakeVoiceService() : super.forTesting();

  VoiceCallStatus statusValue = VoiceCallStatus.connected;
  String? roomIdValue = 'room-1';
  String? roomNameValue = 'Sunday Morning Talk';
  bool mutedValue = false;
  bool muteChangeInProgressValue = false;
  MicState? micStateOverride;
  List<VoiceParticipantViewData> participantsValue = const [];
  int disconnectCalls = 0;

  @override
  VoiceCallStatus get status => statusValue;

  @override
  String? get roomId => roomIdValue;

  @override
  String? get roomName => roomNameValue;

  @override
  bool get isMuted => mutedValue;

  @override
  bool get muteChangeInProgress => muteChangeInProgressValue;

  @override
  bool get isConnected => statusValue == VoiceCallStatus.connected;

  @override
  MicState get micState {
    final override = micStateOverride;
    if (override != null) return override;
    switch (statusValue) {
      case VoiceCallStatus.connecting:
      case VoiceCallStatus.reconnecting:
        return MicState.connecting;
      case VoiceCallStatus.disconnected:
      case VoiceCallStatus.failed:
        return MicState.unavailable;
      case VoiceCallStatus.connected:
        return mutedValue ? MicState.muted : MicState.on;
    }
  }

  @override
  List<VoiceParticipantViewData> get participants => participantsValue;

  @override
  Future<void> disconnect({bool playSound = true}) async {
    disconnectCalls++;
    statusValue = VoiceCallStatus.disconnected;
    roomIdValue = null;
    roomNameValue = null;
    mutedValue = false;
    muteChangeInProgressValue = false;
    notifyListeners();
  }

  @override
  Future<void> setMuted(bool muted) async {
    mutedValue = muted;
    notifyListeners();
  }

  void poke() => notifyListeners();
}

/// RoomService over the fake Firestore, with the server callable paths
/// replaced by recorders — leave must never invent new semantics here.
class FakeRoomService extends RoomService {
  FakeRoomService({required this.db, required String uid})
    : super(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, displayName: 'Kamil'),
        ),
      );

  factory FakeRoomService.fresh({required String uid}) =>
      FakeRoomService(db: FakeFirebaseFirestore(), uid: uid);

  final FakeFirebaseFirestore db;

  final List<String> leaveCalls = [];
  final List<String> mutePersistCalls = [];

  @override
  Future<void> leaveRoom(String roomId) async {
    leaveCalls.add(roomId);
  }

  @override
  Future<void> setMuted({required String roomId, required bool isMuted}) async {
    mutePersistCalls.add('$roomId:$isMuted');
  }
}

class _Harness {
  _Harness({String uid = 'me', String hostId = 'host'}) {
    db = FakeFirebaseFirestore();
    voice = FakeVoiceService();
    rooms = FakeRoomService(db: db, uid: uid);
    coordinator = RoomMuteCoordinator(
      persistRosterState: (roomId, muted) =>
          rooms.setMuted(roomId: roomId, isMuted: muted),
      applyMicrophoneState: (muted) => voice.setMuted(muted),
      readCurrentMuted: () => voice.isMuted,
      disconnectStaleSession: () => voice.disconnect(),
    );
    seedRoom = db.collection('rooms').doc('room-1').set({
      'hostId': hostId,
      'hostName': 'Host',
      'name': 'Sunday Morning Talk',
      'description': 'A calm place to talk about anything.',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 3,
      'memberCount': 0,
      'isLive': true,
      'status': 'active',
      'experience': 'community',
    });
  }

  late final FakeFirebaseFirestore db;
  late final FakeVoiceService voice;
  late final FakeRoomService rooms;
  late final RoomMuteCoordinator coordinator;
  late final Future<void> seedRoom;

  final List<String> openedRooms = [];

  Widget player({
    Size surface = const Size(390, 844),
    bool onSentinelRoute = false,
  }) {
    Widget roomSurface() => MediaQuery(
      key: const ValueKey('sentinel-screen'),
      data: MediaQueryData(size: surface),
      child: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: RoomMiniBar(
          voiceService: voice,
          muteCoordinator: coordinator,
          roomService: rooms,
          openRoom: (context, roomId) async {
            openedRooms.add(roomId);
          },
        ),
      ),
    );

    return MaterialApp(
      initialRoute: onSentinelRoute ? '/sentinel' : '/',
      routes: {
        '/': (_) => onSentinelRoute
            ? const Scaffold(
                key: ValueKey('base-screen'),
                body: SizedBox.expand(),
              )
            : roomSurface(),
        '/sentinel': (_) => roomSurface(),
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  Size viewport = const Size(390, 844),
  bool onSentinelRoute = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  await harness.seedRoom;
  await tester.pumpWidget(
    harness.player(surface: viewport, onSentinelRoute: onSentinelRoute),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mini-player-more')));
  await tester.pumpAndSettle();
  expect(find.text('Room controls'), findsOneWidget);
}

void main() {
  group('visibility follows the one session', () {
    testWidgets('hidden with no session, visible with one', (tester) async {
      final harness = _Harness();
      harness.voice.statusValue = VoiceCallStatus.disconnected;
      harness.voice.roomIdValue = null;
      await _pump(tester, harness);

      expect(find.byKey(const ValueKey('mini-player')), findsNothing);

      harness.voice.statusValue = VoiceCallStatus.connected;
      harness.voice.roomIdValue = 'room-1';
      harness.voice.roomNameValue = 'Sunday Morning Talk';
      harness.voice.poke();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
      expect(find.text('Sunday Morning Talk'), findsOneWidget);
    });

    testWidgets('room ending remotely removes the player', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);

      await harness.voice.disconnect();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
    });

    testWidgets(
      'remote end closes More without popping root and a new session can '
      'open More again',
      (tester) async {
        final harness = _Harness();
        await _pump(tester, harness);
        await _openMore(tester);

        harness.voice
          ..statusValue = VoiceCallStatus.disconnected
          ..roomIdValue = null
          ..poke();
        await tester.pumpAndSettle();

        expect(find.text('Room controls'), findsNothing);
        expect(find.byKey(const ValueKey('mini-player')), findsNothing);
        expect(find.byType(Scaffold), findsOneWidget);

        await harness.db.collection('rooms').doc('room-2').set({
          'hostId': 'someone-else',
          'hostName': 'Host',
          'name': 'Fresh room',
          'description': 'A new live session.',
          'category': 'talk',
          'visibility': 'public',
          'language': 'English',
          'participantCount': 1,
          'memberCount': 0,
          'isLive': true,
          'status': 'active',
          'experience': 'community',
        });
        harness.voice
          ..statusValue = VoiceCallStatus.connected
          ..roomIdValue = 'room-2'
          ..roomNameValue = 'Fresh room'
          ..poke();
        await tester.pumpAndSettle();

        await _openMore(tester);
        expect(find.text('Leave room'), findsOneWidget);
      },
    );

    testWidgets('reconnecting state is labeled', (tester) async {
      final harness = _Harness();
      harness.voice.statusValue = VoiceCallStatus.reconnecting;
      await _pump(tester, harness);

      expect(find.textContaining('Reconnecting'), findsOneWidget);
    });
  });

  group('navigation isolation', () {
    testWidgets('tapping room info navigates', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('mini-player-room-info')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.openedRooms, ['room-1']);
    });

    testWidgets('tapping Return navigates', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness);

      await _openMore(tester);
      await tester.tap(find.byKey(const ValueKey('mini-player-return')));
      await tester.pumpAndSettle();

      expect(harness.openedRooms, ['room-1']);
    });

    testWidgets('tapping enabled Mute toggles and does not navigate', (
      tester,
    ) async {
      final harness = _Harness();
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('mini-player-mute')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        harness.openedRooms,
        isEmpty,
        reason: 'Mute must never navigate into the room.',
      );
      expect(
        harness.rooms.mutePersistCalls,
        ['room-1:true'],
        reason: 'Mute goes through the coordinator (roster first).',
      );
      expect(harness.voice.isMuted, isTrue);
      expect(find.byKey(const ValueKey('room-chat-surface')), findsNothing);
      expect(find.text('Room controls'), findsNothing);
      expect(harness.voice.disconnectCalls, 0);
    });

    testWidgets(
      'THE REPORTED BUG: tapping a DISABLED/busy Mute must swallow the tap '
      '— no navigation, no toggle',
      (tester) async {
        final harness = _Harness();
        harness.voice.muteChangeInProgressValue = true;
        await _pump(tester, harness);

        await tester.tap(find.byKey(const ValueKey('mini-player-mute')));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          harness.openedRooms,
          isEmpty,
          reason:
              'A disabled Mute let the tap fall through to the parent '
              'surface and navigated into the room — the operator\'s bug.',
        );
        expect(
          harness.rooms.mutePersistCalls,
          isEmpty,
          reason: 'A busy mute must not start a second toggle.',
        );
      },
    );

    testWidgets('tapping Leave leaves and does not navigate', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness);

      await _openMore(tester);
      await tester.tap(find.byKey(const ValueKey('mini-player-leave')));
      await tester.pumpAndSettle();

      expect(harness.openedRooms, isEmpty);
      expect(harness.voice.disconnectCalls, 1);
      expect(
        harness.rooms.leaveCalls,
        ['room-1'],
        reason: 'Leave reuses RoomService.leaveRoom — no new semantics.',
      );
      expect(
        find.byKey(const ValueKey('mini-player')),
        findsNothing,
        reason: 'Leaving clears the session and the player disappears.',
      );
      expect(
        find.byType(Scaffold),
        findsOneWidget,
        reason: 'Closing More before Leave must not pop the app root route.',
      );
    });

    testWidgets('tapping Expand chat opens the preview, not the room', (
      tester,
    ) async {
      final harness = _Harness();
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.openedRooms, isEmpty);
      expect(harness.rooms.mutePersistCalls, isEmpty);
      expect(find.text('Room controls'), findsNothing);
      expect(
        find.byKey(const ValueKey('room-chat-surface')),
        findsOneWidget,
        reason: 'Expanded chat reuses the one real chat surface.',
      );
    });

    testWidgets(
      'tapping More only opens its sheet and exposes Return and Leave',
      (tester) async {
        final harness = _Harness();
        await _pump(tester, harness);

        await _openMore(tester);

        expect(
          find.byKey(const ValueKey('mini-player-return')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('mini-player-leave')), findsOneWidget);
        expect(find.text('Return to room'), findsOneWidget);
        expect(find.text('Leave room'), findsOneWidget);
        expect(find.byKey(const ValueKey('room-chat-surface')), findsNothing);
        expect(harness.openedRooms, isEmpty);
        expect(harness.rooms.mutePersistCalls, isEmpty);
        expect(harness.voice.disconnectCalls, 0);
        expect(harness.rooms.leaveCalls, isEmpty);
      },
    );
  });

  group('compact mobile capsule', () {
    testWidgets('is at most 84px tall and all three circular controls keep '
        '44x44 hit targets', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness);

      final capsule = find.byType(CompactActiveRoomBar);
      expect(capsule, findsOneWidget);
      final capsuleSurface = find.byKey(
        const ValueKey('mini-player-compact-surface'),
      );
      expect(capsuleSurface, findsOneWidget);
      expect(
        tester.getSize(capsuleSurface).height,
        lessThanOrEqualTo(84),
        reason:
            'The collapsed phone surface must stay a compact live-room '
            'capsule rather than returning to the old multi-row panel.',
      );

      for (final key in const [
        ValueKey('mini-player-expand-chat'),
        ValueKey('mini-player-mute'),
        ValueKey('mini-player-more'),
      ]) {
        final control = find.byKey(key);
        final size = tester.getSize(control);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$key width');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$key height');
        expect(
          size.width,
          closeTo(size.height, .01),
          reason: '$key must remain a circular, not rectangular, control.',
        );
        final inkWell = tester.widget<InkWell>(
          find.descendant(of: control, matching: find.byType(InkWell)).first,
        );
        expect(inkWell.customBorder, isA<CircleBorder>());
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('primary controls expose semantic tap actions', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness();
      await _pump(tester, harness);

      for (final key in const [
        ValueKey('mini-player-room-info'),
        ValueKey('mini-player-expand-chat'),
        ValueKey('mini-player-mute'),
        ValueKey('mini-player-more'),
      ]) {
        final data = tester.getSemantics(find.byKey(key)).getSemanticsData();
        expect(
          data.hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$key must be activatable by assistive technology.',
        );
      }
      semantics.dispose();
    });

    testWidgets('busy Mute has no semantic tap but still swallows touch', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness();
      harness.voice.muteChangeInProgressValue = true;
      await _pump(tester, harness);

      final data = tester
          .getSemantics(find.byKey(const ValueKey('mini-player-mute')))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(find.byKey(const ValueKey('mini-player-mute')));
      await tester.pump();
      expect(harness.openedRooms, isEmpty);
      expect(harness.rooms.mutePersistCalls, isEmpty);
      semantics.dispose();
    });

    testWidgets('the empty gap between circular controls triggers no action', (
      tester,
    ) async {
      final harness = _Harness();
      await _pump(tester, harness);

      final chat = tester.getRect(
        find.byKey(const ValueKey('mini-player-expand-chat')),
      );
      final mute = tester.getRect(
        find.byKey(const ValueKey('mini-player-mute')),
      );
      expect(mute.left - chat.right, greaterThan(0));

      await tester.tapAt(Offset((chat.right + mute.left) / 2, chat.center.dy));
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.openedRooms, isEmpty);
      expect(harness.rooms.mutePersistCalls, isEmpty);
      expect(harness.voice.disconnectCalls, 0);
      expect(harness.rooms.leaveCalls, isEmpty);
      expect(find.byKey(const ValueKey('room-chat-surface')), findsNothing);
      expect(find.text('Room controls'), findsNothing);
    });

    testWidgets(
      'remote end during More reverse transition never pops the route below',
      (tester) async {
        final harness = _Harness();
        await _pump(tester, harness, onSentinelRoute: true);
        expect(find.byKey(const ValueKey('sentinel-screen')), findsOneWidget);
        expect(find.byKey(const ValueKey('base-screen')), findsNothing);

        await _openMore(tester);
        await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
        // One frame starts the reverse animation but deliberately does not
        // wait for route.completed — this is the race window under test.
        await tester.pump(const Duration(milliseconds: 16));

        harness.voice
          ..statusValue = VoiceCallStatus.disconnected
          ..roomIdValue = null
          ..poke();
        await tester.pumpAndSettle();

        expect(find.text('Room controls'), findsNothing);
        expect(find.byKey(const ValueKey('sentinel-screen')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('base-screen')),
          findsNothing,
          reason:
              'Session cleanup must address the sheet route itself, never '
              'Navigator.maybePop() the sentinel underneath it.',
        );
      },
    );
  });

  group('latest-message preview and session-local unread', () {
    Future<void> send(
      _Harness harness,
      String id,
      String text, {
      DateTime? at,
    }) {
      return harness.db
          .collection('rooms')
          .doc('room-1')
          .collection('messages')
          .doc(id)
          .set({
            'senderId': 'host',
            'senderName': 'Host',
            'senderPhotoUrl': null,
            'text': text,
            'createdAt': Timestamp.fromDate(at ?? DateTime(2026, 8, 22, 10, 0)),
            'reactions': <String, List<String>>{},
          });
    }

    testWidgets('latest message renders and updates on a new arrival', (
      tester,
    ) async {
      final harness = _Harness();
      await send(
        harness,
        'm1',
        'First message',
        at: DateTime(2026, 8, 22, 10, 0),
      );
      await _pump(tester, harness);

      expect(find.textContaining('First message'), findsOneWidget);

      await send(
        harness,
        'm2',
        'Second message',
        at: DateTime(2026, 8, 22, 10, 1),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Second message'), findsOneWidget);
      expect(find.textContaining('First message'), findsNothing);
    });

    testWidgets('"N new" increments while collapsed and resets on expand', (
      tester,
    ) async {
      final harness = _Harness();
      await send(
        harness,
        'm1',
        'Already here',
        at: DateTime(2026, 8, 22, 10, 0),
      );
      await _pump(tester, harness);

      // The message that was already there when the player appeared is not
      // "new" — the counter claims novelty within this session only.
      expect(find.byKey(const ValueKey('mini-player-new-pill')), findsNothing);

      await send(harness, 'm2', 'Fresh one', at: DateTime(2026, 8, 22, 10, 1));
      await tester.pump(const Duration(milliseconds: 300));
      await send(
        harness,
        'm3',
        'And another',
        at: DateTime(2026, 8, 22, 10, 2),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('mini-player-new-pill')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mini-player-new-pill')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('2'),
        findsNothing,
        reason: 'The visual badge must not duplicate Chat semantics.',
      );

      await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('mini-player-new-pill')),
        findsNothing,
        reason: 'Opening the expanded chat resets the session-local count.',
      );
    });

    testWidgets('returning to the room resets the counter', (tester) async {
      final harness = _Harness();
      await send(
        harness,
        'm1',
        'Already here',
        at: DateTime(2026, 8, 22, 10, 0),
      );
      await _pump(tester, harness);
      await send(harness, 'm2', 'Fresh one', at: DateTime(2026, 8, 22, 10, 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('mini-player-new-pill')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('mini-player-room-info')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('mini-player-new-pill')), findsNothing);
    });

    testWidgets('a moderated/deleted latest message updates the preview '
        'without counting as new', (tester) async {
      final harness = _Harness();
      await send(
        harness,
        'm1',
        'Older message',
        at: DateTime(2026, 8, 22, 10, 0),
      );
      await send(
        harness,
        'm2',
        'Rule-breaking message',
        at: DateTime(2026, 8, 22, 10, 1),
      );
      await _pump(tester, harness);
      expect(find.textContaining('Rule-breaking message'), findsOneWidget);

      await harness.db
          .collection('rooms')
          .doc('room-1')
          .collection('messages')
          .doc('m2')
          .delete();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Older message'), findsOneWidget);
      expect(find.textContaining('Rule-breaking message'), findsNothing);
      expect(
        find.byKey(const ValueKey('mini-player-new-pill')),
        findsNothing,
        reason: 'Falling back to an older message is not a new arrival.',
      );
    });

    testWidgets('emoji-only messages render', (tester) async {
      final harness = _Harness();
      await send(harness, 'm1', '🔥🔥🔥', at: DateTime(2026, 8, 22, 10, 0));
      await _pump(tester, harness);

      expect(find.textContaining('🔥🔥🔥'), findsOneWidget);
    });
  });

  group('desktop dock', () {
    testWidgets('expand opens an anchored popover; room end removes it and '
        'a fresh session can expand again', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness, viewport: const Size(1280, 800));

      // Dock layout renders the desktop subtitle.
      expect(find.text('Go back to live room'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('room-chat-surface')), findsOneWidget);

      // Expanding and collapsing never touch the RTC session.
      expect(harness.voice.disconnectCalls, 0);

      // Room ends remotely: the player AND the popover disappear.
      await harness.voice.disconnect();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
      expect(find.byKey(const ValueKey('room-chat-surface')), findsNothing);

      // A fresh session can expand again (the latch must not stay set).
      harness.voice
        ..statusValue = VoiceCallStatus.connected
        ..roomIdValue = 'room-1'
        ..roomNameValue = 'Sunday Morning Talk'
        ..poke();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('room-chat-surface')), findsOneWidget);
    });

    testWidgets('tapping outside the popover collapses it without '
        'navigating or touching the session', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness, viewport: const Size(1280, 800));

      await tester.tap(find.byKey(const ValueKey('mini-player-expand-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('room-chat-surface')), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('room-chat-surface')), findsNothing);
      expect(harness.openedRooms, isEmpty);
      expect(harness.voice.disconnectCalls, 0);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    });
  });

  group('host vs participant', () {
    testWidgets('participant sees Leave room', (tester) async {
      final harness = _Harness(uid: 'me', hostId: 'someone-else');
      await _pump(tester, harness);

      await _openMore(tester);
      expect(find.text('Leave room'), findsOneWidget);
      expect(find.text('End room'), findsNothing);
    });

    testWidgets('host sees End room and confirms before ending', (
      tester,
    ) async {
      final harness = _Harness(uid: 'me', hostId: 'me');
      await _pump(tester, harness);

      await _openMore(tester);
      expect(find.text('End room'), findsOneWidget);
      expect(find.text('Leave room'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mini-player-leave')));
      await tester.pumpAndSettle();

      // The confirmation gate: nothing has been torn down yet.
      expect(harness.voice.disconnectCalls, 0);
      expect(harness.rooms.leaveCalls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('mini-player-end-confirm')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.voice.disconnectCalls, 1);
      expect(
        harness.rooms.leaveCalls,
        ['room-1'],
        reason:
            'The host flow is RoomService.leaveRoom (ADR-091), which '
            'routes a temporary room to end and uses onlyIfEmpty on the '
            'fallback — the player must not invent new semantics.',
      );
    });

    testWidgets(
      'remote end dismisses host confirmation and cannot disconnect the next '
      'session',
      (tester) async {
        final harness = _Harness(uid: 'me', hostId: 'me');
        await _pump(tester, harness);
        await _openMore(tester);
        await tester.tap(find.byKey(const ValueKey('mini-player-leave')));
        await tester.pumpAndSettle();
        expect(find.text('End room?'), findsOneWidget);

        harness.voice
          ..statusValue = VoiceCallStatus.disconnected
          ..roomIdValue = null
          ..poke();
        await tester.pumpAndSettle();

        expect(find.text('End room?'), findsNothing);
        expect(harness.voice.disconnectCalls, 0);
        expect(harness.rooms.leaveCalls, isEmpty);
        expect(find.byType(Scaffold), findsOneWidget);

        await harness.db.collection('rooms').doc('room-2').set({
          'hostId': 'me',
          'hostName': 'Me',
          'name': 'Next room',
          'description': 'A separate session.',
          'category': 'talk',
          'visibility': 'public',
          'language': 'English',
          'participantCount': 1,
          'memberCount': 0,
          'isLive': true,
          'status': 'active',
          'experience': 'community',
        });
        harness.voice
          ..statusValue = VoiceCallStatus.connected
          ..roomIdValue = 'room-2'
          ..roomNameValue = 'Next room'
          ..poke();
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
        expect(harness.voice.disconnectCalls, 0);
        expect(
          find.byKey(const ValueKey('mini-player-end-confirm')),
          findsNothing,
        );
      },
    );
  });
}
