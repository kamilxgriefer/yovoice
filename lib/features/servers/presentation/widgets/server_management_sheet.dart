import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

enum ServerManagementOutcome { left, deleted }

Future<ServerManagementOutcome?> showServerManagementSheet(
  BuildContext context, {
  required Server server,
  required List<ServerChannel> channels,
  required ServerMemberRole role,
  required ServerRepository repository,
  FirebaseFirestore? firestore,
  FirebaseAuth? auth,
}) {
  if (repository is! ServerManagementRepository) return Future.value();
  final management = repository as ServerManagementRepository;
  return showModalBottomSheet<ServerManagementOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    builder: (_) => FractionallySizedBox(
      heightFactor: .92,
      child: _ServerManagementSheet(
        initialServer: server,
        initialChannels: channels,
        role: role,
        repository: repository,
        management: management,
        firestore: firestore,
        auth: auth,
      ),
    ),
  );
}

class _ServerManagementSheet extends StatefulWidget {
  const _ServerManagementSheet({
    required this.initialServer,
    required this.initialChannels,
    required this.role,
    required this.repository,
    required this.management,
    this.firestore,
    this.auth,
  });

  final Server initialServer;
  final List<ServerChannel> initialChannels;
  final ServerMemberRole role;
  final ServerRepository repository;
  final ServerManagementRepository management;

  /// Test-only, as elsewhere in the app: production passes nothing and the
  /// profile preview opened from a member row resolves its own Firebase
  /// instances, which a widget test does not have.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  @override
  State<_ServerManagementSheet> createState() => _ServerManagementSheetState();
}

