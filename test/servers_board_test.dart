import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/server_links.dart';
import 'package:yovoice/features/servers/data/services/server_directory_liveness.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/servers_board.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// The Servers tab's board (owner's choice 2026-10-03, option A of sheet
/// `2_hub`, without the LIVE section; ADR-239): "Twoje serwery" with the LIVE
/// lamp, "Serwery publiczne" from the one listing Rules allow, the "+" sheet
/// with the actions that exist, "Dołącz z linku" and the name filter.

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  ServerPrivacy? privacy,
  ServerMemberRole? role,
  String owner = 'owner',
  int? schemaVersion = 1,
  String activationState = 'active',
}) => Server(
  id: id,
  name: name,
  description: '',
  ownerId: owner,
  type: type,
  privacy:
      privacy ??
      (type == ServerType.family
          ? ServerPrivacy.inviteOnly
          : ServerPrivacy.private),
  memberCount: members,
  schemaVersion: schemaVersion,
  activationState: schemaVersion == null ? null : activationState,
  status: 'active',
  directoryRole: role,
);

List<Server> _mine() => [
  _server(
    's',
    'Nocne Granie',
    ServerType.community,
    members: 128,
    privacy: ServerPrivacy.public,
    role: ServerMemberRole.owner,
  ),
  // Somebody else's server: the one row whose action is "leave".
  _server(
    'p',
    'Paczka z liceum',
    ServerType.friends,
    members: 12,
    owner: 'someone',
    role: ServerMemberRole.member,
  ),
  _server('r', 'Rodzina Nowaków', ServerType.family, members: 6),
  _server('f', 'Studio Fala', ServerType.podcast, members: 42),
];

Server _public(String id, String name, int members, {ServerType? type}) =>
    _server(
      id,
      name,
      type ?? ServerType.community,
      members: members,
      privacy: ServerPrivacy.public,
      owner: 'someone',
    );

List<Server> _publicServers() => [
  _public('pub-f', 'Fotografia po godzinach', 312),
  _public('pub-j', 'Języki przy kawie', 89),
  _public('pub-n', 'Nocna audycja', 26, type: ServerType.podcast),
];

ServerChannel _stage(String serverId, {bool live = true}) => ServerChannel(
  id: 'stage-$serverId',
  serverId: serverId,
  name: 'Scena',
  kind: ServerChannelKind.stage,
  roomId: 'room-$serverId',
  experience: RoomExperience.broadcast,
  mediaMode: ServerMediaMode.video,
  schemaVersion: 1,
  liveness: live
      ? ServerChannelLiveness(
          isLive: true,
          startedAt: DateTime(2026, 10, 3, 21, 4),
        )
      : ServerChannelLiveness.idle,
);

TestServerRepository _repository({
  List<Server>? mine,
  List<Server>? public,
  List<ServerChannel> channels = const [],
}) => TestServerRepository()
  ..servers = mine ?? _mine()
  ..publicServers = public ?? _publicServers()
  ..channels = channels;

Widget _board(
  TestServerRepository repository, {
  ValueListenable<bool>? isVisible,
  VoidCallback? onCreateServer,
  WidgetBuilder? liveSectionBuilder,
}) => ServersScreen(
  key: UniqueKey(),
  isRootTab: true,
  repository: repository,
  chatService: qaChat(),
  connector: FakeServerMediaConnector(),
  isVisible: isVisible,
  onCreateServer: onCreateServer,
  liveSectionBuilder: liveSectionBuilder,
);

Finder _row(String id) => find.byKey(ValueKey('server-directory-$id'));
Finder _card(String id) => find.byKey(ValueKey('server-public-$id'));
Finder _lamp(String id) => find.byKey(ValueKey('server-directory-live-$id'));
Finder get _add => find.byKey(const ValueKey('servers-add'));

/// The account's own list as a live stream the test drives (data, an error,
/// data again), beside a public listing that — like the production one —
/// can be listened to exactly once.
class _FlakyDirectory extends TestServerRepository {
  StreamController<List<Server>> own = StreamController<List<Server>>();
  var _opened = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    // The first subscription gets the seeded list; each retry gets a fresh
    // stream the test feeds.
    if (_opened++ > 0) own = StreamController<List<Server>>();
    final controller = own;
    if (_opened == 1) controller.add(servers);
    return controller.stream;
  }
}

/// Counts the channel listeners that are OPEN per server, not merely how
/// many were ever asked for: the lamp's cost is the listeners it holds.
class _CountingChannels extends TestServerRepository {
  final open = <String, int>{};

  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) {
    final source = super.watchChannels(serverId);
    StreamSubscription<List<ServerChannel>>? inner;
    late final StreamController<List<ServerChannel>> controller;
    controller = StreamController<List<ServerChannel>>(
      onListen: () {
        open[serverId] = (open[serverId] ?? 0) + 1;
        inner = source.listen(controller.add, onError: controller.addError);
      },
      onCancel: () {
        open[serverId] = open[serverId]! - 1;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }
}

/// A read-only repository that can list the account's servers and nothing
/// else: no public listing, no management.
class _NoPublicListing implements ServerRepository {
  _NoPublicListing(this._inner);
  final TestServerRepository _inner;

  @override
  String get currentUserId => _inner.currentUserId;
  @override
  Stream<List<Server>> watchMyServers() => _inner.watchMyServers();
  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) =>
      _inner.watchChannels(serverId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not needed to render the board',
  );
}

