import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_family_board.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_voice_stage.dart';

import 'server_test_support.dart';

/// Boards 01 (friends, turkus) and 03 (family, zieleń) on the shell.
///
/// The honesty line these tests defend: a tile, a ring and a level glyph may
/// only come from the provider's own in-session roster, and no surface may
/// ever render a number of people — no presence writer exists (contract
/// G6/G3). Every module the boards draw (events, calendar, memories, list)
/// has no persistence at all (G9) and must therefore be a named `Wkrótce`
/// state with a disabled action, never a control that fails.

Server boardServer(ServerType type, {bool held = false, int members = 8}) =>
    Server(
      id: 's',
      name: type == ServerType.family ? 'Nasz dom' : 'Po godzinach',
      description: '',
      ownerId: 'owner',
      type: type,
      privacy: type == ServerType.family
          ? ServerPrivacy.inviteOnly
          : ServerPrivacy.private,
      memberCount: members,
      defaultChannelId: serverTemplateChannelsFor(
        type,
      ).firstWhere((seed) => seed.kind == ServerChannelKind.text).seedKey,
      schemaVersion: 1,
      activationState: held ? 'held' : 'active',
      status: held ? 'preparing' : 'active',
    );

List<ServerChannel> boardChannels(
  ServerType type, {
  ServerChannelLiveness liveness = ServerChannelLiveness.idle,
  Set<ServerChannelKind> without = const {},
}) {
  final seeds = serverTemplateChannelsFor(
    type,
  ).where((seed) => !without.contains(seed.kind)).toList();
  return [
    for (var i = 0; i < seeds.length; i++)
      ServerChannel(
        id: seeds[i].seedKey,
        serverId: 's',
        name: seeds[i].polishName,
        kind: seeds[i].kind,
        position: i,
        roomId: seeds[i].kind.isMedia ? 'room-${seeds[i].seedKey}' : null,
        experience: seeds[i].kind.isMedia ? RoomExperience.community : null,
        mediaMode: seeds[i].mediaMode,
        schemaVersion: 1,
        liveness: seeds[i].kind == ServerChannelKind.voice
            ? liveness
            : ServerChannelLiveness.idle,
      ),
  ];
}

ClubChatService boardChat([FakeFirebaseFirestore? firestore]) => ClubChatService(
  firestore: firestore ?? FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
  ),
  requestIdFactory: () => 'msg-1',
  messageSendInvoker: (_) async => <Object?, Object?>{},
);

const boardWidths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

/// Copy that could only come from the presence writer that does not exist.
final fabricated = RegExp(r'\d+\s+(osob[ay]? (rozmawia|w rozmowie)|widz|słuchacz)');

Finder get joinAction => find.byKey(const ValueKey('server-join'));
Finder get micControl =>
    find.byKey(const ValueKey('server-session-microphone'));
Finder get headphonesControl =>
    find.byKey(const ValueKey('server-session-headphones'));
Finder get leaveControl => find.byKey(const ValueKey('server-session-leave'));

/// Four people the provider reports, one of them speaking — board 01's 2×2.
const foursome = [
  ServerMediaParticipant(
    identity: 'owner',
    name: 'Owner',
    isLocal: true,
    isMicrophoneEnabled: true,
  ),
  ServerMediaParticipant(
    identity: 'u2',
    name: 'Maja',
    isLocal: false,
    isSpeaking: true,
    isMicrophoneEnabled: true,
  ),
  ServerMediaParticipant(
    identity: 'u3',
    name: 'Ola',
    isLocal: false,
    isMicrophoneEnabled: true,
  ),
  ServerMediaParticipant(
    identity: 'u4',
    name: 'Bartek',
    isLocal: false,
    isMicrophoneEnabled: false,
  ),
];

