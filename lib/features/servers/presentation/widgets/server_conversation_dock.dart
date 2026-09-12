import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server_channel.dart';
import '../../data/services/server_screen_share_capability.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// The persistent conversation dock. It exists only while a join is in
/// flight or a link is up, and it says "połączono" only while the provider
/// reports an established link — every other phase is named for what it is.
///
/// Board 04's meeting adds `Kamera`, `Udostępnij ekran` and `Tablica` to the
/// row, and the elapsed time of the generation. Each of the three is drawn
/// for what it can actually do: the camera has no publishing lifecycle yet
/// (contract §3) and is disabled and labelled so; the share follows contract
/// decision D — enabled where the grant and the platform both allow it,
/// otherwise disabled with the real reason on it; the whiteboard control
/// selects a view and is drawn only where that view exists.
class ServerConversationDock extends StatelessWidget {
  const ServerConversationDock({
    required this.controller,
    required this.onOpenChannel,
    this.compact = false,
    this.meetingChannel,
    this.onOpenWhiteboard,
    this.screenShare,
    super.key,
  });

  final ServerSessionController controller;
  final ValueChanged<ServerChannel> onOpenChannel;
  final bool compact;

  /// The company meeting this surface is showing, straight from the channel
  /// stream. The dock reads its liveness projection for the meeting clock —
  /// the server's own instant for the generation, never a local guess — and
  /// offers the whiteboard view only while this is the channel the session is
  /// actually in. Null on every other surface.
  final ServerChannel? meetingChannel;

  /// Present only where a whiteboard view exists to select (not on a phone,
  /// where the board is a card inside the meeting itself).
  final VoidCallback? onOpenWhiteboard;

