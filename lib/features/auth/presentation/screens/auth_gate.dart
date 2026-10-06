import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_entry_link.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/reels/presentation/navigation/reel_link_coordinator.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// The shortest a normal cold launch keeps the app-owned startup surface.
///
/// Authentication and profile bootstrap continue concurrently. Explicit
/// session boundaries and failures release this hold immediately.
const authGateInitialStartupMinimumVisibility = Duration(milliseconds: 1400);

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({
    super.key,
    this.initiallySignedOut = false,
    this.initialAuthError,
    this.reelLinkIntent,
    this.entryLink,
    this.initialStartupMinimumVisibility =
        authGateInitialStartupMinimumVisibility,
  });

  /// A route-stack reset after logout already knows the session is gone. Show
  /// LoginScreen on its first frame instead of flashing startup animation
  /// while the new Auth stream delivers its initial null value.
  final bool initiallySignedOut;

  /// Preserves an auth-stream failure while the route stack is replaced, so a
  /// private screen cannot remain above the boundary during an auth error.
  final Object? initialAuthError;
  final ReelLinkIntentController? reelLinkIntent;

  /// The profile or Voice Moment link the app was opened with (ADR-238). A
  /// signed-out visitor reads on the sign-in screen what signing in opens;
  /// the shell opens the link itself after sign-in. Null after a sign-out.
  final AuthEntryLink? entryLink;

  /// Minimum app-owned startup visibility for a normal initial launch.
  ///
  /// [Duration.zero] is used by already-resolved privacy-boundary routes. The
  /// hold never applies to [initiallySignedOut], [initialAuthError], stream
  /// failures, a later principal change or an in-progress auth operation.
  final Duration initialStartupMinimumVisibility;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  late final Completer<void> _initialStartupReady;
  Timer? _initialStartupTimer;
  bool _initialStartupPending = false;
  bool _hasInitialAuthResult = false;
  String? _initialUserId;

  @override
  void initState() {
    super.initState();
    _initialStartupReady = Completer<void>();
    final duration = widget.initialStartupMinimumVisibility;
    if (widget.initiallySignedOut ||
        widget.initialAuthError != null ||
        duration <= Duration.zero) {
      _initialStartupReady.complete();
      return;
    }
    _initialStartupPending = true;
    _initialStartupTimer = Timer(duration, _finishInitialStartupHold);
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallySignedOut || widget.initialAuthError != null) {
      _releaseInitialStartupHold();
    } else if (widget.initialStartupMinimumVisibility <= Duration.zero) {
      _releaseInitialStartupHold();
    }
  }

  void _finishInitialStartupHold() {
    _initialStartupTimer = null;
    if (!_initialStartupPending) return;
    _initialStartupPending = false;
    if (!_initialStartupReady.isCompleted) _initialStartupReady.complete();
    if (mounted) setState(() {});
  }

  void _releaseInitialStartupHold() {
    _initialStartupTimer?.cancel();
    _initialStartupTimer = null;
    _initialStartupPending = false;
    if (!_initialStartupReady.isCompleted) _initialStartupReady.complete();
  }

  void _observeBoundary(
    AsyncValue<User?> authState, {
    required bool authOperationLoading,
  }) {
    if (authState case AsyncError<User?>()) {
      _releaseInitialStartupHold();
      return;
    }
    if (authOperationLoading) {
      // Login and registration are later user-driven flows. Their own loading
      // state stays visible only as long as the operation actually needs it.
      _releaseInitialStartupHold();
    }
    if (authState case AsyncData<User?>(:final value)) {
      final userId = value?.uid;
      if (!_hasInitialAuthResult) {
        _hasInitialAuthResult = true;
        _initialUserId = userId;
      } else if (_initialUserId != userId) {
        // Never keep an old principal's startup presentation above a new
        // privacy boundary. The app-level route reset also replaces the stack.
        _releaseInitialStartupHold();
      }
    }
  }

  @override
  void dispose() {
    _initialStartupTimer?.cancel();
    _initialStartupTimer = null;
    if (!_initialStartupReady.isCompleted) _initialStartupReady.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateChangesProvider);
    final authOperationLoading = ref.watch(authLoadingProvider);
    _observeBoundary(authState, authOperationLoading: authOperationLoading);
    void setRegistrationLoading(bool loading) {
      ref.read(authLoadingProvider.notifier).state = loading;
    }

    final immediateBoundary = switch (authState) {
      AsyncLoading() when widget.initiallySignedOut => KeyedSubtree(
        key: const ValueKey('auth-signed-out'),
        child: LoginScreen(
          onRegistrationLoadingChanged: setRegistrationLoading,
        ),
      ),
      AsyncLoading() when widget.initialAuthError != null => KeyedSubtree(
        key: const ValueKey('auth-error'),
        child: _AuthErrorScreen(
          error: widget.initialAuthError!,
          onRetry: () => ref.invalidate(authStateChangesProvider),
        ),
      ),
      _ => null,
    };
    final child =
        immediateBoundary ??
        authState.when<Widget>(
          loading: () => const KeyedSubtree(
            key: ValueKey('auth-loading'),
            child: StartupLoadingScreen(),
          ),
          error: (error, stackTrace) {
            return KeyedSubtree(
              key: const ValueKey('auth-error'),
              child: _AuthErrorScreen(
                error: error,
                onRetry: () {
                  ref.invalidate(authStateChangesProvider);
                },
              ),
            );
          },
          data: (user) {
            if (user == null) {
              if (_initialStartupPending) {
                return const KeyedSubtree(
                  key: ValueKey('auth-loading'),
                  child: StartupLoadingScreen(),
                );
              }
              return KeyedSubtree(
                key: const ValueKey('auth-signed-out'),
                child: LoginScreen(
                  onRegistrationLoadingChanged: setRegistrationLoading,
                  entryLink: widget.entryLink,
                ),
              );
            }

            // Firebase Auth publishes a newly created principal before
            // AuthService.register() has finished writing the username the
            // member selected. Starting ProfileService.ensureProfile() in
            // that window can seed the email local-part as a non-empty
            // canonical displayName; Rules then correctly prevent the
            // registration write from replacing it. Keep the authenticated
            // entry behind the shared operation flag wired into the shipped
            // responsive registration screen, so profile bootstrap starts
            // only after registration provisioning has completed.
            // ProfileService enforces the same boundary across tabs/processes.
            if (authOperationLoading) {
              return const KeyedSubtree(
                key: ValueKey('auth-operation-loading'),
                child: StartupLoadingScreen(),
              );
            }

            return KeyedSubtree(
              key: ValueKey('auth-user-${user.uid}'),
              child: _AuthenticatedEntry(
                userId: user.uid,
                reelLinkIntent: widget.reelLinkIntent,
                initialStartupReady: _initialStartupReady.future,
              ),
            );
          },
        );

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (currentChild, previousChildren) {
        final children = <Widget>[...previousChildren];
        if (currentChild != null) {
          children.add(currentChild);
        }
        return Stack(fit: StackFit.expand, children: children);
      },
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

