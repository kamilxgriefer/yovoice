import 'dart:async';

import 'package:flutter/material.dart';

enum AuthRouteResetReason { signedOut, principalChanged, authError }

@immutable
class AuthRouteResetTarget {
  const AuthRouteResetTarget._({required this.reason, this.userId, this.error});

  const AuthRouteResetTarget.signedOut()
    : this._(reason: AuthRouteResetReason.signedOut);

  const AuthRouteResetTarget.principalChanged(String userId)
    : this._(reason: AuthRouteResetReason.principalChanged, userId: userId);

  AuthRouteResetTarget.authError(Object error)
    : this._(reason: AuthRouteResetReason.authError, error: error);

  final AuthRouteResetReason reason;
  final String? userId;
  final Object? error;
}

typedef AuthResetRouteFactory =
    Route<void> Function(AuthRouteResetTarget target);

/// Enforces a fresh root route whenever the authenticated principal changes.
///
/// AuthGate is the body of the first route, so changing its child cannot
/// remove Profile, Settings, chat or room routes pushed above it. This
/// coordinator lives above that navigator and replaces the entire route stack
/// on an auth epoch transition. `pushAndRemoveUntil` deliberately does not
/// consult route pop vetoes: a private route may never outlive its session.
class AuthEpochRouteResetter {
  AuthEpochRouteResetter({
    required this.navigatorKey,
    required this.routeFactory,
    this.onPrincipalExit,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final AuthResetRouteFactory routeFactory;
  final VoidCallback? onPrincipalExit;

  bool _hasInitialPrincipal = false;
  String? _currentUserId;
  AuthRouteResetTarget? _pendingTarget;
  bool _postFrameResetScheduled = false;

  void handlePrincipal(String? userId) {
    if (!_hasInitialPrincipal) {
      _hasInitialPrincipal = true;
      _currentUserId = userId;
      return;
    }
    if (_currentUserId == userId) return;

    final previousUserId = _currentUserId;
    _currentUserId = userId;
    if (previousUserId == null && userId != null) {
      // Login/Register are already inside AuthGate. Let that boundary advance
      // naturally so registration can keep its intentional Verify Email flow
      // instead of having a root reset tear the route away.
      return;
    }
    _runPrincipalExitCleanup();
    _replaceStack(
      userId == null
          ? const AuthRouteResetTarget.signedOut()
          : AuthRouteResetTarget.principalChanged(userId),
    );
  }

  void handleError(Object error, StackTrace stackTrace) {
    if (_currentUserId != null) _runPrincipalExitCleanup();
    _replaceStack(AuthRouteResetTarget.authError(error));
  }

  void _runPrincipalExitCleanup() {
    try {
      onPrincipalExit?.call();
    } catch (error) {
      debugPrint(
        'AuthEpochRouteResetter: local session cleanup failed '
        '(${error.runtimeType}); route isolation continues.',
      );
    }
  }

  void _replaceStack(AuthRouteResetTarget target) {
    final navigator = navigatorKey.currentState;
    if (navigator != null && navigator.mounted) {
      _pendingTarget = null;
      unawaited(
        navigator.pushAndRemoveUntil<void>(
          routeFactory(target),
          (route) => false,
        ),
      );
      return;
    }

    // A cold-start auth emission can beat MaterialApp's first Navigator
    // frame. Keep only the newest epoch and commit it as soon as the root
    // navigator exists.
    _pendingTarget = target;
    if (_postFrameResetScheduled) return;
    _postFrameResetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameResetScheduled = false;
      final pending = _pendingTarget;
      if (pending == null) return;
      _replaceStack(pending);
    });
  }
}
