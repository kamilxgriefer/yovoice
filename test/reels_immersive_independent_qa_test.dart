// Independent QA: exercises production MomentsScreen and VideoPlayerController
// against a deterministic platform boundary. No real decoder, media, network,
// OS sharing or device-audio claim is made by this test.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
// The installed video_player plugin owns this locked test-only platform seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_overlay_measure.dart';

const _capture = bool.fromEnvironment('QA_CAPTURE_IMMERSIVE_REELS');
const _caption =
    'A deliberately long caption with a genuine reachable expansion. '
    'The controls and authored links must remain available at large text sizes.';
const _dockKey = ValueKey('independent-reels-retained-dock');
int _fixtureSequence = 0;

class _Engine {
  _Engine(this.uri);
  final String uri;
  // Match an asynchronously cancellable platform event subscription. A plain
  // controller without onCancel returns Dart's root-zone completed Future;
  // awaiting it from FakeAsync never drains into the widget clock, so the
  // real VideoPlayerController.dispose would stall before platform.dispose.
  final events = StreamController<VideoEvent>(onCancel: () async {});
  Duration position = Duration.zero;
  bool playing = false;
  bool disposed = false;
  double volume = 0;
  final seeks = <Duration>[];
}

/// Only the native decoder boundary is substituted. The app still constructs,
/// retains and disposes its real VideoPlayerController and playback coordinator.
class _VideoPlatform extends VideoPlayerPlatform {
  final engines = <int, _Engine>{};
  int failuresRemaining = 0;
  int _nextId = 1;
  final mixRequests = <bool>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final engine = _Engine(options.dataSource.uri!);
    engines[id] = engine;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      engine.events.addError(
        PlatformException(code: 'VideoError', message: 'QA decoder refusal'),
      );
    } else {
      engine.events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(720, 1280),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      engines[playerId]!.events.stream;

  @override
  Future<void> dispose(int playerId) async {
    final engine = engines[playerId]!;
    engine.disposed = true;
    engine.playing = false;
    await engine.events.close();
  }

  @override
  Future<void> play(int playerId) async => engines[playerId]!.playing = true;

  @override
  Future<void> pause(int playerId) async => engines[playerId]!.playing = false;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final engine = engines[playerId]!;
    engine.position = position;
    engine.seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      engines[playerId]!.position;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      engines[playerId]!.volume = volume;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async =>
      mixRequests.add(mixWithOthers);

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => DecoratedBox(
    key: ValueKey('independent-native-player-${options.playerId}'),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFF4F0E8), Color(0xFF527B83), Color(0xFF213147)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );
}

class _Fixture {
  _Fixture({this.links = false})
    : prefix = 'independent_reels_${++_fixtureSequence}' {
    service = ReelService(auth: auth, callableInvoker: _call);
  }

  final String prefix;
  final bool links;
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'independent-reels-viewer', isEmailVerified: true),
  );
  final calls = <({String name, Map<String, Object?> payload})>[];
  bool denied = false;
  bool empty = false;
  Completer<void>? feedGate;
  late final ReelService service;

  String id(int index) => '${prefix}_$index';

  Map<String, Object?> wire(int index) => {
    'id': id(index),
    'authorId': 'independent-reels-author-$index',
    'authorName': 'Aleksandra Nowakowska-Kowalska $index',
    'media': {
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '9',
      'durationMs': 30000,
    },
    'backingAudio': null,
    'composition': ReelComposition(
      trimEndMs: 30000,
      caption: _caption,
      linkOverlays: links
          ? [
              ReelLinkOverlay(
                id: 'top',
                label: 'Read the full story',
                uri: Uri.parse('https://example.com/top'),
                x: .5,
                y: 0,
              ),
              ReelLinkOverlay(
                id: 'bottom',
                label: 'Read the next story',
                uri: Uri.parse('https://example.com/bottom'),
                x: .5,
                y: 1,
              ),
            ]
          : const [],
    ).toWire(),
    'publishedAtMillis': 1900000000000,
    'sortKey': '1900000000000_${id(index)}',
    'availability': {
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': 12,
    'commentCount': 3,
    'callerLiked': false,
  };

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    calls.add((name: name, payload: Map.of(payload)));
    if (name == 'listReelsV2') {
      await feedGate?.future;
      if (denied) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'QA_PRIVATE_ERROR_DO_NOT_SHOW',
        );
      }
      return {
        'schemaVersion': 2,
        'items': empty ? [] : [wire(1), wire(2)],
        'nextCursor': null,
      };
    }
    if (name == 'getReelMediaAccessV2') {
      return {
        'schemaVersion': 2,
        'url':
            'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
        'expiresAtMillis': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        'generation': '9',
        'availabilityHours': 'permanent',
        'contentExpiresAtMillis': null,
      };
    }
    if (name == 'getReelViewV2') {
      final index = payload['reelId'] == id(2) ? 2 : 1;
      return {
        'schemaVersion': 2,
        'reel': wire(index),
        'comments': [],
        'commentsTruncated': false,
        'nextCommentCursor': null,
      };
    }
    if (name == 'listReelCommentsV2') {
      return {'schemaVersion': 2, 'items': [], 'nextCursor': null};
    }
    if (name == 'recordReelViewedV2') return {'schemaVersion': 2};
    throw StateError('Unexpected test callable: $name');
  }
}

