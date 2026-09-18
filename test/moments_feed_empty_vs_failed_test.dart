import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/helpers/callable_failure_reporter.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';

import 'moments_overview_test_support.dart';

/// "The server returned ten Moments and gave us none of them" and "the ten
/// Moments you can see expired" are different facts, and only one of them
/// was ever true during the outage.
///
/// `getVoiceMomentsFeedV2` counts candidates BEFORE the per-item `catch`
/// that swallows every projection failure, so a total drop arrives as
/// "scanned 10, moments 0" with an EMPTY client-side drops map — and
/// `Iterable.every` answers `true` for an empty iterable. The screen
/// therefore asserted expiry for Moments it had never seen.
void main() {
  late VoidCallback restoreIdentity;
  final reported = <CallableRefusal>[];

  setUp(() {
    restoreIdentity = installIdentityStub();
    reported.clear();
    callableRefusalRecorder = (refusal, _) => reported.add(refusal);
  });

  tearDown(() {
    resetCallableRefusalRecorder();
    restoreIdentity();
  });

  Future<_ScriptedDiscovery> pumpFeed(
    WidgetTester tester, {
    required MomentDiscoveryFeed Function(int call) build,
    Locale locale = const Locale('en'),
    Size size = const Size(420, 900),
    double textScale = 1,
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    final firestore = fakeFirestore();
    final discovery = _ScriptedDiscovery(build);
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            onCreate: () {},
            discoveryService: discovery,
            feedService: QuietFeed(firestore: firestore, auth: auth),
            viewsService: StaticViews(const <String>{}),
            friendService: StaticFriends(
              firestore: firestore,
              auth: auth,
              friends: null,
            ),
            followService: FollowService(firestore: firestore, auth: auth),
            playerFactory: SilentPlayer.new,
          ),
        ),
        locale: locale,
        size: size,
        textScale: textScale,
      ),
    );
    await settleOverview(tester);
    return discovery;
  }

  MomentDiscoveryFeed serverDroppedEverything({int scanned = 10}) =>
      MomentDiscoveryFeed(
        moments: const <VoiceMoment>[],
        fetchedCount: scanned,
        drops: const <String, MomentDropReason>{},
        seed: 1,
        poolExhausted: false,
      );

  testWidgets('a page the server emptied says so, and never claims expiry', (
    tester,
  ) async {
    await pumpFeed(tester, build: (_) => serverDroppedEverything());

    expect(find.text('These Moments could not be loaded'), findsOneWidget);
    expect(
      find.textContaining(
        'The server returned 10 Moments and none of them could be prepared.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('reached the end of'),
      findsNothing,
      reason: 'the client never saw these Moments and cannot date them',
    );
    expect(find.textContaining('could not be played back'), findsNothing);
  });

  testWidgets('the same page in Polish', (tester) async {
    await pumpFeed(
      tester,
      locale: const Locale('pl'),
      build: (_) => serverDroppedEverything(scanned: 4),
    );

    expect(find.text('Nie udało się wczytać tych Momentów'), findsOneWidget);
    expect(find.textContaining('Serwer zwrócił 4 Momentów'), findsOneWidget);
    expect(find.textContaining('Okres dostępności'), findsNothing);
  });

  testWidgets('the retry reloads, and the drop is reported exactly once per '
      'load', (tester) async {
    final discovery = await pumpFeed(
      tester,
      build: (call) => call == 1
          ? serverDroppedEverything()
          : MomentDiscoveryFeed(
              moments: <VoiceMoment>[
                overviewMoment('m1', author: 'maja', authorName: 'Maja'),
              ],
              fetchedCount: 1,
              drops: const <String, MomentDropReason>{},
              seed: 1,
              poolExhausted: false,
            ),
    );

    expect(reported, hasLength(1));
    expect(reported.single.callable, 'getVoiceMomentsFeedV2');
    expect(reported.single.code, 'server-dropped-all');

    await tester.tap(find.text('Try again'));
    await settleOverview(tester);

    expect(discovery.loadCalls, 2);
    expect(find.text('These Moments could not be loaded'), findsNothing);
    expect(
      reported,
      hasLength(1),
      reason: 'a healthy reload adds no new signal',
    );
  });

  testWidgets('the new state holds at phone, tablet and desktop widths, and '
      'at 200% text', (tester) async {
    // Same content, three available widths and one Dynamic Type setting.
    // The state is a centred, max-320 scrollable column, so nothing may
    // overflow and the title must stay legible at every one of them.
    const surfaces = <({Size size, double textScale})>[
      (size: Size(320, 640), textScale: 1),
      (size: Size(320, 640), textScale: 2),
      (size: Size(834, 1112), textScale: 1),
      (size: Size(1400, 900), textScale: 1),
    ];
    for (final surface in surfaces) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFeed(
        tester,
        size: surface.size,
        textScale: surface.textScale,
        build: (_) => serverDroppedEverything(),
      );

      expect(
        find.text('These Moments could not be loaded'),
        findsOneWidget,
        reason: 'at ${surface.size} x${surface.textScale}',
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow at ${surface.size} x${surface.textScale}',
      );
    }
  });

  testWidgets('a page this client filtered for expiry keeps its own copy', (
    tester,
  ) async {
    await pumpFeed(
      tester,
      build: (_) => MomentDiscoveryFeed(
        moments: const <VoiceMoment>[],
        fetchedCount: 3,
        drops: const <String, MomentDropReason>{
          'a': MomentDropReason.expired,
          'b': MomentDropReason.expired,
          'c': MomentDropReason.expired,
        },
        seed: 1,
        poolExhausted: false,
      ),
    );

    expect(find.textContaining('reached the end of'), findsOneWidget);
    expect(find.text('These Moments could not be loaded'), findsNothing);
    expect(
      reported,
      isEmpty,
      reason: 'the client did the filtering; nothing failed upstream',
    );
  });
}

/// Answers each load from a script, so a test can state exactly what the
/// server handed back.
class _ScriptedDiscovery implements MomentDiscoveryService {
  _ScriptedDiscovery(this.build);

  final MomentDiscoveryFeed Function(int call) build;
  int loadCalls = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
    return build(loadCalls);
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      const <VoiceMoment>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
