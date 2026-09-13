import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_question.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

ServerPodcastQuestion question() => ServerPodcastQuestion(
  id: 'question-7',
  serverId: 'server-1',
  channelId: 'questions-1',
  authorId: 'listener-1',
  authorName: 'Listener',
  body: 'What changed?',
  status: ServerPodcastQuestionStatus.queued,
  voteCount: 8,
  revision: 4,
  createdAt: DateTime.utc(2026, 9, 13),
  updatedAt: DateTime.utc(2026, 9, 13),
);

void main() {
  test('podcast Q&A mutations call the exact V1 contracts', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerService(
      call: (name, data) async {
        calls.add((name, data));
        return <Object?, Object?>{};
      },
    );
    final item = question();

    await service.createPodcastQuestion(
      serverId: 'server-1',
      channelId: 'questions-1',
      body: 'What changed?',
      requestId: 'request-create-1',
    );
    await service.setPodcastQuestionVote(
      question: item,
      voted: true,
      requestId: 'request-vote-1',
    );
    await service.setPodcastQuestionOnAir(
      question: item,
      onAir: true,
      requestId: 'request-air-1',
    );

    expect(calls.map((call) => call.$1), [
      'createServerPodcastQuestionV1',
      'setServerPodcastQuestionVoteV1',
      'setServerPodcastQuestionOnAirV1',
    ]);
    expect(calls[0].$2, {
      'serverId': 'server-1',
      'channelId': 'questions-1',
      'requestId': 'request-create-1',
      'body': 'What changed?',
    });
    expect(calls[1].$2, {
      'serverId': 'server-1',
      'channelId': 'questions-1',
      'questionId': 'question-7',
      'requestId': 'request-vote-1',
      'expectedRevision': 4,
      'voted': true,
    });
    expect(calls[2].$2, {
      'serverId': 'server-1',
      'channelId': 'questions-1',
      'questionId': 'question-7',
      'requestId': 'request-air-1',
      'expectedRevision': 4,
      'onAir': true,
    });
  });

  test(
    'podcast question parser enforces parent, aggregate and on-air shape',
    () async {
      final firestore = FakeFirebaseFirestore();
      final reference = firestore.doc(
        'clubs/server-1/channels/questions-1/questions/question-7',
      );
      final now = Timestamp.fromDate(DateTime.utc(2026, 9, 13));
      final data = <String, Object?>{
        'schemaVersion': 1,
        'serverId': 'server-1',
        'channelId': 'questions-1',
        'questionId': 'question-7',
        'questionKind': 'podcastQuestion',
        'authorId': 'listener-1',
        'authorName': 'Listener',
        'body': 'What changed?',
        'status': 'queued',
        'voteCount': 3,
        'revision': 2,
        'onAirAt': null,
        'onAirById': null,
        'createdAt': now,
        'updatedAt': now,
      };
      await reference.set(data);
      final parsed = ServerPodcastQuestion.fromFirestore(
        await reference.get(),
        serverId: 'server-1',
        channelId: 'questions-1',
      );
      expect(parsed.voteCount, 3);
      expect(parsed.isOnAir, false);

      await reference.set({...data, 'status': 'onAir'});
      final invalid = await reference.get();
      expect(
        () => ServerPodcastQuestion.fromFirestore(
          invalid,
          serverId: 'server-1',
          channelId: 'questions-1',
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
