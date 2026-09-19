import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';

/// The one owner "delete server" flow, shared by the servers directory and
/// the management sheet so both confirm, route and explain failures the same
/// way.
///
/// The client only OFFERS the action. `deleteServerV1` (or, for a legacy
/// root, `deleteClubSelf`) re-proves ownership in its own transaction and
/// still refuses while any channel is live, whatever the client did first.

/// Channels whose live generation an owner delete would be refused over.
List<ServerChannel> liveServerChannels(Iterable<ServerChannel> channels) => [
  for (final channel in channels)
    if (channel.liveness.isLive && channel.activeSessionId != null) channel,
];

/// The label the owner has to type back: the name the directory shows.
String serverDeleteConfirmationName(Server server, AppLocalizations copy) {
  final name = server.name.trim();
  return name.isEmpty ? copy.serversTitle : name;
}

/// Asks the owner to confirm by typing the server's name. When [liveChannels]
/// is not empty (and the root is V1), the primary action becomes "End
/// conversations and delete". Resolves true only on an explicit confirmation.
Future<bool> confirmServerDeletion(
  BuildContext context, {
  required Server server,
  List<ServerChannel> liveChannels = const [],
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ServerDeleteDialog(
        server: server,
        endsLiveConversations: !server.isLegacy && liveChannels.isNotEmpty,
      ),
    ) ??
    false;

/// Routes the confirmed delete: a legacy root to `deleteClubSelf`, a V1 root
/// to `deleteServerV1` after ending each of [liveChannels].
///
/// A failure to end one generation is not fatal here: the generation may have
/// ended on its own a moment ago, and `deleteServerV1` re-checks liveness in
/// its transaction anyway, so the delete itself is the one answer that
/// counts.
Future<void> deleteServerFor({
  required ServerRepository repository,
  required ServerManagementRepository management,
  required Server server,
  List<ServerChannel> liveChannels = const [],
}) async {
  if (server.isLegacy) {
    // The legacy callable closes the Club's own lounge in its transaction.
    await management.deleteLegacyServer(serverId: server.id);
    return;
  }
  final requestId = repository.newRequestId();
  for (final channel in liveChannels) {
    final sessionId = channel.activeSessionId;
    if (sessionId == null) continue;
    try {
      await repository.endChannelSession(
        serverId: server.id,
        channelId: channel.id,
        sessionId: sessionId,
        requestId: repository.newRequestId(),
      );
    } on FirebaseFunctionsException {
      // See above: the delete below is the authority on liveness.
    }
  }
  await management.deleteServer(serverId: server.id, requestId: requestId);
}

/// Copy for a refused delete. A V1 `failed-precondition` is the live-session
/// refusal (`End the live session in this server before deleting it.`), so
/// it says exactly that instead of the generic "action denied".
String serverDeletionFailureCopy(
  Object error,
  AppLocalizations copy,
  Server server,
) {
  if (!server.isLegacy &&
      error is FirebaseFunctionsException &&
      error.code == 'failed-precondition') {
    return copy.serverDeleteLiveBlocked;
  }
  return serverActionFailureCopy(error, copy);
}

class _ServerDeleteDialog extends StatefulWidget {
  const _ServerDeleteDialog({
    required this.server,
    required this.endsLiveConversations,
  });

  final Server server;
  final bool endsLiveConversations;

  @override
  State<_ServerDeleteDialog> createState() => _ServerDeleteDialogState();
}

class _ServerDeleteDialogState extends State<_ServerDeleteDialog> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final name = serverDeleteConfirmationName(widget.server, copy);
    final matches = _typed.text.trim() == name;
    return AlertDialog(
      key: const ValueKey('server-delete-dialog'),
      icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
      title: Text(copy.serverDelete),
      scrollable: true,
      content: ConstrainedBox(
        // A dialog, not a stretched sheet: one readable measure at every
        // width, and the phone's own inset below it.
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              key: const ValueKey('server-delete-dialog-name'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppRhythm.tight),
            Text(
              copy.serverDeleteQuestion,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppRhythm.tight),
            Text(
              copy.serverDeleteConsequences,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            if (widget.endsLiveConversations) ...[
              const SizedBox(height: AppRhythm.item),
              Container(
                key: const ValueKey('server-delete-live-notice'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppRhythm.item),
                decoration: BoxDecoration(
                  color: palette.warningSurface,
                  borderRadius: AppRadius.md,
                ),
                child: Text(
                  copy.serverDeleteLiveBlocked,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.warningForeground,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppRhythm.title),
            // The instruction wraps as its own line (a field label would be
            // cut to one line on a phone) and is merged into the field's
            // semantics, so a screen reader still names the field.
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    copy.serverDeleteTypeName,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppRhythm.tight),
                  TextField(
                    key: const ValueKey('server-delete-confirm-field'),
                    controller: _typed,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (matches) Navigator.of(context).pop(true);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('server-delete-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(copy.serverCancel),
        ),
        FilledButton(
          key: const ValueKey('server-delete-confirm'),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: Text(
            widget.endsLiveConversations
                ? copy.serverEndAndDelete
                : copy.serverDelete,
          ),
        ),
      ],
    );
  }
}
