import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/auth_social_button.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
import 'package:yovoice/features/auth/presentation/screens/register_screen.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isAuthenticationLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email address and password.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signIn(email: email, password: password);
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _handleAuthenticationError(error);
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
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _handleAuthenticationError(error);
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
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _handleAuthenticationError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isAppleLoading = false;
        });
      }
    }
  }

  void _openForgotPasswordScreen() {
    if (_isAuthenticationLoading) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/forgot-password'),
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  void _openRegisterScreen() {
    if (_isAuthenticationLoading) {
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));
  }

  Future<void> _handleAuthenticationError(Object error) async {
    if (error is FirebaseAuthMultiFactorException) {
      final challenge = _authService.createTotpSignInChallenge(error);
      if (challenge.factors.isEmpty) {
        _showMessage(
          'This account requires a second factor that this app cannot verify. Contact support.',
        );
        return;
      }
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => TotpChallengeScreen(challenge: challenge),
        ),
      );
      return;
    }
    _showMessage(_authService.getErrorMessage(error));
  }

  void _showMessage(String message) {
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
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          const AnimatedWavesBackground(),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/yo_voice_logo_reference.png',
                            width: 305,
                            height: 305,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        const SizedBox(height: 0),
                        const Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 11,
                          runSpacing: 6,
                          children: [
                            Text(
                              'YO',
                              style: TextStyle(
                                color: Color(0xFFA52CFF),
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                letterSpacing: 0.4,
                              ),
                            ),
                            Text(
                              'VOICE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w400,
                                height: 1,
                                letterSpacing: 2.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'SPEAK. CONNECT. BE YOU.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFB8B1C8),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            letterSpacing: 3.7,
                          ),
                        ),
                        const SizedBox(height: 42),
                        _LoginAuthField(
                          controller: _emailController,
                          hintText: copy.email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.email,
                            AutofillHints.username,
                          ],
                          prefixIconPath: 'assets/icons/icon_email.svg',
                        ),
                        const SizedBox(height: 16),
                        _LoginAuthField(
                          controller: _passwordController,
                          hintText: copy.password,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          prefixIconPath: 'assets/icons/icon_lock.svg',
                          suffixIconPath: _obscurePassword
                              ? 'assets/icons/icon_eye.svg'
                              : 'assets/icons/icon_eye_off.svg',
                          onSuffixPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          onSubmitted: (_) {
                            if (!_isAuthenticationLoading) {
                              _login();
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        _LoginPrimaryButton(
                          label: copy.logIn,
                          isLoading: _isLoading,
                          onPressed: _isAuthenticationLoading ? null : _login,
                        ),
                        const SizedBox(height: 28),
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
                              ? 'Continue with Apple — Coming soon'
                              : _appleSignInAvailability ==
                                    AppleSignInAvailability
                                        .temporarilyUnavailable
                              ? 'Continue with Apple — Try again'
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
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                '${copy.noAccount} ',
                                style: const TextStyle(
                                  color: Color(0xFFB8B1C8),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _isAuthenticationLoading
                                  ? null
                                  : _openRegisterScreen,
                              style: ButtonStyle(
                                // Was shrunk to the bare text glyphs
                                // (EdgeInsets.zero + Size.zero + shrinkWrap),
                                // well under Apple/Material's 44/48pt minimum
                                // touch target -- genuinely hard to hit
                                // reliably. Let TextButton's own comfortable
                                // default sizing apply instead, same as
                                // "Forgot password?" right below it.
                                mouseCursor:
                                    WidgetStateProperty.resolveWith<
                                      MouseCursor
                                    >((states) {
                                      if (states.contains(
                                        WidgetState.disabled,
                                      )) {
                                        return SystemMouseCursors.basic;
                                      }

                                      return SystemMouseCursors.click;
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
                                foregroundColor:
                                    WidgetStateProperty.resolveWith<Color>((
                                      states,
                                    ) {
                                      if (states.contains(
                                        WidgetState.disabled,
                                      )) {
                                        return const Color(0xFF6E617A);
                                      }

                                      if (states.contains(
                                        WidgetState.hovered,
                                      )) {
                                        return const Color(0xFFC05CFF);
                                      }

                                      return const Color(0xFFA02BFF);
                                    }),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              child: Text(
                                copy.signUp,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _isAuthenticationLoading
                                ? null
                                : _openForgotPasswordScreen,
                            style: ButtonStyle(
                              mouseCursor:
                                  WidgetStateProperty.resolveWith<MouseCursor>((
                                    states,
                                  ) {
                                    if (states.contains(WidgetState.disabled)) {
                                      return SystemMouseCursors.basic;
                                    }

                                    return SystemMouseCursors.click;
                                  }),
                              overlayColor:
                                  WidgetStateProperty.resolveWith<Color?>((
                                    states,
                                  ) {
                                    if (states.contains(WidgetState.hovered)) {
                                      return const Color(0x22A02BFF);
                                    }

                                    if (states.contains(WidgetState.pressed)) {
                                      return const Color(0x33A02BFF);
                                    }

                                    return Colors.transparent;
                                  }),
                            ),
                            child: Text(
                              copy.forgotPassword,
                              style: const TextStyle(
                                color: Color(0xFFA02BFF),
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
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

class _LoginPrimaryButton extends StatelessWidget {
  const _LoginPrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A00FF), Color(0xFFA12BFF), Color(0xFFC026FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x667B24D1),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: Colors.transparent,
          backgroundColor: Colors.transparent,
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
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
      ),
    );
  }
}

class _LoginAuthField extends StatelessWidget {
  const _LoginAuthField({
    required this.controller,
    required this.hintText,
    required this.prefixIconPath,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIconPath,
    this.onSuffixPressed,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final String prefixIconPath;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final String? suffixIconPath;
  final VoidCallback? onSuffixPressed;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscureText,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9189A6),
          fontSize: 17,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(17),
          child: SvgPicture.asset(prefixIconPath, width: 25, height: 25),
        ),
        suffixIcon: suffixIconPath == null
            ? null
            : IconButton(
                onPressed: onSuffixPressed,
                icon: SvgPicture.asset(suffixIconPath!, width: 26, height: 26),
              ),
        filled: true,
        fillColor: const Color(0xDD171126),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 21,
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
      ),
    );
  }
}
