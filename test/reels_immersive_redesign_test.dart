// Author regression tests. Decoder/transport seams are deterministic; these
// tests do not constitute physical-device playback or network latency evidence.
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
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';

const _capture = bool.fromEnvironment('YO_CAPTURE_IMMERSIVE_REELS');
const _caption =
    'Evening stories from our little corner of the city. '
    'A longer caption stays readable when you open it, without hiding the video controls.';
const _like = ValueKey('reel-like-action');
const _more = ValueKey('reel-more-action');

Map<String, Object?> _wire(int index, {bool stickers = false}) => {
  'id': 'immersive_$index',
  'authorId': 'author_$index',
  'authorName': 'Creator $index',
  'media': {
    'kind': 'video',
    'contentType': 'video/mp4',
    'size': 1024,
    'generation': '1',
    'durationMs': 15000,
  },
  'backingAudio': null,
  'composition': ReelComposition(
    trimEndMs: 15000,
    caption: _caption,
    linkOverlays: stickers
        ? [
            ReelLinkOverlay(
              id: 'top',
              label: 'Top link',
              uri: Uri.parse('https://example.com/top'),
              x: .5,
              y: 0,
            ),
            ReelLinkOverlay(
              id: 'bottom',
              label: 'Bottom link',
              uri: Uri.parse('https://example.com/bottom'),
              x: .5,
              y: 1,
            ),
          ]
        : const [],
  ).toWire(),
  'publishedAtMillis': 1900000000000,
  'sortKey': '1900000000000_immersive_$index',
  'availability': {
    'schemaVersion': 1,
    'availabilityHours': 'permanent',
    'expiresAtMillis': null,
  },
  'likeCount': 12,
  'commentCount': 3,
  'callerLiked': false,
};

class _Fixture {
  _Fixture({
    this.empty = false,
    this.fail = false,
    this.slow = false,
    this.stickers = false,
  }) {
    service = ReelService(
      auth: auth,
      callableInvoker: (name, payload) async {
        calls.add(name);
        if (name == 'listReelsV2') {
          if (slow) await gate.future;
          if (fail) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'test',
            );
          }
          return {
            'schemaVersion': 2,
            'items': empty ? [] : [_wire(1, stickers: stickers), _wire(2)],
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
            'generation': '1',
            'availabilityHours': 'permanent',
            'contentExpiresAtMillis': null,
          };
        }
        if (name == 'getReelViewV2') {
          return {
            'schemaVersion': 2,
            'reel': _wire(1),
            'comments': [],
            'commentsTruncated': false,
            'nextCommentCursor': null,
          };
        }
        if (name == 'setReelLike') {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'test',
          );
        }
        if (name == 'recordReelViewedV2') return {'schemaVersion': 2};
        throw StateError('Unexpected callable $name');
      },
    );
  }
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
  );
  final bool empty;
  bool fail;
  final bool slow;
  final bool stickers;
  final gate = Completer<void>();
  final calls = <String>[];
  final players = <String, List<_Player>>{};
  late final ReelService service;
  ReelVideoPlayback videoFactory(Uri uri, Reel reel) {
    final player = _Player();
    players.putIfAbsent(reel.id, () => []).add(player);
    return player;
  }
}

class _Player implements ReelVideoPlayback {
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  double volume = 0;
  @override
  Future<void> play() async {
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }
}

Widget _still(BuildContext context, Uri uri, Reel reel) => DecoratedBox(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF788B9A), Color(0xFFB18570), Color(0xFF263D3B)],
    ),
  ),
  child: const Center(
    child: Icon(Icons.landscape_outlined, color: Colors.white54, size: 160),
  ),
);

