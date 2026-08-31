import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';

/// Non-shipping simulator target for the TOTP challenge motion sequence.
///
/// Run with:
///   `flutter run -d <ios-simulator-id> -t tool/totp_challenge_preview.dart`
///
/// Every factor and code used by this target is synthetic. This file is not
/// referenced by product routing and must not be added to release entrypoints.
void main() => runApp(const TotpChallengePreviewApp());

enum _PreviewOutcome { fastSuccess, slowSuccess, invalid, network }

extension on _PreviewOutcome {
  String get label => switch (this) {
    _PreviewOutcome.fastSuccess => 'Fast success',
    _PreviewOutcome.slowSuccess => 'Slow success',
    _PreviewOutcome.invalid => 'Invalid code',
    _PreviewOutcome.network => 'Network error',
  };

  String get description => switch (this) {
    _PreviewOutcome.fastSuccess =>
      'The synthetic resolver succeeds while the field-to-node morph is active.',
    _PreviewOutcome.slowSuccess =>
      'The synthetic resolver stays pending long enough to inspect the orbit.',
    _PreviewOutcome.invalid =>
      'Shows the red X feedback, then clears and refocuses the code input.',
    _PreviewOutcome.network =>
      'Preserves all six digits so a deliberate manual retry can be tested.',
  };
}

class TotpChallengePreviewApp extends StatefulWidget {
  const TotpChallengePreviewApp({super.key});

  @override
  State<TotpChallengePreviewApp> createState() =>
      _TotpChallengePreviewAppState();
}

class _TotpChallengePreviewAppState extends State<TotpChallengePreviewApp> {
  bool _reducedMotion = false;
  bool _largeText = false;
  bool _halfSpeed = false;

  @override
  void dispose() {
    timeDilation = 1;
    super.dispose();
  }

  void _setHalfSpeed(bool value) {
    timeDilation = value ? 2 : 1;
    setState(() => _halfSpeed = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YO Voice TOTP Motion Preview',
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            accessibleNavigation: _reducedMotion,
            disableAnimations: _reducedMotion,
            textScaler: _largeText
                ? const TextScaler.linear(2)
                : TextScaler.noScaling,
          ),
          child: child!,
        );
      },
      home: _PreviewLauncher(
        reducedMotion: _reducedMotion,
        largeText: _largeText,
        halfSpeed: _halfSpeed,
        onReducedMotionChanged: (value) {
          setState(() => _reducedMotion = value);
        },
        onLargeTextChanged: (value) {
          setState(() => _largeText = value);
        },
        onHalfSpeedChanged: _setHalfSpeed,
      ),
    );
  }
}

class _PreviewLauncher extends StatefulWidget {
  const _PreviewLauncher({
    required this.reducedMotion,
    required this.largeText,
    required this.halfSpeed,
    required this.onReducedMotionChanged,
    required this.onLargeTextChanged,
    required this.onHalfSpeedChanged,
  });

  final bool reducedMotion;
  final bool largeText;
  final bool halfSpeed;
  final ValueChanged<bool> onReducedMotionChanged;
  final ValueChanged<bool> onLargeTextChanged;
  final ValueChanged<bool> onHalfSpeedChanged;

  @override
  State<_PreviewLauncher> createState() => _PreviewLauncherState();
}

class _PreviewLauncherState extends State<_PreviewLauncher> {
  _PreviewOutcome _outcome = _PreviewOutcome.slowSuccess;
  bool _multipleFactors = false;
  bool? _lastResult;

  Future<void> _openChallenge() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: '/dev/totp-challenge-preview'),
        builder: (_) => TotpChallengeScreen(
          challenge: _SyntheticChallenge(
            outcome: _outcome,
            multipleFactors: _multipleFactors,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Material(
                  color: palette.surface,
                  elevation: 12,
                  shadowColor: palette.shadow.withValues(alpha: .36),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.xl,
                    side: BorderSide(color: palette.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Voice Constellation',
                          style: AppTypography.headlineLarge.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Developer-only challenge preview. Enter the synthetic code 123456 to exercise a scenario.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Resolver outcome',
                          style: AppTypography.titleMedium.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: _PreviewOutcome.values
                              .map(
                                (outcome) => ChoiceChip(
                                  label: Text(outcome.label),
                                  selected: _outcome == outcome,
                                  onSelected: (_) {
                                    setState(() => _outcome = outcome);
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AnimatedSwitcher(
                          duration: widget.reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Text(
                            _outcome.description,
                            key: ValueKey<_PreviewOutcome>(_outcome),
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Reduced motion'),
                          subtitle: const Text(
                            'Sets both accessibleNavigation and disableAnimations.',
                          ),
                          value: widget.reducedMotion,
                          onChanged: widget.onReducedMotionChanged,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('200% text'),
                          subtitle: const Text(
                            'Exercises the fully scaled instruction and status copy.',
                          ),
                          value: widget.largeText,
                          onChanged: widget.onLargeTextChanged,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('0.5× review speed'),
                          subtitle: const Text(
                            'Slows only Flutter motion for frame-by-frame review.',
                          ),
                          value: widget.halfSpeed,
                          onChanged: widget.onHalfSpeedChanged,
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Multiple authenticators'),
                          subtitle: const Text(
                            'Shows the factor selector with a deliberately long synthetic name.',
                          ),
                          value: _multipleFactors,
                          onChanged: (value) {
                            setState(() => _multipleFactors = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _openChallenge,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Open challenge'),
                          ),
                        ),
                        if (_lastResult != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Last controlled pop result: $_lastResult',
                            style: AppTypography.labelMedium.copyWith(
                              color: palette.successForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyntheticChallenge implements TotpSignInChallengeClient {
  _SyntheticChallenge({required this.outcome, required bool multipleFactors})
    : factors = <TotpSignInFactor>[
        const TotpSignInFactor(
          uid: 'synthetic-primary',
          displayName: 'Synthetic authenticator',
        ),
        if (multipleFactors)
          const TotpSignInFactor(
            uid: 'synthetic-secondary',
            displayName: 'Synthetic studio authenticator with a long label',
          ),
      ];

  final _PreviewOutcome outcome;

  @override
  final List<TotpSignInFactor> factors;

  @override
  Future<void> resolve({
    required String factorUid,
    required String code,
  }) async {
    if (!factors.any((factor) => factor.uid == factorUid)) {
      throw const FormatException('Choose a valid authenticator.');
    }
    if (code != '123456') {
      throw FirebaseAuthException(
        code: 'invalid-verification-code',
        message: 'Synthetic preview accepts only 123456.',
      );
    }

    switch (outcome) {
      case _PreviewOutcome.fastSuccess:
        await Future<void>.delayed(const Duration(milliseconds: 30));
      case _PreviewOutcome.slowSuccess:
        await Future<void>.delayed(const Duration(milliseconds: 3200));
      case _PreviewOutcome.invalid:
        await Future<void>.delayed(const Duration(milliseconds: 900));
        throw FirebaseAuthException(
          code: 'invalid-verification-code',
          message: 'Synthetic invalid-code response.',
        );
      case _PreviewOutcome.network:
        await Future<void>.delayed(const Duration(milliseconds: 900));
        throw FirebaseAuthException(
          code: 'network-request-failed',
          message: 'Synthetic network interruption.',
        );
    }
  }
}
