import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

class ShareRoomSheet extends StatelessWidget {
  const ShareRoomSheet({
    super.key,
    required this.roomName,
    required this.roomId,
    required this.shareLink,
    required this.onCopyLink,
    required this.onCopyRoomId,
  });

  final String roomName;
  final String roomId;
  final String shareLink;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onCopyRoomId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const YoModalSheetChrome(
              sheetLabel: 'share podcast',
              surfaceColor: BroadcastRoomColors.surface,
            ),
            const Text(
              'Share podcast',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              roomName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: BroadcastRoomColors.muted),
            ),
            const SizedBox(height: 18),
            CopyValueTile(
              icon: Icons.link_rounded,
              title: 'Invite link',
              value: shareLink,
              onTap: () async {
                await onCopyLink();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
            CopyValueTile(
              icon: Icons.key_rounded,
              title: 'Room ID',
              value: roomId,
              onTap: () async {
                await onCopyRoomId();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CopyValueTile extends StatelessWidget {
  const CopyValueTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BroadcastRoomColors.surfaceSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: BroadcastRoomColors.accentSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: BroadcastRoomColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.copy_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
