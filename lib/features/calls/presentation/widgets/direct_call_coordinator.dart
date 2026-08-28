import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/direct_call_route_registry.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';

/// App-level private-call signaling surface.
///
/// The backend mirrors only active ringing events beneath the callee's own
/// user document. This coordinator owns one subscription per signed-in
/// identity and presents exactly one route per call id. Background/terminated
/// delivery still comes through FCM and NotificationRouter; this stream is
/// what makes a call ring immediately while the app is already open.
class DirectCallCoordinator extends StatefulWidget {
  const DirectCallCoordinator({
    required this.child,
    this.callService,
    this.auth,
    this.voiceService,
    this.soundService,
    this.incomingRetryDelay,
    super.key,
  });

  final Widget child;
  final DirectCallGateway? callService;
  final FirebaseAuth? auth;
  final VoiceCallService? voiceService;
  final UiSoundService? soundService;
  final Duration Function(int attempt)? incomingRetryDelay;

  @override
  State<DirectCallCoordinator> createState() => _DirectCallCoordinatorState();
}

class _DirectCallCoordinatorState extends State<DirectCallCoordinator> {
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final DirectCallGateway _calls =
      widget.callService ?? DirectCallService(auth: _auth);
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final UiSoundService _sounds =
      widget.soundService ?? UiSoundService.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<IncomingDirectCallSignal>>? _incomingSubscription;
  Timer? _incomingRetryTimer;
  final Set<String> _presented = <String>{};
  List<IncomingDirectCallSignal> _latest = const [];
  bool _routeOpen = false;
  int _identityEpoch = 0;
  int _incomingRetryAttempt = 0;
  String? _boundUserId;
  String? _openCallId;

  @override
  void initState() {
    super.initState();
    _authSubscription = _auth.authStateChanges().listen(_handleAuth);
  }

  @override
  void dispose() {
    _incomingRetryTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    DirectCallAlertRegistry.clear();
    super.dispose();
  }

  void _handleAuth(User? user) {
    final previousUserId = _boundUserId;
    _boundUserId = user?.uid;
    final epoch = ++_identityEpoch;
    _incomingRetryTimer?.cancel();
    _incomingRetryTimer = null;
    _incomingRetryAttempt = 0;
    unawaited(_incomingSubscription?.cancel());
    _incomingSubscription = null;
    _latest = const [];
    _presented.clear();
    DirectCallAlertRegistry.clear();
    if (previousUserId != null && previousUserId != user?.uid) {
      if (_voice.isDirectCall) {
        unawaited(_voice.disconnect(playSound: false));
      }
      if (_routeOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _routeOpen && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    }
    if (user == null) return;
    _subscribeToIncomingCalls(epoch: epoch, userId: user.uid);
  }

  void _subscribeToIncomingCalls({required int epoch, required String userId}) {
    if (epoch != _identityEpoch || _boundUserId != userId) return;
    _incomingSubscription = _calls.watchIncomingCalls().listen(
      (signals) {
        if (epoch == _identityEpoch && _boundUserId == userId) {
          _incomingRetryAttempt = 0;
          _handleIncoming(signals, epoch: epoch, userId: userId);
        }
      },
      onError: (Object error) {
        debugPrint(
          'DirectCallCoordinator: incoming call subscription failed '
          '(${error.runtimeType}).',
        );
        _scheduleIncomingRetry(epoch: epoch, userId: userId);
      },
      cancelOnError: true,
    );
  }

  void _scheduleIncomingRetry({required int epoch, required String userId}) {
    if (!mounted ||
        epoch != _identityEpoch ||
        _boundUserId != userId ||
        _incomingRetryTimer != null) {
      return;
    }
    final attempt = _incomingRetryAttempt++;
    final delay =
        widget.incomingRetryDelay?.call(attempt) ??
        Duration(seconds: 1 << attempt.clamp(0, 5));
    _incomingRetryTimer = Timer(delay, () {
      _incomingRetryTimer = null;
      if (!mounted || epoch != _identityEpoch || _boundUserId != userId) {
        return;
      }
      unawaited(_incomingSubscription?.cancel());
      _incomingSubscription = null;
      _subscribeToIncomingCalls(epoch: epoch, userId: userId);
    });
  }

  bool _identityMatches({required int epoch, required String userId}) =>
      mounted && epoch == _identityEpoch && _boundUserId == userId;

  void _handleIncoming(
    List<IncomingDirectCallSignal> signals, {
    required int epoch,
    required String userId,
  }) {
    if (!_identityMatches(epoch: epoch, userId: userId)) return;
    _latest = signals;
    if (_routeOpen || signals.isEmpty) return;
    final signal = signals.firstWhere(
      (item) => !_presented.contains(item.callId),
      orElse: () => signals.first,
    );
    if (_presented.contains(signal.callId)) return;
    _presented.add(signal.callId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_identityMatches(epoch: epoch, userId: userId) || _routeOpen) {
        return;
      }
      unawaited(_present(signal, epoch: epoch, userId: userId));
    });
  }

  Future<void> _present(
    IncomingDirectCallSignal signal, {
    required int epoch,
    required String userId,
  }) async {
    // The post-frame hop creates an account-switch window. Revalidate again
    // immediately before claiming audio/route ownership so an old account can
    // never ring or navigate inside the newly signed-in identity.
    if (!_identityMatches(epoch: epoch, userId: userId)) return;
    if (!DirectCallRouteRegistry.claim(signal.callId)) return;
    _routeOpen = true;
    _openCallId = signal.callId;
    final alertClaim = DirectCallAlertRegistry.claim(
      signal.callId,
      DirectCallAlertOwner.coordinator,
    );
    if (alertClaim.ownsAlert) {
      unawaited(_playCoordinatorAlert(alertClaim));
    } else {
      unawaited(_recoverAlertIfCompetingPathFails(alertClaim));
    }
    try {
      if (!_identityMatches(epoch: epoch, userId: userId)) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DirectCallScreen(
            callId: signal.callId,
            callService: _calls,
            voiceService: _voice,
          ),
        ),
      );
    } finally {
      DirectCallRouteRegistry.release(signal.callId);
      _routeOpen = false;
      _openCallId = null;
      if (_identityMatches(epoch: epoch, userId: userId)) {
        final remaining = _latest
            .where((item) => !_presented.contains(item.callId))
            .toList(growable: false);
        if (remaining.isNotEmpty) {
          _handleIncoming(remaining, epoch: epoch, userId: userId);
        }
      }
    }
  }

  Future<void> _playCoordinatorAlert(DirectCallAlertClaim claim) async {
    final presented = await _sounds.playWithResult(UiSound.notification);
    DirectCallAlertRegistry.complete(claim, presented: presented);
  }

  Future<void> _recoverAlertIfCompetingPathFails(
    DirectCallAlertClaim competingClaim,
  ) async {
    final presented = await competingClaim.result;
    if (presented ||
        !mounted ||
        !_routeOpen ||
        _openCallId != competingClaim.callId) {
      return;
    }
    final retry = DirectCallAlertRegistry.claim(
      competingClaim.callId,
      DirectCallAlertOwner.coordinator,
    );
    if (retry.ownsAlert) await _playCoordinatorAlert(retry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
