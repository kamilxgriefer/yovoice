// Independent QA for Voice Moments after the 2026-09-12 chrome correction.
//
// SCOPE NOTE, deliberate and load-bearing: the owner asked for an immersive
// one-moment-per-screen Voice feed. That feed does NOT exist in this tree --
// Voice below 600 px still renders `_FeedColumn`, a `ListView` of cards. These
// cases therefore pin the behaviour the immersive rewrite must carry forward,
// on the surface that actually ships today. Each one is written so that it
// keeps its meaning against a pager: they assert single audio ownership,
// exact-expiry removal, denial handling, ordering stability, ownership-gated
// actions, caption reachability, end-of-feed honesty and dock clearance --
// never the fact that the container happens to be a list.
//
// Controller and geometry boundary only. No real audio device, no decoder, no
// network, no Firebase project, and no claim about audible sound.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'support/material_icons_font.dart';

final _time = DateTime.utc(2026, 9, 12, 14);
const _dockKey = ValueKey<String>('voice-independent-retained-dock');

/// A caption long enough to need clamping on a 320 px phone at 200 % text.
/// The Polish fixture the spec names in section 5.6.
const _longCaption =
    'Krótka historia o tym, co dziś było ważne. Rozmowa może zacząć się od '
    'jednego zdania — a dalszą część przeczytasz i usłyszysz w szczegółach.';

VoiceMoment _moment(
  String id, {
  String author = 'friend',
  int likes = 0,
  int comments = 0,
  String? caption,
  DateTime? expiresAt,
  bool permanent = false,
}) => VoiceMoment(
  id: id,
  authorId: author,
  authorName: 'Author $author',
  authorPhotoUrl: null,
  caption: caption ?? 'Caption $id',
  audioUrl: null,
  durationSeconds: 24,
  likeCount: likes,
  commentCount: comments,
  isPublished: true,
  createdAt: _time.subtract(const Duration(hours: 1)),
  expiresAt: permanent ? null : (expiresAt ?? _time.add(const Duration(hours: 1))),
  schemaVersion: 2,
  status: 'published',
  hasAuthorizedMedia: true,
  reportReceipt: 'qa-receipt-$id',
);

MomentDiscoveryFeed _page(
  List<VoiceMoment> items, {
  int? fetchedCount,
  bool poolExhausted = false,
  String? nextCursor,
  Future<MomentDiscoveryFeed> Function()? loadMore,
}) => MomentDiscoveryFeed(
  moments: items,
  fetchedCount: fetchedCount ?? items.length,
  drops: const <String, MomentDropReason>{},
  seed: 11,
  poolExhausted: poolExhausted,
  nextCursor: nextCursor,
  loadMore: loadMore,
);

Uri _media(String id) => Uri.parse('https://example.invalid/voice-$id.m4a');

// --------------------------------------------------------------- fake clock

class _FakeExpiryTimer implements MomentExpiryTimer {
  _FakeExpiryTimer(this.deadline, this.callback);

  final DateTime deadline;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    callback();
  }

  @override
  void cancel() => cancelled = true;
}

class _Clock {
  _Clock(this.now);

  DateTime now;
  final List<_FakeExpiryTimer> _timers = <_FakeExpiryTimer>[];

  MomentExpiryTimer create(Duration delay, void Function() callback) {
    final timer = _FakeExpiryTimer(now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    now = now.add(duration);
    while (true) {
      final due =
          _timers
              .where(
                (timer) =>
                    !timer.cancelled &&
                    !timer.fired &&
                    !timer.deadline.isAfter(now),
              )
              .toList(growable: false)
            ..sort((a, b) => a.deadline.compareTo(b.deadline));
      if (due.isEmpty) return;
      due.first.fire();
    }
  }
}

// ------------------------------------------------------------------- doubles

class _Auth extends MockFirebaseAuth {
  User? user = MockUser(uid: 'viewer');
  final events = StreamController<User?>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => events.stream;

