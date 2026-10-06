// Fixtures for the server page (`Strona serwera`, ADR-240), shared by
// `server_page_test.dart` and the developer capture `server_page_capture.dart`.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_test_support.dart';

/// The server of the chosen frames: a public community.
Server pageServer(
  ServerType type, {
  String id = 's',
  String? name,
  String? description,
  int? members,
  ServerPrivacy? privacy,
  bool held = false,
}) => Server(
  id: id,
  name:
      name ??
      switch (type) {
        ServerType.community => 'Nocne Granie',
        ServerType.friends => 'Paczka z liceum',
        ServerType.family => 'Rodzina Nowaków',
        ServerType.podcast => 'Nocne audycje',
        ServerType.company => 'Studio Północ',
      },
  description:
      description ??
      switch (type) {
        ServerType.community => 'Gramy wieczorami, gadamy do późna.',
        ServerType.friends => 'Głos, tekst i plany w jednym miejscu.',
        ServerType.family => 'Plany, zdjęcia i niedzielne rozmowy.',
        ServerType.podcast => 'Rozmowy po zmroku, w każdy czwartek.',
        ServerType.company => 'Projekty, spotkania i pliki zespołu.',
      },
  ownerId: 'owner',
  type: type,
  privacy:
      privacy ??
      switch (type) {
        ServerType.community || ServerType.podcast => ServerPrivacy.public,
        ServerType.family => ServerPrivacy.inviteOnly,
        _ => ServerPrivacy.private,
      },
  memberCount:
      members ??
      switch (type) {
        ServerType.community => 128,
        ServerType.friends => 12,
        ServerType.family => 6,
        ServerType.podcast => 42,
        ServerType.company => 23,
      },
  defaultChannelId: serverTemplateChannelsFor(
    type,
  ).firstWhere((seed) => seed.kind == ServerChannelKind.text).seedKey,
  defaultVoiceChannelId: serverTemplateChannelsFor(
    type,
  ).where((seed) => seed.kind == ServerChannelKind.voice).firstOrNull?.seedKey,
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
  status: held ? 'preparing' : 'active',
);

/// The template's own seeded channels, with [live] on the template's main
/// media channel (the lounge, the stage, the studio or the meeting).
List<ServerChannel> pageChannels(
  ServerType type, {
  String serverId = 's',
  ServerChannelLiveness live = ServerChannelLiveness.idle,
  Set<ServerChannelKind> without = const {},
}) {
  final seeds = serverTemplateChannelsFor(
    type,
  ).where((seed) => !without.contains(seed.kind)).toList();
  final mainKind = switch (type) {
    ServerType.friends || ServerType.family => ServerChannelKind.voice,
    ServerType.community || ServerType.podcast => ServerChannelKind.stage,
    ServerType.company => ServerChannelKind.meeting,
  };
  final mainKey = seeds
      .where((seed) => seed.kind == mainKind)
      .firstOrNull
      ?.seedKey;
  return [
    for (var i = 0; i < seeds.length; i++)
      ServerChannel(
        id: seeds[i].seedKey,
        serverId: serverId,
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
        liveness: seeds[i].seedKey == mainKey
            ? live
            : ServerChannelLiveness.idle,
      ),
  ];
}

/// An event of [type]'s events (or calendar) channel, starting at [startsAt]
/// in Warsaw wall-clock time.
ServerEvent pageEvent(
  ServerType type, {
  required String id,
  required String title,
  required DateTime startsAt,
  String serverId = 's',
}) {
  final (eventKind, channelKind) = switch (type) {
    ServerType.friends => (
      ServerEventKind.friendsEvent,
      ServerChannelKind.events,
    ),
    ServerType.community => (
      ServerEventKind.communityEvent,
      ServerChannelKind.events,
    ),
    ServerType.podcast => (
      ServerEventKind.podcastProgramEvent,
      ServerChannelKind.events,
    ),
    ServerType.family => (
      ServerEventKind.familyCalendarEvent,
      ServerChannelKind.calendar,
    ),
    ServerType.company => throw ArgumentError('A company has no events.'),
  };
  final channelId = serverTemplateChannelsFor(
    type,
  ).firstWhere((seed) => seed.kind == channelKind).seedKey;
  final start = ServerEventTime.wallClockToUtc(startsAt, 'Europe/Warsaw');
  return ServerEvent(
    id: id,
    serverId: serverId,
    channelId: channelId,
    title: title,
    description: '',
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    timeZone: 'Europe/Warsaw',
    status: ServerEventStatus.scheduled,
    authorId: 'owner',
    revision: 1,
    eventKind: eventKind,
    serverType: type,
    channelKind: channelKind,
    reminderOptInEnabled:
        eventKind == ServerEventKind.podcastProgramEvent ||
        eventKind == ServerEventKind.familyCalendarEvent,
  );
}

/// [days] days from today at [hour]:00, as a Warsaw wall clock.
DateTime pageDay(int days, int hour) {
  final today = ServerEventTime.inZone(DateTime.now().toUtc(), 'Europe/Warsaw');
  final day = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).add(Duration(days: days));
  return DateTime.utc(day.year, day.month, day.day, hour);
}

/// The page's clock held at today's noon in Warsaw.
///
/// A fixture that plans something for "today at 23:00" is ahead of this clock
/// at every hour the suite runs; read from the real clock, the same fixture
/// has already started between 23:00 and midnight, and the page rightly stops
/// offering its answer.
DateTime Function() pageNoon() {
  final noon = ServerEventTime.wallClockToUtc(pageDay(0, 12), 'Europe/Warsaw');
  return () => noon;
}

final pageLive = ServerChannelLiveness(
  isLive: true,
  startedAt: DateTime(2026, 10, 3, 21, 4),
);

ClubChatService pageChat([FakeFirebaseFirestore? firestore]) => ClubChatService(
  firestore: firestore ?? FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'owner', email: 'owner@yo.voice'),
  ),
  requestIdFactory: () => 'msg-1',
  messageSendInvoker: (_) async => <Object?, Object?>{},
);

/// A repository holding one server of [type] the way the frames show it.
TestServerRepository pageRepository(
  ServerType type, {
  ServerMemberRole role = ServerMemberRole.owner,
  ServerChannelLiveness live = ServerChannelLiveness.idle,
  List<ServerEvent> events = const [],
  bool held = false,
  List<Server> others = const [],
  Set<ServerChannelKind> without = const {},
}) => TestServerRepository()
  ..servers = [pageServer(type, held: held), ...others]
  ..channels = pageChannels(type, live: live, without: without)
  ..events = events
  ..myRole = role;

/// The workspace as the shell hosts it: no route bar, the directory's way
/// back supplied.
Widget pageWorkspace(
  TestServerRepository repository, {
  String? channelId,
  FakeServerMediaConnector? connector,
  ClubChatService? chat,
  VoidCallback? onBack,
  Future<void> Function(Uri link)? shareServer,
  bool isRootTab = true,
  bool justCreated = false,
  DateTime Function()? now,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: repository,
  isRootTab: isRootTab,
  initialChannelId: channelId,
  chatService: chat ?? pageChat(),
  connector: connector ?? FakeServerMediaConnector(),
  onBack: onBack ?? (isRootTab ? () {} : null),
  shareServer: shareServer,
  justCreated: justCreated,
  now: now,
);