  /// What this platform can do about publishing a screen. Null keeps the
  /// controller's own answer.
  final ServerScreenShareCapability? screenShare;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.isActive) return const SizedBox.shrink();
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final channel = controller.channel;
      final connected = controller.isConnected;
      // A reconnect does not release the capture, so the two local privacy
      // controls stay on screen through it — removing a mute from the surface
      // while the microphone is still open is worse than a mute that has to
      // wait. Everything that needs live signalling stays on `connected`.
      final live = controller.isLive;
      // Board 05's bar makes listening and broadcasting two visibly different
      // states, and the difference is real: a listener's grant carries no
      // track source at all, so a microphone control could only ever fail for
      // them. They get the one control that does work on this device instead.
      final publishing = live && controller.canPublish;
      final status = _status(copy);
      final micLabel = controller.isMicrophoneEnabled
          ? copy.serverMicrophoneOn
          : copy.serverMicrophoneOff;
      // Board 04's row. A meeting is the one channel configuration whose
      // grant carries a camera and a screen share at all, so these three are
      // drawn there and nowhere else.
      final meeting =
          connected && channel?.kind == ServerChannelKind.meeting;
      // The meeting on screen is the one the session is in: a clock and a
      // view that belong to another channel are simply not drawn.
      final here = meeting && channel?.id == meetingChannel?.id;
      final elapsedSince = here && (meetingChannel?.liveness.isLive ?? false)
          ? meetingChannel!.liveness.startedAt
          : null;
      final share = screenShare ?? controller.screenShare;
      final canShare = controller.canShareScreen;
      final sharing = controller.isScreenShareEnabled;
      final controls = [
        if (publishing)
          _DockControl(
            key: const ValueKey('server-dock-microphone'),
            icon: controller.isMicrophoneEnabled
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            label: compact ? null : copy.serverMicrophone,
            semanticLabel: micLabel,
            active: controller.isMicrophoneEnabled,
            onPressed: controller.microphoneBusy
                ? null
                : controller.toggleMicrophone,
          ),
        if (live)
          // Local output only: nothing is published, written or signalled
          // about the person. It is the listener's own volume, not a mute.
          _DockControl(
            key: const ValueKey('server-dock-headphones'),
            icon: controller.isDeafened
                ? Icons.headset_off_rounded
                : Icons.headphones_rounded,
            label: compact ? null : copy.serverHeadphones,
            semanticLabel: controller.isDeafened
                ? copy.serverHeadphonesOff
                : copy.serverHeadphonesOn,
            active: !controller.isDeafened,
            onPressed: controller.headphonesBusy
                ? null
                : controller.toggleDeafened,
          ),
        if (meeting)
          // The grant permits a camera (`mediaMode: meeting`); the client
          // lifecycle that would publish one does not exist yet, so the
          // control is visibly unavailable and says why instead of failing.
          _DockControl(
            key: const ValueKey('server-dock-camera'),
            icon: Icons.videocam_off_outlined,
            label: compact ? null : copy.serverCamera,
            semanticLabel:
                '${copy.serverCamera} — ${copy.serverCameraUnavailable}',
            onPressed: null,
          ),
        if (meeting)
          _DockControl(
            key: const ValueKey('server-dock-share'),
            icon: sharing
                ? Icons.stop_screen_share_outlined
                : Icons.screen_share_outlined,
            label: compact ? null : copy.serverShareScreen,
            semanticLabel: canShare
                ? (sharing ? copy.serverStopSharing : copy.serverShareScreen)
                : '${copy.serverShareScreen} — '
                      '${share.canStartShare ? copy.serverShareScreenHostOnly : copy.serverShareScreenUnavailable}',
            active: sharing,
            onPressed: canShare && !controller.screenShareBusy
                ? controller.toggleScreenShare
                : null,
          ),
        if (here && onOpenWhiteboard != null)
          _DockControl(
            key: const ValueKey('server-dock-whiteboard'),
            icon: Icons.draw_outlined,
            label: compact
                ? null
                : copy.serverChannelKindTitle(ServerChannelKind.whiteboard),
            semanticLabel: copy.serverMeetingBoard,
            onPressed: onOpenWhiteboard,
          ),
        _DockControl(
          key: const ValueKey('server-dock-leave'),
          icon: Icons.call_end_rounded,
          label: compact ? null : copy.serverLeaveShort,
          semanticLabel: copy.serverLeaveConversation,
          destructive: true,
          onPressed: controller.phase == ServerSessionPhase.leaving
              ? null
              : controller.phase == ServerSessionPhase.failed ||
                    controller.phase == ServerSessionPhase.blocked
              ? controller.dismiss
              : controller.leave,
        ),
      ];
      final identity = [
        Icon(
          // Listening and broadcasting differ by glyph, by word and by
          // which controls exist — never by colour alone.
          !connected
              ? Icons.sync_rounded
              : publishing
              ? Icons.graphic_eq_rounded
              : Icons.headphones_rounded,
          color: connected ? palette.audioAccent : palette.textSecondary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: channel == null ? null : () => onOpenChannel(channel),
            borderRadius: AppRadius.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  channel?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  status,
                  key: const ValueKey('server-dock-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: connected
                        ? palette.audioAccent
                        : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (elapsedSince != null) ...[
          const SizedBox(width: 8),
          _Elapsed(since: elapsedSince),
        ],
      ];
      // A conversation's three controls sit beside the status. A meeting's
      // five do not — not at 320 px and not at 200 % text — so they take a
      // row of their own and wrap inside it, exactly as board 04's phone
      // arranges them. Nothing is dropped, scrolled out of reach or hidden.
      final stacked = controls.length > 3;
      return Semantics(
        container: true,
        liveRegion: true,
        label: channel == null ? status : '${channel.name} · $status',
        child: Container(
          key: const ValueKey('server-conversation-dock'),
          margin: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            8,
            compact ? 8 : 16,
            compact ? 8 : 12,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: AppRadius.lg,
            border: Border.all(
              color: connected ? palette.audioAccent : palette.border,
            ),
          ),
          child: stacked
              ? Column(
                  key: const ValueKey('server-dock-stacked'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: identity),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2,
                      runSpacing: 8,
                      children: controls,
                    ),
                  ],
                )
              : Row(
                  children: [
                    ...identity,
                    const SizedBox(width: 8),
                    ...controls,
                  ],
                ),
        ),
      );
    },
  );

  String _status(AppLocalizations copy) {
    // A refused mute or headphones press outranks the phase line for as long
    // as it stands: the phase is still "połączono", which is true and beside
    // the point — what the person needs to know is that the control they just
    // pressed did not take. The next press clears it, and so does leaving.
    // The dock's own `liveRegion` means a screen reader hears it too.
    final refused = controller.privacyError;
    if (refused != null) {
      return serverActionFailureCopy(
        refused,
        copy,
        fallback: copy.serverAudioControlFailed,
      );
    }
    return _phaseStatus(copy);
  }

  String _phaseStatus(AppLocalizations copy) => switch (controller.phase) {
    ServerSessionPhase.idle => '',
    ServerSessionPhase.blocked => copy.serverOtherVoiceActive,
    ServerSessionPhase.starting ||
    ServerSessionPhase.connecting => copy.serverConnecting,
    ServerSessionPhase.authorizing => copy.serverCheckingAccess,
    ServerSessionPhase.connected =>
      !controller.canPublish
          // Board 05's "Słuchasz • Studio LIVE".
          ? copy.serverListening
          // On a stage, publishing is being on the air; in a conversation it
          // is simply being connected, which is what boards 01 and 03 say.
          : controller.channel?.kind == ServerChannelKind.stage
          ? copy.serverStageOnAir
          : copy.serverConnected,
    ServerSessionPhase.reconnecting => copy.serverReconnecting,
    ServerSessionPhase.leaving => copy.serverLeaving,
    ServerSessionPhase.failed =>
      controller.error is ServerSessionDisconnected
          ? copy.serverConnectionLost
          : serverActionFailureCopy(
              controller.error ?? Object(),
              copy,
              fallback: copy.serverJoinFailed,
            ),
  };
}

