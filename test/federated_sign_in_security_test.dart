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
import 'package:yovoice/services/firestore_service.dart';

/// Pre-registered account takeover, trigger A (functions/auth/
/// federated_takeover.js): right after a Google/Apple sign-in the owner's
/// client asks the server to secure the account — awaited (bounded) for a
/// returning sign-in, in the background for a new one. These tests pin the
/// client half — who calls, what a remediation does to this device, early or
/// late, and that the check can never block an ordinary sign-in.

class _AdditionalUserInfo extends AdditionalUserInfo {
  _AdditionalUserInfo({required super.isNewUser})
    : super(providerId: AppleAuthProvider.PROVIDER_ID);
}

class _UserCredential implements UserCredential {
  _UserCredential({required this.user, required bool isNewUser})
    : additionalUserInfo = _AdditionalUserInfo(isNewUser: isNewUser);

  @override
  final User? user;

  @override
  final AdditionalUserInfo additionalUserInfo;

  @override
  AuthCredential? get credential => null;
}

class _RecordingFirebaseAuth extends MockFirebaseAuth {
  _RecordingFirebaseAuth(this.result);

  final UserCredential result;
  int signOutCalls = 0;
  User? signedIn;

  @override
  User? get currentUser => signedIn;

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    signedIn = result.user;
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    signedIn = null;
  }
}

class _Harness {
  _Harness({
    required bool isNewUser,
    required Future<Map<String, dynamic>> Function() check,
    Duration? wait,
  }) : auth = _RecordingFirebaseAuth(
         _UserCredential(
           user: MockUser(uid: 'owner', email: 'owner@gmail.com'),
           isNewUser: isNewUser,
         ),
       ) {
    service = AuthService(
      firebaseAuth: auth,
      firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      appleSignInFeatureEnabled: true,
      appleUseWebPopup: false,
      appleProviderProbe: () async => AppleSignInAvailability.available,
      federatedSignInSecurityCheck: () {
        checks += 1;
        return check();
      },
      federatedSignInSecurityCheckWait: wait,
      clearEphemeralMediaAccess: () {},
      activeVoiceSessionReader: () => (
        directCallId: null,
        isActive: false,
        isRoomSession: false,
        roomId: null,
      ),
    );
  }

  final _RecordingFirebaseAuth auth;
  late final AuthService service;
  int checks = 0;
}

/// Signs in normally; the check's "remediated" arrives only afterwards.
class _LateSecuredAuthService extends AuthService {
  _LateSecuredAuthService()
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  final StreamController<void> late = StreamController<void>.broadcast();

  @override
  Stream<void> get federatedSessionSecuredLater => late.stream;

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;

  @override
  Future<UserCredential> signInWithGoogle() async => _UserCredential(
    user: MockUser(uid: 'owner', email: 'owner@gmail.com'),
    isNewUser: false,
  );
}

