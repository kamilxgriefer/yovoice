import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

// Independent controller-boundary tests, not proof of audible device playback.
// Unlike a command log, this fake applies each native effect when its Future
// settles: a delayed stop really can overwrite a later play unless serialized.
final _time = DateTime.utc(2026, 9, 11, 14);

VoiceMoment _recording(String id, {String author = 'friend'}) => VoiceMoment(
  id: id,
  authorId: author,
  authorName: 'Private author $id',
  authorPhotoUrl: null,
  caption: 'Private caption $id',
  audioUrl: null,
  durationSeconds: 24,
  likeCount: 0,
  commentCount: 0,
  isPublished: true,
  createdAt: _time.subtract(const Duration(minutes: 5)),
  expiresAt: _time.add(const Duration(hours: 1)),
  schemaVersion: 2,
  status: 'published',
  hasAuthorizedMedia: true,
  reportReceipt: 'synthetic-receipt-$id',
);

MomentDiscoveryFeed _page(List<VoiceMoment> items) => MomentDiscoveryFeed(
  moments: items,
  fetchedCount: items.length,
  drops: const {},
  seed: 41,
  poolExhausted: false,
);

class _QueuedAuth extends MockFirebaseAuth {
  User? user = MockUser(uid: 'viewer');
  final events = StreamController<User?>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => events.stream;

