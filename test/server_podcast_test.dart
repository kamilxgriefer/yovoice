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
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_community_stage.dart';

import 'server_test_support.dart';

/// Board 05 — `Dla podcastu`.
///
/// Two things are asserted here over and over, because they are what this
/// board is most tempting to fake. First, **no count**: the mockup prints
/// "84 słuchaczy" three times and nothing writes a listener count (contract
/// G6), so the strongest cases below prove no such number is ever drawn —
/// before or after joining. Second, **no recording claim**: recording has no
/// contract at all (contract §3), so "Audycja jest nagrywana" can never
/// appear, and what the studio says instead is the opposite.
///
/// What *is* real: the liveness projection, the reviewed token path,
/// `setServerSessionHandV1`, the server's own questions channel, and the
/// session role the server signs into each participant's access token.
Server podcastServer({
  bool held = false,
  String description = 'Rozmowy o tym, co dzieje się między słowami.',
  int members = 132,
}) => Server(
  id: 's',
  name: 'Między słowami',
  description: description,
  ownerId: 'owner',
  type: ServerType.podcast,
  privacy: ServerPrivacy.public,
  memberCount: members,
  defaultChannelId: 'discussion',
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
  status: held ? 'preparing' : 'active',
);

List<ServerChannel> podcastChannels({
  ServerChannelLiveness studio = ServerChannelLiveness.idle,
  String? activeSessionId,
  Set<ServerChannelKind> without = const {},
}) {
  final seeds = serverTemplateChannelsFor(ServerType.podcast);
  return [
    for (var i = 0; i < seeds.length; i++)
      if (!without.contains(seeds[i].kind))
        ServerChannel(
          id: seeds[i].seedKey,
          serverId: 's',
          name: seeds[i].polishName,
          kind: seeds[i].kind,
          position: i,
          roomId: seeds[i].kind.isMedia ? 'room-${seeds[i].seedKey}' : null,
          experience: !seeds[i].kind.isMedia
              ? null
              : seeds[i].kind == ServerChannelKind.stage
              ? RoomExperience.broadcast
              : RoomExperience.community,
          mediaMode: seeds[i].mediaMode,
          schemaVersion: 1,
          liveness: seeds[i].kind == ServerChannelKind.stage
              ? studio
              : ServerChannelLiveness.idle,
          activeSessionId: seeds[i].kind == ServerChannelKind.stage
              ? activeSessionId
              : null,
        ),
  ];
}

ClubChatService podcastChat({FakeFirebaseFirestore? firestore}) =>
    ClubChatService(
      firestore: firestore ?? FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
      ),
      requestIdFactory: () => 'msg-1',
      messageSendInvoker: (_) async => <Object?, Object?>{},
    );

Widget podcastWorkspace(
  TestServerRepository repository, {
  String channelId = 'studio',
  FakeServerMediaConnector? connector,
  ClubChatService? chat,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: repository,
  isRootTab: true,
  initialChannelId: channelId,
  chatService: chat ?? podcastChat(),
  connector: connector ?? FakeServerMediaConnector(),
);

/// Any phrasing that could only come from a presence, vote or recording
/// writer — none of which exists.
final fabricated = RegExp(
  r'\d+\s*(widz|słuchacz|osob[ay]? rozmawia|głos(ów|y)?\b)|(?<!nie )jest\s+nagrywan',
  caseSensitive: false,
);

Finder get studio => find.byKey(const ValueKey('server-podcast-scene'));
Finder get stageRow => find.byKey(const ValueKey('server-podcast-stage'));
Finder get audience => find.byKey(const ValueKey('server-podcast-audience'));
Finder get waveform => find.byKey(const ValueKey('server-podcast-waveform'));
Finder get recording => find.byKey(const ValueKey('server-podcast-recording'));
Finder get ask => find.byKey(const ValueKey('server-podcast-ask'));
Finder get hand => find.byKey(const ValueKey('server-podcast-hand'));
Finder get livePill => find.byKey(const ValueKey('server-live-pill'));
Finder get join => find.byKey(const ValueKey('server-join'));
Finder get dockStatus => find.byKey(const ValueKey('server-dock-status'));

String dockText(WidgetTester tester) =>
    tester.widget<Text>(dockStatus).data ?? '';

final live = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 9, 12, 19, 40),
);

const widths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

