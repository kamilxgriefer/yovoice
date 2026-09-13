// One position, four readers: the ring, the waveform, the slider and the
// clock can never disagree — and a position tick must not rebuild the page
// around them.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_progress_ring.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'moment_listen_test_support.dart';

double _ringProgress(WidgetTester tester) =>
    tester.widget<MomentProgressRing>(find.byType(MomentProgressRing)).progress;

double _waveProgress(WidgetTester tester) =>
    tester.widgetList<StoryWaveform>(find.byType(StoryWaveform)).first.progress;

double _sliderValue(WidgetTester tester) => tester
    .widget<Slider>(find.byKey(const ValueKey('moment-detail-position')))
    .value;

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

  testWidgets('0 → 40 % → the end: ring, waveform, slider and clock read ONE '
      'value', (tester) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1', durationSeconds: 45),
      size: const Size(900, 900),
    );

    expect(_ringProgress(tester), 0);
    expect(_waveProgress(tester), 0);
    expect(_sliderValue(tester), 0);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);

    await playTo(tester, harness, const Duration(seconds: 18));

    expect(_ringProgress(tester), closeTo(0.4, 1e-9));
    expect(_waveProgress(tester), closeTo(0.4, 1e-9));
    expect(_sliderValue(tester), 18000);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('0:18'), findsOneWidget);
    expect(find.text('0:45'), findsOneWidget);

    harness.player.complete();
    await tester.pump();

    expect(_ringProgress(tester), 1);
    expect(_sliderValue(tester), 45000);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the end of a recording ends playback and starts nothing else', (
    tester,
  ) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      neighbours: [listenMoment('m2', caption: 'The next one')],
      size: const Size(1250, 900),
    );

    await playTo(tester, harness, const Duration(seconds: 44));
    harness.player.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // One player, one play call, and the page is still on the same Moment.
    expect(harness.players, hasLength(1));
    expect(harness.player.playCalls, 1);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('moment-detail-caption')))
          .data,
      'Before the city wakes up',
    );
  });

  testWidgets('a position tick repaints the transport, not the thread', (
    tester,
  ) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1', comments: 1),
      seed: (db) => seedListenComment(db, momentId: 'm1', id: 'c1'),
      size: const Size(900, 900),
    );

    await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final before = tester.widget<MomentConversationThread>(
      find.byType(MomentConversationThread),
    );

    harness.player.emitPosition(const Duration(seconds: 9));
    await tester.pump();
    final afterFirst = tester.widget<MomentConversationThread>(
      find.byType(MomentConversationThread),
    );
    harness.player.emitPosition(const Duration(seconds: 18));
    await tester.pump();
    final afterSecond = tester.widget<MomentConversationThread>(
      find.byType(MomentConversationThread),
    );

    expect(
      identical(before, afterFirst) && identical(before, afterSecond),
      isTrue,
      reason: 'position ticks must not rebuild the route around the player',
    );
    // ...while the transport did move.
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('seeking is clamped and never starts playback', (tester) async {
    final harness = await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(900, 900),
    );

    // Nothing is loaded yet: the skips are disabled and seek nothing.
    await tester.tap(
      find.byKey(const ValueKey('moment-detail-skip-forward')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(harness.players, isEmpty);

    await playTo(tester, harness, const Duration(seconds: 40));
    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-forward')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(harness.player.lastSeekPosition, const Duration(seconds: 45));
    expect(harness.player.playCalls, 1, reason: 'a seek is not a play');

    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(harness.player.lastSeekPosition, const Duration(seconds: 30));
  });
}
