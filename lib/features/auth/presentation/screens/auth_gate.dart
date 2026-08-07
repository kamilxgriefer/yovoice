import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yovoice/features/auth/presentation/screens/login_screen.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () => const _AuthLoadingScreen(),
      error: (error, stackTrace) {
        return _AuthErrorScreen(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(authStateChangesProvider);
          },
        );
      },
      data: (user) {
        if (user == null) {
          return const LoginScreen();
        }

        return const _AuthenticatedEntry();
      },
    );
  }
}

class _AuthenticatedEntry extends StatefulWidget {
  const _AuthenticatedEntry();

  @override
  State<_AuthenticatedEntry> createState() => _AuthenticatedEntryState();
}

class _AuthenticatedEntryState extends State<_AuthenticatedEntry> {
  Timer? _welcomeTimer;
  bool _showMainShell = false;

  @override
  void initState() {
    super.initState();

    // Fire-and-forget: push is a nice-to-have, never something the welcome
    // animation or main shell should wait on.
    unawaited(PushNotificationService.instance.initialize());

    // Seeds the Firestore profile doc once per sign-in if it doesn't
    // exist yet (ensureProfile() is a no-op for existing docs). Must run
    // before PresenceService's heartbeat has any reason to touch the doc.
    unawaited(ProfileService().ensureProfile());

    _welcomeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showMainShell = true;
      });
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(opacity: fadeAnimation, child: child);
      },
      child: _showMainShell
          ? const MainShell(key: ValueKey('main-shell'))
          : const _WelcomeScreen(key: ValueKey('welcome-screen')),
    );
  }
}

class _WelcomeScreen extends StatefulWidget {
  const _WelcomeScreen({super.key});

  @override
  State<_WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<_WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _logoEntranceAnimation;
  late final Animation<double> _logoPulseAnimation;
  late final Animation<double> _contentOpacityAnimation;
  late final Animation<Offset> _contentSlideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _logoEntranceAnimation = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0, 0.3, curve: Curves.easeOutBack),
      ),
    );

    _logoPulseAnimation =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1,
              end: 1.035,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.035,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 50,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.3, 1, curve: Curves.easeInOut),
          ),
        );

    _contentOpacityAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.18, 0.55, curve: Curves.easeOut),
    );

    _contentSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.18, 0.55, curve: Curves.easeOutCubic),
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0618),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _WelcomeBackground(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale:
                              _logoEntranceAnimation.value *
                              _logoPulseAnimation.value,
                          child: Opacity(
                            opacity: _contentOpacityAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: const _WelcomeLogo(),
                    ),
                    const SizedBox(height: 30),
                    FadeTransition(
                      opacity: _contentOpacityAnimation,
                      child: SlideTransition(
                        position: _contentSlideAnimation,
                        child: const Column(
                          children: [
                            Text(
                              'Welcome to YoVoice',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Connect, speak, be you.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF9189A6),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeLogo extends StatelessWidget {
  const _WelcomeLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Image.asset(
        'assets/images/yo_voice_logo_reference.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.record_voice_over_rounded,
            color: Color(0xFFC026FF),
            size: 82,
          );
        },
      ),
    );
  }
}

class _WelcomeBackground extends StatelessWidget {
  const _WelcomeBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0D0618)),
        Positioned(
          top: -170,
          left: -130,
          child: Container(
            width: 420,
            height: 420,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x336A00FF), Color(0x006A00FF)],
              ),
            ),
          ),
        ),
        Positioned(
          right: -150,
          bottom: -190,
          child: Container(
            width: 460,
            height: 460,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x30C026FF), Color(0x00C026FF)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D0618),
      body: Center(child: CircularProgressIndicator(color: Color(0xFFA12BFF))),
    );
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