/// A studio in session: the host and two guests the server signed as such,
/// plus listeners, exactly as board 05 draws them.
const broadcast = [
  ServerMediaParticipant(
    identity: 'maja',
    name: 'Maja',
    isLocal: false,
    isSpeaking: true,
    isMicrophoneEnabled: true,
    sessionRole: 'host',
  ),
  ServerMediaParticipant(
    identity: 'kamil',
    name: 'Kamil',
    isLocal: false,
    isMicrophoneEnabled: true,
    sessionRole: 'guest',
  ),
  ServerMediaParticipant(
    identity: 'ola',
    name: 'Ola',
    isLocal: false,
    isMicrophoneEnabled: true,
    sessionRole: 'guest',
  ),
  ServerMediaParticipant(
    identity: 'owner',
    name: 'Kasia',
    isLocal: true,
    sessionRole: 'listener',
  ),
  ServerMediaParticipant(
    identity: 'bartek',
    name: 'Bartek',
    isLocal: false,
    sessionRole: 'listener',
  ),
];

/// The repository of somebody who joined a live generation as a listener:
/// `deriveSessionGrant` gives that person no track source at all.
TestServerRepository listenerRepository() =>
    TestServerRepository()
      ..servers = [podcastServer()]
      ..channels = podcastChannels(studio: live, activeSessionId: 'gen-7')
      ..myRole = ServerMemberRole.member
      ..sessionRole = 'listener'
      ..permittedTrackSources = const [];

Future<FakeServerMediaLink> joinAsListener(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  double textScale = 1,
  bool light = false,
  List<ServerMediaParticipant> roster = broadcast,
}) async {
  final connector = FakeServerMediaConnector();
  await pumpServers(
    tester,
    podcastWorkspace(listenerRepository(), connector: connector),
    size: size,
    textScale: textScale,
    light: light,
  );
  await tester.tap(join);
  await tester.pumpAndSettle();
  final link = connector.links.single;
  link.setRoster(roster);
  await tester.pumpAndSettle();
  return link;
}

