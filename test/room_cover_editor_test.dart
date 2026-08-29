import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/presentation/room_cover_editor.dart';

class _PickedImageService implements RoomImageService {
  _PickedImageService(this.bytes);

  final Uint8List bytes;
  int pickCalls = 0;

  @override
  Future<XFile?> pickRoomCoverSource() async {
    pickCalls++;
    return _BytesXFile(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `XFile.fromData` delegates some operations differently in a browser test
/// than a real `image_picker_for_web` result. Keep this fake at the exact
/// platform-independent contract RoomCoverEditor consumes.
class _BytesXFile implements XFile {
  _BytesXFile(this.bytes);

  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.lengthInBytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LengthGuardXFile implements XFile {
  bool readCalled = false;

  @override
  Future<int> length() async => RoomCoverEditor.maxSourceBytes + 1;

  @override
  Future<Uint8List> readAsBytes() async {
    readCalled = true;
    throw StateError('Oversized source must not be allocated.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LengthGuardImageService implements RoomImageService {
  _LengthGuardImageService(this.file);

  final _LengthGuardXFile file;

  @override
  Future<XFile?> pickRoomCoverSource() async => file;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
}) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw TestFailure(reason ?? 'Timed out waiting for asynchronous image work.');
}

void main() {
  testWidgets('oversized source is rejected before reading it into memory', (
    tester,
  ) async {
    final file = _LengthGuardXFile();
    final service = _LengthGuardImageService(file);
    Object? failure;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              try {
                await RoomCoverEditor.pickAndCrop(context, service);
              } catch (error) {
                failure = error;
              }
            },
            child: const Text('Choose room cover'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose room cover'));
    await tester.pumpAndSettle();

    expect(failure, isA<StateError>());
    expect(file.readCalled, isFalse);
  });

  testWidgets('picked bytes → crop editor → confirm returns final room JPEG', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = img.Image(width: 1200, height: 900);
    img.fill(source, color: img.ColorRgb8(122, 47, 247));
    final imageService = _PickedImageService(
      Uint8List.fromList(img.encodePng(source)),
    );
    PickedRoomCover? result;
    Object? failure;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                try {
                  result = await RoomCoverEditor.pickAndCrop(
                    context,
                    imageService,
                  );
                } catch (error) {
                  failure = error;
                }
              },
              child: const Text('Choose room cover'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose room cover'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => failure != null || find.text('Adjust cover').evaluate().isNotEmpty,
      reason: 'Crop editor did not open after decoding a valid PNG.',
    );
    await tester.pumpAndSettle();

    expect(imageService.pickCalls, 1);
    expect(find.text('Adjust cover'), findsOneWidget);
    await tester.tap(find.text('Use cover'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => result != null || failure != null,
      reason: 'Room-cover JPEG export did not finish.',
    );
    await tester.pumpAndSettle();

    expect(failure, isNull);
    expect(result, isNotNull);
    final output = img.decodeJpg(result!.bytes)!;
    expect(output.width, 1600);
    expect(output.height, 686);
  });

  testWidgets(
    'forced root reset completes the crop flow without an image race',
    (tester) async {
      final source = img.Image(width: 1200, height: 900);
      img.fill(source, color: img.ColorRgb8(122, 47, 247));
      final imageService = _PickedImageService(
        Uint8List.fromList(img.encodePng(source)),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      var completed = false;
      Object? failure;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  try {
                    await RoomCoverEditor.pickAndCrop(context, imageService);
                    completed = true;
                  } catch (error) {
                    failure = error;
                  }
                },
                child: const Text('Choose room cover'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose room cover'));
      await _pumpUntil(
        tester,
        () =>
            failure != null || find.text('Adjust cover').evaluate().isNotEmpty,
        reason: 'Crop editor did not open before the route reset.',
      );

      unawaited(
        navigatorKey.currentState!.pushAndRemoveUntil<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Login')),
          ),
          (_) => false,
        ),
      );
      await tester.pumpAndSettle();
      await _pumpUntil(
        tester,
        () => completed || failure != null,
        reason: 'Removed crop route did not release its awaiting caller.',
      );

      expect(failure, isNull);
      expect(completed, isTrue);
      expect(find.text('Login'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid source never opens the cropper', (tester) async {
    final service = _PickedImageService(Uint8List.fromList([1, 2, 3, 4]));
    Object? failure;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                try {
                  await RoomCoverEditor.pickAndCrop(context, service);
                } catch (error) {
                  failure = error;
                }
              },
              child: const Text('Choose room cover'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose room cover'));
    await tester.pumpAndSettle();

    expect(failure, isA<StateError>());
    expect(find.text('Adjust room cover'), findsNothing);
  });

  for (final testCase in <({String label, Uint8List bytes, String message})>[
    (
      label: 'empty source',
      bytes: Uint8List(0),
      message: "We couldn't process this image. Try another one.",
    ),
    (
      label: 'source over 8 MB',
      bytes: Uint8List(RoomCoverEditor.maxSourceBytes + 1),
      message: 'Choose a room cover smaller than 8 MB.',
    ),
    (
      label: 'valid JPEG signature with undecodable contents',
      bytes: Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0xFF,
        0xD9,
      ]),
      message: "We couldn't process this image. Try another one.",
    ),
  ]) {
    testWidgets('${testCase.label} fails before crop navigation', (
      tester,
    ) async {
      final service = _PickedImageService(testCase.bytes);
      Object? failure;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  try {
                    await RoomCoverEditor.pickAndCrop(context, service);
                  } catch (error) {
                    failure = error;
                  }
                },
                child: const Text('Choose room cover'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose room cover'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();

      expect(
        failure,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          testCase.message,
        ),
      );
      expect(find.text('Adjust room cover'), findsNothing);
    });
  }
}
