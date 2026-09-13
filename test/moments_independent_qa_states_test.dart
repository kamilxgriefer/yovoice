// Independent QA — the YO Moments destination: Voice ↔ Reels switching, the
// state matrix the boards do not draw, account changes, pagination and
// coexistence with a live room.
//
// Written from the contract, not from the implementation. The destination is
// the real `MomentsScreen` hosting the real `MomentsFeedView` and the real
// embedded Reels stage; the only stand-ins are the audio device, the network
// reads, and the identity.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// A discovery double that pages: the first call returns page one with a
/// cursor, `loadMore` returns the merged page two. `failNextPage` makes the
/// second page fail the way a server refusal does.
class _PagingDiscovery implements MomentDiscoveryService {
  _PagingDiscovery({
    required this.pageOne,
    required this.pageTwo,
    this.failNextPage = false,
  });

  final List<VoiceMoment> pageOne;
  final List<VoiceMoment> pageTwo;
  bool failNextPage;

  int loadCalls = 0;
  int pageCalls = 0;

  MomentDiscoveryFeed _feed(List<VoiceMoment> moments, {required bool more}) =>
      MomentDiscoveryFeed(
        moments: moments,
        fetchedCount: moments.length,
        drops: const <String, MomentDropReason>{},
        seed: 7,
        poolExhausted: more,
        nextCursor: more ? 'cursor-1' : null,
        loadMore: more ? _next : null,
      );

  Future<MomentDiscoveryFeed> _next() async {
    pageCalls += 1;
    if (failNextPage) throw StateError('page unavailable');
    return _feed(<VoiceMoment>[...pageOne, ...pageTwo], more: false);
  }

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
    return _feed(pageOne, more: true);
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

/// Refuses every read with a real denial code, the way rules do.
class _DeniedDiscovery implements MomentDiscoveryService {
  int loadCalls = 0;
  bool allow = false;
  List<VoiceMoment> moments = const <VoiceMoment>[];

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
    if (!allow) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
    }
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: moments.length,
      drops: const <String, MomentDropReason>{},
      seed: 3,
      poolExhausted: false,
    );
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

/// Counts every Reels callable, so "a Voice-only session starts no Reels
/// network request" is a fact rather than a claim about lazy construction.
class _CountingReelService extends ReelService {
  _CountingReelService({required this.calls, required MockFirebaseAuth auth})
    : super(
        auth: auth,
        callableInvoker: (name, payload) async {
          calls.add(name);
          if (name == 'listReelsV2') {
            return <Object?, Object?>{
              'schemaVersion': 2,
              'items': <Object?>[],
              'nextCursor': null,
            };
          }
          throw StateError('unexpected callable $name');
        },
      );

  final List<String> calls;
}

List<String> _visibleMomentIds(WidgetTester tester) => tester
    .widgetList<Widget>(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('moment-row-') &&
            !key.value.startsWith('moment-row-play') &&
            !key.value.startsWith('moment-row-title') &&
            !key.value.startsWith('moment-row-badge') &&
            !key.value.startsWith('moment-row-author') &&
            !key.value.startsWith('moment-row-chain') &&
            !key.value.startsWith('moment-row-like') &&
            !key.value.startsWith('moment-row-comments') &&
            !key.value.startsWith('moment-row-share') &&
            !key.value.startsWith('moment-row-reply') &&
            !key.value.startsWith('moment-row-progress') &&
            !key.value.startsWith('moment-row-time');
      }),
    )
    .map((widget) => (widget.key! as ValueKey<String>).value)
    .toList(growable: false);

