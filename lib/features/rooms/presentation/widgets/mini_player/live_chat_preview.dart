import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The collapsed chat preview: overline + "N new" pill, the LATEST message
/// (sender and a two-line body), and the Expand action. Expanding is its
/// own isolated tap target — it must never navigate into the room.
///
/// "N new" is deliberately SESSION-LOCAL: there is no per-user read state
/// for room chat in the backend and none is faked here. The pill claims
/// novelty since this player last had your attention, nothing more.
class LiveChatPreview extends StatelessWidget {
  const LiveChatPreview({
    required this.latest,
    required this.newCount,
    required this.onExpand,
    this.compact = false,
    this.expandFocusNode,
    super.key,
  });

  final RoomMessage? latest;
  final int newCount;
  final VoidCallback onExpand;
  final bool compact;
  final FocusNode? expandFocusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'LATEST CHAT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // Lifted from textHint: 4.41:1 measured on the player
                  // surface, under the 4.5:1 small-text bar.
                  color: Color(0xFF9C93AB),
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            if (newCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                key: const ValueKey('mini-player-new-pill'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: .55),
                  ),
                ),
                child: Text(
                  '$newCount new',
                  style: TextStyle(
                    color: Color.lerp(AppColors.secondary, Colors.white, .45),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: compact ? 5 : 7),
        _LatestMessage(latest: latest, compact: compact),
        SizedBox(height: compact ? 5 : 7),
        const Divider(
          height: 1,
          thickness: 1,
          color: AppImmersiveColors.divider,
        ),
        _ExpandChatButton(
          onExpand: onExpand,
          compact: compact,
          focusNode: expandFocusNode,
        ),
      ],
    );
  }
}

class _LatestMessage extends StatelessWidget {
  const _LatestMessage({required this.latest, required this.compact});

  final RoomMessage? latest;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final message = latest;
    if (message == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          'No messages yet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            // Lifted from textHint: 4.41:1 measured on the player
            // surface, under the 4.5:1 small-text bar.
            color: Color(0xFF9C93AB),
            fontSize: compact ? 11 : 12,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          // ExcludeSemantics: the fallback initial read as a stray
          // one-letter node ("H") between the sender name and the body.
          child: ExcludeSemantics(
            child: UserAvatar(
              radius: compact ? 9 : 11,
              photoUrl: message.senderPhotoUrl,
              displayName: message.senderName,
            ),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFCFC5D8),
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              // TWO lines maximum: a long message must never grow the
              // player, only ellipsize.
              Text(
                message.text,
                key: const ValueKey('mini-player-latest-message'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppImmersiveColors.textSecondary,
                  fontSize: compact ? 11 : 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandChatButton extends StatelessWidget {
  const _ExpandChatButton({
    required this.onExpand,
    required this.compact,
    this.focusNode,
  });

  final VoidCallback onExpand;
  final bool compact;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // The label IS the whole announcement; without excluding the child
      // text a screen reader heard "Expand chat" twice.
      excludeSemantics: true,
      label: 'Expand chat',
      onTap: onExpand,
      child: InkWell(
        key: const ValueKey('mini-player-expand-chat'),
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(8),
        onTap: onExpand,
        child: ConstrainedBox(
          // 44pt floor: this is the primary chat affordance and it measured
          // 26pt tall on a phone — under the project's own 44x44 bar and
          // both platform tap-target guidelines. The visual row stays small;
          // the TARGET grows.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 5 : 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: AppColors.voice,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    'Expand chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.voice,
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
