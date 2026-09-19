import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_invite_authority.dart';
import '../../data/models/server_session.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// `Zaproś`: pick a friend, send `createServerInviteV1`. The callable
/// re-proves the friendship, the role and every invitee state; this sheet
/// only offers the candidates and reports the receipt.
Future<void> showServerInviteSheet(
  BuildContext context, {
  required Server server,
  required ServerRepository repository,
  FirebaseFirestore? firestore,
  FirebaseAuth? auth,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
  builder: (_) => FractionallySizedBox(
    heightFactor: .85,
    child: ServerInviteSheet(
      server: server,
      repository: repository,
      firestore: firestore,
      auth: auth,
    ),
  ),
);

class ServerInviteSheet extends StatefulWidget {
  const ServerInviteSheet({
    required this.server,
    required this.repository,
    this.firestore,
    this.auth,
    super.key,
  });
  final Server server;
  final ServerRepository repository;

  /// Test-only, as elsewhere in the app: production passes nothing and the
  /// profile preview opened from a candidate row resolves its own Firebase
  /// instances, which a widget test does not have.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  @override
  State<ServerInviteSheet> createState() => _ServerInviteSheetState();
}

enum _RowState { idle, sending, sent, pending }

class _ServerInviteSheetState extends State<ServerInviteSheet> {
  late Stream<List<ServerInviteCandidate>> _candidates;
  final _rows = <String, _RowState>{};
  final _failures = <String, String>{};

  @override
  void initState() {
    super.initState();
    _candidates = widget.repository.watchInviteCandidates();
  }

  Future<void> _invite(ServerInviteCandidate person) async {
    if (_rows[person.id] == _RowState.sending) return;
    final copy = AppLocalizations.of(context);
    setState(() {
      _rows[person.id] = _RowState.sending;
      _failures.remove(person.id);
    });
    try {
      final result = await widget.repository.createInvite(
        serverId: widget.server.id,
        inviteeId: person.id,
        requestId: widget.repository.newRequestId(),
      );
      if (!mounted) return;
      setState(() {
        _rows[person.id] = result.alreadyExisted
            ? _RowState.pending
            : _RowState.sent;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyExisted
                ? copy.serverInvitePending(person.displayName)
                : copy.serverInviteSent(person.displayName),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rows[person.id] = _RowState.idle;
        _failures[person.id] = serverActionFailureCopy(
          error,
          copy,
          invite: true,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      widget.server.type,
    ).resolve(Theme.of(context).brightness);
    return Column(
      key: const ValueKey('server-invite-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The sheet's header is fixed above an `Expanded` list, so it
              // has to be bounded: a 118-character server name at 200 % text
              // in a 320-px sheet ran to fifteen lines and overflowed the
              // sheet by 507 px, taking the friend list with it.
              Text(
                '${copy.serverInvite} · ${widget.server.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                serverAdmitsPublicJoin(widget.server)
                    ? copy.serverInvitePublicBody
                    : copy.serverInviteBody,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ServerInviteCandidate>>(
            stream: _candidates,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SingleChildScrollView(
                  child: YoErrorState(
                    error: snapshot.error,
                    compact: true,
                    onRetry: () => setState(
                      () => _candidates = widget.repository
                          .watchInviteCandidates(),
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final people = snapshot.data ?? const <ServerInviteCandidate>[];
              if (people.isEmpty) {
                return SingleChildScrollView(
                  child: YoEmptyState(
                    icon: Icons.person_add_outlined,
                    title: copy.serverInviteNoFriendsTitle,
                    subtitle: copy.serverInviteNoFriendsBody,
                    compact: true,
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                itemCount: people.length,
                itemBuilder: (context, index) {
                  final person = people[index];
                  final state = _rows[person.id] ?? _RowState.idle;
                  final failure = _failures[person.id];
                  final done =
                      state == _RowState.sent || state == _RowState.pending;
                  return ListTile(
                    key: ValueKey('server-invite-${person.id}'),
                    minTileHeight: 56,
                    // The avatar only: the tile deliberately has no onTap
                    // so the trailing Invite button stays the single primary
                    // action. Looking at someone before inviting them is a
                    // read-only detour, so it stays live while a row sends.
                    leading: AccessibleTapRegion(
                      key: ValueKey('server-invite-profile-${person.id}'),
                      circular: true,
                      semanticLabel: copy.text('Open profile', 'Otwórz profil'),
                      tooltip: copy.text('Open profile', 'Otwórz profil'),
                      onTap: () => unawaited(
                        showProfilePreview(
                          context,
                          userId: person.id,
                          displayName: person.displayName,
                          firestore: widget.firestore,
                          auth: widget.auth,
                        ),
                      ),
                      child: ExcludeSemantics(
                        child: UserAvatar(
                          radius: 20,
                          userId: person.id,
                          displayName: person.displayName,
                          backgroundColor: colors.iconSurface,
                        ),
                      ),
                    ),
                    title: Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: failure != null
                        ? Text(
                            failure,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.dangerForeground),
                          )
                        : state == _RowState.pending
                        ? Text(
                            copy.serverInvitePending(person.displayName),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: state == _RowState.sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : done
                        ? Icon(
                            Icons.check_rounded,
                            color: colors.foreground,
                            semanticLabel: copy.serverInviteSent(
                              person.displayName,
                            ),
                          )
                        : FilledButton.tonal(
                            onPressed: () => _invite(person),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            child: Text(copy.serverInvite),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
