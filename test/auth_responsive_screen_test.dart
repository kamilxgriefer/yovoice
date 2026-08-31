import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/register_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

class _FakeAuthService extends AuthService {
  factory _FakeAuthService({
    AppleSignInAvailability appleAvailability =
        AppleSignInAvailability.available,
    Completer<UserCredential>? pendingLogin,
    Completer<UserCredential>? pendingRegister,
  }) {
    final mockAuth = MockFirebaseAuth();
    return _FakeAuthService._(
      appleAvailability: appleAvailability,
      pendingLogin: pendingLogin,
      pendingRegister: pendingRegister,
      mockAuth: mockAuth,
    );
  }

  _FakeAuthService._({
    required this.appleAvailability,
    required this.pendingLogin,
    required this.pendingRegister,
    required this.mockAuth,
  }) : super(
         firebaseAuth: mockAuth,
         firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
       );

  final MockFirebaseAuth mockAuth;
  final AppleSignInAvailability appleAvailability;
  final Completer<UserCredential>? pendingLogin;
  final Completer<UserCredential>? pendingRegister;

  int passwordLoginCalls = 0;
  int registerCalls = 0;
  int googleCalls = 0;
  int appleCalls = 0;

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      appleAvailability;

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    passwordLoginCalls += 1;
    return pendingLogin?.future ?? mockAuth.signInAnonymously();
  }

  @override
  Future<UserCredential> register({
    required String email,
    required String password,
    required String username,
  }) {
    registerCalls += 1;
    return pendingRegister?.future ?? mockAuth.signInAnonymously();
  }

  @override
  Future<UserCredential> signInWithGoogle() {
    googleCalls += 1;
    return mockAuth.signInAnonymously();
  }

  @override
  Future<UserCredential> signInWithApple() {
    appleCalls += 1;
    return mockAuth.signInAnonymously();
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<void> _pumpAuth(
  WidgetTester tester, {
  required Size size,
  required Widget screen,
  double textScale = 1,
  bool reduceMotion = false,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final inherited = MediaQuery.of(context);
        return MediaQuery(
          data: inherited.copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            accessibleNavigation: reduceMotion,
          ),
          child: child!,
        );
      },
      home: screen,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _tapAuthControl(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 240));
  final scrollable = find
      .ancestor(of: target, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(target, 260, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 240));
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _enterAuthText(
  WidgetTester tester,
  Key fieldKey,
  String value,
) async {
  final editable = find.descendant(
    of: find.byKey(fieldKey),
    matching: find.byType(EditableText),
  );
  expect(editable, findsOneWidget);
  await tester.enterText(editable, value);
}

Future<void> _switchToRegisterAndSettle(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 248));
  await tester.pump(const Duration(milliseconds: 272));
  await tester.pump(const Duration(milliseconds: 180));
  await tester.pump();
}

