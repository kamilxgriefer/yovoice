import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'support/material_icons_font.dart';

final _now = DateTime.utc(2026, 9, 11, 14);
const _capture = bool.fromEnvironment('YO_CAPTURE_VOICE_REDESIGN');

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

VoiceMoment _moment(String id, {String author = 'friend', int likes = 0}) =>
    VoiceMoment(
      id: id,
      authorId: author,
      authorName: 'Author $author',
      authorPhotoUrl: null,
      caption: 'Caption $id',
      audioUrl: null,
      durationSeconds: 24,
      likeCount: likes,
      commentCount: 2,
      isPublished: true,
      createdAt: _now.subtract(const Duration(hours: 1)),
      expiresAt: _now.add(const Duration(hours: 1)),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: true,
    );

class _Discovery implements MomentDiscoveryService {
  _Discovery(this.moments);

  List<VoiceMoment> moments;
  int loads = 0;
  Future<MomentDiscoveryFeed> Function()? load;
  final counters = StreamController<Map<String, MomentEngagement>>.broadcast();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = 60,
    int? seed,
  }) {
    loads += 1;
    return load?.call() ??
        Future.value(
          MomentDiscoveryFeed(
            moments: moments,
            fetchedCount: moments.length,
            drops: const {},
            seed: 7,
            poolExhausted: false,
          ),
        );
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({int poolSize = 60}) =>
      counters.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Feed implements HomeFeedService {
  List<VoiceMoment> social = [];
  final events = StreamController<List<VoiceMoment>>.broadcast();
  int listens = 0;
  int cancels = 0;
  final writes = <String>[];
  Future<void> Function()? writeLike;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.multi((sink) {
        listens++;
        sink.add(social);
        final subscription = events.stream.listen(
          sink.add,
          onError: sink.addError,
        );
        sink.onCancel = () {
          cancels++;
          return subscription.cancel();
        };
      }, isBroadcast: true);

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    writes.add('$momentId:$liked');
    await writeLike?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Moments implements MomentService {
  final requests = <String>[];
  final grants = <String, Completer<Uri>>{};
  List<VoiceMoment> mine = [];

  @override
  Stream<VoiceMoment> watchMoment(String momentId) =>
      Stream.value(_moment(momentId));

  @override
  Stream<List<VoiceMoment>> watchMyMoments() => Stream.value(mine);

  @override
  Stream<List<MomentComment>> watchComments(
    String momentId, {
    int limit = 80,
  }) => Stream.value(const []);

  @override
  Future<Uri> resolveMediaUri({required String momentId, String? commentId}) {
    requests.add(momentId);
    return grants[momentId]?.future ??
        Future.value(Uri.parse('https://example.invalid/$momentId.m4a'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Views implements MomentViewsService {
  final marked = <String>[];

  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(const {});

  @override
  Future<void> markViewed(String momentId) async => marked.add(momentId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements audio.AudioPlayer {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completions = StreamController<void>.broadcast();
  final commands = <String>[];
  Future<void> Function(String uri)? onPlay;
  Future<void> Function()? onStop;
  Future<void> Function()? onDispose;

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
    final uri = (source as audio.UrlSource).url;
    commands.add('play:$uri');
    await onPlay?.call(uri);
  }

  @override
  Future<void> pause() async => commands.add('pause');

  @override
  Future<void> resume() async => commands.add('resume');

  @override
  Future<void> stop() async {
    commands.add('stop');
    await onStop?.call();
  }

  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inMilliseconds}');

  @override
  Future<void> dispose() async {
    commands.add('dispose');
    await onDispose?.call();
  }

  Future<void> close() async {
    await positions.close();
    await durations.close();
    await completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  _Fixture({List<VoiceMoment>? items})
    : discovery = _Discovery(items ?? [_moment('a'), _moment('b')]);

  final auth = _Auth();
  final _Discovery discovery;
  final feed = _Feed();
  final moments = _Moments();
  final views = _Views();
  final player = _Player();
  final visible = ValueNotifier(true);
  final captureKey = GlobalKey();
  final navigatorKey = GlobalKey<NavigatorState>();
  final extraPlayers = <_Player>[];
  final details = <String>[];
  final detailSnapshots = <VoiceMoment>[];
  DateTime now = _now;
  int records = 0;
  int playersCreated = 0;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 1200),
    double scale = 1,
    bool light = false,
    bool polish = false,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [appRouteObserver],
        locale: Locale(polish ? 'pl' : 'en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: Scaffold(
            body: MomentsFeedView(
              discoveryService: discovery,
              feedService: feed,
              momentService: moments,
              viewsService: views,
              auth: auth,
              isVisible: visible,
              expiryClock: () => now,
              playerFactory: () {
                playersCreated += 1;
                if (playersCreated == 1) return player;
                final next = _Player();
                extraPlayers.add(next);
                return next;
              },
              onRecord: () => records++,
              onOpenDetail: (moment) {
                details.add(moment.id);
                detailSnapshots.add(moment);
              },
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await discovery.counters.close();
    await feed.events.close();
    await auth.events.close();
    await player.close();
    for (final next in extraPlayers) {
      await next.close();
    }
    visible.dispose();
  }
}

Future<void> _play(WidgetTester tester, String id) async {
  final control = find.byKey(ValueKey('moment-row-play-$id'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
}

Future<void> _filter(WidgetTester tester, MomentsFilter filter) async {
  final control = find.byKey(ValueKey('moments-filter-${filter.name}'));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

MomentDiscoveryFeed _page(
  List<VoiceMoment> moments, {
  Future<MomentDiscoveryFeed> Function()? next,
}) => MomentDiscoveryFeed(
  moments: moments,
  fetchedCount: moments.length,
  drops: const {},
  seed: 7,
  poolExhausted: next != null,
  nextCursor: next == null ? null : 'opaque.cursor.never-decoded',
  loadMore: next,
);

Future<void> _shoot(WidgetTester tester, _Fixture fixture, String name) async {
  if (!_capture) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'test/.screenshots/voice-redesign-author-2026-09-11/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await loadMaterialIconsFont();
  });
  late PublicIdentityRepository previousIdentity;

  setUp(() {
    previousIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() => PublicIdentityRepository.instance = previousIdentity);

  testWidgets(
    'Voice detail handoff uses current projection after pending release',
    (tester) async {
      final fixture = _Fixture();
      final released = Completer<void>();
      fixture.player.onDispose = () => released.future;
      fixture.feed.social = [_moment('a')];
      await fixture.pump(tester);
      try {
        await _filter(tester, MomentsFilter.following);
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('moment-row-title-a')));
        await tester.pump();
        fixture.feed.events.add([
          _moment('a').copyWith(caption: 'Current projection'),
        ]);
        await tester.pump();
        released.complete();
        await tester.pumpAndSettle();
        expect(fixture.detailSnapshots.single.caption, 'Current projection');
      } finally {
        if (!released.isCompleted) released.complete();
        await fixture.close(tester);
      }
    },
  );

  testWidgets('Voice queued auth ABA invalidates the prior grant epoch', (
    tester,
  ) async {
    final fixture = _Fixture();
    final grant = Completer<Uri>();
    fixture.moments.grants['a'] = grant;
    await fixture.pump(tester);
    try {
      await _play(tester, 'a');
      fixture.auth.switchTo(null);
      fixture.auth.switchTo('viewer');
      await tester.pump();
      grant.complete(Uri.parse('https://example.invalid/retired-account.m4a'));
      await tester.pumpAndSettle();
      expect(fixture.views.marked, isEmpty);
      expect(fixture.playersCreated, 0);
    } finally {
      if (!grant.isCompleted) {
        grant.complete(Uri.parse('https://example.invalid/a.m4a'));
      }
      await fixture.close(tester);
    }
  });

  testWidgets('Voice delayed switch stop settles before successor play', (
    tester,
  ) async {
    final fixture = _Fixture();
    final stop = Completer<void>();
    var stops = 0;
    await fixture.pump(tester);
    try {
      await _play(tester, 'a');
      await tester.pumpAndSettle();
      fixture.player.onStop = () {
        if (++stops != 1) return Future.value();
        return stop.future.then(
          (_) => fixture.player.commands.add('old-stop-effect'),
        );
      };
      await _play(tester, 'b');
      await tester.pump();
      expect(
        fixture.player.commands.where((value) => value.startsWith('play:')),
        hasLength(1),
        reason: 'An unresolved native stop must not reach a successor source.',
      );
      stop.complete();
      await tester.pumpAndSettle();
      expect(fixture.views.marked, ['a', 'b']);
      expect(
        fixture.player.commands.indexOf('old-stop-effect'),
        lessThan(
          fixture.player.commands.indexOf('play:https://example.invalid/b.m4a'),
        ),
      );
    } finally {
      if (!stop.isCompleted) stop.complete();
      await fixture.close(tester);
    }
  });

  testWidgets('Voice author chain can hand off to detail after it closes', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(tester);
    try {
      await tester.tap(find.byKey(const ValueKey('moment-row-chain-a')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('story-open-detail')));
      await tester.pumpAndSettle();
      expect(fixture.details, ['a']);
      expect(find.byKey(const ValueKey('story-open-detail')), findsNothing);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets('Voice records viewed only after successful current playback', (
    tester,
  ) async {
    final fixture = _Fixture();
    final grant = Completer<Uri>();
    final started = Completer<void>();
    fixture.moments.grants['a'] = grant;
    fixture.player.onPlay = (_) => started.future;
    await fixture.pump(tester);
    try {
      expect(
        tester.takeException(),
        isNull,
        reason: 'The fixture must render.',
      );
      await _play(tester, 'a');
      expect(fixture.views.marked, isEmpty, reason: 'A grant is not playback.');
      grant.complete(Uri.parse('https://example.invalid/a.m4a'));
      await tester.pump();
      expect(
        fixture.views.marked,
        isEmpty,
        reason: 'Pending play is not success.',
      );
      started.complete();
      await tester.pumpAndSettle();
      expect(fixture.views.marked, ['a']);
    } finally {
      if (!grant.isCompleted) {
        grant.complete(Uri.parse('https://example.invalid/a.m4a'));
      }
      if (!started.isCompleted) started.complete();
      await fixture.close(tester);
    }
  });

  testWidgets('Voice stale A grant failure cannot overwrite playing B', (
    tester,
  ) async {
    final fixture = _Fixture();
    final grant = Completer<Uri>();
    fixture.moments.grants['a'] = grant;
    await fixture.pump(tester);
    try {
      expect(
        tester.takeException(),
        isNull,
        reason: 'The fixture must render.',
      );
      await _play(tester, 'a');
      await _play(tester, 'b');
      await tester.pumpAndSettle();
      grant.completeError(StateError('private stale grant error'));
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('moment-row-play-b'));
      expect(
        find.descendant(
          of: control,
          matching: find.byIcon(Icons.pause_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.text('This Moment could not be played. Try again.'),
        findsNothing,
      );
      expect(fixture.views.marked, ['b']);
    } finally {
      if (!grant.isCompleted) {
        grant.complete(Uri.parse('https://example.invalid/a.m4a'));
      }
      await fixture.close(tester);
    }
  });

  testWidgets('Voice lazily builds one card per recording without autoplay', (
    tester,
  ) async {
    final fixture = _Fixture(
      items: [for (var index = 0; index < 80; index++) _moment('item_$index')],
    );
    await fixture.pump(tester, size: const Size(390, 844));
    try {
      final scroll = tester.widget<ListView>(
        find.byKey(const ValueKey('moments-feed-scroll')),
      );
      expect(scroll.childrenDelegate, isA<SliverChildBuilderDelegate>());
      expect(find.byType(MomentStoryStrip), findsNothing);
      expect(find.byType(MomentDetailPanel), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-item_79')), findsNothing);
      expect(fixture.playersCreated, 0);
      expect(fixture.views.marked, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'Voice shared player exposes actual progress pause seek and resume',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        fixture.player.durations.add(const Duration(seconds: 30));
        fixture.player.positions.add(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        expect(find.text('0:09 / 0:30'), findsOneWidget);
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        expect(fixture.player.commands, contains('pause'));
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('moment-row-progress-a')),
        );
        slider.onChanged!(14000);
        await tester.pump();
        expect(fixture.player.commands, contains('seek:14000'));
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        expect(fixture.player.commands, contains('resume'));
        expect(fixture.moments.requests, [
          'a',
          'a',
        ], reason: 'Resume renews access.');
        expect(fixture.views.marked, ['a']);
        await _play(tester, 'b');
        await tester.pumpAndSettle();
        expect(fixture.playersCreated, 1);
        expect(fixture.views.marked, ['a', 'b']);
        expect(find.text('0:14 / 0:30'), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('Voice native A completion cannot play over B or mark stale A', (
    tester,
  ) async {
    final fixture = _Fixture();
    final oldPlay = Completer<void>();
    fixture.player.onPlay = (uri) =>
        uri.endsWith('/a.m4a') ? oldPlay.future : Future.value();
    await fixture.pump(tester);
    try {
      await _play(tester, 'a');
      await _play(tester, 'b');
      await tester.pump();
      expect(
        fixture.player.commands.where((value) => value.startsWith('play:')),
        hasLength(1),
      );
      expect(fixture.views.marked, isEmpty);
      oldPlay.complete();
      await tester.pumpAndSettle();
      final plays = fixture.player.commands
          .where((value) => value.startsWith('play:'))
          .toList();
      expect(plays, [
        'play:https://example.invalid/a.m4a',
        'play:https://example.invalid/b.m4a',
      ]);
      expect(fixture.views.marked, ['b']);
      final lastPlay = fixture.player.commands.lastIndexOf(plays.last);
      expect(
        fixture.player.commands.skip(lastPlay + 1),
        isNot(contains('stop')),
      );
    } finally {
      if (!oldPlay.isCompleted) oldPlay.complete();
      await fixture.close(tester);
    }
  });

  testWidgets('Voice late native A failure cannot clear successful B', (
    tester,
  ) async {
    final fixture = _Fixture();
    final oldPlay = Completer<void>();
    fixture.player.onPlay = (uri) =>
        uri.endsWith('/a.m4a') ? oldPlay.future : Future.value();
    await fixture.pump(tester);
    try {
      await _play(tester, 'a');
      await _play(tester, 'b');
      oldPlay.completeError(StateError('private failed old decoder'));
      await tester.pumpAndSettle();
      expect(fixture.views.marked, ['b']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-play-b')),
          matching: find.byIcon(Icons.pause_rounded),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private failed'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (!oldPlay.isCompleted) oldPlay.complete();
      await fixture.close(tester);
    }
  });

  testWidgets(
    'Voice hide fences pending grant and never allocates a hidden player',
    (tester) async {
      final fixture = _Fixture();
      final grant = Completer<Uri>();
      fixture.moments.grants['a'] = grant;
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        fixture.visible.value = false;
        await tester.pump();
        grant.complete(Uri.parse('https://example.invalid/private.m4a'));
        await tester.pumpAndSettle();
        expect(fixture.playersCreated, 0);
        expect(fixture.views.marked, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!grant.isCompleted) {
          grant.complete(Uri.parse('https://example.invalid/a.m4a'));
        }
        await fixture.close(tester);
      }
    },
  );

  testWidgets('Voice UID ABA rejects the previous account epoch grant', (
    tester,
  ) async {
    final fixture = _Fixture();
    final grant = Completer<Uri>();
    fixture.moments.grants['a'] = grant;
    await fixture.pump(tester);
    try {
      await _play(tester, 'a');
      fixture.auth.switchTo('other');
      await tester.pump();
      fixture.auth.switchTo('viewer');
      await tester.pumpAndSettle();
      grant.complete(Uri.parse('https://example.invalid/stale-a.m4a'));
      await tester.pumpAndSettle();
      expect(fixture.playersCreated, 0);
      expect(fixture.views.marked, isEmpty);
      fixture.moments.grants.remove('a');
      await _play(tester, 'a');
      await tester.pumpAndSettle();
      expect(fixture.views.marked, ['a']);
    } finally {
      if (!grant.isCompleted) {
        grant.complete(Uri.parse('https://example.invalid/a.m4a'));
      }
      await fixture.close(tester);
    }
  });

  testWidgets(
    'Voice account exit clears the cached feed without a new unauthenticated read',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        final loads = fixture.discovery.loads;
        fixture.auth.switchTo(null);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment-row-a')), findsNothing);
        expect(
          find.byKey(const ValueKey('moments-discovery-error')),
          findsOneWidget,
        );
        expect(fixture.discovery.loads, loads);
        expect(fixture.player.commands, contains('dispose'));
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice background release is single owner and return never autoplays',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        fixture.visible.value = false;
        await tester.pumpAndSettle();
        expect(
          fixture.player.commands.where((value) => value == 'dispose'),
          hasLength(1),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        fixture.visible.value = true;
        await tester.pumpAndSettle();
        expect(fixture.playersCreated, 1);
        expect(
          fixture.player.commands.where((value) => value.startsWith('play:')),
          hasLength(1),
        );
        await _play(tester, 'b');
        await tester.pumpAndSettle();
        expect(fixture.playersCreated, 2);
        expect(
          fixture.extraPlayers.single.commands,
          contains('play:https://example.invalid/b.m4a'),
        );
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice route coverage releases audio and return preserves no autoplay',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        unawaited(
          fixture.navigatorKey.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Covered route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fixture.player.commands, contains('dispose'));
        fixture.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(
          fixture.player.commands.where((value) => value.startsWith('play:')),
          hasLength(1),
        );
        expect(find.byKey(const ValueKey('moment-row-a')), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('Voice scrolling active card out releases shared audio', (
    tester,
  ) async {
    final fixture = _Fixture(
      items: [for (var i = 0; i < 20; i++) _moment('a$i')],
    );
    await fixture.pump(tester, size: const Size(390, 844));
    try {
      await _play(tester, 'a0');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('moments-feed-scroll')),
        const Offset(0, -1800),
      );
      await tester.pumpAndSettle();
      expect(fixture.player.commands, contains('dispose'));
      expect(fixture.playersCreated, 1);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'Voice expiry removes recording and releases its audio without another snapshot',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        fixture.now = _now.add(const Duration(hours: 2));
        await tester.pump(const Duration(hours: 2));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment-row-a')), findsNothing);
        expect(fixture.player.commands, contains('dispose'));
        expect(fixture.playersCreated, 1);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice playback failure is safe local retry and is never a view',
    (tester) async {
      final fixture = _Fixture();
      fixture.player.onPlay = (_) =>
          Future.error(StateError('secret signed token in decoder'));
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        expect(fixture.views.marked, isEmpty);
        expect(find.textContaining('secret signed'), findsNothing);
        expect(
          find.byKey(const ValueKey('moment-row-play-retry-a')),
          findsOneWidget,
        );
        fixture.player.onPlay = null;
        await tester.tap(find.byKey(const ValueKey('moment-row-play-retry-a')));
        await tester.pumpAndSettle();
        expect(fixture.views.marked, ['a']);
        expect(fixture.playersCreated, 1);
        expect(
          find.byKey(const ValueKey('moment-row-play-retry-a')),
          findsNothing,
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice details callback runs once only after the player is released',
    (tester) async {
      final fixture = _Fixture();
      final released = Completer<void>();
      fixture.player.onDispose = () => released.future;
      await fixture.pump(tester);
      try {
        await _play(tester, 'a');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('moment-row-title-a')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('moment-row-title-a')));
        expect(fixture.details, isEmpty);
        released.complete();
        await tester.pumpAndSettle();
        expect(fixture.details, ['a']);
        expect(
          fixture.player.commands.where((value) => value == 'dispose'),
          hasLength(1),
        );
      } finally {
        if (!released.isCompleted) released.complete();
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice live counters and optimistic likes keep frozen engagement ordering',
    (tester) async {
      final fixture = _Fixture(
        items: [_moment('a', likes: 2), _moment('b', likes: 1)],
      );
      final write = Completer<void>();
      fixture.feed.writeLike = () => write.future;
      await fixture.pump(tester);
      try {
        await _filter(tester, MomentsFilter.mostEngaged);
        final before = tester
            .getTopLeft(find.byKey(const ValueKey('moment-row-a')))
            .dy;
        fixture.discovery.counters.add({
          'a': const MomentEngagement(likeCount: 3, commentCount: 4),
          'b': const MomentEngagement(likeCount: 99, commentCount: 99),
        });
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('moment-row-a'))).dy,
          before,
        );
        await tester.tap(find.byKey(const ValueKey('moment-row-like-a')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('moment-row-like-a')));
        expect(fixture.feed.writes, ['a:true']);
        write.completeError(StateError('secret backend failure'));
        await tester.pumpAndSettle();
        expect(find.text('Likes: 3'), findsOneWidget);
        expect(find.textContaining('secret backend'), findsNothing);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('moment-row-a'))).dy,
          before,
        );
      } finally {
        if (!write.isCompleted) write.complete();
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice refresh rejects late older load and keeps real retry scoped',
    (tester) async {
      final fixture = _Fixture();
      final old = Completer<MomentDiscoveryFeed>();
      fixture.discovery.load = () => old.future;
      await fixture.pump(tester, settle: false);
      try {
        expect(
          find.byKey(const ValueKey('moments-discovery-loading')),
          findsOneWidget,
        );
        fixture.discovery.load = () async => _page([_moment('new')]);
        await tester.tap(
          find.byKey(const ValueKey('moments-discovery-refresh')),
        );
        await tester.pumpAndSettle();
        old.complete(_page([_moment('stale')]));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment-row-new')), findsOneWidget);
        expect(find.byKey(const ValueKey('moment-row-stale')), findsNothing);
        expect(fixture.discovery.loads, 2);
        expect(fixture.feed.listens - fixture.feed.cancels, 1);
      } finally {
        if (!old.isCompleted) old.complete(_page([]));
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice denied refresh removes cache while error differs from empty',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      try {
        fixture.discovery.load = () => Future.error(
          FirebaseAuthException(
            code: 'permission-denied',
            message: 'private root',
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('moments-discovery-refresh')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment-row-a')), findsNothing);
        expect(
          find.byKey(const ValueKey('moments-discovery-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('moments-discovery-empty')),
          findsNothing,
        );
        expect(find.textContaining('private root'), findsNothing);
        fixture.discovery.load = () async => _page([_moment('recovered')]);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-row-recovered')),
          findsOneWidget,
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'Voice Following denial clears old social cache and retry preserves own draft',
    (tester) async {
      final fixture = _Fixture();
      fixture.feed.social = [_moment('social')];
      fixture.moments.mine = [_moment('mine', author: 'viewer')];
      await fixture.pump(tester);
      try {
        await _filter(tester, MomentsFilter.following);
        expect(find.byKey(const ValueKey('moment-row-social')), findsOneWidget);
        fixture.feed.events.addError(
          FirebaseAuthException(code: 'permission-denied'),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('moment-row-social')), findsNothing);
        expect(
          find.byKey(const ValueKey('moments-discovery-error')),
          findsOneWidget,
        );
        fixture.feed.social = [_moment('social-new')];
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-row-social-new')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('moment-row-mine')), findsOneWidget);
        expect(fixture.feed.listens - fixture.feed.cancels, 1);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('Voice filtered empty page retains its opaque next-page action', (
    tester,
  ) async {
    final fixture = _Fixture();
    var pages = 0;
    fixture.discovery.load = () async => _page(
      [],
      next: () async {
        pages++;
        return _page([_moment('next')]);
      },
    );
    await fixture.pump(tester);
    try {
      expect(find.byKey(const ValueKey('moments-load-more')), findsOneWidget);
      expect(find.text('No Voice Moments yet'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('moments-load-more')));
      await tester.pumpAndSettle();
      expect(pages, 1);
      expect(find.byKey(const ValueKey('moment-row-next')), findsOneWidget);
    } finally {
      await fixture.close(tester);
    }
  });

  for (final width in [320.0, 390.0, 430.0, 768.0, 1100.0, 1440.0, 1920.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final light in [false, true]) {
        testWidgets('Voice card render $width / $scale / light=$light', (
          tester,
        ) async {
          final fixture = _Fixture(
            items: [
              _moment('long').copyWith(
                authorName: 'Aleksandra Magdalena Nowak',
                caption:
                    'Krótka historia o tym, co dziś było ważne. Rozmowa może zacząć się od jednego zdania — a dalszą część przeczytasz i usłyszysz w szczegółach.',
              ),
              _moment('second'),
            ],
          );
          await fixture.pump(
            tester,
            size: Size(width, 1000),
            scale: scale,
            light: light,
            polish: true,
          );
          try {
            expect(tester.takeException(), isNull);
            expect(fixture.playersCreated, 0);
            expect(find.byType(MomentStoryStrip), findsNothing);
            await _shoot(
              tester,
              fixture,
              'populated-${light ? 'pearl' : 'dark'}-${width.toInt()}-${scale.toInt()}x',
            );
            await tester.drag(
              find.byKey(const ValueKey('moments-feed-scroll')),
              const Offset(0, -480),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await _shoot(
              tester,
              fixture,
              'scrolled-${light ? 'pearl' : 'dark'}-${width.toInt()}-${scale.toInt()}x',
            );
          } finally {
            await fixture.close(tester);
          }
        });
      }
    }
  }

  for (final phase in ['empty', 'loading', 'error', 'denied']) {
    for (final width in [320.0, 1440.0]) {
      testWidgets('Voice $phase at $width and large text stays actionable', (
        tester,
      ) async {
        final fixture = _Fixture(items: []);
        final loading = Completer<MomentDiscoveryFeed>();
        fixture.discovery.load = switch (phase) {
          'loading' => () => loading.future,
          'error' => () => Future.error(StateError('private runtime stack')),
          'denied' => () => Future.error(
            FirebaseAuthException(code: 'permission-denied'),
          ),
          _ => () async => _page([]),
        };
        await fixture.pump(
          tester,
          size: Size(width, 800),
          scale: 2,
          polish: true,
          settle: phase != 'loading',
        );
        try {
          expect(tester.takeException(), isNull);
          expect(find.textContaining('private runtime'), findsNothing);
          await _shoot(tester, fixture, '$phase-dark-${width.toInt()}-2x');
          if (phase == 'empty') {
            await tester.ensureVisible(find.text('Nagraj Moment'));
            await tester.tap(find.text('Nagraj Moment'));
            expect(fixture.records, 1);
          }
        } finally {
          if (!loading.isCompleted) loading.complete(_page([]));
          await fixture.close(tester);
        }
      });
    }
  }
}
