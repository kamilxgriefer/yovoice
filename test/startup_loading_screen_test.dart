import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';

void main() {
  test('ring is invisible on both sides of its radius wrap', () {
    expect(startupRingOpacity(0), closeTo(0, 1e-12));
    expect(startupRingOpacity(1), closeTo(0, 1e-12));
    expect(startupRingOpacity(1 - 1e-6), lessThan(1e-10));
    expect(startupRingOpacity(.5), closeTo(.34, 1e-12));
  });

  test(
    'native launch surfaces use the real mark and the Flutter background',
    () {
      final iosAssets = [
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ];
      for (var index = 0; index < iosAssets.length; index++) {
        final path = iosAssets[index];
        final decoded = image.decodePng(File(path).readAsBytesSync());
        expect(decoded, isNotNull, reason: path);
        expect(decoded!.width, 170 * (index + 1), reason: path);
        expect(decoded.height, 170 * (index + 1), reason: path);
      }

      for (final path in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('@color/splash_background'), reason: path);
        expect(source, contains('@mipmap/launch_image'), reason: path);
      }
      for (final path in [
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final android12 = File(path).readAsStringSync();
        expect(
          android12,
          contains('windowSplashScreenBackground'),
          reason: path,
        );
        expect(
          android12,
          contains('windowSplashScreenAnimatedIcon'),
          reason: path,
        );
      }
      final webLaunch = File('web/index.html').readAsStringSync();
      expect(webLaunch, contains('width: 170px;'));
      expect(webLaunch, contains('height: 170px;'));
    },
  );

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
      expect(
        logoRect.width,
        closeTo(170, 1),
        reason: 'native and Flutter launch marks must not resize on hand-off',
      );
      expect(
        logoRect.center.dy,
        closeTo(size.height / 2, 2),
        reason: 'native and Flutter launch marks must not jump vertically',
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

  testWidgets('startup wordmark stays on-screen at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: StartupLoadingScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 420));

    final titleRect = tester.getRect(
      find.byKey(const ValueKey('startup-title')),
    );
    expect(titleRect.left, greaterThanOrEqualTo(0));
    expect(titleRect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuthGate crossfades from startup instead of cutting frames', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => auth.stream),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    expect(find.byType(StartupLoadingScreen), findsOneWidget);

    auth.addError(StateError('diagnostic auth failure'));
    await tester.pump();
    expect(
      find.byType(StartupLoadingScreen),
      findsOneWidget,
      reason: 'the outgoing frame stays mounted during the fade',
    );
    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 230));
    expect(find.byType(StartupLoadingScreen), findsNothing);
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  test('authenticated entry has no fixed welcome delay', () {
    final source = File(
      'lib/features/auth/presentation/screens/auth_gate.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Duration(seconds: 4)')));
    expect(source, isNot(contains('welcome-screen')));
  });
}