void main() {
  testWidgets('the desktop studio is an audio stage, never a video player', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(1440, 900),
    );
    expect(studio, findsOneWidget);
    // Board 02's 16:9 player belongs to the community template and to
    // nothing else; the spec says so in as many words.
    expect(find.byKey(const ValueKey('server-community-scene')), findsNothing);
    expect(find.byType(ServerCommunityStage), findsNothing);
    expect(find.text('Studio LIVE'), findsWidgets);
    expect(livePill, findsWidgets);
    expect(find.textContaining('Na żywo od'), findsWidgets);
    expect(find.textContaining(fabricated), findsNothing);
  });

  testWidgets('before joining the studio names nobody and counts nobody', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live)
          ..myRole = ServerMemberRole.member,
      ),
      size: const Size(1440, 900),
    );
    // `channelSessions` and the V1 room anchor are not client-readable
    // (contract G2/G3), so there is no pre-join host, guest or audience.
    expect(stageRow, findsNothing);
    expect(audience, findsNothing);
    expect(find.text('Prowadzący'), findsNothing);
    expect(find.text('Gość'), findsNothing);
    expect(find.text('Dołącz, aby słuchać na żywo.'), findsOneWidget);
    // An audio stage is listened to; `Oglądaj` belongs to board 02's video.
    expect(find.text('Słuchaj'), findsOneWidget);
    expect(find.text('Oglądaj'), findsNothing);
  });

  testWidgets('a quiet studio says so and offers a listener nothing to start',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels()
          ..myRole = ServerMemberRole.member,
      ),
      size: const Size(1440, 900),
    );
    expect(find.text('Scena jeszcze nie nadaje'), findsWidgets);
    expect(livePill, findsNothing);
    // `startSession` needs moderator power on a stage, so no button is drawn
    // for a member that the Rules would refuse.
    expect(join, findsNothing);
    expect(
      find.text('Będzie można słuchać, gdy scena zacznie nadawać.'),
      findsOneWidget,
    );
  });

  testWidgets('in session the stage is the roles the server signed, and the '
      'waveform is only the speaking signal', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await joinAsListener(tester);
    expect(stageRow, findsOneWidget);
    expect(find.text('Maja'), findsOneWidget);
    expect(find.text('Prowadzący'), findsOneWidget);
    expect(find.text('Kamil'), findsOneWidget);
    expect(find.text('Ola'), findsOneWidget);
    expect(find.text('Gość'), findsNWidgets(2));
    // Only Maja is speaking, so exactly one waveform exists.
    expect(waveform, findsOneWidget);
    // The listeners are the audience and are never named on the stage.
    expect(audience, findsOneWidget);
    expect(find.textContaining(fabricated), findsNothing);
  });

  testWidgets('a role the server did not sign never reaches the stage', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await joinAsListener(
      tester,
      roster: const [
        // No metadata at all, and metadata that names a different identity:
        // neither is authority, so neither is drawn as a host.
        ServerMediaParticipant(
          identity: 'unknown',
          name: 'Nieznany',
          isLocal: false,
          isMicrophoneEnabled: true,
        ),
        ServerMediaParticipant(
          identity: 'owner',
          name: 'Kasia',
          isLocal: true,
          sessionRole: 'listener',
        ),
      ],
    );
    expect(stageRow, findsNothing);
    expect(find.text('Prowadzący'), findsNothing);
    expect(find.text('Nikt nie jest teraz na antenie.'), findsOneWidget);
    expect(audience, findsOneWidget);
  });

  testWidgets('the audience strip counts avatars that did not fit, never '
      'listeners', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await joinAsListener(
      tester,
      size: const Size(390, 844),
      roster: [
        broadcast.first,
        for (var index = 0; index < 12; index++)
          ServerMediaParticipant(
            identity: 'listener-$index',
            name: 'Słuchacz $index',
            isLocal: false,
            sessionRole: 'listener',
          ),
      ],
    );
    expect(audience, findsOneWidget);
    final overflow = find.byKey(
      const ValueKey('server-podcast-audience-overflow'),
    );
    expect(overflow, findsOneWidget);
    // `+N` is the avatars this row could not show, which is why it moves with
    // the width. It is not a listener count and never reads as one.
    expect(find.textContaining(fabricated), findsNothing);
  });

  testWidgets('recording is never claimed, and the studio says the opposite', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await joinAsListener(tester);
    expect(recording, findsOneWidget);
    expect(
      find.descendant(of: recording, matching: find.text('Nagrywanie audycji · Wkrótce')),
      findsOneWidget,
    );
    expect(
      find.text('Nagrywanie jeszcze nie działa — nic z transmisji się nie zapisuje.'),
      findsOneWidget,
    );
    // The board's lit red dot: there is no recording job to light it, so the
    // mark stays the unlit outline and nothing on screen claims otherwise.
    expect(
      find.descendant(
        of: recording,
        matching: find.byIcon(Icons.radio_button_unchecked),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(fabricated), findsNothing);
  });

  // The gate's F-3. At 1100 x 200 % the marker rendered as `Nagrywanie
  // audycji ·` — a dangling middle dot, the `Wkrótce` gone and not even an
  // ellipsis to say something had been cut — in both themes, while at
  // 1440 x 200 % the same marker rendered whole. The mechanism is `Chip`: it
  // takes its label's intrinsic width, so the label was given a two-line
  // layout inside a box sized for one and the second line was painted
  // outside it and clipped. An unavailable feature that loses the word
  // making it unavailable reads as a live one, which is the honesty rule
  // this whole board is built around — so the marker may not be a `Chip` and
  // its label may not be truncatable.
  testWidgets('the recording marker keeps its "Wkrótce" whole at 1100 and '
      '200 percent, in both themes', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const labelText = 'Nagrywanie audycji · Wkrótce';
    for (final light in [false, true]) {
      final theme = light ? 'pearl' : 'dark';
      await pumpServers(
        tester,
        podcastWorkspace(
          TestServerRepository()
            ..servers = [podcastServer()]
            ..channels = podcastChannels(studio: live),
        ),
        size: const Size(1100, 800),
        textScale: 2,
        light: light,
      );
      expect(recording, findsOneWidget, reason: theme);
      expect(
        find.descendant(of: recording, matching: find.byType(Chip)),
        findsNothing,
        reason: '$theme — a Chip sizes to its label\'s intrinsic width and '
            'clips what will not fit its own box; this marker has to be a '
            'pill that grows with its label instead',
      );
      final labelFinder = find.descendant(
        of: recording,
        matching: find.text(labelText),
      );
      expect(labelFinder, findsOneWidget, reason: theme);
      final label = tester.widget<Text>(labelFinder);
      expect(
        label.maxLines,
        isNull,
        reason: '$theme — a line limit on this marker is a line the reader '
            'never sees',
      );
      expect(
        label.overflow,
        isNot(TextOverflow.ellipsis),
        reason: '$theme — this label must wrap, never truncate',
      );
      // And it really is drawn inside the pill rather than past its edge.
      final pill = find.byKey(const ValueKey('server-podcast-recording-pill'));
      expect(pill, findsOneWidget, reason: theme);
      final labelRect = tester.getRect(labelFinder);
      final pillRect = tester.getRect(pill);
      expect(
        labelRect.bottom,
        lessThanOrEqualTo(pillRect.bottom + 0.5),
        reason: '$theme — the last line is painted outside the pill',
      );
      expect(
        labelRect.right,
        lessThanOrEqualTo(pillRect.right + 0.5),
        reason: '$theme — the label runs past the pill\'s edge',
      );
      expect(tester.takeException(), isNull, reason: theme);
    }
  });

  testWidgets('Poproś o głos reaches setServerSessionHandV1 and comes back', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = listenerRepository();
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      podcastWorkspace(repository, connector: connector),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    connector.links.single.setRoster(broadcast);
    await tester.pumpAndSettle();
    await tester.ensureVisible(hand);
    await tester.tap(hand);
    await tester.pumpAndSettle();
    expect(repository.calls.map((call) => call.$1), [
      'createServerChannelTokenV1',
      'setServerSessionHandV1',
    ]);
    expect(repository.calls.last.$2, {
      'serverId': 's',
      'channelId': 'studio',
      'sessionId': 'gen-7',
      'requestId': 'request-2',
      'raised': true,
    });
    // The only state shown is the receipt of its own call: the participant
    // document is not readable, so nothing here guesses at a queue.
    expect(find.text('Prowadzący widzą Twoją prośbę.'), findsOneWidget);
    expect(find.text('Anuluj prośbę o głos'), findsOneWidget);
  });

  testWidgets('a refused hand is one sentence and never the raw code', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = listenerRepository()
      ..failNextCall['setServerSessionHandV1'] = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'raw',
      );
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      podcastWorkspace(repository, connector: connector),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    connector.links.single.setRoster(broadcast);
    await tester.pumpAndSettle();
    await tester.ensureVisible(hand);
    await tester.tap(hand);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-podcast-hand-error')),
      findsOneWidget,
    );
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('raw'), findsNothing);
  });

  testWidgets('the generation host is never offered the queue', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live, activeSessionId: 'gen-7')
          ..sessionRole = 'host',
        connector: connector,
      ),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    connector.links.single.setRoster(const [
      ServerMediaParticipant(
        identity: 'owner',
        name: 'Kasia',
        isLocal: true,
        isMicrophoneEnabled: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(hand, findsNothing);
    // The receipt is this device's own authority, so the local participant is
    // drawn as the host even when the provider carried no metadata for them.
    expect(find.text('Prowadzący'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-podcast-hand-state')),
      findsOneWidget,
    );
  });

  testWidgets('Zadaj pytanie opens the real questions channel', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(1440, 900),
    );
    await tester.ensureVisible(ask);
    await tester.tap(ask);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-thread-questions')),
      findsOneWidget,
    );
    expect(studio, findsNothing);
  });

  testWidgets('no questions channel means no Zadaj pytanie at all', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(
            studio: live,
            without: const {ServerChannelKind.questions},
          ),
      ),
      size: const Size(1440, 900),
    );
    expect(studio, findsOneWidget);
    expect(ask, findsNothing);
  });

  testWidgets('the desktop context panel is the listeners questions over the '
      'real channel', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(1440, 900),
    );
    expect(find.byKey(const ValueKey('server-context-panel')), findsOneWidget);
    // Board 05 reads questions beside the studio — a real channel of its own,
    // not the podcast's discussion channel.
    expect(find.text('Pytania słuchaczy · #Pytania'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-context-questions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-context-discussion')),
      findsNothing,
    );
  });

  testWidgets('the tablet local tabs read Studio LIVE | Pytania', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(900, 900),
    );
    expect(find.byKey(const ValueKey('server-tab-scene')), findsOneWidget);
    final chat = find.byKey(const ValueKey('server-tab-chat'));
    expect(chat, findsOneWidget);
    expect(find.text('Pytania'), findsWidgets);
    expect(find.text('Czat'), findsNothing);
    await tester.tap(chat);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-context-questions')),
      findsOneWidget,
    );
  });

  testWidgets('the phone keeps the studio, the Kanały entry and the one '
      'action on the surface', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(390, 844),
    );
    expect(studio, findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-open-channels')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('server-tab-scene')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-tab-chat')), findsOneWidget);
    // `Pytania` is a tab here, so the phone draws one control to that place,
    // not two — board 05's phone pins `Poproś o głos` and nothing else.
    expect(ask, findsNothing);
    expect(find.text('Pytania'), findsWidgets);
    // The action is pinned to the bottom of the scene, not left below the
    // fold of a scroll the board never shows.
    final action = tester.getRect(join);
    expect(action.bottom, lessThanOrEqualTo(844));
    expect(action.top, greaterThan(0));
  });

  testWidgets('Następny odcinek and Ostatnie odcinki are honest modules with '
      'a real channel behind each', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live),
      ),
      size: const Size(1440, 900),
    );
    final next = find.byKey(const ValueKey('server-podcast-next-episode'));
    final recent = find.byKey(
      const ValueKey('server-podcast-recent-episodes'),
    );
    expect(next, findsOneWidget);
    expect(recent, findsOneWidget);
    // Episodes have a channel kind and no persistence (contract G9): both
    // actions are visibly disabled beside `Wkrótce`, and no episode title,
    // date or length is drawn anywhere.
    for (final label in ['Przypomnij', 'Odtwórz']) {
      expect(
        tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
        ).onPressed,
        isNull,
      );
    }
    expect(find.text('Wkrótce'), findsWidgets);
    await tester.ensureVisible(find.descendant(of: recent, matching: find.text('Odcinki')));
    await tester.tap(find.descendant(of: recent, matching: find.text('Odcinki')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-module-episodes')),
      findsOneWidget,
    );
  });

  testWidgets('a podcast server without its module channels shows no card for '
      'what is not there', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(
            studio: live,
            without: const {
              ServerChannelKind.events,
              ServerChannelKind.episodes,
            },
          ),
      ),
      size: const Size(1440, 900),
    );
    expect(studio, findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-podcast-next-episode')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('server-podcast-recent-episodes')),
      findsNothing,
    );
  });

  testWidgets('a held podcast server shows no studio surface', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [podcastServer(held: true)]
      ..channels = podcastChannels();
    await pumpServers(
      tester,
      podcastWorkspace(repository),
      size: const Size(1440, 900),
    );
    expect(studio, findsNothing);
    expect(stageRow, findsNothing);
    expect(tester.widget<FilledButton>(join).onPressed, isNull);
    expect(repository.calls, isEmpty);
  });

  testWidgets('the dock tells listening from broadcasting', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await joinAsListener(tester, size: const Size(390, 844));
    // Board 05's "Słuchasz • Studio LIVE": the word, the glyph and the
    // controls all differ from broadcasting, so the state never depends on
    // colour alone.
    expect(dockText(tester), 'Słuchasz');
    expect(find.text('Studio LIVE'), findsWidgets);
    expect(
      find.byKey(const ValueKey('server-dock-microphone')),
      findsNothing,
      reason: 'a listener grant carries no track source at all',
    );
    expect(
      find.byKey(const ValueKey('server-dock-headphones')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.headphones_rounded), findsWidgets);
  });

  testWidgets('a publisher dock says on air and carries a microphone', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      podcastWorkspace(
        TestServerRepository()
          ..servers = [podcastServer()]
          ..channels = podcastChannels(studio: live, activeSessionId: 'gen-7')
          ..sessionRole = 'host',
        connector: connector,
      ),
      size: const Size(390, 844),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(dockText(tester), 'Na antenie');
    expect(
      find.byKey(const ValueKey('server-dock-microphone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-dock-headphones')),
      findsOneWidget,
    );
    // Nothing opened the microphone: joining is a join, never a broadcast.
    expect(connector.links.single.microphoneCalls, isEmpty);
  });

  testWidgets('the live marker survives 200 percent on a 320 px phone, dock '
      'and all', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Found in a rendered frame, not in an assertion: with a dock on screen
    // the shell's own header block is bounded to half of what is left, and at
    // 200 % text it cut the `NA ŻYWO` pill down to a coral bar seven pixels
    // tall. The studio carries its own name and live line for exactly that
    // reason, pinned above its scroll.
    await joinAsListener(tester, size: const Size(320, 760), textScale: 2);
    expect(find.byKey(const ValueKey('server-podcast-title')), findsOneWidget);
    expect(livePill, findsWidgets);
    for (final element in tester.elementList(livePill)) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(
        rect.height,
        greaterThan(26),
        reason: 'the pill must read as a word, not a bar',
      );
      expect(rect.bottom, lessThanOrEqualTo(760));
      expect(rect.top, greaterThanOrEqualTo(0));
    }
    final liveness = tester.getRect(
      find.byKey(const ValueKey('server-podcast-liveness')),
    );
    expect(liveness.bottom, lessThanOrEqualTo(760));
  });

  testWidgets('the studio survives six widths and 200 percent in both themes',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in widths) {
      for (final (scale, light) in const [(1.0, false), (2.0, false), (1.0, true)]) {
        await pumpServers(
          tester,
          podcastWorkspace(
            TestServerRepository()
              ..servers = [podcastServer()]
              ..channels = podcastChannels(studio: live),
          ),
          size: Size(width, 900),
          textScale: scale,
          light: light,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$width at $scale, light $light',
        );
        expect(
          find.textContaining(fabricated),
          findsNothing,
          reason: '$width at $scale, light $light',
        );
      }
    }
  });
}
