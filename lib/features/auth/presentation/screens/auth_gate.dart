import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final child = authState.when<Widget>(
      loading: () => const KeyedSubtree(
        key: ValueKey('auth-loading'),
        child: StartupLoadingScreen(),
      ),
      error: (error, stackTrace) {
        return KeyedSubtree(
          key: const ValueKey('auth-error'),
          child: _AuthErrorScreen(
            message: error.toString(),
            onRetry: () {
              ref.invalidate(authStateChangesProvider);
            },
          ),
        );
      },
      data: (user) {
        if (user == null) {
          return const KeyedSubtree(
            key: ValueKey('auth-signed-out'),
            child: LoginScreen(),
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
  @override
  void initState() {
    super.initState();

    // Fire-and-forget: neither service is allowed to hold the main shell.
    unawaited(PushNotificationService.instance.initialize());

    // Seeds the Firestore profile doc once per sign-in if it doesn't
    // exist yet (ensureProfile() is a no-op for existing docs). Must run
    // before PresenceService's heartbeat has any reason to touch the doc.
    unawaited(ProfileService().ensureProfile());
  }

  @override
  Widget build(BuildContext context) {
    return const MainShell();
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const Text(
                  'Something went wrong',
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
                      child: const Text(
                        'TRY AGAIN',
                        style: TextStyle(
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
  }
}
