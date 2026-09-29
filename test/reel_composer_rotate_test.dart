// "Obróć" in the Yeel composer (ADR-235, owner decision B): where the pill
// appears, how it looks and reads, what a tap does, and what Publish uploads.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake_bytes.dart';
import 'package:yovoice/features/reels/presentation/reel_video_backdrop_policy.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_draft_preview.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_rotate_pill.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

import 'reel_fit_test_support.dart';

const _pill = ValueKey<String>('reel-rotate-video');
const _plate = ValueKey<String>('reel-rotate-video-plate');
const _ring = ValueKey<String>('reel-rotate-video-focus-ring');
const _cropReset = ValueKey<String>('reel-rotate-crop-reset');

final Uint8List _pixelClip = File(
  'test/fixtures/reels/reel_landscape_faststart.mp4',
).readAsBytesSync();

const _rotatable = ReelVideoOrientation(
  length: 1211,
  tracks: <ReelVideoTrackOrientation>[
    ReelVideoTrackOrientation(
      handler: 'vide',
      tkhdVersion: 0,
      matrixOffset: 200,
      quarterTurns: 0,
      widthFixed: 64 * 0x10000,
      heightFixed: 36 * 0x10000,
    ),
  ],
);

class _Picker extends ImagePicker {
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => XFile.fromData(
    Uint8List.fromList(_pixelClip),
    mimeType: 'video/mp4',
    name: 'kot.mp4',
    path: 'kot.mp4',
  );

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    return XFile.fromData(
      Uint8List.fromList(<int>[...png, ...List<int>.filled(128, 0)]),
      mimeType: 'image/png',
      name: 'reel.png',
    );
  }
}

/// Bakes in memory with the real patcher and records every call.
class _Baker extends ReelVideoRotationBaker {
  _Baker({this.failure});

  final ReelVideoRotationException? failure;

  /// What [isIntact] answers: false models a copy the OS trimmed from the
  /// cache directory between two attempts.
  bool intact = true;
  final intactChecks = <ReelUploadPayload>[];
  final bakes = <(ReelUploadPayload, int)>[];
  final discarded = <ReelUploadPayload>[];
  final baked = <ReelUploadPayload>[];
  int sweeps = 0;

  @override
  Future<ReelUploadPayload> bake(
    ReelUploadPayload source,
    int quarterTurns,
  ) async {
    bakes.add((source, quarterTurns));
    if (failure != null) throw failure!;
    final result = await bakeReelVideoRotationBytes(source, quarterTurns);
    baked.add(result);
    return result;
  }

  @override
  Future<void> discard(ReelUploadPayload baked) async => discarded.add(baked);

  @override
  Future<void> sweep() async => sweeps += 1;

  @override
  Future<bool> isIntact(ReelUploadPayload baked) async {
    intactChecks.add(baked);
    return intact;
  }
}

ReelService _service({
  List<Map<String, Object?>>? reserves,
  List<ReelUploadPayload>? uploads,
  Future<String> Function(ReelUploadPayload payload)? upload,
  Future<Map<Object?, Object?>> Function()? reserve,
}) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    if (name == 'reserveReelDraftV2') {
      reserves?.add(Map<String, Object?>.of(payload));
      if (reserve != null) return reserve();
      return <Object?, Object?>{
        'schemaVersion': 2,
        'reelId': 'rotated_reel',
        'mediaStoragePath': 'reels/creator-1/rotated_reel/media.mp4',
        'backingAudioStoragePath': null,
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        'availabilityHours': 24,
        'contentExpiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch,
      };
    }
    throw StateError('finalize refused in this suite');
  },
  uploadInvoker:
      ({
        required storagePath,
        required payload,
        required metadata,
        onProgress,
      }) async {
        uploads?.add(payload);
        if (upload != null) return upload(payload);
        return '123';
      },
);

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 8; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _choose(WidgetTester tester, String label) async {
  final choose = find.byKey(const ValueKey('reel-choose-media'));
  await tester.ensureVisible(choose);
  await tester.tap(choose);
  await _settle(tester);
  if (find.text('Replace media').evaluate().isNotEmpty &&
      find.byType(AlertDialog).evaluate().isNotEmpty) {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Replace media'),
      ),
    );
    // The dialog's exit transition, then the sheet's entrance.
    await _settle(tester);
    await _settle(tester);
  }
  await tester.tap(find.text(label));
  await _settle(tester);
}

