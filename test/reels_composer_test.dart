import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';

void main() {
  testWidgets('composer exposes camera and library for photos and videos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ReelComposerScreen()));

    await tester.ensureVisible(find.text('Choose media'));
    await tester.tap(find.text('Choose media'));
    await tester.pumpAndSettle();

    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Record video'), findsOneWidget);
    expect(find.text('Choose video'), findsOneWidget);
  });

  testWidgets('composer keeps controls readable on a wide canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ReelComposerScreen()));
    expect(find.text('Create Reel'), findsOneWidget);
    expect(find.text('Caption'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('availability defaults to 24h and supports custom hours/days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReelComposerScreen()));

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
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-availability-apply')),
    );
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
          expect(payload['availabilityHours'], 'permanent');
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
        expect(name, 'finalizeReelDraftV2');
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
    final caption = find.byType(TextField).first;
    await tester.enterText(caption, 'Original caption');
    final permanent = find.byKey(
      const ValueKey<String>('reel-availability-permanent'),
    );
    await tester.ensureVisible(permanent);
    await tester.tap(permanent);
    await tester.ensureVisible(find.text('Publish Reel'));
    await tester.tap(find.text('Publish Reel'));
    await tester.pumpAndSettle();

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
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: ReelComposerScreen(),
        ),
      ),
    );
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
