import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/register_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

// The responsive auth shell exposes both modes through a full-width,
// two-option rail. The compatibility RegisterScreen route still pops when
// its Log in option is selected.

// LoginScreen constructs a real AuthService(), which reaches for
// FirebaseAuth.instance -> Firebase.app() at State-construction time.
// FirebaseAuth's own platform delegate is created lazily (only touched by
// actual auth calls we never make in this test), so all we need is for
// Firebase.app() to resolve -- no real platform channel round-trip
// required. Swapping in a bare FirebasePlatform fake gets us that without
// depending on firebase_core's internal Pigeon channel wire format.
class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: 'test-app-id',
          messagingSenderId: 'test-sender-id',
          projectId: 'test-project-id',
        ),
      );
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

class _SuccessfulSocialAuthService extends AuthService {
  _SuccessfulSocialAuthService()
    : _mockAuth = MockFirebaseAuth(),
      super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  final MockFirebaseAuth _mockAuth;

  int googleCalls = 0;

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;

  @override
  Future<UserCredential> signInWithGoogle() {
    googleCalls += 1;
    return _mockAuth.signInAnonymously();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  testWidgets(
    'Create account rail option switches the shared shell to Register mode',
    (tester) async {
      // LoginScreen's background has a continuously-repeating animation,
      // so pumpAndSettle() never terminates here -- use bounded pump()
      // calls instead.
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Create account'), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);

      await tester.tap(find.text('Create account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 520));

      expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
    },
  );

  testWidgets(
    'Forgot password opens its own email form without requiring login email',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(const Duration(milliseconds: 500));

      final link = find.text('Forgot password?');
      await tester.ensureVisible(link);
      await tester.pump();
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.byKey(const Key('forgot-password-email')), findsOneWidget);
      expect(find.byKey(const Key('send-reset-link')), findsOneWidget);
      expect(find.text('Enter your email address.'), findsNothing);
    },
  );

  for (final width in <double>[320, 390, 768, 1100, 1440]) {
    testWidgets(
      'social sign-in controls fit at ${width.toInt()}px with 200% text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1100),
              textScaler: const TextScaler.linear(2),
            ),
            child: const MaterialApp(home: LoginScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        final appleLabel = find.textContaining('Continue with Apple');
        await tester.ensureVisible(appleLabel);
        await tester.pump();

        expect(find.text('Continue with Google'), findsOneWidget);
        expect(appleLabel, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Register exposes the same Google and Apple account creation actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('Continue with Apple'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('successful social registration closes the registration route', (
    tester,
  ) async {
    final auth = _SuccessfulSocialAuthService();
    await tester.binding.setSurfaceSize(const Size(402, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RegisterScreen(authService: auth),
                ),
              ),
              child: const Text('open social registration'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open social registration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(auth.googleCalls, 1);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('open social registration'), findsOneWidget);
  });

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
