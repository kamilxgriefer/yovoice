import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_test_support.dart';

Server shellServer(ServerType type, {bool held = false, int members = 12}) =>
    Server(
      id: 's',
      name: 'Po godzinach',
      description: '',
      ownerId: 'owner',
      type: type,
      privacy: type.allowsPublic
          ? ServerPrivacy.public
          : ServerPrivacy.inviteOnly,
      memberCount: members,
      defaultChannelId: firstText(type),
      schemaVersion: 1,
      activationState: held ? 'held' : 'active',
      status: held ? 'preparing' : 'active',
    );

String firstText(ServerType type) => serverTemplateChannelsFor(
  type,
).firstWhere((seed) => seed.kind == ServerChannelKind.text).seedKey;

String firstMedia(ServerType type) => serverTemplateChannelsFor(
  type,
).firstWhere((seed) => seed.kind.isMedia).seedKey;

/// The seeded template as the workspace reads it back, in Polish.
List<ServerChannel> shellChannels(
  ServerType type, {
  ServerChannelLiveness liveness = ServerChannelLiveness.idle,
  String? activeSessionId,
}) {
  final seeds = serverTemplateChannelsFor(type);
  return [
    for (var i = 0; i < seeds.length; i++)
      ServerChannel(
        id: seeds[i].seedKey,
        serverId: 's',
        name: seeds[i].polishName,
        kind: seeds[i].kind,
        position: i,
        access: seeds[i].restricted
            ? ServerChannelAccess.restricted
            : ServerChannelAccess.members,
        roomId: seeds[i].kind.isMedia ? 'room-${seeds[i].seedKey}' : null,
        experience: !seeds[i].kind.isMedia
            ? null
            : seeds[i].kind == ServerChannelKind.stage
            ? RoomExperience.broadcast
            : RoomExperience.community,
        mediaMode: seeds[i].mediaMode,
        schemaVersion: 1,
        // Only the template's first media channel carries the live
        // projection; its siblings stay idle so both states render at once.
        liveness: seeds[i].seedKey == firstMedia(type)
            ? liveness
            : ServerChannelLiveness.idle,
        activeSessionId: seeds[i].seedKey == firstMedia(type)
            ? activeSessionId
            : null,
      ),
  ];
}

ClubChatService fakeChat({
  FakeFirebaseFirestore? firestore,
  ClubMessageSendInvoker? send,
}) => ClubChatService(
  firestore: firestore ?? FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
  ),
  requestIdFactory: () => 'msg-1',
  messageSendInvoker: send ?? (_) async => <Object?, Object?>{},
);

const widths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

/// Copy that could only come from a presence writer that does not exist.
final fabricatedCount = RegExp(r'\d+\s+(osob[ay]? rozmawia|widz|słuchacz)');

Finder get dock => find.byKey(const ValueKey('server-conversation-dock'));
Finder get dockStatus => find.byKey(const ValueKey('server-dock-status'));
Finder get join => find.byKey(const ValueKey('server-join'));

String dockText(WidgetTester tester) =>
    tester.widget<Text>(dockStatus).data ?? '';

