import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/reels/presentation/navigation/reel_link_coordinator.dart';
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
          return _ProfileBootstrapErrorScreen(
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

class _ProfileBootstrapErrorScreen extends StatelessWidget {
  const _ProfileBootstrapErrorScreen({
    required this.onRetry,
    required this.onSignOut,
  });

  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final content = Scaffold(
      backgroundColor: const Color(0xFF0D0618),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFFC05CFF),
                    size: 58,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    copy.text(
                      'Finishing your profile',
                      'Kończymy konfigurację profilu',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.text(
                      'Your account is secure. Check your connection and try '
                          'again to finish setting up YO Voice.',
                      'Twoje konto jest bezpieczne. Sprawdź połączenie i spróbuj '
                          'ponownie, aby dokończyć konfigurację YO Voice.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFB8B1C8),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFA02BFF),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        copy.text('TRY AGAIN', 'SPRÓBUJ PONOWNIE'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => unawaited(onSignOut()),
                    child: Text(
                      copy.text('Use another account', 'Użyj innego konta'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final message = localizedAuthError(context, error);
    final content = Scaffold(
      backgroundColor: const Color(0xFF0D0618),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: Color(0xFFC026FF),
                ),
                const SizedBox(height: 20),
                Text(
                  copy.text('Something went wrong', 'Coś poszło nie tak'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9189A6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF6A00FF),
                          Color(0xFFA12BFF),
                          Color(0xFFC026FF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        copy.text('TRY AGAIN', 'SPRÓBUJ PONOWNIE'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}
