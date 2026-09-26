import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_question_attention.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_podcast_questions_board.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_waiting_dot.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';

import 'server_podcast_test.dart' as podcast;
import 'server_test_support.dart';

/// The podcast host's "new listener questions" dot (ADR "listener questions
/// dot"): who sees it, where, when it clears, and what a hidden Servers slot
/// costs.
final _t0 = DateTime.utc(2026, 9, 25, 18);

ServerPodcastQuestion _question(
  String id, {
  required int minute,
  int votes = 0,
  String author = 'listener-1',
  String serverId = 's',
}) => ServerPodcastQuestion(
  id: id,
  serverId: serverId,
  channelId: 'questions',
  authorId: author,
  authorName: 'Ola',
  body: 'Pytanie $id',
  status: ServerPodcastQuestionStatus.queued,
  voteCount: votes,
  revision: 1,
  createdAt: _t0.add(Duration(minutes: minute)),
  updatedAt: _t0.add(Duration(minutes: minute)),
);

/// The board's list as a live stream the test can push to, like Firestore.
class _LiveQuestions {
  _LiveQuestions(this.current);
  List<ServerPodcastQuestion> current;
  final _changes = StreamController<List<ServerPodcastQuestion>>.broadcast();

  Stream<List<ServerPodcastQuestion>> get stream => Stream.multi((listener) {
    listener.add(current);
    final subscription = _changes.stream.listen(listener.add);
    listener.onCancel = subscription.cancel;
  });

  void set(TestServerRepository repository, List<ServerPodcastQuestion> next) {
    current = next;
    _changes.add(next);
    repository.setPodcastQuestions(next);
  }
}

TestServerRepository _repository({
  ServerMemberRole role = ServerMemberRole.owner,
  List<ServerPodcastQuestion>? questions,
}) {
  final repository = TestServerRepository()
    ..servers = [podcast.podcastServer().withDirectoryRole(role)]
    ..channels = podcast.podcastChannels()
    ..myRole = role
    ..podcastQuestions = questions ?? [_question('q1', minute: 1)];
  return repository;
}

Widget _workspace(
  TestServerRepository repository, {
  String channelId = 'studio',
  ValueListenable<bool>? isVisible,
}) => ServerWorkspaceScreen(
  serverId: 's',
  repository: repository,
  isRootTab: true,
  initialChannelId: channelId,
  chatService: podcast.podcastChat(),
  connector: FakeServerMediaConnector(),
  podcastEpisodeRepository: repository,
  isVisible: isVisible,
);

Finder get _tabDot => find.byKey(const ValueKey('server-tab-chat-waiting'));
Finder get _rowDot =>
    find.byKey(const ValueKey('server-channel-questions-waiting-questions'));
Finder get _channelsDot =>
    find.byKey(const ValueKey('server-open-channels-waiting'));
Finder get _anyDot => find.byType(ServerWaitingDot);

