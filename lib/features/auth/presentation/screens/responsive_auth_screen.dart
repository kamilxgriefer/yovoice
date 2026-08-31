import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/auth_social_button.dart';
import 'package:yovoice/shared/widgets/backgrounds/animated_waves_background.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

enum AuthMode { login, register }

enum _AuthLayout { compact, medium, wide }

/// One source of truth for the signed-out entry experience.
///
/// The four text controllers deliberately live above every responsive shell:
/// changing the window size or crossing the compact/desktop threshold cannot
/// throw away input. Only the active mode is ever mounted, focusable and
/// exposed to semantics.
class ResponsiveAuthScreen extends StatefulWidget {
  const ResponsiveAuthScreen({
    required this.initialMode,
    super.key,
    this.authService,
    this.popAfterSocialSuccess = false,
    this.popWhenSelectingLogin = false,
    this.replaceWithVerifyEmail = false,
    this.onRegistrationLoadingChanged,
  });

  final AuthMode initialMode;
  final AuthService? authService;
  final bool popAfterSocialSuccess;
  final bool popWhenSelectingLogin;
  final bool replaceWithVerifyEmail;
  final ValueChanged<bool>? onRegistrationLoadingChanged;

  @override
  State<ResponsiveAuthScreen> createState() => _ResponsiveAuthScreenState();
}

