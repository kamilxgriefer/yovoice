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
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_test_support.dart';

/// Fixtures for the independent QA pass over the in-server shell and the five
/// template boards.
///
/// They are written from the contract rather than from the implementation
/// slices' own suites: the server is built here, the channels are built here,
/// and nothing is imported from `server_shell_test.dart` or the four board
/// suites, so a fixture those suites relax cannot quietly relax these
/// assertions with it.

/// Every width the contract names, plus the two the shell's own tiers turn on.
const qaWidths = <double>[320, 390, 768, 1100, 1440, 1920];

/// A name nobody would type but the product has to survive: 118 characters,
/// Polish diacritics, no spaces long enough to break on their own.
const qaLongServerName =
    'Klub Przyjaciół Od Zawsze I Na Zawsze Spotykających Się Wieczorami '
    'Przy Wyjątkowo Długiej Nazwie Serwera Bez Skrótów';

/// The same for a channel: long enough that no column at 320 px can hold it.
String qaLongChannelName(String base) =>
    '$base — kanał o wyjątkowo rozwlekłej i nieskracanej nazwie zespołu';

/// Anything that could only come from a presence writer. There is none
/// (contract G6) and `participantCount` does not exist, so no rendered string
/// anywhere may carry one of these numbers.
///
/// Two shapes, because Polish writes this claim both ways and the boards do
/// too. Number first — "126 widzów", "84 słuchaczy", "6 uczestników",
/// "4 osoby rozmawiają", "6 osób potwierdziło" — and verb first, which is how
/// board 03 words it: "Teraz rozmawiają 3 osoby". The first version of this
/// guard only caught the number-first order, so the mockups' own family
/// wording would have passed it.
///
/// `memberCount` is deliberately *not* caught: "12 osób", "12 osób w
/// serwerze" and "Społeczność · 248 osób" are a field the backend really
/// writes (contract §1.1), so a bare count of members is honest and only a
/// count tied to presence is not.
///
/// Dart's `\w` is ASCII, so it stops dead at `ą` and would never carry an
/// inflection like "rozmawiają" — the very ending that makes board 03's
/// sentence the verb-first one. Polish endings therefore get an explicit
/// letter class, and `os(?:ob...|ób)` covers osoba / osoby / osobę / osób.
final qaFabricatedCount = RegExp(
  // Number first: "126 widzów", "84 słuchaczy", "6 uczestników",
  // "4 osoby rozmawiają", "6 osób potwierdziło", "12 reakcji", "8 głosów".
  r'\d+\s*(?:widz|słuchacz|uczestnik|reakcj|głos(?:y|ów)'
  r'|os(?:ob[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]*|ób)'
  r'\s+(?:rozmawia|ogląda|słucha|potwierdz|czeka))'
  // Verb first, which is how board 03 words it: "Teraz rozmawiają 3 osoby".
  r'|(?:rozmawia|ogląda|słucha|potwierdz|czeka)[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]*'
  r'\s+\d+\s*os(?:ob[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]*|ób)',
  caseSensitive: false,
);

/// A recording claim. Recording has no contract at all (contract §3), so a
/// surface may say it does not work, and may never say that it does.
final qaRecordingClaim = RegExp(r'(?<!nie )jest\s+nagrywan', caseSensitive: false);

Server qaServer(
  ServerType type, {
  bool held = false,
  int members = 12,
  String? name,
}) => Server(
  id: 's',
  name: name ?? 'Po godzinach',
  description: '',
  ownerId: 'owner',
  type: type,
  privacy: type.allowsPublic ? ServerPrivacy.public : ServerPrivacy.inviteOnly,
  memberCount: members,
  defaultChannelId: qaFirstText(type),
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
  status: held ? 'preparing' : 'active',
);

String qaFirstText(ServerType type) => serverTemplateChannelsFor(
  type,
).firstWhere((seed) => seed.kind == ServerChannelKind.text).seedKey;

/// The template's first media channel — the one a join can be tested on.
String qaFirstMedia(ServerType type) =>
    serverTemplateChannelsFor(type).firstWhere((seed) => seed.kind.isMedia).seedKey;

/// The destination each board is actually about (contract §4.2): board 01's
/// `Salon`, board 02's `Scena LIVE`, board 05's `Studio LIVE`, board 04's
/// `Spotkania`, and board 03's `Rodzinny pulpit` — which is a view of the
/// server and therefore has no channel id at all.
String? qaBoardChannel(ServerType type) => switch (type) {
  ServerType.friends => 'lounge',
  ServerType.community => 'stage',
  ServerType.podcast => 'studio',
  ServerType.family => null,
  ServerType.company => 'meeting',
};

/// The media channel each board's own scene joins — board 03 joins from the
/// home view's `Salon rodzinny` card, which is the same voice channel.
String qaJoinableChannel(ServerType type) =>
    qaBoardChannel(type) ?? qaFirstMedia(type);

