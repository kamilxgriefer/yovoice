import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_session.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import 'server_panel.dart';

/// `Dodaj kanał` → `createServerChannelV1`. Returns the created channel id
/// so the shell can select it.
Future<String?> showServerCreateChannelSheet(
  BuildContext context, {
  required Server server,
  required ServerRepository repository,
  required ServerMemberRole role,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ServerCreateChannelSheet(
      server: server,
      repository: repository,
      role: role,
    ),
  ),
);

class ServerCreateChannelSheet extends StatefulWidget {
  const ServerCreateChannelSheet({
    required this.server,
    required this.repository,
    required this.role,
    super.key,
  });
  final Server server;
  final ServerRepository repository;
  final ServerMemberRole role;

  /// The kinds a template offers when adding a channel. Media kinds carry
  /// the one media configuration `mediaConfiguration()` accepts for them.
  static List<ServerChannelKind> kindsFor(ServerType type) => [
    ServerChannelKind.text,
    ServerChannelKind.voice,
    ServerChannelKind.announcements,
    if (type == ServerType.community || type == ServerType.podcast)
      ServerChannelKind.stage,
    if (type == ServerType.company) ServerChannelKind.meeting,
  ];

  @override
  State<ServerCreateChannelSheet> createState() =>
      _ServerCreateChannelSheetState();
}

class _ServerCreateChannelSheetState extends State<ServerCreateChannelSheet> {
  final _name = TextEditingController();
  ServerChannelKind _kind = ServerChannelKind.text;
  bool _restricted = false;
  bool _busy = false;

  /// A failure the request came back with. It belongs to the attempt, not to
  /// the field, so it stays a message under the form.
  String? _error;

  /// A validation message about the name itself. It goes through
  /// `YoTextField(errorText:)` so it is attached to — and announced with —
  /// the editable node, rather than printed as an unassociated `Text` below
  /// the kind chips (WCAG 3.3.1 / 4.1.3).
  String? _nameError;
  String? _requestId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final copy = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = copy.serverChannelNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    // One request id per attempt at this exact input: a retry after a lost
    // answer replays instead of creating a second channel.
    _requestId ??= widget.repository.newRequestId();
    try {
      final result = await widget.repository.createChannel(
        ServerChannelCreationRequest(
          serverId: widget.server.id,
          requestId: _requestId!,
          kind: _kind,
          name: name,
          restricted: _restricted,
          mediaMode: switch (_kind) {
            ServerChannelKind.stage =>
              widget.server.type == ServerType.community
                  ? ServerMediaMode.video
                  : ServerMediaMode.audio,
            _ => null,
          },
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.serverChannelCreated)));
      Navigator.of(context).pop(result.channelId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = serverActionFailureCopy(error, copy);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final kinds = ServerCreateChannelSheet.kindsFor(widget.server.type);
    return SingleChildScrollView(
      key: const ValueKey('server-create-channel-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.serverNewChannelTitle,
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // `YoTextField` draws its `label` as a sibling `Text` and never
          // sets `labelText`, so nothing merges into the editable node and
          // the field has no accessible name of its own. Merging the block
          // gives the input the visible label as its name without adding a
          // second, duplicated one (WCAG 4.1.2).
          MergeSemantics(
            child: YoTextField(
              key: const ValueKey('server-channel-name'),
              controller: _name,
              label: copy.serverChannelNameLabel,
              errorText: _nameError,
              maxLength: 80,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                // Different input is a different request.
                _requestId = null;
                if (_error != null || _nameError != null) {
                  setState(() {
                    _error = null;
                    _nameError = null;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.serverChannelKindLabel,
            style: AppTypography.labelMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in kinds)
                ChoiceChip(
                  key: ValueKey('server-channel-kind-${kind.name}'),
                  avatar: Icon(serverChannelIcon(kind), size: 18),
                  label: Text(copy.serverChannelKindTitle(kind)),
                  selected: _kind == kind,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _kind = kind;
                          _requestId = null;
                        }),
                ),
            ],
          ),
          if (widget.role == ServerMemberRole.owner) ...[
            const SizedBox(height: 8),
            // Restricted creation is owner-only on the server, so the
            // toggle is offered to the owner alone.
            SwitchListTile.adaptive(
              key: const ValueKey('server-channel-restricted'),
              contentPadding: EdgeInsets.zero,
              value: _restricted,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _restricted = value;
                      _requestId = null;
                    }),
              title: Text(
                copy.serverChannelRestrictedToggle,
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('server-channel-error'),
              style: AppTypography.bodySmall.copyWith(
                color: palette.dangerForeground,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('server-channel-submit'),
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(
              _busy ? copy.serverCreating : copy.serverChannelCreateAction,
            ),
          ),
        ],
      ),
    );
  }
}
