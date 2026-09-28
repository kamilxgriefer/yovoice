import 'dart:math' as math;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';
import 'package:yovoice/shared/widgets/buttons/yo_create_ring_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// Refine-look B6, the Yeels half (spec §8.4): the media plates, the create
/// `+` as the R6 disc on the canvas and over footage, the played timeline as
/// the theme-invariant brand sweep, and the create sheet's R2 tiles.
void main() {
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );

  BoxDecoration plateDecoration(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(OverlayPlate),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  group('media plates', () {
    testWidgets('a smoked 0x8C plate with a white hairline edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const OverlayPlate(
            icon: Icons.favorite_border_rounded,
            color: Colors.white,
            hovered: false,
          ),
        ),
      );
      final decoration = plateDecoration(tester);
      expect(decoration.color, const Color(0x8C000000));
      expect(overlayGlyphPlateColor, const Color(0x8C000000));
      final edge = (decoration.border! as Border).top;
      expect(edge.color, const Color(0x24FFFFFF));
      expect(edge.width, 1);
    });

    testWidgets('high contrast keeps the denser plate', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: host(
            const OverlayPlate(
              icon: Icons.favorite_border_rounded,
              color: Colors.white,
              hovered: false,
            ),
          ),
        ),
      );
      expect(plateDecoration(tester).color, overlayPlateColor);
    });

    testWidgets('hover darkens to 0xB3', (tester) async {
      await tester.pumpWidget(
        host(
          const OverlayPlate(
            icon: Icons.favorite_border_rounded,
            color: Colors.white,
            hovered: true,
          ),
        ),
      );
      expect(plateDecoration(tester).color, const Color(0xB3000000));
    });

    testWidgets('a ring replaces the hairline', (tester) async {
      await tester.pumpWidget(
        host(
          const OverlayPlate(
            icon: Icons.favorite_rounded,
            color: Colors.white,
            hovered: false,
            ring: AppColors.live,
          ),
        ),
      );
      final edge = (plateDecoration(tester).border! as Border).top;
      expect(edge.color, AppColors.live);
      expect(edge.width, 2);
    });

    testWidgets('a canvas host keeps its own fill and gets no hairline', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const OverlayPlate(
            icon: Icons.refresh_rounded,
            color: Colors.white,
            hovered: false,
            fill: Colors.transparent,
          ),
        ),
      );
      final decoration = plateDecoration(tester);
      expect(decoration.color, Colors.transparent);
      expect(decoration.border, isNull);
    });

    test('text pills keep the denser plate (4.5:1 for small text)', () {
      expect(overlayPlateColor, const Color(0xB8000000));
      expect(overlayPlateHoverColor, const Color(0xD6000000));
    });

    test('a white glyph holds 3:1 on the lighter plate over pure white', () {
      final plate = Color.alphaBlend(overlayGlyphPlateColor, Colors.white);
      final contrast =
          (1.05) / (plate.computeLuminance() + .05); // white on the plate
      expect(contrast, greaterThanOrEqualTo(3));
    });
  });

  group('the create disc', () {
    for (final (theme, name) in <(ThemeData, String)>[
      (AppTheme.darkTheme, 'Dark'),
      (AppTheme.lightTheme, 'Pearl'),
    ]) {
      testWidgets('$name: over media it is the R6 disc in the Dark palette', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            OverlayBrandDiscButton(
              key: const ValueKey('create'),
              icon: Icons.add_rounded,
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
            ),
            theme: theme,
          ),
        );
        final disc = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
        expect(disc.size, 48);
        expect(disc.emphasis, YoDiscEmphasis.lift);
        expect(disc.tone, YoDiscTone.brand);
        expect(
          AppPalette.of(tester.element(find.byType(YoGradientDisc))),
          AppPalette.dark,
          reason: 'the light over footage does not follow the app theme',
        );
        expect(tester.getSize(find.byKey(const ValueKey('create'))).width, 48);
        expect(tester.getSize(find.byKey(const ValueKey('create'))).height, 48);
        expect(find.bySemanticsLabel('UTWÓRZ'), findsOneWidget);
      });

      testWidgets('$name: on the canvas it follows the app theme', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            OverlayBrandDiscButton(
              icon: Icons.add_rounded,
              semanticLabel: 'UTWÓRZ',
              onTap: () {},
              onMedia: false,
            ),
            theme: theme,
          ),
        );
        expect(
          AppPalette.of(tester.element(find.byType(YoGradientDisc))),
          theme.extension<AppPalette>(),
        );
      });
    }

    testWidgets('a tap reaches the callback; no callback is disabled', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          OverlayBrandDiscButton(
            icon: Icons.add_rounded,
            semanticLabel: 'UTWÓRZ',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(OverlayBrandDiscButton));
      expect(taps, 1);

      await tester.pumpWidget(
        host(
          const OverlayBrandDiscButton(
            icon: Icons.add_rounded,
            semanticLabel: 'UTWÓRZ',
            onTap: null,
          ),
        ),
      );
      final disc = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
      expect(disc.status, YoDiscStatus.disabled);
      expect(disc.emphasis, YoDiscEmphasis.rest);
    });

    for (final onCanvas in <bool>[true, false]) {
      testWidgets('the Moments header "+" is the create ring '
          '(onCanvas: $onCanvas)', (tester) async {
        late ImmersiveFeedHeaderSlots slots;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) {
                slots = buildImmersiveMomentsHeader(
                  context,
                  showBack: false,
                  selectedFormat: YoMomentsFormat.reels,
                  onFormatSelected: (_) {},
                  onCreate: () {},
                  onCanvas: onCanvas,
                );
                return Scaffold(body: Center(child: slots.trailing));
              },
            ),
          ),
        );
        // ADR-229: the gradient ring replaced the R6 disc in this row.
        final create = tester.widget<YoCreateRingButton>(
          find.byKey(const ValueKey('moments-create-cta')),
        );
        expect(create.onMedia, !onCanvas);
        expect(find.byType(OverlayBrandDiscButton), findsNothing);
        expect(find.bySemanticsLabel('CREATE'), findsOneWidget);
      });
    }
  });

  group('the played timeline', () {
    // The Dark pair of the voice sweep Kamil approved (spec §12.1).
    final lifted = AppGradients.voicePlayed(
      AppTheme.darkTheme.colorScheme,
      AppPalette.dark,
    ).colors;

    LinearGradient playedGradientOf(WidgetTester tester) {
      final played = tester.widget<DecoratedBox>(
        find.byKey(ReelProgressBar.playedKey),
      );
      return (played.decoration as BoxDecoration).gradient! as LinearGradient;
    }

    Color trackColorOf(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('reel-progress-bar')),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    Future<ValueNotifier<Duration>> pumpBar(
      WidgetTester tester, {
      ThemeData? theme,
      bool highContrast = false,
      bool onMedia = true,
      TextDirection direction = TextDirection.ltr,
      Duration at = const Duration(seconds: 6),
    }) async {
      final position = ValueNotifier<Duration>(at);
      addTearDown(position.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: highContrast),
            child: child!,
          ),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: ReelProgressBar(
                    position: position,
                    total: const Duration(seconds: 18),
                    onMedia: onMedia,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return position;
    }

    test('over media it is the lifted logo sweep in both themes', () {
      expect(lifted, <Color>[
        Color.lerp(AppColors.primary, AppColors.white, .40)!,
        Color.lerp(AppColors.secondary, AppColors.white, .32)!,
      ]);
      for (final scheme in <ColorScheme>[
        AppTheme.darkTheme.colorScheme,
        AppTheme.lightTheme.colorScheme,
      ]) {
        final gradient = reelPlayedGradient(.5, onMedia: true, scheme: scheme);
        expect(gradient.colors, lifted);
        expect(gradient.colors, isNot(contains(AppPalette.light.audioAccent)));
      }
    });

    test('on the phone stage played vs unplayed holds 3:1 on any frame', () {
      // WCAG 1.4.11: on a phone at rest the time labels are hidden, so the
      // bar's length is the only indicator. There the bar is the frame's
      // bottom edge, on the 0x59 legibility wash under the 0xB8 peak of the
      // footer scrim; the worst case is pure-white footage (the lightest
      // scrim), the best pure black. (The card stage keeps its time labels
      // on screen, so its bar is never the only indicator.)
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
      }

      for (final footage in <Color>[Colors.white, Colors.black]) {
        final scrim = Color.alphaBlend(
          const Color(0xB8000000),
          Color.alphaBlend(const Color(0x59000000), footage),
        );
        final track = Color.alphaBlend(
          reelMediaTrackColor(highContrast: false),
          scrim,
        );
        for (final played in lifted) {
          expect(
            contrast(played, track),
            greaterThanOrEqualTo(3),
            reason: 'played $played vs unplayed $track over $footage',
          );
          expect(contrast(played, scrim), greaterThanOrEqualTo(3));
        }
        final hcTrack = Color.alphaBlend(
          reelMediaTrackColor(highContrast: true),
          scrim,
        );
        expect(contrast(Colors.white, hcTrack), greaterThanOrEqualTo(4.5));
      }
    });

    test('on an app surface it is the theme\'s AA-safe pair', () {
      final scheme = AppTheme.lightTheme.colorScheme;
      final gradient = reelPlayedGradient(.5, onMedia: false, scheme: scheme);
      expect(gradient.colors, <Color>[scheme.primary, scheme.secondary]);
    });

    test('the sweep spans the whole track, revealed to the playhead', () {
      AlignmentDirectional endOf(double fraction) =>
          reelPlayedGradient(
                fraction,
                onMedia: true,
                scheme: AppTheme.darkTheme.colorScheme,
              ).end
              as AlignmentDirectional;
      // Half played: the gradient ends one box-width past the played box.
      expect(endOf(.5).start, closeTo(3, 1e-9));
      expect(endOf(.25).start, closeTo(7, 1e-9));
      expect(endOf(1).start, closeTo(1, 1e-9));
      expect(endOf(0).start, 1);
    });

    testWidgets('Pearl over footage paints the sweep, not the teal', (
      tester,
    ) async {
      await pumpBar(tester, theme: AppTheme.lightTheme);
      expect(playedGradientOf(tester).colors, lifted);
      expect(tester.getSize(find.byKey(ReelProgressBar.playedKey)).width, 120);
      expect(
        tester.getSize(find.byKey(ReelProgressBar.playedKey)).height,
        ReelProgressBar.trackHeight,
      );
      expect(trackColorOf(tester), Colors.white.withValues(alpha: .14));
    });

    testWidgets('right-to-left: the sweep starts at the right end and ends '
        'at the track\'s left end', (tester) async {
      // 9 s of 18: half played.
      await pumpBar(
        tester,
        direction: TextDirection.rtl,
        at: const Duration(seconds: 9),
      );
      final track = tester.getRect(
        find.byKey(const ValueKey<String>('reel-progress-bar')),
      );
      final box = tester.getRect(find.byKey(ReelProgressBar.playedKey));
      expect(box.width, closeTo(track.width / 2, 1e-6));
      expect(box.right, closeTo(track.right, 1e-6), reason: 'played is right');
      expect(box.left, closeTo(track.center.dx, 1e-6));

      final gradient = playedGradientOf(tester);
      final begin = gradient.begin.resolve(TextDirection.rtl);
      final end = gradient.end.resolve(TextDirection.rtl);
      expect(begin, Alignment.centerRight);
      expect(end.x, closeTo(-3, 1e-9));
      // Where those alignments land on screen: the sweep starts at the
      // track's start (right) edge and ends at its far (left) edge.
      final beginX = box.center.dx + begin.x * box.width / 2;
      final endX = box.center.dx + end.x * box.width / 2;
      expect(beginX, closeTo(track.right, 1e-6));
      expect(endX, closeTo(track.left, 1e-6));
      expect(gradient.colors.first, lifted.first, reason: 'violet at start');
    });

    testWidgets('high contrast: solid white over footage, no gradient', (
      tester,
    ) async {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        await pumpBar(tester, theme: theme, highContrast: true);
        final played = tester.widget<DecoratedBox>(
          find.byKey(ReelProgressBar.playedKey),
        );
        final decoration = played.decoration as BoxDecoration;
        expect(decoration.gradient, isNull);
        expect(decoration.color, Colors.white);
        expect(trackColorOf(tester), Colors.white.withValues(alpha: .32));
        expect(
          tester.getSize(find.byKey(ReelProgressBar.playedKey)).width,
          120,
        );
      }
    });

    testWidgets('high contrast on a surface: solid primary, no gradient', (
      tester,
    ) async {
      await pumpBar(
        tester,
        theme: AppTheme.lightTheme,
        highContrast: true,
        onMedia: false,
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(find.byKey(ReelProgressBar.playedKey))
                  .decoration
              as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, AppTheme.lightTheme.colorScheme.primary);
    });
  });

  group('the scrub feedback', () {
    const bandKey = ValueKey<String>('reel-progress-scrub');
    const thumbKey = ValueKey<String>('reel-progress-scrub-thumb');
    const scrubTrackKey = ValueKey<String>('reel-progress-scrub-track');

    Future<TestGesture> dragTo40(
      WidgetTester tester, {
      bool highContrast = false,
      ThemeData? theme,
    }) async {
      final target = _ScrubTarget();
      addTearDown(target.dispose);
      final trackKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: highContrast),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 200,
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: KeyedSubtree(
                        key: trackKey,
                        child: ReelProgressBar(
                          position: target.position,
                          total: _ScrubTarget.total,
                          announce: false,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 40,
                      child: ReelProgressScrubber(
                        key: bandKey,
                        target: target,
                        position: target.position,
                        total: _ScrubTarget.total,
                        trackKey: trackKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final band = tester.getRect(find.byKey(bandKey));
      final gesture = await tester.startGesture(
        Offset(band.left + 40, band.center.dy),
      );
      await gesture.moveTo(Offset(band.left + 160, band.center.dy));
      await tester.pumpAndSettle();
      return gesture;
    }

    BoxDecoration thumbOf(WidgetTester tester) =>
        tester.widget<DecoratedBox>(find.byKey(thumbKey)).decoration
            as BoxDecoration;

    DecoratedBox scrubPlayedOf(WidgetTester tester) =>
        tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(scrubTrackKey),
            matching: find.byType(DecoratedBox),
          ),
        );

    testWidgets('while dragging: a white thumb ringed in the logo violet, '
        'over the lifted sweep', (tester) async {
      final gesture = await dragTo40(tester);
      final thumb = thumbOf(tester);
      expect(thumb.color, Colors.white);
      expect(thumb.shape, BoxShape.circle);
      final ring = (thumb.border! as Border).top;
      expect(ring.color, AppColors.primary);
      expect(ring.width, 2);

      final played = scrubPlayedOf(tester);
      final gradient =
          (played.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(
        gradient.colors,
        AppGradients.voicePlayed(
          AppTheme.darkTheme.colorScheme,
          AppPalette.dark,
        ).colors,
      );
      expect(
        tester.getSize(find.byType(ReelProgressScrubber)).width,
        400,
        reason: 'the band spans the bar',
      );
      final scrubTrack = tester.getRect(find.byKey(scrubTrackKey));
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byKey(scrubTrackKey),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        reelMediaTrackColor(highContrast: false),
        reason: 'the grown track keeps the resting ink (3:1 with no thumb)',
      );
      expect(
        tester.getRect(find.byWidget(played)).width,
        closeTo(scrubTrack.width * .4, 1),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('high contrast: a black ring and a solid white sweep', (
      tester,
    ) async {
      final gesture = await dragTo40(
        tester,
        highContrast: true,
        theme: AppTheme.lightTheme,
      );
      final ring = (thumbOf(tester).border! as Border).top;
      expect(ring.color, AppColors.black);
      final played = scrubPlayedOf(tester).decoration as BoxDecoration;
      expect(played.gradient, isNull);
      expect(played.color, Colors.white);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('the create sheet', () {
    testWidgets('its choices are R2 blocks with a 44 px primary circle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MomentsScreen(
            isRootTab: true,
            initialFormat: YoMomentsFormat.reels,
            reelService: _emptyReels(),
            onCreateReel: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
      await tester.pumpAndSettle();

      for (final key in <String>[
        'create-voice-moment-choice',
        'create-reel-choice',
      ]) {
        final tile = find.byKey(ValueKey<String>(key));
        final card = tester.widget<YoCard>(
          find.descendant(of: tile, matching: find.byType(YoCard)),
        );
        expect(card.radius, BorderRadius.circular(20));
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(72));
        final circle = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        expect(tester.getSize(circle), const Size(44, 44));
        expect(
          (tester.widget<Container>(circle).decoration! as BoxDecoration).color,
          AppTheme.lightTheme.colorScheme.primary.withValues(alpha: .14),
        );
      }
      expect(tester.takeException(), isNull);
    });

    for (final highContrast in <bool>[false, true]) {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        final palette = theme.extension<AppPalette>()!;
        testWidgets('the sheet edge is the palette '
            '${highContrast ? 'borderStrong' : 'hairline'} '
            '(${palette.isDark ? 'Dark' : 'Pearl'}, high contrast: '
            '$highContrast)', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(highContrast: highContrast),
                child: child!,
              ),
              home: MomentsScreen(
                isRootTab: true,
                initialFormat: YoMomentsFormat.reels,
                reelService: _emptyReels(),
                onCreateReel: () async {},
              ),
            ),
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
          await tester.pumpAndSettle();

          final sheet = tester.widget<Material>(
            find.byKey(const ValueKey<String>('yo-moments-create-sheet')),
          );
          final shape = sheet.shape! as RoundedRectangleBorder;
          expect(
            shape.borderRadius,
            const BorderRadius.vertical(top: Radius.circular(28)),
          );
          expect(
            shape.side.color,
            highContrast ? palette.borderStrong : palette.hairline,
          );
          expect(shape.side.width, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

/// An empty Yeels pool, so the screen needs no Firebase app.
ReelService _emptyReels() => ReelService(
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

/// A scrub target over a 20 s timeline that follows the finger.
class _ScrubTarget extends ChangeNotifier implements ReelScrubTarget {
  static const Duration total = Duration(seconds: 20);

  final ValueNotifier<Duration> position = ValueNotifier<Duration>(
    Duration.zero,
  );
  bool _scrubbing = false;

  @override
  bool get canSeek => true;

  @override
  bool get isScrubbing => _scrubbing;

  @override
  Future<void> beginScrub() async {
    _scrubbing = true;
    notifyListeners();
  }

  @override
  void scrubTo(Duration offset) => position.value = offset;

  @override
  Future<void> endScrub() async {
    _scrubbing = false;
    notifyListeners();
  }

  @override
  Future<void> seekBy(Duration delta) async {}

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }
}
