import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';

class ClubMemberManagementScreen extends StatefulWidget {
  const ClubMemberManagementScreen({
    required this.clubId,
    required this.member,
    super.key,
  });

  final String clubId;
  final ClubMember member;

  @override
  State<ClubMemberManagementScreen> createState() =>
      _ClubMemberManagementScreenState();
}

class _ClubMemberManagementScreenState
    extends State<ClubMemberManagementScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171120);
  static const _purple = Color(0xFF9D20FF);

  final ClubService _service = ClubService();
  bool _saving = false;

  Future<void> _changeRole(ClubRole role) async {
    if (_saving || role == widget.member.role) return;
    setState(() => _saving = true);
    try {
      await _service.updateMemberRole(
        clubId: widget.clubId,
        memberId: widget.member.userId,
        role: role,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Role changed to ${role.label}.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMember() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text(
          'Remove member?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${widget.member.displayName} will lose access to this club, its chat and Club Lounge.',
          style: const TextStyle(color: Color(0xFFB8AFBD)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB72D55),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.removeMember(
        clubId: widget.clubId,
        memberId: widget.member.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed from the club.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Member role'),
      ),
      body: StreamBuilder<ClubMember?>(
        stream: _service.watchMyMembership(widget.clubId),
        builder: (context, snapshot) {
          final actor = snapshot.data;
          final canManage =
              actor != null &&
              actor.role.canManageRoles &&
              actor.userId != widget.member.userId &&
              actor.role.power > widget.member.role.power;
          final canRemove =
              actor != null &&
              actor.role.canRemoveMembers &&
              actor.userId != widget.member.userId &&
              actor.role.power > widget.member.role.power &&
              widget.member.role != ClubRole.owner;

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
            children: [
              _MemberHeader(member: widget.member),
              const SizedBox(height: 22),
              const Text(
                'CLUB ROLE',
                style: TextStyle(
                  color: Color(0xFF9F95A6),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              for (final role in ClubRole.values.where(
                (role) => role != ClubRole.owner,
              ))
                _RoleTile(
                  role: role,
                  selected: role == widget.member.role,
                  enabled:
                      canManage &&
                      (actor.role == ClubRole.owner ||
                          role.power < actor.role.power),
                  onTap: () => _changeRole(role),
                ),
              if (!canManage) ...[
                const SizedBox(height: 14),
                const Text(
                  'Only a higher-ranking Owner or Co-owner can change this member’s role.',
                  style: TextStyle(
                    color: Color(0xFF968C9D),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              if (canRemove) ...[
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _removeMember,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B8E),
                    side: const BorderSide(color: Color(0xFF6B2940)),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.person_remove_rounded),
                  label: const Text('REMOVE FROM CLUB'),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator(color: _purple)),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({required this.member});
  final ClubMember member;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = member.photoUrl?.isNotEmpty ?? false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171120),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF392A46)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFF7230A5),
            backgroundImage: hasPhoto ? NetworkImage(member.photoUrl!) : null,
            child: hasPhoto
                ? null
                : Text(
                    member.initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  member.role.label,
                  style: const TextStyle(
                    color: Color(0xFFD19CFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.role,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final ClubRole role;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (role) {
      ClubRole.coOwner => 'Manage roles, club settings and channels',
      ClubRole.admin => 'Manage channels and club operations',
      ClubRole.moderator => 'Invite and moderate members',
      ClubRole.member => 'Standard club access',
      ClubRole.guest => 'Limited club access',
      ClubRole.owner => 'Full ownership',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        tileColor: selected ? const Color(0xFF352047) : const Color(0xFF171120),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: selected ? const Color(0xFF9D20FF) : const Color(0xFF33263F),
          ),
        ),
        leading: Icon(
          selected ? Icons.verified_rounded : Icons.shield_outlined,
          color: enabled || selected
              ? const Color(0xFFC17BFF)
              : const Color(0xFF5E5664),
        ),
        title: Text(
          role.label,
          style: TextStyle(
            color: enabled || selected ? Colors.white : const Color(0xFF756D7B),
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF9F95A6), fontSize: 11),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFFB85CFF))
            : null,
      ),
    );
  }
}
