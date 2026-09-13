import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';

import 'server_podcast_test.dart' as podcast;
import 'server_test_support.dart';

ServerPodcastQuestion question({
  String id = 'question-1',
  String body = 'Jak wybieracie gości?',
  int votes = 4,
  int revision = 3,
  bool onAir = false,
}) => ServerPodcastQuestion(
  id: id,
  serverId: 's',
  channelId: 'questions',
  authorId: 'listener-1',
  authorName: 'Ola',
  body: body,
  status: onAir
      ? ServerPodcastQuestionStatus.onAir
      : ServerPodcastQuestionStatus.queued,
  voteCount: votes,
  revision: revision,
  createdAt: DateTime.utc(2026, 9, 13, 12),
  updatedAt: DateTime.utc(2026, 9, 13, 12, 5),
  onAirAt: onAir ? DateTime.utc(2026, 9, 13, 12, 5) : null,
  onAirById: onAir ? 'moderator-1' : null,
);

TestServerRepository repository({
  ServerMemberRole role = ServerMemberRole.member,
  List<ServerPodcastQuestion>? questions,
}) => TestServerRepository()
  ..servers = [podcast.podcastServer()]
  ..channels = podcast.podcastChannels(studio: podcast.live)
  ..myRole = role
  ..podcastQuestions = questions ?? [question()];

void main() {
  testWidgets('the podcast stage context is the persisted Q&A board', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repository()),
      size: const Size(1440, 900),
    );

    expect(
      find.byKey(const ValueKey('server-context-questions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('server-podcast-questions-board')),
      findsOneWidget,
    );
    expect(find.text('Jak wybieracie gości?'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-thread-questions')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member submits one trimmed question with the exact callable', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = repository(questions: const []);
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repo, channelId: 'questions'),
      size: const Size(390, 844),
    );

    final composer = find.byKey(
      const ValueKey('server-podcast-question-composer'),
    );
    await tester.enterText(composer, '  Co zmieniło ten odcinek?  ');
    await tester.pump();
    final send = find.byKey(const ValueKey('server-podcast-question-send'));
    await tester.ensureVisible(send);
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    expect(send.hitTestable(), findsOneWidget);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(repo.calls.single.$1, 'createServerPodcastQuestionV1');
    expect(repo.calls.single.$2, {
      'serverId': 's',
      'channelId': 'questions',
      'requestId': 'request-1',
      'body': 'Co zmieniło ten odcinek?',
    });
    expect(find.text('Co zmieniło ten odcinek?'), findsNothing);
  });

  testWidgets('one member vote sends the question revision and toggled state', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final item = question(revision: 7, votes: 2);
    final repo = repository(questions: [item]);
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repo, channelId: 'questions'),
      size: const Size(390, 844),
    );

    final vote = find.byKey(
      const ValueKey('server-podcast-question-vote-question-1'),
    );
    await tester.ensureVisible(vote);
    await tester.tap(vote);
    await tester.pumpAndSettle();

    expect(repo.calls.single.$1, 'setServerPodcastQuestionVoteV1');
    expect(repo.calls.single.$2, {
      'serverId': 's',
      'channelId': 'questions',
      'questionId': 'question-1',
      'requestId': 'request-1',
      'expectedRevision': 7,
      'voted': true,
    });
  });

  testWidgets('moderator can put a question on air; member cannot', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = repository(role: ServerMemberRole.moderator);
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repo, channelId: 'questions'),
      size: const Size(390, 844),
    );
    final air = find.byKey(
      const ValueKey('server-podcast-question-air-question-1'),
    );
    await tester.ensureVisible(air);
    await tester.tap(air);
    await tester.pumpAndSettle();
    expect(repo.calls.single.$1, 'setServerPodcastQuestionOnAirV1');
    expect(repo.calls.single.$2, {
      'serverId': 's',
      'channelId': 'questions',
      'questionId': 'question-1',
      'requestId': 'request-1',
      'expectedRevision': 3,
      'onAir': true,
    });

    await pumpServers(
      tester,
      podcast.podcastWorkspace(repository(), channelId: 'questions'),
      size: const Size(390, 844),
    );
    expect(air, findsNothing);
  });

  testWidgets('on-air state is explicit and a moderator can clear it', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = repository(
      role: ServerMemberRole.moderator,
      questions: [question(onAir: true, revision: 9)],
    );
    await pumpServers(
      tester,
      podcast.podcastWorkspace(repo, channelId: 'questions'),
      size: const Size(390, 844),
    );
    expect(
      find.byKey(const ValueKey('server-podcast-question-on-air-question-1')),
      findsOneWidget,
    );
    expect(find.text('NA ANTENIE'), findsOneWidget);
    final air = find.byKey(
      const ValueKey('server-podcast-question-air-question-1'),
    );
    await tester.ensureVisible(air);
    await tester.tap(air);
    await tester.pumpAndSettle();
    expect(repo.calls.single.$2['onAir'], false);
    expect(repo.calls.single.$2['expectedRevision'], 9);
  });

  testWidgets('guest sees the Q&A without composer or vote controls', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcast.podcastWorkspace(
        repository(role: ServerMemberRole.guest),
        channelId: 'questions',
      ),
      size: const Size(390, 844),
    );
    expect(
      find.byKey(const ValueKey('server-podcast-question-composer')),
      findsNothing,
    );
    final vote = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('server-podcast-question-vote-question-1')),
    );
    expect(vote.onPressed, isNull);
  });

  testWidgets('Q&A fits a narrow phone at 200 percent text', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(
      tester,
      podcast.podcastWorkspace(
        repository(
          role: ServerMemberRole.moderator,
          questions: [
            question(
              body:
                  'Jak przygotowujecie długą rozmowę z gościem, który opowiada bardzo szeroko?',
              onAir: true,
            ),
          ],
        ),
        channelId: 'questions',
      ),
      size: const Size(320, 760),
      textScale: 2,
    );
    expect(
      find.byKey(const ValueKey('server-podcast-questions-board')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