  void switchTo(String? uid) {
    user = uid == null ? null : MockUser(uid: uid);
    events.add(user);
  }
}

class _Discovery implements MomentDiscoveryService {
  _Discovery(this.items);

  List<VoiceMoment> items;
  int loads = 0;
  Future<MomentDiscoveryFeed> Function()? onLoad;
  final engagement =
      StreamController<Map<String, MomentEngagement>>.broadcast();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({int poolSize = 60, int? seed}) {
    loads++;
    return onLoad?.call() ?? Future<MomentDiscoveryFeed>.value(_page(items));
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      engagement.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed implements HomeFeedService {
  List<VoiceMoment> social = <VoiceMoment>[];
  final changes = StreamController<List<VoiceMoment>>.broadcast();
  final writes = <String>[];
  Completer<void>? likeGate;
  bool likeShouldFail = false;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.multi((sink) {
        sink.add(social);
        final subscription = changes.stream.listen(
          sink.add,
          onError: sink.addError,
        );
        sink.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    writes.add('$momentId:$liked');
    final gate = likeGate;
    if (gate != null) await gate.future;
    if (likeShouldFail) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'QA_LIKE_WRITE_REFUSED',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Moments implements MomentService {
  final requested = <String>[];
  final deleted = <String>[];
  final grants = <String, Completer<Uri>>{};
  Object? deleteFailure;
  List<VoiceMoment> mine = <VoiceMoment>[];
  final mineChanges = StreamController<List<VoiceMoment>>.broadcast();

  @override
  Stream<List<VoiceMoment>> watchMyMoments() =>
      Stream<List<VoiceMoment>>.multi((sink) {
        sink.add(mine);
        final subscription = mineChanges.stream.listen(
          sink.add,
          onError: sink.addError,
        );
        sink.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<Uri> resolveMediaUri({required String momentId, String? commentId}) {
    requested.add(momentId);
    return grants[momentId]?.future ?? Future<Uri>.value(_media(momentId));
  }

  @override
  Future<void> deleteMoment(VoiceMoment moment) async {
    deleted.add(moment.id);
    final failure = deleteFailure;
    if (failure != null) throw failure;
  }

  @override
  Stream<VoiceMoment> watchMoment(String momentId) =>
      Stream<VoiceMoment>.value(_moment(momentId));

  @override
  Stream<List<MomentComment>> watchComments(String momentId, {int limit = 80}) =>
      Stream<List<MomentComment>>.value(const <MomentComment>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Views implements MomentViewsService {
  final ids = <String>[];

  @override
  Stream<Set<String>> watchViewedMomentIds() =>
      Stream<Set<String>>.value(const <String>{});

  @override
  Future<void> markViewed(String momentId) async => ids.add(momentId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Applies each native effect when its Future settles, so a slow stop really
/// can overlap a later play unless the transport serializes them.
class _NativeDriver {
  final players = <_NativePlayer>[];
  final effects = <String>[];
  int maximumOwners = 0;
  bool overlapped = false;

  _NativePlayer makePlayer() {
    final player = _NativePlayer(this, players.length);
    players.add(player);
    return player;
  }

  void observe() {
    final owners = players.where((p) => p.allocated && !p.disposed).length;
    if (owners > maximumOwners) maximumOwners = owners;
    if (audible.length > 1) overlapped = true;
  }

  List<String> get audible => <String>[
    for (final player in players)
      if (player.audibleSource != null) player.audibleSource!,
  ];
}

class _NativePlayer implements audio.AudioPlayer {
  _NativePlayer(this.driver, this.id);

  final _NativeDriver driver;
  final int id;
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completions = StreamController<void>.broadcast();
  Future<void> Function(int call)? stopBarrier;
  String? loadedSource;
  String? audibleSource;
  bool allocated = false;
  bool disposed = false;
  int stopCalls = 0;
  final playCalls = <String>[];

  @override
  Stream<Duration> get onPositionChanged => positions.stream;

  @override
  Stream<Duration> get onDurationChanged => durations.stream;

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    final url = (source as audio.UrlSource).url;
    playCalls.add(url);
    driver.effects.add('$id:play-start:$url');
    loadedSource = url;
    audibleSource = url;
    driver.effects.add('$id:play-settled:$url');
    driver.observe();
  }

  @override
  Future<void> stop() async {
    final call = ++stopCalls;
    driver.effects.add('$id:stop-start:$call');
    await stopBarrier?.call(call);
    audibleSource = null;
    driver.effects.add('$id:stop-settled:$call');
  }

  @override
  Future<void> pause() async => audibleSource = null;

  @override
  Future<void> resume() async {
    audibleSource = loadedSource;
    driver.observe();
  }

  @override
  Future<void> seek(Duration position) async => positions.add(position);

  @override
  Future<void> dispose() async {
    audibleSource = null;
    disposed = true;
    driver.observe();
  }

  Future<void> close() async {
    await positions.close();
    await durations.close();
    await completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ------------------------------------------------------------------ harness

class _Harness {
  _Harness({List<VoiceMoment>? items})
    : discovery = _Discovery(
        items ?? <VoiceMoment>[_moment('a'), _moment('b')],
      );

  final auth = _Auth();
  final _Discovery discovery;
  final feed = _Feed();
  final moments = _Moments();
  final views = _Views();
  final driver = _NativeDriver();
  final clock = _Clock(_time);
  final visible = ValueNotifier<bool>(true);
  final opened = <VoiceMoment>[];
  final announcements = <String>[];
  int creations = 0;

  _NativePlayer get player => driver.players.first;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1200),
    double scale = 1,
    ThemeData? theme,
    MomentsFilter filter = MomentsFilter.discover,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (Object? message) async {
        if (message is Map && message['type'] == 'announce') {
          final data = message['data'] as Map?;
          final text = data?['message'];
          if (text is String) announcements.add(text);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.darkTheme,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorObservers: <NavigatorObserver>[appRouteObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: MomentsFeedView(
            onRecord: () {},
            initialFilter: filter,
            auth: auth,
            discoveryService: discovery,
            feedService: feed,
            momentService: moments,
            viewsService: views,
            isVisible: visible,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
            playerFactory: () {
              final player = driver.makePlayer();
              creations++;
              player.allocated = true;
              driver.observe();
              return player;
            },
            onOpenDetail: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    for (final player in driver.players) {
      player.stopBarrier = null;
    }
    for (final entry in moments.grants.entries) {
      if (!entry.value.isCompleted) entry.value.complete(_media(entry.key));
    }
    final gate = feed.likeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await auth.events.close();
    await discovery.engagement.close();
    await feed.changes.close();
    await moments.mineChanges.close();
    for (final player in driver.players) {
      await player.close();
    }
    visible.dispose();
  }
}

Future<void> _tapPlay(WidgetTester tester, String id) async {
  final control = find.byKey(ValueKey<String>('moment-row-play-$id'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
}

Finder _card(String id) => find.byKey(ValueKey<String>('moment-row-$id'));

void main() {
  late PublicIdentityRepository previousIdentity;

  setUpAll(() async {
    await loadMaterialIconsFont();
  });

  setUp(() {
    previousIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      fetchOverride: (uids) async => <String, Map<String, Object?>>{
        for (final uid in uids)
          uid: <String, Object?>{'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() => PublicIdentityRepository.instance = previousIdentity);

  testWidgets('independent Voice: the previous Moment is silenced before the '
      'next one starts, even when its stop settles late', (tester) async {
    final harness = _Harness();
    await harness.mount(tester);

    await _tapPlay(tester, 'a');
    await tester.pumpAndSettle();
    expect(
      harness.driver.audible,
      <String>[_media('a').toString()],
      reason: 'A must be the sole audible source after its own play',
    );

    // Hold A's interruption open so a naive implementation would let B start
    // over a still-audible A.
    final release = Completer<void>();
    harness.player.stopBarrier = (_) => release.future;

    await _tapPlay(tester, 'b');
    await tester.pump();
    expect(
      harness.driver.audible.length,
      lessThanOrEqualTo(1),
      reason: 'B must not become audible while A has not confirmed its stop',
    );

    release.complete();
    await tester.pumpAndSettle();

    expect(
      harness.driver.audible,
      <String>[_media('b').toString()],
      reason: 'exactly one Moment is audible, and it is B',
    );
    expect(
      harness.driver.overlapped,
      isFalse,
      reason: 'two Voice Moments were audible at the same time',
    );
    expect(
      harness.driver.maximumOwners,
      1,
      reason: 'the feed must never hold two native players at once',
    );
    final stopSettled = harness.driver.effects.indexWhere(
      (effect) => effect.startsWith('0:stop-settled'),
    );
    final playB = harness.driver.effects.indexWhere(
      (effect) => effect.endsWith('play-settled:${_media('b')}'),
    );
    expect(stopSettled, isNonNegative);
    expect(
      stopSettled,
      lessThan(playB),
      reason: "A's stop must settle before B's play is applied",
    );
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: an expiry that fires while the Moment is on '
      'screen stops its audio, removes it and announces once', (tester) async {
    final harness = _Harness(
      items: <VoiceMoment>[
        _moment('a', expiresAt: _time.add(const Duration(seconds: 30))),
        _moment('b', permanent: true),
      ],
    );
    await harness.mount(tester);

    await _tapPlay(tester, 'a');
    await tester.pumpAndSettle();
    expect(harness.driver.audible, <String>[_media('a').toString()]);
    expect(_card('a'), findsOneWidget);

    harness.announcements.clear();
    harness.clock.advance(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(
      _card('a'),
      findsNothing,
      reason: 'the expired Moment must leave the surface',
    );
    expect(_card('b'), findsOneWidget, reason: 'the live Moment stays');
    expect(
      harness.driver.audible,
      isEmpty,
      reason: 'an expired Moment must not stay audible',
    );
    expect(
      harness.announcements.where(
        (text) => text.toLowerCase().contains('expired'),
      ),
      hasLength(1),
      reason: 'exactly one polite expiry announcement, never zero or two',
    );
    expect(
      find.byKey(const ValueKey<String>('moments-discovery-refresh')),
      findsOneWidget,
      reason: 'the focus-recovery target must survive the removal',
    );
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: a permission loss on the next page silences '
      'audio and never shows a fake empty feed', (tester) async {
    final harness = _Harness();
    harness.discovery.onLoad = () async => _page(
      <VoiceMoment>[_moment('a'), _moment('b')],
      poolExhausted: true,
      nextCursor: 'cursor-1',
      loadMore: () async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'QA_PRIVATE_DENIAL',
      ),
    );
    await harness.mount(tester);

    await _tapPlay(tester, 'a');
    await tester.pumpAndSettle();
    expect(harness.driver.audible, <String>[_media('a').toString()]);

    final loadMore = find.byKey(const ValueKey<String>('moments-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(
      harness.driver.audible,
      isEmpty,
      reason: 'losing read permission mid-feed must stop playback',
    );
    expect(_card('a'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('moments-discovery-error')),
      findsOneWidget,
      reason: 'denial is an error state, never an empty corpus claim',
    );
    expect(
      find.text('No Voice Moments yet'),
      findsNothing,
      reason: 'a denied read must never be reported as "nobody published"',
    );
    expect(
      find.textContaining('QA_PRIVATE_DENIAL'),
      findsNothing,
      reason: 'raw backend messages must not reach the surface',
    );
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: losing the account mid-playback clears the '
      'feed and releases audio', (tester) async {
    final harness = _Harness();
    await harness.mount(tester);

    await _tapPlay(tester, 'a');
    await tester.pumpAndSettle();
    expect(harness.driver.audible, isNotEmpty);

    harness.auth.switchTo(null);
    await tester.pumpAndSettle();

    expect(
      harness.driver.audible,
      isEmpty,
      reason: 'a signed-out viewer must not keep hearing the previous account',
    );
    expect(_card('a'), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: live like and comment counters landing '
      'during a swipe change the numbers and never the order', (tester) async {
    final harness = _Harness(
      items: <VoiceMoment>[
        _moment('a', likes: 0, comments: 0),
        _moment('b', likes: 5, comments: 1),
      ],
    );
    await harness.mount(tester, filter: MomentsFilter.mostEngaged);

    // Frozen engagement order: b outranks a.
    final beforeA = tester.getTopLeft(_card('a')).dy;
    final beforeB = tester.getTopLeft(_card('b')).dy;
    expect(beforeB, lessThan(beforeA));

    // A counter update arrives mid-gesture that would re-rank a above b if
    // live numbers were allowed to drive ordering (ADR-095 forbids that).
    await tester.drag(
      find.byKey(const ValueKey<String>('moments-feed-scroll')),
      const Offset(0, -30),
    );
    harness.discovery.engagement.add(<String, MomentEngagement>{
      'a': const MomentEngagement(likeCount: 99, commentCount: 42),
      'b': const MomentEngagement(likeCount: 5, commentCount: 1),
    });
    await tester.pumpAndSettle();

    expect(
      find.text('Likes: 99'),
      findsOneWidget,
      reason: 'the live counter must reach the rendered number',
    );
    expect(find.text('Comments: 42'), findsOneWidget);
    expect(
      tester.getTopLeft(_card('b')).dy,
      lessThan(tester.getTopLeft(_card('a')).dy),
      reason: 'a like landing mid-swipe must not reorder the feed under the '
          'finger',
    );
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: a like tapped while the feed scrolls stays '
      'single-flight and reverts honestly on failure', (tester) async {
    final harness = _Harness(
      items: <VoiceMoment>[_moment('a', likes: 3), _moment('b')],
    );
    final gate = Completer<void>();
    harness.feed.likeGate = gate;
    await harness.mount(tester);

    final like = find.byKey(const ValueKey<String>('moment-row-like-a'));
    await tester.ensureVisible(like);
    await tester.tap(like);
    await tester.pump();

    expect(
      find.text('Likes: 4'),
      findsOneWidget,
      reason: 'the optimistic count is shown while the write is in flight',
    );

    // Single-flight is carried by the control going inert, not by luck: a
    // second press cannot queue a second write.
    expect(
      tester.widget<TextButton>(like).onPressed,
      isNull,
      reason: 'the like control must be inert while its write is in flight',
    );
    expect(
      harness.feed.writes,
      <String>['a:true'],
      reason: 'an in-flight like must not be sent twice',
    );

    // The write then refuses: the optimistic number must go back, not stick.
    harness.feed.likeShouldFail = true;
    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.text('Likes: 3'),
      findsOneWidget,
      reason: 'a refused like must revert the optimistic count',
    );
    expect(
      find.text('Likes: 4'),
      findsNothing,
      reason: 'a refused like must not leave an invented count on screen',
    );
    expect(
      find.text('Your like could not be saved. Try again.'),
      findsOneWidget,
      reason: 'a refused like must be admitted to the viewer',
    );
    expect(
      find.textContaining('QA_LIKE_WRITE_REFUSED'),
      findsNothing,
      reason: 'raw backend text must not reach the surface',
    );
    expect(
      tester.widget<TextButton>(like).onPressed,
      isNotNull,
      reason: 'the control must become usable again after a failure',
    );
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: report is offered on another author only, '
      'and delete on your own only', (tester) async {
    final harness = _Harness(
      items: <VoiceMoment>[
        _moment('other', author: 'friend'),
        _moment('mine', author: 'viewer'),
      ],
    );
    await harness.mount(tester);

    // Somebody else's Moment: Report, never Delete.
    await tester.tap(find.byKey(const ValueKey<String>('moment-row-menu-other')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('moment-row-report-other')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('moment-row-delete-other')),
      findsNothing,
      reason: 'deleting another author\'s Moment must never be offered',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('moment-row-report-other')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('report-reason-sheet')),
      findsOneWidget,
      reason: 'report must reach the shared moderation flow',
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('report-reason-sheet'))),
    ).pop();
    await tester.pumpAndSettle();

    // Your own Moment: Delete, never Report.
    await tester.tap(find.byKey(const ValueKey<String>('moment-row-menu-mine')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('moment-row-delete-mine')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('moment-row-report-mine')),
      findsNothing,
      reason: 'reporting yourself is not a real intent',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('moment-row-delete-mine')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('moment-delete-confirm')),
      findsOneWidget,
      reason: 'delete is destructive and must be confirmed',
    );
    await tester.tap(find.byKey(const ValueKey<String>('moment-delete-cancel')));
    await tester.pumpAndSettle();
    expect(
      harness.moments.deleted,
      isEmpty,
      reason: 'cancelling must not delete',
    );

    await tester.tap(find.byKey(const ValueKey<String>('moment-row-menu-mine')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('moment-row-delete-mine')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('moment-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(harness.moments.deleted, <String>['mine']);
    expect(_card('mine'), findsNothing, reason: 'a deleted Moment leaves at once');
    expect(_card('other'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: a long caption at 200 % on a 320 px phone '
      'clamps without overflow and stays fully reachable', (tester) async {
    final harness = _Harness(
      items: <VoiceMoment>[_moment('a', caption: _longCaption)],
    );
    await harness.mount(
      tester,
      size: const Size(320, 844),
      scale: 2,
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'a long caption must not overflow at 320 px / 200 %',
    );

    final caption = find.descendant(
      of: _card('a'),
      matching: find.text(_longCaption),
    );
    expect(caption, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(caption);
    expect(
      paragraph.size.width,
      lessThanOrEqualTo(320),
      reason: 'the caption must stay inside the viewport width',
    );

    // Clamped text is only acceptable because the whole caption is reachable.
    final title = find.byKey(const ValueKey<String>('moment-row-title-a'));
    await tester.ensureVisible(title);
    expect(
      title.hitTestable(),
      findsOneWidget,
      reason: 'the caption must remain tappable to reach the full text',
    );
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(
      harness.opened.map((moment) => moment.id),
      <String>['a'],
      reason: 'the clamped caption must open the detail that holds all of it',
    );
    await harness.close(tester);
  });

  testWidgets('independent Voice: the last page and the caught-up state are '
      'counted honestly', (tester) async {
    // A cursor remains: the load-more action must exist.
    final paged = _Harness();
    paged.discovery.onLoad = () async => _page(
      <VoiceMoment>[_moment('a'), _moment('b')],
      poolExhausted: true,
      nextCursor: 'cursor-1',
      loadMore: () async =>
          _page(<VoiceMoment>[_moment('a'), _moment('b'), _moment('c')]),
    );
    await paged.mount(tester);

    final loadMore = find.byKey(const ValueKey<String>('moments-load-more'));
    await tester.ensureVisible(loadMore);
    expect(loadMore, findsOneWidget);
    expect(find.text('2 live Moments loaded.'), findsOneWidget);

    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    // The next page was the last one: caught-up copy, no stranded action.
    expect(_card('c'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('moments-load-more')),
      findsNothing,
      reason: 'the caught-up state must not keep offering another page',
    );
    expect(
      find.text('That is all 3 live Moments right now.'),
      findsOneWidget,
      reason: 'the end-of-feed copy is counted, never estimated',
    );
    expect(tester.takeException(), isNull);
    await paged.close(tester);
  });

  testWidgets('independent Voice: a filtered empty page keeps its opaque '
      'next-page action instead of claiming an empty corpus', (tester) async {
    final harness = _Harness();
    harness.discovery.onLoad = () async => _page(
      const <VoiceMoment>[],
      fetchedCount: 4,
      poolExhausted: true,
      nextCursor: 'cursor-1',
      loadMore: () async => _page(<VoiceMoment>[_moment('a')]),
    );
    await harness.mount(tester);

    expect(
      find.byKey(const ValueKey<String>('moments-load-more')),
      findsOneWidget,
      reason: 'a page the privacy filter emptied still has work behind its '
          'cursor',
    );
    expect(find.text('No Voice Moments yet'), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets('independent Voice: no action sits under the retained dock', (
    tester,
  ) async {
    for (final (size, scale) in <(Size, double)>[
      (Size(320, 844), 1),
      (Size(320, 844), 2),
      (Size(390, 844), 1),
      (Size(430, 932), 2),
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()} @$scale';
      final discovery = _Discovery(<VoiceMoment>[_moment('a'), _moment('b')]);
      final feed = _Feed();
      final moments = _Moments();
      final views = _Views();
      final auth = _Auth();
      final visible = ValueNotifier<bool>(true);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: <NavigatorObserver>[appRouteObserver],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            bottomNavigationBar: const SizedBox(key: _dockKey, height: 88),
            body: MomentsScreen(
              isRootTab: true,
              auth: auth,
              discoveryService: discovery,
              feedService: feed,
              momentService: moments,
              viewsService: views,
              isVisible: visible,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dockTop = tester.getRect(find.byKey(_dockKey)).top;
      for (final key in <String>[
        'moment-row-play-a',
        'moment-row-like-a',
        'moment-row-comments-a',
        'moment-row-share-a',
        'moment-row-menu-a',
      ]) {
        final action = find.byKey(ValueKey<String>(key));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        final rect = tester.getRect(action);
        expect(
          rect.bottom,
          lessThanOrEqualTo(dockTop + .5),
          reason: '$label: $key is under the dock',
        );
        expect(
          action.hitTestable(),
          findsOneWidget,
          reason: '$label: $key must stay reachable',
        );
      }
      // The primary transport control carries the product's 48 px promise.
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('moment-row-play-a')))
            .shortestSide,
        greaterThanOrEqualTo(48),
        reason: '$label: the play control must keep a 48 px target',
      );
      expect(tester.takeException(), isNull, reason: label);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await auth.events.close();
      await discovery.engagement.close();
      await feed.changes.close();
      await moments.mineChanges.close();
      visible.dispose();
    }
    tester.view.reset();
  });

  testWidgets('independent Voice: the shared chrome names the selected format '
      'without a text decoration, in both appearances', (tester) async {
    for (final theme in <ThemeData>[AppTheme.darkTheme, AppTheme.lightTheme]) {
      for (final format in YoMomentsFormat.values) {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            navigatorObservers: <NavigatorObserver>[appRouteObserver],
            home: MomentsScreen(
              key: UniqueKey(),
              isRootTab: true,
              initialFormat: format,
              reelService: _emptyReelService(),
              onCreateReel: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(
            text.style?.decoration,
            anyOf(isNull, TextDecoration.none),
            reason: 'selection must never be carried by an underline '
                '(format=$format)',
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('independent Voice: PRE-IMMERSIVE BASELINE -- the Voice body on '
      'a phone is still a card list, not a one-Moment-per-screen pager', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester, size: const Size(390, 844));

    expect(
      find.byKey(const ValueKey<String>('moments-feed-scroll')),
      findsOneWidget,
      reason: 'the shipping Voice body is _FeedColumn, a ListView of cards',
    );
    expect(
      find.byType(PageView),
      findsNothing,
      reason: 'the immersive Voice pager the owner asked for is NOT built; '
          'this assertion is the scope marker and must be inverted by the '
          'change that lands it',
    );
    expect(_card('a'), findsOneWidget);
    expect(_card('b'), findsOneWidget);
    await harness.close(tester);
  });
}

ReelService _emptyReelService() => ReelService(
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
  callableInvoker: (name, payload) async {
    if (name == 'listReelsV2') {
      return <Object?, Object?>{
        'schemaVersion': 2,
        'items': const <Object?>[],
        'nextCursor': null,
      };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);
