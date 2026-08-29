import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// The phone/tablet active-room surface.
///
/// It deliberately keeps the room identity and all three controls as separate
/// tap targets. There is no parent-wide handler for a temporarily busy Mute to
/// fall through to, preserving the navigation-isolation contract of ADR-102.
class CompactActiveRoomBar extends StatelessWidget {
  const CompactActiveRoomBar({
    required this.roomName,
    required this.reconnecting,
    required this.participantCount,
    required this.latest,
    required this.newCount,
    required this.micState,
    required this.muteBusy,
    required this.onReturnToRoom,
    required this.onExpandChat,
    required this.onToggleMute,
    required this.onMore,
    super.key,
  });

  final String roomName;
  final bool reconnecting;
  final int participantCount;
  final RoomMessage? latest;
  final int newCount;
  final MicState micState;
  final bool muteBusy;
  final VoidCallback onReturnToRoom;
  final VoidCallback onExpandChat;
  final VoidCallback onToggleMute;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Align(
      child: Container(
        key: const ValueKey('mini-player-compact-surface'),
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.fromLTRB(10, 5, 10, 7),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.surfaceRaised, palette.navigationSurface],
          ),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: Color.lerp(
              palette.borderStrong,
              AppColors.voice,
              .42,
            )!.withValues(alpha: .72),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .16),
              blurRadius: 20,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: palette.shadow.withValues(alpha: .26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _CompactRoomInfo(
                roomName: roomName,
                reconnecting: reconnecting,
                participantCount: participantCount,
                latest: latest,
                onTap: onReturnToRoom,
              ),
            ),
            const SizedBox(width: 7),
            _CompactChatButton(
              latest: latest,
              newCount: newCount,
              onTap: onExpandChat,
            ),
            const SizedBox(width: 5),
            _CompactMuteButton(
              micState: micState,
              busy: muteBusy,
              onToggleMute: onToggleMute,
            ),
            const SizedBox(width: 5),
            _CompactCircleButton(
              key: const ValueKey('mini-player-more'),
              semanticLabel: 'More room controls',
              tooltip: 'More room controls',
              icon: Icons.more_horiz_rounded,
              foreground: palette.textPrimary,
              fill: palette.surfaceMuted,
              border: palette.borderStrong.withValues(alpha: .62),
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRoomInfo extends StatelessWidget {
  const _CompactRoomInfo({
    required this.roomName,
    required this.reconnecting,
    required this.participantCount,
    required this.latest,
    required this.onTap,
  });

  final String roomName;
  final bool reconnecting;
  final int participantCount;
  final RoomMessage? latest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final status = reconnecting ? 'Reconnecting' : 'Live';
    final latestText = _latestLabel(latest);
    final countText = participantCount > 0 ? '$participantCount inside' : null;
    final metadata = reconnecting
        ? status
        : [status, ?countText, latestText].join(' · ');

    return Semantics(
      button: true,
      label: 'Return to $roomName. $metadata',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('mini-player-room-info'),
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      border: Border.all(
                        color: AppColors.voice.withValues(alpha: .72),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: .34),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: reconnecting
                                    ? AppColors.warning
                                    : AppColors.live,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _latestLabel(RoomMessage? message) {
    if (message == null) return 'No chat yet';
    final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return message.senderName;
    return '${message.senderName}: $text';
  }
}

class _CompactChatButton extends StatelessWidget {
  const _CompactChatButton({
    required this.latest,
    required this.newCount,
    required this.onTap,
  });

  final RoomMessage? latest;
  final int newCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final unreadLabel = newCount == 0
        ? ''
        : '. $newCount new ${newCount == 1 ? 'message' : 'messages'}';
    final latestLabel = latest == null
        ? '. No messages yet'
        : '. Latest from ${latest!.senderName}: ${latest!.text}';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _CompactCircleButton(
          key: const ValueKey('mini-player-expand-chat'),
          semanticLabel: 'Expand room chat$unreadLabel$latestLabel',
          tooltip: 'Room chat',
          icon: Icons.chat_bubble_rounded,
          foreground: AppColors.voice,
          fill: palette.surfaceMuted,
          border: AppColors.voice.withValues(alpha: .54),
          onTap: onTap,
        ),
        if (newCount > 0)
          Positioned(
            right: -3,
            top: -4,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('mini-player-new-pill'),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Color.lerp(AppColors.live, AppColors.black, .25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: palette.navigationSurface,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    newCount > 9 ? '9+' : '$newCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompactMuteButton extends StatelessWidget {
  const _CompactMuteButton({
    required this.micState,
    required this.busy,
    required this.onToggleMute,
  });

  final MicState micState;
  final bool busy;
  final VoidCallback onToggleMute;

  bool get _actionable =>
      !busy && (micState == MicState.on || micState == MicState.muted);

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final muted = micState == MicState.muted;
    final listenOnly = micState == MicState.listenOnly;
    final connecting = micState == MicState.connecting;

    final String label;
    final String tooltip;
    if (listenOnly) {
      label = 'Listening. Listen-only';
      tooltip = 'Listen-only';
    } else if (busy || connecting) {
      label = '${muted ? 'Unmute' : 'Mute'} microphone. One moment';
      tooltip = 'Updating microphone';
    } else if (muted) {
      label = 'Unmute microphone. Microphone muted';
      tooltip = 'Unmute microphone';
    } else {
      label = 'Mute microphone. You are live';
      tooltip = 'Mute microphone';
    }

    final fill = muted
        ? AppColors.warning
        : listenOnly || connecting || busy
        ? palette.surfaceMuted
        : AppColors.primary;
    final foreground = muted
        ? AppColors.black
        : listenOnly || connecting || busy
        ? palette.textSecondary
        : Colors.white;

    return _CompactCircleButton(
      key: const ValueKey('mini-player-mute'),
      semanticLabel: label,
      tooltip: tooltip,
      icon: muted || listenOnly ? Icons.mic_off_rounded : Icons.mic_rounded,
      foreground: foreground,
      fill: fill,
      border: muted
          ? AppColors.warning.withValues(alpha: .76)
          : AppColors.voice.withValues(alpha: .56),
      showSpinner: busy,
      enabledForSemantics: _actionable,
      // ALWAYS consume the gesture. A busy control must never forward its tap
      // to the room-info zone and navigate while a mute mutation is in flight.
      onTap: () {
        if (!_actionable) return;
        onToggleMute();
      },
    );
  }
}

class _CompactCircleButton extends StatelessWidget {
  const _CompactCircleButton({
    required this.semanticLabel,
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.fill,
    required this.border,
    required this.onTap,
    this.showSpinner = false,
    this.enabledForSemantics = true,
    super.key,
  });

  final String semanticLabel;
  final String tooltip;
  final IconData icon;
  final Color foreground;
  final Color fill;
  final Color border;
  final VoidCallback onTap;
  final bool showSpinner;
  final bool enabledForSemantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabledForSemantics,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabledForSemantics ? onTap : null,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            canRequestFocus: enabledForSemantics,
            child: Ink(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: border.withValues(alpha: .2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: showSpinner
                  ? Padding(
                      padding: const EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
                      ),
                    )
                  : Icon(icon, size: 21, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

enum CompactRoomMoreAction { returnToRoom, leave }

/// Presents the two lower-frequency room actions after the compact mobile bar
/// has already kept Chat and Mute one tap away.
///
/// The route's reverse transition is awaited before returning the selection,
/// so a Return action cannot push the room underneath a still-closing modal.
Future<CompactRoomMoreAction?> showCompactRoomMoreSheet(
  BuildContext context, {
  required bool endsRoomNow,
  ValueChanged<ModalBottomSheetRoute<CompactRoomMoreAction>>? onRouteCreated,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<CompactRoomMoreAction>(
    builder: (sheetContext) => _CompactRoomMoreSheet(
      endsRoomNow: endsRoomNow,
      onSelected: (action) => Navigator.of(sheetContext).pop(action),
    ),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: true,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    backgroundColor: Colors.transparent,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    modalBarrierColor: context.appPalette.scrim.withValues(alpha: .72),
    showDragHandle: false,
    useSafeArea: true,
  );
  onRouteCreated?.call(route);
  final action = await navigator.push(route);
  await route.completed;
  return action;
}

class _CompactRoomMoreSheet extends StatelessWidget {
  const _CompactRoomMoreSheet({
    required this.endsRoomNow,
    required this.onSelected,
  });

  final bool endsRoomNow;
  final ValueChanged<CompactRoomMoreAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoModalSheetChrome(
              sheetLabel: 'room controls',
              surfaceColor: palette.surfaceRaised,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Room controls',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: _SheetAction(
                key: const ValueKey('mini-player-return'),
                icon: Icons.arrow_forward_rounded,
                title: 'Return to room',
                subtitle: 'Open the live room',
                accent: colorScheme.primary,
                onTap: () => onSelected(CompactRoomMoreAction.returnToRoom),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _SheetAction(
                key: const ValueKey('mini-player-leave'),
                icon: Icons.logout_rounded,
                title: endsRoomNow ? 'End room' : 'Leave room',
                subtitle: endsRoomNow
                    ? 'End this live session'
                    : 'Leave this live session',
                accent: colorScheme.error,
                danger: true,
                onTap: () => onSelected(CompactRoomMoreAction.leave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: danger ? palette.dangerSurface : accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: .48)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: danger ? accent : palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: accent.withValues(alpha: .78),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