class _AuthenticatedEntry extends StatefulWidget {
  const _AuthenticatedEntry({
    required this.userId,
    required this.initialStartupReady,
    this.reelLinkIntent,
  });

  final String userId;
  final Future<void> initialStartupReady;
  final ReelLinkIntentController? reelLinkIntent;

  @override
  State<_AuthenticatedEntry> createState() => _AuthenticatedEntryState();
}

class _AuthenticatedEntryState extends State<_AuthenticatedEntry> {
  late Future<void> _profileBootstrap;
  Future<void> _pushOnboardingReadiness = Future<void>.value();
  bool _isProfileRetry = false;

  @override
  void initState() {
    super.initState();

    _profileBootstrap = _bootstrapProfile();
  }

  Future<void> _bootstrapProfile() async {
    await ensureAuthenticatedProfileWithRetry(ProfileService().ensureProfile);

    // Bind push only after the private profile exists. Profile provisioning is
    // the authenticated-entry boundary; push remains best-effort and never
    // delays the shell once that boundary has succeeded.
    final push = PushNotificationService.instance;
    final initialization = push.initialize();
    _pushOnboardingReadiness = push.initialOnboardingReadiness;
    unawaited(initialization);
  }

  void _retryProfileBootstrap() {
    setState(() {
      // The 1.4 s hold belongs only to the first launch attempt. A manual
      // retry stays on its natural profile-loading boundary and proceeds as
      // soon as that retry succeeds.
      _isProfileRetry = true;
      _profileBootstrap = _bootstrapProfile();
    });
  }

