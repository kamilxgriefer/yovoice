import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/presentation/reel_visuals.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

void _useViewport(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Future<void> _pumpCanvas(
  WidgetTester tester, {
  required ThemeData theme,
  required Size viewport,
}) async {
  _useViewport(tester, viewport, textScale: 2);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ReelCompositionCanvas(
            composition: ReelComposition(
              originalAudioVolume: 0,
              crop: const ReelCropTransform(scale: 3, offsetX: 1, offsetY: -1),
              filter: ReelFilter.vivid,
              textOverlays: const <ReelTextOverlay>[
                ReelTextOverlay(
                  id: 'headline',
                  text:
                      'A long readable overlay that remains fully inside the '
                      'safe canvas even with enlarged text',
                  x: 1,
                  y: 0,
                  scale: 1.35,
                  color: ReelOverlayColor.light,
                ),
              ],
              linkOverlays: <ReelLinkOverlay>[
                ReelLinkOverlay(
                  id: 'link',
                  label: 'Open the attached link',
                  uri: Uri.parse('https://yovoice.app/reels'),
                  x: 0,
                  y: 1,
                ),
              ],
            ),
            media: const ColoredBox(color: Colors.orange),
            onOpenLink: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _contrast(Color first, Color second) {
  final light = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final dark = identical(light, first) ? second : first;
  return (light.computeLuminance() + .05) / (dark.computeLuminance() + .05);
}

void main() {
  group('canonical Reel renderer', () {
    for (final themeEntry in <String, ThemeData>{
      'Dark': AppTheme.darkTheme,
      'Pearl': AppTheme.lightTheme,
    }.entries) {
      for (final viewport in const <Size>[Size(320, 568), Size(390, 844)]) {
        testWidgets('${themeEntry.key} ${viewport.width.toInt()}x'
            '${viewport.height.toInt()} at 200% keeps overlays safe', (
          tester,
        ) async {
          await _pumpCanvas(
            tester,
            theme: themeEntry.value,
            viewport: viewport,
          );

          final canvas = tester.getRect(find.byType(ReelCompositionCanvas));
          final text = tester.getRect(
            find.byKey(const ValueKey('reel-text-overlay-headline')),
          );
          final link = tester.getRect(
            find.byKey(const ValueKey('reel-link-overlay-link')),
          );

          for (final overlay in <Rect>[text, link]) {
            expect(overlay.left, greaterThanOrEqualTo(canvas.left + 16));
            expect(overlay.right, lessThanOrEqualTo(canvas.right - 16));
            expect(overlay.top, greaterThanOrEqualTo(canvas.top + 16));
            expect(overlay.bottom, lessThanOrEqualTo(canvas.bottom - 132));
          }
          expect(link.height, greaterThanOrEqualTo(44));
          expect(tester.takeException(), isNull);
        });
      }
    }

    test('crop translation uses only the spare zoomed pixels', () {
      expect(
        reelCropTranslation(
          const Size(320, 568),
          const ReelCropTransform(scale: 3, offsetX: 1, offsetY: -1),
        ),
        const Offset(320, -568),
      );
      expect(
        reelCropTranslation(
          const Size(320, 568),
          const ReelCropTransform(scale: 1, offsetX: 1, offsetY: -1),
        ),
        Offset.zero,
      );
    });

    test('text and link pills remain AA-safe over black and white media', () {
      for (final color in ReelOverlayColor.values) {
        final foreground = reelOverlayColor(color);
        final surface = reelTextOverlaySurface(color);
        final outline = reelTextOverlayOutline(color);
        for (final media in const <Color>[Colors.black, Colors.white]) {
          final compositedSurface = Color.alphaBlend(surface, media);
          expect(
            _contrast(foreground, compositedSurface),
            greaterThanOrEqualTo(4.5),
            reason: '$color text contrast on $media',
          );
          expect(
            _contrast(outline, compositedSurface),
            greaterThanOrEqualTo(3),
            reason: '$color outline contrast on $media',
          );
        }
      }
      expect(
        _contrast(reelLinkOverlayForeground, reelLinkOverlaySurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(reelLinkOverlayOutline, reelLinkOverlaySurface),
        greaterThanOrEqualTo(3),
      );
    });

    test('filter and colour enums expose localized product names', () {
      const copy = AppLocalizations(Locale('pl'));
      expect(localizedReelFilter(copy, ReelFilter.original), 'Oryginalny');
      expect(localizedReelFilter(copy, ReelFilter.vivid), 'Żywy');
      expect(
        localizedReelOverlayColor(copy, ReelOverlayColor.accent),
        'Fioletowy',
      );
    });
  });

  group('composer previews and adaptive sheets', () {
    for (final themeEntry in <String, ThemeData>{
      'Dark': AppTheme.darkTheme,
      'Pearl': AppTheme.lightTheme,
    }.entries) {
      for (final viewport in const <Size>[Size(320, 568), Size(390, 844)]) {
        testWidgets('${themeEntry.key} source sheet fits '
            '${viewport.width.toInt()}x${viewport.height.toInt()} at 200%', (
          tester,
        ) async {
          _useViewport(tester, viewport, textScale: 2);
          await tester.pumpWidget(
            MaterialApp(
              theme: themeEntry.value,
              home: const ReelComposerScreen(),
            ),
          );
          await tester.tap(find.text('Choose media'));
          await tester.pumpAndSettle();

          expect(find.byType(YoModalSheetChrome), findsOneWidget);
          expect(
            find.byKey(const ValueKey('modal-sheet-close')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('modal-sheet-close')));
          await tester.pumpAndSettle();
          expect(find.byType(YoModalSheetChrome), findsNothing);
        });
      }
    }

    testWidgets('owned backing audio previews at selected trim and volume', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 844));
      final player = _RecordingAudioPlayer();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ReelComposerScreen(
            imagePicker: _ImagePickerStub(),
            backingAudioPicker: () async => ReelUploadPayload.backingAudio(
              bytes: Uint8List.fromList(<int>[
                0x49,
                0x44,
                0x33,
                ...List<int>.filled(509, 0),
              ]),
              durationMs: 30000,
            ),
            audioPlayerFactory: () => player,
          ),
        ),
      );

      await tester.tap(find.text('Choose media'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add your audio'));
      await tester.tap(find.text('Add your audio'));
      await tester.pump();

      final startSemantics = find.bySemanticsLabel(
        'Backing audio start position',
      );
      final startSlider = find.descendant(
        of: startSemantics,
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(startSlider);
      await tester.drag(startSlider, const Offset(90, 0));
      await tester.pump();
      final selectedStart = tester.widget<Slider>(startSlider).value.round();
      expect(selectedStart, greaterThan(0));

      await tester.ensureVisible(
        find.byKey(const ValueKey('reel-backing-audio-preview')),
      );
      await tester.tap(
        find.byKey(const ValueKey('reel-backing-audio-preview')),
      );
      await tester.pump();

      expect(player.sourceCount, 1);
      expect(player.recordedVolume, closeTo(.7, .001));
      expect(player.seekPositions.last.inMilliseconds, selectedStart);
      expect(player.resumeCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unsafe link stays in the dialog with a live inline error', (
      tester,
    ) async {
      _useViewport(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ReelComposerScreen(imagePicker: _ImagePickerStub()),
        ),
      );
      await tester.tap(find.text('Choose media'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add link'));
      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Unsafe link');
      await tester.enterText(
        find.byType(TextField).last,
        'http://localhost/admin',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      const error = 'Enter a label and a public HTTPS link.';
      expect(find.text(error), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text(error))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    });
  });

  group('feed renderer and report sheet', () {
    for (final themeEntry in <String, ThemeData>{
      'Dark': AppTheme.darkTheme,
      'Pearl': AppTheme.lightTheme,
    }.entries) {
      for (final viewport in const <Size>[Size(320, 568), Size(390, 844)]) {
        testWidgets('${themeEntry.key} feed is stable at '
            '${viewport.width.toInt()}x${viewport.height.toInt()} and 200%', (
          tester,
        ) async {
          _useViewport(tester, viewport, textScale: 2);
          await tester.pumpWidget(
            MaterialApp(
              theme: themeEntry.value,
              home: ReelsFeedScreen(
                embedded: true,
                service: _feedService(),
                videoBuilder: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF335577)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('reel-text-overlay-feed_text')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('reel-link-overlay-feed_link')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.byTooltip('Report Reel'));
          await tester.pumpAndSettle();
          expect(find.byType(YoModalSheetChrome), findsOneWidget);
          expect(
            find.byKey(const ValueKey('modal-sheet-close')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

ReelService _feedService() {
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'viewer'),
  );
  final composition = ReelComposition(
    crop: const ReelCropTransform(scale: 2, offsetX: .8, offsetY: -.8),
    trimStartMs: 0,
    trimEndMs: 10000,
    textOverlays: const <ReelTextOverlay>[
      ReelTextOverlay(id: 'feed_text', text: 'Feed overlay', x: .95, y: .12),
    ],
    linkOverlays: <ReelLinkOverlay>[
      ReelLinkOverlay(
        id: 'feed_link',
        label: 'YO Voice',
        uri: Uri.parse('https://yovoice.app'),
        x: .05,
        y: .65,
      ),
    ],
  );
  return ReelService(
    auth: auth,
    callableInvoker: (name, payload) async {
      if (name == 'listReels') {
        return <Object?, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'reel_feed_1',
              'authorId': 'creator_1',
              'authorName': 'Creator',
              'media': <String, Object?>{
                'kind': 'video',
                'contentType': 'video/mp4',
                'size': 4096,
                'generation': '7',
                'durationMs': 10000,
              },
              'backingAudio': null,
              'composition': composition.toWire(),
              'publishedAtMillis': 1725000000000,
              'sortKey': '1725000000000_reel_feed_1',
            },
          ],
          'nextCursor': null,
        };
      }
      if (name == 'getReelMediaAccess') {
        return <Object?, Object?>{
          'schemaVersion': 1,
          'url': 'https://storage.googleapis.com/yovoice/reel.mp4?token=test',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
        };
      }
      throw StateError('Unexpected callable $name with $payload');
    },
  );
}

class _ImagePickerStub extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    final decoded = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    return XFile.fromData(
      Uint8List.fromList(<int>[...decoded, ...List<int>.filled(128, 0)]),
      mimeType: 'image/png',
      name: 'reel.png',
    );
  }
}

class _RecordingAudioPlayer implements AudioPlayer {
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  int sourceCount = 0;
  int resumeCount = 0;
  double recordedVolume = 1;
  final List<Duration> seekPositions = <Duration>[];

  @override
  Stream<PlayerState> get onPlayerStateChanged => _states.stream;

  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Future<void> setSource(Source source) async => sourceCount += 1;

  @override
  Future<void> setVolume(double value) async => recordedVolume = value;

  @override
  Future<void> seek(Duration position) async => seekPositions.add(position);

  @override
  Future<void> resume() async {
    resumeCount += 1;
    _states.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async => _states.add(PlayerState.paused);

  @override
  Future<void> stop() async => _states.add(PlayerState.stopped);

  @override
  Future<void> dispose() async => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
