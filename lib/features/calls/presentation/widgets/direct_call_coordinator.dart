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
    super.key,
  });

  final Widget child;
  final DirectCallGateway? callService;
  final FirebaseAuth? auth;
  final VoiceCallService? voiceService;

  @override
  State<DirectCallCoordinator> createState() => _DirectCallCoordinatorState();
}

class _DirectCallCoordinatorState extends State<DirectCallCoordinator> {
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final DirectCallGateway _calls =
      widget.callService ?? DirectCallService(auth: _auth);
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<IncomingDirectCallSignal>>? _incomingSubscription;
  final Set<String> _presented = <String>{};
  List<IncomingDirectCallSignal> _latest = const [];
  bool _routeOpen = false;
  int _identityEpoch = 0;
  String? _boundUserId;

  @override
  void initState() {
    super.initState();
    _authSubscription = _auth.authStateChanges().listen(_handleAuth);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    super.dispose();
  }

  void _handleAuth(User? user) {
    final previousUserId = _boundUserId;
    _boundUserId = user?.uid;
    final epoch = ++_identityEpoch;
    unawaited(_incomingSubscription?.cancel());
    _incomingSubscription = null;
    _latest = const [];
    _presented.clear();
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
    _incomingSubscription = _calls.watchIncomingCalls().listen(
      (signals) {
        if (epoch == _identityEpoch && _boundUserId == user.uid) {
          _handleIncoming(signals);
        }
      },
      onError: (Object error) {
        debugPrint(
          'DirectCallCoordinator: incoming call subscription failed '
          '(${error.runtimeType}).',
        );
      },
    );
  }

  void _handleIncoming(List<IncomingDirectCallSignal> signals) {
    _latest = signals;
    if (_routeOpen || signals.isEmpty) return;
    final signal = signals.firstWhere(
      (item) => !_presented.contains(item.callId),
      orElse: () => signals.first,
    );
    if (_presented.contains(signal.callId)) return;
    _presented.add(signal.callId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _routeOpen) return;
      unawaited(_present(signal));
    });
  }

  Future<void> _present(IncomingDirectCallSignal signal) async {
    if (!DirectCallRouteRegistry.claim(signal.callId)) return;
    _routeOpen = true;
    unawaited(UiSoundService.instance.play(UiSound.notification));
    try {
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
      if (mounted) {
        final remaining = _latest
            .where((item) => !_presented.contains(item.callId))
            .toList(growable: false);
        if (remaining.isNotEmpty) _handleIncoming(remaining);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