  void setAccount(String? uid) {
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
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = 60,
    int? seed,
  }) {
    loads++;
    return onLoad?.call() ?? Future.value(_page(items));
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      engagement.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SocialFeed implements HomeFeedService {
  List<VoiceMoment> items = [];
  final changes = StreamController<List<VoiceMoment>>.broadcast();

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.multi((sink) {
        sink.add(items);
        final subscription = changes.stream.listen(
          sink.add,
          onError: sink.addError,
        );
        sink.onCancel = subscription.cancel;
      }, isBroadcast: true);

  void replace(List<VoiceMoment> next) {
    items = next;
    changes.add(next);
  }

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Moments implements MomentService {
  final requested = <String>[];
  final grants = <String, Completer<Uri>>{};
  List<VoiceMoment> mine = [];
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

  void replaceMine(List<VoiceMoment> next) {
    mine = next;
    mineChanges.add(next);
  }

  @override
  Future<Uri> resolveMediaUri({required String momentId, String? commentId}) {
    requested.add(momentId);
    return grants[momentId]?.future ?? Future.value(_media(momentId));
  }

  @override
  Stream<List<MomentComment>> watchComments(
    String momentId, {
    int limit = 80,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uri _media(String id) => Uri.parse('https://example.invalid/qa-$id.m4a');

class _Views implements MomentViewsService {
  final ids = <String>[];

  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(const {});

  @override
  Future<void> markViewed(String momentId) async => ids.add(momentId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  List<String> get audible => [
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
  Future<void> Function(String source)? playBarrier;
  Future<void> Function(int call)? stopBarrier;
  Future<void> Function(int call)? disposeBarrier;
  String? loadedSource;
  String? audibleSource;
  bool allocated = false;
  bool disposed = false;
  int stopCalls = 0;
  int disposeCalls = 0;
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
    await playBarrier?.call(url);
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
    final call = ++disposeCalls;
    await disposeBarrier?.call(call);
    audibleSource = null;
    disposed = true;
    driver.effects.add('$id:disposed:$call');
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

class _Harness {
  _Harness({List<VoiceMoment>? items})
    : discovery = _Discovery(items ?? [_recording('a'), _recording('b')]) {
    first = driver.makePlayer();
  }

  final auth = _QueuedAuth();
  final _Discovery discovery;
  final feed = _SocialFeed();
  final moments = _Moments();
  final views = _Views();
  final driver = _NativeDriver();
  late final _NativePlayer first;
  final visible = ValueNotifier(true);
  final navigator = GlobalKey<NavigatorState>();
  final opened = <VoiceMoment>[];
  final gates = <Completer<void>>[];
  DateTime now = _time;
  int creations = 0;

  Completer<void> gate() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate;
  }

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver],
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: MomentsFeedView(
            onRecord: () {},
            auth: auth,
            discoveryService: discovery,
            feedService: feed,
            momentService: moments,
            viewsService: views,
            isVisible: visible,
            expiryClock: () => now,
            playerFactory: () {
              final player = creations++ == 0 ? first : driver.makePlayer();
              player.allocated = true;
              driver.observe();
              return player;
            },
            onOpenDetail: opened.add,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    for (final player in driver.players) {
      player.playBarrier = null;
      player.stopBarrier = null;
      player.disposeBarrier = null;
    }
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final entry in moments.grants.entries) {
      if (!entry.value.isCompleted) entry.value.complete(_media(entry.key));
    }
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
  final control = find.byKey(ValueKey('moment-row-play-$id'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
}

Future<void> _following(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('moments-filter-following')));
  await tester.pumpAndSettle();
}

Future<void> _refresh(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('moments-discovery-refresh')));
  await tester.pumpAndSettle();
}

void main() {
  late PublicIdentityRepository previousIdentity;
  setUp(() {
    previousIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });
  tearDown(() => PublicIdentityRepository.instance = previousIdentity);

  testWidgets('independent Voice queued UID ABA retires an outstanding grant', (
    tester,
  ) async {
    final h = _Harness();
    final grant = Completer<Uri>();
    h.moments.grants['a'] = grant;
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      h.discovery.items = [];
      h.auth.setAccount(null);
      h.auth.setAccount('viewer');
      // Intentionally NO await/pump between auth events: currentUser is A
      // again before the first queued event is delivered.
      await tester.pumpAndSettle();
      grant.complete(_media('a'));
      await tester.pumpAndSettle();
      expect(
        h.creations,
        0,
        reason: 'The retired epoch must not allocate audio.',
      );
      expect(h.views.ids, isEmpty);
      expect(find.text('Private caption a'), findsNothing);
      expect(h.discovery.loads, greaterThan(1));
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'independent Voice queued UID ABA releases current native owner',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      try {
        await _tapPlay(tester, 'a');
        await tester.pumpAndSettle();
        expect(h.driver.audible, [_media('a').toString()]);
        h.discovery.items = [];
        h.auth.setAccount('other');
        h.auth.setAccount('viewer');
        await tester.pumpAndSettle();
        expect(h.driver.audible, isEmpty);
        expect(h.first.disposed, isTrue);
        expect(find.text('Private caption a'), findsNothing);
        expect(
          h.creations,
          1,
          reason: 'Account return cannot auto-create audio.',
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('independent Voice auth stream error removes content and audio', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      await tester.pumpAndSettle();
      h.auth.events.addError(
        FirebaseAuthException(
          code: 'network-request-failed',
          message: 'private-auth-diagnostic',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Auth errors are handled.',
      );
      expect(h.driver.audible, isEmpty);
      expect(h.first.disposed, isTrue);
      expect(find.text('Private caption a'), findsNothing);
      expect(find.textContaining('private-auth-diagnostic'), findsNothing);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('independent Voice late switch stop cannot overwrite B play', (
    tester,
  ) async {
    final h = _Harness();
    final stopped = h.gate();
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      await tester.pumpAndSettle();
      final heldStop = h.first.stopCalls + 1;
      h.first.stopBarrier = (call) =>
          call == heldStop ? stopped.future : Future.value();
      await _tapPlay(tester, 'b');
      await tester.pump();
      expect(
        h.first.playCalls,
        [_media('a').toString()],
        reason:
            'B must wait for every prior native stop, not just a second stop.',
      );
      expect(h.views.ids, ['a']);
      stopped.complete();
      await tester.pumpAndSettle();
      expect(h.driver.audible, [_media('b').toString()]);
      expect(h.views.ids, ['a', 'b']);
      expect(
        h.driver.effects.indexOf('0:stop-settled:$heldStop'),
        lessThan(h.driver.effects.indexOf('0:play-start:${_media('b')}')),
      );
      expect(h.driver.maximumOwners, 1);
      expect(h.driver.overlapped, isFalse);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('independent Voice late A play settles and is cleaned before B', (
    tester,
  ) async {
    final h = _Harness();
    final played = h.gate();
    h.first.playBarrier = (url) =>
        url == _media('a').toString() ? played.future : Future.value();
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      await _tapPlay(tester, 'b');
      expect(h.first.playCalls, [_media('a').toString()]);
      expect(h.driver.audible, isEmpty);
      expect(h.views.ids, isEmpty);
      played.complete();
      await tester.pumpAndSettle();
      expect(h.driver.audible, [_media('b').toString()]);
      expect(h.views.ids, ['b']);
      final oldCompletion = h.driver.effects.indexOf(
        '0:play-settled:${_media('a')}',
      );
      final nextStart = h.driver.effects.indexOf('0:play-start:${_media('b')}');
      expect(nextStart, greaterThan(oldCompletion));
      expect(
        h.driver.effects.sublist(oldCompletion + 1, nextStart),
        anyElement(startsWith('0:stop-settled:')),
      );
      expect(h.driver.maximumOwners, 1);
    } finally {
      await h.close(tester);
    }
  });

  for (final boundary in ['hidden', 'background', 'route', 'expiry']) {
    testWidgets(
      'independent Voice $boundary retires an in-flight native play',
      (tester) async {
        final h = _Harness(
          items: [
            _recording(
              'a',
            ).copyWith(expiresAt: _time.add(const Duration(seconds: 2))),
          ],
        );
        final played = h.gate();
        h.first.playBarrier = (_) => played.future;
        await h.mount(tester);
        try {
          await _tapPlay(tester, 'a');
          switch (boundary) {
            case 'hidden':
              h.visible.value = false;
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
            case 'route':
              unawaited(
                h.navigator.currentState!.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Foreign route')),
                  ),
                ),
              );
            case 'expiry':
              h.now = _time.add(const Duration(seconds: 3));
              await tester.pump(const Duration(seconds: 3));
          }
          await tester.pump();
          played.complete();
          await tester.pumpAndSettle();
          expect(h.views.ids, isEmpty);
          expect(h.driver.audible, isEmpty);
          expect(h.first.disposed, isTrue);
          expect(h.first.disposeCalls, 1);
          expect(h.creations, 1);
          if (boundary == 'route') {
            expect(find.text('Foreign route'), findsOneWidget);
            expect(h.navigator.currentState!.canPop(), isTrue);
          }
          if (boundary == 'expiry') {
            expect(find.text('Private caption a'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await h.close(tester);
          if (boundary == 'background') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
          }
        }
      },
    );
  }

  testWidgets('independent Voice uncertain dispose prevents a second owner', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      await tester.pumpAndSettle();
      h.first.disposeBarrier = (_) async =>
          throw StateError('uncertain-release');
      h.visible.value = false;
      await tester.pumpAndSettle();
      expect(h.first.disposed, isFalse);
      h.visible.value = true;
      await tester.pumpAndSettle();
      await _tapPlay(tester, 'b');
      await tester.pumpAndSettle();
      expect(h.creations, 1);
      expect(h.first.playCalls, [_media('a').toString()]);
      expect(h.driver.maximumOwners, 1);
      expect(h.driver.audible, isEmpty);
      h.first.disposeBarrier = null;
      await _tapPlay(tester, 'b');
      await tester.pumpAndSettle();
      expect(h.first.disposed, isTrue);
      expect(h.creations, 2);
      expect(h.driver.maximumOwners, 1);
      expect(h.driver.audible, [_media('b').toString()]);
      expect(h.driver.overlapped, isFalse);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'independent Voice recovery release cannot adopt a new account intent',
    (tester) async {
      final h = _Harness();
      final released = h.gate();
      await h.mount(tester);
      try {
        await _tapPlay(tester, 'a');
        await tester.pumpAndSettle();
        h.first.disposeBarrier = (_) async =>
            throw StateError('uncertain-release');
        h.visible.value = false;
        await tester.pumpAndSettle();
        expect(h.first.disposed, isFalse);
        h.visible.value = true;
        await tester.pumpAndSettle();

        // This tap belongs to the old signed-in lifetime. It waits for the
        // unresolved native owner to be released before requesting B's grant.
        h.first.disposeBarrier = (_) => released.future;
        await _tapPlay(tester, 'b');
        expect(h.moments.requested, ['a']);
        expect(h.first.disposeCalls, greaterThan(1));
        h.auth.setAccount(null);
        h.auth.setAccount('viewer');
        await tester.pumpAndSettle();
        expect(find.text('Private caption b'), findsOneWidget);

        released.complete();
        await tester.pumpAndSettle();
        expect(
          h.moments.requested,
          ['a'],
          reason:
              'A retired tap cannot capture the new account epoch after await.',
        );
        expect(h.creations, 1);
        expect(h.first.disposed, isTrue);
        expect(h.driver.audible, isEmpty);
        expect(h.views.ids, ['a']);

        // Recovery is not a permanent disable: a fresh intent may now play B.
        await _tapPlay(tester, 'b');
        await tester.pumpAndSettle();
        expect(h.moments.requested, ['a', 'b']);
        expect(h.driver.audible, [_media('b').toString()]);
        expect(h.creations, 2);
        expect(h.driver.maximumOwners, 1);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'independent Voice current media withdrawal fences pending grant',
    (tester) async {
      final h = _Harness();
      final old = _recording('social');
      h.feed.items = [old];
      final grant = Completer<Uri>();
      h.moments.grants[old.id] = grant;
      await h.mount(tester);
      try {
        await _following(tester);
        await _tapPlay(tester, old.id);
        h.feed.replace([old.copyWith(hasAuthorizedMedia: false)]);
        await tester.pump();
        grant.complete(_media(old.id));
        await tester.pumpAndSettle();
        expect(
          h.creations,
          0,
          reason: 'Use current media eligibility after await.',
        );
        expect(h.views.ids, isEmpty);
        expect(h.driver.audible, isEmpty);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'independent Voice current own draft cannot inherit published play',
    (tester) async {
      final h = _Harness();
      final old = _recording('mine', author: 'viewer');
      h.moments.mine = [old];
      final grant = Completer<Uri>();
      h.moments.grants[old.id] = grant;
      await h.mount(tester);
      try {
        await _following(tester);
        await _tapPlay(tester, old.id);
        h.moments.replaceMine([
          old.copyWith(isPublished: false, status: 'draft'),
        ]);
        await tester.pump();
        grant.complete(_media(old.id));
        await tester.pumpAndSettle();
        expect(h.creations, 0);
        expect(h.views.ids, isEmpty);
        expect(h.driver.audible, isEmpty);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('independent Voice detail cannot receive retired metadata', (
    tester,
  ) async {
    final h = _Harness();
    final old = _recording('social');
    h.feed.items = [old];
    final released = h.gate();
    await h.mount(tester);
    try {
      await _following(tester);
      await _tapPlay(tester, old.id);
      await tester.pumpAndSettle();
      h.first.disposeBarrier = (_) => released.future;
      await tester.tap(find.byKey(ValueKey('moment-row-title-${old.id}')));
      await tester.pump();
      expect(h.opened, isEmpty);
      final current = old.copyWith(
        caption: 'Current permitted caption',
        authorName: 'Current permitted name',
        reportReceipt: 'current-synthetic-receipt',
      );
      h.feed.replace([current]);
      await tester.pump();
      released.complete();
      await tester.pumpAndSettle();
      // Safe refusal is valid; any actual destination must use fresh metadata.
      expect(h.opened, hasLength(lessThanOrEqualTo(1)));
      for (final delivered in h.opened) {
        expect(delivered.caption, current.caption);
        expect(delivered.authorName, current.authorName);
        expect(delivered.reportReceipt, current.reportReceipt);
      }
      expect(find.text('Private caption social'), findsNothing);
      expect(h.driver.audible, isEmpty);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'independent Voice old discovery completion cannot fill new account',
    (tester) async {
      final h = _Harness();
      final oldRead = Completer<MomentDiscoveryFeed>();
      h.discovery.onLoad = () => oldRead.future;
      await h.mount(tester, settle: false);
      try {
        h.discovery.onLoad = () async => _page([_recording('current-b')]);
        h.auth.setAccount('account-b');
        await tester.pumpAndSettle();
        expect(find.text('Private caption current-b'), findsOneWidget);
        oldRead.complete(_page([_recording('retired-a')]));
        await tester.pumpAndSettle();
        expect(find.text('Private caption current-b'), findsOneWidget);
        expect(find.text('Private caption retired-a'), findsNothing);
        expect(h.creations, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!oldRead.isCompleted) oldRead.complete(_page(const []));
        await h.close(tester);
      }
    },
  );

  testWidgets('independent Voice denied reload removes cache and old grant', (
    tester,
  ) async {
    final h = _Harness();
    final grant = Completer<Uri>();
    h.moments.grants['a'] = grant;
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      h.discovery.onLoad = () async => throw FirebaseAuthException(
        code: 'permission-denied',
        message: 'private-read-diagnostic',
      );
      await _refresh(tester);
      grant.complete(_media('a'));
      await tester.pumpAndSettle();
      expect(find.text('Private caption a'), findsNothing);
      expect(find.textContaining('private-read-diagnostic'), findsNothing);
      expect(h.creations, 0);
      expect(h.views.ids, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'independent Voice disposed player events cannot control successor',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      try {
        await _tapPlay(tester, 'a');
        await tester.pumpAndSettle();
        h.visible.value = false;
        await tester.pumpAndSettle();
        h.visible.value = true;
        await tester.pumpAndSettle();
        await _tapPlay(tester, 'b');
        await tester.pumpAndSettle();
        expect(h.creations, 2);
        final current = h.driver.players.last;
        current.durations.add(const Duration(seconds: 24));
        current.positions.add(const Duration(seconds: 7));
        await tester.pump();
        h.first.positions.add(const Duration(seconds: 21));
        h.first.durations.add(const Duration(seconds: 999));
        h.first.completions.add(null);
        await tester.pump();
        expect(find.text('0:07 / 0:24'), findsOneWidget);
        expect(find.textContaining('16:39'), findsNothing);
        expect(h.driver.audible, [_media('b').toString()]);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('moment-row-play-b')),
            matching: find.byIcon(Icons.pause_rounded),
          ),
          findsOneWidget,
        );
        expect(h.driver.maximumOwners, 1);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('independent Voice pending detail does not pop a foreign route', (
    tester,
  ) async {
    final h = _Harness();
    final released = h.gate();
    await h.mount(tester);
    try {
      await _tapPlay(tester, 'a');
      await tester.pumpAndSettle();
      h.first.disposeBarrier = (_) => released.future;
      await tester.tap(find.byKey(const ValueKey('moment-row-title-a')));
      await tester.pump();
      unawaited(
        h.navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Foreign route')),
          ),
        ),
      );
      await tester.pump();
      released.complete();
      await tester.pumpAndSettle();
      expect(h.opened, isEmpty);
      expect(find.text('Foreign route'), findsOneWidget);
      expect(h.navigator.currentState!.canPop(), isTrue);
      expect(h.first.disposeCalls, 1);
      expect(h.driver.audible, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close(tester);
    }
  });
}