class _ServerManagementSheetState extends State<_ServerManagementSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final Stream<Server?> _server;
  late final Stream<List<ServerChannel>> _channels;
  late final Stream<List<ServerMember>> _members;
  late ServerPrivacy _privacy;
  late int _expectedServerRevision;
  var _section = 0;
  var _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialServer.name);
    _description = TextEditingController(
      text: widget.initialServer.description,
    );
    _privacy = widget.initialServer.privacy;
    _expectedServerRevision = widget.initialServer.revision;
    _server = widget.repository.watchServer(widget.initialServer.id);
    _channels = widget.repository.watchChannels(widget.initialServer.id);
    _members = widget.management.watchMembers(widget.initialServer.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return true;
      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = AppLocalizations.of(context).serverSaved;
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = serverActionFailureCopy(error, AppLocalizations.of(context));
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      widget.initialServer.type,
    ).resolve(Theme.of(context).brightness);
    return Material(
      color: palette.background,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.iconSurface,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: colors.iconBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.initialServer.initial,
                    style: AppTypography.titleSmall.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.serverSettings,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        widget.initialServer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('server-management-close'),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _SectionChip(
                  label: copy.serverOverview,
                  icon: Icons.tune_rounded,
                  selected: _section == 0,
                  onSelected: () => setState(() => _section = 0),
                ),
                const SizedBox(width: 8),
                _SectionChip(
                  label: copy.serverChannels,
                  icon: Icons.tag_rounded,
                  selected: _section == 1,
                  onSelected: () => setState(() => _section = 1),
                ),
                const SizedBox(width: 8),
                _SectionChip(
                  label: copy.serverMembersTitle,
                  icon: Icons.group_outlined,
                  selected: _section == 2,
                  onSelected: () => setState(() => _section = 2),
                ),
              ],
            ),
          ),
          if (_message != null)
            Container(
              key: const ValueKey('server-management-message'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _messageIsError
                    ? palette.dangerSurface
                    : palette.successSurface,
                borderRadius: AppRadius.md,
              ),
              child: Text(
                _message!,
                style: AppTypography.bodySmall.copyWith(
                  color: _messageIsError
                      ? palette.dangerForeground
                      : palette.successForeground,
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: StreamBuilder<Server?>(
              stream: _server,
              initialData: widget.initialServer,
              builder: (context, serverSnapshot) {
                final server = serverSnapshot.data;
                if (server == null) {
                  return Center(
                    child: Text(
                      copy.text(
                        'Server unavailable',
                        'Serwer jest niedostępny',
                      ),
                    ),
                  );
                }
                return StreamBuilder<List<ServerChannel>>(
                  stream: _channels,
                  initialData: widget.initialChannels,
                  builder: (context, channelSnapshot) {
                    final channels = channelSnapshot.data ?? const [];
                    return switch (_section) {
                      0 => _overview(context, server),
                      1 => _channelList(context, server, channels),
                      _ => _memberList(context, server),
                    };
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(BuildContext context, Server server) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final canEdit = widget.role.power >= ServerMemberRole.coOwner.power;
    final privacyOptions = _privacyOptions(server.type);
    return ListView(
      key: const ValueKey('server-management-overview'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        TextField(
          key: const ValueKey('server-management-name'),
          controller: _name,
          enabled: canEdit && !_busy,
          maxLength: 40,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: copy.serverNameLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('server-management-description'),
          controller: _description,
          enabled: canEdit && !_busy,
          maxLength: 220,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: copy.serverDescriptionLabel),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ServerPrivacy>(
          key: const ValueKey('server-management-privacy'),
          initialValue: privacyOptions.contains(_privacy)
              ? _privacy
              : privacyOptions.first,
          decoration: InputDecoration(labelText: copy.serverPrivacyLabel),
          items: [
            for (final privacy in privacyOptions)
              DropdownMenuItem(
                value: privacy,
                child: Text(copy.serverPrivacyTitle(privacy)),
              ),
          ],
          onChanged: canEdit && !_busy
              ? (value) {
                  if (value != null) setState(() => _privacy = value);
                }
              : null,
        ),
        if (canEdit) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('server-management-save'),
            onPressed: _busy || _name.text.trim().length < 3
                ? null
                : () async {
                    final saved = await _run(
                      () => widget.management.updateServer(
                        serverId: server.id,
                        // The revision belongs to the snapshot that populated
                        // these controllers. A newer stream snapshot must not
                        // bless stale form values and overwrite another
                        // manager's edit.
                        expectedRevision: _expectedServerRevision,
                        patch: {
                          'name': _name.text.trim(),
                          'description': _description.text.trim(),
                          'privacy': _privacy.name,
                          'defaultLanguage': server.defaultLanguage,
                        },
                        requestId: widget.repository.newRequestId(),
                      ),
                    );
                    if (saved) _expectedServerRevision += 1;
                  },
            icon: const Icon(Icons.check_rounded),
            label: Text(copy.serverSaveChanges),
          ),
        ],
        const SizedBox(height: 28),
        Divider(color: palette.border),
        const SizedBox(height: 12),
        if (widget.role == ServerMemberRole.owner)
          OutlinedButton.icon(
            key: const ValueKey('server-delete-action'),
            onPressed: _busy ? null : () => _deleteServer(context, server),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.dangerForeground,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(copy.serverDelete),
          )
        else
          OutlinedButton.icon(
            key: const ValueKey('server-leave-action'),
            onPressed: _busy ? null : () => _leaveServer(context, server),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.dangerForeground,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(copy.serverLeave),
          ),
      ],
    );
  }

  Widget _channelList(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
  ) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    if (channels.isEmpty) {
      return Center(child: Text(copy.serverNoChannelsBody));
    }
    return ListView.separated(
      key: const ValueKey('server-management-channels'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      itemCount: channels.length,
      separatorBuilder: (_, _) => Divider(color: palette.border, height: 1),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ListTile(
          key: ValueKey('server-management-channel-${channel.id}'),
          minTileHeight: 56,
          leading: Icon(serverChannelManagementIcon(channel.kind)),
          title: Text(channel.name),
          subtitle: Text(
            channel.access == ServerChannelAccess.restricted
                ? copy.serverChannelRestricted
                : copy.serverEveryoneInServer,
          ),
          trailing: !widget.role.canManage
              ? null
              : PopupMenuButton<_ChannelAction>(
                  enabled: !_busy,
                  tooltip: copy.text('Channel actions', 'Działania kanału'),
                  onSelected: (action) => _handleChannelAction(
                    context,
                    server,
                    channels,
                    index,
                    action,
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _ChannelAction.rename,
                      child: Text(copy.serverRenameChannel),
                    ),
                    PopupMenuItem(
                      value: _ChannelAction.access,
                      child: Text(copy.serverChannelAccess),
                    ),
                    if (index > 0)
                      PopupMenuItem(
                        value: _ChannelAction.up,
                        child: Text(copy.serverMoveUp),
                      ),
                    if (index + 1 < channels.length)
                      PopupMenuItem(
                        value: _ChannelAction.down,
                        child: Text(copy.serverMoveDown),
                      ),
                    PopupMenuItem(
                      value: _ChannelAction.archive,
                      child: Text(copy.serverArchiveChannel),
                    ),
                    PopupMenuItem(
                      value: _ChannelAction.delete,
                      child: Text(
                        copy.serverDeleteChannel,
                        style: TextStyle(color: palette.dangerForeground),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _memberList(BuildContext context, Server server) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return StreamBuilder<List<ServerMember>>(
      stream: _members,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                serverActionFailureCopy(snapshot.error!, copy),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = snapshot.data!;
        if (members.isEmpty) return Center(child: Text(copy.serverNoMembers));
        return ListView.separated(
          key: const ValueKey('server-management-members'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          itemCount: members.length,
          separatorBuilder: (_, _) => Divider(color: palette.border, height: 1),
          itemBuilder: (context, index) {
            final member = members[index];
            final actions = _memberActions(member);
            return ListTile(
              key: ValueKey('server-management-member-${member.id}'),
              minTileHeight: 64,
              // The canonical widget, exactly as the sibling invite sheet
              // uses it: the denormalized photoUrl bypassed the viewer /
              // visibility / block recheck, and a failed load painted an
              // empty disc with no initial at all.
              //
              // The avatar alone is the profile target; the trailing
              // role/ban/remove menu keeps its own. The preview is
              // read-only, so it stays live while a mutation is in flight.
              leading: AccessibleTapRegion(
                key: ValueKey('server-management-profile-${member.id}'),
                circular: true,
                semanticLabel: copy.text('Open profile', 'Otwórz profil'),
                tooltip: copy.text('Open profile', 'Otwórz profil'),
                onTap: () => unawaited(
                  showProfilePreview(
                    context,
                    userId: member.id,
                    displayName: member.displayName,
                    firestore: widget.firestore,
                    auth: widget.auth,
                  ),
                ),
                child: ExcludeSemantics(
                  child: UserAvatar(
                    radius: 20,
                    userId: member.id,
                    displayName: member.displayName,
                    backgroundColor: ServerIdentity.of(server.type)
                        .resolve(Theme.of(context).brightness)
                        .iconSurface,
                  ),
                ),
              ),
              title: Text(member.displayName),
              subtitle: Text(
                '${_roleLabel(copy, member.role)}'
                '${member.isBanned ? ' · ${copy.serverBannedLabel}' : ''}',
              ),
              trailing: actions.isEmpty
                  ? null
                  : PopupMenuButton<_MemberAction>(
                      enabled: !_busy,
                      tooltip: copy.text('Member actions', 'Działania członka'),
                      onSelected: (action) =>
                          _handleMemberAction(context, server, member, action),
                      itemBuilder: (_) => [
                        for (final action in actions)
                          PopupMenuItem(
                            value: action,
                            child: Text(
                              _memberActionLabel(copy, action, member),
                              style:
                                  action == _MemberAction.remove ||
                                      action == _MemberAction.ban
                                  ? TextStyle(color: palette.dangerForeground)
                                  : null,
                            ),
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  List<_MemberAction> _memberActions(ServerMember member) {
    if (member.id == widget.repository.currentUserId ||
        member.role == ServerMemberRole.owner ||
        member.role.power >= widget.role.power) {
      return const [];
    }
    return [
      if (widget.role == ServerMemberRole.owner ||
          widget.role == ServerMemberRole.coOwner)
        _MemberAction.role,
      if (widget.role.canModerate)
        member.isBanned ? _MemberAction.unban : _MemberAction.ban,
      if (widget.role.canModerate) _MemberAction.remove,
      if (widget.role == ServerMemberRole.owner) _MemberAction.transfer,
    ];
  }

  Future<void> _handleChannelAction(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
    int index,
    _ChannelAction action,
  ) async {
    final copy = AppLocalizations.of(context);
    final channel = channels[index];
    switch (action) {
      case _ChannelAction.rename:
        final name = await _textDialog(
          context,
          title: copy.serverRenameChannel,
          initialValue: channel.name,
          maxLength: 80,
        );
        if (name == null || name == channel.name) return;
        await _run(
          () => widget.management.updateChannel(
            serverId: server.id,
            channelId: channel.id,
            expectedRevision: channel.revision,
            patch: {'name': name},
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _ChannelAction.access:
        final access = await _accessDialog(context, channel.access);
        if (access == null || access == channel.access) return;
        final roles =
            access == ServerChannelAccess.members
                  ? const <String>[]
                  : <String>{'owner', ...channel.accessRoleIds}.toList()
              ..sort();
        await _run(
          () => widget.management.setChannelAccess(
            serverId: server.id,
            channelId: channel.id,
            expectedAclRevision: channel.aclRevision,
            access: access,
            roleIds: roles,
            userIds: access == ServerChannelAccess.members
                ? const []
                : channel.accessUserIds,
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _ChannelAction.up:
      case _ChannelAction.down:
        final target = action == _ChannelAction.up ? index - 1 : index + 1;
        final reordered = List<ServerChannel>.of(channels);
        final item = reordered.removeAt(index);
        reordered.insert(target, item);
        await _run(
          () => widget.management.reorderChannels(
            serverId: server.id,
            expectedRevision: server.revision,
            channelIds: reordered.map((item) => item.id).toList(),
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _ChannelAction.archive:
        if (!await _confirm(context, copy.serverArchiveChannelQuestion)) return;
        await _run(
          () => widget.management.archiveChannel(
            serverId: server.id,
            channelId: channel.id,
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _ChannelAction.delete:
        if (!await _confirm(context, copy.serverDeleteChannelQuestion)) return;
        await _run(
          () => widget.management.deleteChannel(
            serverId: server.id,
            channelId: channel.id,
            requestId: widget.repository.newRequestId(),
          ),
        );
    }
  }

  Future<void> _handleMemberAction(
    BuildContext context,
    Server server,
    ServerMember member,
    _MemberAction action,
  ) async {
    final copy = AppLocalizations.of(context);
    switch (action) {
      case _MemberAction.role:
        final role = await _roleDialog(context, member.role);
        if (role == null || role == member.role) return;
        await _run(
          () => widget.management.setMemberRole(
            serverId: server.id,
            memberId: member.id,
            role: role,
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _MemberAction.ban:
        final reason = await _textDialog(
          context,
          title: copy.serverBanMember,
          label: copy.serverBanReason,
          maxLength: 240,
        );
        if (reason == null || reason.isEmpty) return;
        await _run(
          () => widget.management.setMemberBan(
            serverId: server.id,
            memberId: member.id,
            banned: true,
            reason: reason,
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _MemberAction.unban:
        await _run(
          () => widget.management.setMemberBan(
            serverId: server.id,
            memberId: member.id,
            banned: false,
            reason: '',
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _MemberAction.remove:
        if (!await _confirm(
          context,
          '${copy.serverRemoveMember}: ${member.displayName}?',
        )) {
          return;
        }
        await _run(
          () => widget.management.removeMember(
            serverId: server.id,
            memberId: member.id,
            requestId: widget.repository.newRequestId(),
          ),
        );
      case _MemberAction.transfer:
        if (!await _confirm(
          context,
          '${copy.serverTransferOwnership}: ${member.displayName}?',
        )) {
          return;
        }
        await _run(
          () => widget.management.transferOwnership(
            serverId: server.id,
            newOwnerId: member.id,
            requestId: widget.repository.newRequestId(),
          ),
        );
    }
  }

  Future<void> _leaveServer(BuildContext context, Server server) async {
    final copy = AppLocalizations.of(context);
    if (!await _confirm(context, copy.serverLeaveQuestion)) return;
    if (await _run(
          () => widget.management.leaveServer(
            serverId: server.id,
            requestId: widget.repository.newRequestId(),
          ),
        ) &&
        mounted) {
      Navigator.of(this.context).pop(ServerManagementOutcome.left);
    }
  }

  Future<void> _deleteServer(BuildContext context, Server server) async {
    final copy = AppLocalizations.of(context);
    if (!await _confirm(context, copy.serverDeleteQuestion)) return;
    if (await _run(
          () => widget.management.deleteServer(
            serverId: server.id,
            requestId: widget.repository.newRequestId(),
          ),
        ) &&
        mounted) {
      Navigator.of(this.context).pop(ServerManagementOutcome.deleted);
    }
  }

  Future<String?> _textDialog(
    BuildContext context, {
    required String title,
    String? label,
    String initialValue = '',
    required int maxLength,
  }) async {
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(copy.serverConfirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<ServerChannelAccess?> _accessDialog(
    BuildContext context,
    ServerChannelAccess current,
  ) {
    final copy = AppLocalizations.of(context);
    return showDialog<ServerChannelAccess>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(copy.serverChannelAccess),
        children: [
          ListTile(
            minTileHeight: 56,
            leading: Icon(
              current == ServerChannelAccess.members
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
            ),
            title: Text(copy.serverEveryoneInServer),
            onTap: () =>
                Navigator.of(dialogContext).pop(ServerChannelAccess.members),
          ),
          ListTile(
            minTileHeight: 56,
            leading: Icon(
              current == ServerChannelAccess.restricted
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
            ),
            title: Text(copy.serverRestrictedChannel),
            onTap: () =>
                Navigator.of(dialogContext).pop(ServerChannelAccess.restricted),
          ),
        ],
      ),
    );
  }

  Future<ServerMemberRole?> _roleDialog(
    BuildContext context,
    ServerMemberRole current,
  ) {
    final copy = AppLocalizations.of(context);
    final roles = ServerMemberRole.values
        .where(
          (role) =>
              role != ServerMemberRole.owner && role.power < widget.role.power,
        )
        .toList();
    return showDialog<ServerMemberRole>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(copy.serverChangeRole),
        children: [
          for (final role in roles)
            ListTile(
              minTileHeight: 56,
              leading: Icon(
                current == role
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
              ),
              title: Text(_roleLabel(copy, role)),
              onTap: () => Navigator.of(dialogContext).pop(role),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String body) async {
    final copy = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(copy.serverCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(copy.serverConfirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  List<ServerPrivacy> _privacyOptions(ServerType type) => switch (type) {
    ServerType.family => const [ServerPrivacy.inviteOnly],
    ServerType.friends || ServerType.company => const [
      ServerPrivacy.private,
      ServerPrivacy.inviteOnly,
    ],
    ServerType.community || ServerType.podcast => ServerPrivacy.values,
  };
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: (_) => onSelected(),
    avatar: Icon(icon, size: 18),
    label: Text(label),
  );
}

enum _ChannelAction { rename, access, up, down, archive, delete }

enum _MemberAction { role, ban, unban, remove, transfer }

String _roleLabel(AppLocalizations copy, ServerMemberRole role) =>
    switch (role) {
      ServerMemberRole.owner => copy.serverOwnerRole,
      ServerMemberRole.coOwner => copy.serverCoOwnerRole,
      ServerMemberRole.admin => copy.serverAdminRole,
      ServerMemberRole.moderator => copy.serverModerator,
      ServerMemberRole.member => copy.serverMemberRoleLabel,
      ServerMemberRole.guest => copy.serverGuestRole,
    };

String _memberActionLabel(
  AppLocalizations copy,
  _MemberAction action,
  ServerMember member,
) => switch (action) {
  _MemberAction.role => copy.serverChangeRole,
  _MemberAction.ban => copy.serverBanMember,
  _MemberAction.unban => copy.serverUnbanMember,
  _MemberAction.remove => copy.serverRemoveMember,
  _MemberAction.transfer => copy.serverTransferOwnership,
};

IconData serverChannelManagementIcon(ServerChannelKind kind) => switch (kind) {
  ServerChannelKind.voice => Icons.graphic_eq_rounded,
  ServerChannelKind.stage => Icons.sensors_rounded,
  ServerChannelKind.events ||
  ServerChannelKind.calendar => Icons.calendar_month_outlined,
  ServerChannelKind.announcements => Icons.campaign_outlined,
  ServerChannelKind.rules => Icons.gavel_outlined,
  ServerChannelKind.questions => Icons.question_answer_outlined,
  ServerChannelKind.episodes => Icons.podcasts_outlined,
  ServerChannelKind.memories => Icons.auto_awesome_outlined,
  ServerChannelKind.list => Icons.checklist_rounded,
  ServerChannelKind.meeting => Icons.video_call_outlined,
  ServerChannelKind.whiteboard => Icons.draw_outlined,
  ServerChannelKind.files => Icons.folder_outlined,
  ServerChannelKind.text => Icons.tag_rounded,
};
