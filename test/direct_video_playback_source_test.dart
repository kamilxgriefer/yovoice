import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in <({String extension, List<int> bytes})>[
    (extension: 'mp4', bytes: <int>[0, 1, 2, 3]),
    (extension: 'mov', bytes: <int>[4, 5, 6, 7]),
    (extension: 'webm', bytes: <int>[8, 9, 10, 11]),
  ]) {
    test('private DM video stages authenticated bytes and preserves '
        '${scenario.extension.toUpperCase()} format', () async {
      final directory = await Directory.systemTemp.createTemp(
        'yovoice_dm_video_test_',
      );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => switch (call.method) {
              'getTemporaryDirectory' => directory.path,
              _ => null,
            },
          );

      final bytes = Uint8List.fromList(scenario.bytes);
      final prepared = await prepareDirectVideoSource(
        bytes,
        'message/id',
        'gs://private/message_attachments/user/conversation/video.${scenario.extension}',
      );
      final controller = prepared.createController();
      // Default options keep Android audio focus and never make a live RTC
      // AVAudioSession mixable on iOS.
      expect(controller.videoPlayerOptions, isNull);
      final file = File(Uri.parse(controller.dataSource).toFilePath());
      expect(file.path, endsWith('.${scenario.extension}'));
      expect(await file.readAsBytes(), bytes);

      await prepared.dispose();
      expect(await file.exists(), isFalse);
    });
  }
}
