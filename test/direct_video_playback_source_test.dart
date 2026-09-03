import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'private DM video stages authenticated bytes and preserves MOV format',
    () async {
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

      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final prepared = await prepareDirectVideoSource(
        bytes,
        'message/id',
        'gs://private/message_attachments/user/conversation/video.mov',
      );
      final controller = prepared.createController();
      final file = File(Uri.parse(controller.dataSource).toFilePath());
      expect(file.path, endsWith('.mov'));
      expect(await file.readAsBytes(), bytes);

      await prepared.dispose();
      expect(await file.exists(), isFalse);
    },
  );
}
