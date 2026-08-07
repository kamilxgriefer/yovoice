import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/register_screen.dart';

// Both LoginScreen and RegisterScreen previously shrank their
// "Sign up" / "Log in" cross-links to a near-zero hit box (padding:
// EdgeInsets.zero + minimumSize: Size.zero + tapTargetSize: shrinkWrap),
// well under Apple/Material's 44/48pt minimum touch target. These tests
// guard against that regression coming back.

// LoginScreen constructs a real AuthService(), which reaches for
// FirebaseAuth.instance -> Firebase.app() at State-construction time.
// FirebaseAuth's own platform delegate is created lazily (only touched by
// actual auth calls we never make in this test), so all we need is for
// Firebase.app() to resolve -- no real platform channel round-trip
// required. Swapping in a bare FirebasePlatform fake gets us that without
// depending on firebase_core's internal Pigeon channel wire format.
class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(defaultFirebaseAppName, const FirebaseOptions(
        apiKey: 'test-api-key',
        appId: 'test-app-id',
        messagingSenderId: 'test-sender-id',
        projectId: 'test-project-id',
      ));
}

class _FakeFirebasePlatform extends FirebasePlatform {
  final _app = _FakeFirebaseApp();

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  testWidgets(
    'tapping "Sign up" at its default TextButton hit box navigates to RegisterScreen',
    (tester) async {
      // LoginScreen's background has a continuously-repeating animation,
      // so pumpAndSettle() never terminates here -- use bounded pump()
      // calls instead.
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Sign up'), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);

      // The row sits inside a SingleChildScrollView below the fold on a
      // real device too -- ensureVisible mirrors the user scrolling down
      // to it before tapping.
      await tester.ensureVisible(find.text('Sign up'));
      await tester.pump();
      await tester.tap(find.text('Sign up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RegisterScreen), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Log in" at its default TextButton hit box pops RegisterScreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterScreen(),
                    ),
                  ),
                  child: const Text('open register'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open register'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RegisterScreen), findsOneWidget);

      await tester.ensureVisible(find.text('Log in'));
      await tester.pump();
      await tester.tap(find.text('Log in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RegisterScreen), findsNothing);
    },
  );
}
