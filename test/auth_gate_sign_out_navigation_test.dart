import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/app/app.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/presentation/navigation/auth_epoch_route_resetter.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';

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

Route<void> _zeroDurationRoot(String label) {
  return PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        Scaffold(body: Center(child: Text(label))),
  );
}

Widget _localizedAuthGate({
  required Stream<User?> authStates,
  required Locale locale,
  Object? initialAuthError,
}) {
  return ProviderScope(
    overrides: [authStateChangesProvider.overrideWith((ref) => authStates)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuthGate(initialAuthError: initialAuthError),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeFirebasePlatform();
    await Firebase.initializeApp();
  });

  testWidgets(
    'logout replaces protected routes in one frame despite PopScope veto',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      var localVoiceActive = true;
      final resetter = AuthEpochRouteResetter(
        navigatorKey: navigatorKey,
        onPrincipalExit: () => localVoiceActive = false,
        routeFactory: (target) => _zeroDurationRoot(
          target.reason == AuthRouteResetReason.signedOut
              ? 'Login screen'
              : 'Fresh authenticated root',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Account A root')),
        ),
      );
      resetter.handlePrincipal('account-a');

      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => PopScope<void>(
              canPop: false,
              child: const Scaffold(
                body: Text('[cloud_firestore/permission-denied] private route'),
                bottomNavigationBar: Text('Private bottom navigation'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(navigatorKey.currentState!.canPop(), isTrue);
      expect(find.textContaining('permission-denied'), findsOneWidget);
      expect(find.text('Private bottom navigation'), findsOneWidget);

      resetter.handlePrincipal(null);
      await tester.pump();

      expect(localVoiceActive, isFalse);
      expect(find.text('Login screen'), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.text('Private bottom navigation'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching directly from account A to B resets the stack', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var localVoiceActive = true;
    final resetter = AuthEpochRouteResetter(
      navigatorKey: navigatorKey,
      onPrincipalExit: () => localVoiceActive = false,
      routeFactory: (target) =>
          _zeroDurationRoot('Fresh root for ${target.userId}'),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Account A root')),
      ),
    );
    resetter.handlePrincipal('account-a');
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Account A profile')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    resetter.handlePrincipal('account-b');
    await tester.pump();

    expect(localVoiceActive, isFalse);
    expect(find.text('Fresh root for account-b'), findsOneWidget);
    expect(find.text('Account A profile'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth stream failure isolates routes and local voice', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var localVoiceActive = true;
    final resetter = AuthEpochRouteResetter(
      navigatorKey: navigatorKey,
      onPrincipalExit: () => localVoiceActive = false,
      routeFactory: (target) => _zeroDurationRoot('Auth error root'),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Account A root')),
      ),
    );
    resetter.handlePrincipal('account-a');
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private A route')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    resetter.handleError(StateError('auth stream failed'), StackTrace.current);
    await tester.pump();

    expect(localVoiceActive, isFalse);
    expect(find.text('Auth error root'), findsOneWidget);
    expect(find.text('Private A route'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out to signed-in keeps the registration route flow', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final resetter = AuthEpochRouteResetter(
      navigatorKey: navigatorKey,
      routeFactory: (target) => _zeroDurationRoot('Unexpected reset'),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Signed-out root')),
      ),
    );
    resetter.handlePrincipal(null);
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Verify email route')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    resetter.handlePrincipal('new-account');
    await tester.pump();

    expect(find.text('Verify email route'), findsOneWidget);
    expect(find.text('Unexpected reset'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the logout reset paints the real LoginScreen immediately', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => auth.stream),
        ],
        child: const MaterialApp(home: AuthGate(initiallySignedOut: true)),
      ),
    );

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(StartupLoadingScreen), findsNothing);
    expect(find.text("You don't have permission to do that."), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an English auth error never paints raw bootstrap details', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    const rawBackendDetail =
        '[firebase_auth/internal-error] bootstrap-token=do-not-render';

    await tester.pumpWidget(
      _localizedAuthGate(
        authStates: auth.stream,
        locale: const Locale('en'),
        initialAuthError: StateError(rawBackendDetail),
      ),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(
      find.text('Authentication could not be completed. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining(rawBackendDetail), findsNothing);
    expect(find.textContaining('bootstrap-token'), findsNothing);
    expect(find.byType(StartupLoadingScreen), findsNothing);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Polish auth-stream error is localized and redacted', (
    tester,
  ) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    const rawBackendDetail = 'api-key=secret-value backend exploded';

    await tester.pumpWidget(
      _localizedAuthGate(authStates: auth.stream, locale: const Locale('pl')),
    );
    expect(find.byType(StartupLoadingScreen), findsOneWidget);

    auth.addError(
      FirebaseAuthException(code: 'internal-error', message: rawBackendDetail),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Coś poszło nie tak'), findsOneWidget);
    expect(
      find.text('Nie udało się ukończyć uwierzytelniania. Spróbuj ponownie.'),
      findsOneWidget,
    );
    expect(find.textContaining(rawBackendDetail), findsNothing);
    expect(find.textContaining('secret-value'), findsNothing);
    expect(find.textContaining('FirebaseAuthException'), findsNothing);
    expect(find.byType(StartupLoadingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session reset removes the current and queued banners at once', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: Text('Session surface')),
      ),
    );
    messengerKey.currentState!
      ..showSnackBar(const SnackBar(content: Text('Account A banner')))
      ..showSnackBar(const SnackBar(content: Text('Queued A banner')));
    await tester.pump();
    expect(find.text('Account A banner'), findsOneWidget);

    clearSessionSnackBars(messengerKey.currentState!);
    await tester.pump();

    expect(find.text('Account A banner'), findsNothing);
    expect(find.text('Queued A banner'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
