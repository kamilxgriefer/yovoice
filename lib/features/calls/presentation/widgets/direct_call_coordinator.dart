import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/audio/call_tone.dart';
import 'package:yovoice/core/audio/call_tone_service.dart';
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
    this.toneService,
    this.incomingRetryDelay,
    super.key,
  });

  final Widget child;
  final DirectCallGateway? callService;
  final FirebaseAuth? auth;
  final VoiceCallService? voiceService;
  final UiSoundService? soundService;
  final CallToneService? toneService;
  final Duration Function(int attempt)? incomingRetryDelay;

  @override
  State<DirectCallCoordinator> createState() => _DirectCallCoordinatorState();
}

class _DirectCallCoordinatorState extends State<DirectCallCoordinator>
    with WidgetsBindingObserver {
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final DirectCallGateway _calls =
      widget.callService ?? DirectCallService(auth: _auth);
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final UiSoundService _sounds =
      widget.soundService ?? UiSoundService.instance;
  late final CallToneService _tones =
      widget.toneService ?? defaultCallToneService;

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
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _auth.authStateChanges().listen(_handleAuth);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingRetryTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    unawaited(_tones.stop());
    DirectCallAlertRegistry.clear();
    super.dispose();
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_tones.stop());
      return;
    }
    if (_routeOpen) {
      _resumeOpenCallAlert();
      return;
    }
    final userId = _boundUserId;
    if (userId != null && _latest.isNotEmpty) {
      _handleIncoming(_latest, epoch: _identityEpoch, userId: userId);
    }
  }

  void _resumeOpenCallAlert() {
    final callId = _openCallId;
    if (!mounted ||
        !_routeOpen ||
        callId == null ||
        !_isForeground ||
        !_hasRingingSignal(callId)) {
      return;
    }
    final claim = DirectCallAlertRegistry.claim(
      callId,
      DirectCallAlertOwner.coordinator,
    );
    if (claim.ownsAlert) {
      unawaited(_playCoordinatorAlert(claim));
    } else {
      unawaited(_recoverAlertIfCompetingPathFails(claim));
    }
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
    unawaited(_tones.stop());
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

  bool _hasRingingSignal(String callId) {
    final now = DateTime.now();
    return _latest.any(
      (signal) =>
          signal.callId == callId &&
          signal.status == DirectCallStatus.ringing &&
          (signal.expiresAt == null || signal.expiresAt!.isAfter(now)),
    );
  }

  void _handleIncoming(
    List<IncomingDirectCallSignal> signals, {
    required int epoch,
    required String userId,
  }) {
    if (!_identityMatches(epoch: epoch, userId: userId)) return;
    _latest = signals;
    if (!_isForeground || _routeOpen || signals.isEmpty) return;
    final signal = signals.firstWhere(
      (item) => !_presented.contains(item.callId),
      orElse: () => signals.first,
    );
    if (_presented.contains(signal.callId)) return;
    _presented.add(signal.callId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_identityMatches(epoch: epoch, userId: userId) ||
          !_isForeground ||
          _routeOpen) {
        _presented.remove(signal.callId);
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
    if (!_identityMatches(epoch: epoch, userId: userId) || !_isForeground) {
      _presented.remove(signal.callId);
      return;
    }
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
            toneService: _tones,
            soundService: _sounds,
            currentUserId: userId,
          ),
        ),
      );
    } finally {
      await _tones.stop();
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
    if (!_hasRingingSignal(claim.callId)) {
      DirectCallAlertRegistry.complete(claim, presented: true);
      return;
    }
    if (!_isForeground ||
        !mounted ||
        !_routeOpen ||
        _openCallId != claim.callId) {
      DirectCallAlertRegistry.complete(claim, presented: false);
      return;
    }
    final result = await _tones.startWithResult(CallTone.incoming);
    if (!_hasRingingSignal(claim.callId)) {
      await _tones.stop();
      DirectCallAlertRegistry.complete(claim, presented: true);
      return;
    }
    var presented = result == CallToneStartResult.started;
    if (result == CallToneStartResult.disabled ||
        result == CallToneStartResult.failed) {
      // Preserve the existing lightweight foreground cue as a fallback when
      // looping playback is disabled or the platform audio engine cannot open.
      if (mounted && _routeOpen && _openCallId == claim.callId) {
        presented = await _sounds.playWithResult(UiSound.notification);
      }
    }
    DirectCallAlertRegistry.complete(claim, presented: presented);
  }

  Future<void> _recoverAlertIfCompetingPathFails(
    DirectCallAlertClaim competingClaim,
  ) async {
    final presented = await competingClaim.result;
    if (presented) {
      await DirectCallAlertRegistry.whenInAppToneAllowed(competingClaim.callId);
      if (mounted &&
          _isForeground &&
          _routeOpen &&
          _openCallId == competingClaim.callId &&
          _hasRingingSignal(competingClaim.callId)) {
        await _playCoordinatorAlert(competingClaim);
      }
      return;
    }
    if (!mounted || !_routeOpen || _openCallId != competingClaim.callId) {
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