void main() {
  // ------------------------------------------------------------ the query

  group('watchPublicServers sends the listing the rules authorize', () {
    late FakeFirebaseFirestore db;
    late ServerService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ServerService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', displayName: 'Kamil'),
        ),
      );
    });

    Future<void> seed(
      String id, {
      String name = 'Server',
      String privacy = 'public',
      String serverType = 'community',
      String? type,
      String status = 'active',
      String activation = 'active',
      int members = 1,
      bool legacy = false,
    }) => db.collection('clubs').doc(id).set({
      'name': name,
      'description': '',
      'ownerId': 'owner-$id',
      'privacy': privacy,
      'type': type ?? (serverType == 'family' ? 'family' : 'community'),
      'status': status,
      'memberCount': members,
      if (!legacy) ...{
        'serverSchemaVersion': 1,
        'templateVersion': 1,
        'serverType': serverType,
        'serverActivationState': activation,
        'revision': 1,
      },
      'createdAt': Timestamp.now(),
    });

    test('public Community and Podcast servers, most members first', () async {
      await seed('small', name: 'Mały', members: 3);
      await seed('big', name: 'Duży', members: 40);
      // A public Podcast root carries `type: 'community'` like every
      // non-family server; the template is `serverType`.
      await seed('show', name: 'Audycja', serverType: 'podcast', members: 12);

      final servers = await service.watchPublicServers().first;

      expect(servers.map((server) => server.id), ['big', 'show', 'small']);
      expect(servers[1].type, ServerType.podcast);
      expect(servers.every((server) => server.privacy.name == 'public'), true);
    });

    test(
      'private, invite-only, family and suspended roots never appear',
      () async {
        await seed('open', name: 'Otwarty');
        await seed('closed', privacy: 'private');
        await seed('invite', privacy: 'inviteOnly');
        await seed(
          'family',
          serverType: 'family',
          type: 'family',
          privacy: 'inviteOnly',
        );
        await seed('suspended', status: 'suspended');

        final servers = await service.watchPublicServers().first;

        expect(servers.map((server) => server.id), ['open']);
      },
    );

    test('a root the admission cannot join is not offered', () async {
      await seed('open');
      // A legacy club has no public admission in the workspace, and a held
      // root is still being prepared: neither has a join path.
      await seed('legacy', legacy: true);
      await seed('held', activation: 'held', status: 'active');
      // A document this build cannot parse is one missing card.
      await db.collection('clubs').doc('future').set({
        'name': 'Future',
        'ownerId': 'x',
        'privacy': 'public',
        'type': 'community',
        'status': 'active',
        'serverSchemaVersion': 2,
      });

      final servers = await service.watchPublicServers().first;

      expect(servers.map((server) => server.id), ['open']);
    });

    test('reads at most the limit it was given', () async {
      for (var i = 0; i < 30; i++) {
        await seed('s${i.toString().padLeft(2, '0')}', members: i);
      }
      // The board shows eight cards and reads three times as many roots.
      expect(ServerService.publicDirectoryLimit, 8);
      expect(ServerService.publicDirectoryReadLimit, 24);
      expect(await service.watchPublicServers().first, hasLength(24));
      expect(await service.watchPublicServers(limit: 3).first, hasLength(3));
    });

    test('eight legacy public clubs do not take the cards\' places', () async {
      // The rule-proven query cannot tell a legacy club from a V1 root, and
      // a legacy club has no join path here. Read exactly eight and these
      // would be the whole answer: an empty section for everybody, although
      // joinable public servers exist.
      for (var i = 0; i < 8; i++) {
        await seed('a$i', name: 'Stary klub $i', legacy: true, members: 99);
      }
      await seed('z1', name: 'Fotografia', members: 12);
      await seed('z2', name: 'Audycja', serverType: 'podcast', members: 40);

      final servers = await service.watchPublicServers().first;

      expect(servers.map((server) => server.id), ['z2', 'z1']);
    });

    test('a signed-out session lists nothing and reads nothing', () async {
      await seed('open');
      final signedOut = ServerService(firestore: db, auth: MockFirebaseAuth());
      expect(await signedOut.watchPublicServers().first, isEmpty);
    });

    test('the three equalities are the ones the rule proves', () {
      // `allow list` on clubs is proven against the query's own constraints
      // (firestore.rules, `match /clubs/{clubId}`); the emulator suite owns
      // the rule, this pins that the client still sends exactly that shape.
      expect(ServerService.publicDirectoryFilters, {
        'privacy': 'public',
        'type': 'community',
        'status': 'active',
      });
    });
  });

  // ------------------------------------------------------------- the lamp

  group('ServerDirectoryLiveness', () {
    test('a server is live exactly when a media channel says so', () async {
      final repository = _repository(
        channels: [_stage('s'), _stage('f', live: false)],
      );
      final liveness = ServerDirectoryLiveness(repository: repository);
      addTearDown(liveness.dispose);
      var notified = 0;
      liveness.addListener(() => notified++);

      liveness.track(_mine());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(liveness.isLive('s'), isTrue);
      expect(liveness.liveSince('s'), DateTime(2026, 10, 3, 21, 4));
      expect(liveness.isLive('f'), isFalse);
      expect(liveness.isLive('p'), isFalse);
      expect(notified, greaterThan(0));
    });

    test('only the first eight eligible servers are watched', () async {
      final many = [
        _server('legacy', 'Stary', ServerType.community, schemaVersion: null),
        _server(
          'held',
          'W przygotowaniu',
          ServerType.friends,
          activationState: 'held',
        ),
        for (var i = 0; i < 12; i++)
          _server('s$i', 'Serwer $i', ServerType.friends),
      ];
      final repository = _repository(mine: many);
      final liveness = ServerDirectoryLiveness(repository: repository);
      addTearDown(liveness.dispose);

      liveness.track(many);

      expect(ServerDirectoryLiveness.budget, 8);
      expect(liveness.openWatches, 8);
      expect(repository.watchChannelsCalls, 8);
      // The same list again opens nothing new.
      liveness.track(many);
      expect(repository.watchChannelsCalls, 8);
    });

    test('a hidden board keeps no listener and no lamp', () async {
      final visible = ValueNotifier(true);
      final repository = _repository(channels: [_stage('s')]);
      final liveness = ServerDirectoryLiveness(
        repository: repository,
        isVisible: visible,
      );
      addTearDown(liveness.dispose);
      liveness.track(_mine());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(liveness.isLive('s'), isTrue);

      visible.value = false;
      expect(liveness.openWatches, 0);
      expect(liveness.isLive('s'), isFalse, reason: 'a lamp is a claim of now');

      visible.value = true;
      expect(liveness.openWatches, 4);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(liveness.isLive('s'), isTrue);

      // The board under a hosted workspace is off screen as well.
      liveness.track(_mine(), active: false);
      expect(liveness.openWatches, 0);
      expect(liveness.isLive('s'), isFalse);
    });

    test('a board covered by a full-screen route keeps no listener and no '
        'lamp, and gets both back', () async {
      final repository = _repository(channels: [_stage('s')]);
      final liveness = ServerDirectoryLiveness(repository: repository);
      addTearDown(liveness.dispose);
      liveness.track(_mine());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(liveness.openWatches, 4);
      expect(liveness.isLive('s'), isTrue);

      liveness.covered = true;
      expect(liveness.openWatches, 0);
      expect(liveness.isLive('s'), isFalse, reason: 'a lamp is a claim of now');
      // The directory changing under the route opens nothing either.
      liveness.track([..._mine(), _server('n', 'Nowy', ServerType.friends)]);
      expect(liveness.openWatches, 0);

      liveness.covered = false;
      expect(liveness.openWatches, 5);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(liveness.isLive('s'), isTrue);

      // Covered AND hidden by the shell: one of them lifting is not enough.
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final both = ServerDirectoryLiveness(
        repository: repository,
        isVisible: visible,
      );
      addTearDown(both.dispose);
      both.track(_mine());
      both.covered = true;
      visible.value = false;
      both.covered = false;
      expect(both.openWatches, 0);
      visible.value = true;
      expect(both.openWatches, 4);
    });

    test('channels that fail to read are a server with no lamp', () async {
      final repository = _repository()
        ..channelStream = Stream<List<ServerChannel>>.error(
          StateError('permission-denied'),
        );
      final liveness = ServerDirectoryLiveness(repository: repository);
      addTearDown(liveness.dispose);
      liveness.track(_mine());
      await Future<void>.delayed(Duration.zero);
      expect(liveness.isLive('s'), isFalse);
    });
  });

  // --------------------------------------------------------- pasted links

  group('parsePastedServerLink', () {
    test('reads the canonical link, with and without a channel', () {
      expect(
        parsePastedServerLink('https://app.yovoice.app/?server=abc123'),
        const ServerLinkTarget(serverId: 'abc123'),
      );
      expect(
        parsePastedServerLink(
          '  https://app.yovoice.app/?server=abc123&channel=general \n',
        ),
        const ServerLinkTarget(serverId: 'abc123', channelId: 'general'),
      );
      expect(
        parsePastedServerLink(
          buildServerLink('s_1', channelId: 'c-2').toString(),
        ),
        const ServerLinkTarget(serverId: 's_1', channelId: 'c-2'),
      );
    });

    test('a link pasted without its scheme still resolves', () {
      expect(
        parsePastedServerLink('app.yovoice.app/?server=abc123'),
        const ServerLinkTarget(serverId: 'abc123'),
      );
    });

    test('the historic club link opens the same server', () {
      expect(
        parsePastedServerLink('https://yovoice.app/?club=old-1'),
        const ServerLinkTarget(serverId: 'old-1'),
      );
    });

    test('everything else fails closed', () {
      for (final input in [
        '',
        '   ',
        'abc123',
        'https://example.com/?server=abc123',
        'http://app.yovoice.app/?server=abc123',
        'https://app.yovoice.app/?server=abc123&next=evil',
        'https://app.yovoice.app/?server=a/b',
        'https://app.yovoice.app/?server=abc123#frag',
        'https://app.yovoice.app/?server=abc 123',
        'javascript:alert(1)',
        'https://app.yovoice.app/?page=someone',
      ]) {
        expect(parsePastedServerLink(input), isNull, reason: input);
      }
    });
  });

  // ------------------------------------------------------------ the board

  group('the board', () {
    testWidgets('title, "Twoje serwery" and "Serwery publiczne" in that '
        'order; nothing pretends to be live', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));

      final headings = tester
          .widgetList<HomeSectionHeader>(find.byType(HomeSectionHeader))
          .map((header) => header.title)
          .toList();
      expect(headings, ['Twoje serwery', 'Serwery publiczne']);
      expect(find.text('Serwery'), findsOneWidget);
      // The LIVE wave's section and every claim that belongs to it are
      // absent: no heading, no placeholder, no count.
      expect(find.text('Na żywo'), findsNothing);
      expect(find.text('Nikt teraz nie nadaje'), findsNothing);
      expect(find.text('Obserwowani'), findsNothing);
      expect(find.text('Obserwowani twórcy'), findsNothing);
      expect(find.byKey(const ValueKey('server-live-pill')), findsNothing);
      for (final id in ['s', 'p', 'r', 'f']) {
        expect(_row(id), findsOneWidget);
        expect(_lamp(id), findsNothing, reason: 'no channel is live');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the LIVE wave mounts its section between the title and '
        '"Twoje serwery"', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _board(
          _repository(),
          liveSectionBuilder: (context) =>
              const SizedBox(key: ValueKey('live-seam'), height: 40),
        ),
      );
      final seam = tester.getRect(find.byKey(const ValueKey('live-seam')));
      expect(seam.top, greaterThan(tester.getRect(find.text('Serwery')).top));
      expect(
        seam.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Twoje serwery')).top),
      );
    });

    testWidgets('the lamp is drawn only where the channel projection says '
        'live, and that server leads the list', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository(channels: [_stage('f')])));

      expect(_lamp('f'), findsOneWidget);
      expect(
        find.descendant(of: _lamp('f'), matching: find.text('na żywo')),
        findsOneWidget,
      );
      for (final id in ['s', 'p', 'r']) {
        expect(_lamp(id), findsNothing, reason: id);
      }
      expect(
        tester.getTopLeft(_row('f')).dy,
        lessThan(tester.getTopLeft(_row('s')).dy),
        reason: 'a live server is never hidden behind "Pokaż wszystkie"',
      );
      // No number of viewers or listeners anywhere on the board.
      qaExpectNoMatch(tester, qaFabricatedCount, 'a fabricated count');
    });

    testWidgets('a slot the shell hides drops its lamps and its listeners', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final repository = _repository(channels: [_stage('s')]);
      await pumpServers(tester, _board(repository, isVisible: visible));
      expect(_lamp('s'), findsOneWidget);
      final opened = repository.watchChannelsCalls;

      visible.value = false;
      await tester.pumpAndSettle();
      expect(_lamp('s'), findsNothing);
      expect(repository.watchChannelsCalls, opened);

      visible.value = true;
      await tester.pumpAndSettle();
      expect(_lamp('s'), findsOneWidget);
    });

    testWidgets('on a phone the board under an opened server holds no lamp '
        'listener, and lights its lamps again on the way back', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _CountingChannels()
        ..servers = _mine()
        ..publicServers = _publicServers()
        ..channels = [_stage('s')]
        ..myRole = null;
      await pumpServers(tester, _board(repository));
      expect(_lamp('s'), findsOneWidget);
      const mine = ['s', 'p', 'r', 'f'];
      expect(
        {for (final id in mine) id: repository.open[id]},
        {for (final id in mine) id: 1},
        reason: 'one channel listener per server while the board is seen',
      );

      // A sheet over the board is not a route that hides it.
      await tester.tap(_add);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-add-sheet')), findsOne);
      expect([for (final id in mine) repository.open[id]], everyElement(1));
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-add-sheet')), findsNothing);

      // A phone opens a server as a pushed route; the board stays built
      // under it for the whole visit.
      await tester.ensureVisible(_card('pub-j'));
      await tester.tap(_card('pub-j'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerWorkspaceScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        [for (final id in mine) repository.open[id]],
        everyElement(0),
        reason: 'nobody can see a lamp under the opened server',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ServerWorkspaceScreen), findsNothing);
      expect([for (final id in mine) repository.open[id]], everyElement(1));
      expect(_lamp('s'), findsOneWidget);
    });

    testWidgets('five rows, then "Pokaż wszystkie"', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final many = [
        ..._mine(),
        for (var i = 0; i < 4; i++)
          _server('m$i', 'Dodatkowy $i', ServerType.friends),
      ];
      await pumpServers(tester, _board(_repository(mine: many)));

      expect(find.byType(ServerBoardRow), findsNWidgets(5));
      expect(_row('m0'), findsOneWidget);
      expect(_row('m1'), findsNothing);
      final toggle = find.byKey(const ValueKey('servers-show-all'));
      expect(
        find.descendant(of: toggle, matching: find.text('Pokaż wszystkie')),
        findsOneWidget,
      );

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byType(ServerBoardRow, skipOffstage: false),
        findsNWidgets(8),
      );
      expect(find.text('Pokaż mniej'), findsOneWidget);

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(ServerBoardRow), findsNWidgets(5));
    });

    testWidgets('four servers need no "Pokaż wszystkie"', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      expect(find.byKey(const ValueKey('servers-show-all')), findsNothing);
    });
  });

  group('"Serwery publiczne"', () {
    testWidgets('lists the joinable public servers the account is not in', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository(
        public: [
          ..._publicServers(),
          // Already a member: it is in "Twoje serwery", not offered again.
          _mine().first,
          // Not joinable from the admission.
          _server(
            'pub-legacy',
            'Stary klub',
            ServerType.community,
            privacy: ServerPrivacy.public,
            schemaVersion: null,
          ),
        ],
      );
      await pumpServers(tester, _board(repository));

      expect(repository.publicServerLimits, [
        ServerService.publicDirectoryReadLimit,
      ]);
      expect(_card('pub-f'), findsOneWidget);
      expect(_card('pub-j'), findsOneWidget);
      expect(_card('pub-n'), findsOneWidget);
      expect(_card('s'), findsNothing);
      expect(_card('pub-legacy'), findsNothing);
      expect(find.text('Społeczność · 312 osób'), findsOneWidget);
      expect(find.text('Serwer podcastu · 26 osób'), findsOneWidget);
      expect(find.text('Zobacz'), findsNWidgets(3));
      // Two columns on a phone.
      expect(
        tester.getTopLeft(_card('pub-f')).dy,
        tester.getTopLeft(_card('pub-j')).dy,
      );
      expect(
        tester.getSize(_card('pub-f')).height,
        tester.getSize(_card('pub-j')).height,
        reason: 'cards in a row share one height',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('three columns on a tablet, four on a desktop', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final public = [
        for (var i = 0; i < 5; i++) _public('pub-$i', 'Publiczny $i', 50 - i),
      ];
      await pumpServers(
        tester,
        _board(_repository(public: public)),
        size: const Size(768, 1024),
      );
      double top(String id) => tester.getTopLeft(_card(id)).dy;
      expect(top('pub-0'), top('pub-2'));
      expect(top('pub-3'), greaterThan(top('pub-2')));

      await pumpServers(
        tester,
        _board(_repository(public: public)),
        size: const Size(1440, 900),
      );
      expect(top('pub-0'), top('pub-3'));
      expect(top('pub-4'), greaterThan(top('pub-3')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty listing leaves no section behind', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository(public: const [])));
      expect(find.text('Serwery publiczne'), findsNothing);
      expect(find.byType(ServerPublicCard), findsNothing);
      expect(find.byKey(const ValueKey('servers-public-error')), findsNothing);
      expect(find.text('Twoje serwery'), findsOneWidget);
    });

    testWidgets('a repository that cannot list has no section and no error', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServersScreen(
          isRootTab: true,
          repository: _NoPublicListing(_repository()),
        ),
      );
      expect(_row('s'), findsOneWidget);
      expect(find.text('Serwery publiczne'), findsNothing);
      expect(find.byKey(const ValueKey('servers-public-error')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed listing says so and retries', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()
        ..publicServersStream = Stream<List<Server>>.error(
          StateError('permission-denied'),
        );
      await pumpServers(tester, _board(repository));

      expect(find.text('Serwery publiczne'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('servers-public-error')),
        findsOneWidget,
      );
      expect(
        find.text('Nie udało się wczytać serwerów publicznych.'),
        findsOneWidget,
      );
      expect(find.byType(ServerPublicCard), findsNothing);
      // The account's own servers are untouched by the failure.
      expect(_row('s'), findsOneWidget);

      repository.publicServersStream = null;
      await tester.tap(find.byKey(const ValueKey('servers-public-retry')));
      await tester.pumpAndSettle();
      expect(repository.publicServerLimits, [
        ServerService.publicDirectoryReadLimit,
        ServerService.publicDirectoryReadLimit,
      ]);
      expect(find.byKey(const ValueKey('servers-public-error')), findsNothing);
      expect(_card('pub-f'), findsOneWidget);
    });

    testWidgets('eight cards at most, after the account\'s own servers and '
        'the roots without a join path are taken out', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository(
        public: [
          // The listing leads with rows that are not cards: the account's
          // own public server and legacy clubs.
          _mine().first,
          for (var i = 0; i < 3; i++)
            _server(
              'old-$i',
              'Stary klub $i',
              ServerType.community,
              privacy: ServerPrivacy.public,
              schemaVersion: null,
            ),
          for (var i = 0; i < 11; i++)
            _public('pub-$i', 'Publiczny $i', 90 - i),
        ],
      );
      await pumpServers(
        tester,
        _board(repository),
        size: const Size(1440, 2400),
      );

      expect(
        find.byType(ServerPublicCard),
        findsNWidgets(ServerService.publicDirectoryLimit),
      );
      for (var i = 0; i < 8; i++) {
        expect(_card('pub-$i'), findsOneWidget, reason: 'pub-$i');
      }
      expect(_card('pub-8'), findsNothing);
      expect(_card('s'), findsNothing);
      expect(_card('old-0'), findsNothing);

      // The filter looks through everything that was listed, not only the
      // eight on screen.
      await tester.enterText(
        find.byKey(const ValueKey('servers-search-field')),
        'publiczny 10',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerPublicCard), findsOneWidget);
      expect(_card('pub-10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the account\'s own list failing and coming back does not '
        'break the public section', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The production listing is a single-subscription stream. The public
      // section used to be subscribed INSIDE the own list's builder, so the
      // own list's error state unmounted it and the retry listened to the
      // same stream a second time: "Stream has already been listened to",
      // an error box where the board should be.
      final repository = _FlakyDirectory()
        ..servers = _mine()
        ..publicServers = _publicServers();
      await pumpServers(tester, _board(repository));
      expect(_row('s'), findsOneWidget);
      expect(_card('pub-f'), findsOneWidget);

      repository.own.addError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(find.byType(YoErrorState), findsOneWidget);
      expect(_row('s'), findsNothing);

      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pump();
      repository.own.add(_mine());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(YoErrorState), findsNothing);
      expect(_row('s'), findsOneWidget);
      expect(_card('pub-f'), findsOneWidget);
      expect(
        repository.publicServerLimits,
        hasLength(1),
        reason: 'the public listing is opened once, not once per recovery',
      );
    });

    testWidgets('a card opens the public admission, and joining goes through '
        'joinServerV1', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()..myRole = null;
      await pumpServers(tester, _board(repository));

      await tester.ensureVisible(_card('pub-j'));
      await tester.tap(_card('pub-j'));
      await tester.pumpAndSettle();
      // A phone pushes the workspace as a route with a real Back.
      expect(find.byType(ServerWorkspaceScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byKey(const ValueKey('server-public-admission')), findsOne);
      expect(find.text('Języki przy kawie'), findsWidgets);
      expect(repository.calls, isEmpty, reason: 'looking joins nothing');

      await tester.tap(find.byKey(const ValueKey('server-public-join')));
      await tester.pumpAndSettle();
      expect(repository.calls.map((call) => call.$1), ['joinServerV1']);
      expect(repository.calls.single.$2['serverId'], 'pub-j');
      expect(
        find.byKey(const ValueKey('server-public-admission')),
        findsNothing,
      );
    });

    testWidgets('from the tablet tier up the admission opens in the slot, '
        'with a way back', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()..myRole = null;
      await pumpServers(
        tester,
        _board(repository),
        size: const Size(1440, 900),
      );

      await tester.tap(_card('pub-f'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('servers-inline-pub-f')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-public-admission')), findsOne);
      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'the shell owns chrome',
      );
      expect(_add, findsNothing, reason: 'the board is under the workspace');

      await tester.tap(find.byKey(const ValueKey('server-state-back')));
      await tester.pumpAndSettle();
      expect(_add, findsOneWidget);
      expect(_card('pub-f'), findsOneWidget);
    });

    testWidgets('the card is one control named after the server', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await pumpServers(tester, _board(_repository()));
      expect(
        tester.getSemantics(_card('pub-f')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label:
              'Fotografia po godzinach, Społeczność · 312 osób. '
              'Zobacz',
        ),
      );
      handle.dispose();
    });
  });

  group('the "+" sheet', () {
    testWidgets('offers exactly the actions that exist today', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      await tester.tap(_add);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const ValueKey('servers-add-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        tester
            .widgetList<ListTile>(
              find.descendant(of: sheet, matching: find.byType(ListTile)),
            )
            .map((tile) => (tile.title! as Text).data),
        ['Stwórz serwer', 'Dołącz z linku'],
      );
      // `Nadaj LIVE` arrives with the LIVE wave; nothing stands in for it.
      expect(find.text('Nadaj LIVE'), findsNothing);
      expect(find.textContaining('LIVE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Stwórz serwer" opens the creation flow', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      await tester.tap(_add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('servers-create')));
      await tester.pumpAndSettle();
      expect(find.byType(CreateServerScreen), findsOneWidget);
    });

    testWidgets('a host that owns creation is asked instead', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var asked = 0;
      await pumpServers(
        tester,
        _board(_repository(), onCreateServer: () => asked++),
      );
      await tester.tap(_add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('servers-create')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.byType(CreateServerScreen), findsNothing);
    });

    testWidgets('the disc is a 44 px button with a spoken name', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await pumpServers(tester, _board(_repository()));
      expect(tester.getSize(_add).shortestSide, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(_add),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Stwórz serwer lub dołącz',
        ),
      );
      handle.dispose();
    });
  });

  group('"Dołącz z linku"', () {
    Future<void> openLinkSheet(WidgetTester tester) async {
      await tester.tap(_add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('servers-join-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-join-link-sheet')), findsOne);
    }

    testWidgets('a link to a public server opens its admission', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()..myRole = null;
      await pumpServers(tester, _board(repository));
      await openLinkSheet(tester);

      await tester.enterText(
        find.byKey(const ValueKey('servers-join-link-field')),
        'https://app.yovoice.app/?server=pub-n',
      );
      await tester.tap(find.byKey(const ValueKey('servers-join-link-open')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('servers-join-link-sheet')),
        findsNothing,
      );
      final workspace = tester.widget<ServerWorkspaceScreen>(
        find.byType(ServerWorkspaceScreen),
      );
      expect(workspace.serverId, 'pub-n');
      expect(workspace.initialChannelId, isNull);
      expect(find.byKey(const ValueKey('server-public-admission')), findsOne);
      expect(repository.calls, isEmpty, reason: 'opening a link joins nothing');
    });

    testWidgets('the channel of the link is carried to the workspace', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      await openLinkSheet(tester);
      await tester.enterText(
        find.byKey(const ValueKey('servers-join-link-field')),
        'app.yovoice.app/?server=s&channel=general',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      final workspace = tester.widget<ServerWorkspaceScreen>(
        find.byType(ServerWorkspaceScreen),
      );
      expect(workspace.serverId, 's');
      expect(workspace.initialChannelId, 'general');
    });

    testWidgets('anything else is refused in the field, and nothing opens', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      await openLinkSheet(tester);
      await tester.enterText(
        find.byKey(const ValueKey('servers-join-link-field')),
        'https://example.com/?server=pub-n',
      );
      await tester.tap(find.byKey(const ValueKey('servers-join-link-open')));
      await tester.pumpAndSettle();

      // The field says it (the text field carries the message itself and
      // announces it with the input).
      expect(find.text('To nie jest link do serwera YO Voice.'), findsWidgets);
      expect(find.byKey(const ValueKey('servers-join-link-sheet')), findsOne);
      expect(find.byType(ServerWorkspaceScreen), findsNothing);

      // Typing again clears the message.
      await tester.enterText(
        find.byKey(const ValueKey('servers-join-link-field')),
        'https://app.yovoice.app/?server=',
      );
      await tester.pump();
      expect(find.text('To nie jest link do serwera YO Voice.'), findsNothing);
    });

    testWidgets('"Wklej" takes the link from the clipboard', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{
                'text': ' https://app.yovoice.app/?server=pub-f ',
              }
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpServers(tester, _board(_repository()..myRole = null));
      await openLinkSheet(tester);
      await tester.tap(find.byKey(const ValueKey('servers-join-link-paste')));
      await tester.pumpAndSettle();
      expect(
        find.text('https://app.yovoice.app/?server=pub-f'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('servers-join-link-open')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ServerWorkspaceScreen>(find.byType(ServerWorkspaceScreen))
            .serverId,
        'pub-f',
      );
    });
  });

  group('a brand-new account', () {
    testWidgets('gets the invitation and still sees where it can go', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository(mine: const [])));

      expect(find.byKey(const ValueKey('servers-newcomer')), findsOneWidget);
      expect(find.text('Twoje serwery'), findsOneWidget);
      expect(find.text('Twoje miejsce na wspólne rozmowy'), findsOneWidget);
      expect(find.byType(ServerBoardRow), findsNothing);
      expect(find.text('Serwery publiczne'), findsOneWidget);
      await tester.scrollUntilVisible(
        _card('pub-f'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_card('pub-f'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('both of its buttons work', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository(mine: const [])));
      await tester.tap(find.byKey(const ValueKey('servers-empty-join-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-join-link-sheet')), findsOne);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('servers-empty-create')));
      await tester.pumpAndSettle();
      expect(find.byType(CreateServerScreen), findsOneWidget);
    });
  });

  group('the name filter', () {
    testWidgets('on a phone it opens from the search button and filters both '
        'lists', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      expect(find.byKey(const ValueKey('servers-search-field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('servers-search')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('servers-search-field'));
      expect(field, findsOneWidget);
      expect(find.text('Szukaj serwera'), findsOneWidget);

      await tester.enterText(field, 'noc');
      await tester.pumpAndSettle();
      expect(_row('s'), findsOneWidget, reason: 'Nocne Granie');
      expect(_row('p'), findsNothing);
      expect(_card('pub-n'), findsOneWidget, reason: 'Nocna audycja');
      expect(_card('pub-f'), findsNothing);

      await tester.enterText(field, 'zzz');
      await tester.pumpAndSettle();
      expect(find.byType(ServerBoardRow), findsNothing);
      expect(find.byType(ServerPublicCard), findsNothing);
      expect(find.byKey(const ValueKey('servers-no-matches')), findsOneWidget);
      expect(
        find.text('Żaden serwer nie pasuje do wyszukiwania.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('servers-search-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('servers-search-field')), findsNothing);
      expect(find.byType(ServerBoardRow), findsNWidgets(4));
      expect(find.text('Serwery'), findsOneWidget);
      // Closing hands focus back to the button that opened the field: a
      // focused field that leaves the tree would drop it to the route.
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: find.byKey(const ValueKey('servers-search')),
              matching: find.byIcon(Icons.search_rounded),
            ),
          ),
        ).hasFocus,
        isTrue,
        reason: 'focus was left on nothing when the field closed',
      );
    });

    testWidgets('in the desktop slot it sits in the title row', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _board(_repository()),
        size: const Size(1440, 900),
      );
      final field = find.byKey(const ValueKey('servers-search-field'));
      expect(field, findsOneWidget);
      expect(find.byKey(const ValueKey('servers-search')), findsNothing);
      expect(tester.getSize(field).width, ServersScreen.inlineSearchFieldWidth);
      expect(find.text('Serwery'), findsOneWidget);

      await tester.enterText(field, 'FALA');
      await tester.pumpAndSettle();
      expect(_row('f'), findsOneWidget, reason: 'case does not matter');
      expect(_row('s'), findsNothing);
    });

    testWidgets('a filter reaches servers behind "Pokaż wszystkie"', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final many = [
        ..._mine(),
        for (var i = 0; i < 6; i++)
          _server('m$i', 'Dodatkowy $i', ServerType.friends),
      ];
      await pumpServers(tester, _board(_repository(mine: many)));
      expect(_row('m5'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('servers-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('servers-search-field')),
        'dodatkowy 5',
      );
      await tester.pumpAndSettle();
      expect(_row('m5'), findsOneWidget);
      expect(find.byKey(const ValueKey('servers-show-all')), findsNothing);
    });
  });

  group('a row\'s actions', () {
    Finder more(String id) =>
        find.byKey(ValueKey('server-directory-actions-$id'));
    final sheet = find.byKey(const ValueKey('server-directory-actions-sheet'));

    testWidgets('at rest the row is the chosen frame: a chevron, no button', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(tester, _board(_repository()));
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(
        find.descendant(
          of: _row('p'),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pointer brings the "…" button without moving the text', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _board(_repository()),
        size: const Size(1440, 900),
      );
      final name = tester.getRect(find.text('Paczka z liceum'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_row('p')));
      await tester.pumpAndSettle();

      expect(more('p'), findsOneWidget);
      expect(more('s'), findsNothing);
      expect(tester.getRect(find.text('Paczka z liceum')), name);

      await tester.tap(more('p'));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(find.byKey(const ValueKey('server-directory-leave')), findsOne);
    });

    testWidgets('a secondary click opens the same sheet', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        _board(_repository()),
        size: const Size(1440, 900),
      );
      await tester.tap(_row('s'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(find.byKey(const ValueKey('server-directory-delete')), findsOne);
    });

    testWidgets('a screen reader hears the lamp once', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await pumpServers(tester, _board(_repository(channels: [_stage('s')])));
      // The lamp's dot and its word carry the same "na żywo" on the board.
      final label = tester.getSemantics(_row('s')).label;
      expect(label, contains('Nocne Granie'));
      expect('na żywo'.allMatches(label), hasLength(1), reason: label);
      handle.dispose();
    });

    testWidgets('a screen reader gets the action by name', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await pumpServers(tester, _board(_repository()));
      final data = tester.getSemantics(_row('p')).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      final labels = [
        for (final id in data.customSemanticsActionIds ?? const <int>[])
          CustomSemanticsAction.getAction(id)?.label,
      ];
      expect(labels, contains('Zarządzaj serwerem'));
      handle.dispose();
    });
  });
}
