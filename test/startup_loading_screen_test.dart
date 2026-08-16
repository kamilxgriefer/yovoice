import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';

void main() {
  for (final size in const [
    Size(320, 640),
    Size(390, 844),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    testWidgets('startup wave fits ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StartupLoadingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 420));

      expect(find.text('YO VOICE'), findsOneWidget);
      expect(find.text('Create your space'), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-sound-wave')), findsOneWidget);
      final logoRect = tester.getRect(
        find.byKey(const ValueKey('startup-logo')),
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('startup-title')),
      );
      expect(
        titleRect.top,
        lessThan(logoRect.bottom),
        reason: 'The title should overlap the lower edge of the logo.',
      );
      expect(
        titleRect.bottom,
        greaterThan(logoRect.bottom),
        reason: 'The title should remain readable in front of the logo.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('authenticated entry has no fixed welcome delay', () {
    final source = File(
      'lib/features/auth/presentation/screens/auth_gate.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Duration(seconds: 4)')));
    expect(source, isNot(contains('welcome-screen')));
  });
}
