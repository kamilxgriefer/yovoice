import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/widgets/check_inbox_sheet.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    this.initialEmail = '',
    this.authService,
    super.key,
  });

  final String initialEmail;
  final AuthService? authService;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final AuthService _authService;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail.trim());
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    final emailPattern = RegExp(
      r'^[a-zA-Z0-9.!#$%&'
      r"*+/=?^_`{|}~-]+@"
      r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
      r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
    );
    if (!emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  Future<void> _sendResetLink() async {
    if (_isSending) return;
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() != true) return;

    final email = _emailController.text.trim();
    setState(() => _isSending = true);

    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      await _showConfirmation(email);
    } catch (error) {
      if (!mounted) return;
      // Keep account existence private. An unknown address receives the same
      // confirmation state as an address with a YO Voice account.
      if (error is FirebaseAuthException && error.code == 'user-not-found') {
        await _showConfirmation(email);
      } else {
        _showError(_authService.getErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showConfirmation(String email) async {
    final backToLogin = await showCheckInboxSheet(
      context,
      email: email,
      authService: _authService,
    );
    if (backToLogin == true && mounted) Navigator.of(context).pop();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
                  stops: [0, .52, 1],
                ),
              ),
            ),
          ),
          const AnimatedWavesBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: copy.backToLogin,
                          onPressed: _isSending
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                          iconSize: 28,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      Center(
                        child: Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(
                              0xFF7B2FF7,
                            ).withValues(alpha: .14),
                            border: Border.all(
                              color: const Color(
                                0xFFB15CFF,
                              ).withValues(alpha: .5),
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_reset_rounded,
                            color: Color(0xFFD7A9FF),
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        copy.resetPassword,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        copy.resetPasswordIntro,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8B1C8),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC151021),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFF3A3151)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  key: const Key('forgot-password-email'),
                                  controller: _emailController,
                                  autofocus: widget.initialEmail.trim().isEmpty,
                                  enabled: !_isSending,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  onFieldSubmitted: (_) => _sendResetLink(),
                                  validator: _validateEmail,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: copy.emailAddress,
                                    prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF171126),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 56,
                                  child: FilledButton(
                                    key: const Key('send-reset-link'),
                                    onPressed: _isSending
                                        ? null
                                        : _sendResetLink,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF8E24F5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                    ),
                                    child: _isSending
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            copy.sendResetLink,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: .6,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          onPressed: _isSending
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 19),
                          label: Text(copy.backToLogin),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFD7A9FF),
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ),
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
