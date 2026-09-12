import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_screen_share_capability.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_company_meeting.dart';

import 'server_test_support.dart';

/// Board 04 — `Dla firmy`, błękit.
///
/// The honesty lines this file defends:
///
/// * no number of people anywhere — the board's "6 uczestników" and
///   "24 osoby" in the meeting have no writer (contract G6), so the tiles are
///   the roster and nothing counts them;
/// * a tile exists only for somebody the provider actually reports, and its
///   microphone glyph is that person's real track state (G3);
/// * `HR` and `Zarząd` reach the panel through `users/{uid}/serverChannelRefs`
///   and through nothing else — a member without the pointer never sees the
///   row, because the query never returns it;
/// * the whiteboard has no backend at all (G9) and says so;
/// * the screen share is answered by one platform capability query (contract
///   decision D), and the camera says plainly that publishing one is not
///   built yet (contract §3).
Server companyServer({bool held = false, int members = 24}) => Server(
  id: 's',
  name: 'Studio North',
  description: '',
  ownerId: 'owner',
  type: ServerType.company,
  privacy: ServerPrivacy.inviteOnly,
  memberCount: members,
  defaultChannelId: 'general',
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
  status: held ? 'preparing' : 'active',
);

/// The seeded company template as the workspace reads it back, in Polish.
/// [restricted] is false for a member who holds no `serverChannelRef`, which
/// is exactly what the repository returns for them.
List<ServerChannel> companyChannels({
  ServerChannelLiveness meeting = ServerChannelLiveness.idle,
  String? activeSessionId,
  bool restricted = true,
}) {
  final seeds = serverTemplateChannelsFor(ServerType.company);
  return [
    for (var i = 0; i < seeds.length; i++)
      if (restricted || !seeds[i].restricted)
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
          experience: seeds[i].kind.isMedia ? RoomExperience.community : null,
          mediaMode: seeds[i].mediaMode,
          schemaVersion: 1,
          liveness: seeds[i].kind == ServerChannelKind.meeting
              ? meeting
              : ServerChannelLiveness.idle,
          activeSessionId: seeds[i].kind == ServerChannelKind.meeting
              ? activeSessionId
              : null,
        ),
  ];
}

ClubChatService companyChat({FakeFirebaseFirestore? firestore}) =>
    ClubChatService(
      firestore: firestore ?? FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
      ),
      requestIdFactory: () => 'msg-1',
      messageSendInvoker: (_) async => <Object?, Object?>{},
    );

Widget companyWorkspace(
  TestServerRepository repository, {
  String channelId = 'meeting',
  FakeServerMediaConnector? connector,
  ClubChatService? chat,
  ServerScreenShareCapability? screenShare,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: repository,
  isRootTab: true,
  initialChannelId: channelId,
  chatService: chat ?? companyChat(),
  connector: connector ?? FakeServerMediaConnector(),
  screenShare: screenShare,
);

/// The grant `deriveSessionGrant` writes for the host of a meeting.
const meetingHostSources = [
  'microphone',
  'camera',
  'screen_share',
  'screen_share_audio',
];

/// …and for everybody else in the same meeting.
const meetingGuestSources = ['microphone', 'camera'];

/// Anything that could only come from a presence writer, including the
/// board's own "6 uczestników".
final fabricated = RegExp(
  r'\d+\s*(uczestnik|osob[ay]? rozmawia|widz|słuchacz)',
  caseSensitive: false,
);

const widths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

Finder get join => find.byKey(const ValueKey('server-join'));
Finder get dock => find.byKey(const ValueKey('server-conversation-dock'));
Finder get search => find.byKey(const ValueKey('server-panel-search'));
Finder get screenState =>
    find.byKey(const ValueKey('server-meeting-screen-state'));
Finder get presentationTab =>
    find.byKey(const ValueKey('server-tab-presentation'));
Finder get whiteboardTab =>
    find.byKey(const ValueKey('server-tab-whiteboard'));
Finder get chatTab => find.byKey(const ValueKey('server-tab-chat'));
Finder get shareControl => find.byKey(const ValueKey('server-dock-share'));
Finder get cameraControl => find.byKey(const ValueKey('server-dock-camera'));

/// A dock control is enabled when the button inside it is. What the
/// accessibility API sees of the same control — its role, its name and, above
/// all, that it carries a tap action at all — is asserted in
/// `server_accessibility_test.dart`, which is where that coverage actually
/// lives (it did not exist when this comment first claimed it did).
bool enabled(WidgetTester tester, Finder control) =>
    tester
        .widget<IconButton>(
          find.descendant(of: control, matching: find.byType(IconButton)),
        )
        .onPressed !=
    null;

/// The microphone glyph on one person's tile, which is that person's own
/// track state and nothing else.
Finder tileIcon(String identity, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('server-meeting-tile-$identity')),
  matching: find.byIcon(icon),
);

