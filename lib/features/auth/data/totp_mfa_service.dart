import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class TotpFactorSummary {
  const TotpFactorSummary({
    required this.uid,
    required this.displayName,
    required this.enrolledAt,
  });

  final String uid;
  final String displayName;
  final DateTime enrolledAt;
}

class TotpEnrollmentDraft {
  const TotpEnrollmentDraft({
    required this.secretKey,
    required this.qrCodeUrl,
    required this.expiresAt,
  });

  final String secretKey;
  final String qrCodeUrl;
  final DateTime? expiresAt;
}

class TotpSignInFactor {
  const TotpSignInFactor({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
}

abstract interface class TotpSignInChallengeClient {
  List<TotpSignInFactor> get factors;
  Future<void> resolve({required String factorUid, required String code});
}

class TotpSignInChallenge implements TotpSignInChallengeClient {
  TotpSignInChallenge(this._resolver)
    : factors = _resolver.hints
          .whereType<TotpMultiFactorInfo>()
          .map(
            (factor) => TotpSignInFactor(
              uid: factor.uid,
              displayName: factor.displayName?.trim().isNotEmpty == true
                  ? factor.displayName!.trim()
                  : 'Authenticator app',
            ),
          )
          .toList(growable: false);

  final MultiFactorResolver _resolver;
  @override
  final List<TotpSignInFactor> factors;

  @override
  Future<void> resolve({
    required String factorUid,
    required String code,
  }) async {
    final normalized = _normalizeTotpCode(code);
    if (!factors.any((factor) => factor.uid == factorUid)) {
      throw const FormatException('Choose a valid authenticator.');
    }
    final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(
      factorUid,
      normalized,
    );
    await _resolver.resolveSignIn(assertion);
  }
}

abstract interface class TotpMfaClient {
  bool get isSupportedPlatform;
  bool get canOpenAuthenticatorApp;
  Future<List<TotpFactorSummary>> getFactors();
  Future<TotpEnrollmentDraft> startEnrollment();
  Future<void> openPendingInAuthenticatorApp();
  Future<void> completeEnrollment(String code);
  void cancelPendingEnrollment();
  Future<void> removeFactor(String factorUid);
  Future<void> reauthenticateWithPassword(String password);
  Future<void> reauthenticateWithGoogle();
  Future<void> reauthenticateWithApple();
  List<String> get providerIds;
}

class TotpMfaService implements TotpMfaClient {
  TotpMfaService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  TotpSecret? _pendingSecret;
  String? _pendingQrCodeUrl;

  @override
  bool get isSupportedPlatform {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.linux || TargetPlatform.windows => false,
      TargetPlatform.fuchsia => false,
    };
  }

  @override
  bool get canOpenAuthenticatorApp => !kIsWeb && isSupportedPlatform;

  User get _requiredUser {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError(
        'You must be signed in to manage two-factor authentication.',
      );
    }
    return user;
  }

  @override
  Future<List<TotpFactorSummary>> getFactors() async {
    final factors = await _requiredUser.multiFactor.getEnrolledFactors();
    return factors
        .whereType<TotpMultiFactorInfo>()
        .map(
          (factor) => TotpFactorSummary(
            uid: factor.uid,
            displayName: factor.displayName?.trim().isNotEmpty == true
                ? factor.displayName!.trim()
                : 'Authenticator app',
            enrolledAt: DateTime.fromMillisecondsSinceEpoch(
              (factor.enrollmentTimestamp * 1000).round(),
              isUtc: true,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<TotpEnrollmentDraft> startEnrollment() async {
    cancelPendingEnrollment();
    final user = _requiredUser;
    if (!user.emailVerified) {
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verify your email before enabling two-factor authentication.',
      );
    }
    final session = await user.multiFactor.getSession();
    final secret = await TotpMultiFactorGenerator.generateSecret(session);
    final accountName = user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : user.uid;
    final qrCodeUrl = await secret.generateQrCodeUrl(
      accountName: accountName,
      issuer: 'YO Voice',
    );
    _pendingSecret = secret;
    _pendingQrCodeUrl = qrCodeUrl;
    return TotpEnrollmentDraft(
      secretKey: secret.secretKey,
      qrCodeUrl: qrCodeUrl,
      expiresAt: secret.enrollmentCompletionDeadline,
    );
  }

  @override
  Future<void> openPendingInAuthenticatorApp() async {
    if (!canOpenAuthenticatorApp) {
      throw UnsupportedError(
        'Opening an authenticator app is not available on this platform.',
      );
    }
    final secret = _pendingSecret;
    final url = _pendingQrCodeUrl;
    if (secret == null || url == null) {
      throw StateError('Start two-factor setup first.');
    }
    await secret.openInOtpApp(url);
  }

  @override
  Future<void> completeEnrollment(String code) async {
    final secret = _pendingSecret;
    if (secret == null) {
      throw StateError('Start two-factor setup first.');
    }
    final deadline = secret.enrollmentCompletionDeadline;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      cancelPendingEnrollment();
      throw FirebaseAuthException(
        code: 'session-expired',
        message: 'This setup expired. Start again to create a new secret.',
      );
    }
    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(
      secret,
      _normalizeTotpCode(code),
    );
    await _requiredUser.multiFactor.enroll(
      assertion,
      displayName: 'YO Voice authenticator',
    );
    cancelPendingEnrollment();
  }

  @override
  void cancelPendingEnrollment() {
    _pendingSecret = null;
    _pendingQrCodeUrl = null;
  }

  @override
  Future<void> removeFactor(String factorUid) async {
    if (factorUid.trim().isEmpty) {
      throw const FormatException('Choose a valid authenticator.');
    }
    await _requiredUser.multiFactor.unenroll(factorUid: factorUid);
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _requiredUser;
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw StateError('This account does not have an email password.');
    }
    if (password.isEmpty) {
      throw const FormatException('Enter your password.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    if (kIsWeb) {
      await _requiredUser.reauthenticateWithPopup(provider);
    } else {
      await _requiredUser.reauthenticateWithProvider(provider);
    }
  }

  @override
  Future<void> reauthenticateWithApple() async {
    final provider = AppleAuthProvider();
    if (kIsWeb) {
      await _requiredUser.reauthenticateWithPopup(provider);
    } else {
      await _requiredUser.reauthenticateWithProvider(provider);
    }
  }

  @override
  List<String> get providerIds => _requiredUser.providerData
      .map((provider) => provider.providerId)
      .toSet()
      .toList(growable: false);
}

String _normalizeTotpCode(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^\d{6}$').hasMatch(normalized)) {
    throw const FormatException(
      'Enter the 6-digit code from your authenticator app.',
    );
  }
  return normalized;
}
