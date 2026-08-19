import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PresenceService {
  PresenceService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> setOnline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Presence must only ever touch presence fields. This used to also
    // seed displayName/email/photoUrl from FirebaseAuth's `user` object --
    // but that object is a separate, sometimes-stale source of truth from
    // the Firestore profile doc (ProfileService is authoritative there).
    // Since this heartbeat runs unconditionally every 45s and on every app
    // resume, writing those fields here silently overwrote real profile
    // edits (e.g. a freshly-uploaded avatar) with whatever FirebaseAuth's
    // cached user.photoURL happened to be. The profile doc's initial
    // identity fields are seeded once by ProfileService.ensureProfile()
    // instead (called from AuthGate on sign-in), not on every heartbeat.
    await _firestore.collection('users').doc(user.uid).set({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'presenceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks [userId] offline.
  ///
  /// This is an owner-authenticated write: `firestore.rules` gates
  /// `users/{userId}` updates on `isSignedIn() && isOwner(userId)`. It
  /// therefore only succeeds while [userId]'s own session is still live —
  /// which is why the sign-out path calls it from inside
  /// `AuthService.signOut()`, *before* `FirebaseAuth.signOut()`, rather than
  /// from an auth-state listener that fires after the session is gone.
  Future<void> setOfflineForUser(String userId) async {
    await _firestore.collection('users').doc(userId).set({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
      'presenceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class PresenceLifecycle extends StatefulWidget {
  const PresenceLifecycle({required this.child, super.key});

  final Widget child;

  @override
  State<PresenceLifecycle> createState() => _PresenceLifecycleState();
}

class _PresenceLifecycleState extends State<PresenceLifecycle>
    with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();

  StreamSubscription<User?>? _authSubscription;
  Timer? _offlineTimer;
  Timer? _heartbeatTimer;

  String? _activeUserId;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthStateChanged,
    );
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    _offlineTimer?.cancel();

    if (user == null) {
      // Deliberately no offline write here, and none in the account-switch
      // case below either. Both used to attempt one and both were denied
      // 100% of the time: `firestore.rules` gates users/{uid} updates on
      // `isSignedIn() && isOwner(uid)`, and by the time authStateChanges
      // reports null the session is already cleared (isSignedIn() false),
      // while a switch writes a *previous* uid under a new identity
      // (isOwner() false). The failures were swallowed to a debugPrint, so
      // signed-out accounts kept showing as "Online" to their friends
      // indefinitely. AuthService.signOut() now performs that write while
      // the session is still live — see the comment on signOut().
      _activeUserId = null;
      _stopHeartbeat();
      return;
    }

    _activeUserId = user.uid;

    if (_isForeground) {
      await _safeSetOnline();
      _startHeartbeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isForeground = true;
        _offlineTimer?.cancel();
        _safeSetOnline();
        _startHeartbeat();
        break;
      case AppLifecycleState.inactive:
        _scheduleOfflineUpdate();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isForeground = false;
        _offlineTimer?.cancel();
        _stopHeartbeat();
        final userId = _activeUserId;
        if (userId != null) {
          _safeSetOffline(userId);
        }
        break;
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    if (_activeUserId == null || !_isForeground) return;

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _safeSetOnline(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleOfflineUpdate() {
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(seconds: 3), () {
      if (!_isForeground) {
        final userId = _activeUserId;
        if (userId != null) {
          _safeSetOffline(userId);
        }
      }
    });
  }

  Future<void> _safeSetOnline() async {
    if (_activeUserId == null) return;

    try {
      await _presenceService.setOnline();
    } catch (error, stackTrace) {
      debugPrint('Could not set user online: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _safeSetOffline(String userId) async {
    try {
      await _presenceService.setOfflineForUser(userId);
    } catch (error, stackTrace) {
      debugPrint('Could not set user offline: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    _stopHeartbeat();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