void main() {
  testWidgets(
    'every template renders the shell at six widths and 200 percent without fabricating presence',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        for (final width in widths) {
          for (final scale in [1.0, 2.0]) {
            final repository = TestServerRepository()
              ..servers = [shellServer(type)]
              ..channels = shellChannels(type);
            await pumpServers(
              tester,
              ServerWorkspaceScreen(
                key: UniqueKey(),
                serverId: 's',
                repository: repository,
                isRootTab: true,
                initialChannelId: firstMedia(type),
                chatService: fakeChat(),
                connector: FakeServerMediaConnector(),
              ),
              size: Size(width, 760),
              textScale: scale,
              light: scale == 2,
            );
            final reason = '$type $width ×$scale';
            expect(tester.takeException(), isNull, reason: reason);
            final phone = width < ServerWorkspaceScreen.tabletBreakpoint;
            final desktop = width >= ServerWorkspaceScreen.desktopBreakpoint;
            expect(
              find.byKey(const ValueKey('server-open-channels')),
              phone ? findsOneWidget : findsNothing,
              reason: reason,
            );
            expect(
              find.byKey(const ValueKey('server-panel')),
              phone ? findsNothing : findsOneWidget,
              reason: reason,
            );
            expect(
              find.byKey(const ValueKey('server-context-panel')),
              desktop ? findsOneWidget : findsNothing,
              reason: reason,
            );
            expect(
              find.byKey(const ValueKey('server-tab-chat')),
              desktop ? findsNothing : findsOneWidget,
              reason: reason,
            );
            expect(join, findsOneWidget, reason: reason);
            expect(
              find.byKey(const ValueKey('server-live-pill')),
              findsNothing,
              reason: reason,
            );
            expect(find.textContaining(fabricatedCount), findsNothing);
            expect(dock, findsNothing, reason: reason);
            expect(repository.calls, isEmpty, reason: reason);
          }
        }
      }
    },
  );

  testWidgets('channels are grouped under the template headings in order', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const expected = <ServerType, List<String>>{
      ServerType.friends: ['TEKSTOWE', 'GŁOSOWE', 'ORGANIZACJA'],
      ServerType.community: ['START', 'ROZMOWY', 'NA ŻYWO'],
      ServerType.podcast: ['PODCAST', 'SPOŁECZNOŚĆ'],
      ServerType.family: ['DOM', 'RAZEM'],
      ServerType.company: ['FIRMA', 'ZESPÓŁ'],
    };
    for (final entry in expected.entries) {
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          key: UniqueKey(),
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [shellServer(entry.key)]
            ..channels = shellChannels(entry.key),
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: const Size(1440, 900),
      );
      final tops = [
        for (final heading in entry.value)
          tester.getTopLeft(find.text(heading)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()), reason: '${entry.key}');
      // Every seeded channel is listed exactly once, under one heading.
      for (final seed in serverTemplateChannelsFor(entry.key)) {
        expect(
          find.byKey(ValueKey('server-channel-${seed.seedKey}')),
          findsOneWidget,
          reason: '${entry.key} ${seed.seedKey}',
        );
      }
    }
    // The company's restricted rows carry a lock, not a channel glyph.
    final hr = find.descendant(
      of: find.byKey(const ValueKey('server-channel-hr')),
      matching: find.byIcon(Icons.lock_outline),
    );
    expect(hr, findsOneWidget);
    expect(find.text('Prywatny serwer · 12 osób'), findsNothing);
    expect(find.text('Przestrzeń firmowa · 12 osób'), findsOneWidget);
  });

  testWidgets('the panel subtitle and the phone header count real members', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.friends, members: 12)]
      ..channels = shellChannels(ServerType.friends);
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        chatService: fakeChat(),
      ),
      size: const Size(1100, 800),
    );
    expect(find.text('Prywatny serwer · 12 osób'), findsOneWidget);
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        key: UniqueKey(),
        serverId: 's',
        repository: repository,
        isRootTab: true,
        chatService: fakeChat(),
      ),
      size: const Size(390, 800),
    );
    expect(find.text('12 osób w serwerze'), findsOneWidget);
  });

  testWidgets('liveness renders live since the server instant and no count', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final startedAt = DateTime(2026, 9, 12, 19, 40);
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.friends)]
      ..channels = shellChannels(
        ServerType.friends,
        liveness: ServerChannelLiveness(isLive: true, startedAt: startedAt),
        activeSessionId: 'live-1',
      );
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        initialChannelId: 'lounge',
        chatService: fakeChat(),
      ),
      size: const Size(1440, 900),
    );
    expect(find.text('Na żywo od 19:40'), findsWidgets);
    expect(find.byKey(const ValueKey('server-live-pill')), findsWidgets);
    expect(find.textContaining(fabricatedCount), findsNothing);
    expect(find.text('Nikt jeszcze nie rozmawia'), findsNothing);
    // The idle sibling stays quiet.
    await tester.tap(find.byKey(const ValueKey('server-channel-gaming')));
    await tester.pumpAndSettle();
    expect(find.text('Nikt jeszcze nie rozmawia'), findsWidgets);
    expect(find.byKey(const ValueKey('server-live-pill')), findsOneWidget);
  });

  testWidgets(
    'joining goes start then token and says connected only when the provider does',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [shellServer(ServerType.friends)]
        ..channels = shellChannels(ServerType.friends);
      final connector = FakeServerMediaConnector()..connectImmediately = false;
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: fakeChat(),
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1440, 900),
      );
      expect(dock, findsNothing);
      await tester.tap(join);
      // An indeterminate spinner is on screen while connecting, so settle
      // by frames, not by quiescence.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(repository.calls.map((call) => call.$1), [
        'startServerChannelSessionV1',
        'createServerChannelTokenV1',
      ]);
      expect(repository.calls[0].$2, {
        'serverId': 's',
        'channelId': 'lounge',
        'requestId': 'request-1',
      });
      expect(repository.calls[1].$2, {
        'serverId': 's',
        'channelId': 'lounge',
        'sessionId': 'session-1',
        'requestId': 'request-2',
      });
      expect(connector.connections, [
        ('wss://livekit.test', 'token-session-1'),
      ]);
      final link = connector.links.single;
      // A token in hand is not a connection.
      expect(dock, findsOneWidget);
      expect(dockText(tester), 'Łączenie…');
      expect(find.text('połączono'), findsNothing);
      expect(link.microphoneCalls, isEmpty);
      expect(
        find.byKey(const ValueKey('server-dock-microphone')),
        findsNothing,
      );

      link.report(ServerMediaLinkState.connected);
      await tester.pumpAndSettle();
      expect(dockText(tester), 'połączono');
      expect(find.text('W rozmowie'), findsOneWidget);
      expect(link.microphoneCalls, isEmpty, reason: 'never on connect');
      // The microphone starts only from the person's own press.
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(link.microphoneCalls, [true]);
      // The scene's round control now carries the board's short label and
      // reports its state through the glyph and its semantics, so the state
      // is asserted on the control itself rather than on a sentence.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-session-microphone')),
          matching: find.byIcon(Icons.mic_rounded),
        ),
        findsOneWidget,
      );

      link.setRoster(const [
        ServerMediaParticipant(
          identity: 'owner',
          name: 'Owner',
          isLocal: true,
          isMicrophoneEnabled: true,
        ),
        ServerMediaParticipant(
          identity: 'u2',
          name: 'Ola',
          isLocal: false,
          isSpeaking: true,
          isMicrophoneEnabled: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Ola'), findsOneWidget);
      expect(find.text('Ty'), findsOneWidget);

      link.report(ServerMediaLinkState.reconnecting);
      await tester.pumpAndSettle();
      expect(dockText(tester), 'Ponowne łączenie…');
      link.report(ServerMediaLinkState.connected);
      await tester.pumpAndSettle();

      // Browsing a text channel keeps the conversation and its dock.
      await tester.tap(find.byKey(const ValueKey('server-channel-general')));
      await tester.pumpAndSettle();
      expect(dock, findsOneWidget);
      expect(dockText(tester), 'połączono');

      await tester.tap(find.byKey(const ValueKey('server-dock-leave')));
      await tester.pumpAndSettle();
      expect(link.disconnects, 1);
      expect(dock, findsNothing);
      expect(repository.calls.length, 2, reason: 'leaving ends nothing');
    },
  );

  testWidgets('a live generation is joined without a start call', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.podcast)]
      ..channels = shellChannels(
        ServerType.podcast,
        liveness: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 20),
        ),
        activeSessionId: 'live-7',
      )
      ..myRole = ServerMemberRole.member;
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        initialChannelId: 'studio',
        chatService: fakeChat(),
        connector: connector,
        anotherVoiceSessionActive: () => false,
      ),
      size: const Size(1100, 800),
    );
    expect(find.text('Słuchaj'), findsOneWidget);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(repository.calls.map((call) => call.$1), [
      'createServerChannelTokenV1',
    ]);
    expect(repository.calls.single.$2['sessionId'], 'live-7');
    // The dock reports the established link, and on a stage it names what
    // publishing actually is: this grant carries the microphone source, so
    // board 05's two states — `Słuchasz` and `Na antenie` — are the two words
    // this line can say, never one word for both.
    expect(dockText(tester), 'Na antenie');
  });

  testWidgets('a listener is not offered to start a stage', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: TestServerRepository()
          ..servers = [shellServer(ServerType.community)]
          ..channels = shellChannels(ServerType.community)
          ..myRole = ServerMemberRole.member,
        isRootTab: true,
        initialChannelId: 'stage',
        chatService: fakeChat(),
      ),
      size: const Size(1100, 800),
    );
    expect(join, findsNothing);
    expect(
      find.text('Będzie można słuchać, gdy scena zacznie nadawać.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('server-invite-action')), findsNothing);
    expect(find.byKey(const ValueKey('server-add-channel')), findsNothing);
  });

  testWidgets('joining is refused while another voice session owns audio', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.family)]
      ..channels = shellChannels(ServerType.family);
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        initialChannelId: 'lounge',
        chatService: fakeChat(),
        connector: FakeServerMediaConnector(),
        anotherVoiceSessionActive: () => true,
      ),
      size: const Size(390, 800),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    expect(find.text('Najpierw zakończ trwającą rozmowę.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('server-session-dismiss')));
    await tester.pumpAndSettle();
    expect(dock, findsNothing);
    expect(join, findsOneWidget);
  });

  testWidgets('a failed join says so and retries with a new request', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.company)]
      ..channels = shellChannels(ServerType.company)
      ..failNextCall['createServerChannelTokenV1'] = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'down',
      );
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        initialChannelId: 'meeting',
        chatService: fakeChat(),
        connector: FakeServerMediaConnector(),
        anotherVoiceSessionActive: () => false,
      ),
      size: const Size(768, 900),
    );
    expect(find.text('Rozpocznij spotkanie'), findsOneWidget);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(
      find.text('To trwa dłużej, niż oczekiwano. Spróbuj ponownie.'),
      findsWidgets,
    );
    expect(find.textContaining('down'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('server-join-retry')));
    await tester.pumpAndSettle();
    expect(repository.calls.map((call) => call.$1), [
      'startServerChannelSessionV1',
      'createServerChannelTokenV1',
      'startServerChannelSessionV1',
      'createServerChannelTokenV1',
    ]);
    expect(dockText(tester), 'połączono');
    // Camera and screen share are still labelled unavailable and still never
    // controls that fail — board 04 now says so in words and keeps both in
    // the dock, disabled. (Board 04's own suite proves the platform query
    // behind the share; here the point is only that neither can be pressed.)
    for (final control in const [
      'server-dock-camera',
      'server-dock-share',
    ]) {
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(ValueKey(control)),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
        reason: control,
      );
    }
    expect(
      find.textContaining('Włączenie własnej kamery jeszcze nie działa'),
      findsOneWidget,
    );
    expect(
      find.textContaining('działa na razie w przeglądarce'),
      findsOneWidget,
    );
  });

  testWidgets('an unregistered callable reads as still being prepared', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.friends)]
      ..channels = shellChannels(ServerType.friends)
      ..failNextCall['startServerChannelSessionV1'] =
          FirebaseFunctionsException(code: 'not-found', message: 'NOT FOUND');
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        initialChannelId: 'lounge',
        chatService: fakeChat(),
        connector: FakeServerMediaConnector(),
        anotherVoiceSessionActive: () => false,
      ),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(
      find.text('Ta część YO Voice jest jeszcze przygotowywana.'),
      findsWidgets,
    );
    expect(find.textContaining('NOT FOUND'), findsNothing);
  });

  testWidgets('a held server joins nothing and invites nobody', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [390.0, 1440.0]) {
      final repository = TestServerRepository()
        ..servers = [shellServer(ServerType.friends, held: true)]
        ..channels = shellChannels(ServerType.friends);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          key: UniqueKey(),
          serverId: 's',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'lounge',
          chatService: fakeChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: Size(width, 900),
      );
      expect(tester.widget<FilledButton>(join).onPressed, isNull);
      if (width >= ServerWorkspaceScreen.tabletBreakpoint) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('server-invite-action')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Zaproszenia będą możliwe, gdy serwer będzie gotowy.'),
          findsOneWidget,
        );
      }
      expect(repository.calls, isEmpty);
    }
  });

  testWidgets('invite goes to createServerInviteV1 with the picked friend', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.friends)]
      ..channels = shellChannels(ServerType.friends)
      ..friends = const [
        ServerInviteCandidate(id: 'u2', displayName: 'Ola'),
        ServerInviteCandidate(id: 'u3', displayName: 'Bartek'),
      ];
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        chatService: fakeChat(),
      ),
      size: const Size(1100, 800),
    );
    await tester.tap(find.byKey(const ValueKey('server-invite-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-invite-sheet')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('server-invite-u2')),
        matching: find.text('Zaproś'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.single.$1, 'createServerInviteV1');
    expect(repository.calls.single.$2, {
      'serverId': 's',
      'inviteeId': 'u2',
      'requestId': 'request-1',
    });
    expect(find.text('Wysłano zaproszenie do Ola'), findsOneWidget);

    repository.inviteResult = const ServerInviteResult(
      serverId: 's',
      inviteeId: 'u3',
      generation: 2,
      status: 'pending',
      alreadyExisted: true,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('server-invite-u3')),
        matching: find.text('Zaproś'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zaproszenie dla Bartek już czeka'), findsWidgets);

    repository.failNextCall['createServerInviteV1'] =
        FirebaseFunctionsException(code: 'permission-denied', message: 'no');
    repository.friends = const [
      ServerInviteCandidate(id: 'u4', displayName: 'Kamil'),
    ];
  });

  testWidgets('invite refusals are one sentence, never the raw code', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.friends)]
      ..channels = shellChannels(ServerType.friends)
      ..friends = const [ServerInviteCandidate(id: 'u4', displayName: 'Kamil')]
      ..failNextCall['createServerInviteV1'] = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'PERMISSION_DENIED',
      );
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        chatService: fakeChat(),
      ),
      size: const Size(390, 800),
    );
    await tester.tap(find.byKey(const ValueKey('server-open-channels')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-invite-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zaproś').last);
    await tester.pumpAndSettle();
    expect(find.text('Tej osoby nie można teraz zaprosić.'), findsOneWidget);
    expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
  });

  testWidgets(
    'adding a channel sends the exact createServerChannelV1 payload',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [shellServer(ServerType.company)]
        ..channels = shellChannels(ServerType.company);
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: const Size(1440, 900),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('server-add-channel')),
      );
      await tester.tap(find.byKey(const ValueKey('server-add-channel')));
      await tester.pumpAndSettle();
      // An empty name is refused before any call.
      await tester.tap(find.byKey(const ValueKey('server-channel-submit')));
      await tester.pumpAndSettle();
      // The message now goes through `YoTextField(errorText:)` so it is
      // attached to — and announced with — the editable node. That component
      // deliberately renders it twice: once inside the decoration at font
      // size 0 (which is what carries it into the field's semantics) and once
      // as the single visible supporting line.
      expect(find.text('Nadaj kanałowi nazwę.'), findsNWidgets(2));
      expect(repository.calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('server-channel-name')),
        'Projekty',
      );
      await tester.tap(find.byKey(const ValueKey('server-channel-kind-voice')));
      await tester.tap(find.byKey(const ValueKey('server-channel-restricted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-channel-submit')));
      await tester.pumpAndSettle();
      expect(repository.calls.single.$1, 'createServerChannelV1');
      expect(repository.calls.single.$2, {
        'serverId': 's',
        'requestId': 'request-1',
        'kind': 'voice',
        'name': 'Projekty',
        'categoryId': null,
        'accessMode': 'restricted',
        'experience': 'community',
        'mediaMode': 'audio',
      });
      expect(find.text('Kanał utworzony'), findsOneWidget);
    },
  );

  testWidgets('a community stage is created as a video broadcast', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [shellServer(ServerType.community)]
      ..channels = shellChannels(ServerType.community)
      ..myRole = ServerMemberRole.admin;
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        isRootTab: true,
        chatService: fakeChat(),
      ),
      size: const Size(1100, 900),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('server-add-channel')),
    );
    await tester.tap(find.byKey(const ValueKey('server-add-channel')));
    await tester.pumpAndSettle();
    // Restricted creation is owner-only on the server; an admin is not
    // offered the toggle.
    expect(
      find.byKey(const ValueKey('server-channel-restricted')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-channel-name')),
      'Q&A',
    );
    await tester.tap(find.byKey(const ValueKey('server-channel-kind-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-channel-submit')));
    await tester.pumpAndSettle();
    expect(repository.calls.single.$2['experience'], 'broadcast');
    expect(repository.calls.single.$2['mediaMode'], 'video');
    expect(repository.calls.single.$2['accessMode'], 'members');
  });

  testWidgets(
    'a text channel reads the club store and sends through sendClubMessage',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('clubs/s').set({'ownerId': 'owner', 'name': 'Po'});
      await firestore.doc('clubs/s/members/owner').set({'role': 'owner'});
      await firestore.doc('clubs/s/channels/general/messages/m1').set({
        'senderId': 'u2',
        'senderName': 'Ola',
        'content': 'Kto dziś gra?',
        'sentAt': Timestamp.fromDate(DateTime(2026, 9, 12, 19, 14)),
      });
      Map<String, Object?>? sent;
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [shellServer(ServerType.friends)]
            ..channels = shellChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: 'general',
          chatService: fakeChat(
            firestore: firestore,
            send: (request) async {
              sent = request;
              return <Object?, Object?>{};
            },
          ),
        ),
        size: const Size(390, 800),
      );
      expect(find.text('Kto dziś gra?'), findsOneWidget);
      expect(find.text('Ola'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('server-composer')),
        'Ja od 20:00!',
      );
      await tester.tap(find.byKey(const ValueKey('server-send')));
      await tester.pumpAndSettle();
      expect(sent, {
        'clubId': 's',
        'channelId': 'general',
        'requestId': 'msg-1',
        'text': 'Ja od 20:00!',
      });
    },
  );

  testWidgets('a held server does not subscribe to a thread it cannot read', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: TestServerRepository()
          ..servers = [shellServer(ServerType.friends, held: true)]
          ..channels = shellChannels(ServerType.friends),
        isRootTab: true,
        initialChannelId: 'general',
        chatService: fakeChat(),
      ),
      size: const Size(768, 800),
    );
    expect(find.byKey(const ValueKey('server-composer')), findsNothing);
    expect(
      find.text(
        'Serwer i kanały zostały zapisane. Rozmowy i wspólne narzędzia są przygotowywane.',
      ),
      findsWidgets,
    );
  });

  testWidgets('the phone Kanały sheet lists the grouped channels and selects', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: TestServerRepository()
          ..servers = [shellServer(ServerType.friends)]
          ..channels = shellChannels(ServerType.friends),
        isRootTab: true,
        initialChannelId: 'lounge',
        chatService: fakeChat(),
      ),
      size: const Size(320, 700),
      textScale: 2,
    );
    expect(find.byKey(const ValueKey('server-tab-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('server-open-channels')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-panel')), findsOneWidget);
    expect(find.text('TEKSTOWE'), findsOneWidget);
    // 320 px at 200 % puts the rest of the list below the fold: the sheet
    // scrolls to it rather than hiding it, which is the point of the check.
    final memes = find.byKey(const ValueKey('server-channel-memes'));
    await tester.ensureVisible(memes);
    await tester.pumpAndSettle();
    await tester.tap(memes);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-panel')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-channel-header')),
        matching: find.text('memy'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('server-tab-chat')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the local chat tab shows the default text channel beside a scene',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The composer follows the viewer's real membership row, so the store
      // carries one; without it the thread is correctly read-only.
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('clubs/s').set({'ownerId': 'owner', 'name': 'Po'});
      await firestore.doc('clubs/s/members/owner').set({'role': 'owner'});
      // The friends template, because it is the shell's ordinary pairing: a
      // media scene beside the server's own default text channel. Board 05's
      // studio deliberately reads its `Pytania` channel instead, and that
      // exception is proven in `server_podcast_test.dart`.
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [shellServer(ServerType.friends)]
            ..channels = shellChannels(ServerType.friends),
          isRootTab: true,
          initialChannelId: firstMedia(ServerType.friends),
          chatService: fakeChat(firestore: firestore),
        ),
        size: const Size(768, 900),
      );
      expect(
        find.byKey(const ValueKey('server-context-general')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('server-tab-chat')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('server-context-general')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-composer')), findsOneWidget);
    },
  );

  testWidgets(
    'the directory hosts the workspace inline from tablet width and pushes a route below',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [shellServer(ServerType.family)]
        ..channels = shellChannels(ServerType.family);
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: const Size(1100, 800),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-panel')), findsOneWidget);
      expect(find.byType(AppBar), findsNothing, reason: 'the shell owns it');
      await tester.tap(find.byKey(const ValueKey('server-panel-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-directory-s')), findsOneWidget);

      await pumpServers(
        tester,
        ServersScreen(
          key: UniqueKey(),
          repository: repository,
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: const Size(390, 800),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget, reason: 'a route has Back');
      expect(
        find.byKey(const ValueKey('server-open-channels')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-panel-back')), findsNothing);
    },
  );

  testWidgets('loading, error and empty states are honest at every tier', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 768.0, 1440.0]) {
      final server = StreamController<Server?>.broadcast();
      addTearDown(server.close);
      final repository = TestServerRepository()..serverStream = server.stream;
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          key: UniqueKey(),
          serverId: 's',
          repository: repository,
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: Size(width, 700),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      server.addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('To trwa dłużej, niż oczekiwano. Spróbuj ponownie.'),
        findsOneWidget,
      );
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          key: UniqueKey(),
          serverId: 's',
          repository: TestServerRepository()
            ..servers = [shellServer(ServerType.friends)],
          isRootTab: true,
          chatService: fakeChat(),
        ),
        size: Size(width, 700),
      );
      expect(find.text('Nie ma jeszcze kanałów'), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
