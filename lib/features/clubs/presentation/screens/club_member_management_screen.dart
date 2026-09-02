import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).text(
              'Role changed to ${role.label}.',
              'Zmieniono rolę na ${_roleLabel(role, AppLocalizations.of(context))}.',
            ),
          ),
        ),
      );
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
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Transfer ownership?', 'Przekazać własność klubu?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.member.displayName} will become the club owner. You will '
                  'be demoted to Co-owner. This cannot be undone by you alone.',
              '${widget.member.displayName} zostanie właścicielem klubu, a Twoja rola '
                  'zmieni się na współwłaściciela. Nie cofniesz tej zmiany samodzielnie.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Transfer', 'Przekaż')),
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
          content: Text(
            AppLocalizations.of(context).text(
              '${widget.member.displayName} is now the club owner.',
              '${widget.member.displayName} jest teraz właścicielem klubu.',
            ),
          ),
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
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Remove member?', 'Usunąć członka?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.member.displayName} will lose access to this club, its chat and Club Lounge.',
              '${widget.member.displayName} straci dostęp do klubu, czatu i klubowego pokoju głosowego.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Remove', 'Usuń')),
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
        SnackBar(
          content: Text(
            AppLocalizations.of(context).text(
              'Member removed from the club.',
              'Usunięto członka z klubu.',
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('club-member-management-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Member role', 'Rola członka')),
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
                  copy.text('CLUB ROLE', 'ROLA W KLUBIE'),
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
                    copy.text(
                      'Only a higher-ranking Owner or Co-owner can change this member’s role.',
                      'Rolę tej osoby może zmienić tylko właściciel lub współwłaściciel o wyższych uprawnieniach.',
                    ),
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
                    label: Text(
                      copy.text('TRANSFER OWNERSHIP', 'PRZEKAŻ WŁASNOŚĆ'),
                    ),
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
                    label: Text(copy.text('REMOVE FROM CLUB', 'USUŃ Z KLUBU')),
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

  String _message(Object error) {
    final copy = AppLocalizations.of(context);
    return friendlyErrorMessage(
      error,
      copy: copy,
      fallback: copy.text(
        'That action could not be completed. Please try again.',
        'Nie udało się wykonać tej czynności. Spróbuj ponownie.',
      ),
    );
  }

  static String _roleLabel(ClubRole role, AppLocalizations copy) {
    return switch (role) {
      ClubRole.owner => copy.text('Owner', 'Właściciel'),
      ClubRole.coOwner => copy.text('Co-owner', 'Współwłaściciel'),
      ClubRole.admin => copy.text('Admin', 'Administrator'),
      ClubRole.moderator => copy.text('Moderator', 'Moderator'),
      ClubRole.member => copy.text('Member', 'Członek'),
      ClubRole.guest => copy.text('Guest', 'Gość'),
    };
  }
}

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({required this.member});
  final ClubMember member;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          UserAvatar(
            radius: 31,
            userId: member.userId,
            displayName: member.displayName,
            backgroundColor: colors.primary,
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
                  _ClubMemberManagementScreenState._roleLabel(
                    member.role,
                    copy,
                  ),
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
    final copy = AppLocalizations.of(context);
    final subtitle = switch (role) {
      ClubRole.coOwner => copy.text(
        'Manage roles, club settings and channels',
        'Zarządzanie rolami, ustawieniami i kanałami',
      ),
      ClubRole.admin => copy.text(
        'Manage channels and club operations',
        'Zarządzanie kanałami i działaniem klubu',
      ),
      ClubRole.moderator => copy.text(
        'Invite and moderate members',
        'Zapraszanie i moderowanie członków',
      ),
      ClubRole.member => copy.text(
        'Standard club access',
        'Standardowy dostęp do klubu',
      ),
      ClubRole.guest => copy.text(
        'Limited club access',
        'Ograniczony dostęp do klubu',
      ),
      ClubRole.owner => copy.text('Full ownership', 'Pełne uprawnienia'),
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
          _ClubMemberManagementScreenState._roleLabel(role, copy),
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