void main() {
  final surfaces = <(Size, String)>[
    (const Size(320, 568), 'compact'),
    (const Size(390, 667), 'compact'),
    (const Size(430, 844), 'compact'),
    (const Size(600, 960), 'medium'),
    (const Size(999, 800), 'medium'),
    (const Size(1000, 700), 'wide'),
    (const Size(1440, 900), 'wide'),
  ];

  for (final (size, variant) in surfaces) {
    testWidgets(
      'Login uses $variant layout at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpAuth(
          tester,
          size: size,
          screen: LoginScreen(authService: _FakeAuthService()),
        );

        expect(find.byKey(ValueKey('auth-layout-$variant')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth-form-login')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth-form-register')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Register uses $variant layout at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpAuth(
          tester,
          size: size,
          screen: RegisterScreen(authService: _FakeAuthService()),
        );

        expect(find.byKey(ValueKey('auth-layout-$variant')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('auth-form-register')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('auth-form-login')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short 320 surface remains overflow-free at 200% text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(320, 568),
      screen: LoginScreen(authService: _FakeAuthService()),
      textScale: 2,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('auth-login-submit')));
    await tester.pump();
    final railSize = tester.getSize(
      find.byKey(const ValueKey('auth-mode-rail')),
    );
    expect(railSize.height, greaterThanOrEqualTo(52));
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout requires the full 620dp usable workspace height', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(1000, 683),
      screen: LoginScreen(authService: _FakeAuthService()),
    );
    expect(find.byKey(const ValueKey('auth-layout-medium')), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1000, 684));
    await tester.pump();
    expect(find.byKey(const ValueKey('auth-layout-wide')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide brand story remains reachable at 200% in EN and PL', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(1100, 1100), Size(1440, 1100)]) {
      for (final locale in const [Locale('en'), Locale('pl')]) {
        for (final mode in AuthMode.values) {
          await _pumpAuth(
            tester,
            size: size,
            screen: ResponsiveAuthScreen(
              key: ValueKey('${size.width}-${locale.languageCode}-$mode'),
              initialMode: mode,
              authService: _FakeAuthService(),
            ),
            textScale: 2,
            locale: locale,
          );

          final cta = find.byKey(const ValueKey('auth-desktop-brand-cta'));
          await tester.ensureVisible(cta);
          await tester.pump();
          expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('compact Voice Relay swaps once at 247ms and reverses', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(430, 844),
      screen: LoginScreen(authService: _FakeAuthService()),
    );

    final railSize = tester.getSize(
      find.byKey(const ValueKey('auth-mode-rail')),
    );
    expect(railSize.height, 52);

    await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 246));
    expect(find.byKey(const ValueKey('auth-form-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-form-register')), findsNothing);

    await tester.pump(const Duration(milliseconds: 2));
    expect(find.byKey(const ValueKey('auth-form-login')), findsNothing);
    expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('auth-mode-login')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 248));
    expect(find.byKey(const ValueKey('auth-form-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-form-register')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide curtain fully covers the seam at the atomic swap', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(1000, 700),
      screen: LoginScreen(authService: _FakeAuthService()),
    );

    final panel = find.byKey(const ValueKey('auth-desktop-brand-panel'));
    final resting = tester.getRect(panel);
    expect(resting.width, closeTo(460, .1));

    await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final covered = tester.getRect(panel);
    expect(covered.width, closeTo(920, .1));
    expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 410));
    final registered = tester.getRect(panel);
    expect(registered.width, closeTo(460, .1));
    expect(registered.left, closeTo(500, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced Motion switches modes atomically without a relay', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(430, 844),
      screen: LoginScreen(authService: _FakeAuthService()),
      reduceMotion: true,
    );

    await tester.tap(find.byKey(const ValueKey('auth-mode-register')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-form-login')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root registration mode supports a left-edge back gesture', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(430, 844),
      screen: LoginScreen(authService: _FakeAuthService()),
    );
    await _switchToRegisterAndSettle(tester);
    expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);

    await tester.dragFrom(const Offset(10, 420), const Offset(80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(const ValueKey('auth-form-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-form-register')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode and typed registration data survive breakpoint resize', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(430, 844),
      screen: LoginScreen(authService: _FakeAuthService()),
    );
    await _switchToRegisterAndSettle(tester);

    await _enterAuthText(
      tester,
      const ValueKey('auth-register-username'),
      'voice.tester',
    );
    await _enterAuthText(
      tester,
      const ValueKey('auth-register-email'),
      'voice@example.com',
    );
    expect(
      tester
          .widget<AuthTextField>(
            find.byKey(const ValueKey('auth-register-username')),
          )
          .controller
          .text,
      'voice.tester',
    );
    expect(
      tester
          .widget<AuthTextField>(
            find.byKey(const ValueKey('auth-register-email')),
          )
          .controller
          .text,
      'voice@example.com',
    );
    for (final size in const [
      Size(600, 960),
      Size(999, 800),
      Size(1000, 700),
      Size(1440, 900),
      Size(999, 800),
      Size(430, 844),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      expect(find.byKey(const ValueKey('auth-form-register')), findsOneWidget);
      expect(
        tester
            .widget<AuthTextField>(
              find.byKey(const ValueKey('auth-register-username')),
            )
            .controller
            .text,
        'voice.tester',
        reason: 'Username must survive resize to $size.',
      );
      expect(
        tester
            .widget<AuthTextField>(
              find.byKey(const ValueKey('auth-register-email')),
            )
            .controller
            .text,
        'voice@example.com',
        reason: 'Email must survive resize to $size.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('registration validation remains attached to the shared body', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(390, 667),
      screen: RegisterScreen(authService: _FakeAuthService()),
    );

    final submit = find.byKey(const ValueKey('auth-register-submit'));
    await _tapAuthControl(tester, submit);

    expect(find.text('Enter a username.'), findsOneWidget);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter a password.'), findsOneWidget);
    expect(find.text('Confirm your password.'), findsOneWidget);
    expect(
      tester
          .widget<AuthTextField>(
            find.byKey(const ValueKey('auth-register-username')),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('registration validation is localized in Polish', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(390, 667),
      screen: RegisterScreen(authService: _FakeAuthService()),
      locale: const Locale('pl'),
    );

    await _tapAuthControl(
      tester,
      find.byKey(const ValueKey('auth-register-submit')),
    );

    expect(find.text('Wpisz nazwę użytkownika.'), findsOneWidget);
    expect(find.text('Wpisz adres e-mail.'), findsOneWidget);
    expect(find.text('Wpisz hasło.'), findsOneWidget);
    expect(find.text('Powtórz hasło.'), findsOneWidget);
  });

  testWidgets(
    'verification route survives AuthGate-style disposal during registration',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<UserCredential>();
      final auth = _FakeAuthService(pendingRegister: pending);
      final signedIn = ValueNotifier<bool>(false);
      final observer = _RecordingNavigatorObserver();
      final registrationLoading = <bool>[];
      addTearDown(signedIn.dispose);

      await tester.binding.setSurfaceSize(const Size(430, 844));
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (context, authenticated, _) => authenticated
                ? const Scaffold(body: Text('Authenticated entry'))
                : LoginScreen(
                    authService: auth,
                    onRegistrationLoadingChanged: registrationLoading.add,
                  ),
          ),
        ),
      );
      await tester.pump();

      await _switchToRegisterAndSettle(tester);
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-username'),
        'voice.tester',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-email'),
        'voice@example.com',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-password'),
        'Secret123',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-confirm'),
        'Secret123',
      );
      final submit = find.byKey(const ValueKey('auth-register-submit'));
      await _tapAuthControl(tester, submit);
      expect(auth.registerCalls, 1);
      expect(registrationLoading, [true]);

      signedIn.value = true;
      await tester.pump();
      expect(find.byType(ResponsiveAuthScreen), findsNothing);

      pending.complete(await auth.mockAuth.signInAnonymously());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );

      expect(
        observer.pushedRoutes.last.settings.name,
        '/verify-email',
        reason: 'The root Navigator must outlive the disposed auth child.',
      );
      expect(
        registrationLoading,
        [true, false],
        reason: 'The shared AuthGate flag must be released after completion.',
      );

      // Remove the Navigator before it builds the Firebase-backed verify
      // surface; this test isolates the registration routing race.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'registration failure after auth swap reaches the surviving messenger',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<UserCredential>();
      final auth = _FakeAuthService(pendingRegister: pending);
      final signedIn = ValueNotifier<bool>(false);
      final observer = _RecordingNavigatorObserver();
      addTearDown(signedIn.dispose);

      await tester.binding.setSurfaceSize(const Size(430, 844));
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (context, authenticated, _) => authenticated
                ? const Scaffold(body: Text('Authenticated entry'))
                : LoginScreen(authService: auth),
          ),
        ),
      );
      await tester.pump();
      await _switchToRegisterAndSettle(tester);
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-username'),
        'voice.tester',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-email'),
        'voice@example.com',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-password'),
        'Secret123',
      );
      await _enterAuthText(
        tester,
        const ValueKey('auth-register-confirm'),
        'Secret123',
      );
      final submit = find.byKey(const ValueKey('auth-register-submit'));
      await _tapAuthControl(tester, submit);
      expect(auth.registerCalls, 1);

      signedIn.value = true;
      await tester.pump();
      pending.completeError(
        const AuthServiceException('Profile setup failed.'),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();

      expect(find.text('Profile setup failed.'), findsOneWidget);
      expect(
        observer.pushedRoutes.where(
          (route) => route.settings.name == '/verify-email',
        ),
        isEmpty,
      );
    },
  );

  testWidgets('popped registration route cannot navigate after late success', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<UserCredential>();
    final auth = _FakeAuthService(pendingRegister: pending);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RecordingNavigatorObserver();

    await tester.binding.setSurfaceSize(const Size(430, 844));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RegisterScreen(authService: auth),
                ),
              ),
              child: const Text('Open registration'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open registration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await _enterAuthText(
      tester,
      const ValueKey('auth-register-username'),
      'voice.tester',
    );
    await _enterAuthText(
      tester,
      const ValueKey('auth-register-email'),
      'voice@example.com',
    );
    await _enterAuthText(
      tester,
      const ValueKey('auth-register-password'),
      'Secret123',
    );
    await _enterAuthText(
      tester,
      const ValueKey('auth-register-confirm'),
      'Secret123',
    );
    final submit = find.byKey(const ValueKey('auth-register-submit'));
    await _tapAuthControl(tester, submit);
    expect(auth.registerCalls, 1);

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Open registration'), findsOneWidget);

    pending.complete(await auth.mockAuth.signInAnonymously());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();

    expect(
      observer.pushedRoutes.where(
        (route) => route.settings.name == '/verify-email',
      ),
      isEmpty,
    );
    expect(find.text('Open registration'), findsOneWidget);
  });

  testWidgets('password login is single-flight and exposes pending state', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<UserCredential>();
    final auth = _FakeAuthService(pendingLogin: pending);
    await _pumpAuth(
      tester,
      size: const Size(430, 844),
      screen: LoginScreen(authService: auth),
    );

    await _enterAuthText(
      tester,
      const ValueKey('auth-login-email'),
      'voice@example.com',
    );
    await _enterAuthText(
      tester,
      const ValueKey('auth-login-password'),
      'Secret123',
    );
    final submit = find.byKey(const ValueKey('auth-login-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(auth.passwordLoginCalls, 1);
    expect(
      find.descendant(
        of: submit,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    pending.complete(await auth.mockAuth.signInAnonymously());
    await tester.pump();
  });

  testWidgets('Apple availability has distinct coming-soon and retry copy', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAuth(
      tester,
      size: const Size(390, 667),
      screen: LoginScreen(
        authService: _FakeAuthService(
          appleAvailability: AppleSignInAvailability.notConfigured,
        ),
      ),
    );
    expect(find.text('Coming soon'), findsOneWidget);

    await _pumpAuth(
      tester,
      size: const Size(390, 667),
      screen: LoginScreen(
        key: const ValueKey('temporary-apple-auth'),
        authService: _FakeAuthService(
          appleAvailability: AppleSignInAvailability.temporarilyUnavailable,
        ),
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-apple-provider')));
    await tester.pump();
    final temporaryAuth =
        tester
                .widget<ResponsiveAuthScreen>(find.byType(ResponsiveAuthScreen))
                .authService
            as _FakeAuthService;
    expect(temporaryAuth.appleCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
