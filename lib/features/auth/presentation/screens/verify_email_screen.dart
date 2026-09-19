import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

const _kResendCooldownSeconds = 60;
const _kAutoCheckInterval = Duration(seconds: 5);

/// Shown right after registration (register_screen.dart) — a soft gate,
/// same policy as the website's non-blocking VerifyEmailBanner: "Skip for
/// now" always works, this screen just makes sure a fresh account is
/// actually offered a chance to verify instead of the app silently saying
/// nothing about it (which is what happened before this screen existed).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService();

  Timer? _cooldownTimer;
  Timer? _autoCheckTimer;

  int _cooldownSeconds = 0;
  bool _sending = false;
  bool _checking = false;
  bool _verified = false;
  String? _errorMessage;
  String? _successMessage;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _checkNow(showSpinner: false);
    _autoCheckTimer = Timer.periodic(_kAutoCheckInterval, (_) {
      if (!_verified) _checkNow(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNow({bool showSpinner = true}) async {
    if (_checking) return;
    if (showSpinner && mounted) setState(() => _checking = true);

    try {
      final verified = await _authService.reloadCurrentUser();
      if (!mounted) return;
      if (verified) {
        _autoCheckTimer?.cancel();
        setState(() => _verified = true);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      if (mounted && showSpinner) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_sending || _cooldownSeconds > 0) return;
    setState(() {
      _sending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.resendVerificationEmail();
      if (!mounted) return;
      setState(
        () => _successMessage = AppLocalizations.of(context).text(
          'Verification email sent.',
          'Wiadomość weryfikacyjna została wysłana.',
        ),
      );
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = localizedAuthError(
          context,
          error,
          authService: _authService,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = _kResendCooldownSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds <= 1) {
          _cooldownSeconds = 0;
          timer.cancel();
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  void _skip() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final email =
        _user?.email ?? copy.text('your email address', 'Twój adres e-mail');
    final verificationIntro = copy
        .text(
          'We sent a confirmation link to {email}. Open it to verify your account.',
          'Wysłaliśmy link potwierdzający na adres {email}. Otwórz go, aby zweryfikować konto.',
        )
        .replaceAll('{email}', email);
    final resendLabel = _sending
        ? copy.text('Sending…', 'Wysyłanie…')
        : _cooldownSeconds > 0
        ? copy
              .text(
                'Resend email ({seconds}s)',
                'Wyślij ponownie ({seconds} s)',
              )
              .replaceAll('{seconds}', '$_cooldownSeconds')
        : copy.text('Resend email', 'Wyślij wiadomość ponownie');

    // Slim (phase 7): the calm AuthBackdrop instead of the three-layer
    // gradient and animated waves, and the same medallion, heading, button
    // and link atoms as the rest of the sign-in chain.
    final content = Scaffold(
      backgroundColor: AppImmersiveColors.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AuthStatusMark(
                      icon: _verified
                          ? Icons.check_circle_rounded
                          : Icons.mark_email_unread_rounded,
                      color: _verified
                          ? AppColors.success
                          : AppImmersiveColors.authLink,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _verified
                          ? copy.text(
                              'Email verified',
                              'Adres e-mail zweryfikowany',
                            )
                          : copy.text(
                              'Verify your email',
                              'Zweryfikuj adres e-mail',
                            ),
                      textAlign: TextAlign.center,
                      style: AuthTypography.heading,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _verified
                          ? copy.text(
                              'You\'re all set. Taking you onward…',
                              'Wszystko gotowe. Przechodzimy dalej…',
                            )
                          : verificationIntro,
                      textAlign: TextAlign.center,
                      style: AuthTypography.subtitle,
                    ),
                    if (!_verified) ...[
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 20),
                        _MessageBanner(text: _errorMessage!, isError: true),
                      ],
                      if (_successMessage != null && _errorMessage == null) ...[
                        const SizedBox(height: 20),
                        _MessageBanner(text: _successMessage!, isError: false),
                      ],
                      const SizedBox(height: 28),
                      _PrimaryButton(
                        label: resendLabel,
                        isLoading: _sending,
                        onPressed: (_sending || _cooldownSeconds > 0)
                            ? null
                            : _resend,
                      ),
                      const SizedBox(height: 12),
                      _SecondaryButton(
                        label: _checking
                            ? copy.text('Checking…', 'Sprawdzanie…')
                            : copy.text(
                                'I have verified my email',
                                'Adres e-mail jest już zweryfikowany',
                              ),
                        isLoading: _checking,
                        onPressed: _checking ? null : () => _checkNow(),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: AppImmersiveColors.textSecondary,
                        ),
                        child: Text(
                          copy.text('Skip for now', 'Pomiń na razie'),
                          style: const TextStyle(
                            color: AppImmersiveColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

/// Inline result of a resend: `AppColors.error` / `AppColors.success` copy on
/// a faint tint of the same status over the immersive `surface` (≥ 4.5:1 for
/// both), replacing four one-off hex literals.
class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final status = isError ? AppColors.error : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          status.withValues(alpha: .14),
          AppImmersiveColors.surface,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: status,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Resend action: the shared solid-primary [AuthPrimaryButton]; the cooldown
/// keeps its dimmed look so the countdown still reads as "not yet".
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isEnabled || isLoading ? 1 : 0.6,
      child: SizedBox(
        width: double.infinity,
        child: AuthPrimaryButton(
          label: label,
          loading: isLoading,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Secondary action: a 52 px outline with the auth control outline
/// (`authBorderStrong`, ≥ 3:1) and the 2 px `authFocus` keyboard boundary.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: authFieldHeight),
        child: OutlinedButton(
          onPressed: onPressed,
          style:
              OutlinedButton.styleFrom(
                foregroundColor: AppImmersiveColors.textPrimary,
                disabledForegroundColor: AppImmersiveColors.textSecondary,
                backgroundColor: AppImmersiveColors.surface,
                disabledBackgroundColor: AppImmersiveColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const BorderSide(
                          color: AppImmersiveColors.authFocus,
                          width: 2,
                        )
                      : const BorderSide(
                          color: AppImmersiveColors.authBorderStrong,
                        ),
                ),
              ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppImmersiveColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
