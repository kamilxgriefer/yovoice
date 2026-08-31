import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_posts_screen.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final _anchor = DateTime.utc(2026, 8, 27, 12);

VoiceMoment _moment(
  String id, {
  DateTime? expiresAt,
  String author = 'friend',
  DateTime? createdAt,
}) => VoiceMoment(
  id: id,
  authorId: author,
  authorName: 'Author $author',
  authorPhotoUrl: null,
  caption: 'caption $id',
  audioUrl: 'https://cdn.example/$id.m4a',
  durationSeconds: 12,
  likeCount: 0,
  commentCount: 0,
  isPublished: true,
  createdAt: createdAt ?? _anchor.subtract(const Duration(hours: 1)),
  expiresAt: expiresAt,
  schemaVersion: 2,
  status: 'published',
  isDeleted: false,
);

Map<String, dynamic> _doc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': true,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  if (moment.expiresAt != null)
    'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

List<Map<Object?, Object?>> _captureAnnouncements(WidgetTester tester) {
  final captured = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (Object? message) async {
      if (message is Map && message['type'] == 'announce') {
        captured.add(message['data'] as Map<Object?, Object?>);
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
  return captured;
}

List<String> _announcementMessages(List<Map<Object?, Object?>> captured) =>
    captured.map((event) => event['message'] as String).toList(growable: false);

class _FakeExpiryClock {
  _FakeExpiryClock(this.now);

  DateTime now;
  final List<_FakeExpiryTimer> _timers = <_FakeExpiryTimer>[];
  final List<Duration> requestedDelays = <Duration>[];

  MomentExpiryTimer create(Duration delay, void Function() callback) {
    requestedDelays.add(delay);
    final timer = _FakeExpiryTimer(now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  List<DateTime> get activeDeadlines => _timers
      .where((timer) => !timer.cancelled && !timer.fired)
      .map((timer) => timer.deadline)
      .toList(growable: false);

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

class _FakeAudioPlayer implements audio.AudioPlayer {
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {
    playCount += 1;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticDiscovery extends MomentDiscoveryService {
  _StaticDiscovery(this.moments, MockFirebaseAuth auth)
    : super(firestore: FakeFirebaseFirestore(), auth: auth);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 1,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => Stream<Map<String, MomentEngagement>>.value(
    const <String, MomentEngagement>{},
  );
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed(MockFirebaseAuth auth)
    : super(firestore: FakeFirebaseFirestore(), auth: auth);

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
}

void main() {
  late PublicIdentityRepository originalIdentity;
  late MockFirebaseAuth auth;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: Duration.zero,
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  test('nearest deadline is reprogrammed; permanent needs no timer; dispose '
      'suppresses callbacks', () {
    final clock = _FakeExpiryClock(_anchor);
    final first = _moment(
      'first',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final second = _moment(
      'second',
      expiresAt: _anchor.add(const Duration(seconds: 20)),
    );
    final permanent = _moment('permanent');
    final visible = <VoiceMoment>[first, second, permanent];
    final fired = <DateTime>[];
    late final MomentExpiryScheduler scheduler;
    scheduler = MomentExpiryScheduler(
      clock: () => clock.now,
      timerFactory: clock.create,
      onDeadline: (deadline) {
        fired.add(deadline);
        visible.removeWhere(
          (moment) =>
              moment.expiresAt != null && !moment.expiresAt!.isAfter(deadline),
        );
        scheduler.schedule(visible);
      },
    );

    scheduler.schedule(visible);
    expect(clock.activeDeadlines, [first.expiresAt]);
    clock.advance(const Duration(seconds: 9));
    expect(fired, isEmpty);
    clock.advance(const Duration(seconds: 1));
    expect(fired, [first.expiresAt]);
    expect(clock.activeDeadlines, [second.expiresAt]);
    clock.advance(const Duration(seconds: 10));
    expect(fired, [first.expiresAt, second.expiresAt]);
    expect(visible, [permanent]);
    expect(clock.activeDeadlines, isEmpty);

    final disposedFires = <DateTime>[];
    final disposed =
        MomentExpiryScheduler(
          clock: () => clock.now,
          timerFactory: clock.create,
          onDeadline: disposedFires.add,
        )..schedule([
          _moment(
            'later',
            expiresAt: clock.now.add(const Duration(seconds: 5)),
          ),
        ]);
    disposed.dispose();
    clock.advance(const Duration(seconds: 5));
    expect(disposedFires, isEmpty);
    scheduler.dispose();
  });

  test('30-day deadline is chunked below the browser timer limit and fires '
      'only when the clock reaches it', () {
    const browserTimerLimit = Duration(milliseconds: 0x7fffffff);
    const availability = Duration(days: 30);
    final clock = _FakeExpiryClock(_anchor);
    final deadline = _anchor.add(availability);
    final fired = <DateTime>[];
    final scheduler = MomentExpiryScheduler(
      clock: () => clock.now,
      timerFactory: clock.create,
      onDeadline: fired.add,
    )..schedule([_moment('thirty-days', expiresAt: deadline)]);

    expect(clock.requestedDelays, [browserTimerLimit]);

    // Even if a platform timer wakes early, the scheduler must re-check the
    // wall clock rather than treating the future deadline as already crossed.
    clock._timers.single.fire();
    expect(fired, isEmpty);
    expect(clock.requestedDelays, [browserTimerLimit, browserTimerLimit]);

    clock.advance(browserTimerLimit);
    expect(fired, isEmpty);
    expect(clock.activeDeadlines, [deadline]);
    expect(
      clock.requestedDelays.every(
        (delay) => delay.inMilliseconds <= browserTimerLimit.inMilliseconds,
      ),
      isTrue,
    );

    clock.advance(deadline.difference(clock.now));
    expect(fired, [deadline]);
    expect(clock.activeDeadlines, isEmpty);
    scheduler.dispose();
  });

  testWidgets('deadline minus one stays visible; deadline hides; permanent '
      'stays visible', (tester) async {
    final clock = _FakeExpiryClock(_anchor);
    final timed = _moment(
      'timed',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            MomentExpiryBoundary(
              moment: timed,
              clock: () => clock.now,
              timerFactory: clock.create,
              expired: const Text('gone'),
              child: const Text('timed-visible'),
            ),
            MomentExpiryBoundary(
              moment: _moment('permanent'),
              clock: () => clock.now,
              timerFactory: clock.create,
              child: const Text('permanent-visible'),
            ),
          ],
        ),
      ),
    );

    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('timed-visible'), findsOneWidget);
    expect(find.text('permanent-visible'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('timed-visible'), findsNothing);
    expect(find.text('gone'), findsOneWidget);
    expect(find.text('permanent-visible'), findsOneWidget);
    expect(clock.activeDeadlines, isEmpty);
  });

  testWidgets(
    'boundary calls onExpired once per active-to-expired transition',
    (tester) async {
      final clock = _FakeExpiryClock(_anchor);
      var moment = _moment(
        'single-callback',
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      );
      var notifications = 0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MomentExpiryBoundary(
                moment: moment,
                clock: () => clock.now,
                timerFactory: clock.create,
                onExpired: () => notifications += 1,
                expired: const Text('gone'),
                child: const Text('live'),
              );
            },
          ),
        ),
      );

      clock.advance(const Duration(seconds: 10));
      await tester.pump();
      expect(notifications, 1);

      // An expired snapshot update in the same transition must not re-fire.
      rebuild(() {
        moment = _moment('single-callback', expiresAt: clock.now);
      });
      await tester.pump();
      await tester.pump();
      expect(notifications, 1);

      // Becoming active resets the transition guard exactly once.
      rebuild(() {
        moment = _moment(
          'single-callback',
          expiresAt: clock.now.add(const Duration(seconds: 5)),
        );
      });
      await tester.pump();
      expect(find.text('live'), findsOneWidget);
      clock.advance(const Duration(seconds: 5));
      await tester.pump();
      expect(notifications, 2);
    },
  );

  testWidgets('list builder reports an overdue transition once when a parent '
      'rebuild beats the queued timer callback', (tester) async {
    final clock = _FakeExpiryClock(_anchor);
    final deadline = _anchor.add(const Duration(seconds: 10));
    final moment = _moment('overdue-list', expiresAt: deadline);
    final notifications = <DateTime>[];
    var parentRevision = 0;
    late StateSetter rebuildParent;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildParent = setState;
            return Column(
              children: [
                Text('parent-$parentRevision'),
                MomentExpiryListBuilder(
                  moments: [moment],
                  clock: () => clock.now,
                  timerFactory: clock.create,
                  onDeadline: notifications.add,
                  builder: (context, now) =>
                      Text(moment.isActiveAt(now) ? 'list-live' : 'list-gone'),
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(find.text('list-live'), findsOneWidget);
    final queuedTimer = clock._timers.single;

    // Advance the wall clock without delivering the timer, then let an
    // unrelated ancestor rebuild the list boundary first.
    clock.now = deadline;
    rebuildParent(() => parentRevision += 1);
    await tester.pump();

    expect(find.text('list-gone'), findsOneWidget);
    expect(notifications, [deadline]);
    expect(queuedTimer.cancelled, isTrue);

    queuedTimer.fire();
    rebuildParent(() => parentRevision += 1);
    await tester.pump();
    expect(notifications, [deadline]);
  });

  test('Home social stream emits again at each exact deadline without a '
      'Firestore snapshot', () async {
    final clock = _FakeExpiryClock(_anchor);
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('friend')
        .set(<String, dynamic>{'since': Timestamp.fromDate(_anchor)});
    final first = _moment(
      'first',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final second = _moment(
      'second',
      expiresAt: _anchor.add(const Duration(seconds: 20)),
    );
    final permanent = _moment('permanent');
    for (final moment in [first, second, permanent]) {
      await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
    }

    final service = HomeFeedService(
      firestore: db,
      auth: auth,
      expiryClock: () => clock.now,
      expiryTimerFactory: clock.create,
    );
    final firstEmission = Completer<void>();
    final firstExpiry = Completer<void>();
    final secondExpiry = Completer<void>();
    var ids = <String>{};
    final subscription = service.watchSocialMoments().listen((moments) {
      ids = moments.map((moment) => moment.id).toSet();
      if (ids.containsAll({'first', 'second', 'permanent'}) &&
          !firstEmission.isCompleted) {
        firstEmission.complete();
      }
      if (ids.length == 2 &&
          ids.containsAll({'second', 'permanent'}) &&
          !firstExpiry.isCompleted) {
        firstExpiry.complete();
      }
      if (ids.length == 1 &&
          ids.contains('permanent') &&
          !secondExpiry.isCompleted) {
        secondExpiry.complete();
      }
    });
    addTearDown(subscription.cancel);

    await firstEmission.future.timeout(const Duration(seconds: 2));
    clock.advance(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);
    expect(ids, containsAll({'first', 'second', 'permanent'}));

    clock.advance(const Duration(seconds: 1));
    await firstExpiry.future.timeout(const Duration(seconds: 2));
    expect(ids, {'second', 'permanent'});

    clock.advance(const Duration(seconds: 10));
    await secondExpiry.future.timeout(const Duration(seconds: 2));
    expect(ids, {'permanent'});
    expect(clock.activeDeadlines, isEmpty);
  });

  testWidgets('Moment detail becomes gone and stops playback at deadline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final moment = _moment(
      'detail',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final db = FakeFirebaseFirestore();
    await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
    final moments = MomentService(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: MomentDetailScreen(
            moment: moment,
            momentService: moments,
            auth: auth,
            playerFactory: () => player,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
    await tester.pump();
    expect(player.playCount, 1);
    await tester.tap(find.byKey(const ValueKey('moment-detail-comment-field')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('moment-detail-comment-field')),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.byKey(const ValueKey('moment-detail-gone')), findsNothing);

    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
    expect(player.stopCount, 1);
    expect(
      find.byKey(const ValueKey('moment-detail-comment-field')),
      findsNothing,
    );
    final back = tester.widget<FilledButton>(
      find.byKey(const ValueKey('moment-detail-gone-back')),
    );
    expect(back.focusNode!.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment is no longer available.',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1));
    semantics.dispose();
  });

  testWidgets('Story viewer stops an expiring clip and advances to the '
      'permanent link', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final timed = _moment(
      'story-timed',
      createdAt: _anchor.subtract(const Duration(hours: 2)),
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final permanent = _moment(
      'story-permanent',
      createdAt: _anchor.subtract(const Duration(hours: 1)),
    );
    final chain = buildMomentChains([timed, permanent]).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MomentStoryViewer(
            chain: chain,
            auth: auth,
            playerFactory: () => player,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(player.playCount, 1);
    expect(find.text('caption story-timed'), findsOneWidget);

    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(player.stopCount, 0);
    expect(find.text('caption story-timed'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(player.stopCount, 1);
    expect(player.playCount, 2);
    expect(find.text('caption story-timed'), findsNothing);
    expect(find.text('caption story-permanent'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    final storyFocus = tester
        .widgetList<Focus>(
          find.descendant(
            of: find.byType(MomentStoryViewer),
            matching: find.byType(Focus),
          ),
        )
        .firstWhere((widget) => widget.autofocus && widget.focusNode != null);
    expect(storyFocus.focusNode!.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment expired. Playing the next Moment.',
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    semantics.dispose();
  });

  testWidgets('Story viewer keeps the first live successor when one wake-up '
      'crosses earlier and current deadlines', (tester) async {
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final earlier = _moment(
      'story-earlier-expiry',
      createdAt: _anchor.subtract(const Duration(hours: 4)),
      expiresAt: _anchor.add(const Duration(seconds: 5)),
    );
    final current = _moment(
      'story-current-expiry',
      createdAt: _anchor.subtract(const Duration(hours: 3)),
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final firstSuccessor = _moment(
      'story-first-successor',
      createdAt: _anchor.subtract(const Duration(hours: 2)),
    );
    final laterSuccessor = _moment(
      'story-later-successor',
      createdAt: _anchor.subtract(const Duration(hours: 1)),
    );
    final chain = buildMomentChains([
      earlier,
      current,
      firstSuccessor,
      laterSuccessor,
    ]).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MomentStoryViewer(
            chain: chain,
            initialIndex: 1,
            auth: auth,
            playerFactory: () => player,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('caption story-current-expiry'), findsOneWidget);
    expect(find.text('2 of 4'), findsOneWidget);

    // Models a suspended app resuming after both finite links expired. The
    // nearest timer fires once with wall time already at the later deadline.
    clock.advance(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();

    expect(player.stopCount, 1);
    expect(player.playCount, 2);
    expect(find.text('caption story-first-successor'), findsOneWidget);
    expect(find.text('caption story-later-successor'), findsNothing);
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Story viewer maps a stale requested index to the first live '
      'successor before its first build', (tester) async {
    final clock = _FakeExpiryClock(_anchor.add(const Duration(seconds: 10)));
    final earlier = _moment(
      'story-stale-earlier',
      createdAt: _anchor.subtract(const Duration(hours: 4)),
      expiresAt: _anchor.add(const Duration(seconds: 5)),
    );
    final requested = _moment(
      'story-stale-requested',
      createdAt: _anchor.subtract(const Duration(hours: 3)),
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final firstSuccessor = _moment(
      'story-stale-first-successor',
      createdAt: _anchor.subtract(const Duration(hours: 2)),
    );
    final laterSuccessor = _moment(
      'story-stale-later-successor',
      createdAt: _anchor.subtract(const Duration(hours: 1)),
    );
    final chain = buildMomentChains([
      earlier,
      requested,
      firstSuccessor,
      laterSuccessor,
    ]).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MomentStoryViewer(
            chain: chain,
            initialIndex: 1,
            autoPlay: false,
            auth: auth,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('caption story-stale-first-successor'), findsOneWidget);
    expect(find.text('caption story-stale-later-successor'), findsNothing);
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('last Story expiry closes at 200% text, announces once, and '
      'restores opener focus', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final openerFocus = FocusNode(debugLabel: 'Open expiring story');
    addTearDown(openerFocus.dispose);
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final chain = buildMomentChains([
      _moment(
        'story-last',
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      ),
    ]).single;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                focusNode: openerFocus,
                onPressed: () => unawaited(
                  showMomentStoryViewer(
                    context,
                    chain: chain,
                    auth: auth,
                    playerFactory: () => player,
                    expiryClock: () => clock.now,
                    expiryTimerFactory: clock.create,
                  ),
                ),
                child: const Text('open expiring story'),
              ),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('open expiring story'));
    await tester.pumpAndSettle();
    expect(find.byType(MomentStoryViewer), findsOneWidget);
    expect(tester.takeException(), isNull);

    clock.advance(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(MomentStoryViewer), findsNothing);
    expect(player.stopCount, 1);
    expect(player.disposeCount, 1);
    expect(openerFocus.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment expired. Closing story.',
    ]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Story expiry removes its own route below a child route without '
      'a background announcement', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final openerFocus = FocusNode(debugLabel: 'Open nested story');
    addTearDown(openerFocus.dispose);
    final clock = _FakeExpiryClock(_anchor);
    final chain = buildMomentChains([
      _moment(
        'story-nested',
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      ),
    ]).single;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              focusNode: openerFocus,
              onPressed: () => unawaited(
                showMomentStoryViewer(
                  context,
                  chain: chain,
                  auth: auth,
                  playerFactory: _FakeAudioPlayer.new,
                  expiryClock: () => clock.now,
                  expiryTimerFactory: clock.create,
                ),
              ),
              child: const Text('open nested story'),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('open nested story'));
    await tester.pumpAndSettle();
    final viewerContext = tester.element(find.byType(MomentStoryViewer));
    unawaited(
      Navigator.of(viewerContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Comments child route'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Comments child route'), findsOneWidget);

    clock.advance(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Comments child route'), findsOneWidget);
    expect(find.byType(MomentStoryViewer, skipOffstage: false), findsNothing);
    expect(_announcementMessages(announcements), isEmpty);

    Navigator.of(tester.element(find.text('Comments child route'))).pop<void>();
    await tester.pumpAndSettle();
    expect(find.text('open nested story'), findsOneWidget);
    expect(openerFocus.hasFocus, isTrue);
    semantics.dispose();
  });

  testWidgets('open Moment sheet closes and disposes its playing card at '
      'deadline', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final openerFocus = FocusNode(debugLabel: 'Open Moment sheet');
    addTearDown(openerFocus.dispose);
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final moment = _moment(
      'sheet',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              focusNode: openerFocus,
              onPressed: () => unawaited(
                showMomentSheet(
                  context,
                  moment: moment,
                  feedService: _QuietFeed(auth),
                  playerFactory: () => player,
                  expiryClock: () => clock.now,
                  expiryTimerFactory: clock.create,
                ),
              ),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    );
    openerFocus.requestFocus();
    await tester.pump();
    expect(openerFocus.hasFocus, isTrue);
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('caption sheet'), findsOneWidget);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
      AppPalette.light.surfaceRaised,
    );

    await tester.tap(find.bySemanticsLabel('Play this Moment'));
    await tester.pump();
    expect(player.playCount, 1);
    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('caption sheet'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('caption sheet'), findsNothing);
    expect(player.disposeCount, 1);
    expect(openerFocus.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment expired. Closing player.',
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    semantics.dispose();
  });

  testWidgets('comments replace the thread and composer with gone state at '
      'deadline', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _FakeExpiryClock(_anchor);
    final moment = _moment(
      'comments',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MomentCommentsScreen(
          moment: moment,
          firestore: FakeFirebaseFirestore(),
          auth: auth,
          expiryClock: () => clock.now,
          expiryTimerFactory: clock.create,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Write a comment...'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('Write a comment...'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('moment-comments-gone')), findsOneWidget);
    expect(find.text('Write a comment...'), findsNothing);
    final back = tester.widget<FilledButton>(
      find.byKey(const ValueKey('moment-comments-gone-back')),
    );
    expect(back.focusNode!.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment expired. Comments are now unavailable.',
    ]);
    semantics.dispose();
  });

  testWidgets('stale-open pinned management drops a Moment at its deadline', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _FakeExpiryClock(_anchor);
    final db = FakeFirebaseFirestore();
    final moment = _moment(
      'pinnable',
      author: 'me',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
    final moments = MomentService(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
    );
    final pins = CreatorPinnedPostService(
      firestore: db,
      auth: auth,
      mutationInvoker: (_) async => const <String, dynamic>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreatorPinnedPostsScreen(
          isRootTab: true,
          pinnedPostService: pins,
          momentService: moments,
          expiryClock: () => clock.now,
          expiryTimerFactory: clock.create,
        ),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('1 available').evaluate().isNotEmpty) break;
    }
    expect(find.text('1 available'), findsOneWidget);
    expect(find.text('caption pinnable'), findsOneWidget);
    final pinFocus = Focus.of(tester.element(find.text('Pin').last));
    pinFocus.requestFocus();
    await tester.pump();
    expect(pinFocus.hasFocus, isTrue);

    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('1 available'), findsOneWidget);
    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0 available'), findsOneWidget);
    expect(find.text('caption pinnable'), findsNothing);
    final headingFocus = Focus.of(
      tester.element(find.bySemanticsLabel('Pinned post')),
    );
    expect(headingFocus.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'Voice Moment expired and is no longer available to pin.',
    ]);
    semantics.dispose();
  });

  testWidgets('public pinned card stops playback and disappears at deadline', (
    tester,
  ) async {
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final db = FakeFirebaseFirestore();
    final moment = _moment(
      'public-pin',
      author: 'me',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
    await db.collection('creatorPinnedPosts').doc('me').set({
      'schemaVersion': 1,
      'creatorId': 'me',
      'momentId': moment.id,
      'pinnedAt': Timestamp.fromDate(_anchor),
      'updatedAt': Timestamp.fromDate(_anchor),
    });
    final pins = CreatorPinnedPostService(
      firestore: db,
      auth: auth,
      mutationInvoker: (_) async => const <String, dynamic>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorPinnedMomentCard(
            creatorId: 'me',
            service: pins,
            playerFactory: () => player,
            expiryClock: () => clock.now,
            expiryTimerFactory: clock.create,
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 10; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('PINNED VOICE MOMENT').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.bySemanticsLabel('Play pinned Voice Moment'));
    await tester.pump();
    expect(player.playCount, 1);

    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('PINNED VOICE MOMENT'), findsOneWidget);
    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('PINNED VOICE MOMENT'), findsNothing);
    expect(player.stopCount, 1);
    expect(player.disposeCount, 1);
  });

  testWidgets('wide feed prunes an expired selected panel and stops its '
      'player', (tester) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clock = _FakeExpiryClock(_anchor);
    final player = _FakeAudioPlayer();
    final expiring = _moment(
      'panel',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );
    final db = FakeFirebaseFirestore();
    await db.collection('voiceMoments').doc(expiring.id).set(_doc(expiring));
    final moments = MomentService(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MomentsScreen(
          isRootTab: true,
          auth: auth,
          momentService: moments,
          discoveryService: _StaticDiscovery([expiring], auth),
          feedService: _QuietFeed(auth),
          playerFactory: () => player,
          expiryClock: () => clock.now,
          expiryTimerFactory: clock.create,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('moments-detail-panel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-play-toggle')));
    await tester.pump();
    expect(player.playCount, 1);
    await tester.tap(find.byKey(const ValueKey('detail-comment-field')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    clock.advance(const Duration(seconds: 9));
    await tester.pump();
    expect(find.byKey(const ValueKey('moments-detail-panel')), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('moments-detail-panel')), findsNothing);
    expect(find.byKey(const ValueKey('moment-row-panel')), findsNothing);
    expect(player.stopCount, 1);
    final refresh = tester.widget<IconButton>(
      find.byKey(const ValueKey('moments-discovery-refresh')),
    );
    expect(refresh.focusNode!.hasFocus, isTrue);
    expect(_announcementMessages(announcements), [
      'One Voice Moment expired and was removed.',
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    semantics.dispose();
  });

  testWidgets(
    'cached IndexedStack expiry stays silent and does not reclaim focus',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final announcements = _captureAnnouncements(tester);
      final hostKey = GlobalKey<_IndexedStackExpiryHostState>();
      final probeKey = GlobalKey<_IndexedStackExpiryProbeState>();
      final expiryTarget = FocusNode(debugLabel: 'expiry recovery target');
      final visibleControl = FocusNode(debugLabel: 'visible tab control');
      addTearDown(expiryTarget.dispose);
      addTearDown(visibleControl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: _IndexedStackExpiryHost(
            key: hostKey,
            probeKey: probeKey,
            expiryTarget: expiryTarget,
            visibleControl: visibleControl,
          ),
        ),
      );
      await tester.pump();
      visibleControl.requestFocus();
      await tester.pump();
      expect(visibleControl.hasFocus, isTrue);
      expect(probeKey.currentState!.surfaceIsVisible, isFalse);

      probeKey.currentState!.expire('hidden-transition');
      await tester.pump();
      expect(_announcementMessages(announcements), isEmpty);
      expect(expiryTarget.hasFocus, isFalse);
      expect(visibleControl.hasFocus, isTrue);

      hostKey.currentState!.showExpirySurface();
      await tester.pump();
      expect(probeKey.currentState!.surfaceIsVisible, isTrue);
      probeKey.currentState!
        ..expire('visible-transition')
        ..expire('visible-transition');
      await tester.pump();

      expect(expiryTarget.hasFocus, isTrue);
      expect(_announcementMessages(announcements), [
        'Visible Voice Moment expired.',
      ]);
      semantics.dispose();
    },
  );
}

class _IndexedStackExpiryHost extends StatefulWidget {
  const _IndexedStackExpiryHost({
    required this.probeKey,
    required this.expiryTarget,
    required this.visibleControl,
    super.key,
  });

  final GlobalKey<_IndexedStackExpiryProbeState> probeKey;
  final FocusNode expiryTarget;
  final FocusNode visibleControl;

  @override
  State<_IndexedStackExpiryHost> createState() =>
      _IndexedStackExpiryHostState();
}

class _IndexedStackExpiryHostState extends State<_IndexedStackExpiryHost> {
  var _index = 1;

  void showExpirySurface() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _IndexedStackExpiryProbe(
            key: widget.probeKey,
            expiryTarget: widget.expiryTarget,
          ),
          Center(
            child: FilledButton(
              focusNode: widget.visibleControl,
              onPressed: () {},
              child: const Text('Visible tab control'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndexedStackExpiryProbe extends StatefulWidget {
  const _IndexedStackExpiryProbe({required this.expiryTarget, super.key});

  final FocusNode expiryTarget;

  @override
  State<_IndexedStackExpiryProbe> createState() =>
      _IndexedStackExpiryProbeState();
}

class _IndexedStackExpiryProbeState extends State<_IndexedStackExpiryProbe> {
  final _announcer = MomentExpiryAnnouncer();

  bool get surfaceIsVisible => momentExpirySurfaceIsVisible(context);

  void expire(Object transition) {
    final previousFocus = FocusManager.instance.primaryFocus;
    _announcer.announce(
      context,
      transition: transition,
      message: 'Visible Voice Moment expired.',
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: widget.expiryTarget,
      previousFocus: previousFocus,
      force: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Focus(
        focusNode: widget.expiryTarget,
        child: const Text('Cached expiry surface'),
      ),
    );
  }
}