void main() {
  late VoidCallback restoreIdentity;

  setUp(() {
    restoreIdentity = installIdentityStub();
    MomentService.clearAllMediaAccessCaches();
  });
  tearDown(() {
    restoreIdentity();
    MomentService.clearAllMediaAccessCaches();
  });

  /// The destination as the shell hosts it, with every seam injected.
  Future<List<FakePreviewAudioPlayer>> pumpDestination(
    WidgetTester tester, {
    required MomentDiscoveryService discovery,
    Size size = const Size(900, 1000),
    MockFirebaseAuth? auth,
    ValueListenable<bool>? isVisible,
    ReelService? reelService,
    MomentNeighbourQueue? queue,
    List<VoiceMoment> social = const <VoiceMoment>[],
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    useSurface(tester, size);
    final identity = auth ?? authAs();
    final firestore = fakeFirestore();
    final players = <FakePreviewAudioPlayer>[];
    await tester.pumpWidget(
      overviewHost(
        MomentsScreen(
          isRootTab: true,
          isVisible: isVisible,
          auth: identity,
          discoveryService: discovery,
          feedService: QuietFeed(
            firestore: firestore,
            auth: identity,
            social: social,
          ),
          viewsService: StaticViews(const <String>{}),
          friendService: StaticFriends(
            firestore: firestore,
            auth: identity,
            friends: null,
          ),
          followService: FollowService(firestore: firestore, auth: identity),
          momentService: StubMomentService(),
          reelService: reelService,
          playerFactory: () {
            final player = FakePreviewAudioPlayer(
              duration: const Duration(seconds: 45),
            );
            players.add(player);
            return player;
          },
        ),
        size: size,
        navigatorKey: navigatorKey,
      ),
    );
    await settleOverview(tester);
    return players;
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('moments-feed-scroll')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pump();
  }

  Future<void> playFirstCard(
    WidgetTester tester,
    List<FakePreviewAudioPlayer> players,
    String id,
  ) async {
    await reveal(tester, find.byKey(ValueKey<String>('moment-row-$id')));
    final play = find.byKey(ValueKey<String>('moment-row-play-$id'));
    await reveal(tester, play);
    await tester.tap(play);
    await settleOverview(tester);
    expect(
      players,
      isNotEmpty,
      reason: 'a deliberate tap is what allocates the one transport',
    );
  }

  group('Voice ↔ Yeels switching', () {
    testWidgets(
      'switching to Yeels releases the Voice transport, and switching back '
      'keeps the loaded pool instead of falling back to loading',
      (tester) async {
        final reelCalls = <String>[];
        final discovery = StaticDiscovery(populatedPool());
        final players = await pumpDestination(
          tester,
          discovery: discovery,
          reelService: _CountingReelService(calls: reelCalls, auth: authAs()),
        );

        await playFirstCard(tester, players, 'm1');
        final voicePlayer = players.single;
        expect(voicePlayer.playCalls, 1);
        expect(
          reelCalls,
          isEmpty,
          reason:
              'a viewer who stays on Voice never starts the Yeels network '
              'request',
        );

        await tester.tap(find.text('Yeels'));
        await settleOverview(tester);

        expect(
          voicePlayer.stopCalls,
          greaterThanOrEqualTo(1),
          reason: 'the hidden half must not keep sounding',
        );
        expect(
          voicePlayer.disposeCalls,
          1,
          reason:
              'the format switch releases the transport, it does not merely '
              'pause it',
        );
        expect(reelCalls, contains('listReelsV2'));

        final loadsBeforeReturn = discovery.loadCalls;
        await tester.tap(find.text('Voice'));
        await settleOverview(tester);

        expect(
          find.byKey(const ValueKey<String>('moments-discovery-loading')),
          findsNothing,
          reason:
              'returning to a retained IndexedStack child must not blank the '
              'pool back to silhouettes',
        );
        await reveal(
          tester,
          find.byKey(const ValueKey<String>('moment-row-m1')),
        );
        expect(
          find.byKey(const ValueKey<String>('moment-row-m1')),
          findsOneWidget,
        );
        expect(
          discovery.loadCalls,
          greaterThan(loadsBeforeReturn),
          reason: 'becoming visible again refreshes the pool',
        );
        expect(
          players.length,
          1,
          reason: 'returning to Voice does not resume or reallocate audio',
        );
      },
    );

    testWidgets(
      'the Yeels half is never built for a session that stays on Voice',
      (tester) async {
        final reelCalls = <String>[];
        await pumpDestination(
          tester,
          discovery: StaticDiscovery(populatedPool()),
          reelService: _CountingReelService(calls: reelCalls, auth: authAs()),
        );

        expect(
          find.byKey(
            const ValueKey<String>('yo-moments-reels-lazy'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'the Yeels slot is a placeholder until it is opened',
        );
        expect(reelCalls, isEmpty);
      },
    );
  });

  group('returning from the expanded player', () {
    testWidgets(
      'a pushed Moment releases the transport, and coming back keeps the same '
      'pool, the same scroll offset and starts nothing',
      (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        final discovery = StaticDiscovery(populatedPool());
        final players = await pumpDestination(
          tester,
          discovery: discovery,
          navigatorKey: navigatorKey,
        );
        await playFirstCard(tester, players, 'm1');
        final player = players.single;

        final scrollable = find
            .descendant(
              of: find.byKey(const ValueKey<String>('moments-feed-scroll')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first;
        await tester.drag(scrollable, const Offset(0, -260));
        await settleOverview(tester);
        final offsetBefore = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        expect(offsetBefore, greaterThan(0));
        final orderBefore = _visibleMomentIds(tester);

        unawaited(
          navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('EXPANDED')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          player.stopCalls,
          greaterThanOrEqualTo(1),
          reason: 'a pushed route silences the feed it was pushed from',
        );

        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        await settleOverview(tester);

        expect(
          tester.state<ScrollableState>(scrollable).position.pixels,
          offsetBefore,
          reason: 'the viewer comes back to where they were reading',
        );
        expect(
          _visibleMomentIds(tester),
          orderBefore,
          reason:
              'the pool the viewer left is the pool they come back to — the '
              'refresh on return must not re-rank the list under them',
        );
        expect(
          players.length,
          1,
          reason: 'coming back allocates no second transport',
        );
        expect(player.resumeCalls, 0, reason: 'and resumes nothing on its own');
      },
    );
  });

  group('the state matrix', () {
    testWidgets(
      'a denied read clears the pool, releases the transport and offers one '
      'retry that recovers',
      (tester) async {
        final discovery = _DeniedDiscovery();
        await pumpDestination(tester, discovery: discovery);

        expect(discovery.loadCalls, 1);
        expect(
          find.byKey(const ValueKey<String>('moments-discovery-refresh')),
          findsOneWidget,
          reason: 'a denial is an error state with a way out, not a blank',
        );
        expect(
          find.byKey(const ValueKey<String>('moments-discovery-loading')),
          findsNothing,
        );

        discovery
          ..allow = true
          // Permanent Moments: the recovery assertion is about the retry, not
          // about an availability timer that would outlive the test.
          ..moments = <VoiceMoment>[
            overviewMoment(
              'm1',
              author: 'maja',
              authorName: 'Maja',
              caption: 'Back after the denial',
              permanent: true,
            ),
          ];
        await tester.tap(
          find.byKey(const ValueKey<String>('moments-discovery-refresh')),
        );
        await settleOverview(tester);

        expect(discovery.loadCalls, 2);
        await reveal(
          tester,
          find.byKey(const ValueKey<String>('moment-row-m1')),
        );
        expect(
          find.byKey(const ValueKey<String>('moment-row-m1')),
          findsOneWidget,
          reason: 'the retry is real: it re-reads and renders the pool',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'a Moment that expires while it is playing is pruned, silences the '
      'transport and leaves no entry in the hand-off list',
      (tester) async {
        final expiring = overviewMoment(
          'm-exp',
          author: 'ola',
          authorName: 'Ola',
          caption: 'Ends soon',
          age: const Duration(hours: 23, minutes: 59),
        );
        final keeper = overviewMoment(
          'm-keep',
          author: 'maja',
          authorName: 'Maja',
          caption: 'Stays',
          permanent: true,
        );
        final queue = MomentNeighbourQueue();
        var now = DateTime.now();
        final players = <FakePreviewAudioPlayer>[];
        useSurface(tester, const Size(900, 1000));
        final identity = authAs();
        final firestore = fakeFirestore();
        await tester.pumpWidget(
          overviewHost(
            Scaffold(
              body: MomentsFeedView(
                auth: identity,
                onRecord: () {},
                onCreate: () {},
                discoveryService: StaticDiscovery(<VoiceMoment>[
                  expiring,
                  keeper,
                ]),
                feedService: QuietFeed(firestore: firestore, auth: identity),
                viewsService: StaticViews(const <String>{}),
                followService: FollowService(
                  firestore: firestore,
                  auth: identity,
                ),
                neighbourQueue: queue,
                momentService: StubMomentService(),
                expiryClock: () => now,
                playerFactory: () {
                  final player = FakePreviewAudioPlayer(
                    duration: const Duration(seconds: 45),
                  );
                  players.add(player);
                  return player;
                },
              ),
            ),
            size: const Size(900, 1000),
          ),
        );
        await settleOverview(tester);

        await playFirstCard(tester, players, 'm-exp');
        final player = players.single;

        // Publish a hand-off the way opening the detail does, then let the
        // Moment reach its deadline.
        queue.publish(
          viewerUid: viewerUid,
          moments: <VoiceMoment>[expiring, keeper],
        );
        now = expiring.expiresAt!.add(const Duration(seconds: 1));
        await tester.pump(const Duration(minutes: 2));
        await settleOverview(tester);

        expect(
          find.byKey(const ValueKey<String>('moment-row-m-exp')),
          findsNothing,
          reason: 'expired audio is enforced dead and disappears',
        );
        expect(
          find.byKey(const ValueKey<String>('moment-row-m-keep')),
          findsOneWidget,
          reason: 'a permanent Moment survives a neighbour expiring',
        );
        expect(
          player.stopCalls,
          greaterThanOrEqualTo(1),
          reason: 'the recording that expired stops sounding',
        );
        expect(
          queue.value.moments.map((moment) => moment.id),
          isNot(contains('m-exp')),
          reason:
              'a hand-off list must not keep offering a Moment that is gone',
        );
      },
    );

    testWidgets('no cover is invented: the card draws no image and an empty '
        'caption reads "Voice Moment"', (tester) async {
      await pumpDestination(
        tester,
        discovery: StaticDiscovery(populatedPool()),
      );

      // m4 has an empty caption in the shared fixture.
      final card = find.byKey(const ValueKey<String>('moment-row-m4'));
      await reveal(tester, card);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Voice Moment')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).image != null,
          ),
        ),
        findsNothing,
        reason:
            'VoiceMoment has no cover field; a placeholder band would be a '
            'fabricated one',
      );
    });
  });

  group('the create composer', () {
    testWidgets(
      'the create chooser opens the Voice recorder on the Voice half and '
      'starts no microphone on the way',
      (tester) async {
        final players = await pumpDestination(
          tester,
          discovery: StaticDiscovery(populatedPool()),
          size: const Size(1300, 1000),
        );

        expect(find.byType(RecordVoiceMomentScreen), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey<String>('moments-create-cta')).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
          findsOneWidget,
          reason: 'one create control, two named composers behind it',
        );
        expect(
          find.byType(RecordVoiceMomentScreen),
          findsNothing,
          reason: 'opening the chooser is not opening the recorder',
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('create-voice-moment-choice')),
        );
        // The recorder draws a live pulse, so it is pumped rather than
        // settled: an animating route never settles.
        await settleOverview(tester);
        await tester.pump(const Duration(milliseconds: 400));

        final recorder = tester.widget<RecordVoiceMomentScreen>(
          find.byType(RecordVoiceMomentScreen),
        );
        expect(
          recorder.replyToMomentId,
          isNull,
          reason: 'a new Moment, not a reply',
        );
        expect(
          players,
          isEmpty,
          reason: 'reaching the composer never allocated a playback transport',
        );
      },
    );
  });

  group('account change', () {
    testWidgets(
      'signing into another account releases the transport, clears the '
      'hand-off list and reloads the pool for the new viewer',
      (tester) async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: viewerUid),
        );
        final queue = MomentNeighbourQueue();
        final discovery = StaticDiscovery(populatedPool());
        final players = <FakePreviewAudioPlayer>[];
        useSurface(tester, const Size(900, 1000));
        final firestore = fakeFirestore();
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
                followService: FollowService(firestore: firestore, auth: auth),
                neighbourQueue: queue,
                momentService: StubMomentService(),
                playerFactory: () {
                  final player = FakePreviewAudioPlayer(
                    duration: const Duration(seconds: 45),
                  );
                  players.add(player);
                  return player;
                },
              ),
            ),
            size: const Size(900, 1000),
          ),
        );
        await settleOverview(tester);

        await playFirstCard(tester, players, 'm1');
        final player = players.single;
        queue.publish(viewerUid: viewerUid, moments: populatedPool());
        final loadsBefore = discovery.loadCalls;

        await auth.signOut();
        await auth.signInWithCustomToken('other');
        await settleOverview(tester);

        expect(
          player.stopCalls,
          greaterThanOrEqualTo(1),
          reason: 'no audio of the previous account survives the switch',
        );
        expect(player.disposeCalls, 1);
        expect(
          queue.value.moments,
          isEmpty,
          reason:
              'a hand-off list belongs to the account that loaded it '
              '(moments_queue_list.dart: "signing out clears it")',
        );
        expect(discovery.loadCalls, greaterThan(loadsBefore));
      },
    );

    testWidgets(
      'a media grant is never shared across accounts, and clearing the caches '
      'invalidates a grant that is still in flight',
      (tester) async {
        final requests = <String>[];
        Completer<void>? gate;

        MomentService serviceFor(String uid) => MomentService(
          firestore: fakeFirestore(),
          auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
          storage: MockFirebaseStorage(),
          mediaAccessInvoker: (request) async {
            requests.add('$uid:${request['momentId']}');
            final open = gate;
            if (open != null) await open.future;
            return <Object?, Object?>{
              'schemaVersion': 1,
              'url':
                  'https://storage.googleapis.com/yovoice-test/'
                  '${request['momentId']}.m4a?sig=$uid${requests.length}',
              'expiresAtMillis': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
              'mediaGeneration': '1001',
              'mediaContentType': 'audio/mp4',
              'mediaSize': 4096,
            };
          },
        );

        final accountA = serviceFor('account-a');
        final first = await accountA.resolveMediaUri(momentId: 'm1');
        final cached = await accountA.resolveMediaUri(momentId: 'm1');
        expect(
          cached,
          first,
          reason: 'the same account reuses its own live grant',
        );
        expect(requests, <String>['account-a:m1']);

        // A different signed-in account, the SAME process-wide cache.
        final accountB = serviceFor('account-b');
        final second = await accountB.resolveMediaUri(momentId: 'm1');
        expect(
          requests,
          <String>['account-a:m1', 'account-b:m1'],
          reason:
              'a signed media URL is a bearer capability; it is keyed to the '
              'account that was granted it and never handed to another',
        );
        expect(second, isNot(first));

        // The sign-out path invalidates a response that is still in flight.
        gate = Completer<void>();
        final pending = accountA.resolveMediaUri(momentId: 'm2');
        MomentService.clearAllMediaAccessCaches();
        gate.complete();
        await expectLater(
          pending,
          throwsA(isA<StateError>()),
          reason:
              'AuthService.signOut clears the caches BEFORE any async cleanup '
              'yields, so an in-flight grant must not resolve afterwards',
        );
      },
    );
  });

  group('pagination', () {
    testWidgets('a second page appends without losing the first', (
      tester,
    ) async {
      final pageOne = <VoiceMoment>[
        overviewMoment('p1', author: 'a', authorName: 'A'),
        overviewMoment('p2', author: 'b', authorName: 'B'),
      ];
      final pageTwo = <VoiceMoment>[
        overviewMoment('p3', author: 'c', authorName: 'C'),
      ];
      final discovery = _PagingDiscovery(pageOne: pageOne, pageTwo: pageTwo);
      await pumpDestination(tester, discovery: discovery);

      final more = find.byKey(const ValueKey<String>('moments-load-more'));
      await tester.scrollUntilVisible(
        more,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('moments-feed-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(more);
      await tester.pump();
      await tester.tap(more);
      await settleOverview(tester);

      expect(discovery.pageCalls, 1);
      for (final id in <String>['p1', 'p2', 'p3']) {
        expect(
          find.byKey(ValueKey<String>('moment-row-$id')),
          findsOneWidget,
          reason: 'paging merges; it never replaces the page already read',
        );
      }
    });

    testWidgets(
      'a failed second page keeps the first page on screen and the retry '
      'appends exactly once',
      (tester) async {
        final pageOne = <VoiceMoment>[
          overviewMoment('p1', author: 'a', authorName: 'A'),
        ];
        final pageTwo = <VoiceMoment>[
          overviewMoment('p2', author: 'b', authorName: 'B'),
        ];
        final discovery = _PagingDiscovery(
          pageOne: pageOne,
          pageTwo: pageTwo,
          failNextPage: true,
        );
        await pumpDestination(tester, discovery: discovery);

        final more = find.byKey(const ValueKey<String>('moments-load-more'));
        await tester.scrollUntilVisible(
          more,
          240,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey<String>('moments-feed-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(more);
        await tester.pump();
        await tester.tap(more);
        await settleOverview(tester);

        expect(
          find.byKey(const ValueKey<String>('moment-row-p1')),
          findsOneWidget,
          reason: 'a paging failure never blanks what was already read',
        );

        discovery.failNextPage = false;
        await tester.ensureVisible(more);
        await tester.pump();
        await tester.tap(more);
        await settleOverview(tester);

        expect(discovery.pageCalls, 2);
        expect(
          find.byKey(const ValueKey<String>('moment-row-p2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('moment-row-p1')),
          findsOneWidget,
          reason: 'the retry appends; it does not duplicate or drop',
        );
      },
    );
  });

  group('coexistence with a live room or call', () {
    testWidgets(
      'the shell hiding Moments for a room silences the recording and starts '
      'no microphone; coming back neither resumes nor records',
      (tester) async {
        final visible = ValueNotifier<bool>(true);
        addTearDown(visible.dispose);
        final discovery = StaticDiscovery(populatedPool());
        final players = await pumpDestination(
          tester,
          discovery: discovery,
          isVisible: visible,
        );

        await playFirstCard(tester, players, 'm1');
        final player = players.single;

        // The viewer joins a room: the shell keeps Moments mounted behind the
        // room surface and marks it invisible.
        visible.value = false;
        await settleOverview(tester);

        expect(
          player.stopCalls,
          greaterThanOrEqualTo(1),
          reason:
              'a Moment recording must not play into a live room — the shell '
              'suspending the destination is the arbitration point',
        );
        expect(player.disposeCalls, 1);
        expect(find.byType(RecordVoiceMomentScreen), findsNothing);

        visible.value = true;
        await settleOverview(tester);

        expect(
          players.length,
          1,
          reason:
              'leaving the room brings the surface back silent — nothing '
              'resumes on its own',
        );
        expect(player.resumeCalls, 0);
        expect(find.byType(RecordVoiceMomentScreen), findsNothing);
      },
    );
  });
}