/// The seeded template read back as the workspace sees it.
///
/// [restricted] false drops the `accessMode: "restricted"` rows exactly as the
/// repository drops them for a member who holds no `serverChannelRef` — the
/// query never returns them, so the list simply does not contain them.
List<ServerChannel> qaChannels(
  ServerType type, {
  ServerChannelLiveness liveness = ServerChannelLiveness.idle,
  String? activeSessionId,
  bool restricted = true,
  bool longNames = false,
  String? liveChannelId,
}) {
  final seeds = serverTemplateChannelsFor(type);
  // The board's own media channel carries the projection; its siblings stay
  // idle, so both states are on screen at once.
  final media = liveChannelId ?? qaJoinableChannel(type);
  return [
    for (var i = 0; i < seeds.length; i++)
      if (restricted || !seeds[i].restricted)
        ServerChannel(
          id: seeds[i].seedKey,
          serverId: 's',
          name: longNames
              ? qaLongChannelName(seeds[i].polishName)
              : seeds[i].polishName,
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
          liveness:
              seeds[i].seedKey == media ? liveness : ServerChannelLiveness.idle,
          activeSessionId:
              seeds[i].seedKey == media ? activeSessionId : null,
        ),
  ];
}

ClubChatService qaChat({
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

Widget qaWorkspace(
  TestServerRepository repository, {
  String? channelId,
  FakeServerMediaConnector? connector,
  ClubChatService? chat,
  bool Function()? anotherVoiceSessionActive,
}) => ServerWorkspaceScreen(
  key: UniqueKey(),
  serverId: 's',
  repository: repository,
  isRootTab: true,
  initialChannelId: channelId,
  chatService: chat ?? qaChat(),
  connector: connector ?? FakeServerMediaConnector(),
  anotherVoiceSessionActive: anotherVoiceSessionActive,
);

Finder get qaJoin => find.byKey(const ValueKey('server-join'));
Finder get qaDock => find.byKey(const ValueKey('server-conversation-dock'));
Finder get qaDockStatus => find.byKey(const ValueKey('server-dock-status'));
Finder get qaPanel => find.byKey(const ValueKey('server-panel'));
Finder get qaOpenChannels =>
    find.byKey(const ValueKey('server-open-channels'));
Finder get qaLivePill => find.byKey(const ValueKey('server-live-pill'));
Finder get qaLeave => find.byKey(const ValueKey('server-dock-leave'));

/// Every string this surface actually puts in front of a reader: the text of
/// every `Text`, the plain text of every `RichText` (so a span-built sentence
/// cannot hide a number), and every semantics label (so a screen reader is
/// held to the same honesty as the screen).
List<String> qaRenderedStrings(WidgetTester tester) {
  final out = <String>[];
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data != null) out.add(data);
  }
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    try {
      out.add(rich.text.toPlainText());
    } catch (_) {
      // A span the widget tree cannot flatten carries no literal text.
    }
  }
  for (final semantics in tester.widgetList<Semantics>(find.byType(Semantics))) {
    final label = semantics.properties.label;
    if (label != null && label.isNotEmpty) out.add(label);
  }
  return out;
}

/// Fails with the offending string rather than with a bare count, so a
/// regression names the copy that broke the rule.
void qaExpectNoMatch(WidgetTester tester, RegExp pattern, String reason) {
  final offenders = qaRenderedStrings(
    tester,
  ).where(pattern.hasMatch).toSet().toList();
  expect(offenders, isEmpty, reason: '$reason — found: $offenders');
}

/// Presses a control the way a person would: a control inside a scrolling
/// surface is scrolled to first, which is also the assertion that it is
/// reachable at all rather than laid out past the end of the world.
Future<void> qaTap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  if (find
      .ancestor(of: finder, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Joins the channel the surface is showing and hands back the provider link
/// the connector produced.
Future<FakeServerMediaLink> qaJoinAndSettle(
  WidgetTester tester,
  FakeServerMediaConnector connector, {
  List<ServerMediaParticipant> roster = const [],
}) async {
  await qaTap(tester, qaJoin);
  final link = connector.links.single;
  if (roster.isNotEmpty) {
    link.setRoster(roster);
    await tester.pumpAndSettle();
  }
  return link;
}

/// The same join for a surface whose clock ticks (a live meeting), pumped
/// explicitly and by less than a second in total so nothing has to settle.
Future<FakeServerMediaLink> qaJoinLive(
  WidgetTester tester,
  FakeServerMediaConnector connector, {
  List<ServerMediaParticipant> roster = const [],
}) async {
  await tester.tap(qaJoin);
  for (var pump = 0; pump < 6; pump++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  final link = connector.links.single;
  if (roster.isNotEmpty) {
    link.setRoster(roster);
    await tester.pump(const Duration(milliseconds: 30));
  }
  return link;
}

/// Three people a provider could really report. Nobody publishes a picture:
/// a `VideoTrack` cannot be constructed off-device, and the tile that must
/// never invent one is exactly the tile without it.
const qaRoster = [
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
  ServerMediaParticipant(identity: 'marta', name: 'Marta', isLocal: false),
];
