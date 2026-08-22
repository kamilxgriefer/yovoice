import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// The mini player's room-identity zone: waveform badge, title, live line
/// and the "N inside" chip. The WHOLE zone — and nothing outside it — is
/// one tap target that returns to the room.
class ActiveRoomInfo extends StatelessWidget {
  const ActiveRoomInfo({
    required this.roomName,
    required this.reconnecting,
    required this.participantCount,
    required this.onReturnToRoom,
    this.compact = false,
    this.narrow = false,
    super.key,
  });

  final String roomName;
  final bool reconnecting;

  /// People currently in the live audio session (RTC truth). The chip is
  /// hidden at zero rather than showing a fabricated count.
  final int participantCount;
  final VoidCallback onReturnToRoom;

  /// Tightened spacing for the mobile card.
  final bool compact;

  /// Very tight width (320-class): metadata degrades before controls —
  /// the chip drops the word "inside" and keeps the honest count.
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final statusLine = reconnecting ? 'Reconnecting…' : 'Live now';
    final statusColor = reconnecting
        ? AppColors.warning
        : Color.lerp(AppColors.secondary, Colors.white, .25)!;

    final statusRow = Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reconnecting ? AppColors.warning : AppColors.live,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: statusLine,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!reconnecting)
                  const TextSpan(
                    text: ' · tap to return',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 10.5 : 11.5),
          ),
        ),
      ],
    );
    final title = Text(
      roomName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: compact ? 13 : 14.5,
        fontWeight: FontWeight.w800,
      ),
    );
    final chip = participantCount > 0
        ? _InsideChip(count: participantCount, narrow: narrow)
        : null;

    // COMPACT stacks status and chip UNDER the badge row so they get the
    // whole column's width — "Reconnecting…" and "Live now · tap to
    // return" were the first casualties of sharing a row with the badge
    // at 320-390.
    final Widget body = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _WaveformBadge(size: 30),
                  const SizedBox(width: 8),
                  Expanded(child: title),
                ],
              ),
              const SizedBox(height: 5),
              statusRow,
              if (chip != null) ...[const SizedBox(height: 5), chip],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _WaveformBadge(size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 3),
                    statusRow,
                    if (chip != null) ...[const SizedBox(height: 7), chip],
                  ],
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label: 'Return to $roomName',
      child: InkWell(
        key: const ValueKey('mini-player-room-info'),
        borderRadius: BorderRadius.circular(14),
        onTap: onReturnToRoom,
        child: Padding(padding: EdgeInsets.all(compact ? 4 : 6), child: body),
      ),
    );
  }
}

/// The circular waveform icon with its soft violet ring.
class _WaveformBadge extends StatelessWidget {
  const _WaveformBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        border: Border.all(
          color: AppColors.voice.withValues(alpha: .55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: Colors.white,
        size: size * .55,
      ),
    );
  }
}

class _InsideChip extends StatelessWidget {
  const _InsideChip({required this.count, required this.narrow});

  final int count;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    // Metadata degrades before controls: at 320-class widths the chip
    // keeps the icon and the honest count and drops only the word —
    // never an ellipsized "3 ins…". (No LayoutBuilder here: the desktop
    // dock measures this subtree through IntrinsicHeight, and
    // LayoutBuilder has no intrinsic dimensions.)
    final label = narrow ? '$count' : '$count inside';
    // The VISUAL string degrades on narrow widths; the accessible one never
    // does — a screen reader was hearing a bare "3".
    return Semantics(
      label: '$count ${count == 1 ? 'person' : 'people'} inside',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_alt_rounded,
              size: 12,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
