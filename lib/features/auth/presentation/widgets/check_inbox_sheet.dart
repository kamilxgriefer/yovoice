import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const int _kResendCooldownSeconds = 60;

/// Shown after requesting a password reset from the login screen.
///
/// Replaces the old fire-and-forget SnackBar with a real state the user
/// can act on: neutral confirmation copy (deliberately not revealing
/// whether the address has an account), a resend button with a cooldown,
/// and a way back to login. The emailed link opens the website's branded
/// /auth/action flow — see docs/email-templates/README.md.
Future<void> showCheckInboxSheet(
  BuildContext context, {
  required String email,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 480,
    ),
    builder: (_) => _CheckInboxSheet(email: email),
  );
}

class _CheckInboxSheet extends StatefulWidget {
  const _CheckInboxSheet({required this.email});

  final String email;

  @override
  State<_CheckInboxSheet> createState() => _CheckInboxSheetState();
}

class _CheckInboxSheetState extends State<_CheckInboxSheet> {
  final AuthService _authService = AuthService();

  Timer? _cooldownTimer;
  int _cooldownSeconds = _kResendCooldownSeconds;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
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
          SnackBar(content: Text(_authService.getErrorMessage(error))),
        );
        setState(() => _sending = false);
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the email. Try again.')),
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
    return Material(
      color: const Color(0xFF120D1A),
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 26),
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7B2FF7).withValues(alpha: .14),
                  border: Border.all(
                    color: const Color(0xFF7B2FF7).withValues(alpha: .4),
                  ),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFFD3A5FF),
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Check your inbox',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If an account exists for ${widget.email}, we\'ve sent '
                'instructions to reset your password.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF9D95AD),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Didn't receive it?",
                style: const TextStyle(color: Color(0xFF9D95AD), fontSize: 13),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _sending || _cooldownSeconds > 0 ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3A3151)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _sending
                        ? 'Sending…'
                        : _cooldownSeconds > 0
                        ? 'Resend email (${_cooldownSeconds}s)'
                        : 'Resend email',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B2FF7),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Back to log in',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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
