import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

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

  Future<void> _transferOwnership() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            'Transfer ownership?',
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            '${widget.member.displayName} will become the club owner. You will '
            'be demoted to Co-owner. This cannot be undone by you alone.',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('Transfer'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.transferOwnership(
        clubId: widget.clubId,
        newOwnerId: widget.member.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.member.displayName} is now the club owner.'),
        ),
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

  Future<void> _removeMember() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            'Remove member?',
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            '${widget.member.displayName} will lose access to this club, its chat and Club Lounge.',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('club-member-management-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: const Text('Member role'),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: StreamBuilder<ClubMember?>(
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
            final canTransferOwnership =
                actor != null &&
                actor.role == ClubRole.owner &&
                actor.userId != widget.member.userId &&
                widget.member.role != ClubRole.owner;

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
              children: [
                _MemberHeader(member: widget.member),
                const SizedBox(height: 22),
                Text(
                  'CLUB ROLE',
                  style: TextStyle(
                    color: palette.textTertiary,
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
                  Text(
                    'Only a higher-ranking Owner or Co-owner can change this member’s role.',
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (canTransferOwnership) ...[
                  const SizedBox(height: 26),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _transferOwnership,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: palette.borderStrong),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('TRANSFER OWNERSHIP'),
                  ),
                ],
                if (canRemove) ...[
                  const SizedBox(height: 26),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _removeMember,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.person_remove_rounded),
                    label: const Text('REMOVE FROM CLUB'),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 20),
                  Center(
                    child: CircularProgressIndicator(color: colors.primary),
                  ),
                ],
              ],
            );
          },
        ),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final hasPhoto = member.photoUrl?.isNotEmpty ?? false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: colors.primary,
            backgroundImage: hasPhoto ? NetworkImage(member.photoUrl!) : null,
            child: hasPhoto
                ? null
                : Text(
                    member.initial,
                    style: TextStyle(
                      color: colors.onPrimary,
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
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  member.role.label,
                  style: TextStyle(
                    color: colors.primary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
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
        tileColor: selected ? colors.primaryContainer : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: selected ? colors.primary : palette.border),
        ),
        leading: Icon(
          selected ? Icons.verified_rounded : Icons.shield_outlined,
          color: enabled || selected
              ? colors.primary
              : palette.navigationInactive,
        ),
        title: Text(
          role.label,
          style: TextStyle(
            color: enabled || selected
                ? palette.textPrimary
                : palette.navigationInactive,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: palette.textSecondary, fontSize: 11),
        ),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: colors.primary)
            : null,
      ),
    );
  }
}