class _SecuredAuthService extends AuthService {
  _SecuredAuthService()
    : super(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

  final Completer<void> release = Completer<void>();

  @override
  Future<AppleSignInAvailability> getAppleSignInAvailability() async =>
      AppleSignInAvailability.available;

  @override
  Future<UserCredential> signInWithGoogle() async {
    await release.future;
    throw const FederatedSessionSecuredException();
  }
}

Future<void> _pumpSignIn(
  WidgetTester tester, {
  required Widget home,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapGoogle(WidgetTester tester) async {
  final google = find.byKey(const ValueKey('auth-google-provider'));
  await tester.ensureVisible(google);
  await tester.pump(const Duration(milliseconds: 240));
  await tester.tap(google);
  await tester.pump();
}

const _english =
    'We secured your account and ended every earlier session, including a '
    'password sign-in that was never verified. Sign in again to continue.';
const _polish =
    'Zabezpieczyliśmy Twoje konto i zakończyliśmy wszystkie wcześniejsze '
    'sesje, w tym logowanie hasłem, którego nikt nie potwierdził. Zaloguj '
    'się ponownie, aby kontynuować.';

void main() {
  group('post-sign-in account check (AuthService)', () {
    test(
      'a returning sign-in asks the server once and continues when clean',
      () async {
        final harness = _Harness(
          isNewUser: false,
          check: () async => {'status': 'clean', 'reauthenticate': false},
        );

        final credential = await harness.service.signInWithApple();

        expect(credential.user?.uid, 'owner');
        expect(harness.checks, 1);
        expect(harness.auth.signOutCalls, 0);
      },
    );

    // Changed on purpose (review of the takeover fix): a brand-new account
    // used to be skipped, which relied on Firebase never reporting a takeover
    // as a new user — an assumption only the emulator had confirmed. It is
    // now checked in the background, so it still never waits for the call.
    test(
      'a brand-new account is checked in the background and never waits',
      () async {
        final answer = Completer<Map<String, dynamic>>();
        final harness = _Harness(isNewUser: true, check: () => answer.future);

        final credential = await harness.service.signInWithApple();

        expect(credential.user?.uid, 'owner');
        expect(harness.checks, 1);
        expect(harness.auth.signOutCalls, 0);

        answer.complete({'status': 'clean', 'reauthenticate': false});
        await pumpEventQueue();
        expect(harness.auth.signOutCalls, 0);
      },
    );

    test(
      'a background "remediated" for a new account signs this device out and says so',
      () async {
        final answer = Completer<Map<String, dynamic>>();
        final harness = _Harness(isNewUser: true, check: () => answer.future);
        var announced = 0;
        final subscription = harness.service.federatedSessionSecuredLater
            .listen((_) => announced += 1);
        addTearDown(subscription.cancel);

        await harness.service.signInWithApple();
        answer.complete({'status': 'remediated', 'reauthenticate': true});
        await pumpEventQueue();

        expect(harness.auth.signOutCalls, 1);
        expect(announced, 1);
      },
    );

    test(
      'a slow returning check lets the sign-in continue and still honours a late remediation',
      () async {
        final answer = Completer<Map<String, dynamic>>();
        final harness = _Harness(
          isNewUser: false,
          check: () => answer.future,
          wait: const Duration(milliseconds: 20),
        );
        var announced = 0;
        final subscription = harness.service.federatedSessionSecuredLater
            .listen((_) => announced += 1);
        addTearDown(subscription.cancel);

        final credential = await harness.service.signInWithApple();
        expect(credential.user?.uid, 'owner');
        expect(harness.auth.signOutCalls, 0);

        answer.complete({'status': 'remediated', 'reauthenticate': true});
        await pumpEventQueue();

        expect(harness.auth.signOutCalls, 1);
        expect(announced, 1);
      },
    );

    test(
      'a late answer never signs out a different account signed in since',
      () async {
        final answer = Completer<Map<String, dynamic>>();
        final harness = _Harness(
          isNewUser: false,
          check: () => answer.future,
          wait: const Duration(milliseconds: 20),
        );
        var announced = 0;
        final subscription = harness.service.federatedSessionSecuredLater
            .listen((_) => announced += 1);
        addTearDown(subscription.cancel);

        await harness.service.signInWithApple();
        harness.auth.signedIn = MockUser(uid: 'someone-else');
        answer.complete({'status': 'remediated', 'reauthenticate': true});
        await pumpEventQueue();

        expect(harness.auth.signOutCalls, 0);
        expect(announced, 0);
      },
    );

    test(
      'a remediation signs this device out and asks the owner to sign in again',
      () async {
        final harness = _Harness(
          isNewUser: false,
          check: () async => {'status': 'remediated', 'reauthenticate': true},
        );

        await expectLater(
          harness.service.signInWithApple(),
          throwsA(isA<FederatedSessionSecuredException>()),
        );
        // The server revoked this device's refresh token with everyone
        // else's; staying "signed in" would only fail later, mid-use.
        expect(harness.auth.signOutCalls, 1);
        expect(
          harness.service.getErrorMessage(
            const FederatedSessionSecuredException(),
          ),
          _english,
        );
      },
    );

    test('an unreachable or undeployed check never blocks a sign-in', () async {
      for (final failure in <Object>[
        StateError('functions unavailable'),
        TimeoutException('slow cold start'),
      ]) {
        final harness = _Harness(
          isNewUser: false,
          check: () async => throw failure,
        );

        final credential = await harness.service.signInWithApple();

        expect(credential.user?.uid, 'owner');
        expect(harness.auth.signOutCalls, 0);
      }
    });

    test('any other answer is treated as nothing to do', () async {
      for (final answer in <Map<String, dynamic>>[
        {'status': 'notApplicable', 'reauthenticate': false},
        {},
        {'status': 'REMEDIATED'},
      ]) {
        final harness = _Harness(isNewUser: false, check: () async => answer);

        await harness.service.signInWithApple();

        expect(harness.auth.signOutCalls, 0);
      }
    });
  });

  group('secured-session notice on the sign-in screen', () {
    testWidgets('is shown in English while the screen is still up', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _SecuredAuthService();
      await _pumpSignIn(tester, home: LoginScreen(authService: service));

      await _tapGoogle(tester);
      service.release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_english), findsOneWidget);
    });

    testWidgets('is shown in Polish for a Polish device', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _SecuredAuthService();
      await _pumpSignIn(
        tester,
        home: LoginScreen(authService: service),
        locale: const Locale('pl'),
      );

      await _tapGoogle(tester);
      service.release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_polish), findsOneWidget);
    });

    testWidgets(
      'still reaches the owner after the auth gate replaced the screen',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _SecuredAuthService();
        final signedIn = ValueNotifier<bool>(false);
        addTearDown(signedIn.dispose);
        await _pumpSignIn(
          tester,
          home: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (context, value, _) => value
                ? const Scaffold(body: Text('authenticated entry'))
                : LoginScreen(authService: service),
          ),
        );

        await _tapGoogle(tester);
        // Firebase publishes the returning account first: AuthGate swaps the
        // sign-in screen out before the post-sign-in check answers.
        signedIn.value = true;
        await tester.pump();
        expect(find.text('authenticated entry'), findsOneWidget);

        service.release.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(_english), findsOneWidget);
      },
    );

    testWidgets(
      'reaches the owner when the remediation is only known after sign-in',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _LateSecuredAuthService();
        addTearDown(service.late.close);
        final signedIn = ValueNotifier<bool>(false);
        addTearDown(signedIn.dispose);
        await _pumpSignIn(
          tester,
          home: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (context, value, _) => value
                ? const Scaffold(body: Text('authenticated entry'))
                : LoginScreen(authService: service),
          ),
        );

        await _tapGoogle(tester);
        await tester.pump();
        signedIn.value = true;
        await tester.pump();
        expect(find.text('authenticated entry'), findsOneWidget);
        expect(find.text(_english), findsNothing);

        // The slow or background check answers "remediated" afterwards.
        service.late.add(null);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(_english), findsOneWidget);
      },
    );
  });
}
