import 'package:flutter/material.dart';

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

  static const emerald = Color(0xFF28D17C);
  static const _surface = Color(0xFF12231D);
  static const _border = Color(0xFF286447);

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FamilyCheckInPanel._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FamilyCheckInPanel._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(
                Icons.waving_hand_rounded,
                size: 18,
                color: FamilyCheckInPanel.emerald,
              ),
              SizedBox(width: 8),
              Text(
                'Quick check-ins',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'A quick note to the family. Not an emergency feature, and no '
            'location is ever shared.',
            style: TextStyle(
              color: Color(0xFF9BAFA4),
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
                return const Text(
                  'Check-ins are unavailable right now.',
                  style: TextStyle(color: Color(0xFF9BAFA4), fontSize: 12.5),
                );
              }
              final checkIns = snapshot.data ?? const <FamilyCheckIn>[];
              if (checkIns.isEmpty) {
                return const Text(
                  'No check-ins yet.',
                  style: TextStyle(color: Color(0xFF9BAFA4), fontSize: 12.5),
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
                              style: const TextStyle(
                                color: Color(0xFFDCEAE3),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _when(checkIn.createdAt),
                            style: const TextStyle(
                              color: Color(0xFF7E9389),
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
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF7E9389),
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
    return Material(
      color: FamilyCheckInPanel.emerald.withValues(alpha: .13),
      shape: StadiumBorder(
        side: BorderSide(
          color: FamilyCheckInPanel.emerald.withValues(alpha: .45),
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8CEFC0),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
