import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS stages authenticated DM bytes as a temporary m4a and cleans it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yovoice_dm_playback_test_',
      );
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => switch (call.method) {
              'getTemporaryDirectory' => directory.path,
              _ => null,
            },
          );

      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final prepared = await prepareDirectVoiceSource(bytes, 'message/id');
      expect(prepared.source, isA<DeviceFileSource>());
      final file = File((prepared.source as DeviceFileSource).path);
      expect(file.path, endsWith('.m4a'));
      expect(await file.readAsBytes(), bytes);

      await prepared.dispose();
      expect(await file.exists(), isFalse);
    },
  );

  test('Android keeps private DM playback in memory', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final bytes = Uint8List.fromList([1, 2, 3]);

    final prepared = await prepareDirectVoiceSource(bytes, 'message');
    expect(prepared.source, isA<BytesSource>());
    expect((prepared.source as BytesSource).mimeType, 'audio/mp4');
    await prepared.dispose();
  });
}