class _ResponsiveAuthScreenState extends State<ResponsiveAuthScreen>
    with SingleTickerProviderStateMixin {
  static const _relayDuration = Duration(milliseconds: 520);
  static const _desktopDuration = Duration(milliseconds: 760);
  static const _relaySwapPoint = 247 / 520;
  static const _desktopSwapPoint = 350 / 760;

  final _registerFormKey = GlobalKey<FormState>();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _loginEmailFocus = FocusNode(debugLabel: 'login-email');
  final _loginPasswordFocus = FocusNode(debugLabel: 'login-password');
  final _usernameFocus = FocusNode(debugLabel: 'register-username');
  final _registerEmailFocus = FocusNode(debugLabel: 'register-email');
  final _registerPasswordFocus = FocusNode(debugLabel: 'register-password');
  final _confirmPasswordFocus = FocusNode(debugLabel: 'register-confirm');
  final _loginModeFocus = FocusNode(debugLabel: 'auth-mode-login');
  final _registerModeFocus = FocusNode(debugLabel: 'auth-mode-register');

  late final AuthService _authService = widget.authService ?? AuthService();
  late final AnimationController _modeController;
  late AuthMode _displayedMode = widget.initialMode;
  late AuthMode _sourceMode = widget.initialMode;
  late AuthMode _targetMode = widget.initialMode;

  _AuthLayout? _lastLayout;
  bool _didSwapMode = false;
  bool _isModeAnimating = false;
  bool _isLoginLoading = false;
  bool _isRegisterLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureConfirmation = true;
  AppleSignInAvailability? _appleAvailability;
  Object? _registrationAttempt;
  double _edgeDragDistance = 0;
  bool _trackingBackEdge = false;

  bool get _isAuthenticationLoading =>
      _isLoginLoading ||
      _isRegisterLoading ||
      _isGoogleLoading ||
      _isAppleLoading;

  bool get _interactionLocked => _isAuthenticationLoading || _isModeAnimating;

  double get _swapPoint =>
      _lastLayout == _AuthLayout.wide ? _desktopSwapPoint : _relaySwapPoint;

  double _intervalProgress(double start, double end) {
    return ((_modeController.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  double get _relayTravelProgress => _intervalProgress(80 / 520, 413 / 520);

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  @override
  void initState() {
    super.initState();
    _modeController = AnimationController(vsync: this)
      ..addListener(_handleModeTick)
      ..addStatusListener(_handleModeStatus);
    _loadAppleAvailability();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion && _isModeAnimating) {
      _settleModeTransition();
    }
  }

  @override
  void dispose() {
    _modeController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _usernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _confirmPasswordController.dispose();
    _loginEmailFocus.dispose();
    _loginPasswordFocus.dispose();
    _usernameFocus.dispose();
    _registerEmailFocus.dispose();
    _registerPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _loginModeFocus.dispose();
    _registerModeFocus.dispose();
    super.dispose();
  }

  void _handleModeTick() {
    if (!_isModeAnimating || _didSwapMode) return;
    if (_modeController.value < _swapPoint) return;

    _didSwapMode = true;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _displayedMode = _targetMode);
    _announceMode(_targetMode);
  }

  void _handleModeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_isModeAnimating) return;
    _settleModeTransition();
  }

  void _settleModeTransition() {
    _modeController.stop();
    _modeController.value = 0;
    if (!mounted) return;
    final modeChanged = _displayedMode != _targetMode;
    setState(() {
      _displayedMode = _targetMode;
      _sourceMode = _targetMode;
      _didSwapMode = true;
      _isModeAnimating = false;
    });
    if (modeChanged) _announceMode(_targetMode);
    _focusSelectedModeAfterFrame();
  }

  void _requestMode(AuthMode mode) {
    if (mode == _targetMode || _interactionLocked) return;

    if (widget.popWhenSelectingLogin && mode == AuthMode.login) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(_popOrShowLogin());
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    if (_reduceMotion) {
      setState(() {
        _sourceMode = mode;
        _targetMode = mode;
        _displayedMode = mode;
      });
      _announceMode(mode);
      _focusSelectedModeAfterFrame();
      return;
    }

    setState(() {
      _sourceMode = _displayedMode;
      _targetMode = mode;
      _didSwapMode = false;
      _isModeAnimating = true;
      _modeController.duration = _lastLayout == _AuthLayout.wide
          ? _desktopDuration
          : _relayDuration;
      _modeController.forward(from: 0);
    });
  }

  Future<void> _popOrShowLogin() async {
    final didPop = await Navigator.of(context).maybePop();
    if (didPop || !mounted) return;
    setState(() {
      _sourceMode = AuthMode.login;
      _targetMode = AuthMode.login;
      _displayedMode = AuthMode.login;
      _didSwapMode = true;
      _isModeAnimating = false;
    });
    _announceMode(AuthMode.login);
    _focusSelectedModeAfterFrame();
  }

  void _announceMode(AuthMode mode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      final heading = mode == AuthMode.login
          ? copy.text('Welcome back', 'Witaj ponownie')
          : copy.text('Create your voice', 'Stwórz swój głos');
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          heading,
          Directionality.of(context),
        ),
      );
    });
  }

  void _focusSelectedModeAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isModeAnimating) return;
      final focus = _displayedMode == AuthMode.login
          ? _loginModeFocus
          : _registerModeFocus;
      focus.requestFocus();
    });
  }

  void _returnToLoginFromBack() {
    if (_isModeAnimating) {
      _modeController.stop();
      setState(() {
        _sourceMode = AuthMode.login;
        _targetMode = AuthMode.login;
        _displayedMode = AuthMode.login;
        _didSwapMode = true;
        _isModeAnimating = false;
      });
      _announceMode(AuthMode.login);
      _focusSelectedModeAfterFrame();
      return;
    }
    if (_displayedMode == AuthMode.register) {
      _requestMode(AuthMode.login);
    }
  }

  void _handleBackEdgeStart(DragStartDetails details) {
    final routeIsFirst = ModalRoute.of(context)?.isFirst ?? true;
    _trackingBackEdge =
        routeIsFirst &&
        _displayedMode == AuthMode.register &&
        !_isModeAnimating &&
        details.globalPosition.dx <= 28;
    _edgeDragDistance = 0;
  }

  void _handleBackEdgeUpdate(DragUpdateDetails details) {
    if (!_trackingBackEdge) return;
    _edgeDragDistance = math.max(
      0,
      _edgeDragDistance + (details.primaryDelta ?? 0),
    );
  }

  void _handleBackEdgeEnd(DragEndDetails details) {
    if (!_trackingBackEdge) return;
    final velocity = details.primaryVelocity ?? 0;
    final shouldReturn = _edgeDragDistance >= 56 || velocity >= 320;
    _trackingBackEdge = false;
    _edgeDragDistance = 0;
    if (shouldReturn) _requestMode(AuthMode.login);
  }

  void _recordLayout(_AuthLayout layout) {
    final changed = _lastLayout != null && _lastLayout != layout;
    _lastLayout = layout;
    if (changed && _isModeAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isModeAnimating) _settleModeTransition();
      });
    }
  }

  Future<void> _loadAppleAvailability() async {
    final availability = await _authService.getAppleSignInAvailability();
    if (!mounted) return;
    setState(() => _appleAvailability = availability);
  }

  Future<void> _login() async {
    if (_interactionLocked) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage(
        AppLocalizations.of(context).text(
          'Enter your email address and password.',
          'Wpisz adres e-mail i hasło.',
        ),
      );
      return;
    }

    setState(() => _isLoginLoading = true);
    try {
      await _authService.signIn(email: email, password: password);
      TextInput.finishAutofillContext();
    } catch (error) {
      if (mounted) await _handleAuthenticationError(error);
    } finally {
      if (mounted) setState(() => _isLoginLoading = false);
    }
  }

  Future<void> _register() async {
    if (_interactionLocked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_registerFormKey.currentState?.validate() ?? false)) {
      _focusFirstInvalidRegistrationField();
      return;
    }

    // Firebase publishes the new principal as soon as Auth creates it, while
    // AuthService still has profile/display-name/email work to finish. AuthGate
    // may therefore replace this widget before the await completes. The root
    // Navigator survives that child swap and remains the correct owner of the
    // verification route.
    final navigator = Navigator.of(context);
    final originRoute = ModalRoute.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final attempt = Object();
    _registrationAttempt = attempt;
    setState(() => _isRegisterLoading = true);
    widget.onRegistrationLoadingChanged?.call(true);
    try {
      final credential = await _authService.register(
        email: _registerEmailController.text.trim(),
        password: _registerPasswordController.text,
        username: _usernameController.text.trim(),
      );
      final registeredUid = credential.user?.uid;
      if (_registrationAttempt != attempt ||
          registeredUid == null ||
          _authService.currentUser?.uid != registeredUid ||
          (widget.replaceWithVerifyEmail && originRoute?.isCurrent != true) ||
          !navigator.mounted) {
        return;
      }
      TextInput.finishAutofillContext();
      final verifyRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/verify-email'),
        builder: (_) => const VerifyEmailScreen(),
      );
      if (widget.replaceWithVerifyEmail) {
        navigator.pushReplacement(verifyRoute);
      } else {
        // The signed-out AuthGate must remain the first route. VerifyEmail
        // deliberately returns with popUntil(isFirst), at which point the
        // gate has already observed the newly authenticated user.
        navigator.push(verifyRoute);
      }
    } catch (error) {
      if (_registrationAttempt != attempt ||
          (widget.replaceWithVerifyEmail && originRoute?.isCurrent != true)) {
        return;
      }
      final message = _authService.getErrorMessage(error);
      if (mounted) {
        _showMessage(message);
      } else if (messenger?.mounted ?? false) {
        _showMessageOn(messenger!, message);
      }
    } finally {
      if (_registrationAttempt == attempt) _registrationAttempt = null;
      widget.onRegistrationLoadingChanged?.call(false);
      if (mounted) setState(() => _isRegisterLoading = false);
    }
  }

  void _focusFirstInvalidRegistrationField() {
    final focus = _validateUsername(_usernameController.text) != null
        ? _usernameFocus
        : _validateEmail(_registerEmailController.text) != null
        ? _registerEmailFocus
        : _validatePassword(_registerPasswordController.text) != null
        ? _registerPasswordFocus
        : _confirmPasswordController.text != _registerPasswordController.text ||
              _confirmPasswordController.text.isEmpty
        ? _confirmPasswordFocus
        : null;
    if (focus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_interactionLocked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isGoogleLoading = true);
    try {
      await _authService.signInWithGoogle();
      if (mounted && widget.popAfterSocialSuccess) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      final completedMfa = await _handleAuthenticationError(error);
      if (mounted && completedMfa && widget.popAfterSocialSuccess) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_interactionLocked ||
        _appleAvailability == null ||
        _appleAvailability == AppleSignInAvailability.notConfigured) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isAppleLoading = true);
    try {
      await _authService.signInWithApple();
      if (mounted && widget.popAfterSocialSuccess) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      final completedMfa = await _handleAuthenticationError(error);
      if (mounted && completedMfa && widget.popAfterSocialSuccess) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isAppleLoading = false);
    }
  }

  /// Returns true only when an MFA challenge completed authentication.
  Future<bool> _handleAuthenticationError(Object error) async {
    if (error is FirebaseAuthMultiFactorException) {
      final challenge = _authService.createTotpSignInChallenge(error);
      if (challenge.factors.isEmpty) {
        _showMessage(
          AppLocalizations.of(context).text(
            'This account requires a second factor that this app cannot verify. Contact support.',
            'To konto wymaga drugiego składnika, którego aplikacja nie może zweryfikować. Skontaktuj się ze wsparciem.',
          ),
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

  void _openForgotPassword() {
    if (_interactionLocked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/forgot-password'),
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _loginEmailController.text.trim(),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    _showMessageOn(ScaffoldMessenger.of(context), message);
  }

  void _showMessageOn(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    final copy = AppLocalizations.of(context);
    if (username.isEmpty) {
      return copy.text('Enter a username.', 'Wpisz nazwę użytkownika.');
    }
    if (username.length < 3) {
      return copy.text(
        'Username must contain at least 3 characters.',
        'Nazwa użytkownika musi mieć co najmniej 3 znaki.',
      );
    }
    if (username.length > 24) {
      return copy.text(
        'Username cannot exceed 24 characters.',
        'Nazwa użytkownika nie może przekraczać 24 znaków.',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) {
      return copy.text(
        'Use only letters, numbers, dots, and underscores.',
        'Użyj tylko liter, cyfr, kropek i podkreśleń.',
      );
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    final copy = AppLocalizations.of(context);
    if (email.isEmpty) {
      return copy.text('Enter your email address.', 'Wpisz adres e-mail.');
    }
    final pattern = RegExp(
      r'^[a-zA-Z0-9.!#$%&'
      '*+/=?^_`{|}~-]+@'
      r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
      r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
    );
    return pattern.hasMatch(email)
        ? null
        : copy.text(
            'Enter a valid email address.',
            'Wpisz prawidłowy adres e-mail.',
          );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    final copy = AppLocalizations.of(context);
    if (password.isEmpty) {
      return copy.text('Enter a password.', 'Wpisz hasło.');
    }
    if (password.length < 8) {
      return copy.text(
        'Password must contain at least 8 characters.',
        'Hasło musi mieć co najmniej 8 znaków.',
      );
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return copy.text(
        'Add at least one uppercase letter.',
        'Dodaj co najmniej jedną wielką literę.',
      );
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return copy.text(
        'Add at least one lowercase letter.',
        'Dodaj co najmniej jedną małą literę.',
      );
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return copy.text(
        'Add at least one number.',
        'Dodaj co najmniej jedną cyfrę.',
      );
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    final copy = AppLocalizations.of(context);
    if ((value ?? '').isEmpty) {
      return copy.text('Confirm your password.', 'Powtórz hasło.');
    }
    if (value != _registerPasswordController.text) {
      return copy.text('Passwords do not match.', 'Hasła nie są takie same.');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final routeIsFirst = ModalRoute.of(context)?.isFirst ?? true;
    final canPop =
        widget.popWhenSelectingLogin ||
        !routeIsFirst ||
        (!_isModeAnimating && _displayedMode == AuthMode.login);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnToLoginFromBack();
      },
      child: YoImmersiveDarkSurface(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: AppImmersiveColors.background,
          body: Stack(
            children: [
              const Positioned.fill(child: _AuthBackground()),
              AnimatedPadding(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: keyboardInset),
                child: AnimatedBuilder(
                  animation: _modeController,
                  builder: (context, _) {
                    return SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final layout = _resolveLayout(constraints);
                          _recordLayout(layout);
                          return switch (layout) {
                            _AuthLayout.compact => _buildSingleCard(
                              context,
                              constraints,
                              compact: true,
                            ),
                            _AuthLayout.medium => _buildSingleCard(
                              context,
                              constraints,
                              compact: false,
                            ),
                            _AuthLayout.wide => _buildDesktop(
                              context,
                              constraints,
                            ),
                          };
                        },
                      ),
                    );
                  },
                ),
              ),
              if (routeIsFirst &&
                  _displayedMode == AuthMode.register &&
                  !_isModeAnimating)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 28,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _handleBackEdgeStart,
                    onHorizontalDragUpdate: _handleBackEdgeUpdate,
                    onHorizontalDragEnd: _handleBackEdgeEnd,
                    onHorizontalDragCancel: () {
                      _trackingBackEdge = false;
                      _edgeDragDistance = 0;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _AuthLayout _resolveLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (width < 600) return _AuthLayout.compact;
    if (width < 1000) return _AuthLayout.medium;

    const horizontalPagePadding = 80.0;
    final workspaceWidth = math.min(1180.0, width - horizontalPagePadding);
    final canFitPanes = workspaceWidth / 2 >= 440;
    final canFitHeight = constraints.maxHeight - 64 >= 620;
    return canFitPanes && canFitHeight ? _AuthLayout.wide : _AuthLayout.medium;
  }

  Widget _buildSingleCard(
    BuildContext context,
    BoxConstraints constraints, {
    required bool compact,
  }) {
    final veryNarrow = constraints.maxWidth < 340;
    final short = constraints.maxHeight < 700;
    final pagePadding = compact ? (veryNarrow ? 10.0 : 16.0) : 32.0;
    final maxWidth = compact ? 430.0 : 560.0;

    return KeyedSubtree(
      key: ValueKey(compact ? 'auth-layout-compact' : 'auth-layout-medium'),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(pagePadding, 16, pagePadding, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 40),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AuthBrandHeader(
                    logoSize: short ? 56 : (compact ? 72 : 84),
                    compact: short,
                  ),
                  SizedBox(height: short ? 8 : 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppImmersiveColors.surface.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppImmersiveColors.authBorderStrong.withValues(
                          alpha: .54,
                        ),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 34,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        veryNarrow ? 16 : 20,
                        short ? 18 : 24,
                        veryNarrow ? 16 : 20,
                        24,
                      ),
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthModeRail(
                              sourceMode: _sourceMode,
                              targetMode: _targetMode,
                              selectedMode: _displayedMode,
                              progress: _relayTravelProgress,
                              isAnimating: _isModeAnimating,
                              isLocked: _interactionLocked,
                              loginFocusNode: _loginModeFocus,
                              registerFocusNode: _registerModeFocus,
                              onSelected: _requestMode,
                            ),
                            SizedBox(height: short ? 18 : 24),
                            if (_reduceMotion)
                              _buildAnimatedForm(context, compact: compact)
                            else
                              AnimatedSize(
                                duration: const Duration(milliseconds: 166),
                                curve: Curves.easeInOutCubic,
                                alignment: Alignment.topCenter,
                                clipBehavior: Clip.hardEdge,
                                child: _buildAnimatedForm(
                                  context,
                                  compact: compact,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, BoxConstraints constraints) {
    final workspaceWidth = math.min(1180.0, constraints.maxWidth - 80);
    final workspaceHeight = math.min(760.0, constraints.maxHeight - 64);
    return KeyedSubtree(
      key: const ValueKey('auth-layout-wide'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Center(
          child: SizedBox(
            width: workspaceWidth,
            height: workspaceHeight,
            child: AuthDesktopSplitShell(
              displayedMode: _displayedMode,
              sourceMode: _sourceMode,
              targetMode: _targetMode,
              progress: _modeController.value,
              isAnimating: _isModeAnimating,
              isLocked: _interactionLocked,
              onModeSelected: _requestMode,
              form: AutofillGroup(child: _buildAnimatedForm(context)),
              rail: AuthModeRail(
                sourceMode: _displayedMode,
                targetMode: _displayedMode,
                selectedMode: _displayedMode,
                progress: 1,
                isAnimating: false,
                isLocked: _interactionLocked,
                loginFocusNode: _loginModeFocus,
                registerFocusNode: _registerModeFocus,
                onSelected: _requestMode,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedForm(BuildContext context, {bool compact = false}) {
    final value = _modeController.value;
    final swap = _swapPoint;
    final outgoing = _isModeAnimating && value < swap;
    final wide = _lastLayout == _AuthLayout.wide;
    final outgoingPhase = wide
        ? _intervalProgress(80 / 760, 260 / 760)
        : _intervalProgress(80 / 520, 247 / 520);
    final incomingPhase = wide
        ? _intervalProgress(400 / 760, 650 / 760)
        : _intervalProgress(247 / 520, 447 / 520);
    final opacity = !_isModeAnimating
        ? 1.0
        : outgoing
        ? 1 - (.58 * Curves.easeInOutCubic.transform(outgoingPhase))
        : .42 + (.58 * Curves.easeOutCubic.transform(incomingPhase));
    final direction = _targetMode == AuthMode.register ? 1.0 : -1.0;
    final outgoingDistance = wide ? 16.0 : 6.0;
    final incomingDistance = wide ? 16.0 : 8.0;
    final offset = _reduceMotion || !_isModeAnimating
        ? 0.0
        : outgoing
        ? -outgoingDistance * direction * outgoingPhase
        : incomingDistance * direction * (1 - incomingPhase);

    return ExcludeFocus(
      excluding: _isModeAnimating,
      child: IgnorePointer(
        ignoring: _isModeAnimating,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(offset, 0),
            child: KeyedSubtree(
              key: ValueKey('auth-form-${_displayedMode.name}'),
              child: _displayedMode == AuthMode.login
                  ? _buildLoginForm(context, compact: compact)
                  : _buildRegisterForm(context, compact: compact),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, {required bool compact}) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeading(
          title: copy.text('Welcome back', 'Witaj ponownie'),
          subtitle: copy.text(
            'Your people and conversations are waiting.',
            'Twoi ludzie i rozmowy już czekają.',
          ),
        ),
        const SizedBox(height: 20),
        _ProviderSection(
          copy: copy,
          appleAvailability: _appleAvailability,
          googleLoading: _isGoogleLoading,
          appleLoading: _isAppleLoading,
          locked: _interactionLocked,
          onGoogle: _signInWithGoogle,
          onApple: _signInWithApple,
          onRetryApple: _signInWithApple,
        ),
        const SizedBox(height: 20),
        _AuthDivider(label: copy.text('OR WITH EMAIL', 'LUB E-MAILEM')),
        const SizedBox(height: 20),
        _EnsureVisibleOnFocus(
          focusNode: _loginEmailFocus,
          child: AuthTextField(
            key: const ValueKey('auth-login-email'),
            controller: _loginEmailController,
            focusNode: _loginEmailFocus,
            label: copy.email,
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onSubmitted: (_) => _loginPasswordFocus.requestFocus(),
          ),
        ),
        const SizedBox(height: 14),
        _EnsureVisibleOnFocus(
          focusNode: _loginPasswordFocus,
          child: AuthTextField(
            key: const ValueKey('auth-login-password'),
            controller: _loginPasswordController,
            focusNode: _loginPasswordFocus,
            label: copy.password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureLoginPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            suffixIcon: _obscureLoginPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            onSuffixPressed: () =>
                setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            onSubmitted: (_) => _login(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('auth-forgot-password'),
            onPressed: _interactionLocked ? null : _openForgotPassword,
            child: Text(copy.forgotPassword),
          ),
        ),
        const SizedBox(height: 10),
        AuthPrimaryButton(
          key: const ValueKey('auth-login-submit'),
          label: copy.logIn,
          loading: _isLoginLoading,
          onPressed: _interactionLocked ? null : _login,
        ),
      ],
    );
  }

  Widget _buildRegisterForm(BuildContext context, {required bool compact}) {
    final copy = AppLocalizations.of(context);
    return Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormHeading(
            title: copy.text('Create your voice', 'Stwórz swój głos'),
            subtitle: copy.text(
              'One account for rooms, moments and real conversations.',
              'Jedno konto do pokoi, momentów i prawdziwych rozmów.',
            ),
          ),
          const SizedBox(height: 20),
          _ProviderSection(
            copy: copy,
            appleAvailability: _appleAvailability,
            googleLoading: _isGoogleLoading,
            appleLoading: _isAppleLoading,
            locked: _interactionLocked,
            onGoogle: _signInWithGoogle,
            onApple: _signInWithApple,
            onRetryApple: _signInWithApple,
          ),
          const SizedBox(height: 20),
          _AuthDivider(label: copy.text('OR WITH EMAIL', 'LUB E-MAILEM')),
          const SizedBox(height: 20),
          _EnsureVisibleOnFocus(
            focusNode: _usernameFocus,
            child: AuthTextField(
              key: const ValueKey('auth-register-username'),
              controller: _usernameController,
              focusNode: _usernameFocus,
              label: copy.username,
              prefixIcon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              validator: _validateUsername,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                LengthLimitingTextInputFormatter(24),
              ],
              onSubmitted: (_) => _registerEmailFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 14),
          _EnsureVisibleOnFocus(
            focusNode: _registerEmailFocus,
            child: AuthTextField(
              key: const ValueKey('auth-register-email'),
              controller: _registerEmailController,
              focusNode: _registerEmailFocus,
              label: copy.email,
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: _validateEmail,
              onSubmitted: (_) => _registerPasswordFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 14),
          _EnsureVisibleOnFocus(
            focusNode: _registerPasswordFocus,
            child: AuthTextField(
              key: const ValueKey('auth-register-password'),
              controller: _registerPasswordController,
              focusNode: _registerPasswordFocus,
              label: copy.password,
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscureRegisterPassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: _obscureRegisterPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onSuffixPressed: () => setState(
                () => _obscureRegisterPassword = !_obscureRegisterPassword,
              ),
              validator: _validatePassword,
              onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 14),
          _EnsureVisibleOnFocus(
            focusNode: _confirmPasswordFocus,
            child: AuthTextField(
              key: const ValueKey('auth-register-confirm'),
              controller: _confirmPasswordController,
              focusNode: _confirmPasswordFocus,
              label: copy.confirmPassword,
              prefixIcon: Icons.lock_reset_outlined,
              obscureText: _obscureConfirmation,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: _obscureConfirmation
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onSuffixPressed: () =>
                  setState(() => _obscureConfirmation = !_obscureConfirmation),
              validator: _validateConfirmation,
              onSubmitted: (_) => _register(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            copy.text(
              'Use 8+ characters with uppercase, lowercase and a number.',
              'Użyj min. 8 znaków, wielkiej i małej litery oraz cyfry.',
            ),
            style: const TextStyle(
              color: AppImmersiveColors.authTextTertiary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            key: const ValueKey('auth-register-submit'),
            label: copy.createAccount,
            loading: _isRegisterLoading,
            onPressed: _interactionLocked ? null : _register,
          ),
        ],
      ),
    );
  }
}

class AuthModeRail extends StatelessWidget {
  const AuthModeRail({
    required this.sourceMode,
    required this.targetMode,
    required this.selectedMode,
    required this.progress,
    required this.isAnimating,
    required this.isLocked,
    required this.loginFocusNode,
    required this.registerFocusNode,
    required this.onSelected,
    super.key,
  });

  final AuthMode sourceMode;
  final AuthMode targetMode;
  final AuthMode selectedMode;
  final double progress;
  final bool isAnimating;
  final bool isLocked;
  final FocusNode loginFocusNode;
  final FocusNode registerFocusNode;
  final ValueChanged<AuthMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final scaledLineHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final railHeight = math.max(52.0, 8 + (scaledLineHeight * 2));
    return Semantics(
      container: true,
      label: copy.text('Authentication mode', 'Tryb uwierzytelniania'),
      child: SizedBox(
        key: const ValueKey('auth-mode-rail'),
        height: railHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final half = constraints.maxWidth / 2;
            final sourceX = sourceMode == AuthMode.login ? 0.0 : half;
            final targetX = targetMode == AuthMode.login ? 0.0 : half;
            final travel = isAnimating
                ? Curves.easeInOutCubic.transform(progress)
                : 1.0;
            final capsuleX = sourceX + ((targetX - sourceX) * travel);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: AppImmersiveColors.background.withValues(alpha: .58),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppImmersiveColors.authBorderStrong),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: capsuleX,
                    top: 0,
                    bottom: 0,
                    width: half,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF5A20C8),
                              AppColors.primary,
                              Color(0xFFA61BE0),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Color(0x557B2FF7), blurRadius: 13),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeRailButton(
                          key: const ValueKey('auth-mode-login'),
                          label: copy.text('Log in', 'Logowanie'),
                          selected: selectedMode == AuthMode.login,
                          focusNode: loginFocusNode,
                          locked: isLocked,
                          onTap: isLocked
                              ? null
                              : () => onSelected(AuthMode.login),
                        ),
                      ),
                      Expanded(
                        child: _ModeRailButton(
                          key: const ValueKey('auth-mode-register'),
                          label: copy.text('Create account', 'Utwórz konto'),
                          selected: selectedMode == AuthMode.register,
                          focusNode: registerFocusNode,
                          locked: isLocked,
                          onTap: isLocked
                              ? null
                              : () => onSelected(AuthMode.register),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModeRailButton extends StatelessWidget {
  const _ModeRailButton({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.locked,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final FocusNode focusNode;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          focusNode: focusNode,
          canRequestFocus: !locked,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  color: selected
                      ? AppImmersiveColors.textPrimary
                      : AppImmersiveColors.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthDesktopSplitShell extends StatelessWidget {
  const AuthDesktopSplitShell({
    required this.displayedMode,
    required this.sourceMode,
    required this.targetMode,
    required this.progress,
    required this.isAnimating,
    required this.isLocked,
    required this.onModeSelected,
    required this.form,
    required this.rail,
    super.key,
  });

  final AuthMode displayedMode;
  final AuthMode sourceMode;
  final AuthMode targetMode;
  final double progress;
  final bool isAnimating;
  final bool isLocked;
  final ValueChanged<AuthMode> onModeSelected;
  final Widget form;
  final Widget rail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = constraints.maxWidth / 2;
        final panelRect = _panelRect(constraints.maxWidth, paneWidth);
        final formOnLeft = displayedMode == AuthMode.register;

        return ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppImmersiveColors.surface,
              border: Border.all(
                color: AppImmersiveColors.authBorderStrong.withValues(
                  alpha: .62,
                ),
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 48,
                  offset: Offset(0, 24),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: formOnLeft
                            ? _DesktopFormPane(rail: rail, form: form)
                            : const SizedBox(),
                      ),
                      Expanded(
                        child: formOnLeft
                            ? const SizedBox()
                            : _DesktopFormPane(rail: rail, form: form),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  key: const ValueKey('auth-desktop-brand-panel'),
                  left: panelRect.left,
                  top: 0,
                  bottom: 0,
                  width: panelRect.width,
                  child: ClipRect(
                    child: _DesktopBrandPanel(
                      mode: displayedMode,
                      isLocked: isLocked,
                      contentMaxWidth: math.max(0, paneWidth - 96),
                      onModeSelected: onModeSelected,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Rect _panelRect(double workspaceWidth, double paneWidth) {
    if (!isAnimating) {
      final left = displayedMode == AuthMode.login ? 0.0 : paneWidth;
      return Rect.fromLTWH(left, 0, paneWidth, 1);
    }

    final travel = ((progress - (80 / 760)) / ((620 - 80) / 760)).clamp(
      0.0,
      1.0,
    );
    const coverStart = .43;
    const coverEnd = .57;
    final movingToRight = targetMode == AuthMode.register;
    if (travel <= coverStart) {
      final phase = Curves.easeInOutCubic.transform(
        (travel / coverStart).clamp(0.0, 1.0),
      );
      if (movingToRight) {
        final right = paneWidth + ((workspaceWidth - paneWidth) * phase);
        return Rect.fromLTRB(0, 0, right, 1);
      }
      final left = paneWidth * (1 - phase);
      return Rect.fromLTRB(left, 0, workspaceWidth, 1);
    }

    if (travel < coverEnd) {
      return Rect.fromLTWH(0, 0, workspaceWidth, 1);
    }

    final phase = const Cubic(
      .22,
      1,
      .36,
      1,
    ).transform(((travel - coverEnd) / (1 - coverEnd)).clamp(0.0, 1.0));
    if (movingToRight) {
      final left = paneWidth * phase;
      return Rect.fromLTRB(left, 0, workspaceWidth, 1);
    }
    final right = workspaceWidth - (paneWidth * phase);
    return Rect.fromLTRB(0, 0, right, 1);
  }
}

class _DesktopFormPane extends StatelessWidget {
  const _DesktopFormPane({required this.rail, required this.form});

  final Widget rail;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(48, 38, 48, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [rail, const SizedBox(height: 28), form],
      ),
    );
  }
}

class _DesktopBrandPanel extends StatelessWidget {
  const _DesktopBrandPanel({
    required this.mode,
    required this.isLocked,
    required this.contentMaxWidth,
    required this.onModeSelected,
  });

  final AuthMode mode;
  final bool isLocked;
  final double contentMaxWidth;
  final ValueChanged<AuthMode> onModeSelected;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final target = mode == AuthMode.login ? AuthMode.register : AuthMode.login;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF26104B), Color(0xFF6B22CF), Color(0xFFBE20D9)],
            stops: [0, .56, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ExcludeSemantics(
              child: CustomPaint(painter: _BrandArcPainter()),
            ),
            LayoutBuilder(
              builder: (context, constraints) => ExcludeFocus(
                excluding: isLocked,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 96),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: Image.asset(
                                'assets/images/yo-voice-favicon-512.png',
                                width: 116,
                                height: 116,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'YO VOICE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              copy.text(
                                'Speak. Connect. Be you.',
                                'Mów. Łącz się. Bądź sobą.',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFE7D8F8),
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                letterSpacing: .8,
                              ),
                            ),
                            const SizedBox(height: 26),
                            Text(
                              mode == AuthMode.login
                                  ? copy.text(
                                      'New here? Create one identity for every voice space.',
                                      'Jesteś tu pierwszy raz? Utwórz jedną tożsamość dla każdej przestrzeni głosowej.',
                                    )
                                  : copy.text(
                                      'Already have your voice? Return to your people.',
                                      'Masz już swoje konto? Wróć do swoich ludzi.',
                                    ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFF0E4FA),
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              key: const ValueKey('auth-desktop-brand-cta'),
                              onPressed: isLocked
                                  ? null
                                  : () => onModeSelected(target),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white60,
                                side: const BorderSide(color: Colors.white70),
                                minimumSize: const Size(180, 48),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                target == AuthMode.register
                                    ? copy.text(
                                        'Create account',
                                        'Utwórz konto',
                                      )
                                    : copy.text('Log in', 'Zaloguj się'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.25,
                colors: [
                  Color(0xFF1C073D),
                  Color(0xFF0D0618),
                  Color(0xFF07030E),
                ],
                stops: [0, .52, 1],
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
                  Color(0x08000000),
                  Color(0x20000000),
                  Color(0x6607030E),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader({required this.logoSize, required this.compact});

  final double logoSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accessibleLayout = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final logo = ExcludeSemantics(
      child: Image.asset(
        'assets/images/yo-voice-favicon-512.png',
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
    final copy = Column(
      crossAxisAlignment: accessibleLayout
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'YO VOICE',
          maxLines: 2,
          textAlign: accessibleLayout ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: AppImmersiveColors.textPrimary,
            fontSize: compact ? 21 : 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          AppLocalizations.of(
            context,
          ).text('Speak. Connect. Be you.', 'Mów. Łącz się. Bądź sobą.'),
          maxLines: 3,
          textAlign: accessibleLayout ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: AppImmersiveColors.textSecondary,
            fontSize: compact ? 11.5 : 12.5,
            letterSpacing: .6,
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      header: true,
      child: accessibleLayout
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [logo, const SizedBox(height: 6), copy],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                logo,
                SizedBox(width: compact ? 10 : 14),
                Flexible(child: copy),
              ],
            ),
    );
  }
}

class _FormHeading extends StatelessWidget {
  const _FormHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppImmersiveColors.textPrimary,
            fontSize: 27,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppImmersiveColors.textSecondary,
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.copy,
    required this.appleAvailability,
    required this.googleLoading,
    required this.appleLoading,
    required this.locked,
    required this.onGoogle,
    required this.onApple,
    required this.onRetryApple,
  });

  final AppLocalizations copy;
  final AppleSignInAvailability? appleAvailability;
  final bool googleLoading;
  final bool appleLoading;
  final bool locked;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onRetryApple;

  @override
  Widget build(BuildContext context) {
    final notConfigured =
        appleAvailability == AppleSignInAvailability.notConfigured;
    final temporary =
        appleAvailability == AppleSignInAvailability.temporarilyUnavailable;
    final applePending = appleAvailability == null;
    final google = AuthSocialButton(
      key: const ValueKey('auth-google-provider'),
      label: copy.continueWithGoogle,
      svgIconPath: 'assets/icons/icon_google_g.svg',
      isLoading: googleLoading,
      onPressed: locked ? null : onGoogle,
    );
    final apple = AuthSocialButton(
      key: const ValueKey('auth-apple-provider'),
      label: copy.continueWithApple,
      statusLabel: notConfigured
          ? copy.text('Coming soon', 'Wkrótce')
          : temporary
          ? copy.text('Try again', 'Spróbuj ponownie')
          : null,
      materialIcon: Icons.apple,
      iconSize: 30,
      isLoading: appleLoading || applePending,
      onPressed: locked || applePending || notConfigured
          ? null
          : temporary
          ? onRetryApple
          : onApple,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final sideBySide = constraints.maxWidth >= 400 && textScale <= 1.3;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: google),
              const SizedBox(width: 12),
              Expanded(child: apple),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [google, const SizedBox(height: 12), apple],
        );
      },
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppImmersiveColors.divider)),
        Flexible(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppImmersiveColors.authTextTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppImmersiveColors.divider)),
      ],
    );
  }
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.prefixIcon,
    super.key,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIcon,
    this.onSuffixPressed,
    this.onSubmitted,
    this.validator,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixPressed;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final decoration = InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(color: AppImmersiveColors.textSecondary),
      prefixIcon: Icon(prefixIcon, color: AppImmersiveColors.textSecondary),
      suffixIcon: suffixIcon == null
          ? null
          : IconButton(
              tooltip: obscureText
                  ? copy.text('Show password', 'Pokaż hasło')
                  : copy.text('Hide password', 'Ukryj hasło'),
              onPressed: onSuffixPressed,
              icon: Icon(suffixIcon, color: AppImmersiveColors.textSecondary),
            ),
      filled: true,
      fillColor: AppImmersiveColors.background.withValues(alpha: .55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      errorMaxLines: 3,
      errorStyle: const TextStyle(color: Color(0xFFFF8CA2), height: 1.25),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppImmersiveColors.authBorderStrong.withValues(alpha: .76),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppImmersiveColors.authBorderStrong.withValues(alpha: .76),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.secondary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error, width: 1.8),
      ),
    );

    if (validator == null) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        obscureText: obscureText,
        autocorrect: false,
        enableSuggestions: !obscureText,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          color: AppImmersiveColors.textPrimary,
          fontSize: 16,
        ),
        cursorColor: AppColors.secondary,
        decoration: decoration,
      );
    }

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      inputFormatters: inputFormatters,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(
        color: AppImmersiveColors.textPrimary,
        fontSize: 16,
      ),
      cursorColor: AppColors.secondary,
      decoration: decoration,
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      value: loading ? copy.text('Loading', 'Ładowanie') : null,
      liveRegion: loading,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF6424DE),
                  AppColors.primary,
                  AppColors.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: onPressed == null
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x557B2FF7),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
            ),
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: loading
                  ? const SizedBox.square(
                      dimension: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnsureVisibleOnFocus extends StatefulWidget {
  const _EnsureVisibleOnFocus({required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  State<_EnsureVisibleOnFocus> createState() => _EnsureVisibleOnFocusState();
}

class _EnsureVisibleOnFocusState extends State<_EnsureVisibleOnFocus>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _EnsureVisibleOnFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode.removeListener(_handleFocus);
    widget.focusNode.addListener(_handleFocus);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleEnsureVisible();

  void _handleFocus() {
    if (widget.focusNode.hasFocus) _scheduleEnsureVisible();
  }

  void _scheduleEnsureVisible() {
    if (!widget.focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      _ensureVisible();
    });
  }

  void _ensureVisible() {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    Scrollable.ensureVisible(
      context,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BrandArcPainter extends CustomPainter {
  const _BrandArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .16);
    for (var i = 0; i < 4; i++) {
      final inset = 42.0 + (i * 44);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .54, size.height * .48),
          width: size.width + inset,
          height: size.height * .72 + inset,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
