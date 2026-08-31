import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/widgets/animated_totp_code_input.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class TotpChallengeScreen extends StatefulWidget {
  const TotpChallengeScreen({required this.challenge, super.key});

  final TotpSignInChallengeClient challenge;

  @override
  State<TotpChallengeScreen> createState() => _TotpChallengeScreenState();
}

enum _ChallengeErrorKind { invalid, warning }

class _TotpChallengeScreenState extends State<TotpChallengeScreen> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  final _motionKey = GlobalKey<AnimatedTotpCodeInputState>();

  Timer? _autoSubmitDebounce;
  String? _selectedFactorUid;
  String? _error;
  _ChallengeErrorKind _errorKind = _ChallengeErrorKind.warning;
  int _previousCodeLength = 0;
  bool _autoSubmitArmed = true;
  bool _locked = false;
  bool _verified = false;
  bool _didPop = false;
  bool _suppressNextCodeEvent = false;

  @override
  void initState() {
    super.initState();
    if (widget.challenge.factors.isNotEmpty) {
      _selectedFactorUid = widget.challenge.factors.first.uid;
    }
    _codeController.addListener(_handleCodeChanged);
  }

  @override
  void dispose() {
    _autoSubmitDebounce?.cancel();
    _codeController.removeListener(_handleCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _handleCodeChanged() {
    if (!mounted) return;
    final length = _codeController.text.length;
    final previous = _previousCodeLength;
    _previousCodeLength = length;

    if (_suppressNextCodeEvent) {
      _suppressNextCodeEvent = false;
      setState(() {});
      return;
    }

    if (_motionKey.currentState?.debugFrame.phase == TotpChallengePhase.error) {
      _motionKey.currentState?.resetEditing();
    }

    if (length < 6) {
      _autoSubmitDebounce?.cancel();
      _autoSubmitArmed = true;
    } else if (previous < 6 && length == 6 && _autoSubmitArmed && !_locked) {
      _autoSubmitArmed = false;
      _autoSubmitDebounce?.cancel();
      _autoSubmitDebounce = Timer(const Duration(milliseconds: 120), _submit);
    }

    setState(() {
      if (_error != null) _error = null;
    });
  }

  void _changeFactor(String? factorUid) {
    if (_locked || factorUid == null) return;
    _autoSubmitDebounce?.cancel();
    _autoSubmitArmed = _codeController.text.length < 6;
    setState(() {
      _selectedFactorUid = factorUid;
      _error = null;
    });
  }

  void _handlePopInvoked(bool didPop, bool? result) {
    if (didPop || _locked || _didPop || !mounted) return;
    _didPop = true;
    Navigator.of(context).pop();
  }

  String get _verifyButtonLabel {
    if (!_locked) return 'Verify and continue';
    if (_verified) return 'Verified';
    if (_error != null) {
      return _errorKind == _ChallengeErrorKind.invalid
          ? 'Code not accepted'
          : 'Could not verify';
    }
    return 'Verification in progress';
  }

  Future<void> _submit() async {
    _autoSubmitDebounce?.cancel();
    if (_locked) return;
    final selectedFactorUid = _selectedFactorUid;
    if (selectedFactorUid == null) return;
    final code = _codeController.text;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      const message = 'Enter all 6 digits.';
      _motionKey.currentState?.resetEditing();
      setState(() {
        _error = message;
        _errorKind = _ChallengeErrorKind.warning;
      });
      _announceError(message);
      _codeFocusNode.requestFocus();
      return;
    }

    setState(() {
      _locked = true;
      _verified = false;
      _error = null;
    });
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    _motionKey.currentState?.startSubmitting();

    try {
      final challenge = widget.challenge;
      await challenge.resolve(factorUid: selectedFactorUid, code: code);
      if (!mounted) return;
      setState(() => _verified = true);
      final motion = _motionKey.currentState;
      if (motion == null) return;
      final completed = await motion.playSuccess();
      if (!completed) {
        if (!mounted) return;
        setState(() => _locked = false);
        _codeFocusNode.requestFocus();
        return;
      }
      if (!mounted || _didPop) return;
      _didPop = true;
      Navigator.of(context).pop(true);
    } on FormatException {
      await _showFailure(
        'Two-factor verification could not be completed. Try again.',
        kind: _ChallengeErrorKind.warning,
      );
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'invalid-verification-code':
        case 'invalid-credential':
          await _showFailure(
            'That code is not valid. Enter a new code and try again.',
            kind: _ChallengeErrorKind.invalid,
            clearCode: true,
          );
          return;
        case 'too-many-requests':
          await _showFailure(
            'Too many attempts. Wait a moment before trying again.',
            kind: _ChallengeErrorKind.warning,
          );
          return;
        case 'network-request-failed':
          await _showFailure(
            'Two-factor verification could not be completed. Check your connection and try again.',
            kind: _ChallengeErrorKind.warning,
          );
          return;
        default:
          await _showFailure(
            'Two-factor verification could not be completed. Try again.',
            kind: _ChallengeErrorKind.warning,
          );
      }
    } catch (_) {
      await _showFailure(
        'Two-factor verification could not be completed. Check your connection and try again.',
        kind: _ChallengeErrorKind.warning,
      );
    }
  }

  Future<void> _showFailure(
    String message, {
    required _ChallengeErrorKind kind,
    bool clearCode = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _verified = false;
      _error = message;
      _errorKind = kind;
    });
    _announceError(message);

    final motion = _motionKey.currentState;
    if (motion != null) {
      await motion.playError(invalid: kind == _ChallengeErrorKind.invalid);
    }
    if (!mounted) return;

    if (clearCode) {
      _suppressNextCodeEvent = true;
      _codeController.clear();
      _previousCodeLength = 0;
      _autoSubmitArmed = true;
    } else {
      // A preserved six-digit value is not edge-triggered again. The button
      // remains a deliberate, Firebase-rate-limited manual retry.
      _autoSubmitArmed = _codeController.text.length < 6;
    }
    motion?.resetEditing();
    setState(() => _locked = false);
    _codeFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocusNode.requestFocus();
    });
  }

  void _announceError(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YoImmersiveDarkSurface(
      child: Builder(
        builder: (context) {
          final palette = context.appPalette;
          return PopScope<bool>(
            canPop: false,
            onPopInvokedWithResult: _handlePopInvoked,
            child: Scaffold(
              backgroundColor: palette.background,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -.88),
                    radius: 1.1,
                    colors: <Color>[palette.backgroundTop, palette.background],
                  ),
                ),
                child: SafeArea(
                  child: ResponsiveContentFrame(
                    width: ResponsiveContentWidth.form,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ListView(
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            4000,
                          ),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.sm,
                            AppSpacing.md,
                            AppSpacing.xxl,
                          ),
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Header(
                                  locked: _locked,
                                  onBack: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Center(
                                  child: Image.asset(
                                    'assets/images/yo-voice-favicon-512.png',
                                    key: const ValueKey<String>('totp-logo'),
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Confirm it’s you',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.headlineLarge.copyWith(
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Enter the current code from the authenticator app connected to your YO Voice account.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                if (widget.challenge.factors.isEmpty)
                                  const _ChallengeErrorCard(
                                    message:
                                        'No supported authenticator is available for this account. Contact support.',
                                    kind: _ChallengeErrorKind.warning,
                                  )
                                else ...[
                                  if (widget.challenge.factors.length > 1) ...[
                                    _FactorSelector(
                                      factors: widget.challenge.factors,
                                      value: _selectedFactorUid,
                                      enabled: !_locked,
                                      onChanged: _changeFactor,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                  AutofillGroup(
                                    onDisposeAction:
                                        AutofillContextAction.cancel,
                                    child: AnimatedTotpCodeInput(
                                      key: _motionKey,
                                      controller: _codeController,
                                      focusNode: _codeFocusNode,
                                      enabled: !_locked,
                                      contentSlotWidth: constraints.maxWidth,
                                      onSubmitted: (_) => _submit(),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 52,
                                      minWidth: 44,
                                    ),
                                    child: FilledButton(
                                      key: const ValueKey<String>(
                                        'totp-verify-button',
                                      ),
                                      onPressed: _locked ? null : _submit,
                                      style: FilledButton.styleFrom(
                                        foregroundColor: AppColors.white,
                                        backgroundColor: AppColors.primary,
                                        disabledBackgroundColor:
                                            palette.surfaceRaised,
                                        disabledForegroundColor:
                                            palette.textTertiary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.lg,
                                          vertical: AppSpacing.md,
                                        ),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: AppRadius.lg,
                                        ),
                                      ),
                                      child: Text(
                                        _verifyButtonLabel,
                                        textAlign: TextAlign.center,
                                        style: AppTypography.labelLarge,
                                      ),
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    _AnimatedChallengeErrorCard(
                                      message: _error!,
                                      kind: _errorKind,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.locked, required this.onBack});

  final bool locked;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          onPressed: locked ? null : onBack,
          tooltip: 'Back',
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          color: palette.textPrimary,
          disabledColor: palette.textTertiary,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Two-factor verification',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FactorSelector extends StatelessWidget {
  const _FactorSelector({
    required this.factors,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<TotpSignInFactor> factors;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    Widget label(TotpSignInFactor factor) => Text(
      factor.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.bodyMedium.copyWith(color: palette.textPrimary),
    );

    return DropdownButtonFormField<String>(
      key: const ValueKey<String>('totp-factor-dropdown'),
      initialValue: value,
      isExpanded: true,
      dropdownColor: palette.surfaceRaised,
      decoration: const InputDecoration(labelText: 'Authenticator'),
      items: factors
          .map(
            (factor) => DropdownMenuItem<String>(
              value: factor.uid,
              child: label(factor),
            ),
          )
          .toList(growable: false),
      selectedItemBuilder: (_) => factors.map(label).toList(growable: false),
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _ChallengeErrorCard extends StatelessWidget {
  const _ChallengeErrorCard({required this.message, required this.kind});

  final String message;
  final _ChallengeErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final invalid = kind == _ChallengeErrorKind.invalid;
    final foreground = invalid
        ? palette.dangerForeground
        : palette.warningForeground;
    final background = invalid ? palette.dangerSurface : palette.warningSurface;
    return Container(
      key: const ValueKey<String>('totp-error-card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.md,
        border: Border.all(color: foreground.withValues(alpha: .54)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            invalid ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedChallengeErrorCard extends StatelessWidget {
  const _AnimatedChallengeErrorCard({
    required this.message,
    required this.kind,
  });

  final String message;
  final _ChallengeErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: reduceMotion ? Offset.zero : Offset(0, 4 * (1 - value)),
          child: child,
        ),
      ),
      child: _ChallengeErrorCard(message: message, kind: kind),
    );
  }
}