Future<void> _next(WidgetTester tester) async {
  final next = find.byKey(const ValueKey('reel-next-step'));
  await tester.ensureVisible(next);
  await tester.tap(next);
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  final back = find.byKey(const ValueKey('reel-previous-step'));
  await tester.ensureVisible(back);
  await tester.tap(back);
  await _settle(tester);
}

Future<void> _tapPill(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_pill));
  await tester.tap(find.byKey(_pill));
  await tester.pump();
}

ReelDraftPreview _preview(WidgetTester tester) =>
    tester.widget<ReelDraftPreview>(find.byType(ReelDraftPreview));

VoidCallback? _pillTap(WidgetTester tester) =>
    tester.widget<ReelRotatePill>(find.byKey(_pill)).onTap;

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _composer({
  ReelService? service,
  ReelVideoRotationScanner? scanner,
  _Baker? baker,
  VideoPlayerController Function(String path)? controller,
  ValueChanged<String>? onPublished,
}) => ReelComposerScreen(
  service: service ?? _service(),
  imagePicker: _Picker(),
  videoDurationProbe: (_) async => 12000,
  videoControllerFactory:
      controller ?? (_) => FakeSizedVideoController(const Size(1920, 1080)),
  videoRotationScanner: scanner ?? (_) async => _rotatable,
  videoRotationBaker: baker ?? _Baker(),
  onPublished: onPublished,
);

