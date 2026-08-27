import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';

Future<ui.Image> _solidImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF7B2FF7),
  );
  return recorder.endRecording().toImage(width, height);
}

Future<ui.Image> _landscapeCropMarker() async {
  const width = 1200;
  const height = 600;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 300, 600),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(300, 0, 600, 600),
    Paint()..color = const Color(0xFF00FF00),
  );
  canvas.drawRect(
    const Rect.fromLTWH(900, 0, 300, 600),
    Paint()..color = const Color(0xFF0000FF),
  );
  return recorder.endRecording().toImage(width, height);
}

Future<void> _pumpCrop(
  WidgetTester tester, {
  required ui.Image image,
  required ProfileImageKind kind,
  required Size surface,
  required double textScale,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ImageCropScreen(image: image, kind: kind),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectImageCoversViewport(WidgetTester tester) {
  final image = tester.getRect(find.byType(RawImage));
  final viewport = tester.getRect(find.byType(InteractiveViewer));
  const tolerance = .05;

  expect(image.left, lessThanOrEqualTo(viewport.left + tolerance));
  expect(image.top, lessThanOrEqualTo(viewport.top + tolerance));
  expect(image.right, greaterThanOrEqualTo(viewport.right - tolerance));
  expect(image.bottom, greaterThanOrEqualTo(viewport.bottom - tolerance));
}

bool _primaryFocusIsInside(WidgetTester tester, Finder target) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  final targetElement = tester.element(target);
  if (focusContext == targetElement) return true;
  var found = false;
  focusContext.visitAncestorElements((element) {
    if (element == targetElement) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _pinch(
  WidgetTester tester, {
  required Rect viewport,
  required double from,
  required double to,
}) async {
  final left = await tester.createGesture(pointer: 1);
  final right = await tester.createGesture(pointer: 2);
  await left.down(viewport.center - Offset(from, 0));
  await right.down(viewport.center + Offset(from, 0));
  await tester.pump();
  await left.moveTo(viewport.center - Offset(to, 0));
  await right.moveTo(viewport.center + Offset(to, 0));
  await tester.pump();
  await left.up();
  await right.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases =
      <
        ({
          String label,
          Size imageSize,
          ProfileImageKind kind,
          Size surface,
          double textScale,
        })
      >[
        (
          label: 'portrait avatar at 390px',
          imageSize: const Size(828, 1064),
          kind: ProfileImageKind.avatar,
          surface: const Size(390, 844),
          textScale: 1,
        ),
        (
          label: 'landscape avatar at 320px and 200% text',
          imageSize: const Size(1200, 700),
          kind: ProfileImageKind.avatar,
          surface: const Size(320, 640),
          textScale: 2,
        ),
        (
          label: 'square banner at 390px and 200% text',
          imageSize: const Size(900, 900),
          kind: ProfileImageKind.banner,
          surface: const Size(390, 844),
          textScale: 2,
        ),
      ];

  for (final testCase in cases) {
    testWidgets('${testCase.label}: cover survives pinch, pan and Reset', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = await _solidImage(
        testCase.imageSize.width.toInt(),
        testCase.imageSize.height.toInt(),
      );
      addTearDown(image.dispose);

      await _pumpCrop(
        tester,
        image: image,
        kind: testCase.kind,
        surface: testCase.surface,
        textScale: testCase.textScale,
      );

      expect(tester.takeException(), isNull);
      _expectImageCoversViewport(tester);
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      final initialImage = tester.getRect(find.byType(RawImage));
      final initialMatrix = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value;
      expect(
        initialMatrix.entry(2, 2),
        closeTo(initialMatrix.entry(0, 0), 1e-9),
        reason:
            'InteractiveViewer includes Z in getMaxScaleOnAxis; XYZ must '
            'stay uniform when the cover scale is below 1.',
      );

      // This exact gesture used to multiply the sub-1 cover scale a second
      // time, shrinking the photo into the top-left quarter of the frame.
      await _pinch(tester, viewport: viewport, from: 80, to: 20);
      _expectImageCoversViewport(tester);
      final afterPinchOut = tester.getRect(find.byType(RawImage));
      expect(afterPinchOut.width, closeTo(initialImage.width, .1));
      expect(afterPinchOut.height, closeTo(initialImage.height, .1));

      // Zooming in and panning hard against a boundary must still leave no
      // uncovered strip in the fixed crop frame.
      await _pinch(tester, viewport: viewport, from: 30, to: 75);
      expect(
        tester.getRect(find.byType(RawImage)).width,
        greaterThan(initialImage.width),
      );
      await tester.dragFrom(viewport.center, const Offset(1000, 1000));
      await tester.pumpAndSettle();
      _expectImageCoversViewport(tester);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      _expectImageCoversViewport(tester);
      final resetImage = tester.getRect(find.byType(RawImage));
      expect(resetImage.width, closeTo(initialImage.width, .1));
      expect(resetImage.height, closeTo(initialImage.height, .1));

      for (final label in ['Reset', 'Cancel', 'Use photo']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(testCase.surface.width));
        expect(rect.bottom, lessThanOrEqualTo(testCase.surface.height));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pinch-out keeps the centered crop in the exported JPEG', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await _landscapeCropMarker();
    addTearDown(image.dispose);

    final navigatorKey = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    final resultFuture = navigatorKey.currentState!.push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) =>
            ImageCropScreen(image: image, kind: ProfileImageKind.avatar),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(InteractiveViewer));
    await tester.sendEventToBinding(
      PointerScaleEvent(position: viewport.center, scale: .25),
    );
    await tester.pumpAndSettle();
    _expectImageCoversViewport(tester);
    await tester.tap(find.text('Use photo'));
    await tester.pump();

    // dart:ui image readback/encoding completes on the real event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    final bytes = await resultFuture;

    expect(bytes, isNotNull);
    final output = img.decodeJpg(bytes!)!;
    expect(output.width, 1024);
    expect(output.height, 1024);
    for (final x in [32, output.width ~/ 2, output.width - 33]) {
      final pixel = output.getPixel(x, output.height ~/ 2);
      expect(pixel.g, greaterThan(220));
      expect(pixel.r, lessThan(35));
      expect(pixel.b, lessThan(35));
    }
  });

  testWidgets(
    'named 44px controls provide keyboard and single-pointer crop actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = await _solidImage(1200, 600);
      addTearDown(image.dispose);

      await _pumpCrop(
        tester,
        image: image,
        kind: ProfileImageKind.avatar,
        surface: const Size(390, 844),
        textScale: 1,
      );

      const controls = <(String, String)>[
        ('crop-zoom-out', 'Zoom out'),
        ('crop-zoom-in', 'Zoom in'),
        ('crop-move-left', 'Move photo left'),
        ('crop-move-up', 'Move photo up'),
        ('crop-move-down', 'Move photo down'),
        ('crop-move-right', 'Move photo right'),
      ];
      for (final (key, label) in controls) {
        final control = find.byKey(ValueKey(key));
        expect(control, findsOneWidget);
        final rect = tester.getRect(control);
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(390));
        expect(find.byTooltip(label), findsOneWidget);
      }

      final preview = find.bySemanticsLabel('Avatar crop preview');
      expect(preview, findsOneWidget);
      expect(tester.getSemantics(preview).value, 'Zoom 100 percent');

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final initialScale = viewer.transformationController!.value
          .getMaxScaleOnAxis();
      final zoomIn = find.byKey(const ValueKey('crop-zoom-in'));
      for (var index = 0; index < 12; index += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (_primaryFocusIsInside(tester, zoomIn)) break;
      }
      expect(_primaryFocusIsInside(tester, zoomIn), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final zoomedScale = viewer.transformationController!.value
          .getMaxScaleOnAxis();
      expect(zoomedScale, greaterThan(initialScale));
      expect(tester.getSemantics(preview).value, 'Zoom 120 percent');

      final beforeNudge = viewer.transformationController!.value
          .getTranslation()
          .x;
      await tester.tap(find.byKey(const ValueKey('crop-move-right')));
      await tester.pumpAndSettle();
      expect(
        viewer.transformationController!.value.getTranslation().x,
        greaterThan(beforeNudge),
      );
      _expectImageCoversViewport(tester);
      semantics.dispose();
    },
  );
}
