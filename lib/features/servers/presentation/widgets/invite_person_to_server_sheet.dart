import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_creation.dart';
import '../../data/models/server_invite_authority.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';

/// `Zaproś na serwer` from a person's profile: the reverse of
/// [ServerInviteSheet] — the person is fixed and the viewer picks one of
/// their servers. Only servers where [canInviteToServer] holds for the
/// viewer's own role are offered; `createServerInviteV1` re-proves the role,
/// the friendship and every invitee state and stays the only authority.
Future<void> showInvitePersonToServerSheet(
  BuildContext context, {
  required String inviteeId,
  required String inviteeName,
  required ServerRepository repository,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(
    context,
    maxWidth: 560,
  ),
  builder: (_) => FractionallySizedBox(
    heightFactor: .7,
    child: InvitePersonToServerSheet(
      inviteeId: inviteeId,
      inviteeName: inviteeName,
      repository: repository,
    ),
  ),
);

enum _InviteRowState { idle, sending, sent, alreadyMember, failed }

class InvitePersonToServerSheet extends StatefulWidget {
  const InvitePersonToServerSheet({
    required this.inviteeId,
    required this.inviteeName,
    required this.repository,
    super.key,
  });

  final String inviteeId;
  final String inviteeName;
  final ServerRepository repository;

  @override
  State<InvitePersonToServerSheet> createState() =>
      _InvitePersonToServerSheetState();
}

class _InvitePersonToServerSheetState extends State<InvitePersonToServerSheet> {
  StreamSubscription<List<Server>>? _serversSubscription;

  /// One role listener per server, bound to the sheet's lifetime.
  final _roleSubscriptions = <String, StreamSubscription<ServerMemberRole?>>{};
  final _roles = <String, ServerMemberRole?>{};
  final _rolesSeen = <String>{};
  final _rows = <String, _InviteRowState>{};
  final _failures = <String, String>{};
  List<Server>? _servers;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _serversSubscription?.cancel();
    _serversSubscription = widget.repository.watchMyServers().listen(
      _handleServers,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = error);
      },
    );
  }

  void _handleServers(List<Server> servers) {
    if (!mounted) return;
    final live = {
      for (final server in servers)
        if (!server.isHeld) server.id,
    };
    for (final id in _roleSubscriptions.keys.toList()) {
      if (live.contains(id)) continue;
      _roleSubscriptions.remove(id)?.cancel();
      _roles.remove(id);
      _rolesSeen.remove(id);
    }
    for (final id in live) {
      _roleSubscriptions.putIfAbsent(
        id,
        () => widget.repository
            .watchMyRole(id)
            .listen(
              (role) {
                if (!mounted) return;
                setState(() {
                  _roles[id] = role;
                  _rolesSeen.add(id);
                });
              },
              onError: (Object _) {
                // An unreadable role offers nothing: fail closed.
                if (!mounted) return;
                setState(() {
                  _roles[id] = null;
                  _rolesSeen.add(id);
                });
              },
            ),
      );
    }
    setState(() {
      _error = null;
      _servers = servers;
    });
  }

  @override
  void dispose() {
    _serversSubscription?.cancel();
    for (final subscription in _roleSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _retry() {
    setState(() {
      _error = null;
      _servers = null;
    });
    _subscribe();
  }

  Future<void> _invite(Server server) async {
    final current = _rows[server.id];
    if (current == _InviteRowState.sending || current == _InviteRowState.sent) {
      return;
    }
    final copy = AppLocalizations.of(context);
    setState(() {
      _rows[server.id] = _InviteRowState.sending;
      _failures.remove(server.id);
    });
    try {
      await widget.repository.createInvite(
        serverId: server.id,
        inviteeId: widget.inviteeId,
        requestId: widget.repository.newRequestId(),
      );
      if (!mounted) return;
      setState(() => _rows[server.id] = _InviteRowState.sent);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_isAlreadyMemberRefusal(error)) {
          _rows[server.id] = _InviteRowState.alreadyMember;
          return;
        }
        _rows[server.id] = _InviteRowState.failed;
        _failures[server.id] = _inviteFailureCopy(error, copy);
      });
    }
  }

  /// `failed-precondition` is shared by several backend refusals: the
  /// server-shell activation gate (`details.reason`), the inviter's email
  /// verification guard, and the membership check. Only the membership check
  /// means the person is already on the server; everything else stays a
  /// retryable failure with its own copy.
  static const _alreadyMemberMessage =
      'This person already belongs to this server.';
  static const _emailVerificationMessage =
      'Verify your email before continuing.';

  static bool _isAlreadyMemberRefusal(Object error) =>
      error is FirebaseFunctionsException &&
      error.code == 'failed-precondition' &&
      !isServerActivationUnavailableFailure(error) &&
      error.message == _alreadyMemberMessage;

  static String _inviteFailureCopy(Object error, AppLocalizations copy) {
    if (isServerActivationUnavailableFailure(error)) {
      return serverActionFailureCopy(error, copy, invite: true);
    }
    if (error is FirebaseFunctionsException) {
      if (error.code == 'permission-denied') {
        return copy.text(
          'Could not send the invite.',
          'Nie udało się zaprosić.',
        );
      }
      if (error.code == 'failed-precondition' &&
          error.message == _emailVerificationMessage) {
        return copy.text('Verify your email', 'Zweryfikuj adres e-mail');
      }
    }
    return serverActionFailureCopy(error, copy, invite: true);
  }

  List<Server> get _eligible => [
    for (final server in _servers ?? const <Server>[])
      if (!server.isHeld && canInviteToServer(server, _roles[server.id]))
        server,
  ];

  bool get _loading {
    final servers = _servers;
    if (servers == null) return true;
    if (_eligible.isNotEmpty) return false;
    return servers.any(
      (server) => !server.isHeld && !_rolesSeen.contains(server.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Column(
      key: const ValueKey('invite-person-to-server-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Invite to a server', 'Zaproś na serwer'),
                style: AppTypography.titleLarge.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                copy.template(
                  'Choose a server for {name}.',
                  'Wybierz serwer dla: {name}.',
                  values: {'name': widget.inviteeName},
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (_error != null) {
      return SingleChildScrollView(
        child: YoErrorState(
          key: const ValueKey('invite-person-to-server-error'),
          error: _error,
          compact: true,
          onRetry: _retry,
        ),
      );
    }
    if (_loading) {
      return Column(
        key: const ValueKey('invite-person-to-server-loading'),
        children: [for (var i = 0; i < 3; i++) const _SkeletonRow()],
      );
    }
    final servers = _eligible;
    if (servers.isEmpty) {
      return SingleChildScrollView(
        child: YoEmptyState(
          key: const ValueKey('invite-person-to-server-empty'),
          icon: Icons.group_add_outlined,
          title: copy.text(
            'You have no servers you can invite people to.',
            'Nie masz serwerów, na które możesz zapraszać.',
          ),
          compact: true,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: servers.length,
      itemBuilder: (context, index) => _row(context, servers[index]),
    );
  }

  Widget _row(BuildContext context, Server server) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final state = _rows[server.id] ?? _InviteRowState.idle;
    final failure = _failures[server.id];
    final String? subtitle = switch (state) {
      _InviteRowState.alreadyMember => copy.text(
        'Already on this server',
        'Już jest na tym serwerze',
      ),
      _InviteRowState.failed => failure,
      _ => copy.serverTypeTitle(server.type),
    };
    final Widget trailing = switch (state) {
      _InviteRowState.sending => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _InviteRowState.sent => OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          disabledForegroundColor: palette.textSecondary,
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: Text(copy.text('Invited', 'Zaproszono')),
      ),
      _InviteRowState.alreadyMember => const SizedBox.shrink(),
      _ => OutlinedButton(
        key: ValueKey('invite-person-to-server-${server.id}'),
        onPressed: () => _invite(server),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(copy.serverInvite),
      ),
    };
    return ListTile(
      key: ValueKey('invite-person-to-server-row-${server.id}'),
      minTileHeight: 64,
      leading: ExcludeSemantics(
        child: YoServerTile(
          initial: server.initial,
          type: server.type,
          size: 40,
        ),
      ),
      title: Text(
        server.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: state == _InviteRowState.failed
                    ? palette.dangerForeground
                    : palette.textSecondary,
              ),
            ),
      trailing: trailing,
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: .6,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: .35,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