Widget _app(
  Widget child, {
  ThemeData? theme,
  double scale = 1,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  locale: locale,
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
  home: child,
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pump();
}

Widget _feed(_Fixture f, {ValueNotifier<bool>? visible}) => LayoutBuilder(
  builder: (_, constraints) => ReelsFeedScreen(
    embedded: true,
    immersive: constraints.maxWidth < 600,
    service: f.service,
    videoBuilder: _still,
    videoPlaybackFactory: f.videoFactory,
    isVisible: visible,
    onOpenAuthor: (_) {},
    onCreate: () async {},
  ),
);

void main() {
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

  testWidgets(
    'authored links stay tappable between measured chrome and footer at 200%',
    (tester) async {
      addTearDown(tester.view.reset);
      await _size(tester, const Size(320, 844));
      final f = _Fixture(stickers: true);
      await tester.pumpWidget(
        _app(
          Scaffold(
            bottomNavigationBar: const SizedBox(height: 88),
            body: MomentsScreen(
              isRootTab: true,
              initialFormat: YoMomentsFormat.reels,
              reelService: f.service,
              reelVideoBuilder: _still,
              onCreateReel: () async {},
            ),
          ),
          scale: 2,
        ),
      );
      await _settle(tester);
      final chrome = tester.getRect(find.byKey(const ValueKey('reels-chrome')));
      final footer = tester.getRect(
        find.byKey(const ValueKey('reel-footer')).first,
      );
      for (final label in ['Top link', 'Bottom link']) {
        final link = find.text(label).hitTestable();
        expect(link, findsOneWidget);
        final rect = tester.getRect(link);
        expect(rect.top, greaterThanOrEqualTo(chrome.bottom));
        expect(rect.bottom, lessThanOrEqualTo(footer.top));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('More keeps the full caption and every authored link reachable', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _size(tester, const Size(320, 568));
    final f = _Fixture(stickers: true);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ReelCard(
            reel: Reel.fromV2Wire(_wire(1, stickers: true)),
            service: f.service,
            videoBuilder: _still,
            fillViewport: true,
          ),
        ),
        scale: 2,
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(_more));
    await _settle(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    for (final id in ['top', 'bottom']) {
      final link = find.byKey(ValueKey('reel-details-link-$id'));
      await tester.ensureVisible(link);
      await _settle(tester);
      expect(link.hitTestable(), findsOneWidget);
      expect(tester.getSize(link).shortestSide, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  for (final surface in ['more', 'caption']) {
    for (final exit in ['background', 'account', 'host_removed']) {
      testWidgets('$surface retires private metadata after $exit', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        await _size(tester, const Size(390, 844));
        final f = _Fixture(stickers: true);
        final present = ValueNotifier<bool>(true);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: present,
                builder: (_, exists, _) => exists
                    ? ReelCard(
                        reel: Reel.fromV2Wire(_wire(1, stickers: true)),
                        service: f.service,
                        videoBuilder: _still,
                        fillViewport: true,
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(
          surface == 'more' ? find.byKey(_more) : find.text(_caption).first,
        );
        await _settle(tester);
        expect(find.byType(SelectableText), findsOneWidget);
        if (exit == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else if (exit == 'account') {
          await f.auth.signOut();
        } else {
          present.value = false;
        }
        await _settle(tester);
        expect(find.byType(SelectableText), findsNothing);
        expect(
          find.byKey(const ValueKey('reel-details-link-top')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('reel-link-comment-overlay-unavailable')),
          findsOneWidget,
        );
        if (exit == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await _settle(tester);
          expect(find.byType(SelectableText), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
        present.dispose();
      });
    }
  }

  testWidgets(
    'immersive player fills width and height above the retained dock',
    (tester) async {
      addTearDown(tester.view.reset);
      await _size(tester, const Size(390, 844));
      final f = _Fixture();
      await tester.pumpWidget(
        _app(
          Scaffold(
            bottomNavigationBar: const SizedBox(
              key: ValueKey('retained-dock'),
              height: 88,
            ),
            body: MomentsScreen(
              isRootTab: true,
              initialFormat: YoMomentsFormat.reels,
              reelService: f.service,
              reelVideoBuilder: _still,
              onCreateReel: () async {},
            ),
          ),
        ),
      );
      await _settle(tester);
      final frame = tester.getRect(
        find.byKey(const ValueKey('reel-viewport')).first,
      );
      final dock = tester.getRect(find.byKey(const ValueKey('retained-dock')));
      expect(frame.left, closeTo(0, .001));
      expect(frame.width, 390);
      expect(frame.top, closeTo(0, .001));
      expect(frame.bottom, dock.top);
      expect(find.byKey(const ValueKey('yo-moments-title')), findsNothing);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Reels'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'format and viewport changes retain card state and feed position',
    (tester) async {
      addTearDown(tester.view.reset);
      await _size(tester, const Size(390, 844));
      final f = _Fixture();
      await tester.pumpWidget(
        _app(
          MomentsScreen(
            isRootTab: true,
            initialFormat: YoMomentsFormat.reels,
            reelService: f.service,
            reelVideoBuilder: _still,
            onCreateReel: () async {},
          ),
        ),
      );
      await _settle(tester);
      final card = find.byKey(
        const ValueKey('immersive_1'),
        skipOffstage: false,
      );
      final first = tester.state(card);
      for (final size in [
        const Size(768, 900),
        const Size(1440, 900),
        const Size(390, 844),
      ]) {
        await _size(tester, size);
        await _settle(tester);
        expect(identical(tester.state(card), first), isTrue);
      }
      await tester.tap(find.text('Voice'));
      await _settle(tester);
      expect(tester.widget<ReelCard>(card).isActive, isTrue);
      expect(tester.widget<ReelCard>(card).isHostVisible, isFalse);
      await tester.tap(find.text('Reels'));
      await _settle(tester);
      expect(identical(tester.state(card), first), isTrue);
      expect(tester.widget<ReelCard>(card).isActive, isTrue);
      expect(tester.widget<ReelCard>(card).isHostVisible, isTrue);
      expect(f.calls.where((name) => name == 'listReelsV2'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one decoder survives responsive reflow and overlay pauses playback',
    (tester) async {
      addTearDown(tester.view.reset);
      await _size(tester, const Size(390, 844));
      final f = _Fixture();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(_app(Scaffold(body: _feed(f, visible: visible))));
      await _settle(tester);
      final player = f.players['immersive_1']!.single;
      expect(player.isPlaying, isTrue);
      expect(player.volume, 0);
      player.position = const Duration(seconds: 4);
      for (final size in [
        const Size(768, 900),
        const Size(1440, 900),
        const Size(390, 844),
      ]) {
        await _size(tester, size);
        await _settle(tester);
        expect(f.players['immersive_1'], hasLength(1));
        expect(player.position, const Duration(seconds: 4));
      }
      await tester.tap(find.byKey(_more));
      await _settle(tester);
      expect(player.isPlaying, isFalse);
      expect(find.text('Report Reel'), findsOneWidget);
      expect(find.text('Delete Reel'), findsNothing);
      Navigator.of(tester.element(find.text('Report Reel'))).pop();
      await _settle(tester);
      expect(player.isPlaying, isTrue);
      visible.value = false;
      await _settle(tester);
      expect(player.isPlaying, isFalse);
      expect(player.position, const Duration(seconds: 4));
      visible.value = true;
      await _settle(tester);
      expect(player.isPlaying, isTrue);
      expect(player.position, const Duration(seconds: 4));
      await tester.tap(
        find.byKey(const ValueKey('reel-video-playback-surface')),
      );
      await _settle(tester);
      expect(player.isPlaying, isFalse);
      visible.value = false;
      await _settle(tester);
      visible.value = true;
      await _settle(tester);
      expect(
        player.isPlaying,
        isFalse,
        reason: 'Keep the deliberate hand-pause',
      );
      expect(player.position, const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'immersive like rolls back and long caption opens without hiding controls',
    (tester) async {
      addTearDown(tester.view.reset);
      await _size(tester, const Size(390, 844));
      final f = _Fixture();
      await tester.pumpWidget(_app(Scaffold(body: _feed(f))));
      await _settle(tester);
      await tester.tap(find.byKey(_like));
      await _settle(tester);
      expect(
        tester.widget<ReelCard>(find.byType(ReelCard).first).reel.callerLiked,
        isFalse,
      );
      expect(f.calls.where((call) => call == 'setReelLike'), hasLength(1));
      // The honest failure notice briefly occupies the bottom of the screen.
      // Read the caption after it clears, not through a live SnackBar.
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      await tester.tap(find.text(_caption).first);
      await _settle(tester);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(f.players['immersive_1']!.single.isPlaying, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop action counts remain readable over white footage', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _size(tester, const Size(1440, 1000));
    for (final scale in [1.0, 2.0]) {
      for (final dark in [true, false]) {
        final fixture = _Fixture(stickers: true);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _app(
            RepaintBoundary(
              key: boundary,
              child: Scaffold(
                bottomNavigationBar: const SizedBox(height: 88),
                body: MomentsScreen(
                  key: UniqueKey(),
                  isRootTab: true,
                  initialFormat: YoMomentsFormat.reels,
                  reelService: fixture.service,
                  reelVideoBuilder: (_, _, _) =>
                      const ColoredBox(color: Colors.white),
                  onCreateReel: () async {},
                ),
              ),
            ),
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            scale: scale,
          ),
        );
        await _settle(tester);
        final card = find.byType(ReelCard).first;
        final top = find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('reel-link-overlay-top')),
        );
        final bottom = find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('reel-link-overlay-bottom')),
        );
        expect(tester.getRect(top).overlaps(tester.getRect(bottom)), isFalse);
        for (final count in ['12', '3']) {
          final label = find.descendant(of: card, matching: find.text(count));
          expect(label, findsOneWidget);
          expect(tester.getRect(label).height, greaterThan(0));
        }
        expect(tester.takeException(), isNull);
        if (_capture) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'test/.screenshots/reels-immersive-2026-09-11/white-media-${scale.toInt()}-${dark ? 'dark' : 'pearl'}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      }
    }
  });

  for (final width in [320.0, 390.0, 430.0, 768.0, 1100.0, 1440.0, 2560.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('responsive immersive states $width / $scale', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        await _size(tester, Size(width, width < 600 ? 844 : 1000));
        for (final dark in [true, false]) {
          for (final state in ['populated', 'empty', 'error', 'loading']) {
            final f = _Fixture(
              empty: state == 'empty',
              fail: state == 'error',
              slow: state == 'loading',
            );
            final boundary = GlobalKey();
            await tester.pumpWidget(
              _app(
                RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    bottomNavigationBar: const SizedBox(height: 88),
                    body: MomentsScreen(
                      key: UniqueKey(),
                      isRootTab: true,
                      initialFormat: YoMomentsFormat.reels,
                      reelService: f.service,
                      reelVideoBuilder: _still,
                      onCreateReel: () async {},
                    ),
                  ),
                ),
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                scale: scale,
                locale: const Locale('pl'),
              ),
            );
            await _settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '$width/$scale/$dark/$state',
            );
            final create = find.byKey(const ValueKey('moments-create-cta'));
            expect(create, findsOneWidget);
            expect(
              tester.getSize(create).shortestSide,
              greaterThanOrEqualTo(44),
            );
            if (state == 'populated' && width < 600) {
              expect(
                tester
                    .getSize(find.byKey(const ValueKey('reel-viewport')).first)
                    .width,
                width,
              );
              for (final key in [
                _like,
                const ValueKey('reel-comments-action'),
                _more,
              ]) {
                expect(
                  tester.getSize(find.byKey(key)).shortestSide,
                  greaterThanOrEqualTo(44),
                );
              }
            }
            if (_capture) {
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'test/.screenshots/reels-immersive-2026-09-11/${width.toInt()}-${scale.toInt()}-${dark ? 'dark' : 'pearl'}-$state.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            if (f.slow) f.gate.complete();
            await tester.pumpWidget(const SizedBox());
            await _settle(tester);
          }
        }
      });
    }
  }
}
