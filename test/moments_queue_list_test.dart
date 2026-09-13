// "KOLEJNE MOMENTY" — a navigation list, never a transport queue.
//
// It lists neighbours the feed has ALREADY loaded for this account, it
// never auto-advances, it releases the player before it opens anything, and
// it drops an item the moment that item expires.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'moment_listen_test_support.dart';

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: listenViewerUid),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<List<VoiceMoment>> pumpList(
    WidgetTester tester, {
    required List<VoiceMoment> upcoming,
    double progress = 0.4,
  }) async {
    final opened = <VoiceMoment>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: SingleChildScrollView(
              child: MomentsQueueList(
                current: listenMoment(
                  'm1',
                  caption: 'Before the city wakes up',
                ),
                upcoming: upcoming,
                progress: ValueNotifier<double>(progress),
                onOpen: opened.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('with nothing loaded after this Moment the section is absent', (
    tester,
  ) async {
    await pumpList(tester, upcoming: const <VoiceMoment>[]);

    expect(find.byKey(const ValueKey('moments-queue-list')), findsNothing);
    expect(find.text('NEXT MOMENTS'), findsNothing);
  });

  testWidgets('it lists real neighbours with their author and real length, '
      'capped at six', (tester) async {
    await pumpList(
      tester,
      upcoming: <VoiceMoment>[
        for (var index = 0; index < 9; index++)
          listenMoment(
            'n$index',
            caption: 'Neighbour $index',
            authorName: 'Kuba',
            durationSeconds: 38,
          ),
      ],
    );

    expect(find.text('NEXT MOMENTS'), findsOneWidget);
    expect(find.text('Neighbour 0'), findsOneWidget);
    expect(find.text('Neighbour 5'), findsOneWidget);
    expect(find.text('Neighbour 6'), findsNothing);
    expect(find.text('Kuba · 0:38'), findsWidgets);
    // The board's "1:02" cannot occur: the cap is 60 seconds.
    expect(find.textContaining('1:02'), findsNothing);
  });

  testWidgets('the Moment being listened to is the selected row and the only '
      'one with progress', (tester) async {
    await pumpList(
      tester,
      upcoming: <VoiceMoment>[listenMoment('n1', caption: 'Neighbour')],
      progress: 0.4,
    );

    expect(find.text('Before the city wakes up'), findsOneWidget);
    expect(find.byType(MomentsQueueList), findsOneWidget);
    // One ring: the active row's.
    expect(find.byType(CustomPaint, skipOffstage: false), findsWidgets);
    expect(find.byKey(const ValueKey('moments-queue-item-n1')), findsOneWidget);
    // The active row is not a button — you are already there.
    expect(find.byKey(const ValueKey('moments-queue-item-m1')), findsNothing);
  });

  testWidgets('selecting a neighbour hands off rather than autoplaying', (
    tester,
  ) async {
    final opened = await pumpList(
      tester,
      upcoming: <VoiceMoment>[listenMoment('n1', caption: 'Neighbour')],
    );

    await tester.tap(find.byKey(const ValueKey('moments-queue-item-n1')));
    await tester.pump();

    expect(opened.single.id, 'n1');
  });

  group('inside the expanded player', () {
    testWidgets('the widest layout offers the loaded neighbours; the narrower '
        'ones do not', (tester) async {
      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        neighbours: <VoiceMoment>[listenMoment('n1', caption: 'Neighbour')],
        size: const Size(1250, 900),
      );
      expect(find.byKey(const ValueKey('moments-queue-list')), findsOneWidget);
      expect(find.text('Neighbour'), findsOneWidget);

      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        neighbours: <VoiceMoment>[listenMoment('n1', caption: 'Neighbour')],
        size: const Size(1150, 900),
      );
      expect(find.byKey(const ValueKey('moments-queue-list')), findsNothing);
    });

    testWidgets('an expired neighbour is never offered', (tester) async {
      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        neighbours: <VoiceMoment>[
          listenMoment('n1', caption: 'Still here'),
          listenMoment(
            'n2',
            caption: 'Already gone',
            age: const Duration(hours: 30),
            lifetime: const Duration(hours: 24),
          ),
        ],
        size: const Size(1250, 900),
      );

      expect(find.text('Still here'), findsOneWidget);
      expect(find.text('Already gone'), findsNothing);
    });

    testWidgets('a pool published for another account is ignored', (
      tester,
    ) async {
      final queue = MomentNeighbourQueue();
      addTearDown(queue.dispose);
      queue.publish(
        viewerUid: 'someone-else',
        moments: <VoiceMoment>[listenMoment('n1', caption: 'Not yours')],
      );

      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        queue: queue,
        size: const Size(1250, 900),
      );

      expect(find.byKey(const ValueKey('moments-queue-list')), findsNothing);
      expect(find.text('Not yours'), findsNothing);
    });

    testWidgets('the pool the feed publishes for THIS account is offered, and '
        'a later publication updates it', (tester) async {
      final queue = MomentNeighbourQueue();
      addTearDown(queue.dispose);
      queue.publish(
        viewerUid: listenViewerUid,
        moments: <VoiceMoment>[
          listenMoment('m1'),
          listenMoment('n1', caption: 'Neighbour one'),
        ],
      );

      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        queue: queue,
        size: const Size(1250, 900),
      );
      expect(find.text('Neighbour one'), findsOneWidget);

      // The feed pruned it (deleted, blocked, expired): the offer goes too.
      queue.publish(
        viewerUid: listenViewerUid,
        moments: <VoiceMoment>[listenMoment('m1')],
      );
      await tester.pump();

      expect(find.text('Neighbour one'), findsNothing);
      expect(find.byKey(const ValueKey('moments-queue-list')), findsNothing);
    });

    testWidgets('selecting a neighbour releases the player first and waits '
        'for a deliberate play', (tester) async {
      final neighbour = listenMoment('n1', caption: 'Neighbour');
      final harness = await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        neighbours: <VoiceMoment>[neighbour],
        // The neighbour is a real, readable Moment: opening it reads its
        // own view exactly as arriving from the feed would.
        seed: (db) => db
            .collection('voiceMoments')
            .doc(neighbour.id)
            .set(listenMomentDoc(neighbour)),
        size: const Size(1250, 900),
      );

      await playTo(tester, harness, const Duration(seconds: 10));
      expect(harness.player.playCalls, 1);

      await tester.tap(find.byKey(const ValueKey('moments-queue-item-n1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(harness.player.stopCalls, 1);
      expect(
        harness.player.playCalls,
        1,
        reason: 'the Moment that opens waits for a deliberate play',
      );
      expect(find.text('0%'), findsOneWidget);
    });
  });
}
