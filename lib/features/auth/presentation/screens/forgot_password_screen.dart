import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/check_inbox_sheet.dart';
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
    final copy = AppLocalizations.of(context);
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return copy.text('Enter your email address.', 'Wpisz swój adres e-mail.');
    }
    final emailPattern = RegExp(
      r'^[a-zA-Z0-9.!#$%&'
      r"*+/=?^_`{|}~-]+@"
      r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
      r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
    );
    if (!emailPattern.hasMatch(email)) {
      return copy.text(
        'Enter a valid email address.',
        'Wpisz prawidłowy adres e-mail.',
      );
    }
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
        _showError(
          localizedAuthError(context, error, authService: _authService),
        );
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
    // Slim (phase 7): the same atoms as sign-in — the calm AuthBackdrop, the
    // 52 px auth field, the solid primary button and an authLink link — with
    // the form lying on the backdrop instead of inside a bordered card.
    final content = Scaffold(
      backgroundColor: AppImmersiveColors.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
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
                        color: AppImmersiveColors.textPrimary,
                        iconSize: 24,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: AuthStatusMark(icon: Icons.lock_reset_rounded),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      copy.resetPassword,
                      textAlign: TextAlign.center,
                      style: AuthTypography.heading,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      copy.resetPasswordIntro,
                      textAlign: TextAlign.center,
                      style: AuthTypography.subtitle,
                    ),
                    const SizedBox(height: 28),
                    Form(
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
                            style: authInputTextStyle,
                            cursorColor: AppImmersiveColors.authFocus,
                            decoration: authInputDecoration(
                              label: copy.emailAddress,
                              prefixIcon: Icons.mail_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthPrimaryButton(
                            key: const Key('send-reset-link'),
                            label: copy.sendResetLink,
                            loading: _isSending,
                            onPressed: _isSending ? null : _sendResetLink,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isSending
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text(
                          copy.backToLogin,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppImmersiveColors.authLink,
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
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}
