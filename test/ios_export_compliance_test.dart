import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares that the app uses no non-exempt encryption', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      infoPlist,
      contains(
        '<key>ITSAppUsesNonExemptEncryption</key>\n'
        '\t<false/>',
      ),
      reason:
          'Without the explicit exemption declaration, every TestFlight '
          'upload is held in Missing Compliance instead of reaching testers.',
    );
  });
}
