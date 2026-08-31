import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class DirectCallScreen extends StatefulWidget {
  const DirectCallScreen({
    required this.callId,
    this.callService,
    this.voiceService,
    this.currentUserId,
    this.participantName,
    super.key,
  });

  final String callId;
  final DirectCallGateway? callService;
  final VoiceCallService? voiceService;
  final String? currentUserId;
  final String? participantName;

  @override
  State<DirectCallScreen> createState() => _DirectCallScreenState();
}

class _DirectCallScreenState extends State<DirectCallScreen>
    with SingleTickerProviderStateMixin {
  late final DirectCallGateway _calls =
      widget.callService ?? DirectCallService();
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final Stream<DirectCall> _call = _calls.watchCall(widget.callId);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  Timer? _clock;
  Timer? _closeTimer;
  DirectCall? _latest;
  DirectCallStatus? _lastHandledStatus;
  bool _actionBusy = false;
  bool _joinRequested = false;
  int _elapsedSeconds = 0;

  String get _currentUserId {
    final injected = widget.currentUserId?.trim();
    if (injected?.isNotEmpty == true) return injected!;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  String get _participantName {
    final injected = widget.participantName?.trim();
    if (injected?.isNotEmpty == true) return injected!;
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName?.isNotEmpty == true) return displayName!;
    return user?.email?.split('@').first ?? 'YO Voice user';
  }

  @override
  void initState() {
    super.initState();
    _voice.addListener(_refresh);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _closeTimer?.cancel();
    _pulse.dispose();
    _voice.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _handleCall(DirectCall call) {
    _latest = call;
    if (_lastHandledStatus == call.status) return;
    _lastHandledStatus = call.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (call.status) {
        case DirectCallStatus.active:
          _startClock(call);
          if (!_joinRequested) unawaited(_connect(call));
        case DirectCallStatus.ringing:
          break;
        case DirectCallStatus.declined:
        case DirectCallStatus.cancelled:
        case DirectCallStatus.ended:
        case DirectCallStatus.missed:
          _clock?.cancel();
          if (_voice.directCallId == call.id) {
            unawaited(_voice.disconnect(playSound: true));
          }
          _closeTimer ??= Timer(const Duration(milliseconds: 1500), () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
      }
    });
  }

  void _startClock(DirectCall call) {
    _clock?.cancel();
    void update() {
      if (!mounted) return;
      final start = call.answeredAt ?? DateTime.now();
      setState(() {
        _elapsedSeconds = DateTime.now()
            .difference(start)
            .inSeconds
            .clamp(0, 8 * 60 * 60);
      });
    }

    update();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _connect(DirectCall call) async {
    _joinRequested = true;
    final contact = call.otherIdentity(_currentUserId);
    try {
      await _voice.joinDirectCall(
        callId: call.id,
        contactName: contact.displayName,
        participantName: _participantName,
      );
    } catch (error) {
      _joinRequested = false;
      if (!mounted) return;
      _showError(
        friendlyErrorMessage(
          error,
          fallback: 'Could not connect this private voice call.',
        ),
      );
    }
  }

  Future<void> _accept() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _calls.accept(widget.callId);
    } catch (error) {
      if (mounted) {
        _showError(
          friendlyErrorMessage(error, fallback: 'Could not answer this call.'),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _finish() async {
    final call = _latest;
    if (call == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      switch (call.status) {
        case DirectCallStatus.ringing:
          if (call.isIncomingFor(_currentUserId)) {
            await _calls.decline(call.id);
          } else {
            await _calls.cancel(call.id);
          }
        case DirectCallStatus.active:
          await _calls.end(call.id);
        case DirectCallStatus.declined:
        case DirectCallStatus.cancelled:
        case DirectCallStatus.ended:
        case DirectCallStatus.missed:
          break;
      }
      if (_voice.directCallId == call.id) {
        await _voice.disconnect(playSound: true);
      }
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showError(
          friendlyErrorMessage(error, fallback: 'Could not end this call.'),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _durationLabel() {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final content = StreamBuilder<DirectCall>(
      stream: _call,
      builder: (context, snapshot) {
        final call = snapshot.data;
        if (call != null) _handleCall(call);
        final canPop = call?.status.isTerminal ?? false;
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_finish());
          },
          child: Scaffold(
            backgroundColor: AppImmersiveColors.background,
            body: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.28),
                  radius: 1.05,
                  colors: [Color(0xFF2A0B49), AppImmersiveColors.background],
                  stops: [0, .72],
                ),
              ),
              child: SafeArea(
                child: snapshot.hasError
                    ? _CallFailure(onClose: () => Navigator.of(context).pop())
                    : call == null
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.secondary,
                        ),
                      )
                    : _buildCall(context, call),
              ),
            ),
          ),
        );
      },
    );
    return YoImmersiveDarkSurface(child: content);
  }

  Widget _buildCall(BuildContext context, DirectCall call) {
    final incoming = call.isIncomingFor(_currentUserId);
    final contact = call.otherIdentity(_currentUserId);
    final active = call.status == DirectCallStatus.active;
    final status = _statusText(call, incoming);
    final connected = _voice.isConnected && _voice.directCallId == call.id;

    return ResponsiveContentFrame(
      width: ResponsiveContentWidth.form,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _actionBusy ? null : _finish,
              tooltip: active ? 'End call and close' : 'Close call',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
              color: AppImmersiveColors.textPrimary,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final pulse = active ? 0.15 : _pulse.value;
                        return Container(
                          padding: EdgeInsets.all(18 + pulse * 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: .08),
                            border: Border.all(
                              color: AppColors.secondary.withValues(
                                alpha: .22 + pulse * .28,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary.withValues(
                                  alpha: .13 + pulse * .16,
                                ),
                                blurRadius: 32 + pulse * 24,
                                spreadRadius: pulse * 7,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: _CallAvatar(identity: contact, size: 138),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      contact.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppImmersiveColors.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        active && connected ? _durationLabel() : status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active && connected
                              ? AppColors.success
                              : AppImmersiveColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (active && !connected) ...[
                      const SizedBox(height: 18),
                      const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _CallControls(
            call: call,
            incoming: incoming,
            connected: connected,
            actionBusy: _actionBusy,
            muted: _voice.isMuted,
            muteBusy: _voice.muteChangeInProgress,
            connectionFailed: _voice.status == VoiceCallStatus.failed,
            onAccept: _accept,
            onFinish: _finish,
            onMute: _voice.toggleMute,
            onRetry: () => _connect(call),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  String _statusText(DirectCall call, bool incoming) {
    return switch (call.status) {
      DirectCallStatus.ringing => incoming ? 'Incoming voice call' : 'Calling…',
      DirectCallStatus.active =>
        _voice.status == VoiceCallStatus.failed
            ? _voice.errorMessage ?? 'Connection failed'
            : 'Connecting securely…',
      DirectCallStatus.declined => 'Call declined',
      DirectCallStatus.cancelled => 'Call cancelled',
      DirectCallStatus.ended => 'Call ended',
      DirectCallStatus.missed => 'Missed call',
    };
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.identity, required this.size});

  final DirectCallIdentity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = identity.displayName.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondary, AppColors.primary],
        ),
      ),
      child: identity.photoUrl == null
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: AppImmersiveColors.textPrimary,
                  fontSize: size * .38,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : Image.network(
              identity.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: AppImmersiveColors.textPrimary,
                    fontSize: size * .38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.call,
    required this.incoming,
    required this.connected,
    required this.actionBusy,
    required this.muted,
    required this.muteBusy,
    required this.connectionFailed,
    required this.onAccept,
    required this.onFinish,
    required this.onMute,
    required this.onRetry,
  });

  final DirectCall call;
  final bool incoming;
  final bool connected;
  final bool actionBusy;
  final bool muted;
  final bool muteBusy;
  final bool connectionFailed;
  final VoidCallback onAccept;
  final VoidCallback onFinish;
  final VoidCallback onMute;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (call.status.isTerminal) return const SizedBox(height: 88);
    if (call.status == DirectCallStatus.ringing && incoming) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 42,
        runSpacing: 18,
        children: [
          _RoundCallAction(
            label: 'Decline',
            icon: Icons.call_end_rounded,
            color: AppColors.error,
            onPressed: actionBusy ? null : onFinish,
          ),
          _RoundCallAction(
            label: 'Answer',
            icon: Icons.call_rounded,
            color: AppColors.success,
            onPressed: actionBusy ? null : onAccept,
          ),
        ],
      );
    }
    if (call.status == DirectCallStatus.ringing) {
      return Center(
        child: _RoundCallAction(
          label: 'Cancel',
          icon: Icons.call_end_rounded,
          color: AppColors.error,
          onPressed: actionBusy ? null : onFinish,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 42,
      runSpacing: 18,
      children: [
        if (connectionFailed)
          _RoundCallAction(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            color: AppImmersiveColors.surfaceRaised,
            foregroundColor: AppImmersiveColors.textPrimary,
            onPressed: actionBusy ? null : onRetry,
          )
        else
          _RoundCallAction(
            label: muted ? 'Unmute' : 'Mute',
            icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: AppImmersiveColors.surfaceRaised,
            foregroundColor: AppImmersiveColors.textPrimary,
            onPressed: !connected || muteBusy ? null : onMute,
          ),
        _RoundCallAction(
          label: 'End',
          icon: Icons.call_end_rounded,
          color: AppColors.error,
          onPressed: actionBusy ? null : onFinish,
        ),
      ],
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.foregroundColor = AppImmersiveColors.textPrimary,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            onPressed: onPressed,
            tooltip: label,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(70),
              backgroundColor: color,
              foregroundColor: foregroundColor,
              disabledBackgroundColor: color.withValues(alpha: .35),
              disabledForegroundColor: foregroundColor.withValues(alpha: .6),
            ),
            icon: Icon(icon, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppImmersiveColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallFailure extends StatelessWidget {
  const _CallFailure({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.phone_disabled_rounded,
              size: 52,
              color: AppImmersiveColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'This call is no longer available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppImmersiveColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
