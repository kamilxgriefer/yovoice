import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

/// The blue-violet Return accent, derived from the palette rather than a
/// remembered hex (CLAUDE.md: app_colors.dart is the source of truth).
Color get miniPlayerReturnAccent =>
    Color.lerp(AppColors.voice, AppColors.info, .45)!;

/// The three mini-player controls. EVERY tile is an isolated tap target:
/// its InkWell always has a handler, so a busy/disabled control SWALLOWS
/// the tap instead of letting it fall through to any ancestor — falling
/// through is exactly how pressing Mute mid-toggle used to navigate into
/// the room. There is deliberately no parent-wide onTap anywhere in the
/// player for a tile to fall through to, and these tiles are the second
/// line of defence.
class ActiveRoomControls extends StatelessWidget {
  const ActiveRoomControls({
    required this.micState,
    required this.muteBusy,
    required this.isHost,
    required this.onToggleMute,
    required this.onReturnToRoom,
    required this.onLeave,
    this.layout = ActiveRoomControlsLayout.dock,
    super.key,
  });

  final MicState micState;

  /// A mute change is already in flight (service or coordinator): the tile
  /// shows progress and swallows taps until it lands.
  final bool muteBusy;
  final bool isHost;
  final VoidCallback onToggleMute;
  final VoidCallback onReturnToRoom;
  final VoidCallback onLeave;
  final ActiveRoomControlsLayout layout;

  @override
  Widget build(BuildContext context) {
    final mute = MiniPlayerMuteButton(
      micState: micState,
      busy: muteBusy,
      onToggleMute: onToggleMute,
      horizontal: layout == ActiveRoomControlsLayout.grid,
    );
    final back = MiniPlayerReturnButton(
      onReturnToRoom: onReturnToRoom,
      horizontal: layout == ActiveRoomControlsLayout.grid,
    );
    final leave = MiniPlayerLeaveButton(
      isHost: isHost,
      onLeave: onLeave,
      horizontal: layout == ActiveRoomControlsLayout.grid,
    );

    if (layout == ActiveRoomControlsLayout.dock) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 128, child: mute),
          const SizedBox(width: 8),
          SizedBox(width: 128, child: back),
          const SizedBox(width: 8),
          SizedBox(width: 128, child: leave),
        ],
      );
    }

    // The mobile 2x2-ish grid: Mute and Return side by side, the
    // destructive tile wide underneath so it can never be fat-fingered
    // from either neighbour.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: mute),
              const SizedBox(width: 7),
              Expanded(child: back),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Row(children: [Expanded(child: leave)]),
      ],
    );
  }
}

enum ActiveRoomControlsLayout {
  /// Desktop: three bordered tiles in a row.
  dock,

  /// Mobile: compact 2x2-ish grid.
  grid,
}

class MiniPlayerMuteButton extends StatelessWidget {
  const MiniPlayerMuteButton({
    required this.micState,
    required this.busy,
    required this.onToggleMute,
    this.horizontal = false,
    super.key,
  });

  final MicState micState;
  final bool busy;
  final VoidCallback onToggleMute;
  final bool horizontal;

  bool get _actionable =>
      !busy && (micState == MicState.on || micState == MicState.muted);

  @override
  Widget build(BuildContext context) {
    final muted = micState == MicState.muted;
    final listenOnly = micState == MicState.listenOnly;

    final String title;
    final String subtitle;
    if (listenOnly) {
      title = 'Listening';
      subtitle = 'Listen-only';
    } else if (busy || micState == MicState.connecting) {
      title = muted ? 'Unmute mic' : 'Mute mic';
      subtitle = 'One moment…';
    } else if (muted) {
      title = 'Unmute mic';
      subtitle = 'Microphone muted';
    } else {
      title = 'Mute mic';
      subtitle = 'You are live';
    }

    return _ControlTile(
      key: const ValueKey('mini-player-mute'),
      icon: muted || listenOnly ? Icons.mic_off_rounded : Icons.mic_rounded,
      title: title,
      subtitle: subtitle,
      accent: AppColors.voice,
      horizontal: horizontal,
      showSpinner: busy,
      dimmed: muted || listenOnly || busy,
      enabled: _actionable,
      // ALWAYS a handler: a non-actionable mute swallows the tap. It must
      // never bubble to anything that navigates.
      onTap: () {
        if (!_actionable) return;
        onToggleMute();
      },
    );
  }
}

class MiniPlayerReturnButton extends StatelessWidget {
  const MiniPlayerReturnButton({
    required this.onReturnToRoom,
    this.horizontal = false,
    super.key,
  });

  final VoidCallback onReturnToRoom;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return _ControlTile(
      key: const ValueKey('mini-player-return'),
      icon: Icons.arrow_forward_rounded,
      title: 'Return to room',
      subtitle: horizontal ? 'Go to room' : 'Go back to live room',
      accent: miniPlayerReturnAccent,
      horizontal: horizontal,
      onTap: onReturnToRoom,
    );
  }
}

class MiniPlayerLeaveButton extends StatelessWidget {
  const MiniPlayerLeaveButton({
    required this.isHost,
    required this.onLeave,
    this.horizontal = false,
    super.key,
  });

  final bool isHost;
  final VoidCallback onLeave;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return _ControlTile(
      key: const ValueKey('mini-player-leave'),
      icon: Icons.logout_rounded,
      title: isHost ? 'End room' : 'Leave room',
      subtitle: 'End session',
      accent: AppColors.error,
      horizontal: horizontal,
      onTap: onLeave,
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    required this.horizontal,
    this.showSpinner = false,
    this.dimmed = false,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool horizontal;
  final bool showSpinner;
  final bool dimmed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = dimmed ? accent.withValues(alpha: .65) : accent;
    final titleColor = dimmed
        ? AppColors.textPrimary.withValues(alpha: .72)
        : AppColors.textPrimary;
    final subtitleColor = Color.lerp(accent, Colors.white, .38)!;

    final Widget leading = showSpinner
        ? SizedBox(
            width: horizontal ? 14 : 18,
            height: horizontal ? 14 : 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
          )
        : Icon(icon, size: horizontal ? 16 : 20, color: iconColor);

    final Widget body = horizontal
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 7),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: 5),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      // excludeSemantics, or the visible Texts merge back in and every tile
      // announces its content twice ("Mute mic. You are live Mute mic You
      // are live") — measured in the accessibility review's semantics dump.
      excludeSemantics: true,
      label: '$title. $subtitle',
      child: Material(
        color: accent.withValues(alpha: dimmed ? .06 : .09),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // The handler stays attached even while non-actionable so the
          // tap is consumed HERE — never forwarded to an ancestor.
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: horizontal ? 8 : 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: dimmed ? .35 : .55),
              ),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