/// Past the board's debounce, so a cursor write (if any) has been sent.
Future<void> _settleSeen(WidgetTester tester) async {
  await tester.pump(
    ServerPodcastQuestionsBoard.seenDebounce + const Duration(milliseconds: 50),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('who sees the dot', () {
    for (final role in [
      ServerMemberRole.owner,
      ServerMemberRole.admin,
      ServerMemberRole.moderator,
    ]) {
      testWidgets('${role.name}: a new question lights the Pytania tab', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _repository(role: role);
        await pumpServers(tester, _workspace(repository));

        expect(_tabDot, findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Nowe pytania słuchaczy')),
          findsWidgets,
        );
        // The studio's own tab strip already offers `Pytania`; the header's
        // `Kanały` does not repeat the dot.
        expect(_channelsDot, findsNothing);
        expect(repository.questionSeenWrites, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    for (final role in [ServerMemberRole.member, ServerMemberRole.guest]) {
      testWidgets('${role.name}: no dot, no listener, no cursor write', (
        tester,
      ) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _repository(role: role);
        await pumpServers(tester, _workspace(repository));
        expect(_anyDot, findsNothing);
        expect(repository.unseenWatchCount, 0);

        await tester.tap(find.byKey(const ValueKey('server-tab-chat')));
        await tester.pumpAndSettle();
        await _settleSeen(tester);
        expect(
          find.byKey(const ValueKey('server-podcast-questions-board')),
          findsOneWidget,
        );
        expect(repository.questionSeenWrites, isEmpty);
        expect(_anyDot, findsNothing);
      });
    }

    testWidgets('a held podcast server draws no dot and opens no listener', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()
        ..servers = [
          podcast
              .podcastServer(held: true)
              .withDirectoryRole(ServerMemberRole.owner),
        ];
      await pumpServers(tester, _workspace(repository));
      expect(_anyDot, findsNothing);
      expect(repository.unseenWatchCount, 0);
    });
  });

  group('what the dot means', () {
    testWidgets('no questions: no dot', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository(questions: const []);
      await pumpServers(tester, _workspace(repository));
      expect(repository.openUnseenWatches, 1);
      expect(_anyDot, findsNothing);
    });

    testWidgets('a cursor that cannot be read fails quiet: no dot', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()
        ..unseenError = StateError('permission-denied');
      await pumpServers(tester, _workspace(repository));
      expect(_anyDot, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the host\'s own question is not news to them', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository(
        questions: [_question('mine', minute: 1, author: 'owner')],
      );
      await pumpServers(tester, _workspace(repository));
      expect(_anyDot, findsNothing);
    });

    testWidgets('a question older than the cursor: no dot', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()
        ..questionSeenAt['s_questions'] = _t0.add(const Duration(minutes: 5));
      await pumpServers(tester, _workspace(repository));
      expect(_anyDot, findsNothing);
    });

    test('the decision itself: none, equal, older and own', () {
      final at = _t0;
      bool unseen(DateTime? newest, DateTime? seen, {String by = 'a'}) =>
          serverPodcastQuestionsUnseen(
            newestCreatedAt: newest,
            newestAuthorId: by,
            seenAt: seen,
            viewerId: 'me',
          );
      expect(unseen(null, null), isFalse);
      expect(unseen(at, null), isTrue);
      expect(unseen(at, at), isFalse);
      expect(unseen(at.add(const Duration(microseconds: 1)), at), isTrue);
      expect(unseen(at, at.add(const Duration(seconds: 1))), isFalse);
      expect(unseen(at, null, by: 'me'), isFalse);
      expect(serverQuestionSeenId('srv_a', 'ch_b'), 'srv_a_ch_b');
      expect(serverQuestionSeenId('a/b', 'c'), isNull);
    });
  });

  group('opening the list clears it', () {
    testWidgets('phone: the Pytania tab writes the newest createdAt, once', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The board orders by votes: the most-voted is the OLDEST here, so a
      // cursor taken from the first card would stop short of the newest.
      final repository = _repository(
        questions: [
          _question('old', minute: 1, votes: 9),
          _question('new', minute: 7),
          _question('mid', minute: 4, votes: 2),
        ],
      );
      await pumpServers(tester, _workspace(repository));
      expect(_tabDot, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-tab-chat')));
      await tester.pumpAndSettle();
      // Never on the selected tab: the list is on screen.
      expect(_tabDot, findsNothing);
      expect(repository.questionSeenWrites, isEmpty, reason: 'debounced');

      await _settleSeen(tester);
      expect(repository.questionSeenWrites, [
        ('s', 'questions', _t0.add(const Duration(minutes: 7))),
      ]);

      // Back on the studio the dot stays gone.
      await tester.tap(find.byKey(const ValueKey('server-tab-scene')));
      await tester.pumpAndSettle();
      expect(_anyDot, findsNothing);
    });

    testWidgets('a burst of new questions moves the cursor once', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository(questions: [_question('a', minute: 1)]);
      final live = _LiveQuestions(repository.podcastQuestions);
      repository.podcastQuestionsStream = live.stream;
      await pumpServers(tester, _workspace(repository, channelId: 'questions'));

      for (var i = 2; i <= 6; i++) {
        live.set(repository, [
          ...live.current,
          _question('q$i', minute: i),
        ]);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, hasLength(1));
      expect(
        repository.questionSeenWrites.single.$3,
        _t0.add(const Duration(minutes: 6)),
      );
    });

    testWidgets('desktop: the context column beside the studio clears it', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository();
      await pumpServers(
        tester,
        _workspace(repository),
        size: const Size(1440, 900),
      );
      // The row shows it until the board beside the studio has been on
      // screen for the debounce.
      expect(_rowDot, findsOneWidget);
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, hasLength(1));
      expect(_anyDot, findsNothing);
    });

    testWidgets('desktop on another channel: the Questions row keeps the dot', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository();
      await pumpServers(
        tester,
        _workspace(repository, channelId: 'discussion'),
        size: const Size(1440, 900),
      );
      await _settleSeen(tester);
      expect(_rowDot, findsOneWidget);
      expect(repository.questionSeenWrites, isEmpty);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-channel-questions')),
          matching: find.byType(ServerWaitingDot),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('server-channel-questions')));
      await tester.pumpAndSettle();
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, hasLength(1));
      expect(_anyDot, findsNothing);
    });

    testWidgets('phone on another channel: Kanały carries it into the sheet', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository();
      await pumpServers(tester, _workspace(repository, channelId: 'discussion'));
      expect(_channelsDot, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-open-channels')));
      await tester.pumpAndSettle();
      expect(_rowDot, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-channel-questions')));
      await tester.pumpAndSettle();
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, hasLength(1));
      expect(_anyDot, findsNothing);
    });
  });

  group('the retained Servers slot', () {
    testWidgets('hidden, it listens to nothing and writes nothing; back, the '
        'dot is right', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final repository = _repository(questions: const []);
      await pumpServers(tester, _workspace(repository, isVisible: visible));
      expect(repository.openUnseenWatches, 1);
      expect(_anyDot, findsNothing);

      visible.value = false;
      await tester.pumpAndSettle();
      expect(repository.openUnseenWatches, 0);

      // A listener asks while the host is on Home.
      repository.setPodcastQuestions([_question('q1', minute: 3)]);
      await _settleSeen(tester);
      expect(repository.unseenWatchCount, 1, reason: 'no read while hidden');
      expect(repository.questionSeenWrites, isEmpty);

      visible.value = true;
      await tester.pumpAndSettle();
      expect(repository.openUnseenWatches, 1);
      expect(_tabDot, findsOneWidget);
    });

    testWidgets('desktop: a board left on screen does not mark a question '
        'that arrived while the slot was hidden', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final repository = _repository(questions: const []);
      final live = _LiveQuestions(const []);
      repository.podcastQuestionsStream = live.stream;
      await pumpServers(
        tester,
        _workspace(repository, isVisible: visible),
        size: const Size(1440, 900),
      );
      expect(
        find.byKey(const ValueKey('server-podcast-questions-board')),
        findsOneWidget,
      );

      visible.value = false;
      await tester.pumpAndSettle();
      live.set(repository, [_question('q1', minute: 2)]);
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, isEmpty);

      // Back on Servers, the list really is in front of the host again.
      visible.value = true;
      await tester.pumpAndSettle();
      await _settleSeen(tester);
      expect(repository.questionSeenWrites, [
        ('s', 'questions', _t0.add(const Duration(minutes: 2))),
      ]);
      expect(_anyDot, findsNothing);
    });

    test('the controller pauses and resumes its listeners', () async {
      final visible = ValueNotifier<bool>(true);
      final repository = _repository();
      final attention = ServerQuestionAttention(
        repository: repository,
        isVisible: visible,
      );
      addTearDown(attention.dispose);
      addTearDown(visible.dispose);

      attention.trackDirectory(repository.servers);
      await pumpEventQueue();
      expect(attention.isWaiting('s'), isTrue);
      expect(repository.openUnseenWatches, 1);

      visible.value = false;
      await pumpEventQueue();
      expect(repository.openUnseenWatches, 0);
      // The last answer stands while nobody can see it.
      expect(attention.isWaiting('s'), isTrue);

      repository.questionSeenAt['s_questions'] = _t0.add(
        const Duration(hours: 1),
      );
      visible.value = true;
      await pumpEventQueue();
      expect(repository.openUnseenWatches, 1);
      expect(attention.isWaiting('s'), isFalse);
    });

    test('only moderated, active podcast servers are ever watched', () async {
      final repository = TestServerRepository()
        ..channels = [
          ...podcast.podcastChannels(),
          for (final channel in podcast.podcastChannels())
            ServerChannel(
              id: channel.id,
              serverId: 'm',
              name: channel.name,
              kind: channel.kind,
              position: channel.position,
              schemaVersion: 1,
            ),
        ]
        ..podcastQuestions = [
          _question('q1', minute: 1),
          _question('q2', minute: 1, serverId: 'm'),
        ];
      final attention = ServerQuestionAttention(repository: repository);
      addTearDown(attention.dispose);
      final server = podcast.podcastServer();
      attention.trackDirectory([
        server.withDirectoryRole(ServerMemberRole.admin),
        Server(
          id: 'm',
          name: 'Member',
          description: '',
          ownerId: 'x',
          type: ServerType.podcast,
          privacy: ServerPrivacy.public,
          schemaVersion: 1,
          activationState: 'active',
          directoryRole: ServerMemberRole.member,
        ),
      ]);
      await pumpEventQueue();
      expect(attention.isWaiting('s'), isTrue);
      expect(attention.isWaiting('m'), isFalse);
      expect(repository.unseenWatchCount, 1);
    });
  });

  group('outside the workspace', () {
    testWidgets('the directory tile carries the dot for a host only', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _repository()
        ..servers = [
          podcast.podcastServer().withDirectoryRole(ServerMemberRole.owner),
          Server(
            id: 'p2',
            name: 'Cudzy podcast',
            description: '',
            ownerId: 'x',
            type: ServerType.podcast,
            privacy: ServerPrivacy.public,
            schemaVersion: 1,
            activationState: 'active',
            directoryRole: ServerMemberRole.member,
          ),
        ]
        ..podcastQuestions = [
          _question('q1', minute: 1),
          _question('q2', minute: 1, serverId: 'p2'),
        ];
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: podcast.podcastChat(),
          connector: FakeServerMediaConnector(),
        ),
      );
      expect(
        find.byKey(const ValueKey('server-directory-questions-waiting-s')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-directory-questions-waiting-p2')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rail marks another podcast server, not the open one', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final friends = Server(
        id: 'f',
        name: 'Ekipa',
        description: '',
        ownerId: 'owner',
        type: ServerType.friends,
        privacy: ServerPrivacy.private,
        defaultChannelId: 'general',
        schemaVersion: 1,
        activationState: 'active',
        directoryRole: ServerMemberRole.owner,
      );
      final repository = _repository()
        ..servers = [
          friends,
          podcast.podcastServer().withDirectoryRole(ServerMemberRole.owner),
        ]
        ..channels = [
          ...podcast.podcastChannels(),
          const ServerChannel(
            id: 'general',
            serverId: 'f',
            name: 'ogólny',
            kind: ServerChannelKind.text,
            position: 0,
            schemaVersion: 1,
          ),
        ];
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: podcast.podcastChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-f')));
      await tester.pumpAndSettle();

      final railDot = find.byKey(
        const ValueKey('server-rail-questions-waiting-s'),
      );
      expect(railDot, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-rail-s')),
          matching: railDot,
        ),
        findsOneWidget,
      );
      // One listener serves the tile, the rail and the workspace alike.
      expect(repository.openUnseenWatches, 1);

      await tester.tap(find.byKey(const ValueKey('server-rail-s')));
      await tester.pumpAndSettle();
      // Now the podcast is open: its own surfaces carry the dot, the rail
      // does not repeat it.
      expect(railDot, findsNothing);
      expect(_rowDot, findsOneWidget);
    });

    testWidgets('a rail item draws a supplied mark and nothing by default', (
      tester,
    ) async {
      Widget item(Widget? attention) => MaterialApp(
        home: Scaffold(
          body: YoServerRailItem(
            key: const ValueKey('server-rail-x'),
            initial: 'P',
            type: ServerType.podcast,
            semanticLabel: 'Podcast',
            selected: false,
            onTap: () {},
            attention: attention,
          ),
        ),
      );
      await tester.pumpWidget(item(null));
      expect(_anyDot, findsNothing);
      await tester.pumpWidget(
        item(const ServerWaitingDot(semanticLabel: 'Nowe pytania słuchaczy')),
      );
      expect(_anyDot, findsOneWidget);
      expect(find.bySemanticsLabel('Nowe pytania słuchaczy'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final size in [const Size(320, 700), const Size(768, 1024)]) {
      for (final light in [false, true]) {
        testWidgets(
          '${size.width.toInt()} px at 200 percent '
          '(${light ? 'Pearl' : 'Dark'}): the tab keeps its dot',
          (tester) async {
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await pumpServers(
              tester,
              _workspace(_repository()),
              size: size,
              textScale: 2,
              light: light,
            );
            expect(_tabDot, findsOneWidget);
            expect(tester.takeException(), isNull);
            final tab = tester.getRect(
              find.byKey(const ValueKey('server-tab-chat')),
            );
            final dot = tester.getRect(_tabDot);
            expect(tab.contains(dot.center), isTrue);
          },
        );
      }
    }
  });
}
