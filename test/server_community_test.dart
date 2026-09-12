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

/// Board 02 — `Dla społeczności`.
///
/// Everything asserted here is either a real contract (the liveness map, the
/// token path, `setServerSessionHandV1`, the member roster) or the deliberate
/// absence of one. The counts the mockup shows — "126 widzów", "84 słuchaczy",
/// "4 osoby rozmawiają" — have no writer at all, so the strongest assertions
/// in this file are the ones that prove no number is ever drawn.
Server communityServer({
  bool held = false,
  String description = 'Rozmowy na żywo, inspirujące osoby, wspólna pasja.',
  int members = 248,
}) => Server(
  id: 's',
  name: 'Tech po godzinach',
  description: description,
  ownerId: 'owner',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  memberCount: members,
  defaultChannelId: 'general',
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
  status: held ? 'preparing' : 'active',
);

List<ServerChannel> communityChannels({
  ServerChannelLiveness stage = ServerChannelLiveness.idle,
  String? activeSessionId,
  bool withEvents = true,

  /// Board 05's audio stage, for the comparisons that prove the community's
  /// video stage is treated differently. Null keeps the template's own mode.
  ServerMediaMode? stageMedia,
}) {
  final seeds = serverTemplateChannelsFor(ServerType.community);
  return [
    for (var i = 0; i < seeds.length; i++)
      if (withEvents || seeds[i].kind != ServerChannelKind.events)
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
          mediaMode: seeds[i].kind == ServerChannelKind.stage
              ? (stageMedia ?? seeds[i].mediaMode)
              : seeds[i].mediaMode,
          schemaVersion: 1,
          liveness: seeds[i].kind == ServerChannelKind.stage
              ? stage
              : ServerChannelLiveness.idle,
          activeSessionId: seeds[i].kind == ServerChannelKind.stage
              ? activeSessionId
              : null,
        ),
  ];
}

ClubChatService communityChat({FakeFirebaseFirestore? firestore}) =>
    ClubChatService(
      firestore: firestore ?? FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
      ),
      requestIdFactory: () => 'msg-1',
      messageSendInvoker: (_) async => <Object?, Object?>{},
    );