Widget _app(
  _Fixture f, {
  double scale = 1,
  bool pearl = false,
  GlobalKey? boundary,
}) => MaterialApp(
  theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  navigatorObservers: [appRouteObserver],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: RepaintBoundary(
    key: boundary,
    child: Scaffold(
      bottomNavigationBar: const SizedBox(key: _dockKey, height: 88),
      body: MomentsScreen(
        isRootTab: true,
        initialFormat: YoMomentsFormat.reels,
        reelService: f.service,
        auth: f.auth,
        onCreateReel: () async {},
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture f,
  Size size, {
  double scale = 1,
  bool pearl = false,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
  });
  await tester.pumpWidget(
    _app(f, scale: scale, pearl: pearl, boundary: boundary),
  );
  await _pump(tester);
}

Finder _card(_Fixture f, int index) =>
    find.byKey(ValueKey(f.id(index)), skipOffstage: false);
Finder _inside(Finder card, String key) => find.descendant(
  of: card,
  matching: find.byKey(ValueKey(key)),
  skipOffstage: false,
);

_Engine _engine(_VideoPlatform platform, _Fixture f, int index) =>
    platform.engines.values.singleWhere(
      (engine) =>
          engine.uri.endsWith('/${f.id(index)}.mp4') && !engine.disposed,
    );

Future<void> _atSixSeconds(WidgetTester tester, _Engine engine) async {
  engine.position = const Duration(seconds: 6);
  await _pump(tester); // lets the real controller observe platform position
  engine.seeks.clear();
}

Future<void> _captureFrame(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'test/.screenshots/reels-independent-qa-2026-09-11/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late _VideoPlatform platform;
  late VideoPlayerPlatform original;

  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });
  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  testWidgets(
    'independent actual decoder retains selected second Reel and position across widths',
    (tester) async {
      final f = _Fixture();
      await _mount(tester, f, const Size(320, 844));
      final pager = find.byType(PageView).first;
      await tester.drag(pager, const Offset(0, -620));
      await _pump(tester);
      expect(tester.widget<ReelCard>(_card(f, 2)).isActive, isTrue);
      final player = _engine(platform, f, 2);
      await _atSixSeconds(tester, player);
      final state = tester.state(_card(f, 2));
      for (final size in [
        const Size(768, 900),
        const Size(1440, 1000),
        const Size(320, 844),
      ]) {
        tester.view.physicalSize = size;
        await _pump(tester);
        expect(identical(tester.state(_card(f, 2)), state), isTrue);
        expect(identical(_engine(platform, f, 2), player), isTrue);
        expect(player.position, const Duration(seconds: 6));
        expect(player.seeks, isEmpty);
        expect(platform.engines.values.where((e) => e.playing), hasLength(1));
      }
      expect(f.calls.where((call) => call.name == 'listReelsV2'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(platform.engines.values.every((e) => e.disposed), isTrue);
    },
  );

  testWidgets(
    'independent Voice switch suspends without rewinding the real decoder',
    (tester) async {
      final f = _Fixture();
      await _mount(tester, f, const Size(390, 844));
      final player = _engine(platform, f, 1);
      await _atSixSeconds(tester, player);
      await tester.tap(find.text('Voice'));
      await _pump(tester);
      expect(player.playing, isFalse);
      expect(player.position, const Duration(seconds: 6));
      await tester.tap(find.text('Reels'));
      await _pump(tester);
      expect(identical(_engine(platform, f, 1), player), isTrue);
      expect(player.position, const Duration(seconds: 6));
      expect(player.playing, isTrue);
      expect(f.calls.where((call) => call.name == 'listReelsV2'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'independent recreated inactive decoder retains hidden-host suspension',
    (tester) async {
      final f = _Fixture();
      final replacement = ReelService(auth: f.auth, callableInvoker: f._call);
      final reel = Reel.fromV2Wire(f.wire(1));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await _pump(tester);
      });

      Widget host(
        ReelService service, {
        bool active = false,
        bool visible = false,
      }) => MaterialApp(
        theme: AppTheme.darkTheme,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ReelCard(
            key: ValueKey(reel.id),
            reel: reel,
            service: service,
            isActive: active,
            isHostVisible: visible,
            fillViewport: true,
          ),
        ),
      );

      await tester.pumpWidget(host(f.service));
      await _pump(tester);
      final state = tester.state(_card(f, 1));
      final originalPlayer = _engine(platform, f, 1);
      expect(originalPlayer.playing, isFalse);

      await tester.pumpWidget(host(replacement));
      await _pump(tester);
      expect(identical(tester.state(_card(f, 1)), state), isTrue);
      // The decoder may be retained for an equivalent URI; the contract is
      // that every engine stays paused while the host is hidden, not disposal.
      expect(
        platform.engines.values.where((engine) => engine.playing),
        isEmpty,
      );

      await tester.pumpWidget(host(replacement, active: true));
      await _pump(tester);
      expect(
        platform.engines.values.where((engine) => engine.playing),
        isEmpty,
        reason: 'Selecting an inactive card must not bypass the hidden host.',
      );
      expect(
        f.calls.where((call) => call.name == 'recordReelViewedV2'),
        isEmpty,
      );

      await tester.pumpWidget(host(replacement, active: true, visible: true));
      await _pump(tester);
      final playing = platform.engines.values.where((engine) => engine.playing);
      expect(playing, hasLength(1));
      expect(playing.single.volume, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['caption', 'more', 'share']) {
    testWidgets(
      'independent real Moments host $action pauses without rewinding or undoing manual pause',
      (tester) async {
        final f = _Fixture();
        await _mount(tester, f, const Size(390, 844));
        final player = _engine(platform, f, 1);
        await _atSixSeconds(tester, player);
        final card = _card(f, 1);
        final control = action == 'caption'
            ? find.descendant(of: card, matching: find.text(_caption))
            : _inside(card, 'reel-$action-action');
        await tester.tap(control);
        await _pump(tester);
        expect(player.playing, isFalse);
        expect(player.position, const Duration(seconds: 6));
        Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
        await _pump(tester);
        expect(player.position, const Duration(seconds: 6));
        expect(player.playing, isTrue);
        await tester.tap(_inside(card, 'reel-viewport'), warnIfMissed: false);
        await _pump(tester);
        expect(player.playing, isFalse);
        await tester.tap(control);
        await _pump(tester);
        Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
        await _pump(tester);
        expect(
          player.playing,
          isFalse,
          reason: 'An overlay must not clear an explicit viewer pause.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final size in [
    const Size(320, 568),
    const Size(320, 844),
    const Size(390, 844),
    const Size(768, 900),
    const Size(1440, 1000),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'independent authored links avoid actual chrome and footer ${size.width}x${size.height} / $scale',
        (tester) async {
          for (final pearl in [false, true]) {
            final f = _Fixture(links: true);
            final boundary = GlobalKey();
            await _mount(
              tester,
              f,
              size,
              scale: scale,
              pearl: pearl,
              boundary: boundary,
            );
            final card = _card(f, 1);
            final viewport = tester.getRect(_inside(card, 'reel-viewport'));
            final chrome = tester.getRect(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('reels-discover-filter')),
                    matching: find.byType(ReelOverlayMeasure),
                  )
                  .first,
            );
            final rail = tester.getRect(
              find
                  .descendant(
                    of: card,
                    matching: find.byType(ReelEngagementBar),
                  )
                  .first,
            );
            final identityRects = [
              ...find
                  .descendant(of: card, matching: find.byType(ReelAuthorRow))
                  .evaluate()
                  .map(
                    (element) => tester.getRect(find.byWidget(element.widget)),
                  ),
              ...find
                  .descendant(of: card, matching: find.text(_caption))
                  .evaluate()
                  .map(
                    (element) => tester.getRect(find.byWidget(element.widget)),
                  ),
            ];
            final label =
                '${size.width.toInt()}x${size.height.toInt()}-${scale.toInt()}x-${pearl ? 'pearl' : 'dark'}-links';
            await _captureFrame(tester, boundary, label);
            final topLinkRect = tester.getRect(
              _inside(card, 'reel-link-overlay-top'),
            );
            final bottomLinkRect = tester.getRect(
              _inside(card, 'reel-link-overlay-bottom'),
            );
            expect(
              topLinkRect.overlaps(bottomLinkRect),
              isFalse,
              reason:
                  '$label: opposite-edge authored links must not cover one another '
                  '(top: $topLinkRect; bottom: $bottomLinkRect)',
            );
            for (final id in ['top', 'bottom']) {
              final link = _inside(card, 'reel-link-overlay-$id');
              final rect = tester.getRect(link);
              expect(rect.width, greaterThanOrEqualTo(44), reason: label);
              expect(rect.height, greaterThanOrEqualTo(44), reason: label);
              expect(
                rect.top,
                greaterThanOrEqualTo(viewport.top),
                reason: label,
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(viewport.bottom),
                reason: label,
              );
              expect(
                rect.overlaps(chrome),
                isFalse,
                reason: '$label: link is covered by chrome',
              );
              expect(
                rect.overlaps(rail),
                isFalse,
                reason: '$label: link is covered by rail',
              );
              for (final identity in identityRects) {
                expect(
                  rect.overlaps(identity),
                  isFalse,
                  reason: '$label: link is covered by identity/caption',
                );
              }
              expect(
                link.hitTestable(),
                findsOneWidget,
                reason: '$label: authored link must be reachable',
              );
            }
            expect(
              tester.getRect(find.byKey(_dockKey)).top,
              greaterThanOrEqualTo(viewport.bottom - .5),
            );
            for (final key in [
              'reel-like-action',
              'reel-comments-action',
              'reel-share-action',
              'reel-more-action',
            ]) {
              expect(
                tester.getSize(_inside(card, key)).shortestSide,
                greaterThanOrEqualTo(44),
              );
              expect(_inside(card, key).hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull, reason: label);
            await tester.pumpWidget(const SizedBox());
            await _pump(tester);
          }
        },
      );
    }
  }

  testWidgets(
    'independent feed denial and fresh retry never become fake empty',
    (tester) async {
      final f = _Fixture()..denied = true;
      await _mount(tester, f, const Size(390, 844));
      expect(find.textContaining('QA_PRIVATE_ERROR'), findsNothing);
      expect(find.text('No Reels yet'), findsNothing);
      expect(platform.engines, isEmpty);
      f.denied = false;
      await tester.tap(find.text('Try again'));
      await _pump(tester);
      expect(_card(f, 1), findsOneWidget);
      expect(_engine(platform, f, 1).playing, isTrue);
      expect(_engine(platform, f, 1).volume, 0);
      expect(f.calls.where((call) => call.name == 'listReelsV2'), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'independent loading does not initialize a decoder or claim empty',
    (tester) async {
      final gate = Completer<void>();
      final f = _Fixture()..feedGate = gate;
      await _mount(tester, f, const Size(390, 844));
      expect(platform.engines, isEmpty);
      expect(find.text('No Reels yet'), findsNothing);
      expect(find.byKey(const ValueKey('moments-create-cta')), findsOneWidget);
      gate.complete();
      await _pump(tester);
      expect(_engine(platform, f, 1).playing, isTrue);
      expect(_engine(platform, f, 1).volume, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'independent decoder failure stops after one automatic refresh then retries explicitly',
    (tester) async {
      final f = _Fixture();
      platform.failuresRemaining = 2;
      await _mount(tester, f, const Size(390, 844));
      final grants = f.calls.where(
        (call) =>
            call.name == 'getReelMediaAccessV2' &&
            call.payload['reelId'] == f.id(1),
      );
      expect(grants, hasLength(2));
      expect(
        platform.engines.values.where((engine) => engine.playing),
        isEmpty,
      );
      expect(find.text('Open video'), findsOneWidget);
      expect(find.text('QA decoder refusal'), findsNothing);
      await tester.tap(find.text('Retry'));
      await _pump(tester);
      expect(grants, hasLength(3));
      expect(_engine(platform, f, 1).playing, isTrue);
      expect(_engine(platform, f, 1).volume, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
