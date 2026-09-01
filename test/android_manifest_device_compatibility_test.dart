import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera permissions do not make camera hardware mandatory in Play', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final feature in <String>[
      'android.hardware.camera',
      'android.hardware.camera.any',
      'android.hardware.camera.autofocus',
      'android.hardware.camera.front',
    ]) {
      final optionalFeature = RegExp(
        '<uses-feature\\s+'
        'android:name="${RegExp.escape(feature)}"\\s+'
        'android:required="false"\\s*/>',
        multiLine: true,
      );

      expect(
        manifest,
        matches(optionalFeature),
        reason: '$feature must remain optional to preserve device coverage',
      );
    }
  });
}
