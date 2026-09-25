import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

/// The Firestore half of the podcast host's "new listener questions" dot:
/// the newest-question read, the owner-private cursor and its forward-only
/// write (ADR "listener questions dot").
final _t0 = DateTime.utc(2026, 9, 25, 18);

Map<String, Object?> _question(
  String id, {
  required int minute,
  String author = 'listener-1',
}) {
  final at = Timestamp.fromDate(_t0.add(Duration(minutes: minute)));
  return {
    'schemaVersion': 1,
    'serverId': 'srv_1',
    'channelId': 'ch_q',
    'questionId': id,
    'questionKind': 'podcastQuestion',
    'authorId': author,
    'authorName': 'Ola',
    'body': 'Pytanie',
    'status': 'queued',
    'voteCount': 0,
    'revision': 1,
    'onAirAt': null,
    'onAirById': null,
    'createdAt': at,
    'updatedAt': at,
  };
}

void main() {
  late FakeFirebaseFirestore firestore;
  late ServerService service;
  late List<bool> values;

  CollectionReference<Map<String, dynamic>> questions() =>
      firestore.collection('clubs/srv_1/channels/ch_q/questions');
  DocumentReference<Map<String, dynamic>> cursor() =>
      firestore.doc('users/host/serverQuestionSeen/srv_1_ch_q');

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = ServerService(
      firestore: firestore,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'host'),
      ),
    );
    values = <bool>[];
  });

  Future<void> listen() async {
    final subscription = service
        .watchPodcastQuestionsUnseen('srv_1', 'ch_q')
        .listen(values.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
  }

  test('newest question against the cursor, end to end', () async {
    await listen();
    expect(values.last, isFalse, reason: 'no questions yet');

    await questions().doc('q1').set(_question('q1', minute: 1));
    await pumpEventQueue();
    expect(values.last, isTrue, reason: 'no cursor yet');

    await service.markPodcastQuestionsSeen(
      serverId: 'srv_1',
      channelId: 'ch_q',
      newestCreatedAt: _t0.add(const Duration(minutes: 1)),
    );
    await pumpEventQueue();
    expect(values.last, isFalse);
    expect(
      ((await cursor().get()).data()!['seenAt'] as Timestamp).toDate().toUtc(),
      _t0.add(const Duration(minutes: 1)),
    );
    expect((await cursor().get()).data()!.keys, ['seenAt']);

    await questions().doc('q2').set(_question('q2', minute: 5));
    await pumpEventQueue();
    expect(values.last, isTrue);

    // Deliberately updated (podcast-host fix round): the host's own question
    // is not news to the host, but it must not hide the listener's question
    // (q2) asked before it, which the host has not seen yet. This step used
    // to expect false, which was exactly that loss.
    await questions().doc('q3').set(_question('q3', minute: 9, author: 'host'));
    await pumpEventQueue();
    expect(values.last, isTrue);

    // Once the host has looked, their own newer question lights nothing.
    await service.markPodcastQuestionsSeen(
      serverId: 'srv_1',
      channelId: 'ch_q',
      newestCreatedAt: _t0.add(const Duration(minutes: 9)),
    );
    await pumpEventQueue();
    expect(values.last, isFalse);
    await questions().doc('q4').set(_question('q4', minute: 12, author: 'host'));
    await pumpEventQueue();
    expect(values.last, isFalse);
  });

  test('a listener question at T1, the host\'s own at T2 and a cursor before '
      'T1 still shows the dot', () async {
    await cursor().set({'seenAt': Timestamp.fromDate(_t0)});
    await questions().doc('q1').set(_question('q1', minute: 1));
    await questions().doc('q2').set(_question('q2', minute: 2, author: 'host'));
    await listen();
    expect(values.last, isTrue);
  });

  test('only the host\'s own questions light nothing', () async {
    await questions().doc('q1').set(_question('q1', minute: 1, author: 'host'));
    await questions().doc('q2').set(_question('q2', minute: 2, author: 'host'));
    await listen();
    expect(values, [false]);
  });

  test('the cursor only ever moves forward', () async {
    await listen();
    await service.markPodcastQuestionsSeen(
      serverId: 'srv_1',
      channelId: 'ch_q',
      newestCreatedAt: _t0.add(const Duration(minutes: 5)),
    );
    await service.markPodcastQuestionsSeen(
      serverId: 'srv_1',
      channelId: 'ch_q',
      newestCreatedAt: _t0.add(const Duration(minutes: 2)),
    );
    expect(
      ((await cursor().get()).data()!['seenAt'] as Timestamp).toDate().toUtc(),
      _t0.add(const Duration(minutes: 5)),
    );
  });

  test('a cursor another device wrote is respected', () async {
    await cursor().set({
      'seenAt': Timestamp.fromDate(_t0.add(const Duration(minutes: 10))),
    });
    await questions().doc('q1').set(_question('q1', minute: 3));
    await listen();
    expect(values.last, isFalse);
    // Knowing the cursor, a stale mark from this device writes nothing.
    await service.markPodcastQuestionsSeen(
      serverId: 'srv_1',
      channelId: 'ch_q',
      newestCreatedAt: _t0.add(const Duration(minutes: 3)),
    );
    expect(
      ((await cursor().get()).data()!['seenAt'] as Timestamp).toDate().toUtc(),
      _t0.add(const Duration(minutes: 10)),
    );
  });

  test('a newest document that does not parse never holds a dot on', () async {
    await questions().doc('bad').set({
      ..._question('bad', minute: 4),
      'questionKind': 'somethingElse',
    });
    await listen();
    expect(values, [false]);
  });

  test('ids the rules would refuse read and write nothing', () async {
    expect(
      await service.watchPodcastQuestionsUnseen('srv.1', 'ch_q').first,
      isFalse,
    );
    await service.markPodcastQuestionsSeen(
      serverId: 'srv.1',
      channelId: 'ch_q',
      newestCreatedAt: _t0,
    );
    expect(
      (await firestore.collection('users/host/serverQuestionSeen').get()).docs,
      isEmpty,
    );
  });

  group('a failed read', () {
    late List<StreamController<ServerNewestQuestion>> newest;
    late List<StreamController<DateTime?>> cursors;
    late List<bool> dot;
    late StreamSubscription<bool> subscription;

    setUp(() {
      newest = [];
      cursors = [];
      dot = [];
      subscription =
          serverLatestQuestionUnseen(
            newest: () {
              final controller = StreamController<ServerNewestQuestion>();
              newest.add(controller);
              return controller.stream;
            },
            cursor: () {
              final controller = StreamController<DateTime?>();
              cursors.add(controller);
              return controller.stream;
            },
            viewerId: 'host',
            retryDelay: const Duration(milliseconds: 10),
            maxRetryDelay: const Duration(milliseconds: 40),
          ).listen(dot.add);
    });

    tearDown(() => subscription.cancel());

    Future<void> answer(int index, {required int minute}) async {
      newest[index].add((
        createdAt: _t0.add(Duration(minutes: minute)),
        authorId: 'listener-1',
      ));
      cursors[index].add(_t0);
      await pumpEventQueue();
    }

    test('that is transient goes quiet, then reopens both reads', () async {
      await pumpEventQueue();
      await answer(0, minute: 3);
      expect(dot, [true]);
      newest[0].addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      await pumpEventQueue();
      expect(dot, [true, false]);
      expect(newest[0].hasListener, isFalse);
      expect(cursors[0].hasListener, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(newest, hasLength(2));
      expect(cursors, hasLength(2));
      await answer(1, minute: 3);
      expect(dot, [true, false, true]);
    });

    test('that is a denial stays off and reads nothing more', () async {
      await pumpEventQueue();
      await answer(0, minute: 3);
      cursors[0].addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(dot, [true, false]);
      expect(newest, hasLength(1));
      expect(cursors, hasLength(1));
    });

    test('backs off up to the ceiling and stops when nobody listens', () async {
      await pumpEventQueue();
      for (var attempt = 0; attempt < 3; attempt++) {
        newest.last.addError(StateError('offline'));
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(newest, hasLength(4));
      await subscription.cancel();
      newest.last.addError(StateError('offline'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(newest, hasLength(4));
    });
  });
}
