// The expanded Voice Moment (board 07) and the currency of one playback.
//
// A media grant is a network round trip. Between the tap that asks for it and
// the bytes that answer, the viewer can hand off to a neighbour, watch the
// Moment reach its deadline, push a route over the screen or send the app to
// the background. `mounted` sees none of that, which is why the answer used to
// sound over whatever had replaced it.
//
// These cases are the three media probes of `moments-media.md` (D-1 / D-2 /
// D-3) and the lifecycle gap of D-4, inverted: they assert the rule rather
// than the defect, so they fail if the guard is ever removed.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';

import 'moment_listen_test_support.dart';
import 'voice_moment_test_doubles.dart';

const _playKey = ValueKey<String>('moment-detail-play');

/// A grant seam whose answer can be held open for as long as the case needs.
class _HeldGrants {
  final List<String> requests = <String>[];
  Completer<void>? gate;

  MomentMediaAccessInvoker get invoker => (request) async {
    requests.add('${request['momentId']}');
    final open = gate;
    if (open != null) await open.future;
    return <Object?, Object?>{
      'schemaVersion': 1,
      'url':
          'https://storage.googleapis.com/yovoice-test/'
          '${request['momentId']}.m4a?X-Goog-Signature=currency',
      'expiresAtMillis': DateTime.now()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
      'mediaGeneration': '1001',
      'mediaContentType': 'audio/mp4',
      'mediaSize': 4096,
    };
  };
}

/// A clock the case advances by hand, so a deadline can pass while a grant
/// is in flight without the test waiting for real time.
class _TestClock {
  _TestClock(this.now);
  DateTime now;
  void advance(Duration by) => now = now.add(by);
}

class _Harness {
  _Harness({
    required this.players,
    required this.grants,
    required this.navigatorKey,
    required this.clock,
  });

  final List<FakePreviewAudioPlayer> players;
  final _HeldGrants grants;
  final GlobalKey<NavigatorState> navigatorKey;
  final _TestClock clock;

  FakePreviewAudioPlayer get main => players.first;
  int get playCalls =>
      players.fold(0, (total, player) => total + player.playCalls);
  int get stopCalls =>
      players.fold(0, (total, player) => total + player.stopCalls);
}

/// Pumps the expanded player as the pushed route production uses, under the
/// real [appRouteObserver] so `didPushNext` behaves as it does in the app.
Future<_Harness> _pumpDetail(
  WidgetTester tester, {
  required VoiceMoment moment,
  List<VoiceMoment> neighbours = const <VoiceMoment>[],
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final clock = _TestClock(DateTime.now());
  final db = FakeFirebaseFirestore();
  await db
      .collection('voiceMoments')
      .doc(moment.id)
      .set(listenMomentDoc(moment));
  for (final neighbour in neighbours) {
    await db
        .collection('voiceMoments')
        .doc(neighbour.id)
        .set(listenMomentDoc(neighbour));
  }

  final auth = listenAuth();
  final grants = _HeldGrants();
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
  // The grant cache is process-wide and static.
  MomentService.clearAllMediaAccessCaches();
  addTearDown(MomentService.clearAllMediaAccessCaches);

  final players = <FakePreviewAudioPlayer>[];
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
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
          neighbours: neighbours.isEmpty ? null : neighbours,
          neighbourQueue: MomentNeighbourQueue(),
          expiryClock: () => clock.now,
          playerFactory: () {
            final player = FakePreviewAudioPlayer(
              duration: const Duration(seconds: 45),
            );
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
  return _Harness(
    players: players,
    grants: grants,
    navigatorKey: navigatorKey,
    clock: clock,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  testWidgets(
    'a grant that lands after the hand-off never plays the Moment the viewer '
    'left',
    (tester) async {
      final current = listenMoment('m-current', caption: 'The one being left');
      final next = listenMoment(
        'm-next',
        author: 'bartek',
        authorName: 'Bartek',
        caption: 'The one handed off to',
      );
      final harness = await _pumpDetail(
        tester,
        moment: current,
        neighbours: <VoiceMoment>[next],
      );

      // Ask for the recording and hold its grant open.
      harness.grants.gate = Completer<void>();
      await tester.tap(find.byKey(_playKey));
      await _settle(tester);
      expect(harness.grants.requests, <String>['m-current']);
      expect(harness.playCalls, 0, reason: 'the bytes have not arrived yet');

      // Hand off while the grant is still in flight.
      final row = find.byKey(
        const ValueKey<String>('moments-queue-item-m-next'),
      );
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await _settle(tester);

      harness.grants.gate!.complete();
      await _settle(tester);

      expect(
        harness.playCalls,
        0,
        reason:
            'the answer belongs to a Moment this screen no longer shows; '
            'starting it would sound the PREVIOUS recording over the new '
            'Moment with the transport reading 0 %',
      );
      expect(find.text('The one handed off to'), findsWidgets);
    },
  );

  testWidgets(
    'a grant that lands after the Moment is gone never plays an expired '
    'recording',
    (tester) async {
      // Alive when the screen opens, past its deadline a moment later.
      final moment = listenMoment(
        'm-expiring',
        age: const Duration(hours: 23, minutes: 59, seconds: 58),
      );
      final harness = await _pumpDetail(tester, moment: moment);

      harness.grants.gate = Completer<void>();
      await tester.tap(find.byKey(_playKey));
      await _settle(tester);
      expect(harness.playCalls, 0);

      // The deadline passes while the grant is in flight.
      harness.clock.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);

      harness.grants.gate!.complete();
      await _settle(tester);

      expect(
        harness.playCalls,
        0,
        reason:
            'the grant was minted legitimately before expiry, so the server '
            'cannot be the guard here — the client is (architecture §6.2)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a route pushed over the expanded player stops and RELEASES the recording',
    (tester) async {
      final moment = listenMoment('m-pushed');
      final harness = await _pumpDetail(tester, moment: moment);

      await tester.tap(find.byKey(_playKey));
      await _settle(tester);
      expect(harness.playCalls, 1);
      expect(harness.main.stopCalls, 0);

      unawaited(
        harness.navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('OVER'))),
          ),
        ),
      );
      await _settle(tester);

      expect(
        harness.main.stopCalls,
        greaterThan(0),
        reason:
            'the Voice feed and every Yeel card already stop on didPushNext; '
            'this surface owns board 07 transport and must agree',
      );
      expect(
        harness.main.disposeCalls,
        greaterThan(0),
        reason:
            'released, not paused: a paused audioplayers instance still owns '
            'its native player and, on iOS, its audio session',
      );
    },
  );

  testWidgets('the app leaving the foreground stops the recording', (
    tester,
  ) async {
    final moment = listenMoment('m-background');
    final harness = await _pumpDetail(tester, moment: moment);

    await tester.tap(find.byKey(_playKey));
    await _settle(tester);
    expect(harness.playCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester);

    expect(
      harness.main.stopCalls,
      greaterThan(0),
      reason:
          'ios/Runner/Info.plist declares UIBackgroundModes: audio for '
          'LiveKit, so a backgrounded recording really keeps sounding with '
          'no lock-screen controls and no way to stop it',
    );
  });

  testWidgets(
    'a grant that lands after the screen is gone starts nothing at all',
    (tester) async {
      final moment = listenMoment('m-disposed');
      final harness = await _pumpDetail(tester, moment: moment);

      harness.grants.gate = Completer<void>();
      await tester.tap(find.byKey(_playKey));
      await _settle(tester);

      harness.navigatorKey.currentState!.pop();
      await _settle(tester);

      harness.grants.gate!.complete();
      await _settle(tester);

      expect(harness.playCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