/// The meeting clock of board 04 ("12:24").
///
/// It counts from the instant the server wrote into the channel's liveness
/// projection when this generation started, so every device in the meeting
/// reads the same number and a device that joined late does not start at
/// zero. It ticks once a second while it is on screen and stops with it.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.since});
  final DateTime since;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// `mm:ss` under an hour, `h:mm:ss` beyond it — a meeting that runs past an
  /// hour must not restart its own clock.
  static String format(Duration elapsed) {
    final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    if (minutes < 60) return '$minutes:$rest';
    final hours = minutes ~/ 60;
    return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$rest';
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final value = format(DateTime.now().difference(widget.since));
    return Semantics(
      label: copy.serverMeetingElapsed(value),
      excludeSemantics: true,
      child: Text(
        value,
        key: const ValueKey('server-dock-elapsed'),
        style: AppTypography.labelMedium.copyWith(
          color: palette.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _DockControl extends StatelessWidget {
  const _DockControl({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.label,
    this.active = false,
    this.destructive = false,
    super.key,
  });
  final IconData icon;
  final String semanticLabel;
  final String? label;
  final bool active;
  final bool destructive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final background = destructive
        ? AppColors.error
        : active
        ? palette.audioAccent
        : palette.surfaceMuted;
    // `AppColors.white` on the error fill is 2.95:1 — below the 3:1 that
    // WCAG 1.4.11 asks of a glyph that identifies a control, and on a phone
    // this control has no text label at all. `contrastInk` is 5.87:1 on the
    // same fill.
    final foreground = destructive
        ? AppColors.contrastInk
        : active
        ? AppColors.contrastInk
        : scheme.onSurface;
    // `onTap` is the whole accessibility contract of this control: the outer
    // node carries role, name and state, and without the action the excluded
    // `IconButton` takes `SemanticsAction.tap` with it — leaving a button a
    // screen reader, Switch Access or Voice Control cannot press.
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton.filled(
          onPressed: onPressed,
          style:
              IconButton.styleFrom(
                backgroundColor: background,
                foregroundColor: foreground,
                disabledBackgroundColor: palette.surfaceMuted,
                disabledForegroundColor: palette.textTertiary,
              ).copyWith(
                // An identity-filled control overrides the fill the theme's
                // focus ring was measured against (`docs/UI.md`, semantic
                // colour ownership), so it brings its own on-colour ring.
                side: serverFocusRing(foreground),
              ),
          icon: Icon(icon, size: 22),
        ),
      ),
    );
    if (label == null) {
      return Padding(padding: const EdgeInsets.only(left: 6), child: button);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          const SizedBox(height: 2),
          ExcludeSemantics(
            child: Text(
              label!,
              style: AppTypography.labelSmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
