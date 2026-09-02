import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

const int _kResendCooldownSeconds = 60;

/// Shown after requesting a password reset from the login screen.
///
/// Replaces the old fire-and-forget SnackBar with a real state the user
/// can act on: neutral confirmation copy (deliberately not revealing
/// whether the address has an account), a resend button with a cooldown,
/// and a way back to login. The emailed link opens the website's branded
/// /auth/action flow — see docs/email-templates/README.md.
Future<bool?> showCheckInboxSheet(
  BuildContext context, {
  required String email,
  AuthService? authService,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 480,
    ),
    builder: (_) => _CheckInboxSheet(email: email, authService: authService),
  );
}

class _CheckInboxSheet extends StatefulWidget {
  const _CheckInboxSheet({required this.email, this.authService});

  final String email;
  final AuthService? authService;

  @override
  State<_CheckInboxSheet> createState() => _CheckInboxSheetState();
}

class _CheckInboxSheetState extends State<_CheckInboxSheet> {
  late final AuthService _authService;

  Timer? _cooldownTimer;
  int _cooldownSeconds = _kResendCooldownSeconds;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    // The first email was just sent by the caller — start cooling down
    // immediately so "Resend" can't double-fire within seconds.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
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
          timer.cancel();
          _cooldownSeconds = 0;
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  Future<void> _resend() async {
    if (_sending || _cooldownSeconds > 0) return;
    setState(() => _sending = true);
    try {
      await _authService.sendPasswordResetEmail(widget.email);
    } on FirebaseAuthException catch (error) {
      // user-not-found deliberately falls through to the same success
      // path: surfacing it would tell whoever is typing addresses into
      // the form which ones have accounts.
      if (error.code != 'user-not-found' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizedAuthError(context, error, authService: _authService),
            ),
          ),
        );
        setState(() => _sending = false);
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text(
                'Could not send the email. Try again.',
                'Nie udało się wysłać wiadomości. Spróbuj ponownie.',
              ),
            ),
          ),
        );
        setState(() => _sending = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final confirmation = copy
        .text(
          'If an account exists for {email}, we\'ve sent instructions to reset your password.',
          'Jeśli istnieje konto przypisane do adresu {email}, wysłaliśmy instrukcję resetowania hasła.',
        )
        .replaceAll('{email}', widget.email);

    return Material(
      color: AppImmersiveColors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text(
                  'check your inbox',
                  'sprawdź skrzynkę odbiorczą',
                ),
                surfaceColor: AppImmersiveColors.surface,
              ),
              const SizedBox(height: 6),
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: .14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: .4),
                  ),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.secondary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                copy.text('Check your inbox', 'Sprawdź skrzynkę odbiorczą'),
                style: const TextStyle(
                  color: AppImmersiveColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                confirmation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppImmersiveColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                copy.text("Didn't receive it?", 'Wiadomość nie dotarła?'),
                style: const TextStyle(
                  color: AppImmersiveColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _sending || _cooldownSeconds > 0 ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppImmersiveColors.textPrimary,
                    side: const BorderSide(color: AppImmersiveColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _sending
                        ? copy.text('Sending…', 'Wysyłanie…')
                        : _cooldownSeconds > 0
                        ? copy
                              .text(
                                'Resend email ({seconds}s)',
                                'Wyślij ponownie ({seconds} s)',
                              )
                              .replaceAll('{seconds}', '$_cooldownSeconds')
                        : copy.text(
                            'Resend email',
                            'Wyślij wiadomość ponownie',
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    copy.backToLogin,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppImmersiveColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