Widget communityWorkspace(
  TestServerRepository repository, {
  String channelId = 'stage',
  FakeServerMediaConnector? connector,
  ClubChatService? chat,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: repository,
  isRootTab: true,
  initialChannelId: channelId,
  chatService: chat ?? communityChat(),
  connector: connector ?? FakeServerMediaConnector(),
);

/// Any phrasing that could only come from a presence or reaction writer.
final fabricated = RegExp(
  r'\d+\s*(widz|słuchacz|osob[ay]? rozmawia|reakcj)',
  caseSensitive: false,
);

Finder get stage => find.byKey(const ValueKey('server-community-scene'));
Finder get livePill => find.byKey(const ValueKey('server-live-pill'));
Finder get hand => find.byKey(const ValueKey('server-community-hand'));
Finder get join => find.byKey(const ValueKey('server-join'));

const widths = [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0];

void main() {
  testWidgets('the desktop stage is a 16:9 scene with no count anywhere', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );

    expect(stage, findsOneWidget);
    final ratio = tester.widget<AspectRatio>(stage).aspectRatio;
    expect(ratio, closeTo(16 / 9, 0.001));
    final rect = tester.getRect(stage);
    expect(rect.width / rect.height, closeTo(16 / 9, 0.02));
    // A 16:9 scene in a 1100 px column would be 619 px tall and push the
    // title, the actions and the event card off the surface.
    expect(
      rect.height,
      lessThanOrEqualTo(ServerCommunityStage.maxStageHeight + 0.5),
    );

    // The picture and everything written under it share one left edge: a
    // bounded scene centred in a wide column leaves the description, the
    // actions and the event card hanging off a different one.
    final description = tester.getRect(
      find.byKey(const ValueKey('server-community-description')),
    );
    expect(rect.left, closeTo(description.left, 0.5));

    // The shell's channel header already names the channel over the scene,
    // and the board's session title has no source, so the scene does not
    // repeat the name under the picture at this width.
    expect(find.byKey(const ValueKey('server-community-title')), findsNothing);
    expect(find.text('Scena LIVE'), findsWidgets);
    expect(
      find.text('Rozmowy na żywo, inspirujące osoby, wspólna pasja.'),
      findsOneWidget,
    );
    // Not live, so no pill anywhere — including the panel row.
    expect(livePill, findsNothing);
    expect(find.text('Scena jeszcze nie nadaje'), findsWidgets);
    expect(find.textContaining(fabricated), findsNothing);
    // Nothing counts a reaction, so no reaction is drawn.
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(repository.calls, isEmpty);
  });

  testWidgets('a live stage says since when and never how many', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 19, 40),
        ),
      );
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );

    expect(livePill, findsWidgets);
    expect(find.text('Na żywo od 19:40'), findsWidgets);
    expect(find.textContaining(fabricated), findsNothing);
    // The pill rides on the scene itself, as the board draws it.
    final pillOnStage = find.descendant(of: stage, matching: livePill);
    expect(pillOnStage, findsOneWidget);
    expect(
      find.text('Dołącz, aby oglądać i słuchać.'),
      findsOneWidget,
    );
  });

  testWidgets('the ordinary Salon stays a conversation, not a stage', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository, channelId: 'lounge'),
      size: const Size(1440, 900),
    );

    expect(stage, findsNothing);
    expect(find.byKey(const ValueKey('server-community-title')), findsNothing);
    expect(find.text('Dołącz do rozmowy'), findsWidgets);
    expect(find.text('Nikt jeszcze nie rozmawia'), findsWidgets);

    // And selecting the stage from the panel does switch scenes.
    await tester.tap(find.byKey(const ValueKey('server-channel-stage')));
    await tester.pumpAndSettle();
    expect(stage, findsOneWidget);
  });

  testWidgets('Obserwuj and Udostępnij are labelled unavailable, not broken', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );

    for (final key in const [
      ValueKey('server-community-follow'),
      ValueKey('server-community-share'),
    ]) {
      final finder = find.byKey(key);
      expect(finder, findsOneWidget, reason: '$key');
      expect(
        tester.widget<OutlinedButton>(finder).onPressed,
        isNull,
        reason: '$key is not wired to anything that would fail',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-community-secondary-actions')),
        matching: find.text('Wkrótce'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the next-event card is honest and only when the channel exists',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    final card = find.byKey(const ValueKey('server-community-event-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Dołączę')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: card, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    // The real channel is the way in.
    final way = find.descendant(of: card, matching: find.text('Wydarzenia'));
    await tester.ensureVisible(way);
    await tester.pumpAndSettle();
    await tester.tap(way);
    await tester.pumpAndSettle();
    expect(stage, findsNothing);

    final without = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(withEvents: false);
    await pumpServers(
      tester,
      communityWorkspace(without),
      size: const Size(1440, 900),
    );
    expect(
      find.byKey(const ValueKey('server-community-event-card')),
      findsNothing,
    );
  });

  testWidgets('the desktop context panel is the live chat over a real channel',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    expect(find.byKey(const ValueKey('server-context-panel')), findsOneWidget);
    expect(find.text('Czat na żywo · #ogólny'), findsOneWidget);
  });

  testWidgets('the phone surface leads with the video and Czat | Kanały', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(390, 844),
    );

    expect(stage, findsOneWidget);
    final chatTab = find.byKey(const ValueKey('server-tab-chat'));
    final channelsTab = find.byKey(const ValueKey('server-open-channels'));
    expect(chatTab, findsOneWidget);
    // Exactly one way into the channel list: the strip owns it, so the
    // header drops its pill.
    expect(channelsTab, findsOneWidget);
    expect(find.text('Czat na żywo'), findsOneWidget);
    // No channel header here, so the scene carries the name and the live
    // line itself — exactly once.
    expect(
      find.byKey(const ValueKey('server-community-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-community-liveness')),
      findsOneWidget,
    );

    final stageRect = tester.getRect(stage);
    final tabsRect = tester.getRect(chatTab);
    expect(stageRect.top, lessThan(tabsRect.top));
    // The channel header is not repeated over a scene that names itself.
    expect(find.byKey(const ValueKey('server-channel-header')), findsNothing);
    // The primary action is pinned under the conversation.
    expect(join, findsOneWidget);
    expect(tester.getRect(join).top, greaterThan(tabsRect.bottom));

    await tester.tap(channelsTab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-panel')), findsOneWidget);
  });

  testWidgets('Poproś o głos reaches setServerSessionHandV1 and comes back', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 19, 40),
        ),
        activeSessionId: 'gen-7',
      )
      ..sessionRole = 'listener'
      ..permittedTrackSources = const [];
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      communityWorkspace(repository, connector: connector),
      size: const Size(390, 844),
    );

    // Nothing is asked for before the person joins.
    expect(hand, findsNothing);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(
      repository.calls.map((call) => call.$1),
      // A live generation is joined without starting a second one.
      ['createServerChannelTokenV1'],
    );
    expect(hand, findsOneWidget);
    expect(find.text('Poproś o głos'), findsOneWidget);

    await tester.tap(hand);
    await tester.pumpAndSettle();
    final raise = repository.calls.last;
    expect(raise.$1, 'setServerSessionHandV1');
    expect(raise.$2['serverId'], 's');
    expect(raise.$2['channelId'], 'stage');
    expect(raise.$2['sessionId'], 'gen-7');
    expect(raise.$2['raised'], isTrue);
    expect(raise.$2['requestId'], isNotEmpty);
    expect(find.text('Prowadzący widzą Twoją prośbę.'), findsOneWidget);

    // The same control takes the request back.
    await tester.tap(hand);
    await tester.pumpAndSettle();
    expect(repository.calls.last.$2['raised'], isFalse);
    expect(find.text('Poproś o głos'), findsOneWidget);
    expect(find.text('Prowadzący widzą Twoją prośbę.'), findsNothing);
  });

  testWidgets('a refused hand is one sentence and never the raw code', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: const ServerChannelLiveness(isLive: false),
        activeSessionId: 'gen-7',
      )
      ..sessionRole = 'listener';
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();

    repository.failNextCall['setServerSessionHandV1'] =
        FirebaseFunctionsException(code: 'not-found', message: 'unregistered');
    await tester.tap(hand);
    await tester.pumpAndSettle();
    expect(
      find.text('Ta część YO Voice jest jeszcze przygotowywana.'),
      findsOneWidget,
    );
    expect(find.textContaining('not-found'), findsNothing);
    expect(find.text('Prowadzący widzą Twoją prośbę.'), findsNothing);
  });

  testWidgets('the generation host is never offered the stage queue', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();
    // The default receipt is the starter's: `sessionRole: host`.
    expect(hand, findsNothing);
    expect(find.text('W rozmowie'), findsWidgets);
  });

  testWidgets('in session the scene names only who the provider reports', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    final connector = FakeServerMediaConnector();
    await pumpServers(
      tester,
      communityWorkspace(repository, connector: connector),
      size: const Size(1440, 900),
    );
    await tester.tap(join);
    await tester.pumpAndSettle();

    connector.links.single.setRoster(const [
      ServerMediaParticipant(
        identity: 'owner',
        name: 'Maja',
        isLocal: true,
        isMicrophoneEnabled: true,
      ),
      ServerMediaParticipant(identity: 'u2', name: 'Bartek', isLocal: false),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('server-community-on-air')), findsOneWidget);
    expect(find.text('Maja'), findsWidgets);
    expect(find.text('Bartek'), findsWidgets);
    // Nobody is publishing a camera, so the scene says exactly that instead
    // of holding an empty player.
    expect(find.text('Nikt nie przesyła teraz obrazu.'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-community-video')), findsNothing);
    expect(find.textContaining(fabricated), findsNothing);
  });

  testWidgets('Moderator badges come from the roster and from nothing else', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final firestore = FakeFirebaseFirestore();
    final messages = firestore
        .collection('clubs')
        .doc('s')
        .collection('channels')
        .doc('general')
        .collection('messages');
    await messages.doc('m1').set({
      'senderId': 'mod',
      'senderName': 'Michał',
      'content': 'Świetny temat!',
      'sentAt': DateTime(2026, 9, 12, 19, 16),
      'isDeleted': false,
    });
    await messages.doc('m2').set({
      'senderId': 'u2',
      'senderName': 'Bartek',
      'content': 'Cześć wszystkim!',
      'sentAt': DateTime(2026, 9, 12, 19, 14),
      'isDeleted': false,
    });

    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels()
      ..moderators = const {'mod'};
    await pumpServers(
      tester,
      communityWorkspace(
        repository,
        chat: communityChat(firestore: firestore),
      ),
      size: const Size(1440, 900),
    );
    await tester.pumpAndSettle();

    expect(find.text('Świetny temat!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-moderator-badge-m1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-moderator-badge-m2')),
      findsNothing,
    );
    expect(find.text('Moderator'), findsOneWidget);

    // An unread or denied roster badges nobody at all.
    final blind = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();
    await pumpServers(
      tester,
      communityWorkspace(blind, chat: communityChat(firestore: firestore)),
      size: const Size(1440, 900),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moderator'), findsNothing);
  });

  testWidgets('a held community server shows no broadcast surface', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer(held: true)]
      ..channels = communityChannels();
    for (final width in [390.0, 1440.0]) {
      await pumpServers(
        tester,
        communityWorkspace(repository),
        size: Size(width, 844),
      );
      expect(stage, findsNothing, reason: '$width');
      expect(
        tester.widget<FilledButton>(join).onPressed,
        isNull,
        reason: '$width',
      );
      expect(repository.calls, isEmpty, reason: '$width');
    }
  });

  testWidgets('the stage survives six widths and 200 percent in both themes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in widths) {
      for (final scale in [1.0, 2.0]) {
        final repository = TestServerRepository()
          ..servers = [communityServer()]
          ..channels = communityChannels(
            stage: ServerChannelLiveness(
              isLive: true,
              startedAt: DateTime(2026, 9, 12, 19, 40),
            ),
          );
        await pumpServers(
          tester,
          communityWorkspace(repository),
          size: Size(width, 760),
          textScale: scale,
          light: scale == 2,
        );
        final reason = '$width ×$scale';
        expect(tester.takeException(), isNull, reason: reason);
        expect(stage, findsOneWidget, reason: reason);
        expect(join, findsOneWidget, reason: reason);
        expect(find.textContaining(fabricated), findsNothing, reason: reason);
        expect(repository.calls, isEmpty, reason: reason);
        final rect = tester.getRect(stage);
        expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
        expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: reason);
      }
    }
  });

  testWidgets('the picture keeps its place and never scrolls the name away', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The narrowest surface at the largest text setting is where a scrolling
    // block used to spend its whole height on the 16:9 picture and cut the
    // channel's name, its live line and every action out of the phone.
    for (final scale in [1.0, 2.0]) {
      final repository = TestServerRepository()
        ..servers = [communityServer()]
        ..channels = communityChannels(
          stage: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime(2026, 9, 12, 19, 40),
          ),
        );
      await pumpServers(
        tester,
        communityWorkspace(repository),
        size: const Size(320, 760),
        textScale: scale,
      );
      final reason = '×$scale';
      expect(tester.takeException(), isNull, reason: reason);

      final scene = tester.getRect(stage);
      final title = tester.getRect(
        find.byKey(const ValueKey('server-community-title')),
      );
      final liveness = tester.getRect(
        find.byKey(const ValueKey('server-community-liveness')),
      );
      // The scrolling block's viewport: anything laid out below its bottom
      // edge is clipped away, which is exactly how the name and the live line
      // used to disappear when the picture scrolled with them.
      final viewport = tester.getRect(
        find.byKey(const ValueKey('server-community-details')),
      );
      // 16:9 at every text setting: a short surface narrows the picture, it
      // never distorts it and never overflows the column.
      expect(scene.width / scene.height, closeTo(16 / 9, 0.02), reason: reason);
      expect(scene.top, greaterThanOrEqualTo(0), reason: reason);
      // The picture holds its own place above the scroll…
      expect(scene.bottom, lessThanOrEqualTo(viewport.top + 0.5), reason: reason);
      // …and the channel's name and its live line hold their own place
      // between the picture and the scroll, whole, at every text setting.
      expect(title.top, greaterThan(scene.bottom - 1), reason: reason);
      expect(liveness.bottom, lessThanOrEqualTo(viewport.top + 0.5),
          reason: reason);
      expect(liveness.bottom, lessThanOrEqualTo(760), reason: reason);
      expect(find.text('Na żywo od 19:40'), findsWidgets, reason: reason);
      expect(find.textContaining(fabricated), findsNothing, reason: reason);
    }
  });

  testWidgets('at 200 percent the strip chooses instead of stacking', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 19, 40),
        ),
      );
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(320, 760),
      textScale: 2,
    );

    // The broadcast, its name and the primary action keep their place; the
    // rest of the surface is whichever of the two the person picks.
    final scene = find.byKey(const ValueKey('server-tab-scene'));
    final conversation = find.byKey(const ValueKey('server-tab-chat'));
    expect(scene, findsOneWidget);
    expect(conversation, findsOneWidget);
    expect(find.byKey(const ValueKey('server-open-channels')), findsOneWidget);
    expect(stage, findsOneWidget);
    expect(find.byKey(const ValueKey('server-community-details')), findsOneWidget);
    expect(find.text('Nie ma jeszcze wiadomości'), findsNothing);

    await tester.tap(conversation);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Choosing the conversation means the conversation: at this size the
    // picture steps aside rather than leaving the chat a band too small for
    // its own composer.
    expect(stage, findsNothing);
    expect(find.text('Nie ma jeszcze wiadomości'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-community-details')), findsNothing);

    await tester.tap(scene);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-community-details')), findsOneWidget);
    expect(find.text('Nie ma jeszcze wiadomości'), findsNothing);
    expect(repository.calls, isEmpty);
  });

  testWidgets('a scrolling remainder says so, and only when it scrolls', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fade = find.byKey(const ValueKey('server-community-details-fade'));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels();

    // A phone cannot hold the description, the unavailable actions and the
    // event card under the picture, so the cut is marked rather than left
    // slicing a control in half.
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(390, 844),
    );
    expect(fade, findsOneWidget);

    // A desktop column holds all of it; nothing is faded there.
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    expect(fade, findsNothing);
  });

  testWidgets('a video stage is watched, an audio stage is listened to', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // `mediaConfiguration()` gives board 02's stage `broadcast/video` and the
    // grant a camera source, so the join may not promise sound alone. The
    // podcast's audio stage keeps `Słuchaj`.
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 19, 40),
        ),
      );
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    expect(
      tester.widget<Text>(find.descendant(of: join, matching: find.byType(Text))).data,
      'Oglądaj',
    );
    expect(find.descendant(of: join, matching: find.byIcon(Icons.live_tv_rounded)),
        findsOneWidget);

    final audio = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels(
        stage: ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 9, 12, 19, 40),
        ),
        stageMedia: ServerMediaMode.audio,
      );
    await pumpServers(
      tester,
      communityWorkspace(audio),
      size: const Size(1440, 900),
    );
    expect(
      tester.widget<Text>(find.descendant(of: join, matching: find.byType(Text))).data,
      'Słuchaj',
    );
  });

  testWidgets('a listener without moderator power is not offered to go live', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [communityServer()]
      ..channels = communityChannels()
      ..myRole = ServerMemberRole.member;
    await pumpServers(
      tester,
      communityWorkspace(repository),
      size: const Size(1440, 900),
    );
    expect(join, findsNothing);
    expect(
      find.text('Będzie można słuchać, gdy scena zacznie nadawać.'),
      findsOneWidget,
    );
    expect(repository.calls, isEmpty);
  });
}
