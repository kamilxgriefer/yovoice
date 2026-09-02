import 'package:barcode_widget/barcode_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

Color _twoFactorSuccess(BuildContext context) =>
    context.appPalette.successForeground;

class TwoFactorAuthenticationScreen extends StatefulWidget {
  const TwoFactorAuthenticationScreen({
    this.isRootTab = false,
    this.client,
    this.signOutForExpiredSession,
    super.key,
  });

  final bool isRootTab;
  final TotpMfaClient? client;
  final Future<void> Function()? signOutForExpiredSession;

  @override
  State<TwoFactorAuthenticationScreen> createState() =>
      _TwoFactorAuthenticationScreenState();
}

class _TwoFactorAuthenticationScreenState
    extends State<TwoFactorAuthenticationScreen> {
  late final TotpMfaClient _client = widget.client ?? TotpMfaService();
  late final Future<void> Function() _signOutForExpiredSession =
      widget.signOutForExpiredSession ?? AuthService().signOut;
  final _codeController = TextEditingController();
  List<TotpFactorSummary>? _factors;
  TotpEnrollmentDraft? _draft;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _client.cancelPendingEnrollment();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_client.isSupportedPlatform) {
      setState(() => _factors = const []);
      return;
    }
    try {
      final factors = await _client.getFactors();
      if (mounted) setState(() => _factors = factors);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    }
  }

  Future<void> _startSetup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await _client.startEnrollment();
      if (mounted) setState(() => _draft = draft);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login' && mounted) {
        final reauthenticated = await _reauthenticate();
        if (reauthenticated && mounted) {
          setState(() => _busy = false);
          await _startSetup();
          return;
        }
      } else if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _reauthenticate() async {
    final providers = _client.providerIds;
    if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
      return _performReauth(_client.reauthenticateWithGoogle);
    }
    if (providers.contains(AppleAuthProvider.PROVIDER_ID)) {
      return _performReauth(_client.reauthenticateWithApple);
    }
    if (!providers.contains(EmailAuthProvider.PROVIDER_ID)) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).text(
            'Sign out and sign in again before changing two-factor authentication.',
            'Wyloguj się i zaloguj ponownie, zanim zmienisz ustawienia uwierzytelniania dwuskładnikowego.',
          );
        });
      }
      return false;
    }

    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(copy.text('Confirm your password', 'Potwierdź hasło')),
          content: TextField(
            controller: passwordController,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: copy.text('Password', 'Hasło'),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, passwordController.text),
              child: Text(copy.text('Continue', 'Dalej')),
            ),
          ],
        );
      },
    );
    passwordController.dispose();
    if (password == null) return false;
    return _performReauth(() => _client.reauthenticateWithPassword(password));
  }

  Future<bool> _performReauth(Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
      return false;
    }
  }

  Future<void> _openAuthenticator() async {
    try {
      await _client.openPendingInAuthenticatorApp();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    }
  }

  void _cancelSetup() {
    _client.cancelPendingEnrollment();
    setState(() {
      _draft = null;
      _error = null;
      _codeController.clear();
    });
  }

  Future<void> _completeSetup() async {
    if (_busy) return;
    final deadline = _draft?.expiresAt;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      _client.cancelPendingEnrollment();
      setState(() {
        _draft = null;
        _codeController.clear();
        _error = AppLocalizations.of(context).text(
          'This setup expired. Start again to create a new secret.',
          'Ta konfiguracja wygasła. Rozpocznij ponownie, aby utworzyć nowy klucz.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.completeEnrollment(_codeController.text);
      _codeController.clear();
      final factors = await _client.getFactors();
      if (!mounted) return;
      setState(() {
        _draft = null;
        _factors = factors;
      });
      _notify(
        AppLocalizations.of(context).text(
          'Two-factor authentication is now enabled.',
          'Uwierzytelnianie dwuskładnikowe zostało włączone.',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TotpFactorSummary factor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            copy.text(
              'Remove authenticator?',
              'Usunąć aplikację uwierzytelniającą?',
            ),
          ),
          content: Text(
            copy.text(
              'You will no longer need a code from this authenticator when signing in.',
              'Kod z tej aplikacji uwierzytelniającej nie będzie już wymagany podczas logowania.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Keep it', 'Zachowaj')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(copy.text('Remove', 'Usuń')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _busy) {
      return;
    }
    await _removeConfirmed(factor);
  }

  Future<void> _removeConfirmed(
    TotpFactorSummary factor, {
    bool retriedAfterReauthentication = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.removeFactor(factor.uid);
      final factors = await _client.getFactors();
      if (!mounted) return;
      setState(() => _factors = factors);
      _notify(
        AppLocalizations.of(context).text(
          'Authenticator removed.',
          'Usunięto aplikację uwierzytelniającą.',
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-token-expired') {
        if (mounted) {
          _notify(
            AppLocalizations.of(context).text(
              'Authenticator removed. Firebase ended this session; sign in again.',
              'Usunięto aplikację uwierzytelniającą. Firebase zakończył tę sesję — zaloguj się ponownie.',
            ),
          );
        }
        await _signOutForExpiredSession();
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (error.code == 'requires-recent-login' &&
          !retriedAfterReauthentication &&
          mounted) {
        final reauthenticated = await _reauthenticate();
        if (reauthenticated && mounted) {
          await _removeConfirmed(factor, retriedAfterReauthentication: true);
          return;
        }
      } else if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(Object error) {
    final copy = AppLocalizations.of(context);
    if (error is FormatException) {
      return copy.text(
        error.message,
        'Wprowadzone dane mają nieprawidłowy format.',
      );
    }
    if (error is StateError) {
      return copy.text(
        error.message,
        'Nie można teraz wykonać tej operacji. Spróbuj ponownie.',
      );
    }
    if (error is UnsupportedError) {
      return copy.text(
        error.message ?? 'Not supported.',
        'Ta funkcja nie jest obsługiwana.',
      );
    }
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'email-not-verified' => copy.text(
          'Verify your email before enabling two-factor authentication.',
          'Zweryfikuj adres e-mail przed włączeniem uwierzytelniania dwuskładnikowego.',
        ),
        'invalid-verification-code' || 'invalid-credential' => copy.text(
          'That code is not valid. Wait for a new code and try again.',
          'Ten kod jest nieprawidłowy. Poczekaj na nowy kod i spróbuj ponownie.',
        ),
        'wrong-password' => copy.text(
          'The password is not correct.',
          'Hasło jest nieprawidłowe.',
        ),
        'too-many-requests' => copy.text(
          'Too many attempts. Please try again later.',
          'Zbyt wiele prób. Spróbuj ponownie później.',
        ),
        'session-expired' => copy.text(
          'This setup expired. Start again to create a new secret.',
          'Ta konfiguracja wygasła. Rozpocznij ponownie, aby utworzyć nowy klucz.',
        ),
        'operation-not-allowed' => copy.text(
          'Two-factor authentication is not enabled for this app yet.',
          'Uwierzytelnianie dwuskładnikowe nie jest jeszcze włączone dla tej aplikacji.',
        ),
        _ => copy.text(
          'Two-factor authentication could not be updated.',
          'Nie udało się zaktualizować uwierzytelniania dwuskładnikowego.',
        ),
      };
    }
    return copy.text(
      'Two-factor authentication could not be updated.',
      'Nie udało się zaktualizować uwierzytelniania dwuskładnikowego.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final factors = _factors;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: widget.isRootTab
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              title: Text(
                copy.text(
                  'Two-factor authentication',
                  'Uwierzytelnianie dwuskładnikowe',
                ),
              ),
            ),
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          alignment: ResponsiveContentAlignment.topLeft,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 64),
            children: [
              Text(
                copy.text(
                  'Two-factor authentication',
                  'Uwierzytelnianie dwuskładnikowe',
                ),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.text(
                  'Protect your account with a changing 6-digit code from an authenticator app. YO Voice never asks for your authenticator secret.',
                  'Chroń konto zmieniającym się, 6-cyfrowym kodem z aplikacji uwierzytelniającej. YO Voice nigdy nie prosi o podanie tajnego klucza uwierzytelniającego.',
                ),
                style: TextStyle(color: palette.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (!_client.isSupportedPlatform)
                const _UnsupportedPlatformCard()
              else if (factors == null)
                Center(child: CircularProgressIndicator(color: colors.primary))
              else ...[
                _StatusCard(enabled: factors.isNotEmpty),
                const SizedBox(height: 18),
                for (final factor in factors) ...[
                  _FactorCard(
                    factor: factor,
                    busy: _busy,
                    onRemove: () => _remove(factor),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_draft == null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _busy ? null : _startSetup,
                    icon: const Icon(Icons.add_moderator_rounded),
                    label: Text(
                      factors.isEmpty
                          ? copy.text(
                              'Set up authenticator',
                              'Skonfiguruj aplikację uwierzytelniającą',
                            )
                          : copy.text(
                              'Add another authenticator',
                              'Dodaj kolejną aplikację uwierzytelniającą',
                            ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  _EnrollmentCard(
                    draft: _draft!,
                    codeController: _codeController,
                    busy: _busy,
                    canOpenAuthenticatorApp: _client.canOpenAuthenticatorApp,
                    onOpenAuthenticator: _openAuthenticator,
                    onCopySecret: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _draft!.secretKey),
                      );
                      if (mounted) {
                        _notify(
                          copy.text(
                            'Secret copied.',
                            'Skopiowano klucz konfiguracji.',
                          ),
                        );
                      }
                    },
                    onComplete: _completeSetup,
                    onCancel: _busy ? null : _cancelSetup,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UnsupportedPlatformCard extends StatelessWidget {
  const _UnsupportedPlatformCard();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.desktop_access_disabled_rounded,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                copy.text(
                  'Authenticator-based two-factor authentication is not supported by Firebase on Windows or Linux. Set it up from YO Voice on the web, Android, iPhone, iPad or Mac.',
                  'Firebase nie obsługuje uwierzytelniania dwuskładnikowego z aplikacją uwierzytelniającą w systemach Windows i Linux. Skonfiguruj je w YO Voice w przeglądarce, na Androidzie, iPhonie, iPadzie lub Macu.',
                ),
                style: TextStyle(color: palette.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final color = enabled ? _twoFactorSuccess(context) : palette.textSecondary;
    return Container(
      key: const ValueKey('two-factor-status-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: enabled ? palette.successSurface : palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? color.withValues(alpha: .55) : palette.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
            color: color,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled
                      ? copy.text(
                          '2FA is enabled',
                          'Weryfikacja 2FA jest włączona',
                        )
                      : copy.text(
                          '2FA is not enabled',
                          'Weryfikacja 2FA nie jest włączona',
                        ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  enabled
                      ? copy.text(
                          'A code is required after your password or social sign-in.',
                          'Po podaniu hasła lub zalogowaniu przez usługę zewnętrzną wymagany jest kod.',
                        )
                      : copy.text(
                          'Add an authenticator to protect future sign-ins.',
                          'Dodaj aplikację uwierzytelniającą, aby chronić kolejne logowania.',
                        ),
                  style: TextStyle(color: palette.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorCard extends StatelessWidget {
  const _FactorCard({
    required this.factor,
    required this.busy,
    required this.onRemove,
  });
  final TotpFactorSummary factor;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.phonelink_lock_rounded, color: colors.primary),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor.displayName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  copy.text(
                    'Added ${_formatDate(factor.enrolledAt)}',
                    'Dodano ${_formatDate(factor.enrolledAt)}',
                  ),
                  style: TextStyle(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: copy.text(
              'Remove authenticator',
              'Usuń aplikację uwierzytelniającą',
            ),
            onPressed: busy ? null : onRemove,
            icon: Icon(Icons.delete_outline_rounded, color: colors.error),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentCard extends StatelessWidget {
  const _EnrollmentCard({
    required this.draft,
    required this.codeController,
    required this.busy,
    required this.canOpenAuthenticatorApp,
    required this.onOpenAuthenticator,
    required this.onCopySecret,
    required this.onComplete,
    required this.onCancel,
  });
  final TotpEnrollmentDraft draft;
  final TextEditingController codeController;
  final bool busy;
  final bool canOpenAuthenticatorApp;
  final VoidCallback onOpenAuthenticator;
  final VoidCallback onCopySecret;
  final VoidCallback onComplete;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.text(
              'Connect your authenticator',
              'Połącz aplikację uwierzytelniającą',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy.text(
              'Scan this QR code with your authenticator app. You can also enter the setup key manually. Then enter the current 6-digit code.',
              'Zeskanuj kod QR w aplikacji uwierzytelniającej. Możesz też ręcznie wpisać klucz konfiguracji. Następnie wprowadź aktualny 6-cyfrowy kod.',
            ),
            style: TextStyle(color: palette.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Center(
            child: Semantics(
              label: copy.text(
                'Authenticator setup QR code',
                'Kod QR do konfiguracji aplikacji uwierzytelniającej',
              ),
              image: true,
              child: ExcludeSemantics(
                child: Container(
                  width: 196,
                  height: 196,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: draft.qrCodeUrl,
                    color: Colors.black,
                    backgroundColor: Colors.white,
                    errorBuilder: (context, error) => const Center(
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.black,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            copy.text('Manual setup key', 'Klucz do ręcznej konfiguracji'),
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: copy.text(
              'Manual authenticator setup key',
              'Klucz do ręcznej konfiguracji aplikacji uwierzytelniającej',
            ),
            child: SelectableText(
              draft.secretKey,
              style: TextStyle(
                color: palette.textPrimary,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onCopySecret,
            icon: const Icon(Icons.copy_rounded),
            label: Text(
              copy.text('Copy setup secret', 'Skopiuj klucz konfiguracji'),
            ),
          ),
          if (canOpenAuthenticatorApp) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : onOpenAuthenticator,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                copy.text(
                  'Open authenticator app',
                  'Otwórz aplikację uwierzytelniającą',
                ),
              ),
            ),
          ],
          if (draft.expiresAt != null) ...[
            const SizedBox(height: 12),
            Text(
              copy.text(
                'Finish setup before ${_formatDeadline(draft.expiresAt!)}.',
                'Dokończ konfigurację przed ${_formatDeadline(draft.expiresAt!)}.',
              ),
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: codeController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(
              labelText: copy.text('6-digit code', 'Kod 6-cyfrowy'),
            ),
            onSubmitted: (_) => onComplete(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : onComplete,
            child: Text(
              copy.text(
                'Enable two-factor authentication',
                'Włącz uwierzytelnianie dwuskładnikowe',
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: Text(copy.text('Cancel setup', 'Anuluj konfigurację')),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

String _formatDeadline(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
