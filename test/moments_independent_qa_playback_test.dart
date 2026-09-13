// Independent QA — the Voice Moments playback contract (boards 06/07).
//
// Written by the Senior QA Automation Engineer, from the architecture
// contract rather than from the implementation: every assertion below states
// what the product promises (§2 playback engine, §2.3 the arbiter, §2.6 the
// binding queue rule) and then asks the real widgets whether they keep it.
//
// Nothing here is a mock of the thing under test: the expanded player is the
// real `MomentDetailScreen` over the real `MomentService` reading a fake
// Firestore, the grants come through the real `resolveMediaUri` seam, and the
// only stand-in is the audio device itself.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';

import 'moment_listen_test_support.dart';
import 'voice_moment_test_doubles.dart';

const _playKey = ValueKey<String>('moment-detail-play');
const _micKey = ValueKey<String>('moment-detail-composer-mic');
const _seeAllKey = ValueKey<String>('moment-comment-preview-see-all');

/// A media-grant seam that can be held open, so the window between "the
/// arbiter granted the floor" and "the bytes arrived" is a real, controllable
/// interval instead of an invisible one.
class _GatedGrants {
  final List<String> requests = <String>[];
  Completer<void>? gate;

  /// Which requests the gate holds. Defaults to the recording's own grant,
  /// so a reply's grant can still resolve while the recording's is pending.
  bool Function(Map<String, Object?> request) hold = (request) =>
      request['commentId'] == null;

  MomentMediaAccessInvoker get invoker => (request) async {
    requests.add(
      '${request['momentId']}'
      '${request['commentId'] == null ? '' : '/${request['commentId']}'}',
    );
    final open = gate;
    if (open != null && hold(request)) await open.future;
    return <Object?, Object?>{
      'schemaVersion': 1,
      'url':
          'https://storage.googleapis.com/yovoice-test/'
          '${request['momentId']}.m4a?X-Goog-Signature=qa',
      'expiresAtMillis': DateTime.now()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
      'mediaGeneration': '1001',
      'mediaContentType': 'audio/mp4',
      'mediaSize': 4096,
    };
  };
}

class _QaHarness {
  _QaHarness({
    required this.db,
    required this.moments,
    required this.players,
    required this.grants,
    required this.navigatorKey,
    required this.queue,
  });

  final FakeFirebaseFirestore db;
  final MomentService moments;
  final List<FakePreviewAudioPlayer> players;
  final _GatedGrants grants;
  final GlobalKey<NavigatorState> navigatorKey;
  final MomentNeighbourQueue queue;

  FakePreviewAudioPlayer get main => players.first;
}

