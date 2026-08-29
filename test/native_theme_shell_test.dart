import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS runtime appearance is not pinned away from the Flutter theme', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final xcodeProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final launchStoryboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final mainStoryboard = File(
      'ios/Runner/Base.lproj/Main.storyboard',
    ).readAsStringSync();
    const brandedDarkBackground =
        '<color key="backgroundColor" '
        'red="0.050980392156862744" '
        'green="0.023529411764705882" '
        'blue="0.09411764705882353" alpha="1" '
        'colorSpace="custom" customColorSpace="sRGB"/>';

    expect(infoPlist, isNot(contains('<key>UIUserInterfaceStyle</key>')));
    expect(xcodeProject, isNot(contains('UIUserInterfaceStyle')));
    expect(xcodeProject, isNot(contains('INFOPLIST_KEY_UIUserInterfaceStyle')));
    expect(launchStoryboard, contains(brandedDarkBackground));
    expect(mainStoryboard, contains(brandedDarkBackground));
  });
}
