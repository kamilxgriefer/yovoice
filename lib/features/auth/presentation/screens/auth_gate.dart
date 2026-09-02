import 'dart:async';

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
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({
    super.key,
    this.initiallySignedOut = false,
    this.initialAuthError,
  });

  /// A route-stack reset after logout already knows the session is gone. Show
  /// LoginScreen on its first frame instead of flashing startup animation
  /// while the new Auth stream delivers its initial null value.
  final bool initiallySignedOut;

  /// Preserves an auth-stream failure while the route stack is replaced, so a
  /// private screen cannot remain above the boundary during an auth error.
  final Object? initialAuthError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final authOperationLoading = ref.watch(authLoadingProvider);
    void setRegistrationLoading(bool loading) {
      ref.read(authLoadingProvider.notifier).state = loading;
    }

    final immediateBoundary = switch (authState) {
      AsyncLoading() when initiallySignedOut => KeyedSubtree(
        key: const ValueKey('auth-signed-out'),
        child: LoginScreen(
          onRegistrationLoadingChanged: setRegistrationLoading,
        ),
      ),
      AsyncLoading() when initialAuthError != null => KeyedSubtree(
        key: const ValueKey('auth-error'),
        child: _AuthErrorScreen(
          error: initialAuthError!,
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
              child: const _AuthenticatedEntry(),
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
  const _AuthenticatedEntry();

  @override
  State<_AuthenticatedEntry> createState() => _AuthenticatedEntryState();
}

class _AuthenticatedEntryState extends State<_AuthenticatedEntry> {
  late Future<void> _profileBootstrap;
  Future<void> _pushOnboardingReadiness = Future<void>.value();

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

        return MainShell(onboardingReadiness: _pushOnboardingReadiness);
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
