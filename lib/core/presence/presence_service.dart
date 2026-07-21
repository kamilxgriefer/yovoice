import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PresenceService {
  PresenceService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>>? get _currentUserDocument {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    return _firestore.collection('users').doc(user.uid);
  }

  Future<void> setOnline() async {
    final user = _auth.currentUser;
    final document = _currentUserDocument;

    if (user == null || document == null) {
      return;
    }

    final fallbackName = user.email?.split('@').first ?? 'YoVoice user';
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : fallbackName;

    await document.set({
      'displayName': displayName,
      'email': user.email?.trim().toLowerCase(),
      'photoUrl': user.photoURL,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'presenceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setOffline() async {
    final document = _currentUserDocument;

    if (document == null) {
      return;
    }

    await document.set({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
      'presenceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class PresenceLifecycle extends StatefulWidget {
  const PresenceLifecycle({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<PresenceLifecycle> createState() => _PresenceLifecycleState();
}

class _PresenceLifecycleState extends State<PresenceLifecycle>
    with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();

  StreamSubscription<User?>? _authSubscription;
  Timer? _offlineTimer;
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
      _activeUserId = null;
      return;
    }

    _activeUserId = user.uid;

    if (_isForeground) {
      await _safeSetOnline();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isForeground = true;
        _offlineTimer?.cancel();
        _safeSetOnline();
        break;

      case AppLifecycleState.inactive:
        _scheduleOfflineUpdate();
        break;

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isForeground = false;
        _offlineTimer?.cancel();
        _safeSetOffline();
        break;
    }
  }

  void _scheduleOfflineUpdate() {
    _offlineTimer?.cancel();

    _offlineTimer = Timer(
      const Duration(seconds: 3),
      () {
        if (!_isForeground) {
          _safeSetOffline();
        }
      },
    );
  }

  Future<void> _safeSetOnline() async {
    if (_activeUserId == null) {
      return;
    }

    try {
      await _presenceService.setOnline();
    } catch (error, stackTrace) {
      debugPrint('Could not set user online: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _safeSetOffline() async {
    if (_activeUserId == null) {
      return;
    }

    try {
      await _presenceService.setOffline();
    } catch (error, stackTrace) {
      debugPrint('Could not set user offline: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