  Future<void> _signOut() => AuthService().signOut();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _profileBootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StartupLoadingScreen();
        }

        if (snapshot.hasError) {
          return ProfileBootstrapErrorScreen(
            onRetry: _retryProfileBootstrap,
            onSignOut: _signOut,
          );
        }

        Widget buildShell() {
          final intent = widget.reelLinkIntent;
          final shell = MainShell(
            onboardingReadiness: intent == null
                ? _pushOnboardingReadiness
                : Future.wait<void>([
                    _pushOnboardingReadiness,
                    intent.initialVisitCompleted,
                  ]),
          );
          if (intent == null) return shell;
          return ReelLinkEntryCoordinator(
            controller: intent,
            userId: widget.userId,
            child: shell,
          );
        }

        if (_isProfileRetry) return buildShell();
        return FutureBuilder<void>(
          future: widget.initialStartupReady,
          builder: (context, startupSnapshot) {
            if (startupSnapshot.connectionState != ConnectionState.done) {
              return const StartupLoadingScreen();
            }
            return buildShell();
          },
        );
      },
    );
  }
}

@visibleForTesting
Future<void> ensureAuthenticatedProfileWithRetry(
  Future<void> Function() ensureProfile, {
  List<Duration> retryDelays = const [
    Duration.zero,
    Duration(milliseconds: 350),
    Duration(milliseconds: 1200),
  ],
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;

  for (final delay in retryDelays) {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    try {
      await ensureProfile();
      return;
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }

  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}

/// Shown when profile bootstrap still fails after its retries (for example
/// offline on a first sign-in). It shares the auth-gate failure layout; its
/// retry is a recovery action, not the sign-in chain's step, so it keeps the
/// gradient without the R5 lift (R5: never on retry actions).
///
/// Public only so tests and the capture harness can render it directly; the
/// app reaches it through [AuthGate].
@visibleForTesting
class ProfileBootstrapErrorScreen extends StatelessWidget {
  const ProfileBootstrapErrorScreen({
    required this.onRetry,
    required this.onSignOut,
    super.key,
  });

  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return _GateFailure(
      // A connection problem, not a failed sign-in: its glyph keeps the
      // warning role rather than the error red.
      icon: Icons.cloud_off_rounded,
      iconColor: AppColors.warning,
      title: copy.text(
        'Finishing your profile',
        'Kończymy konfigurację profilu',
      ),
      // Size and copy unchanged; weight at the w700 cap (refine-look §2.6).
      titleStyle: const TextStyle(
        color: AppImmersiveColors.textPrimary,
        fontSize: 25,
        fontWeight: FontWeight.w700,
      ),
      message: copy.text(
        'Your account is secure. Check your connection and try '
            'again to finish setting up YO Voice.',
        'Twoje konto jest bezpieczne. Sprawdź połączenie i spróbuj '
            'ponownie, aby dokończyć konfigurację YO Voice.',
      ),
      messageStyle: const TextStyle(
        color: AppImmersiveColors.textSecondary,
        fontSize: 15,
        height: 1.45,
      ),
      retryLabel: copy.text('TRY AGAIN', 'SPRÓBUJ PONOWNIE'),
      onRetry: onRetry,
      liftedRetry: false,
      secondary: TextButton(
        key: const ValueKey('profile-bootstrap-sign-out'),
        onPressed: () => unawaited(onSignOut()),
        child: Text(copy.text('Use another account', 'Użyj innego konta')),
      ),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return _GateFailure(
      icon: Icons.error_outline_rounded,
      iconColor: AppColors.error,
      title: copy.text('Something went wrong', 'Coś poszło nie tak'),
      titleStyle: const TextStyle(
        color: AppImmersiveColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      message: localizedAuthError(context, error),
      messageStyle: const TextStyle(
        color: AppImmersiveColors.textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      retryLabel: copy.text('TRY AGAIN', 'SPRÓBUJ PONOWNIE'),
      onRetry: onRetry,
    );
  }
}

/// A full-screen failure of the auth gate (refine-look §8.7): the sign-in
/// chain's calm [AuthBackdrop], the real logo at 64 with its bloom, a 20 px
/// status glyph before the unchanged title, the unchanged copy and the
/// chain's gradient action ([AuthPrimaryButton]: 52 px, radius 12, full
/// width; lifted only when [liftedRetry]). Immersive dark in both themes.
///
/// Narrow: the content spans the width inside the sign-in form's 16 px
/// gutter, so the retry is as wide as the chain's other actions. Medium and
/// wide: it is capped at [maxContentWidth] and centred. Long copy or large
/// text scrolls instead of overflowing, and the title never breaks mid-word
/// ([titleScaler]).
class _GateFailure extends StatelessWidget {
  const _GateFailure({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleStyle,
    required this.message,
    required this.messageStyle,
    required this.retryLabel,
    required this.onRetry,
    this.liftedRetry = true,
    this.secondary,
  });

  static const double logoSize = 64;
  static const double iconSize = 20;
  static const double iconGap = 8;
  static const double titleLineHeight = 1.2;
  static const double maxContentWidth = 440;

  final IconData icon;
  final Color iconColor;
  final String title;
  final TextStyle titleStyle;
  final String message;
  final TextStyle messageStyle;
  final String retryLabel;
  final VoidCallback onRetry;
  final bool liftedRetry;
  final Widget? secondary;

  /// The title's text scale: the reader's own, clamped only as far as the
  /// title's longest word needs to fit [width] on one line (a narrow phone
  /// at very large text), so the heading never breaks mid-word. The message
  /// and the actions always keep the full scale (the same rule as the
  /// delete-account headline).
  static TextScaler titleScaler(
    BuildContext context, {
    required String title,
    required TextStyle style,
    required double width,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize ?? 14;
    final current = scaler.scale(fontSize) / fontSize;
    if (current <= 1) return scaler;
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final word in title.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    if (widest <= 0) return scaler;
    // One px of slack for glyph rounding at the line's end.
    final fits = (width - 1) / widest;
    if (current <= fits) return scaler;
    return scaler.clamp(maxScaleFactor: math.max(1.0, fits));
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 24);
    final content = Scaffold(
      backgroundColor: AppImmersiveColors.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final columnWidth = math.min(
                viewport.maxWidth - padding.horizontal,
                viewport.maxWidth < 600 ? double.infinity : maxContentWidth,
              );
              final resolvedTitleStyle = DefaultTextStyle.of(
                context,
              ).style.merge(titleStyle.copyWith(height: titleLineHeight));
              final scaler = titleScaler(
                context,
                title: title,
                style: resolvedTitleStyle,
                width: columnWidth - iconSize - iconGap,
              );
              final firstLine =
                  scaler.scale(resolvedTitleStyle.fontSize!) * titleLineHeight;
              final iconTop = math.max(0.0, (firstLine - iconSize) / 2);
              return SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      viewport.maxHeight - padding.vertical,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: columnWidth),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ExcludeSemantics(
                            child: YoBrandMark(
                              key: ValueKey('auth-gate-logo'),
                              size: logoSize,
                              light: YoBrandLight.bloom,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Centred on the title's first line, also when
                              // large text wraps it.
                              Padding(
                                padding: EdgeInsets.only(top: iconTop),
                                child: ExcludeSemantics(
                                  child: Icon(
                                    icon,
                                    key: const ValueKey(
                                      'auth-gate-status-icon',
                                    ),
                                    size: iconSize,
                                    color: iconColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: iconGap),
                              Flexible(
                                child: Text(
                                  title,
                                  // One line is centred with its glyph as a
                                  // unit. A title wrapped by large text is a
                                  // block as wide as its longest line whose
                                  // lines start beside the glyph, so the
                                  // glyph always leads the first word
                                  // instead of floating beside a short
                                  // first line.
                                  textAlign: TextAlign.start,
                                  textWidthBasis: TextWidthBasis.longestLine,
                                  textScaler: scaler,
                                  style: resolvedTitleStyle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: messageStyle,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: AuthPrimaryButton(
                              key: const ValueKey('auth-gate-retry'),
                              label: retryLabel,
                              loading: false,
                              onPressed: onRetry,
                              lifted: liftedRetry,
                            ),
                          ),
                          if (secondary != null) ...[
                            const SizedBox(height: 8),
                            secondary!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}
