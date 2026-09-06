import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_draft_preview.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';

void main() {
  test(
    'crop gesture preserves stored zoom-space contract and clamps edges',
    () {
      const size = Size(180, 320);
      final unchanged = reelCropFromGesture(
        initial: const ReelCropTransform(),
        viewport: size,
        initialFocalPoint: const Offset(90, 160),
        focalPoint: const Offset(120, 190),
        gestureScale: 1,
      );
      expect(unchanged.offsetX, 0);
      expect(unchanged.offsetY, 0);
      final zoomed = reelCropFromGesture(
        initial: const ReelCropTransform(),
        viewport: size,
        initialFocalPoint: const Offset(90, 160),
        focalPoint: const Offset(135, 200),
        gestureScale: 2,
      );
      expect(zoomed.scale, 2);
      expect(zoomed.offsetX, .5);
      expect(zoomed.offsetY, .25);
      final clamped = reelCropFromGesture(
        initial: zoomed,
        viewport: size,
        initialFocalPoint: const Offset(90, 160),
        focalPoint: const Offset(10000, -10000),
        gestureScale: 10,
      );
      expect(clamped.scale, 8);
      expect(clamped.offsetX, 1);
      expect(clamped.offsetY, -1);
    },
  );

  test('overlay drag maps canvas pixels to the normalized safe area', () {
    const canvas = Size(390, 390 * 16 / 9);
    const insets = EdgeInsets.fromLTRB(16, 16, 16, 132);
    final same = reelOverlayPositionFromGesture(
      startX: .5,
      startY: .42,
      startFocalPoint: const Offset(100, 100),
      focalPoint: const Offset(100, 100),
      canvas: canvas,
      safeInsets: insets,
    );
    expect(same.x, .5);
    expect(same.y, .42);
    // Safe width is 358 px, so 35.8 px is exactly one tenth of the range.
    final moved = reelOverlayPositionFromGesture(
      startX: .5,
      startY: .42,
      startFocalPoint: Offset.zero,
      focalPoint: const Offset(35.8, 54.533),
      canvas: canvas,
      safeInsets: insets,
    );
    expect(moved.x, closeTo(.6, 1e-9));
    expect(moved.y, closeTo(.52, 1e-4));
    final clamped = reelOverlayPositionFromGesture(
      startX: .5,
      startY: .5,
      startFocalPoint: Offset.zero,
      focalPoint: const Offset(-9999, 9999),
      canvas: canvas,
      safeInsets: insets,
    );
    expect(clamped.x, 0);
    expect(clamped.y, 1);
    expect(reelTextOverlayScaleFromGesture(startScale: 1, gestureScale: 5), 2);
    expect(
      reelTextOverlayScaleFromGesture(startScale: 1, gestureScale: .1),
      .75,
    );
  });

  testWidgets('text overlays drag on the preview only in the Text tool', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: _composerService(),
          imagePicker: _ImagePickerStub(),
        ),
      ),
    );
    await _choosePhoto(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('reel-tool-text')));
    await tester.tap(find.byKey(const ValueKey('reel-tool-text')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add text'));
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Drag me');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    ReelDraftPreview preview() =>
        tester.widget<ReelDraftPreview>(find.byType(ReelDraftPreview));
    final overlay = preview().composition.textOverlays.single;
    expect(overlay.x, .5);
    final handle = find.byKey(
      ValueKey('reel-text-overlay-handle-${overlay.id}'),
    );
    await tester.ensureVisible(find.byType(ReelDraftPreview));
    expect(handle, findsOneWidget);
    final before = tester.getCenter(handle);
    final gesture = await tester.startGesture(before);
    await gesture.moveBy(const Offset(40, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final dragged = preview().composition.textOverlays.single;
    expect(dragged.x, greaterThan(.5));
    expect(dragged.y, greaterThan(.42));
    expect(dragged.text, 'Drag me');
    expect(
      preview().composition.validate(
        mediaKind: ReelMediaKind.image,
        durationMs: 0,
        hasBackingAudio: false,
      ),
      isNull,
    );
    final after = tester.getCenter(
      find.byKey(ValueKey('reel-text-overlay-handle-${overlay.id}')),
    );
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, greaterThan(before.dy));
    // A far drag clamps at the edge and the recipe stays publishable.
    final far = await tester.startGesture(after);
    await far.moveBy(const Offset(5000, 5000));
    await tester.pump();
    await far.up();
    await tester.pumpAndSettle();
    expect(preview().composition.textOverlays.single.x, 1);
    expect(
      preview().composition.validate(
        mediaKind: ReelMediaKind.image,
        durationMs: 0,
        hasBackingAudio: false,
      ),
      isNull,
    );
    // The Crop tool owns the pointer: no overlay handles there.
    await tester.ensureVisible(find.byKey(const ValueKey('reel-tool-crop')));
    await tester.tap(find.byKey(const ValueKey('reel-tool-crop')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('reel-text-overlay-handle-${overlay.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'steps preserve caption and compatible edits on confirmed replacement',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ReelComposerScreen(
            service: _composerService(),
            imagePicker: _ImagePickerStub(),
          ),
        ),
      );
      expect(find.text('Caption'), findsNothing);
      expect(find.text('Publish Reel'), findsNothing);
      await _choosePhoto(tester);
      expect(find.byType(ReelDraftPreview), findsOneWidget);
      expect(
        tester.getSize(find.byType(ReelDraftPreview)).height,
        lessThanOrEqualTo(350),
      );
      final zoom = find.bySemanticsLabel('Crop zoom');
      await tester.ensureVisible(zoom);
      final slider = find.descendant(of: zoom, matching: find.byType(Slider));
      tester.widget<Slider>(slider).onChanged!(2);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ReelDraftPreview));
      final pan = await tester.startGesture(
        tester.getCenter(find.byType(ReelDraftPreview)),
      );
      await pan.moveBy(const Offset(30, 0));
      await tester.pump();
      await pan.moveBy(const Offset(20, 10));
      await tester.pump();
      await pan.up();
      expect(
        tester
            .widget<ReelDraftPreview>(find.byType(ReelDraftPreview))
            .composition
            .crop
            .offsetX,
        greaterThan(0),
      );
      await _review(tester);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Keep my draft');
      for (var i = 0; i < 2; i++) {
        final back = find.byKey(const ValueKey('reel-previous-step'));
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Replace media'));
      await tester.pumpAndSettle();
      expect(find.text('Replace media?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Replace media'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReelDraftPreview>(find.byType(ReelDraftPreview))
            .composition
            .crop
            .scale,
        1,
      );
      await _review(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Keep my draft',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('composer exposes camera and library for photos and videos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: _composerService(),
          imagePicker: _ImagePickerStub(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Choose media'));
    await tester.tap(find.text('Choose media'));
    await tester.pumpAndSettle();

    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Record video'), findsOneWidget);
    expect(find.text('Choose video'), findsOneWidget);
  });

  testWidgets(
    'account changes discard draft and reject late picker across A B A',
    (tester) async {
      final service = _MutableComposerService();
      final pending = Completer<XFile?>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReelComposerScreen(
            service: service,
            imagePicker: _ImagePickerStub(pending: pending),
          ),
        ),
      );
      await tester.tap(find.text('Choose media'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pump();
      service.switchTo('B');
      await tester.pump();
      service.switchTo('A');
      await tester.pump();
      pending.complete(
        await _ImagePickerStub().pickImage(source: ImageSource.gallery),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReelDraftPreview), findsNothing);
      expect(find.text('Choose media'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await service.changes.close();
    },
  );

  testWidgets('account exit closes owned text dialog and forgets local media', (
    tester,
  ) async {
    final service = _MutableComposerService();
    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: service,
          imagePicker: _ImagePickerStub(),
        ),
      ),
    );
    await _choosePhoto(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('reel-tool-text')));
    await tester.tap(find.byKey(const ValueKey('reel-tool-text')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add text'));
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Private draft A');
    service.switchTo('B');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReelDraftPreview), findsNothing);
    expect(find.text('Private draft A'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await service.changes.close();
  });

  testWidgets(
    'text and link controllers survive normal dialog exit animations',
    (tester) async {
      final service = _MutableComposerService();
      await tester.pumpWidget(
        MaterialApp(
          home: ReelComposerScreen(
            service: service,
            imagePicker: _ImagePickerStub(),
          ),
        ),
      );
      await _choosePhoto(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('reel-tool-text')));
      await tester.tap(find.byKey(const ValueKey('reel-tool-text')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add text'));
      await tester.tap(find.text('Add text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My overlay');
      final route = ModalRoute.of(tester.element(find.byType(TextField).first));
      expect(route?.traversalEdgeBehavior, TraversalEdgeBehavior.closedLoop);
      for (var index = 0; index < 6; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        var inDialog = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (element.widget is AlertDialog) inDialog = true;
          return !inDialog;
        });
        expect(inDialog, isTrue, reason: 'Tab stays in the owned modal');
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      var preview = tester.widget<ReelDraftPreview>(
        find.byType(ReelDraftPreview),
      );
      expect(preview.composition.textOverlays.single.text, 'My overlay');

      await tester.ensureVisible(find.widgetWithText(InputChip, 'My overlay'));
      await tester.tap(find.widgetWithText(InputChip, 'My overlay'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Edited overlay');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      preview = tester.widget<ReelDraftPreview>(find.byType(ReelDraftPreview));
      expect(preview.composition.textOverlays.single.text, 'Edited overlay');

      await tester.ensureVisible(find.text('Add link'));
      await tester.tap(find.text('Add link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Visit');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      preview = tester.widget<ReelDraftPreview>(find.byType(ReelDraftPreview));
      expect(preview.composition.linkOverlays.single.label, 'Visit');
      final retainedTextAction = tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'Edited overlay'))
          .onPressed!;
      final retainedLinkAction = tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'Visit'))
          .onPressed!;
      service.switchTo('B');
      // Old widgets can still dispatch before the account-change rebuild.
      retainedTextAction();
      retainedLinkAction();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ReelDraftPreview), findsNothing);
      expect(find.text('Edited overlay'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await service.changes.close();
    },
  );

  testWidgets('composer keeps controls readable on a wide canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: _composerService(),
          imagePicker: _ImagePickerStub(),
        ),
      ),
    );
    expect(find.text('Create Reel'), findsOneWidget);
    await _choosePhoto(tester);
    expect(find.text('Caption'), findsNothing);
    await _review(tester);
    expect(find.text('Caption'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('availability defaults to 24h and supports custom hours/days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: _composerService(),
          imagePicker: _ImagePickerStub(),
        ),
      ),
    );
    await _choosePhoto(tester);
    await _review(tester);

    final picker = find.byKey(
      const ValueKey<String>('reel-availability-picker'),
    );
    await tester.ensureVisible(picker);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('reel-availability-24')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reel-availability-custom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-availability-amount')),
      '23',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-availability-apply')),
    );
    await tester.pump();
    expect(find.textContaining('24–720'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-availability-amount')),
      '2',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-availability-unit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Days').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reel-availability-amount')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-availability-apply')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Custom · 48h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous publish ACK freezes one plan and reuses its session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var reserveCount = 0;
    var uploadCount = 0;
    var finalizeCount = 0;
    final finalizePayloads = <Map<String, Object?>>[];
    String? publishedId;
    final service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
      ),
      callableInvoker: (name, payload) async {
        if (name == 'reserveReelDraftV2') {
          reserveCount += 1;
          expectSync(payload['availabilityHours'], 'permanent');
          return <Object?, Object?>{
            'schemaVersion': 2,
            'reelId': 'retry_reel',
            'mediaStoragePath': 'reels/creator-1/retry_reel/media.png',
            'backingAudioStoragePath': null,
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
            'availabilityHours': 'permanent',
            'contentExpiresAtMillis': null,
          };
        }
        expectSync(name, 'finalizeReelDraftV2');
        finalizeCount += 1;
        finalizePayloads.add(Map<String, Object?>.of(payload));
        if (finalizeCount == 1) throw StateError('lost acknowledgement');
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reelId': 'retry_reel',
          'published': true,
          'availabilityHours': 'permanent',
          'expiresAtMillis': null,
        };
      },
      uploadInvoker:
          ({
            required storagePath,
            required payload,
            required metadata,
            onProgress,
          }) async {
            uploadCount += 1;
            return '123';
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReelComposerScreen(
          service: service,
          imagePicker: _ImagePickerStub(),
          onPublished: (value) => publishedId = value,
        ),
      ),
    );

    await tester.tap(find.text('Choose media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await _review(tester);
    final caption = find.byType(TextField).first;
    await tester.enterText(caption, 'Original caption');
    final permanent = find.byKey(
      const ValueKey<String>('reel-availability-permanent'),
    );
    await tester.ensureVisible(permanent);
    await tester.tap(permanent);
    await tester.ensureVisible(find.text('Publish Reel'));
    final publishButton = tester.widget<YoButton>(
      find.byKey(const ValueKey('reel-publish')),
    );
    publishButton.onPressed!();
    publishButton.onPressed!();
    await tester.pumpAndSettle();

    expect(
      finalizeCount,
      1,
      reason: 'Rapid submit is a single publish attempt',
    );
    expect(tester.widget<ChoiceChip>(permanent).selected, isTrue);
    expect(tester.widget<ChoiceChip>(permanent).onSelected, isNull);
    expect(find.text('Availability is locked for this retry.'), findsOneWidget);
    expect(tester.widget<TextField>(caption).readOnly, isTrue);

    await tester.ensureVisible(find.text('Publish Reel'));
    await tester.tap(find.text('Publish Reel'));
    await tester.pumpAndSettle();

    expect(publishedId, 'retry_reel');
    expect(reserveCount, 1);
    expect(uploadCount, 1);
    expect(finalizeCount, 2);
    expect(
      finalizePayloads.map((payload) => payload['requestId']).toSet(),
      hasLength(1),
    );
    expect(
      finalizePayloads
          .map((payload) => payload['composition']! as Map<Object?, Object?>)
          .map((composition) => composition['caption']),
      everyElement('Original caption'),
    );
  });

  testWidgets('availability picker survives 320px at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: ReelComposerScreen(
            service: _composerService(),
            imagePicker: _ImagePickerStub(),
          ),
        ),
      ),
    );
    final mediaLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('reel-choose-media')),
        matching: find.text('Choose media'),
      ),
    );
    expect(mediaLabel.maxLines, isNull);
    expect(mediaLabel.overflow, isNot(TextOverflow.ellipsis));
    await _choosePhoto(tester);
    await _review(tester);
    final picker = find.byKey(
      const ValueKey<String>('reel-availability-picker'),
    );
    await tester.ensureVisible(picker);
    await tester.pump();
    expect(picker, findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('reel-availability-custom')),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _choosePhoto(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Choose media'));
  await tester.tap(find.text('Choose media'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose photo'));
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester) async {
  final next = find.byKey(const ValueKey('reel-next-step'));
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

ReelService _composerService() => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'composer-fixture', isEmailVerified: true),
  ),
);

class _ImagePickerStub extends ImagePicker {
  _ImagePickerStub({this.pending});
  final Completer<XFile?>? pending;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (pending != null) return pending!.future;
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

class _MutableComposerService extends ReelService {
  _MutableComposerService() : super(auth: MockFirebaseAuth());
  String? uid = 'A';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  String? get currentUserId => uid;
  @override
  Stream<String?> get identityChanges => changes.stream;
  void switchTo(String? value) {
    uid = value;
    changes.add(value);
  }
}