void main() {
  // The label-fit rule measures real glyphs: load the app's Inter so the
  // widths match a device instead of the test font's square glyphs.
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
  });
  setUp(
    () => ReelVideoBackdropPolicy.debugOverride = ReelVideoBackdrop.blurred,
  );
  tearDown(() => ReelVideoBackdropPolicy.debugOverride = null);

  group('visibility', () {
    testWidgets('a rotatable video shows the pill in edit and review', (
      tester,
    ) async {
      _bigView(tester);
      final baker = _Baker();
      await tester.pumpWidget(_host(_composer(baker: baker)));
      expect(baker.sweeps, 1, reason: 'stale copies are swept on open');
      expect(find.byKey(_pill), findsNothing, reason: 'media step');
      await _choose(tester, 'Choose video');
      expect(find.byKey(_pill), findsOneWidget, reason: 'edit step');
      expect(_pillTap(tester), isNotNull);
      await _next(tester);
      expect(find.byKey(_pill), findsOneWidget, reason: 'review step');
      await _back(tester);
      await _back(tester);
      expect(find.byKey(_pill), findsNothing, reason: 'back in the media step');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no pill for a photo', (tester) async {
      _bigView(tester);
      await tester.pumpWidget(_host(_composer()));
      await _choose(tester, 'Choose photo');
      expect(find.byType(ReelDraftPreview), findsOneWidget);
      expect(find.byKey(_pill), findsNothing);
    });

    testWidgets('no pill for an unsupported scan, none while it is pending', (
      tester,
    ) async {
      _bigView(tester);
      final pending = Completer<ReelVideoOrientation?>();
      await tester.pumpWidget(_host(_composer(scanner: (_) => pending.future)));
      await _choose(tester, 'Choose video');
      expect(find.byKey(_pill), findsNothing, reason: 'scan pending');
      pending.complete(null);
      await _settle(tester);
      expect(find.byKey(_pill), findsNothing, reason: 'not rotatable');
    });

    testWidgets('the real scanner offers the pill for the Pixel-style clip', (
      tester,
    ) async {
      _bigView(tester);
      await tester.pumpWidget(
        _host(
          ReelComposerScreen(
            service: _service(),
            imagePicker: _Picker(),
            videoDurationProbe: (_) async => 12000,
            videoControllerFactory: (_) =>
                FakeSizedVideoController(const Size(1920, 1080)),
            videoRotationBaker: _Baker(),
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      expect(find.byKey(_pill), findsOneWidget);
    });

    testWidgets('no pill while the preview is preparing or has failed', (
      tester,
    ) async {
      _bigView(tester);
      final gate = Completer<void>();
      await tester.pumpWidget(
        _host(_composer(controller: (_) => _GatedController(gate))),
      );
      await _choose(tester, 'Choose video');
      expect(find.byKey(_pill), findsNothing, reason: 'decoder preparing');
      gate.completeError(StateError('decoder refused'));
      await _settle(tester);
      expect(find.text('Retry preview'), findsOneWidget);
      expect(find.byKey(_pill), findsNothing, reason: 'preview failed');
    });

    testWidgets('disabled while publishing and once reserved', (tester) async {
      _bigView(tester);
      final upload = Completer<String>();
      final service = _service(upload: (_) => upload.future);
      await tester.pumpWidget(_host(_composer(service: service)));
      await _choose(tester, 'Choose video');
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      tester
          .widget<YoButton>(find.byKey(const ValueKey('reel-publish')))
          .onPressed!();
      await _settle(tester);
      expect(find.byKey(_pill), findsOneWidget);
      expect(_pillTap(tester), isNull, reason: 'publishing');
      upload.completeError(StateError('upload lost'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('reel-composer-error')), findsOneWidget);
      expect(_pillTap(tester), isNull, reason: 'a reservation exists');
    });
  });

  group('pill geometry and semantics', () {
    Future<void> pumpPreview(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
      Locale locale = const Locale('en'),
      int turns = 0,
      VoidCallback? onRotate,
    }) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: ReelDraftPreview(
                  media: ReelUploadPayload(
                    bytes: _pixelClip,
                    contentType: 'video/mp4',
                    durationMs: 12000,
                    sourcePath: '/tmp/kot.mp4',
                  ),
                  composition: const ReelComposition(
                    trimEndMs: 12000,
                    originalAudioVolume: 100,
                  ),
                  videoControllerFactory: (_) =>
                      FakeSizedVideoController(const Size(1920, 1080)),
                  videoQuarterTurns: turns,
                  onRotate: onRotate ?? () {},
                ),
              ),
            ),
          ),
          locale: locale,
          textScale: textScale,
        ),
      );
      await _settle(tester);
    }

    testWidgets('48 px target, 36 px plate, 4 px from the top-end corner', (
      tester,
    ) async {
      await pumpPreview(tester, size: const Size(350 * 9 / 16, 350));
      final preview = tester.getRect(find.byType(ReelDraftPreview));
      final target = tester.getRect(find.byKey(_pill));
      final plate = tester.getRect(find.byKey(_plate));
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.width, greaterThanOrEqualTo(48));
      expect(plate.height, 36);
      expect(target.top - preview.top, 4);
      expect(preview.right - target.right, 4);
      expect(find.text('Rotate'), findsOneWidget);
      // Inside the preview's 24 px rounded clip: the plate's far corner
      // stays within the corner circle.
      final corner = Offset(preview.right - 24, preview.top + 24);
      final plateCorner = Offset(plate.right - 18, plate.top + 18);
      final far = plateCorner + const Offset(18, -18) / 1.4142;
      expect((far - corner).distance, lessThan(24));
    });

    for (final locale in const <Locale>[Locale('ar'), Locale('he')]) {
      testWidgets('mirrors to the top-left in ${locale.languageCode}', (
        tester,
      ) async {
        await pumpPreview(
          tester,
          size: const Size(350 * 9 / 16, 350),
          locale: locale,
        );
        final preview = tester.getRect(find.byType(ReelDraftPreview));
        final target = tester.getRect(find.byKey(_pill));
        expect(target.top - preview.top, 4);
        expect(target.left - preview.left, 4);
      });
    }

    testWidgets('icon only at 180 px and 200% text, labelled at 350 and wide', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        size: const Size(180 * 9 / 16, 180),
        textScale: 2,
      );
      expect(find.byKey(_pill), findsOneWidget);
      expect(find.text('Rotate'), findsNothing);
      expect(find.byIcon(Icons.rotate_90_degrees_cw_rounded), findsOneWidget);
      expect(tester.getSize(find.byKey(_plate)), const Size(36, 36));
      expect(tester.getSize(find.byKey(_pill)), const Size(48, 48));
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.byKey(_plate), matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, 'Rotate video 90° clockwise');

      await pumpPreview(tester, size: const Size(350 * 9 / 16, 350));
      expect(find.text('Rotate'), findsOneWidget);

      await pumpPreview(tester, size: const Size(315, 560), textScale: 2);
      expect(find.text('Rotate'), findsOneWidget);
    });

    const copy = <String, (String, String)>{
      'en': ('Rotate', 'Rotate video 90° clockwise'),
      'pl': ('Obróć', 'Obróć film o 90° w prawo'),
      'de': ('Drehen', 'Video um 90° im Uhrzeigersinn drehen'),
    };
    for (final entry in copy.entries) {
      testWidgets('label, tooltip and semantics in ${entry.key}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpPreview(
          tester,
          size: const Size(315, 560),
          locale: Locale(entry.key),
        );
        expect(find.text(entry.value.$1), findsOneWidget);
        expect(
          tester
              .widget<Tooltip>(
                find.ancestor(
                  of: find.byKey(_plate),
                  matching: find.byType(Tooltip),
                ),
              )
              .message,
          entry.value.$2,
        );
        expect(find.bySemanticsLabel(entry.value.$2), findsOneWidget);
        semantics.dispose();
      });
    }

    testWidgets('the value announces the turn', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPreview(tester, size: const Size(315, 560), turns: 1);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Rotate video 90° clockwise'),
      );
      expect(node.value, 'Rotated 90°');
      await pumpPreview(
        tester,
        size: const Size(315, 560),
        turns: 3,
        locale: const Locale('pl'),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Obróć film o 90° w prawo'))
            .value,
        'Obrócono o 270°',
      );
      semantics.dispose();
    });

    testWidgets('keyboard Enter activates it', (tester) async {
      var taps = 0;
      await pumpPreview(
        tester,
        size: const Size(315, 560),
        onRotate: () => taps += 1,
      );
      bool focused() {
        final context = FocusManager.instance.primaryFocus?.context;
        return context != null &&
            context.findAncestorWidgetOfExactType<ReelRotatePill>() != null;
      }

      for (var index = 0; index < 6 && !focused(); index += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('focus is drawn on the plate, inside the rounded corner', (
      tester,
    ) async {
      await pumpPreview(tester, size: const Size(350 * 9 / 16, 350));
      // No hover ring, ink or focus ring on the 48 px target.
      expect(
        tester
            .widget<AccessibleTapRegion>(
              find.descendant(
                of: find.byKey(_pill),
                matching: find.byType(AccessibleTapRegion),
              ),
            )
            .paintsIndicators,
        isFalse,
      );
      expect(find.byKey(_ring), findsNothing);
      for (
        var index = 0;
        index < 6 && find.byKey(_ring).evaluate().isEmpty;
        index += 1
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(find.byKey(_ring), findsOneWidget);
      final plate = tester.getRect(find.byKey(_plate));
      final ring = tester.getRect(find.byKey(_ring));
      expect(ring, plate.inflate(ReelRotatePill.focusRingGap));
      // Every point of the ring's end arc that lies in the preview's corner
      // square is inside its 24 px rounded clip.
      final preview = tester.getRect(find.byType(ReelDraftPreview));
      final clipCentre = Offset(preview.right - 24, preview.top + 24);
      final radius = ring.height / 2;
      final arcCentre = Offset(ring.right - radius, ring.top + radius);
      for (var degrees = 0; degrees <= 90; degrees += 1) {
        final angle = degrees * math.pi / 180;
        final point =
            arcCentre + Offset(math.cos(angle), -math.sin(angle)) * radius;
        if (point.dx > clipCentre.dx && point.dy < clipCentre.dy) {
          expect(
            (point - clipCentre).distance,
            lessThanOrEqualTo(24.01),
            reason: '$degrees°',
          );
        }
      }
    });

    test('every locale\'s visible label is part of its accessible name', () {
      // WCAG 2.5.3: a voice-control user says what they see.
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        final label = copy
            .contextualText('reels.composer.rotate', 'Rotate', 'Obróć')
            .toLowerCase();
        final name = copy
            .text('Rotate video 90° clockwise', 'Obróć film o 90° w prawo')
            .toLowerCase();
        expect(name, contains(label), reason: '$locale');
      }
    });
  });

  group('tapping', () {
    testWidgets('turns 1, 2, 3, 0; crop resets; decoder untouched; fit flips', (
      tester,
    ) async {
      _bigView(tester);
      final controllers = <FakeSizedVideoController>[];
      await tester.pumpWidget(
        _host(
          _composer(
            controller: (_) {
              final controller = FakeSizedVideoController(
                const Size(1920, 1080),
              );
              controllers.add(controller);
              return controller;
            },
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      final state = tester.state<ReelDraftPreviewState>(
        find.byType(ReelDraftPreview),
      );
      final preparations = state.debugPreparations;
      expect(find.byType(ImageFiltered), findsOneWidget, reason: 'contain');

      final seen = <int>[];
      for (var tap = 0; tap < 4; tap += 1) {
        _preview(tester).onCropChanged!(
          const ReelCropTransform(scale: 2, offsetX: .5),
        );
        await tester.pump();
        expect(_preview(tester).composition.crop.scale, 2);
        await _tapPill(tester);
        seen.add(_preview(tester).videoQuarterTurns);
        expect(
          _preview(tester).composition.crop,
          const ReelCropTransform(),
          reason: 'tap ${tap + 1} resets the crop',
        );
        // Re-evaluated in the same frame: upright on odd turns.
        expect(
          find.byType(ImageFiltered),
          seen.last.isOdd ? findsNothing : findsOneWidget,
        );
      }
      expect(seen, <int>[1, 2, 3, 0]);
      expect(state.debugPreparations, preparations);
      expect(controllers, hasLength(1));
      expect(controllers.single.initializeCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('position sliders follow the pan limits per axis', (
      tester,
    ) async {
      _bigView(tester);
      await tester.pumpWidget(_host(_composer()));
      await _choose(tester, 'Choose video');
      List<Slider> sliders() =>
          tester.widgetList<Slider>(find.byType(Slider)).toList();

      // 16:9 contained, 2×: horizontal pans, vertical has nothing to pan into.
      _preview(tester).onCropChanged!(const ReelCropTransform(scale: 2));
      await _settle(tester);
      expect(sliders()[1].onChanged, isNotNull);
      expect(sliders()[2].onChanged, isNull);
      // The locked axis is explained: zooming in further frees it.
      expect(find.text('Zoom in to reposition the frame.'), findsOneWidget);

      // One turn: an upright cover, both axes pan as they always did.
      await _tapPill(tester);
      await _settle(tester);
      _preview(tester).onCropChanged!(const ReelCropTransform(scale: 2));
      await _settle(tester);
      expect(sliders()[1].onChanged, isNotNull);
      expect(sliders()[2].onChanged, isNotNull);
      expect(find.text('Zoom in to reposition the frame.'), findsNothing);
    });

    testWidgets('a tap that resets a crop says so, and Undo takes it back', (
      tester,
    ) async {
      _bigView(tester);
      final baker = _Baker();
      await tester.pumpWidget(_host(_composer(baker: baker)));
      await _choose(tester, 'Choose video');
      // An untouched crop loses nothing: no notice.
      await _tapPill(tester);
      await _settle(tester);
      expect(find.byKey(_cropReset), findsNothing);

      const framed = ReelCropTransform(scale: 2, offsetX: .5, offsetY: -.25);
      _preview(tester).onCropChanged!(framed);
      await tester.pump();
      await _tapPill(tester);
      await _settle(tester);
      expect(find.byKey(_cropReset), findsOneWidget);
      expect(find.text('Rotating reset the crop.'), findsOneWidget);
      expect(_preview(tester).videoQuarterTurns, 2);
      expect(_preview(tester).composition.crop.scale, 1);

      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(_preview(tester).videoQuarterTurns, 1);
      final restored = _preview(tester).composition.crop;
      expect(
        (restored.scale, restored.offsetX, restored.offsetY),
        (2.0, .5, -.25),
      );

      // A newer tap retires the notice: its Undo can never act on a draft
      // it no longer describes.
      _preview(tester).onCropChanged!(framed);
      await tester.pump();
      await _tapPill(tester);
      await _settle(tester);
      expect(find.byKey(_cropReset), findsOneWidget);
      await _tapPill(tester);
      await _settle(tester);
      await _settle(tester);
      expect(find.byKey(_cropReset), findsNothing);
      expect(_preview(tester).videoQuarterTurns, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Polish names the crop reset and its Undo', (tester) async {
      _bigView(tester);
      await tester.pumpWidget(_host(_composer(), locale: const Locale('pl')));
      await _choose(tester, 'Wybierz film');
      _preview(tester).onCropChanged!(const ReelCropTransform(scale: 2));
      await tester.pump();
      await _tapPill(tester);
      await _settle(tester);
      expect(find.text('Obrót zresetował kadr.'), findsOneWidget);
      expect(find.text('Cofnij'), findsOneWidget);
    });

    testWidgets(
      'the Text tool hides the pill so a corner caption stays draggable',
      (tester) async {
        _bigView(tester);
        await tester.pumpWidget(_host(_composer()));
        await _choose(tester, 'Choose video');
        expect(find.byKey(_pill), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('reel-tool-text')),
        );
        await tester.tap(find.byKey(const ValueKey('reel-tool-text')));
        await _settle(tester);
        expect(find.byKey(_pill), findsNothing);
        await tester.ensureVisible(find.text('Add text'));
        await tester.tap(find.text('Add text'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Corner');
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await _settle(tester);
        final id = _preview(tester).composition.textOverlays.single.id;
        final handle = find.byKey(ValueKey('reel-text-overlay-handle-$id'));
        await tester.ensureVisible(find.byType(ReelDraftPreview));
        // Into the top-end corner, where the pill sits in the other tools.
        final far = await tester.startGesture(tester.getCenter(handle));
        await far.moveBy(const Offset(5000, -5000));
        await tester.pump();
        await far.up();
        await _settle(tester);
        var overlay = _preview(tester).composition.textOverlays.single;
        expect(overlay.x, 1);
        expect(overlay.y, 0);
        expect(find.byKey(_pill), findsNothing);
        // It is still the caption that answers a drag in that corner.
        final back = await tester.startGesture(tester.getCenter(handle));
        await back.moveBy(const Offset(-40, 40));
        await tester.pump();
        await back.up();
        await _settle(tester);
        overlay = _preview(tester).composition.textOverlays.single;
        expect(overlay.x, lessThan(1));
        expect(overlay.y, greaterThan(0));
        // Any other tool brings the pill back.
        await tester.ensureVisible(
          find.byKey(const ValueKey('reel-tool-crop')),
        );
        await tester.tap(find.byKey(const ValueKey('reel-tool-crop')));
        await _settle(tester);
        expect(find.byKey(_pill), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('picking new media resets the turns', (tester) async {
      _bigView(tester);
      final baker = _Baker();
      await tester.pumpWidget(_host(_composer(baker: baker)));
      await _choose(tester, 'Choose video');
      await _tapPill(tester);
      expect(_preview(tester).videoQuarterTurns, 1);
      await _back(tester);
      await _choose(tester, 'Choose video');
      expect(_preview(tester).videoQuarterTurns, 0);
      // The new clip's size reaches the sliders even though it equals the
      // old one's: a contained 16:9 at 2× has nothing to pan vertically.
      _preview(tester).onCropChanged!(const ReelCropTransform(scale: 2));
      await _settle(tester);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders[1].onChanged, isNotNull);
      expect(sliders[2].onChanged, isNull);
    });
  });

  group('publish', () {
    testWidgets('one turn uploads a same-size copy rotated once', (
      tester,
    ) async {
      _bigView(tester);
      final reserves = <Map<String, Object?>>[];
      final uploads = <ReelUploadPayload>[];
      final baker = _Baker();
      await tester.pumpWidget(
        _host(
          _composer(
            service: _service(reserves: reserves, uploads: uploads),
            baker: baker,
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      final original = _preview(tester).media;
      await _tapPill(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);

      expect(baker.bakes, hasLength(1));
      expect(identical(baker.bakes.single.$1, original), isTrue);
      expect(baker.bakes.single.$2, 1);
      expect(reserves.single['mediaSize'], original.size);
      expect(reserves.single['mediaContentType'], original.contentType);
      final uploaded = uploads.single;
      expect(uploaded.size, original.size);
      expect(uploaded.contentType, original.contentType);
      final bytes = await uploaded.readBytes();
      final scan = await scanReelVideoOrientation(bytesRangeReader(bytes));
      expect(scan.orientation!.tracks.single.quarterTurns, 1);
      expect(
        bytes,
        File(
          'test/fixtures/reels/reel_landscape_faststart.rot1.mp4',
        ).readAsBytesSync(),
      );
    });

    testWidgets('no turn uploads the original payload instance', (
      tester,
    ) async {
      _bigView(tester);
      final uploads = <ReelUploadPayload>[];
      final baker = _Baker();
      await tester.pumpWidget(
        _host(
          _composer(
            service: _service(uploads: uploads),
            baker: baker,
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      final original = _preview(tester).media;
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);
      expect(baker.bakes, isEmpty);
      expect(identical(uploads.single, original), isTrue);
    });

    testWidgets('a bake failure is named, unlocks the draft and keeps turns', (
      tester,
    ) async {
      _bigView(tester);
      final reserves = <Map<String, Object?>>[];
      await tester.pumpWidget(
        _host(
          _composer(
            service: _service(reserves: reserves),
            baker: _Baker(
              failure: const ReelVideoRotationException(
                ReelVideoRotationFailure.noSpace,
              ),
            ),
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      await _tapPill(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);
      expect(reserves, isEmpty);
      // Only a full disk can succeed on a plain retry, so only it says so.
      expect(
        find.text(
          'The rotated video could not be prepared: there is not enough free space. Free up some space and try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Photos up to 10 MB. Videos: 1 second – 5 minutes, up to 100 MB.',
        ),
        findsNothing,
      );
      expect(_preview(tester).videoQuarterTurns, 1);
      expect(_pillTap(tester), isNotNull, reason: 'the draft is unlocked');
      expect(
        tester
            .widget<YoButton>(find.byKey(const ValueKey('reel-publish')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('Polish names the rotation failure too', (tester) async {
      _bigView(tester);
      await tester.pumpWidget(
        _host(
          _composer(
            baker: _Baker(
              failure: const ReelVideoRotationException(
                ReelVideoRotationFailure.sourceMissing,
              ),
            ),
          ),
          locale: const Locale('pl'),
        ),
      );
      await _choose(tester, 'Wybierz film');
      await _tapPill(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);
      // A vanished source fails the same way every time: the two ways out,
      // never "try again".
      expect(
        find.text(
          'Nie udało się przygotować obróconego filmu. Wybierz film ponownie albo obróć go z powrotem, aby opublikować go bez zmian.',
        ),
        findsOneWidget,
      );
    });

    for (final reason in const <ReelVideoRotationFailure>[
      ReelVideoRotationFailure.sourceMissing,
      ReelVideoRotationFailure.sourceChanged,
      ReelVideoRotationFailure.unsupported,
    ]) {
      testWidgets('${reason.name} asks to choose again or rotate back', (
        tester,
      ) async {
        _bigView(tester);
        await tester.pumpWidget(
          _host(
            _composer(
              baker: _Baker(failure: ReelVideoRotationException(reason)),
            ),
          ),
        );
        await _choose(tester, 'Choose video');
        await _tapPill(tester);
        await _next(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
        await tester.tap(find.byKey(const ValueKey('reel-publish')));
        await _settle(tester);
        expect(
          find.text(
            'The rotated video could not be prepared. Choose the video again, or rotate it back to publish it as it was.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Try again'), findsNothing);
      });
    }

    testWidgets('a copy trimmed since the last attempt is baked again', (
      tester,
    ) async {
      _bigView(tester);
      var reserveCalls = 0;
      final uploads = <ReelUploadPayload>[];
      final baker = _Baker();
      await tester.pumpWidget(
        _host(
          _composer(
            baker: baker,
            service: _service(
              uploads: uploads,
              reserve: () async {
                reserveCalls += 1;
                // The first attempt never obtains a reservation.
                throw StateError('reserve refused');
              },
            ),
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      await _tapPill(tester);
      await _next(tester);
      final publish = find.byKey(const ValueKey('reel-publish'));
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await _settle(tester);
      expect(baker.bakes, hasLength(1));

      // Intact: the retry reuses the copy.
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await _settle(tester);
      expect(baker.bakes, hasLength(1));
      expect(baker.intactChecks, hasLength(1));

      // Trimmed by the OS: bake afresh instead of failing every retry, and
      // the stale copy is deleted once that attempt is over.
      baker.intact = false;
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await _settle(tester);
      expect(baker.bakes, hasLength(2));
      expect(identical(baker.bakes[1].$1, baker.bakes[0].$1), isTrue);
      expect(baker.discarded, hasLength(1));
      expect(identical(baker.discarded.single, baker.baked.first), isTrue);
      expect(reserveCalls, 3);
      expect(uploads, isEmpty);
    });

    testWidgets(
      'a retry reuses the baked copy; it is deleted only after success',
      (tester) async {
        _bigView(tester);
        final uploads = <ReelUploadPayload>[];
        var attempt = 0;
        final second = Completer<String>();
        final baker = _Baker();
        String? published;
        await tester.pumpWidget(
          _host(
            _composer(
              service: _service(
                uploads: uploads,
                upload: (_) {
                  attempt += 1;
                  if (attempt == 1) throw StateError('upload lost');
                  return second.future;
                },
              ),
              baker: baker,
              onPublished: (id) => published = id,
            ),
          ),
        );
        await _choose(tester, 'Choose video');
        await _tapPill(tester);
        await _next(tester);
        final publish = find.byKey(const ValueKey('reel-publish'));
        await tester.ensureVisible(publish);
        await tester.tap(publish);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('reel-composer-error')),
          findsOneWidget,
        );
        expect(baker.discarded, isEmpty);

        await tester.ensureVisible(publish);
        await tester.tap(publish);
        await _settle(tester);
        expect(baker.bakes, hasLength(1), reason: 'no second bake');
        expect(uploads, hasLength(2));
        expect(identical(uploads[0], uploads[1]), isTrue);
        expect(baker.discarded, isEmpty, reason: 'never while publishing');

        second.complete('456');
        await _settle(tester);
        // finalize is refused by this suite's service: a failed attempt keeps
        // the copy for the next retry.
        expect(published, isNull);
        expect(baker.discarded, isEmpty);
      },
    );

    testWidgets('the copy is deleted after a successful publish', (
      tester,
    ) async {
      _bigView(tester);
      final baker = _Baker();
      String? published;
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
        ),
        callableInvoker: (name, payload) async {
          if (name == 'reserveReelDraftV2') {
            return <Object?, Object?>{
              'schemaVersion': 2,
              'reelId': 'rotated_reel',
              'mediaStoragePath': 'reels/creator-1/rotated_reel/media.mp4',
              'backingAudioStoragePath': null,
              'expiresAtMillis': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
              'availabilityHours': 24,
              'contentExpiresAtMillis': 4102444800000,
            };
          }
          return <Object?, Object?>{
            'schemaVersion': 2,
            'reelId': 'rotated_reel',
            'published': true,
            'availabilityHours': 24,
            'expiresAtMillis': 4102444800000,
          };
        },
        uploadInvoker:
            ({
              required storagePath,
              required payload,
              required metadata,
              onProgress,
            }) async => '123',
      );
      await tester.pumpWidget(
        _host(
          _composer(
            service: service,
            baker: baker,
            onPublished: (id) => published = id,
          ),
        ),
      );
      await _choose(tester, 'Choose video');
      await _tapPill(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);
      expect(published, 'rotated_reel');
      expect(baker.discarded, hasLength(1));
      expect(identical(baker.discarded.single, baker.baked.single), isTrue);
    });

    testWidgets('discarding the draft deletes the copy', (tester) async {
      _bigView(tester);
      final baker = _Baker();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => _composer(
              baker: baker,
              service: _service(
                reserve: () async => throw StateError('reserve refused'),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _choose(tester, 'Choose video');
      await _tapPill(tester);
      await _next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-publish')));
      await tester.tap(find.byKey(const ValueKey('reel-publish')));
      await _settle(tester);
      expect(baker.baked, hasLength(1));
      expect(baker.discarded, isEmpty, reason: 'kept for the retry');

      await _back(tester);
      await _back(tester);
      await tester.pageBack();
      await _settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await _settle(tester);
      // Let the exit transition finish so the composer is disposed.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(ReelComposerScreen), findsNothing);
      expect(baker.discarded, hasLength(1));
      expect(identical(baker.discarded.single, baker.baked.single), isTrue);
    });
  });
}

/// A decoder that stays in "preparing" until [gate] completes.
class _GatedController extends FakeSizedVideoController {
  _GatedController(this.gate) : super(const Size(1920, 1080));
  final Completer<void> gate;

  @override
  Future<void> initialize() async {
    await gate.future;
    await super.initialize();
  }
}
