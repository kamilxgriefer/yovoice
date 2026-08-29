import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// A width-independent summary of the member's activity on YO Voice.
///
/// Rows deliberately use a compact intrinsic height instead of deriving
/// their height from the available width. This keeps the card equally useful
/// inside the narrow phone feed and the wide desktop shell.
class ProfileJourneyCard extends StatelessWidget {
  const ProfileJourneyCard({
    required this.communitiesCount,
    required this.messageCount,
    required this.voiceMinutes,
    required this.roomCount,
    super.key,
  });

  final int communitiesCount;
  final int messageCount;
  final int voiceMinutes;
  final int roomCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final items = <_JourneyItem>[
      _JourneyItem(
        icon: Icons.hub_rounded,
        label: 'Communities',
        value: '$communitiesCount',
        keyName: 'communities',
      ),
      _JourneyItem(
        icon: Icons.forum_rounded,
        label: 'Messages',
        value: '$messageCount',
        keyName: 'messages',
      ),
      _JourneyItem(
        icon: Icons.graphic_eq_rounded,
        label: 'Voice time',
        value: _formatVoiceTime(voiceMinutes),
        keyName: 'voice-time',
      ),
      _JourneyItem(
        icon: Icons.meeting_room_rounded,
        label: 'Rooms created',
        value: '$roomCount',
        keyName: 'rooms-created',
      ),
    ];

    return SizedBox(
      width: double.infinity,
      child: Container(
        key: const ValueKey('profile-journey-card'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your YO Voice journey',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(height: 1, indent: 34, color: palette.border),
              _JourneyRow(item: items[index]),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatVoiceTime(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({required this.item});

  final _JourneyItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: item.label,
      value: item.value,
      child: ConstrainedBox(
        key: ValueKey('profile-journey-row-${item.keyName}'),
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(item.icon, color: colors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                item.value,
                maxLines: 1,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyItem {
  const _JourneyItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.keyName,
  });

  final IconData icon;
  final String label;
  final String value;
  final String keyName;
}
