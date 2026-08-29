import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
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
      setState(() => _successMessage = 'Verification email sent.');
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _authService.getErrorMessage(error));
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
    final email = _user?.email ?? 'your email';

    final content = Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.3,
                  colors: [
                    Color(0xFF1B063D),
                    Color(0xFF0D0618),
                    Color(0xFF07030E),
                  ],
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          const AnimatedWavesBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFA02BFF,
                          ).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFF5A2A75)),
                        ),
                        child: Icon(
                          _verified
                              ? Icons.check_circle_rounded
                              : Icons.mark_email_unread_rounded,
                          color: const Color(0xFFD28AFF),
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _verified ? 'Email verified' : 'Verify your email',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _verified
                            ? 'You\'re all set. Taking you onward…'
                            : 'We sent a confirmation link to $email. '
                                  'Open it to verify your account.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8B1C8),
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      if (!_verified) ...[
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          _MessageBanner(text: _errorMessage!, isError: true),
                        ],
                        if (_successMessage != null &&
                            _errorMessage == null) ...[
                          const SizedBox(height: 20),
                          _MessageBanner(
                            text: _successMessage!,
                            isError: false,
                          ),
                        ],
                        const SizedBox(height: 28),
                        _PrimaryButton(
                          label: _sending
                              ? 'Sending…'
                              : _cooldownSeconds > 0
                              ? 'Resend email (${_cooldownSeconds}s)'
                              : 'Resend email',
                          isLoading: _sending,
                          onPressed: (_sending || _cooldownSeconds > 0)
                              ? null
                              : _resend,
                        ),
                        const SizedBox(height: 12),
                        _SecondaryButton(
                          label: _checking
                              ? 'Checking…'
                              : 'I have verified my email',
                          isLoading: _checking,
                          onPressed: _checking ? null : () => _checkNow(),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _skip,
                          child: const Text(
                            'Skip for now',
                            style: TextStyle(
                              color: Color(0xFF9189A6),
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
        ],
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF481C30) : const Color(0xFF203D2C),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isError ? const Color(0xFFFF9EB6) : const Color(0xFF7EE8A6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

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
      opacity: isEnabled ? 1 : 0.6,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A00FF), Color(0xFFA12BFF), Color(0xFFC026FF)],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

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
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF3A3151)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
