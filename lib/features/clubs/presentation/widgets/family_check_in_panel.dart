import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Quick check-ins for a Family Room.
///
/// These are ORDINARY STATUS UPDATES between family members. They are
/// deliberately NOT an emergency feature: nothing here contacts a service,
/// raises an alarm, or asks for — let alone sends — a location. The four
/// statuses are the whole vocabulary, and `firestore.rules` rejects any
/// other value as well as any document carrying location keys.
///
/// Visible only to active members, because the collection itself is
/// readable only by them. Deletion follows the club surfaces' existing
/// pattern: the author, or an organizer.
class FamilyCheckInPanel extends StatefulWidget {
  const FamilyCheckInPanel({
    required this.clubId,
    required this.currentUserId,
    required this.canManage,
    this.clubService,
    super.key,
  });

  final String clubId;
  final String currentUserId;

  /// Organizer (owner/co-owner/admin). Mirrors the club surfaces' own
  /// `canEditClub`, and rules re-check it independently.
  final bool canManage;

  final ClubService? clubService;

  @override
  State<FamilyCheckInPanel> createState() => _FamilyCheckInPanelState();
}

class _FamilyCheckInPanelState extends State<FamilyCheckInPanel> {
  late final ClubService _service = widget.clubService ?? ClubService();
  bool _busy = false;

  Future<void> _post(FamilyCheckInStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.postCheckIn(clubId: widget.clubId, status: status);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not send that check-in.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(FamilyCheckIn checkIn) async {
    try {
      await _service.deleteCheckIn(
        clubId: widget.clubId,
        checkInId: checkIn.id,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not remove that check-in.')),
      );
    }
  }

  String _when(DateTime? at) {
    if (at == null) return 'just now';
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final accent = palette.successForeground;
    return Container(
      key: const ValueKey('family-check-in-panel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.successSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.waving_hand_rounded, size: 18, color: accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quick check-ins',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A quick note to the family. Not an emergency feature, and no '
            'location is ever shared.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in FamilyCheckInStatus.values)
                _CheckInChip(
                  label: status.label,
                  enabled: !_busy,
                  onTap: () => _post(status),
                ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<FamilyCheckIn>>(
            stream: _service.watchCheckIns(widget.clubId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Check-ins are unavailable right now.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                );
              }
              final checkIns = snapshot.data ?? const <FamilyCheckIn>[];
              if (checkIns.isEmpty) {
                return Text(
                  'No check-ins yet.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final checkIn in checkIns.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          UserAvatar(
                            radius: 14,
                            userId: checkIn.userId,
                            photoUrl: checkIn.photoUrl,
                            displayName: checkIn.displayName,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${checkIn.displayName} · '
                              '${checkIn.status!.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _when(checkIn.createdAt),
                            style: TextStyle(
                              color: palette.textTertiary,
                              fontSize: 11.5,
                            ),
                          ),
                          // The author, or an organizer — the same pattern
                          // the club surfaces already use for member
                          // content. Rules re-check both independently.
                          if (checkIn.userId == widget.currentUserId ||
                              widget.canManage)
                            IconButton(
                              onPressed: () => _delete(checkIn),
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Remove check-in',
                              icon: Icon(
                                Icons.close_rounded,
                                color: palette.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CheckInChip extends StatelessWidget {
  const _CheckInChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final accent = palette.successForeground;
    return Material(
      color: palette.successSurface,
      shape: StadiumBorder(
        side: BorderSide(color: accent.withValues(alpha: .55)),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
