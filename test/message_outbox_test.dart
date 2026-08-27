import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/services/message_outbox.dart';

/// The outbox is what stands between "the callable is unavailable" and
/// "the message is gone".
///
/// Before ADR-082 that gap was filled by writing the message straight to
/// Firestore, which skipped every server-side moderation check at once. The
/// rules refuse a client-authored message now, so these guarantees — queued,
/// bounded, retried under a stable id, and never silently dropped — are the
/// only thing keeping a failed send recoverable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<MessageOutbox> outboxWith({
    int capacity = 50,
    int maxAttempts = 6,
    DateTime Function()? clock,
    Duration baseBackoff = Duration.zero,
    Duration maxBackoff = Duration.zero,
  }) async {
    final outbox = MessageOutbox(
      preferences: await SharedPreferences.getInstance(),
      capacity: capacity,
      maxAttempts: maxAttempts,
      clock: clock,
      baseBackoff: baseBackoff,
      maxBackoff: maxBackoff,
    );
    await outbox.load();
    return outbox;
  }

  Future<OutboxEntry> enqueueOne(MessageOutbox outbox, String text) => outbox
      .enqueue(conversationId: 'c1', recipientId: 'recipient-uid', text: text);

  group('persistence', () {
    test('concurrent first callers share one load barrier', () async {
      final first = await outboxWith();
      await enqueueOne(first, 'restored first');

      final reopened = MessageOutbox(
        preferences: await SharedPreferences.getInstance(),
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final loadA = reopened.load();
      final loadB = reopened.load();
      expect(identical(loadA, loadB), isTrue);

      await Future.wait<Object?>([
        loadA,
        reopened.enqueue(
          conversationId: 'c1',
          recipientId: 'recipient-uid',
          text: 'queued during load',
        ),
      ]);

      expect(reopened.entries.map((entry) => entry.text), [
        'restored first',
        'queued during load',
      ]);
    });

    test('live queues are shared per owner and never across owners', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        MessageOutbox.legacyStorageKey,
        jsonEncode([
          {
            'id': 'legacy-id',
            'requestId': 'legacy-request',
            'conversationId': 'private-chat',
            'recipientId': 'private-recipient',
            'text': 'must not be guessed into an account',
            'state': 'pending',
            'attempts': 0,
            'queuedAt': DateTime.utc(2026, 8, 27).toIso8601String(),
          },
        ]),
      );

      final ownerA = MessageOutbox.sharedForUser('outbox-owner-a-test');
      final sameOwnerA = MessageOutbox.sharedForUser('outbox-owner-a-test');
      final ownerB = MessageOutbox.sharedForUser('outbox-owner-b-test');
      expect(identical(ownerA, sameOwnerA), isTrue);
      expect(identical(ownerA, ownerB), isFalse);
      expect(ownerA.ownerId, 'outbox-owner-a-test');
      expect(ownerB.ownerId, 'outbox-owner-b-test');

      await Future.wait([ownerA.load(), ownerB.load()]);
      expect(ownerA.entries, isEmpty);
      expect(ownerB.entries, isEmpty);
      expect(
        prefs.getString(MessageOutbox.legacyStorageKey),
        isNull,
        reason: 'an ownerless legacy draft must not leak on account switch',
      );

      await ownerA.enqueue(
        conversationId: 'private-chat',
        recipientId: 'recipient-a',
        text: 'only A may see this',
      );
      expect(ownerA.entries, hasLength(1));
      expect(ownerB.entries, isEmpty);
      await ownerA.clear();
      await ownerB.clear();
    });

    test('a queued message survives a restart, with its requestId', () async {
      final first = await outboxWith();
      final queued = await enqueueOne(first, 'survive me');

      // A second instance stands in for the next app launch.
      final reopened = await outboxWith();

      expect(reopened.entries, hasLength(1));
      final restored = reopened.entries.single;
      expect(restored.text, 'survive me');
      expect(restored.id, queued.id);
      expect(
        restored.requestId,
        queued.requestId,
        reason:
            'a restart that changed the requestId would turn the next '
            'retry of an already-committed send into a duplicate message',
      );
    });

    test('a failed message survives a restart too — it is not quietly '
        'dropped on the way', () async {
      final first = await outboxWith(maxAttempts: 1);
      final queued = await enqueueOne(first, 'failed but kept');
      await first.markRetry(queued.id, 'nope');
      expect(first.failed, hasLength(1));

      final reopened = await outboxWith(maxAttempts: 1);
      expect(reopened.failed, hasLength(1));
      expect(reopened.failed.single.text, 'failed but kept');
      expect(reopened.failed.single.lastError, 'nope');
    });

    test(
      'one unreadable entry does not strand the rest of the queue',
      () async {
        final real = await outboxWith();
        final good = await enqueueOne(real, 'readable');

        // Splice a malformed record in beside a good one, the way a future
        // schema change or a partial write could.
        final prefs = await SharedPreferences.getInstance();
        final stored =
            jsonDecode(prefs.getString('messages.outbox.v1')!) as List;
        stored.insert(0, <String, Object?>{'id': 'broken'});
        await prefs.setString('messages.outbox.v1', jsonEncode(stored));

        final reopened = await outboxWith();
        expect(reopened.entries, hasLength(1));
        expect(reopened.entries.single.id, good.id);
      },
    );

    test('a corrupt queue is dropped rather than thrown — it is a cache of '
        'unsent work, not a source of truth', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('messages.outbox.v1', 'not json at all');

      final outbox = await outboxWith();
      expect(outbox.entries, isEmpty);
      await expectLater(enqueueOne(outbox, 'still works'), completes);
    });
  });

  group('states', () {
    test('a new message is Pending', () async {
      final outbox = await outboxWith();
      final entry = await enqueueOne(outbox, 'fresh');
      expect(entry.state, OutboxState.pending);
      expect(entry.attempts, 0);
      expect(entry.isTerminal, isFalse);
    });

    test(
      'a transient failure moves it to Retrying and counts the attempt',
      () async {
        final outbox = await outboxWith();
        final entry = await enqueueOne(outbox, 'transient');
        final retried = await outbox.markRetry(entry.id, 'network down');

        expect(retried!.state, OutboxState.retrying);
        expect(retried.attempts, 1);
        expect(retried.lastError, 'network down');
        expect(retried.isTerminal, isFalse);
      },
    );

    test('the retry budget is bounded — it becomes Failed rather than '
        'retrying forever', () async {
      final outbox = await outboxWith(maxAttempts: 3);
      final entry = await enqueueOne(outbox, 'doomed');

      await outbox.markRetry(entry.id, 'one');
      await outbox.markRetry(entry.id, 'two');
      final third = await outbox.markRetry(entry.id, 'three');

      expect(third!.state, OutboxState.failed);
      expect(third.attempts, 3);
      expect(third.isTerminal, isTrue);
      expect(
        outbox.due(),
        isEmpty,
        reason:
            'a terminal entry is never picked up by the automatic loop '
            'again; an endless retry is a battery and quota drain',
      );
    });

    test(
      'a refusal fails immediately, without spending the retry budget',
      () async {
        final outbox = await outboxWith();
        final entry = await enqueueOne(outbox, 'refused');
        final failed = await outbox.markFailed(entry.id, 'You are blocked.');

        expect(failed!.state, OutboxState.failed);
        expect(
          failed.attempts,
          0,
          reason: 'a refusal repeated on a timer is just a slower refusal',
        );
        expect(failed.lastError, 'You are blocked.');
      },
    );

    test(
      'a manual retry resets the attempts but KEEPS the requestId',
      () async {
        final outbox = await outboxWith(maxAttempts: 1);
        final entry = await enqueueOne(outbox, 'by hand');
        await outbox.markRetry(entry.id, 'gave up');
        expect(outbox.failed, hasLength(1));

        final revived = await outbox.retryNow(entry.id);
        expect(revived!.state, OutboxState.pending);
        expect(revived.attempts, 0);
        expect(revived.nextAttemptAt, isNull);
        expect(
          revived.requestId,
          entry.requestId,
          reason:
              'a manual retry of a send that secretly succeeded must still '
              'be deduplicated by the server ledger',
        );
      },
    );

    test('a delivered message leaves the queue', () async {
      final outbox = await outboxWith();
      final entry = await enqueueOne(outbox, 'done');
      await outbox.markSent(entry.id);
      expect(outbox.entries, isEmpty);
    });
  });

  group('bounded', () {
    test('it refuses past capacity instead of growing without limit', () async {
      final outbox = await outboxWith(capacity: 3);
      for (final text in ['a', 'b', 'c']) {
        await enqueueOne(outbox, text);
      }

      await expectLater(
        enqueueOne(outbox, 'd'),
        throwsA(isA<OutboxFullException>()),
      );
      expect(outbox.entries, hasLength(3));
    });

    test('a failed entry is evicted to make room, so old failures never '
        'block a fresh send', () async {
      final outbox = await outboxWith(capacity: 2, maxAttempts: 1);
      final doomed = await enqueueOne(outbox, 'old failure');
      await outbox.markRetry(doomed.id, 'gone');
      expect(outbox.failed, hasLength(1));
      await enqueueOne(outbox, 'still pending');

      final fresh = await enqueueOne(outbox, 'new send');

      expect(outbox.entries, hasLength(2));
      expect(
        outbox.entries.map((entry) => entry.text),
        ['still pending', 'new send'],
        reason: 'the FAILED entry is the one evicted, never an unsent one',
      );
      expect(fresh.state, OutboxState.pending);
    });

    test(
      'a queue full of unsent messages is never silently discarded',
      () async {
        final outbox = await outboxWith(capacity: 2);
        await enqueueOne(outbox, 'one');
        await enqueueOne(outbox, 'two');

        await expectLater(
          enqueueOne(outbox, 'three'),
          throwsA(isA<OutboxFullException>()),
        );
        expect(
          outbox.unsent.map((entry) => entry.text),
          ['one', 'two'],
          reason:
              'evicting an unsent message to make room would lose exactly '
              'what this queue exists to protect',
        );
      },
    );
  });

  group('ordering', () {
    test('due() returns messages oldest first', () async {
      final outbox = await outboxWith();
      for (final text in ['first', 'second', 'third']) {
        await enqueueOne(outbox, text);
      }
      expect(outbox.due().map((entry) => entry.text), [
        'first',
        'second',
        'third',
      ]);
    });

    test('a terminal entry is skipped while the rest stay due', () async {
      final outbox = await outboxWith(maxAttempts: 1);
      final first = await enqueueOne(outbox, 'first');
      await enqueueOne(outbox, 'second');
      await outbox.markRetry(first.id, 'dead');

      expect(outbox.due().map((entry) => entry.text), ['second']);
    });

    test(
      'backoff blocks overtaking only inside the same conversation',
      () async {
        final now = DateTime.utc(2026, 8, 27, 12);
        final outbox = await outboxWith(
          clock: () => now,
          baseBackoff: const Duration(seconds: 30),
          maxBackoff: const Duration(seconds: 30),
        );
        final first = await enqueueOne(outbox, 'first');
        await outbox.markRetry(first.id, 'offline');
        await enqueueOne(outbox, 'second');
        await outbox.enqueue(
          conversationId: 'another-chat',
          recipientId: 'another-recipient',
          text: 'independent',
        );

        expect(
          outbox.due().map((entry) => entry.text),
          ['independent'],
          reason: 'second must wait behind first, while another chat may drain',
        );
      },
    );
  });

  test('changes emits the queue so a chat view can show what has not gone '
      'out yet', () async {
    final outbox = await outboxWith();
    final seen = <int>[];
    final subscription = outbox.changes.listen((entries) {
      seen.add(entries.length);
    });

    final entry = await enqueueOne(outbox, 'watch me');
    await outbox.markRetry(entry.id, 'later');
    await outbox.markSent(entry.id);
    await Future<void>.delayed(Duration.zero);

    expect(seen, [1, 1, 0]);
    await subscription.cancel();
    await outbox.dispose();
  });

  test(
    'delivered bridges a server success, but discard does not fake one',
    () async {
      final outbox = await outboxWith();
      final delivered = <String>[];
      final subscription = outbox.delivered.listen(
        (entry) => delivered.add(entry.id),
      );
      final sent = await enqueueOne(outbox, 'sent');
      final removed = await enqueueOne(outbox, 'discarded');

      await outbox.markSent(sent.id);
      await outbox.discard(removed.id);
      await Future<void>.delayed(Duration.zero);

      expect(delivered, [sent.id]);
      expect(outbox.entries, isEmpty);
      await subscription.cancel();
      await outbox.dispose();
    },
  );
}
