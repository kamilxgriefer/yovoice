import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';

/// One refined horizontal panel of room tools (the podcast host's
/// Guests · Hands · Manage row). Shared presentation; the OWNING screen
/// decides which tools exist and what they do.
class RoomQuickActions extends StatelessWidget {
  const RoomQuickActions({
    required this.identity,
    required this.items,
    super.key,
  });

  final SpaceIdentity identity;
  final List<RoomQuickActionItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0813).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(child: _QuickAction(item: item, identity: identity)),
        ],
      ),
    );
  }
}

class RoomQuickActionItem {
  const RoomQuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// True when the tool carries a real pending signal (raised hands).
  final bool highlighted;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.item, required this.identity});

  final RoomQuickActionItem item;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: item.highlighted ? identity.primary : identity.wash,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                item.icon,
                color: item.highlighted ? Colors.white : identity.accent,
                size: 19,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
