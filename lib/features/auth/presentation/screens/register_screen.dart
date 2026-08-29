import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/auth_social_button.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, @visibleForTesting this.authService});

  final AuthService? authService;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  AppleSignInAvailability? _appleSignInAvailability;

  bool get _isAuthenticationLoading =>
      _isLoading || _isGoogleLoading || _isAppleLoading;

  @override
  void initState() {
    super.initState();
    _loadAppleSignInAvailability();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isAuthenticationLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
      );

      if (!mounted) return;

      TextInput.finishAutofillContext();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(_authService.getErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isAuthenticationLoading) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      await _authService.signInWithGoogle();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted && await _handleAuthenticationError(error)) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _loadAppleSignInAvailability() async {
    final availability = await _authService.getAppleSignInAvailability();
    if (!mounted) {
      return;
    }

    setState(() {
      _appleSignInAvailability = availability;
    });
  }

  Future<void> _signInWithApple() async {
    if (_isAuthenticationLoading ||
        _appleSignInAvailability == null ||
        _appleSignInAvailability == AppleSignInAvailability.notConfigured) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isAppleLoading = true;
    });

    try {
      await _authService.signInWithApple();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted && await _handleAuthenticationError(error)) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAppleLoading = false;
        });
      }
    }
  }

  /// Returns true only when an MFA challenge completed the social sign-in.
  Future<bool> _handleAuthenticationError(Object error) async {
    if (error is FirebaseAuthMultiFactorException) {
      final challenge = _authService.createTotpSignInChallenge(error);
      if (challenge.factors.isEmpty) {
        _showMessage(
          'This account requires a second factor that this app cannot verify. Contact support.',
        );
        return false;
      }

      return await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => TotpChallengeScreen(challenge: challenge),
            ),
          ) ??
          false;
    }

    _showMessage(_authService.getErrorMessage(error));
    return false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';

    if (username.isEmpty) {
      return 'Enter a username.';
    }

    if (username.length < 3) {
      return 'Username must contain at least 3 characters.';
    }

    if (username.length > 24) {
      return 'Username cannot exceed 24 characters.';
    }

    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) {
      return 'Use only letters, numbers, dots, and underscores.';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Enter your email address.';
    }

    final emailPattern = RegExp(
      r'^[a-zA-Z0-9.!#$%&'
      '*+/=?^_`{|}~-]+@'
      r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
      r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
    );

    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Enter a password.';
    }

    if (password.length < 8) {
      return 'Password must contain at least 8 characters.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Add at least one uppercase letter.';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Add at least one lowercase letter.';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Add at least one number.';
    }

    return null;
  }

  String? _validatePasswordConfirmation(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Confirm your password.';
    }

    if (value != _passwordController.text) {
      return 'Passwords do not match.';
    }

    return null;
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
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          const AnimatedWavesBackground(),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x11000000),
                    Color(0x22000000),
                    Color(0x5507030E),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: _isAuthenticationLoading
                                  ? null
                                  : _goBack,
                              icon: SvgPicture.asset(
                                'assets/icons/icon_back.svg',
                                width: 34,
                                height: 34,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Center(
                            child: Image.asset(
                              'assets/images/yo_voice_logo_reference.png',
                              width: 150,
                              height: 150,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            copy.createAccount,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            copy.text(
                              'Join YO Voice and start connecting.',
                              'Dołącz do YO Voice i zacznij poznawać ludzi.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFB8B1C8),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 28),
                          AuthSocialButton(
                            label: copy.continueWithGoogle,
                            svgIconPath: 'assets/icons/icon_google_g.svg',
                            isLoading: _isGoogleLoading,
                            onPressed: _isAuthenticationLoading
                                ? null
                                : _signInWithGoogle,
                          ),
                          const SizedBox(height: 14),
                          AuthSocialButton(
                            label:
                                _appleSignInAvailability ==
                                    AppleSignInAvailability.notConfigured
                                ? copy.text(
                                    'Continue with Apple — Coming soon',
                                    'Kontynuuj z Apple — Wkrótce',
                                  )
                                : _appleSignInAvailability ==
                                      AppleSignInAvailability
                                          .temporarilyUnavailable
                                ? copy.text(
                                    'Continue with Apple — Try again',
                                    'Kontynuuj z Apple — Spróbuj ponownie',
                                  )
                                : copy.continueWithApple,
                            materialIcon: Icons.apple,
                            iconSize: 34,
                            isLoading:
                                _isAppleLoading ||
                                _appleSignInAvailability == null,
                            onPressed:
                                _isAuthenticationLoading ||
                                    _appleSignInAvailability == null ||
                                    _appleSignInAvailability ==
                                        AppleSignInAvailability.notConfigured
                                ? null
                                : _signInWithApple,
                          ),
                          const SizedBox(height: 24),
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Color(0xFF4C376F),
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: Color(0xFF9189A6),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Color(0xFF4C376F),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _RegisterField(
                            controller: _usernameController,
                            hintText: copy.username,
                            prefixIcon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newUsername],
                            validator: _validateUsername,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9_.]'),
                              ),
                              LengthLimitingTextInputFormatter(24),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _emailController,
                            hintText: copy.email,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _passwordController,
                            hintText: copy.password,
                            prefixIcon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            suffixIcon: _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            onSuffixPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 16),
                          _RegisterField(
                            controller: _confirmPasswordController,
                            hintText: copy.confirmPassword,
                            prefixIcon: Icons.lock_reset_outlined,
                            obscureText: _obscureConfirmation,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            suffixIcon: _obscureConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            onSuffixPressed: () {
                              setState(() {
                                _obscureConfirmation = !_obscureConfirmation;
                              });
                            },
                            onFieldSubmitted: (_) {
                              if (!_isLoading) {
                                _register();
                              }
                            },
                            validator: _validatePasswordConfirmation,
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              copy.text(
                                'Use at least 8 characters, including an uppercase letter, a lowercase letter, and a number.',
                                'Użyj co najmniej 8 znaków, w tym wielkiej i małej litery oraz cyfry.',
                              ),
                              style: const TextStyle(
                                color: Color(0xFF9189A6),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          _RegisterPrimaryButton(
                            label: copy.createAccount,
                            isLoading: _isLoading,
                            onPressed: _isAuthenticationLoading
                                ? null
                                : _register,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  '${copy.alreadyHaveAccount} ',
                                  style: const TextStyle(
                                    color: Color(0xFFB8B1C8),
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _isAuthenticationLoading
                                    ? null
                                    : _goBack,
                                style: ButtonStyle(
                                  // Was shrunk to the bare text glyphs
                                  // (EdgeInsets.zero + Size.zero +
                                  // shrinkWrap), well under Apple/Material's
                                  // 44/48pt minimum touch target -- let
                                  // TextButton's own comfortable default
                                  // sizing apply instead.
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith<Color?>((
                                        states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.disabled,
                                        )) {
                                          return const Color(0xFF665D76);
                                        }

                                        if (states.contains(
                                          WidgetState.hovered,
                                        )) {
                                          return const Color(0xFFC05CFF);
                                        }

                                        return const Color(0xFFA02BFF);
                                      }),
                                  overlayColor:
                                      WidgetStateProperty.resolveWith<Color?>((
                                        states,
                                      ) {
                                        if (states.contains(
                                          WidgetState.hovered,
                                        )) {
                                          return const Color(0x22A02BFF);
                                        }

                                        if (states.contains(
                                          WidgetState.pressed,
                                        )) {
                                          return const Color(0x33A02BFF);
                                        }

                                        return Colors.transparent;
                                      }),
                                ),
                                child: Text(
                                  copy.text('Log in', 'Zaloguj się'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
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

class _RegisterField extends StatelessWidget {
  const _RegisterField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIcon,
    this.onSuffixPressed,
    this.onFieldSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final FormFieldValidator<String> validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixPressed;
  final ValueChanged<String>? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      inputFormatters: inputFormatters,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: Colors.white, fontSize: 17),
      cursorColor: const Color(0xFFA02BFF),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF9189A6), fontSize: 17),
        prefixIcon: Icon(prefixIcon, color: const Color(0xFFB8B1C8), size: 26),
        suffixIcon: suffixIcon == null
            ? null
            : IconButton(
                onPressed: onSuffixPressed,
                icon: Icon(
                  suffixIcon,
                  color: const Color(0xFFB8B1C8),
                  size: 26,
                ),
              ),
        filled: true,
        fillColor: const Color(0xDD171126),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 21,
        ),
        errorMaxLines: 2,
        errorStyle: const TextStyle(
          color: Color(0xFFFF7A9C),
          fontSize: 13,
          height: 1.2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF3A3151)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF3A3151)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFA02BFF), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFFF5C87)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFFF5C87), width: 1.8),
        ),
      ),
    );
  }
}

class _RegisterPrimaryButton extends StatelessWidget {
  const _RegisterPrimaryButton({
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
      opacity: isEnabled ? 1 : 0.72,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A00FF), Color(0xFFA12BFF), Color(0xFFC026FF)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isEnabled
              ? const [
                  BoxShadow(
                    color: Color(0x667B24D1),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
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
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
        ),
      ),
    );
  }
}
