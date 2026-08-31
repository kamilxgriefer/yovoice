import 'package:barcode_widget/barcode_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/widgets/animated_totp_code_input.dart';
import 'package:yovoice/features/settings/presentation/screens/two_factor_authentication_screen.dart';

import 'totp_challenge_test_support.dart';

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
    final statusCard = tester.widget<Container>(
      find.byKey(const ValueKey('two-factor-status-card')),
    );
    expect(
      (statusCard.decoration! as BoxDecoration).color,
      AppPalette.dark.successSurface,
    );
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
        theme: AppTheme.lightTheme,
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
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      AppPalette.light.background,
    );
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(find.text('Enable two-factor authentication'), findsOneWidget);
  });

  group('TOTP sign-in challenge input and submission', () {
    Finder codeInput() => find.byKey(totpCodeInputKey);

    EditableText editableText(WidgetTester tester) =>
        tester.widget<EditableText>(
          find.descendant(of: codeInput(), matching: find.byType(EditableText)),
        );

    testWidgets(
      'uses one autofill-ready semantic input with digit formatters',
      (tester) async {
        await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
        await tester.pump();

        expect(find.byType(AutofillGroup), findsOneWidget);
        expect(
          tester
              .widget<AutofillGroup>(find.byType(AutofillGroup))
              .onDisposeAction,
          AutofillContextAction.cancel,
        );
        expect(find.byType(EditableText), findsOneWidget);
        final field = tester.widget<TextField>(codeInput());
        expect(field.keyboardType, TextInputType.number);
        expect(field.textInputAction, TextInputAction.done);
        expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
        expect(field.enableIMEPersonalizedLearning, isFalse);
        expect(
          field.inputFormatters,
          contains(isA<FilteringTextInputFormatter>()),
        );
        expect(
          field.inputFormatters,
          contains(isA<LengthLimitingTextInputFormatter>()),
        );
      },
    );

    testWidgets(
      'typing paste autofill-equivalent and backspace share the same field',
      (tester) async {
        final challenge = FakeTotpChallenge();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();

        await tester.enterText(codeInput(), '12a 34-56789');
        expect(editableText(tester).controller.text, '123456');
        expect(challenge.resolveCalls, 0);

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '12345',
            selection: TextSelection.collapsed(offset: 5),
          ),
        );
        await tester.pump();
        expect(editableText(tester).controller.text, '12345');

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '987654',
            selection: TextSelection.collapsed(offset: 6),
          ),
        );
        await tester.pump(const Duration(milliseconds: 119));
        expect(editableText(tester).controller.text, '987654');
        expect(challenge.resolveCalls, 0);
      },
    );

    for (var length = 0; length < 6; length += 1) {
      testWidgets('$length digits never reach resolve and keep input focused', (
        tester,
      ) async {
        final challenge = FakeTotpChallenge();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();
        await tester.enterText(codeInput(), '12345'.substring(0, length));
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();

        expect(challenge.resolveCalls, 0);
        expect(find.text('Enter all 6 digits.'), findsOneWidget);
        expect(editableText(tester).focusNode.hasFocus, isTrue);
      });
    }

    testWidgets('sixth digit auto-submits once at the 120ms edge', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '654321');

      await tester.pump(const Duration(milliseconds: 119));
      expect(challenge.resolveCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(challenge.resolveCalls, 1);
      expect(
        challenge.lastCall,
        isA<TotpResolveCall>()
            .having((call) => call.factorUid, 'factorUid', 'factor-1')
            .having((call) => call.code, 'code', '654321'),
      );

      await disposePendingTotp(tester, pending);
    });

    testWidgets('sixth digit done and rapid tap share one single-flight call', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '654321');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump(const Duration(milliseconds: 120));

      expect(challenge.resolveCalls, 1);
      expect(challenge.lastCall?.code, '654321');
      await disposePendingTotp(tester, pending);
    });

    testWidgets('changing authenticator cancels debounce and uses its uid', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge(
        factors: const <TotpSignInFactor>[
          TotpSignInFactor(uid: 'factor-1', displayName: 'Primary app'),
          TotpSignInFactor(uid: 'factor-2', displayName: 'Backup app'),
        ],
      );
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpFactorDropdownKey));
      await tester.pump();
      await tester.tap(find.text('Backup app').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(challenge.resolveCalls, 0);

      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      expect(challenge.resolveCalls, 1);
      expect(challenge.lastCall?.factorUid, 'factor-2');
      await disposePendingTotp(tester, pending);
    });

    testWidgets('Back is blocked synchronously on the submit edge', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      final probe = TotpRouteProbe();
      await tester.pumpWidget(totpRouteTestApp(challenge, probe));
      await tester.pump();
      await tester.pump();
      await tester.enterText(codeInput(), '123456');

      await tester.tap(find.byKey(totpVerifyButtonKey));
      expect(challenge.resolveCalls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Confirm it’s you'), findsOneWidget);
      expect(probe.results, isEmpty);
      await disposePendingTotp(tester, pending);
    });

    testWidgets('pending locks all controls and system Back', (tester) async {
      final challenge = FakeTotpChallenge(
        factors: const <TotpSignInFactor>[
          TotpSignInFactor(uid: 'factor-1', displayName: 'Primary app'),
          TotpSignInFactor(uid: 'factor-2', displayName: 'Backup app'),
        ],
      );
      final pending = challenge.enqueuePending();
      final probe = TotpRouteProbe();
      await tester.pumpWidget(totpRouteTestApp(challenge, probe));
      await tester.pump();
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();

      expect(tester.widget<TextField>(codeInput()).enabled, isFalse);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(totpFactorDropdownKey),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(totpVerifyButtonKey)).onPressed,
        isNull,
      );
      expect(find.text('Verifying code'), findsOneWidget);
      expect(find.byKey(totpStatusChannelKey), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Confirm it’s you'), findsOneWidget);
      expect(probe.results, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(totpSuccessBadgeKey), findsNothing);
      expect(find.byKey(totpSuccessCheckKey), findsNothing);
      expect(probe.results, isEmpty);
      await disposePendingTotp(tester, pending);
    });

    testWidgets(
      'success blocks Back through hold and exit then pops true exactly once',
      (tester) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        final probe = TotpRouteProbe();
        await tester.pumpWidget(totpRouteTestApp(challenge, probe));
        await tester.pump();
        await tester.pump();
        await tester.enterText(codeInput(), '123456');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump(const Duration(milliseconds: 60));

        pending.complete();
        await tester.pump();
        expect(find.byKey(totpSuccessBadgeKey), findsOneWidget);
        expect(probe.results, isEmpty);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Confirm it’s you'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 660));
        expect(find.byKey(totpSuccessCheckKey), findsOneWidget);
        expect(find.text('Code verified'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(probe.results, isEmpty);

        await tester.pump(const Duration(milliseconds: 179));
        expect(probe.results, isEmpty);
        await tester.pump(const Duration(milliseconds: 199));
        expect(probe.results, isEmpty);
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();
        expect(probe.results, <bool?>[true]);
        expect(probe.challengePops, 1);
      },
    );

    testWidgets('Back cannot win the final success-frame race', (tester) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      final probe = TotpRouteProbe();
      await tester.pumpWidget(totpRouteTestApp(challenge, probe));
      await tester.pump();
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump(const Duration(milliseconds: 60));
      pending.complete();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 1039));
      expect(probe.results, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(probe.results, <bool?>[true]);
      expect(probe.challengePops, 1);
    });

    testWidgets('cancelled success motion never authenticates or pops', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      final probe = TotpRouteProbe();
      await tester.pumpWidget(totpRouteTestApp(challenge, probe));
      await tester.pump();
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      pending.complete();
      await tester.pump();

      tester
          .state<AnimatedTotpCodeInputState>(find.byType(AnimatedTotpCodeInput))
          .resetEditing();
      await tester.pump();

      expect(probe.results, isEmpty);
      expect(probe.challengePops, 0);
      expect(tester.widget<TextField>(codeInput()).enabled, isTrue);
    });

    for (final invalidCode in <String>[
      'invalid-verification-code',
      'invalid-credential',
    ]) {
      testWidgets(
        '$invalidCode shows a red X before clear focus and manual re-entry',
        (tester) async {
          final challenge = FakeTotpChallenge();
          final invalid = challenge.enqueuePending();
          final reentry = challenge.enqueuePending();
          await tester.pumpWidget(totpTestApp(challenge));
          await tester.pump();
          await tester.enterText(codeInput(), '123456');
          await tester.tap(find.byKey(totpVerifyButtonKey));
          await tester.pump();
          invalid.completeError(FirebaseAuthException(code: invalidCode));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          final badge = tester.widget<Container>(
            find.byKey(totpInvalidBadgeKey),
          );
          final decoration = badge.decoration! as BoxDecoration;
          expect(decoration.color, AppColors.error);
          expect(decoration.shape, BoxShape.circle);
          expect(
            tester.widget<Icon>(find.byKey(totpInvalidXKey)).icon,
            Icons.close_rounded,
          );
          expect(find.byKey(totpSuccessBadgeKey), findsNothing);
          expect(find.byKey(totpSuccessCheckKey), findsNothing);
          expect(editableText(tester).controller.text, '123456');

          await tester.pump(const Duration(milliseconds: 499));
          expect(editableText(tester).controller.text, '123456');
          expect(tester.widget<TextField>(codeInput()).enabled, isFalse);
          expect(
            tester
                .widget<FilledButton>(find.byKey(totpVerifyButtonKey))
                .onPressed,
            isNull,
          );

          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump();
          expect(editableText(tester).controller.text, isEmpty);
          expect(editableText(tester).focusNode.hasFocus, isTrue);
          expect(tester.widget<TextField>(codeInput()).enabled, isTrue);
          expect(
            tester
                .state<AnimatedTotpCodeInputState>(
                  find.byType(AnimatedTotpCodeInput),
                )
                .debugFrame
                .phase,
            TotpChallengePhase.editing,
          );
          expect(find.byKey(totpInvalidBadgeKey), findsNothing);
          expect(find.byKey(totpInvalidXKey), findsNothing);
          await tester.pump(const Duration(seconds: 2));
          expect(challenge.resolveCalls, 1);

          await tester.enterText(codeInput(), '222222');
          await tester.pump(const Duration(milliseconds: 120));
          expect(challenge.resolveCalls, 2);
          expect(challenge.lastCall?.code, '222222');
          await disposePendingTotp(tester, reentry);
        },
      );
    }

    for (final failure in <({String name, Object error})>[
      (
        name: 'too-many-requests',
        error: FirebaseAuthException(code: 'too-many-requests'),
      ),
      (
        name: 'network-request-failed',
        error: FirebaseAuthException(code: 'network-request-failed'),
      ),
      (name: 'generic platform failure', error: StateError('platform failure')),
    ]) {
      testWidgets(
        '${failure.name} preserves code disarms auto retry and allows tap',
        (tester) async {
          final challenge = FakeTotpChallenge();
          challenge.enqueueError(failure.error);
          final retry = challenge.enqueuePending();
          await tester.pumpWidget(totpTestApp(challenge));
          await tester.pump();
          await tester.enterText(codeInput(), '654321');
          await tester.tap(find.byKey(totpVerifyButtonKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));

          expect(editableText(tester).controller.text, '654321');
          expect(editableText(tester).focusNode.hasFocus, isTrue);
          await tester.pump(const Duration(seconds: 2));
          expect(challenge.resolveCalls, 1);
          await tester.tap(find.byKey(totpVerifyButtonKey));
          await tester.pump();
          expect(challenge.resolveCalls, 2);
          await disposePendingTotp(tester, retry);
        },
      );
    }

    testWidgets('editing below six re-arms the automatic submit edge', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      challenge.enqueueError(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      final retry = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      // Let the scripted immediate backend error start the feedback timeline
      // before advancing that timeline by its full duration.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(challenge.resolveCalls, 1);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '12345',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '123457',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(challenge.resolveCalls, 2);
      expect(challenge.lastCall?.code, '123457');
      await disposePendingTotp(tester, retry);
    });

    testWidgets('FormatException stays contained and returns to retry', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      challenge.enqueueError(
        const FormatException('SENSITIVE_RESOLVER_STATE must never render'),
      );
      final retry = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '654321');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Two-factor verification could not be completed. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('SENSITIVE_RESOLVER_STATE'), findsNothing);
      expect(find.byKey(totpErrorCardKey), findsOneWidget);
      expect(editableText(tester).controller.text, '654321');
      expect(editableText(tester).focusNode.hasFocus, isTrue);

      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      expect(challenge.resolveCalls, 2);
      await disposePendingTotp(tester, retry);
    });

    testWidgets('empty factors fail closed without calling resolve', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge(factors: const []);
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();

      expect(find.byKey(totpCodeInputKey), findsNothing);
      expect(find.byKey(totpVerifyButtonKey), findsNothing);
      expect(find.textContaining('No supported authenticator'), findsOneWidget);
      expect(challenge.resolveCalls, 0);
    });

    testWidgets('dispose during a pending request is lifecycle safe', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(codeInput(), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('TOTP challenge semantics and branding', () {
    testWidgets('has one input one polite channel and decorative digit cells', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();

      expect(find.byType(EditableText), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(totpCodeInputKey)).label,
        '6-digit authenticator code',
      );
      final semanticTextFields = totpTextFields(tester);
      expect(semanticTextFields, hasLength(1));
      expect(
        semanticTextFields.single.getSemanticsData().label,
        '6-digit authenticator code',
      );
      expect(
        totpNodesWithLabel(tester, '6-digit authenticator code'),
        hasLength(1),
      );
      expect(find.byKey(totpStatusChannelKey), findsOneWidget);
      expect(totpLiveRegions(tester), hasLength(1));
      expect(
        tester.getSemantics(find.byKey(totpStatusChannelKey)).label,
        isEmpty,
      );
      expect(
        tester
            .getSemantics(find.text('Confirm it’s you'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      for (var index = 0; index < 6; index += 1) {
        final cell = find.byKey(totpDigitCellKey(index));
        expect(cell, findsOneWidget);
        expect(
          find.descendant(of: cell, matching: find.byType(ExcludeSemantics)),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('polite status only announces pending and verified states', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(totpStatusChannelKey)).label,
        isEmpty,
      );

      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(totpStatusChannelKey)).label,
        contains('Verifying code'),
      );

      pending.complete();
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(totpStatusChannelKey)).label,
        'Code verified',
      );
      expect(totpLiveRegions(tester), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('invalid code is announced assertively exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final announcements = captureTotpAnnouncements(tester);
      final challenge = FakeTotpChallenge();
      challenge.enqueueError(
        FirebaseAuthException(code: 'invalid-verification-code'),
      );
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      announcements.clear();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump(const Duration(milliseconds: 600));

      final assertive = announcements
          .where(isAssertiveAnnouncement)
          .map(announcementMessage)
          .toList(growable: false);
      expect(assertive, <String>[
        'That code is not valid. Enter a new code and try again.',
      ]);
      expect(totpLiveRegions(tester), hasLength(1));
      handle.dispose();
    });

    testWidgets('incomplete code is announced assertively exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final announcements = captureTotpAnnouncements(tester);
      final challenge = FakeTotpChallenge();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      announcements.clear();
      await tester.enterText(find.byKey(totpCodeInputKey), '123');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();

      final assertive = announcements
          .where(isAssertiveAnnouncement)
          .map(announcementMessage)
          .toList(growable: false);
      expect(assertive, <String>['Enter all 6 digits.']);
      expect(challenge.resolveCalls, 0);
      expect(totpLiveRegions(tester), hasLength(1));
      handle.dispose();
    });

    testWidgets('uses the canonical untinted YO Voice logo', (tester) async {
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();

      final image = tester.widget<Image>(find.byKey(totpLogoKey));
      expect(
        image.image,
        isA<AssetImage>().having(
          (asset) => asset.assetName,
          'assetName',
          'assets/images/yo-voice-favicon-512.png',
        ),
      );
      expect(image.fit, BoxFit.contain);
      expect(image.color, isNull);
    });

    testWidgets('all interactive controls retain at least 44px targets', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge(
        factors: const <TotpSignInFactor>[
          TotpSignInFactor(uid: 'factor-1', displayName: 'Primary app'),
          TotpSignInFactor(uid: 'factor-2', displayName: 'Backup app'),
        ],
      );
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();

      for (final key in <ValueKey<String>>[
        totpCodeInputKey,
        totpFactorDropdownKey,
        totpVerifyButtonKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(44), reason: key.value);
        expect(size.width, greaterThanOrEqualTo(44), reason: key.value);
      }
    });
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
  }

  for (final size in <Size>[
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 844),
    const Size(768, 1024),
    const Size(1100, 900),
    const Size(1440, 900),
    const Size(2560, 1440),
  ]) {
    testWidgets(
      'challenge fits ${size.width.toInt()}x${size.height.toInt()} at 200%',
      (tester) async {
        useTotpSurface(tester, size);
        await tester.pumpWidget(
          totpTestApp(
            FakeTotpChallenge(
              factors: const <TotpSignInFactor>[
                TotpSignInFactor(
                  uid: 'factor-1',
                  displayName:
                      'A very long authenticator application name for layout',
                ),
                TotpSignInFactor(
                  uid: 'factor-2',
                  displayName: 'Backup authenticator application',
                ),
              ],
            ),
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Confirm it’s you'), findsOneWidget);
        expect(find.byKey(totpMotionStageKey), findsOneWidget);
      },
    );
  }

  testWidgets('keyboard inset remains scrollable without overflow', (
    tester,
  ) async {
    useTotpSurface(tester, const Size(320, 640));
    await tester.pumpWidget(
      totpTestApp(
        FakeTotpChallenge(),
        textScaler: const TextScaler.linear(2),
        viewInsets: const EdgeInsets.only(bottom: 300),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(totpVerifyButtonKey), findsOneWidget);
  });

  testWidgets('Pearl theme keeps challenge on an immersive dark island', (
    tester,
  ) async {
    await tester.pumpWidget(
      totpTestApp(FakeTotpChallenge(), theme: AppTheme.lightTheme),
    );
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.dark.background);
    expect(
      tester.widget<Text>(find.text('Confirm it’s you')).style?.color,
      AppPalette.dark.textPrimary,
    );
  });
}
