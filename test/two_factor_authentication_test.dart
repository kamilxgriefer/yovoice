import 'package:barcode_widget/barcode_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/two_factor_authentication_screen.dart';

class _FakeTotpClient implements TotpMfaClient {
  _FakeTotpClient({
    List<TotpFactorSummary>? factors,
    this.isSupportedPlatform = true,
    this.canOpenAuthenticatorApp = true,
    this.enrollmentDeadline,
    this.openError,
    this.removeError,
  }) : factors = factors ?? <TotpFactorSummary>[];

  List<TotpFactorSummary> factors;
  @override
  final bool isSupportedPlatform;
  @override
  final bool canOpenAuthenticatorApp;
  final DateTime? enrollmentDeadline;
  final Object? openError;
  final Object? removeError;
  String? completedCode;
  String? removedUid;
  bool opened = false;
  bool pendingEnrollmentCancelled = false;
  int getFactorsCalls = 0;

  @override
  void cancelPendingEnrollment() {
    pendingEnrollmentCancelled = true;
  }

  @override
  Future<void> completeEnrollment(String code) async {
    completedCode = code;
    factors = [
      TotpFactorSummary(
        uid: 'factor-1',
        displayName: 'YO Voice authenticator',
        enrolledAt: DateTime.utc(2026, 8, 18),
      ),
    ];
  }

  @override
  Future<List<TotpFactorSummary>> getFactors() async {
    getFactorsCalls += 1;
    return factors;
  }

  @override
  Future<void> openPendingInAuthenticatorApp() async {
    opened = true;
    if (openError != null) throw openError!;
  }

  @override
  List<String> get providerIds => const ['password'];

  @override
  Future<void> reauthenticateWithApple() async {}

  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}

  @override
  Future<void> removeFactor(String factorUid) async {
    removedUid = factorUid;
    if (removeError != null) throw removeError!;
    factors = [];
  }

  @override
  Future<TotpEnrollmentDraft> startEnrollment() async => TotpEnrollmentDraft(
    secretKey: 'ABCDEFGHIJKLMNOP',
    qrCodeUrl: 'otpauth://totp/YO%20Voice:test@example.com?secret=ABC',
    expiresAt:
        enrollmentDeadline ?? DateTime.now().add(const Duration(minutes: 10)),
  );
}

class _FakeChallenge implements TotpSignInChallengeClient {
  _FakeChallenge({this.error});

  final Object? error;
  String? receivedFactor;
  String? receivedCode;

  @override
  final factors = const [
    TotpSignInFactor(uid: 'factor-1', displayName: 'Authenticator app'),
  ];

  @override
  Future<void> resolve({
    required String factorUid,
    required String code,
  }) async {
    if (error != null) throw error!;
    receivedFactor = factorUid;
    receivedCode = code;
  }
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: MediaQuery(data: const MediaQueryData(), child: child),
);

void main() {
  testWidgets('enrollment UI calls client and updates enabled state', (
    tester,
  ) async {
    final client = _FakeTotpClient();
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2FA is not enabled'), findsOneWidget);
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your authenticator'), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text('ABCDEFGHIJKLMNOP'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open authenticator app'));
    await tester.pump();
    expect(client.opened, isTrue);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable two-factor authentication'));
    await tester.pumpAndSettle();

    expect(client.completedCode, '123456');
    expect(find.text('2FA is enabled'), findsOneWidget);
    expect(find.text('YO Voice authenticator'), findsOneWidget);
  });

  testWidgets('web-style flow does not offer unsupported app launcher', (
    tester,
  ) async {
    final client = _FakeTotpClient(canOpenAuthenticatorApp: false);
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();

    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text('Open authenticator app'), findsNothing);
    expect(client.opened, isFalse);
  });

  testWidgets('authenticator launch failure never claims to copy the secret', (
    tester,
  ) async {
    final client = _FakeTotpClient(
      openError: UnsupportedError('No authenticator app is available.'),
    );
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Set up authenticator'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open authenticator app'));
    await tester.pumpAndSettle();
    expect(client.opened, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();

    expect(find.text('No authenticator app is available.'), findsOneWidget);
    expect(find.textContaining('Secret copied'), findsNothing);
  });

  testWidgets('cancel clears the pending enrollment secret', (tester) async {
    final client = _FakeTotpClient();
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel setup'));
    await tester.pumpAndSettle();

    expect(client.pendingEnrollmentCancelled, isTrue);
    expect(find.text('Connect your authenticator'), findsNothing);
  });

  testWidgets('expired enrollment is cleared before completion', (
    tester,
  ) async {
    final client = _FakeTotpClient(
      enrollmentDeadline: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable two-factor authentication'));
    await tester.pumpAndSettle();

    expect(client.completedCode, isNull);
    expect(client.pendingEnrollmentCancelled, isTrue);
    expect(find.textContaining('This setup expired'), findsOneWidget);
  });

  testWidgets('unsupported platforms do not call Firebase MFA APIs', (
    tester,
  ) async {
    final client = _FakeTotpClient(isSupportedPlatform: false);
    await tester.pumpWidget(
      _app(TwoFactorAuthenticationScreen(client: client)),
    );
    await tester.pumpAndSettle();

    expect(client.getFactorsCalls, 0);
    expect(find.textContaining('not supported by Firebase'), findsOneWidget);
    expect(find.text('Set up authenticator'), findsNothing);
  });

  testWidgets('token expiry during removal signs out safely', (tester) async {
    var signedOut = false;
    final client = _FakeTotpClient(
      factors: [
        TotpFactorSummary(
          uid: 'factor-1',
          displayName: 'YO Voice authenticator',
          enrolledAt: DateTime.utc(2026, 8, 18),
        ),
      ],
      removeError: FirebaseAuthException(code: 'user-token-expired'),
    );
    await tester.pumpWidget(
      _app(
        TwoFactorAuthenticationScreen(
          client: client,
          signOutForExpiredSession: () async => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove authenticator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
    expect(client.removedUid, 'factor-1');
  });

  testWidgets('QR enrollment fits 320px at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = _FakeTotpClient(canOpenAuthenticatorApp: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: TwoFactorAuthenticationScreen(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Set up authenticator'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text('Enable two-factor authentication'), findsOneWidget);
  });

  testWidgets('sign-in challenge submits selected authenticator code', (
    tester,
  ) async {
    final challenge = _FakeChallenge();
    await tester.pumpWidget(_app(TotpChallengeScreen(challenge: challenge)));
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();

    expect(challenge.receivedFactor, 'factor-1');
    expect(challenge.receivedCode, '654321');
  });

  testWidgets('sign-in challenge contains unexpected platform failures', (
    tester,
  ) async {
    final challenge = _FakeChallenge(error: StateError('platform failure'));
    await tester.pumpWidget(_app(TotpChallengeScreen(challenge: challenge)));
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('could not be completed'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
    testWidgets('2FA screen fits ${width.toInt()}px at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = _FakeTotpClient(
        factors: [
          TotpFactorSummary(
            uid: 'factor-1',
            displayName: 'My authenticator application',
            enrolledAt: DateTime.utc(2026, 8, 18),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: TwoFactorAuthenticationScreen(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2FA is enabled'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2FA is enabled'), findsOneWidget);
    });

    testWidgets('challenge fits ${width.toInt()}px at 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: TotpChallengeScreen(challenge: _FakeChallenge()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Confirm it’s you'), findsOneWidget);
    });
  }
}