/// Three people the provider reports: one sending a picture is impossible to
/// fake off-device (a `VideoTrack` cannot be constructed in a widget test),
/// so these exercise the no-picture tile, which is the state that must never
/// invent one.
const team = [
  ServerMediaParticipant(
    identity: 'owner',
    name: 'Kamil',
    isLocal: true,
    isMicrophoneEnabled: true,
  ),
  ServerMediaParticipant(
    identity: 'ola',
    name: 'Ola',
    isLocal: false,
    isSpeaking: true,
    isMicrophoneEnabled: true,
  ),
  ServerMediaParticipant(
    identity: 'marta',
    name: 'Marta',
    isLocal: false,
  ),
];

Future<FakeServerMediaLink> joinMeeting(
  WidgetTester tester,
  FakeServerMediaConnector connector, {
  List<ServerMediaParticipant> roster = team,
}) async {
  await tester.tap(join);
  await tester.pumpAndSettle();
  final link = connector.links.single..setRoster(roster);
  await tester.pumpAndSettle();
  return link;
}

/// The same join into a **live** meeting, where the dock's one-second clock
/// starts and therefore never settles. Pumped explicitly and by less than one
/// second in total, exactly as the direct call screen's own clock is tested.
Future<FakeServerMediaLink> joinLiveMeeting(
  WidgetTester tester,
  FakeServerMediaConnector connector, {
  List<ServerMediaParticipant> roster = team,
}) async {
  await tester.tap(join);
  for (var pump = 0; pump < 6; pump++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  final link = connector.links.single..setRoster(roster);
  await tester.pump(const Duration(milliseconds: 30));
  return link;
}

void main() {
  group('board 04 shell', () {
    testWidgets(
      'the meeting renders at six widths and 200 percent with no tile and '
      'no number of people before a join',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final width in widths) {
          for (final scale in [1.0, 2.0]) {
            final repository = TestServerRepository()
              ..servers = [companyServer()]
              ..channels = companyChannels();
            await pumpServers(
              tester,
              companyWorkspace(repository),
              size: Size(width, 780),
              textScale: scale,
              light: scale == 2,
            );
            final reason = 'company $width ×$scale';
            expect(tester.takeException(), isNull, reason: reason);
            expect(
              find.byType(ServerMeetingTile),
              findsNothing,
              reason: reason,
            );
            expect(
              find.textContaining(fabricated),
              findsNothing,
              reason: reason,
            );
            expect(join, findsOneWidget, reason: reason);
            expect(dock, findsNothing, reason: reason);
            expect(repository.calls, isEmpty, reason: reason);
          }
        }
      },
    );

    testWidgets('each width arranges the meeting for what it can hold', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in widths) {
        await pumpServers(
          tester,
          companyWorkspace(
            TestServerRepository()
              ..servers = [companyServer()]
              ..channels = companyChannels(),
          ),
          size: Size(width, 820),
        );
        final phone = width < ServerWorkspaceScreen.tabletBreakpoint;
        final desktop = width >= ServerWorkspaceScreen.desktopBreakpoint;
        final reason = 'company $width';
        // Phone: the shell's own strip, `Spotkanie | Czat | Kanały`, and the
        // presentation and whiteboard as cards under it.
        expect(
          find.byKey(const ValueKey('server-tab-scene')),
          phone ? findsOneWidget : findsNothing,
          reason: reason,
        );
        // Tablet and desktop: the meeting's own strip.
        expect(
          presentationTab,
          phone ? findsNothing : findsOneWidget,
          reason: reason,
        );
        expect(
          whiteboardTab,
          phone ? findsNothing : findsOneWidget,
          reason: reason,
        );
        // The conversation is a tab exactly where it has nowhere else to be:
        // never twice, and never missing.
        expect(chatTab, desktop ? findsNothing : findsOneWidget,
            reason: reason);
        expect(
          find.byKey(const ValueKey('server-context-panel')),
          desktop ? findsOneWidget : findsNothing,
          reason: reason,
        );
        // `Kanały` is offered exactly once on a phone, by the strip.
        expect(
          find.byKey(const ValueKey('server-open-channels')),
          phone ? findsOneWidget : findsNothing,
          reason: reason,
        );
        expect(
          find.byKey(const ValueKey('server-meeting-board')),
          phone ? findsOneWidget : findsNothing,
          reason: reason,
        );
      }
    });

    testWidgets('the phone strip opens the channel list without leaving the '
        'meeting view', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
        ),
        size: const Size(390, 844),
      );
      await joinMeeting(tester, connector);
      await tester.tap(find.byKey(const ValueKey('server-open-channels')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-panel')), findsOneWidget);
      // Opening the list is an action: nothing about the session changed.
      expect(connector.links.single.disconnects, 0);
      await tester.tap(find.byKey(const ValueKey('server-channel-meeting')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerMeetingTile), findsNWidgets(team.length));
      expect(connector.links.single.disconnects, 0);
    });
  });

  group('panel search', () {
    testWidgets('only the company panel searches, and it filters the real '
        'channel list', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels(),
        ),
        size: const Size(1440, 900),
      );
      expect(search, findsOneWidget);
      expect(find.byKey(const ValueKey('server-channel-hr')), findsOneWidget);
      await tester.enterText(search, 'zarz');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('server-channel-boardroom')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-channel-hr')), findsNothing);
      expect(
        find.byKey(const ValueKey('server-channel-general')),
        findsNothing,
      );
      // A search that matches nothing says that, not "this server has no
      // channels".
      await tester.enterText(search, 'nie ma takiego');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('server-panel-search-empty')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('server-panel-search-clear')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-channel-hr')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-channel-general')),
        findsOneWidget,
      );
    });

    testWidgets('the other four templates have no search field', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        if (type == ServerType.company) continue;
        await pumpServers(
          tester,
          ServerWorkspaceScreen(
            key: UniqueKey(),
            serverId: 's',
            repository: TestServerRepository()
              ..servers = [
                Server(
                  id: 's',
                  name: 'Po godzinach',
                  description: '',
                  ownerId: 'owner',
                  type: type,
                  privacy: ServerPrivacy.private,
                  memberCount: 8,
                  schemaVersion: 1,
                  activationState: 'active',
                ),
              ],
            isRootTab: true,
            chatService: companyChat(),
          ),
          size: const Size(1440, 900),
        );
        expect(search, findsNothing, reason: '$type');
      }
    });
  });

  group('restricted rows', () {
    testWidgets('HR and Zarząd reach the panel only through a real '
        'serverChannelRef', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'member', email: 'member@yo.voice'),
      );
      await firestore.doc('clubs/s').set({
        'serverSchemaVersion': 1,
        'serverType': 'company',
        'name': 'Studio North',
        'ownerId': 'owner',
        'privacy': 'inviteOnly',
        'serverActivationState': 'active',
        'status': 'active',
        'memberCount': 24,
      });
      await firestore.doc('clubs/s/members/member').set({
        'userId': 'member',
        'role': 'member',
      });
      for (final seed in serverTemplateChannelsFor(ServerType.company)) {
        await firestore.doc('clubs/s/channels/${seed.seedKey}').set({
          'serverSchemaVersion': 1,
          'serverId': 's',
          'name': seed.polishName,
          'kind': seed.kind.name,
          'accessMode': seed.restricted ? 'restricted' : 'members',
          'isPrivate': seed.restricted,
          'status': 'active',
          'position': 0,
          if (seed.kind.isMedia) 'roomId': 'room-${seed.seedKey}',
          if (seed.kind.isMedia) 'experience': 'community',
          if (seed.kind.isMedia) 'mediaMode': seed.mediaMode!.name,
        });
      }
      Widget workspace() => ServerWorkspaceScreen(
        key: UniqueKey(),
        serverId: 's',
        repository: ServerService(firestore: firestore, auth: auth),
        isRootTab: true,
        initialChannelId: 'general',
        chatService: companyChat(firestore: firestore),
      );
      await pumpServers(tester, workspace(), size: const Size(1440, 900));
      expect(find.byKey(const ValueKey('server-channel-general')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('server-channel-hr')), findsNothing);
      expect(
        find.byKey(const ValueKey('server-channel-boardroom')),
        findsNothing,
      );
      expect(find.text('HR'), findsNothing);
      expect(find.text('Zarząd'), findsNothing);

      // The pointer is the whole access story: nothing about the channel
      // document changes when it appears.
      await firestore.doc('users/member/serverChannelRefs/hr').set({
        'serverId': 's',
        'channelId': 'hr',
      });
      await pumpServers(tester, workspace(), size: const Size(1440, 900));
      final hr = find.byKey(const ValueKey('server-channel-hr'));
      expect(hr, findsOneWidget);
      expect(
        find.descendant(of: hr, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
      // Still nothing for the row this person was never given.
      expect(
        find.byKey(const ValueKey('server-channel-boardroom')),
        findsNothing,
      );
    });
  });

  group('meeting scene', () {
    testWidgets('before a join the surface says what it is, and joining is '
        'the only way to a track', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [companyServer()]
        ..channels = companyChannels();
      await pumpServers(
        tester,
        companyWorkspace(repository),
        size: const Size(1440, 900),
      );
      expect(
        tester.widget<Text>(screenState).data,
        'Spotkanie się nie rozpoczęło',
      );
      expect(find.text('Rozpocznij spotkanie'), findsOneWidget);
      expect(repository.calls, isEmpty);

      // A live generation somebody else started is joined, not started.
      final live = TestServerRepository()
        ..servers = [companyServer()]
        ..channels = companyChannels(
          meeting: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
          ),
          activeSessionId: 'gen-4',
        );
      await pumpServers(
        tester,
        companyWorkspace(live),
        size: const Size(1440, 900),
      );
      expect(
        tester.widget<Text>(screenState).data,
        'Dołącz do spotkania, aby zobaczyć, co jest udostępniane.',
      );
      expect(find.text('Dołącz do spotkania'), findsOneWidget);
    });

    testWidgets('in session the tiles are the provider roster, with each '
        'microphone drawn from its own track', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      final link = await joinMeeting(tester, connector);
      expect(find.byType(ServerMeetingTile), findsNWidgets(3));
      expect(tileIcon('owner', Icons.mic_rounded), findsOneWidget);
      expect(tileIcon('ola', Icons.mic_rounded), findsOneWidget);
      expect(tileIcon('marta', Icons.mic_off_rounded), findsOneWidget);
      expect(find.text('Ty'), findsOneWidget);
      expect(find.text('Ola'), findsOneWidget);
      expect(
        tester.widget<Text>(screenState).data,
        'Nikt nie udostępnia teraz ekranu.',
      );
      // Nothing counts the people on screen.
      expect(find.textContaining(fabricated), findsNothing);

      // The roster is the only source: when the provider drops somebody the
      // tile goes with them.
      link.setRoster(team.take(2).toList());
      await tester.pumpAndSettle();
      expect(find.byType(ServerMeetingTile), findsNWidgets(2));
      link.setRoster(const []);
      await tester.pumpAndSettle();
      expect(find.byType(ServerMeetingTile), findsNothing);
    });

    testWidgets('the whiteboard is honestly unavailable and offers the real '
        'channel', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [companyServer()]
        ..channels = companyChannels();
      await pumpServers(
        tester,
        companyWorkspace(repository),
        size: const Size(1440, 900),
      );
      await tester.tap(whiteboardTab);
      await tester.pumpAndSettle();
      expect(find.text('Tablica zespołu'), findsOneWidget);
      expect(
        find.textContaining('Na razie nic się tu nie zapisuje'),
        findsOneWidget,
      );
      expect(find.text('Wkrótce'), findsWidgets);
      // The real `Tablica` channel is a destination, and taking it changes
      // the channel rather than pretending the board exists.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('server-meeting-board')),
          matching: find.text('Tablica'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-channel-header')), findsWidgets);
      expect(repository.calls, isEmpty);
    });

    testWidgets('switching between the meeting views never ends the meeting', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
        ),
        size: const Size(768, 1024),
      );
      final link = await joinMeeting(tester, connector);
      expect(dock, findsOneWidget);
      for (final tab in [whiteboardTab, chatTab, presentationTab]) {
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(dock, findsOneWidget);
        expect(link.disconnects, 0);
        expect(link.state, ServerMediaLinkState.connected);
      }
      expect(find.byType(ServerMeetingTile), findsNWidgets(3));
    });
  });

  group('meeting dock', () {
    testWidgets('the dock is board 04s row, and its clock counts from the '
        'server instant', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels(
              meeting: ServerChannelLiveness(
                isLive: true,
                startedAt: DateTime.now().subtract(
                  const Duration(minutes: 12, seconds: 24),
                ),
              ),
              activeSessionId: 'gen-4',
            )
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
          screenShare: ServerScreenShareCapability.web,
        ),
        size: const Size(1440, 900),
      );
      await joinLiveMeeting(tester, connector);
      expect(
        find.byKey(const ValueKey('server-dock-microphone')),
        findsOneWidget,
      );
      expect(cameraControl, findsOneWidget);
      expect(shareControl, findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-dock-whiteboard')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-dock-leave')), findsOneWidget);
      final elapsed = tester
          .widget<Text>(find.byKey(const ValueKey('server-dock-elapsed')))
          .data;
      expect(elapsed, matches(RegExp(r'^12:2[3-6]$')));

      // `Tablica` in the dock selects the view; the meeting carries on.
      await tester.tap(find.byKey(const ValueKey('server-dock-whiteboard')));
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Tablica zespołu'), findsOneWidget);
      expect(connector.links.single.disconnects, 0);

      // Two seconds of pumped time later the clock is still the same clock —
      // it keeps counting from the server's instant and never restarts at
      // zero. (How fast it ticks is wall-clock behaviour: `DateTime.now()`
      // does not move with the test's own clock, so the cadence is the
      // shipped `Timer.periodic` the direct call screen already uses.)
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('server-dock-elapsed')))
            .data,
        matches(RegExp(r'^12:2[3-9]$')),
      );
    });

    testWidgets('a meeting with no server instant shows no clock at all', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      await joinMeeting(tester, connector);
      expect(dock, findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-dock-elapsed')),
        findsNothing,
      );
    });

    testWidgets('every meeting control stays on screen at 320 px and 200 '
        'percent text', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 1100 × 2 is the cell that found the in-session overflow: it is the
      // narrowest width with three panels AND a context column, so the
      // meeting's tiles, the conversation's composer and a five-control dock
      // all compete for one 760-px column. The matrix lists 1100 and used to
      // skip it here.
      for (final (width, scale) in <(double, double)>[
        (320, 2),
        (390, 1),
        (768, 2),
        (1100, 2),
        (1440, 1),
      ]) {
        final connector = FakeServerMediaConnector();
        await pumpServers(
          tester,
          companyWorkspace(
            TestServerRepository()
              ..servers = [companyServer()]
              ..channels = companyChannels(
                meeting: ServerChannelLiveness(
                  isLive: true,
                  startedAt: DateTime.now().subtract(
                    const Duration(minutes: 8),
                  ),
                ),
                activeSessionId: 'gen-4',
              )
              ..permittedTrackSources = meetingHostSources,
            connector: connector,
            screenShare: ServerScreenShareCapability.web,
          ),
          size: Size(width, 780),
          textScale: scale,
        );
        await joinLiveMeeting(tester, connector);
        final reason = 'meeting dock $width ×$scale';
        // A RenderFlex that does not fit is an exception in a test; the five
        // controls take a row of their own rather than being clipped.
        expect(tester.takeException(), isNull, reason: reason);
        expect(
          find.byKey(const ValueKey('server-dock-stacked')),
          findsOneWidget,
          reason: reason,
        );
        for (final control in const [
          'server-dock-microphone',
          'server-dock-headphones',
          'server-dock-camera',
          'server-dock-share',
          'server-dock-leave',
        ]) {
          expect(
            find.byKey(ValueKey(control)),
            findsOneWidget,
            reason: '$reason $control',
          );
        }
        expect(
          find.byKey(const ValueKey('server-dock-elapsed')),
          findsOneWidget,
          reason: reason,
        );
      }
    });

    testWidgets('the camera control is present, disabled and says why', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
          screenShare: ServerScreenShareCapability.web,
        ),
        size: const Size(1440, 900),
      );
      await joinMeeting(tester, connector);
      expect(enabled(tester, cameraControl), isFalse);
      expect(
        find.textContaining('Włączenie własnej kamery jeszcze nie działa'),
        findsOneWidget,
      );
    });
  });

  group('screen share follows the platform capability', () {
    testWidgets('in a browser the host can start and stop a share', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
          screenShare: ServerScreenShareCapability.web,
        ),
        size: const Size(1440, 900),
      );
      final link = await joinMeeting(tester, connector);
      expect(enabled(tester, shareControl), isTrue);
      await tester.tap(shareControl);
      await tester.pumpAndSettle();
      expect(link.screenShareCalls, [true]);
      expect(link.isScreenShareEnabled, isTrue);
      await tester.tap(shareControl);
      await tester.pumpAndSettle();
      expect(link.screenShareCalls, [true, false]);
      expect(link.isScreenShareEnabled, isFalse);
    });

    testWidgets('on a phone the control is visibly unavailable and the '
        'reason is on screen', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels()
            ..permittedTrackSources = meetingHostSources,
          connector: connector,
          screenShare: ServerScreenShareCapability.mobile,
        ),
        size: const Size(390, 844),
      );
      final link = await joinMeeting(tester, connector);
      expect(shareControl, findsOneWidget);
      expect(enabled(tester, shareControl), isFalse);
      await tester.tap(shareControl, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(link.screenShareCalls, isEmpty);
      expect(
        find.textContaining('działa na razie w przeglądarce'),
        findsOneWidget,
      );
    });

    testWidgets('a guest is told who shares, even in a browser', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        companyWorkspace(
          TestServerRepository()
            ..servers = [companyServer()]
            ..channels = companyChannels(activeSessionId: 'gen-4')
            ..sessionRole = 'guest'
            ..permittedTrackSources = meetingGuestSources,
          connector: connector,
          screenShare: ServerScreenShareCapability.web,
        ),
        size: const Size(1440, 900),
      );
      final link = await joinMeeting(tester, connector);
      expect(enabled(tester, shareControl), isFalse);
      expect(link.screenShareCalls, isEmpty);
      expect(
        find.text('Ekran udostępnia osoba, która rozpoczęła spotkanie.'),
        findsOneWidget,
      );
    });

    test('the capability query answers per platform, never per feature flag', () {
      expect(serverScreenShareCapability(isWeb: true).canStartShare, isTrue);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final capability = serverScreenShareCapability(
          isWeb: false,
          platform: platform,
        );
        expect(capability.canStartShare, isFalse, reason: '$platform');
        expect(
          capability.reason,
          ServerScreenShareReason.mobileNotBuilt,
          reason: '$platform',
        );
      }
      expect(
        serverScreenShareCapability(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ).reason,
        ServerScreenShareReason.desktopUnverified,
      );
    });
  });

  group('grants', () {
    test('a meeting grant is read exactly as deriveSessionGrant writes it', () {
      final host = ServerSessionConnection.fromMap({
        'serverUrl': 'wss://livekit.test',
        'participantToken': 'token',
        'roomName': 'room',
        'participantIdentity': 'owner',
        'participantName': 'Kamil',
        'roomId': 'room',
        'sessionId': 'gen-4',
        'sessionRole': 'host',
        'permissions': {'canPublish': true, 'canSubscribe': true},
        'permittedTrackSources': meetingHostSources,
      });
      expect(host.canPublishMicrophone, isTrue);
      expect(host.canPublishCamera, isTrue);
      expect(host.canPublishScreenShare, isTrue);
      final guest = ServerSessionConnection.fromMap({
        'serverUrl': 'wss://livekit.test',
        'participantToken': 'token',
        'roomName': 'room',
        'participantIdentity': 'ola',
        'participantName': 'Ola',
        'roomId': 'room',
        'sessionId': 'gen-4',
        'sessionRole': 'guest',
        'permissions': {'canPublish': true, 'canSubscribe': true},
        'permittedTrackSources': meetingGuestSources,
      });
      expect(guest.canPublishCamera, isTrue);
      expect(guest.canPublishScreenShare, isFalse);
    });
  });
}