void main() {
  group('friends board 01', () {
    testWidgets('the salon renders at six widths and 200 percent with no '
        'person, ring or count before a join', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in boardWidths) {
        for (final scale in [1.0, 2.0]) {
          final repository = TestServerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(ServerType.friends);
          await pumpServers(
            tester,
            ServerWorkspaceScreen(
              key: UniqueKey(),
              serverId: 's',
              repository: repository,
              isRootTab: true,
              initialChannelId: 'lounge',
              chatService: boardChat(),
              connector: FakeServerMediaConnector(),
            ),
            size: Size(width, 780),
            textScale: scale,
            light: scale == 2,
          );
          final reason = 'friends $width ×$scale';
          expect(tester.takeException(), isNull, reason: reason);
          expect(find.byType(ServerParticipantTile), findsNothing,
              reason: reason);
          expect(find.byKey(const ValueKey('server-voice-controls')),
              findsNothing, reason: reason);
          expect(find.textContaining(fabricated), findsNothing, reason: reason);
          expect(joinAction, findsOneWidget, reason: reason);
          expect(repository.calls, isEmpty, reason: reason);
        }
      }
    });

    testWidgets('after joining the scene is the provider roster around the '
        'mic orb, with the ring only on who is actually speaking',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.friends)]
        ..channels = boardChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(joinAction);
      await tester.pumpAndSettle();
      final link = connector.links.single;
      expect(link.microphoneCalls, isEmpty, reason: 'never on connect');
      // No roster yet: the provider has not reported anybody.
      expect(find.byType(ServerParticipantTile), findsNothing);

      link.setRoster(foursome);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-voice-stage-orbit')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('server-voice-orb')), findsOneWidget);
      expect(find.byType(ServerParticipantTile), findsNWidgets(4));
      expect(find.text('Maja'), findsOneWidget);
      expect(find.text('Ty'), findsOneWidget);
      expect(find.textContaining(fabricated), findsNothing);

      // The ring is the speaking state, and only Maja is speaking.
      final rings = tester
          .widgetList<ServerParticipantTile>(find.byType(ServerParticipantTile))
          .where((tile) => tile.person.isSpeaking)
          .map((tile) => tile.person.name)
          .toList();
      expect(rings, ['Maja']);

      // Three round controls, and the leave control is the destructive one.
      expect(micControl, findsOneWidget);
      expect(headphonesControl, findsOneWidget);
      expect(leaveControl, findsOneWidget);
      await tester.tap(leaveControl);
      await tester.pumpAndSettle();
      expect(link.disconnects, 1);
      expect(repository.calls.length, 2, reason: 'leaving ends nothing');
    });

    testWidgets('Słuchawki silences this device only and calls no backend', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.friends)]
        ..channels = boardChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1100, 860),
      );
      await tester.tap(joinAction);
      await tester.pumpAndSettle();
      final link = connector.links.single;
      final before = repository.calls.length;
      await tester.tap(headphonesControl);
      await tester.pumpAndSettle();
      expect(link.deafenCalls, [true]);
      await tester.tap(headphonesControl);
      await tester.pumpAndSettle();
      expect(link.deafenCalls, [true, false]);
      expect(repository.calls.length, before, reason: 'local output only');
    });

    testWidgets('the controls report their state to assistive technology', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1100, 860),
      );
      await tester.tap(joinAction);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Mikrofon wyłączony'), findsWidgets);
      // Both the scene's round control and the dock's carry it: the dock is
      // the only place a listener — who has no microphone at all — can
      // silence the room, so it owns a real `Słuchawki` control too.
      expect(find.bySemanticsLabel('Dźwięk włączony'), findsWidgets);
      await tester.tap(micControl);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Mikrofon włączony'), findsWidgets);
      semantics.dispose();
    });

    testWidgets('a listener grant shows no working microphone control', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: _ListenerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1100, 860),
      );
      await tester.tap(joinAction);
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(
          find.descendant(of: micControl, matching: find.byType(IconButton)),
        ).onPressed,
        isNull,
      );
      expect(find.text('Tylko słuchasz'), findsOneWidget);
    });

    testWidgets('the event card is an honest module, not a working RSVP', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.friends)]
        ..channels = boardChannels(ServerType.friends);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      final card = find.byKey(const ValueKey('server-friends-event-card'));
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text('Wkrótce')),
        findsOneWidget,
      );
      final rsvp = find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, 'Dołączę'),
      );
      expect(tester.widget<FilledButton>(rsvp).onPressed, isNull);
      // The real channel is offered instead, and opening it changes nothing
      // but the selection.
      await tester.tap(
        find.descendant(of: card, matching: find.text('Wydarzenia')),
      );
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      // The header names the channel and, under it, its kind — the same
      // word twice for an events channel, which is correct.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-channel-header')),
          matching: find.text('Wydarzenia'),
        ),
        findsWidgets,
      );
    });

    testWidgets('no events channel means no event card at all', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(
              ServerType.friends,
              without: {ServerChannelKind.events},
            ),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      expect(
        find.byKey(const ValueKey('server-friends-event-card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('server-tab-events')), findsNothing);
    });

    testWidgets('the phone carries Salon | Czat | Wydarzenia', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('clubs/s').set({'ownerId': 'owner', 'name': 'Po'});
      await firestore.doc('clubs/s/members/owner').set({'role': 'owner'});
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(firestore),
        ),
        size: const Size(390, 800),
      );
      expect(find.byKey(const ValueKey('server-tab-scene')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-tab-chat')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-tab-events')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-tab-chat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-composer')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-tab-events')));
      await tester.pumpAndSettle();
      expect(find.text('Nie ma jeszcze planów'), findsOneWidget);
      expect(find.text('Wkrótce'), findsWidgets);
      expect(joinAction, findsNothing, reason: 'the events tab is not a scene');
    });

    testWidgets('the desktop context panel is the salon chat over a real '
        'channel', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.friends)]
            ..channels = boardChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      expect(find.text('Czat salonu · #ogólny'), findsOneWidget);
      // A text channel is not a salon, so the heading goes back to plain chat.
      await tester.tap(find.byKey(const ValueKey('server-channel-memes')));
      await tester.pumpAndSettle();
      expect(find.text('Czat salonu · #ogólny'), findsNothing);
    });
  });

  group('family board 03', () {
    testWidgets('the family server opens on Rodzinny pulpit with the hero, '
        'the lock and its real boundary', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.family)]
        ..channels = boardChannels(ServerType.family);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      expect(find.byKey(const ValueKey('server-family-board')), findsOneWidget);
      expect(find.text('Dobrze być razem.'), findsOneWidget);
      expect(
        find.text('Znajome głosy. Te same historie. Zawsze nasz dom.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-family-hero')),
          matching: find.byIcon(Icons.lock_outline),
        ),
        findsOneWidget,
      );
      expect(find.text('Tylko na zaproszenie'), findsWidgets);
      expect(find.text('Tylko na zaproszenie · 8 osób'), findsOneWidget);
      expect(find.byKey(const ValueKey('server-home-board')), findsOneWidget);
      expect(find.text('Rodzinny pulpit'), findsOneWidget);
      // A board is not a channel: nothing was asked of the backend to draw it.
      expect(repository.calls, isEmpty);
      expect(find.textContaining(fabricated), findsNothing);
    });

    testWidgets('the Salon rodzinny card joins for real and then shows the '
        'provider roster', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.family)]
        ..channels = boardChannels(ServerType.family);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          chatService: boardChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1440, 900),
      );
      expect(find.text('Nikt jeszcze nie rozmawia'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Dołącz do rozmowy'),
        findsOneWidget,
      );
      await tester.tap(joinAction);
      await tester.pumpAndSettle();
      expect(repository.calls.map((call) => call.$1), [
        'startServerChannelSessionV1',
        'createServerChannelTokenV1',
      ]);
      expect(repository.calls.first.$2['channelId'], 'lounge');
      final link = connector.links.single;
      link.setRoster(foursome.take(3).toList());
      await tester.pumpAndSettle();
      expect(find.byType(ServerParticipantTile), findsNWidgets(3));
      expect(micControl, findsOneWidget);
      expect(headphonesControl, findsOneWidget);
      expect(leaveControl, findsOneWidget);
      expect(find.textContaining(fabricated), findsNothing);
      expect(
        find.byKey(const ValueKey('server-conversation-dock')),
        findsOneWidget,
      );
    });

    testWidgets('the three cards are named modules with disabled actions and '
        'a real channel behind each', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.family)]
        ..channels = boardChannels(ServerType.family);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      const cards = {
        'server-family-plans': ('Najbliższe plany', 'Będę', 'Kalendarz'),
        'server-family-memories': (
          'Rodzinne wspomnienia',
          'Odtwórz',
          'Wspomnienia',
        ),
        'server-family-shopping': (
          'Do kupienia',
          'Dodaj produkt',
          'Lista zakupów',
        ),
      };
      for (final entry in cards.entries) {
        final card = find.byKey(ValueKey(entry.key));
        expect(card, findsOneWidget, reason: entry.key);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: card, matching: find.text(entry.value.$1)),
          findsOneWidget,
          reason: entry.key,
        );
        expect(
          find.descendant(of: card, matching: find.text('Wkrótce')),
          findsOneWidget,
          reason: entry.key,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: card,
                  matching: find.widgetWithText(FilledButton, entry.value.$2),
                ),
              )
              .onPressed,
          isNull,
          reason: entry.key,
        );
        expect(
          find.descendant(of: card, matching: find.text(entry.value.$3)),
          findsOneWidget,
          reason: entry.key,
        );
      }
      expect(repository.calls, isEmpty);
    });

    testWidgets('the module row is three, two and one column by width', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Columns follow the CENTRE's width, not the window's: the panel
      // takes 264–280 of it from tablet up.
      final expected = <double, int>{1440: 3, 1100: 2, 390: 1};
      for (final entry in expected.entries) {
        await pumpServers(
          tester,
          ServerWorkspaceScreen(
            key: UniqueKey(),
            serverId: 's',
            repository: TestServerRepository()
              ..servers = [boardServer(ServerType.family)]
              ..channels = boardChannels(ServerType.family),
            isRootTab: true,
            chatService: boardChat(),
          ),
          size: Size(entry.key, 1400),
        );
        final tops = [
          for (final key in const [
            'server-family-plans',
            'server-family-memories',
            'server-family-shopping',
          ])
            tester.getTopLeft(find.byKey(ValueKey(key))).dy,
        ];
        final rows = tops.toSet().length;
        expect(
          rows,
          entry.value == 3
              ? 1
              : entry.value == 2
              ? 2
              : 3,
          reason: 'family modules at ${entry.key}',
        );
      }
    });

    testWidgets('the phone board carries Dom | Kanały | Kalendarz | '
        'Wspomnienia and each one goes somewhere real', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.family)]
            ..channels = boardChannels(ServerType.family),
          isRootTab: true,
          chatService: boardChat(),
        ),
        size: const Size(390, 820),
      );
      expect(find.byKey(const ValueKey('server-tab-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-tab-calendar')), findsOneWidget);
      expect(find.byKey(const ValueKey('server-tab-memories')), findsOneWidget);
      // `Kanały` is offered exactly once on the surface: the strip owns it.
      expect(
        find.byKey(const ValueKey('server-open-channels')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('server-tab-calendar')));
      await tester.pumpAndSettle();
      // The header names the channel and, under it, its kind — which for a
      // calendar channel is the same word twice, quite correctly.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-channel-header')),
          matching: find.text('Kalendarz'),
        ),
        findsWidgets,
      );
      expect(find.byKey(const ValueKey('server-family-board')), findsNothing);
      // The strip is still there, so the way home is one tap.
      await tester.tap(find.byKey(const ValueKey('server-tab-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-family-board')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-open-channels')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-panel')), findsOneWidget);
      final lounge = find.byKey(const ValueKey('server-channel-lounge'));
      await tester.ensureVisible(lounge);
      await tester.pumpAndSettle();
      await tester.tap(lounge);
      await tester.pumpAndSettle();
      // A channel is not the board, so the shell's own header entry is back.
      expect(find.byKey(const ValueKey('server-family-board')), findsNothing);
      expect(find.byKey(const ValueKey('server-tab-chat')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-open-channels')),
        findsOneWidget,
      );
    });

    testWidgets('the board survives six widths and 200 percent and asks the '
        'backend for nothing', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in boardWidths) {
        for (final scale in [1.0, 2.0]) {
          final repository = TestServerRepository()
            ..servers = [boardServer(ServerType.family)]
            ..channels = boardChannels(ServerType.family);
          await pumpServers(
            tester,
            ServerWorkspaceScreen(
              key: UniqueKey(),
              serverId: 's',
              repository: repository,
              isRootTab: true,
              chatService: boardChat(),
              connector: FakeServerMediaConnector(),
            ),
            size: Size(width, 820),
            textScale: scale,
            light: scale == 2,
          );
          final reason = 'family $width ×$scale';
          expect(tester.takeException(), isNull, reason: reason);
          expect(
            find.byKey(const ValueKey('server-family-board')),
            findsOneWidget,
            reason: reason,
          );
          expect(joinAction, findsOneWidget, reason: reason);
          expect(find.byType(ServerParticipantTile), findsNothing,
              reason: reason);
          expect(find.textContaining(fabricated), findsNothing, reason: reason);
          expect(repository.calls, isEmpty, reason: reason);
        }
      }
    });

    testWidgets('a held family server has no board and joins nothing', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [boardServer(ServerType.family, held: true)]
        ..channels = boardChannels(ServerType.family);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: boardChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: const Size(1440, 900),
      );
      expect(find.byKey(const ValueKey('server-family-board')), findsNothing);
      expect(find.byKey(const ValueKey('server-home-board')), findsNothing);
      expect(tester.widget<FilledButton>(joinAction).onPressed, isNull);
      expect(repository.calls, isEmpty);
    });

    testWidgets('a family server without its module channels shows no card '
        'for what is not there', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.family)]
            ..channels = boardChannels(
              ServerType.family,
              without: {
                ServerChannelKind.calendar,
                ServerChannelKind.memories,
                ServerChannelKind.list,
              },
            ),
          isRootTab: true,
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      expect(find.byType(ServerFamilyBoard), findsOneWidget);
      expect(find.byKey(const ValueKey('server-family-plans')), findsNothing);
      expect(
        find.byKey(const ValueKey('server-family-memories')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-family-shopping')),
        findsNothing,
      );
      expect(joinAction, findsOneWidget, reason: 'the lounge is still real');
    });

    testWidgets('a live lounge says since when and never how many', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [boardServer(ServerType.family)]
            ..channels = boardChannels(
              ServerType.family,
              liveness: ServerChannelLiveness(
                isLive: true,
                startedAt: DateTime(2026, 9, 12, 19, 40),
              ),
            ),
          isRootTab: true,
          chatService: boardChat(),
        ),
        size: const Size(1440, 900),
      );
      expect(find.text('Na żywo od 19:40'), findsWidgets);
      expect(find.byKey(const ValueKey('server-live-pill')), findsWidgets);
      expect(find.textContaining(fabricated), findsNothing);
    });
  });
}

/// A token grant with no microphone source, which is what a listener gets.
class _ListenerRepository extends TestServerRepository {
  @override
  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) async {
    final granted = await super.createChannelToken(
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
      requestId: requestId,
    );
    return ServerSessionConnection(
      serverUrl: granted.serverUrl,
      participantToken: granted.participantToken,
      roomName: granted.roomName,
      participantIdentity: granted.participantIdentity,
      participantName: granted.participantName,
      expiresAtMillis: granted.expiresAtMillis,
      canPublish: false,
      canSubscribe: true,
      permittedTrackSources: const [],
      sessionRole: 'listener',
      roomId: granted.roomId,
      sessionId: granted.sessionId,
    );
  }
}
