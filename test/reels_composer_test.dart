import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