/// Pumps the expanded player as the pushed route production uses, with every
/// asynchronous seam under the test's control.
Future<_QaHarness> _pumpDetail(
  WidgetTester tester, {
  required VoiceMoment moment,
  Size size = const Size(390, 844),
  List<VoiceMoment>? neighbours,
  Future<void> Function(FakeFirebaseFirestore db)? seed,
  Duration playerDuration = const Duration(seconds: 45),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = FakeFirebaseFirestore();
  await db
      .collection('voiceMoments')
      .doc(moment.id)
      .set(listenMomentDoc(moment));
  for (final neighbour in neighbours ?? const <VoiceMoment>[]) {
    await db
        .collection('voiceMoments')
        .doc(neighbour.id)
        .set(listenMomentDoc(neighbour));
  }
  if (seed != null) await seed(db);

  final auth = listenAuth();
  final grants = _GatedGrants();
  final moments = MomentService(
    firestore: db,
    auth: auth,
    storage: MockFirebaseStorage(),
    readService: VoiceMomentReadService(
      viewInvoker: fakeVoiceMomentViewInvoker(
        firestore: db,
        viewerUid: listenViewerUid,
      ),
    ),
    mediaAccessInvoker: grants.invoker,
  );
  // The grant cache is process-wide and static: a Moment id played by an
  // earlier case must never satisfy this one.
  MomentService.clearAllMediaAccessCaches();
  addTearDown(MomentService.clearAllMediaAccessCaches);

  final players = <FakePreviewAudioPlayer>[];
  final navigatorKey = GlobalKey<NavigatorState>();
  final queue = MomentNeighbourQueue();

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: Center(child: Text('FEED'))),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentDetailScreen(
          moment: moment,
          momentService: moments,
          feedService: HomeFeedService(firestore: db, auth: auth),
          auth: auth,
          neighbours: neighbours,
          neighbourQueue: queue,
          playerFactory: () {
            final player = FakePreviewAudioPlayer(duration: playerDuration);
            players.add(player);
            return player;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return _QaHarness(
    db: db,
    moments: moments,
    players: players,
    grants: grants,
    navigatorKey: navigatorKey,
    queue: queue,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// The expanded player scrolls in a lazy `ListView`, so the thread is only
/// built once it is reachable. Every thread assertion below scrolls to it
/// the way a reader would.
Future<void> _revealThread(WidgetTester tester, Finder target) async {
  if (tester.any(target)) {
    await tester.ensureVisible(target);
    await tester.pump();
    return;
  }
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('moment-detail-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

void main() {
  group('reply playback arbitration', () {
    testWidgets(
      'the recording pauses before a reply sounds, and restarting the '
      'recording stops that reply',
      (tester) async {
        final moment = listenMoment('m-arb', comments: 1);
        final harness = await _pumpDetail(
          tester,
          moment: moment,
          size: const Size(900, 1000),
          seed: (db) =>
              seedListenComment(db, momentId: 'm-arb', id: 'c1', voice: true),
        );

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        expect(
          harness.main.playCalls,
          1,
          reason: 'the main recording must be the first thing that sounds',
        );

        final replyFinder = find.byKey(
          const ValueKey<String>('voice-reply-mini-player-c1'),
        );
        await _revealThread(tester, replyFinder);
        expect(replyFinder, findsOneWidget);
        await tester.tap(replyFinder);
        await _settle(tester);

        expect(
          harness.main.pauseCalls,
          1,
          reason:
              'architecture §2.3: a reply never plays over the recording it '
              'answers — the main transport is paused first',
        );
        expect(harness.players.length, 2, reason: 'one main + one reply');
        final reply = harness.players[1];
        expect(reply.playCalls, 1);

        // The recording takes the floor back.
        await tester.ensureVisible(find.byKey(_playKey));
        await tester.pump();
        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        expect(
          reply.pauseCalls,
          1,
          reason: 'the main recording starting stops whichever reply sounded',
        );
      },
    );

    testWidgets(
      'a reply that lost the floor while its grant was still in flight '
      'never sounds',
      (tester) async {
        // Two voice replies, one arbiter, one grant held open. This is the
        // window the arbiter exists to close: the code comment in
        // voice_reply_mini_player.dart claims "two sources never overlap even
        // for the length of a round trip".
        final arbiter = ReplyPlaybackArbiter();
        addTearDown(arbiter.dispose);
        final slow = Completer<Uri>();
        final players = <String, FakePreviewAudioPlayer>{};

        FakePreviewAudioPlayer playerFor(String id) =>
            players.putIfAbsent(id, FakePreviewAudioPlayer.new);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  VoiceReplyMiniPlayer(
                    commentId: 'slow',
                    authorName: 'Ola',
                    durationSeconds: 12,
                    arbiter: arbiter,
                    resolveMediaUri: () => slow.future,
                    playerFactory: () => playerFor('slow'),
                  ),
                  VoiceReplyMiniPlayer(
                    commentId: 'fast',
                    authorName: 'Kuba',
                    durationSeconds: 9,
                    arbiter: arbiter,
                    resolveMediaUri: () async =>
                        Uri.parse('https://cdn.example/fast.m4a'),
                    playerFactory: () => playerFor('fast'),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('voice-reply-mini-player-slow')),
        );
        await tester.pump();
        expect(arbiter.activeReplyId, 'slow');

        await tester.tap(
          find.byKey(const ValueKey<String>('voice-reply-mini-player-fast')),
        );
        await _settle(tester);
        expect(arbiter.activeReplyId, 'fast');
        expect(playerFor('fast').playCalls, 1);

        // The first reply's grant lands AFTER it lost the floor.
        slow.complete(Uri.parse('https://cdn.example/slow.m4a'));
        await _settle(tester);

        expect(
          playerFor('slow').playCalls,
          0,
          reason:
              'the reply that lost the floor must not start when its grant '
              'arrives — two replies would sound at once',
        );
      },
    );

    testWidgets(
      'the recording that lost the floor while its grant was in flight '
      'never sounds over the reply',
      (tester) async {
        final moment = listenMoment('m-race', comments: 1);
        final harness = await _pumpDetail(
          tester,
          moment: moment,
          size: const Size(900, 1000),
          seed: (db) =>
              seedListenComment(db, momentId: 'm-race', id: 'c1', voice: true),
        );

        // Hold the main recording's grant open, then let a reply take over.
        harness.grants.gate = Completer<void>();
        await tester.tap(find.byKey(_playKey));
        await tester.pump();
        expect(harness.grants.requests, <String>['m-race']);

        final replyFinder = find.byKey(
          const ValueKey<String>('voice-reply-mini-player-c1'),
        );
        await _revealThread(tester, replyFinder);
        await tester.tap(replyFinder);
        await _settle(tester);
        final reply = harness.players[1];
        expect(reply.playCalls, 1, reason: 'the reply now holds the floor');

        harness.grants.gate!.complete();
        await _settle(tester);

        expect(
          harness.main.playCalls,
          0,
          reason:
              'architecture §2.3: the recording must not start once a reply '
              'holds the floor — the grant round trip is not a licence',
        );
      },
    );

    testWidgets(
      'opening the full thread does not leave the recording sounding under '
      'a pushed route',
      (tester) async {
        final moment = listenMoment('m-thread', comments: 1);
        final harness = await _pumpDetail(
          tester,
          moment: moment,
          size: const Size(900, 1000),
          seed: (db) => seedListenComment(db, momentId: 'm-thread', id: 'c1'),
        );

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        expect(harness.main.playCalls, 1);

        final seeAll = find.byKey(_seeAllKey);
        await _revealThread(tester, seeAll);
        expect(
          seeAll,
          findsOneWidget,
          reason: 'the full thread is one tap from the expanded player',
        );
        await tester.tap(seeAll);
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          harness.main.pauseCalls + harness.main.stopCalls,
          greaterThan(0),
          reason:
              'every other Moments surface stops audio when a route is '
              'pushed over it (moments_feed_view didPushNext); the full '
              'thread page owns its own un-hosted arbiter, so a recording '
              'left running there can be played over by a voice reply',
        );
      },
    );
  });

  group('one transport, one position', () {
    testWidgets(
      'pausing and playing again resumes the retained position and mints no '
      'second grant',
      (tester) async {
        final moment = listenMoment('m-resume');
        final harness = await _pumpDetail(tester, moment: moment);

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        harness.main.emitPosition(const Duration(seconds: 20));
        await tester.pump();
        expect(find.text('0:20'), findsOneWidget);

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        expect(harness.main.pauseCalls, 1);
        expect(
          find.text('0:20'),
          findsOneWidget,
          reason: 'a pause keeps the position it paused at',
        );

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);

        expect(
          harness.main.resumeCalls,
          1,
          reason: 'resuming continues the loaded source',
        );
        expect(
          harness.main.playCalls,
          1,
          reason: 'no second source load, so no restart from zero',
        );
        expect(
          harness.grants.requests,
          <String>['m-resume'],
          reason:
              'a resume must not mint a second short-lived media grant '
              '(privacy §6: a grant nobody needs is a leaked capability)',
        );
        expect(find.text('0:20'), findsOneWidget);
      },
    );

    testWidgets(
      'opening the expanded player starts no audio, allocates no transport '
      'and mints no grant',
      (tester) async {
        final moment = listenMoment('m-quiet', comments: 2);
        final harness = await _pumpDetail(
          tester,
          moment: moment,
          seed: (db) async {
            await seedListenComment(
              db,
              momentId: 'm-quiet',
              id: 'c1',
              voice: true,
            );
            await seedListenComment(
              db,
              momentId: 'm-quiet',
              id: 'c2',
              voice: true,
              minutesAgo: 10,
            );
          },
        );

        expect(
          find.byKey(const ValueKey<String>('moment-detail-screen')),
          findsOneWidget,
        );
        expect(
          harness.players,
          isEmpty,
          reason:
              'a thread of voice replies allocates no decoder until one is '
              'deliberately tapped',
        );
        expect(harness.grants.requests, isEmpty);
        expect(
          find.byType(RecordVoiceMomentScreen),
          findsNothing,
          reason: 'opening a Moment never opens the recorder',
        );
      },
    );

    testWidgets(
      'the hand-off to a neighbour releases the recording, resets the '
      'position and waits for a deliberate play',
      (tester) async {
        final open = listenMoment('m-open', caption: 'Open');
        final next = listenMoment('m-next', caption: 'Next', author: 'kuba');
        final harness = await _pumpDetail(
          tester,
          moment: open,
          size: const Size(1400, 1000),
          neighbours: <VoiceMoment>[open, next],
        );

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        harness.main.emitPosition(const Duration(seconds: 18));
        await tester.pump();

        final row = find.byKey(
          const ValueKey<String>('moments-queue-item-m-next'),
        );
        expect(row, findsOneWidget, reason: 'the hand-off list offers m-next');
        await tester.tap(row);
        await _settle(tester);

        expect(
          harness.main.stopCalls,
          greaterThanOrEqualTo(1),
          reason: 'the recording is released BEFORE the next Moment opens',
        );
        expect(
          harness.players.length,
          1,
          reason:
              'the surface owns exactly one transport — a hand-off must not '
              'leave a second decoder behind',
        );
        expect(
          harness.main.playCalls,
          1,
          reason:
              'architecture §2.6: the queue never auto-advances, so the next '
              'Moment is not played for the viewer',
        );
        expect(
          harness.grants.requests,
          <String>['m-open'],
          reason: 'no grant is minted for a Moment nobody asked to hear',
        );
        expect(find.text('0:00'), findsWidgets);
      },
    );
  });

  group('composer, recorder and the microphone', () {
    testWidgets(
      'the composer mic opens the recorder in reply mode and pauses the '
      'recording first',
      (tester) async {
        final moment = listenMoment('m-mic');
        final harness = await _pumpDetail(tester, moment: moment);

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);

        await tester.tap(find.byKey(_micKey));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          harness.main.pauseCalls,
          1,
          reason:
              'a viewer never records over the recording they are answering',
        );
        final recorder = tester.widget<RecordVoiceMomentScreen>(
          find.byType(RecordVoiceMomentScreen),
        );
        expect(recorder.replyToMomentId, 'm-mic');
        expect(recorder.replyToAuthorName, moment.authorName);
      },
    );
  });

  group('listener ownership', () {
    testWidgets(
      'the expanded player releases its transport and stops listening to the '
      'shared hand-off queue when it is disposed',
      (tester) async {
        final moment = listenMoment('m-dispose');
        final harness = await _pumpDetail(tester, moment: moment);

        await tester.tap(find.byKey(_playKey));
        await _settle(tester);
        expect(harness.main.disposeCalls, 0);

        harness.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(
          harness.main.disposeCalls,
          1,
          reason: 'the one transport is disposed with the screen',
        );

        // A hand-off published after the screen is gone must not reach a
        // dead State: the screen owns its listener and removed it.
        harness.queue.publish(
          viewerUid: listenViewerUid,
          moments: <VoiceMoment>[listenMoment('m-later')],
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
