import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final DirectCallGateway _calls =
      widget.callService ?? DirectCallService();
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final Stream<DirectCall> _call = _calls.watchCall(widget.callId);
  late final AnimationController _pulse;

  Timer? _clock;
  Timer? _closeTimer;
  DirectCall? _latest;
  DirectCallStatus? _lastHandledStatus;
  bool _actionBusy = false;
  bool _finishRequested = false;
  bool _joinRequested = false;
  bool _locallyAccepted = false;
  bool _connectionInterrupted = false;
  bool _terminalDisconnectPending = false;
  bool _cameraPausedInBackground = false;
  int _elapsedSeconds = 0;
  late VoiceCallStatus _lastVoiceStatus;

  bool get _connectionNeedsRetry =>
      _voice.status == VoiceCallStatus.failed || _connectionInterrupted;

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
    return user?.email?.split('@').first ??
        AppLocalizations.of(
          context,
        ).text('YO Voice user', 'Użytkownik YO Voice');
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState == null || lifecycleState == AppLifecycleState.resumed) {
      _voice.resumeAfterBackground();
    } else {
      // A route may be created from a notification while the app is still
      // inactive. Record that state before any accepted-call join can request
      // camera permission.
      unawaited(_pauseCameraForBackground());
    }
    _lastVoiceStatus = _voice.status;
    _voice.addListener(_refresh);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _closeTimer?.cancel();
    _pulse.dispose();
    _voice.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_voice.isVideoCall || _latest?.isVideo == true) {
          _cameraPausedInBackground =
              _voice.isCameraEnabled ||
              _voice.cameraChangeInProgress ||
              _voice.status == VoiceCallStatus.connecting;
        }
        // Always record the lifecycle transition in the service. The first
        // video permission Future may still be in flight before isVideoCall
        // becomes observable here.
        unawaited(_pauseCameraForBackground());
      case AppLifecycleState.resumed:
        _voice.resumeAfterBackground();
        if (_cameraPausedInBackground) {
          _cameraPausedInBackground = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showError(
                AppLocalizations.of(context).text(
                  'Camera stayed off after returning to the app.',
                  'Po powrocie do aplikacji kamera pozostała wyłączona.',
                ),
              );
            }
          });
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _pauseCameraForBackground() async {
    try {
      await _voice.pauseCameraForBackground();
    } catch (_) {
      // A concurrent hang-up/disconnect already closes the media session.
      // Lifecycle cleanup must never surface an unhandled async exception.
    }
  }

  void _refresh() {
    final nextStatus = _voice.status;
    final terminalDisconnect =
        _joinRequested &&
        _latest?.status == DirectCallStatus.active &&
        nextStatus == VoiceCallStatus.disconnected &&
        _lastVoiceStatus != VoiceCallStatus.disconnected;
    if (terminalDisconnect) {
      if (_actionBusy) {
        // The authoritative active snapshot can connect media before Answer's
        // callable returns. Preserve a terminal SDK disconnect from that
        // window and reconcile it as soon as the user action completes.
        _terminalDisconnectPending = true;
      } else {
        _markConnectionInterrupted();
      }
    } else if (nextStatus == VoiceCallStatus.connected) {
      _terminalDisconnectPending = false;
      _connectionInterrupted = false;
    }
    _lastVoiceStatus = nextStatus;
    if (mounted) setState(() {});
  }

  void _markConnectionInterrupted() {
    _terminalDisconnectPending = false;
    _joinRequested = false;
    _connectionInterrupted = true;
  }

  void _completeBusyAction() {
    if (!mounted) return;
    setState(() {
      _actionBusy = false;
      if (_terminalDisconnectPending) {
        final callStillActive = _latest?.status == DirectCallStatus.active;
        if (_joinRequested &&
            callStillActive &&
            _voice.status == VoiceCallStatus.disconnected) {
          _markConnectionInterrupted();
        } else {
          _terminalDisconnectPending = false;
        }
      }
    });
  }

  bool _needsExplicitIncomingJoin(DirectCall call) {
    final connected = _voice.isConnected && _voice.directCallId == call.id;
    return call.status == DirectCallStatus.active &&
        call.isIncomingFor(_currentUserId) &&
        !_locallyAccepted &&
        !_joinRequested &&
        !connected;
  }

  void _handleCall(DirectCall call) {
    _latest = call;
    if (_lastHandledStatus == call.status) return;
    _lastHandledStatus = call.status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (call.status) {
        case DirectCallStatus.active:
          if (_finishRequested) {
            // A remote Answer can arrive while the caller's Cancel request is
            // pending. The local finishing intent is authoritative for media:
            // never join or reopen mic/camera after that user gesture.
            if (_voice.directCallId == call.id) {
              unawaited(_voice.disconnect(playSound: false));
            }
            return;
          }
          if (call.isIncomingFor(_currentUserId) && !_locallyAccepted) {
            // Another installation of this account may have answered. Never
            // auto-join it (and therefore never open this device's mic) without
            // the local Answer gesture that created the server binding.
            _startClock(call);
            return;
          }
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

  Future<void> _connect(DirectCall call, {bool? enableCamera}) async {
    if (_finishRequested) return;
    _joinRequested = true;
    _connectionInterrupted = false;
    final contact = call.otherIdentity(_currentUserId);
    try {
      await _voice.joinDirectCall(
        callId: call.id,
        contactName: contact.displayName,
        participantName: _participantName,
        enableCamera: enableCamera ?? call.isVideo,
      );
      if (_finishRequested && _voice.directCallId == call.id) {
        await _voice.disconnect(playSound: false);
      }
    } catch (error) {
      _joinRequested = false;
      if (_finishRequested) return;
      if (!mounted) return;
      _showError(
        _friendlyError(
          error,
          english: 'Could not connect this private voice call.',
          polish: 'Nie udało się połączyć rozmowy prywatnej.',
        ),
      );
    }
  }

  Future<void> _accept() async {
    if (_actionBusy || _finishRequested) return;
    final call = _latest;
    if (call == null) return;
    setState(() => _actionBusy = true);
    try {
      final acceptedMedia = await _prepareMediaPermissions(
        includeCamera: call.isVideo,
      );
      if (acceptedMedia == null || _finishRequested) return;
      final acceptedStatus = await _calls.accept(
        widget.callId,
        mediaType: acceptedMedia,
      );
      if (_finishRequested || acceptedStatus != DirectCallStatus.active) {
        return;
      }
      // An active snapshot can belong to another installation of this same
      // account. Only the validated, installation-bound callable response
      // above authorises this device to open its local media session.
      _locallyAccepted = true;
      final latest = _latest;
      if (latest?.status == DirectCallStatus.active && !_joinRequested) {
        await _connect(
          latest!,
          enableCamera: acceptedMedia == DirectCallMediaType.video,
        );
      }
    } catch (error) {
      _locallyAccepted = false;
      if (mounted) {
        _showError(
          _friendlyError(
            error,
            english: 'Could not answer this call.',
            polish: 'Nie udało się odebrać połączenia.',
          ),
        );
      }
    } finally {
      _completeBusyAction();
    }
  }

  Future<void> _finish() async {
    final call = _latest;
    if (call == null || _actionBusy) return;
    _finishRequested = true;
    setState(() => _actionBusy = true);
    try {
      // Privacy is local-first: an offline or slow callable must never leave
      // microphone/camera capture running after the user taps End.
      if (_voice.directCallId == call.id) {
        await _voice.disconnect(playSound: true);
      }
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
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showError(
          _friendlyError(
            error,
            english: 'Could not end this call.',
            polish: 'Nie udało się zakończyć połączenia.',
          ),
        );
      }
    } finally {
      _completeBusyAction();
    }
  }

  Future<void> _toggleMute() async {
    try {
      await _voice.toggleMute();
    } catch (error) {
      if (mounted) {
        _showError(
          _friendlyError(
            error,
            english: 'Could not update the mic.',
            polish: 'Nie udało się zmienić ustawienia mikrofonu.',
          ),
        );
      }
    }
  }

  Future<void> _toggleCamera() async {
    try {
      if (!_voice.isCameraEnabled &&
          await _prepareMediaPermissions(includeCamera: true) == null) {
        return;
      }
      await _voice.toggleCamera();
    } catch (error) {
      if (mounted) {
        _showError(
          AppLocalizations.of(context).isPolish
              ? 'Nie udało się zmienić ustawienia kamery.'
              : _voice.cameraIssue ??
                    friendlyErrorMessage(
                      error,
                      fallback: 'Could not update the camera.',
                    ),
        );
      }
    }
  }

  Future<void> _flipCamera() async {
    try {
      await _voice.flipCamera();
    } catch (error) {
      if (mounted) {
        _showError(
          AppLocalizations.of(context).isPolish
              ? 'Nie udało się przełączyć kamery.'
              : _voice.cameraIssue ??
                    friendlyErrorMessage(
                      error,
                      fallback: 'Could not switch the camera.',
                    ),
        );
      }
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      await _voice.toggleSpeaker();
    } catch (error) {
      if (mounted) {
        _showError(
          _friendlyError(
            error,
            english: 'Could not change the audio output.',
            polish: 'Nie udało się zmienić wyjścia dźwięku.',
          ),
        );
      }
    }
  }

  Future<void> _retryConnect(DirectCall call) async {
    if (_finishRequested) return;
    final preparedMedia = await _prepareMediaPermissions(
      includeCamera: call.isVideo,
    );
    if (preparedMedia == null || _finishRequested) {
      return;
    }
    _connectionInterrupted = false;
    await _connect(
      call,
      enableCamera: preparedMedia == DirectCallMediaType.video,
    );
  }

  Future<void> _continueIncomingCall(DirectCall call) async {
    if (_actionBusy || _joinRequested || _finishRequested) return;
    setState(() => _actionBusy = true);
    try {
      final preparedMedia = await _prepareMediaPermissions(
        includeCamera: call.isVideo,
      );
      if (preparedMedia == null || _finishRequested) return;
      await _connect(
        call,
        enableCamera: preparedMedia == DirectCallMediaType.video,
      );
    } finally {
      _completeBusyAction();
    }
  }

  Future<DirectCallMediaType?> _prepareMediaPermissions({
    required bool includeCamera,
  }) async {
    final snapshot = await _voice.prepareMediaPermissionsFromUserGesture(
      includeCamera: includeCamera,
    );
    final microphone = snapshot[AppPermissionKind.microphone];
    if (!microphone.isUsable) {
      if (mounted) {
        _showError(
          AppLocalizations.of(context).text(
            'Allow microphone access in system settings before joining the call.',
            'Zezwól na dostęp do mikrofonu w ustawieniach systemowych, zanim dołączysz do połączenia.',
          ),
        );
      }
      return null;
    }
    if (includeCamera &&
        !snapshot[AppPermissionKind.camera].isUsable &&
        mounted) {
      _showError(
        AppLocalizations.of(context).text(
          'Camera access is off. The call will continue with audio only.',
          'Dostęp do aparatu jest wyłączony. Połączenie będzie kontynuowane tylko z dźwiękiem.',
        ),
      );
    }
    return includeCamera && snapshot[AppPermissionKind.camera].isUsable
        ? DirectCallMediaType.video
        : DirectCallMediaType.audio;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(
    Object error, {
    required String english,
    required String polish,
  }) {
    final copy = AppLocalizations.of(context);
    if (error is DirectCallInstallationBindingException) {
      return copy.text(
        'This call is active on another device. Continue there.',
        'To połączenie jest aktywne na innym urządzeniu. Kontynuuj na nim.',
      );
    }
    return copy.isPolish
        ? polish
        : friendlyErrorMessage(error, fallback: english);
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
        final passiveIncoming =
            call != null && _needsExplicitIncomingJoin(call);
        final canPop =
            (call?.status.isTerminal ?? false) ||
            (passiveIncoming && !_actionBusy);
        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !passiveIncoming) unawaited(_finish());
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
    final copy = AppLocalizations.of(context);
    final incoming = call.isIncomingFor(_currentUserId);
    final contact = call.otherIdentity(_currentUserId);
    final active = call.status == DirectCallStatus.active;
    final status = _statusText(call, incoming);
    final connected = _voice.isConnected && _voice.directCallId == call.id;
    final needsExplicitIncomingJoin = _needsExplicitIncomingJoin(call);

    if (needsExplicitIncomingJoin) {
      return _buildExplicitIncomingJoin(context, call: call, contact: contact);
    }

    if (call.isVideo && active) {
      return _buildActiveVideoCall(
        context,
        call: call,
        contact: contact,
        connected: connected,
      );
    }

    return ResponsiveContentFrame(
      width: ResponsiveContentWidth.form,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _actionBusy ? null : _finish,
              tooltip: active
                  ? copy.text('End call and close', 'Zakończ i zamknij')
                  : copy.text('Close call', 'Zamknij połączenie'),
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
            speakerPreferred: _voice.isSpeakerPreferred,
            speakerBusy: _voice.speakerChangeInProgress,
            canSwitchSpeaker: _voice.canSwitchSpeakerphone,
            connectionFailed: _connectionNeedsRetry,
            onAccept: _accept,
            onFinish: _finish,
            onMute: _toggleMute,
            onSpeaker: _toggleSpeaker,
            onRetry: () => unawaited(_retryConnect(call)),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildExplicitIncomingJoin(
    BuildContext context, {
    required DirectCall call,
    required DirectCallIdentity contact,
  }) {
    final copy = AppLocalizations.of(context);
    return ResponsiveContentFrame(
      width: ResponsiveContentWidth.form,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _actionBusy
                  ? null
                  : () => Navigator.of(context).maybePop(),
              tooltip: copy.text('Close', 'Zamknij'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
              color: AppImmersiveColors.textPrimary,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CallAvatar(identity: contact, size: 128),
                    const SizedBox(height: 26),
                    Text(
                      contact.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppImmersiveColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      copy.text(
                        'This call was answered on one of your devices.',
                        'To połączenie odebrano na jednym z Twoich urządzeń.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppImmersiveColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _actionBusy
                          ? null
                          : () => unawaited(_continueIncomingCall(call)),
                      icon: _actionBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              call.isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                            ),
                      label: Text(
                        copy.text(
                          'Continue on this device',
                          'Kontynuuj na tym urządzeniu',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      copy.text(
                        'Only the device used to answer can reconnect.',
                        'Ponownie połączy się tylko urządzenie użyte do odebrania.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppImmersiveColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildActiveVideoCall(
    BuildContext context, {
    required DirectCall call,
    required DirectCallIdentity contact,
    required bool connected,
  }) {
    final copy = AppLocalizations.of(context);
    final remoteTrack = _voice.remoteCameraTrack;
    final localTrack = _voice.localCameraTrack;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final previewWidth = wide ? 190.0 : 112.0;
        final previewHeight = wide ? 248.0 : 154.0;
        final outerPadding = wide ? 22.0 : 0.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.all(outerPadding),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(wide ? 34 : 0),
                child: Stack(
                  key: const ValueKey('active-video-call-stage'),
                  fit: StackFit.expand,
                  children: [
                    _CallVideoSurface(
                      track: remoteTrack,
                      identity: contact,
                      label: connected
                          ? copy.template(
                              '{displayName} camera is off',
                              'Kamera użytkownika {displayName} jest wyłączona',
                              values: {'displayName': contact.displayName},
                            )
                          : copy.template(
                              'Connecting to {displayName}',
                              'Łączenie z {displayName}',
                              values: {'displayName': contact.displayName},
                            ),
                    ),
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xB8000000),
                              Colors.transparent,
                              Colors.transparent,
                              Color(0xD9000000),
                            ],
                            stops: [0, .24, .62, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 8,
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: _actionBusy ? null : _finish,
                            tooltip: copy.text(
                              'End call and close',
                              'Zakończ i zamknij',
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(48),
                              backgroundColor: Colors.black.withValues(
                                alpha: .34,
                              ),
                              foregroundColor: AppImmersiveColors.textPrimary,
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  contact.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppImmersiveColors.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    connected
                                        ? _durationLabel()
                                        : _statusText(call, false),
                                    style: const TextStyle(
                                      color: AppImmersiveColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .34),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  color: AppImmersiveColors.textSecondary,
                                  size: 14,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  copy.text('1:1 call', 'Rozmowa 1:1'),
                                  style: const TextStyle(
                                    color: AppImmersiveColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: wide ? 88 : 74,
                      right: wide ? 24 : 14,
                      width: previewWidth,
                      height: previewHeight,
                      child: Semantics(
                        label: localTrack == null
                            ? copy.text(
                                'Your camera is off',
                                'Twoja kamera jest wyłączona',
                              )
                            : copy.text(
                                'Your camera preview',
                                'Podgląd Twojej kamery',
                              ),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppImmersiveColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(wide ? 24 : 18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .2),
                              width: 1.4,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (localTrack == null)
                                const _LocalCameraOff()
                              else
                                VideoTrackRenderer(
                                  localTrack,
                                  fit: VideoViewFit.cover,
                                  mirrorMode: _voice.shouldMirrorLocalCamera
                                      ? VideoViewMirrorMode.mirror
                                      : VideoViewMirrorMode.off,
                                ),
                              if (localTrack != null)
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: IconButton.filledTonal(
                                    onPressed: _voice.cameraChangeInProgress
                                        ? null
                                        : _flipCamera,
                                    tooltip: copy.text(
                                      'Switch camera',
                                      'Przełącz kamerę',
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size.square(38),
                                      backgroundColor: Colors.black.withValues(
                                        alpha: .48,
                                      ),
                                      foregroundColor:
                                          AppImmersiveColors.textPrimary,
                                    ),
                                    icon: const Icon(
                                      Icons.cameraswitch_rounded,
                                      size: 19,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: wide ? 18 : 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_voice.cameraIssue != null) ...[
                            Container(
                              constraints: const BoxConstraints(maxWidth: 560),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .58),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.warning.withValues(
                                    alpha: .4,
                                  ),
                                ),
                              ),
                              child: Text(
                                copy.isPolish
                                    ? 'Kamera jest chwilowo niedostępna.'
                                    : _voice.cameraIssue!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppImmersiveColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _VideoCallControls(
                            connected: connected,
                            connectionFailed: _connectionNeedsRetry,
                            muted: _voice.isMuted,
                            cameraEnabled: _voice.isCameraEnabled,
                            cameraBusy: _voice.cameraChangeInProgress,
                            speakerPreferred: _voice.isSpeakerPreferred,
                            speakerBusy: _voice.speakerChangeInProgress,
                            canSwitchSpeaker: _voice.canSwitchSpeakerphone,
                            actionBusy: _actionBusy,
                            onMute: _toggleMute,
                            onCamera: _toggleCamera,
                            onSpeaker: _toggleSpeaker,
                            onRetry: () => unawaited(_retryConnect(call)),
                            onFinish: _finish,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _statusText(DirectCall call, bool incoming) {
    final copy = AppLocalizations.of(context);
    return switch (call.status) {
      DirectCallStatus.ringing =>
        incoming
            ? call.isVideo
                  ? copy.text(
                      'Incoming video call',
                      'Przychodzące połączenie wideo',
                    )
                  : copy.text(
                      'Incoming voice call',
                      'Przychodzące połączenie głosowe',
                    )
            : call.isVideo
            ? copy.text('Video calling…', 'Łączenie wideo…')
            : copy.text('Calling…', 'Łączenie…'),
      DirectCallStatus.active =>
        _connectionNeedsRetry
            ? copy.isPolish
                  ? copy.text('Connection interrupted', 'Połączenie przerwane')
                  : _voice.errorMessage ??
                        copy.text(
                          'Connection interrupted',
                          'Połączenie przerwane',
                        )
            : copy.text('Connecting…', 'Łączenie…'),
      DirectCallStatus.declined => copy.text(
        'Call declined',
        'Połączenie odrzucone',
      ),
      DirectCallStatus.cancelled => copy.text(
        'Call cancelled',
        'Połączenie anulowane',
      ),
      DirectCallStatus.ended => copy.text(
        'Call ended',
        'Połączenie zakończone',
      ),
      DirectCallStatus.missed => copy.text(
        'Missed call',
        'Nieodebrane połączenie',
      ),
    };
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.identity, required this.size});

  final DirectCallIdentity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      radius: size / 2,
      userId: identity.userId,
      displayName: identity.displayName,
      backgroundColor: AppColors.primary,
    );
  }
}

class _CallVideoSurface extends StatelessWidget {
  const _CallVideoSurface({
    required this.track,
    required this.identity,
    required this.label,
  });

  final VideoTrack? track;
  final DirectCallIdentity identity;
  final String label;

  @override
  Widget build(BuildContext context) {
    final videoTrack = track;
    if (videoTrack != null) {
      return Semantics(
        label: AppLocalizations.of(context).template(
          '{displayName} video',
          'Obraz wideo: {displayName}',
          values: {'displayName': identity.displayName},
        ),
        child: VideoTrackRenderer(videoTrack, fit: VideoViewFit.cover),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.18),
          radius: 1.08,
          colors: [Color(0xFF351158), AppImmersiveColors.background],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 520;
          final contentWidth = (constraints.maxWidth - 56).clamp(120, 360);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              28,
              compactHeight ? 64 : 96,
              28,
              compactHeight ? 104 : 170,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: contentWidth.toDouble(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CallAvatar(
                        identity: identity,
                        size: compactHeight ? 82 : 124,
                      ),
                      SizedBox(height: compactHeight ? 10 : 20),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppImmersiveColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocalCameraOff extends StatelessWidget {
  const _LocalCameraOff();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: AppImmersiveColors.textSecondary,
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            copy.text('You', 'Ty'),
            style: const TextStyle(
              color: AppImmersiveColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCallControls extends StatelessWidget {
  const _VideoCallControls({
    required this.connected,
    required this.connectionFailed,
    required this.muted,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.speakerPreferred,
    required this.speakerBusy,
    required this.canSwitchSpeaker,
    required this.actionBusy,
    required this.onMute,
    required this.onCamera,
    required this.onSpeaker,
    required this.onRetry,
    required this.onFinish,
  });

  final bool connected;
  final bool connectionFailed;
  final bool muted;
  final bool cameraEnabled;
  final bool cameraBusy;
  final bool speakerPreferred;
  final bool speakerBusy;
  final bool canSwitchSpeaker;
  final bool actionBusy;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onRetry;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6171022),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: connectionFailed
            ? [
                _CompactVideoAction(
                  label: copy.text('Retry', 'Ponów'),
                  semanticsLabel: copy.text(
                    'Retry connection',
                    'Ponów połączenie',
                  ),
                  icon: Icons.refresh_rounded,
                  onPressed: actionBusy ? null : onRetry,
                ),
                _CompactVideoAction(
                  label: copy.text('End', 'Zakończ'),
                  semanticsLabel: copy.text('End call', 'Zakończ połączenie'),
                  semanticsHint: copy.text(
                    'Double tap to end the call',
                    'Dotknij dwukrotnie, aby zakończyć połączenie',
                  ),
                  icon: Icons.call_end_rounded,
                  destructive: true,
                  onPressed: actionBusy ? null : onFinish,
                ),
              ]
            : [
                _CompactVideoAction(
                  label: muted
                      ? copy.text('Unmute', 'Włącz mikrofon')
                      : copy.text('Mute', 'Wycisz'),
                  semanticsLabel: copy.text('Microphone', 'Mikrofon'),
                  semanticsHint: muted
                      ? copy.text(
                          'Double tap to unmute',
                          'Dotknij dwukrotnie, aby włączyć mikrofon',
                        )
                      : copy.text(
                          'Double tap to mute',
                          'Dotknij dwukrotnie, aby wyciszyć',
                        ),
                  semanticsToggled: !muted,
                  icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  selected: muted,
                  onPressed: connected && !actionBusy ? onMute : null,
                ),
                _CompactVideoAction(
                  label: cameraEnabled
                      ? copy.text('Camera off', 'Wyłącz kamerę')
                      : copy.text('Camera on', 'Włącz kamerę'),
                  semanticsLabel: copy.text('Camera', 'Kamera'),
                  semanticsHint: cameraEnabled
                      ? copy.text(
                          'Double tap to turn camera off',
                          'Dotknij dwukrotnie, aby wyłączyć kamerę',
                        )
                      : copy.text(
                          'Double tap to turn camera on',
                          'Dotknij dwukrotnie, aby włączyć kamerę',
                        ),
                  semanticsToggled: cameraEnabled,
                  icon: cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  selected: !cameraEnabled,
                  busy: cameraBusy,
                  onPressed: connected && !actionBusy && !cameraBusy
                      ? onCamera
                      : null,
                ),
                _CompactVideoAction(
                  label: speakerPreferred
                      ? copy.text('Use earpiece', 'Użyj słuchawki')
                      : copy.text('Use speaker', 'Użyj głośnika'),
                  semanticsLabel: copy.text(
                    'Speakerphone',
                    'Tryb głośnomówiący',
                  ),
                  semanticsHint: speakerPreferred
                      ? copy.text(
                          'Double tap to use earpiece',
                          'Dotknij dwukrotnie, aby użyć słuchawki',
                        )
                      : copy.text(
                          'Double tap to use speaker',
                          'Dotknij dwukrotnie, aby użyć głośnika',
                        ),
                  semanticsToggled: speakerPreferred,
                  icon: speakerPreferred
                      ? Icons.volume_up_rounded
                      : Icons.hearing_rounded,
                  selected: speakerPreferred,
                  busy: speakerBusy,
                  onPressed:
                      connected &&
                          canSwitchSpeaker &&
                          !speakerBusy &&
                          !actionBusy
                      ? onSpeaker
                      : null,
                ),
                _CompactVideoAction(
                  label: copy.text('End', 'Zakończ'),
                  semanticsLabel: copy.text('End call', 'Zakończ połączenie'),
                  semanticsHint: copy.text(
                    'Double tap to end the call',
                    'Dotknij dwukrotnie, aby zakończyć połączenie',
                  ),
                  icon: Icons.call_end_rounded,
                  destructive: true,
                  onPressed: actionBusy ? null : onFinish,
                ),
              ],
      ),
    );
  }
}

class _CompactVideoAction extends StatelessWidget {
  const _CompactVideoAction({
    required this.label,
    required this.semanticsLabel,
    required this.icon,
    required this.onPressed,
    this.semanticsHint,
    this.semanticsToggled,
    this.selected = false,
    this.destructive = false,
    this.busy = false,
  });

  final String label;
  final String semanticsLabel;
  final String? semanticsHint;
  final bool? semanticsToggled;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final background = destructive
        ? AppColors.error
        : selected
        ? AppImmersiveColors.textPrimary
        : Colors.white.withValues(alpha: .12);
    final foreground = selected && !destructive
        ? AppImmersiveColors.background
        : AppImmersiveColors.textPrimary;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      toggled: semanticsToggled,
      label: semanticsLabel,
      hint: semanticsHint,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                onPressed: onPressed,
                tooltip: label,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(52),
                  backgroundColor: background,
                  foregroundColor: foreground,
                  disabledBackgroundColor: background.withValues(alpha: .34),
                  disabledForegroundColor: foreground.withValues(alpha: .48),
                ),
                icon: busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: foreground,
                        ),
                      )
                    : Icon(icon, size: 24),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppImmersiveColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    required this.speakerPreferred,
    required this.speakerBusy,
    required this.canSwitchSpeaker,
    required this.connectionFailed,
    required this.onAccept,
    required this.onFinish,
    required this.onMute,
    required this.onSpeaker,
    required this.onRetry,
  });

  final DirectCall call;
  final bool incoming;
  final bool connected;
  final bool actionBusy;
  final bool muted;
  final bool muteBusy;
  final bool speakerPreferred;
  final bool speakerBusy;
  final bool canSwitchSpeaker;
  final bool connectionFailed;
  final VoidCallback onAccept;
  final VoidCallback onFinish;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (call.status.isTerminal) return const SizedBox(height: 88);
    if (call.status == DirectCallStatus.ringing && incoming) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 42,
        runSpacing: 18,
        children: [
          _RoundCallAction(
            label: copy.text('Decline', 'Odrzuć'),
            icon: Icons.call_end_rounded,
            color: AppColors.error,
            onPressed: actionBusy ? null : onFinish,
          ),
          _RoundCallAction(
            label: call.isVideo
                ? copy.text('Answer video', 'Odbierz wideo')
                : copy.text('Answer', 'Odbierz'),
            icon: call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            color: AppColors.success,
            onPressed: actionBusy ? null : onAccept,
          ),
        ],
      );
    }
    if (call.status == DirectCallStatus.ringing) {
      return Center(
        child: _RoundCallAction(
          label: copy.text('Cancel', 'Anuluj'),
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
            label: copy.text('Retry', 'Ponów'),
            icon: Icons.refresh_rounded,
            color: AppImmersiveColors.surfaceRaised,
            foregroundColor: AppImmersiveColors.textPrimary,
            onPressed: actionBusy ? null : onRetry,
          )
        else
          _RoundCallAction(
            label: muted
                ? copy.text('Unmute', 'Włącz mikrofon')
                : copy.text('Mute', 'Wycisz'),
            icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: AppImmersiveColors.surfaceRaised,
            foregroundColor: AppImmersiveColors.textPrimary,
            onPressed: !connected || muteBusy ? null : onMute,
          ),
        if (!connectionFailed && canSwitchSpeaker)
          _RoundCallAction(
            label: speakerPreferred
                ? copy.text('Earpiece', 'Słuchawka')
                : copy.text('Speaker', 'Głośnik'),
            icon: speakerPreferred
                ? Icons.hearing_rounded
                : Icons.volume_up_rounded,
            color: AppImmersiveColors.surfaceRaised,
            foregroundColor: AppImmersiveColors.textPrimary,
            onPressed: !connected || speakerBusy ? null : onSpeaker,
          ),
        _RoundCallAction(
          label: copy.text('End', 'Zakończ'),
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
    final copy = AppLocalizations.of(context);
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
            Text(
              copy.text(
                'This call is no longer available.',
                'To połączenie nie jest już dostępne.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppImmersiveColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onClose,
              child: Text(copy.text('Close', 'Zamknij')),
            ),
          ],
        ),
      ),
    );
  }
}
