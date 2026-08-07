import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
import 'package:yovoice/features/auth/presentation/screens/register_screen.dart';

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
  bool _isResettingPassword = false;

  bool get _isAuthenticationLoading => _isLoading || _isGoogleLoading;

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
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(_authService.getErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_isResettingPassword || _isAuthenticationLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('Enter your email address.');
      return;
    }

    setState(() {
      _isResettingPassword = true;
    });

    try {
      await _authService.sendPasswordResetEmail(email);

      if (!mounted) {
        return;
      }

      _showMessage('Password reset email has been sent.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(_authService.getErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isResettingPassword = false;
        });
      }
    }
  }

  void _openRegisterScreen() {
    if (_isAuthenticationLoading) {
      return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));
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
    return Scaffold(
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
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                            SizedBox(width: 11),
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
                          hintText: 'Email',
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
                          hintText: 'Password',
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
                          label: 'LOG IN',
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
                        _LoginSocialButton(
                          label: 'Continue with Google',
                          svgIconPath: 'assets/icons/icon_google_g.svg',
                          isLoading: _isGoogleLoading,
                          onPressed: _isAuthenticationLoading
                              ? null
                              : _signInWithGoogle,
                        ),
                        const SizedBox(height: 14),
                        _LoginSocialButton(
                          label: 'Continue with Apple',
                          materialIcon: Icons.apple,
                          iconSize: 34,
                          onPressed: _isAuthenticationLoading
                              ? null
                              : () {
                                  _showMessage(
                                    'Apple Sign-In will be added in the next stage.',
                                  );
                                },
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Flexible(
                              child: Text(
                                "Don't have an account? ",
                                style: TextStyle(
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
                              child: const Text(
                                'Sign up',
                                style: TextStyle(
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
                            onPressed:
                                _isResettingPassword || _isAuthenticationLoading
                                ? null
                                : _resetPassword,
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
                            child: _isResettingPassword
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFA02BFF),
                                    ),
                                  )
                                : const Text(
                                    'Forgot password?',
                                    style: TextStyle(
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

class _LoginSocialButton extends StatelessWidget {
  const _LoginSocialButton({
    required this.label,
    required this.onPressed,
    this.svgIconPath,
    this.materialIcon,
    this.iconSize = 30,
    this.isLoading = false,
  }) : assert(
         svgIconPath != null || materialIcon != null,
         'An SVG icon path or Material icon must be provided.',
       );

  final String label;
  final VoidCallback? onPressed;
  final String? svgIconPath;
  final IconData? materialIcon;
  final double iconSize;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0x660D0618),
          disabledBackgroundColor: const Color(0x440D0618),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF9189A6),
          side: BorderSide(
            color: onPressed == null
                ? const Color(0xFF46305F)
                : const Color(0xFF6E1FBD),
            width: 1.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
            : Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: svgIconPath != null
                          ? SvgPicture.asset(
                              svgIconPath!,
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                            )
                          : Icon(
                              materialIcon,
                              size: iconSize,
                              color: onPressed == null
                                  ? const Color(0xFF9189A6)
                                  : Colors.white,
                            ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: onPressed == null
                            ? const Color(0xFF9189A6)
                            : Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
      ),
    );
  }
}
