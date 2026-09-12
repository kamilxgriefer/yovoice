import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// A text channel's thread: the existing club message store read at
/// `clubs/{serverId}/channels/{channelId}/messages` and written through
/// `sendClubMessage`, which already enforces V1 channel access
/// (`assertServerChannelAccessIfVersioned`). No parallel message path.
///
/// Draws no app bar: it is a scene inside the shell at every width.
class ServerTextChannelScene extends StatefulWidget {
  const ServerTextChannelScene({
    required this.server,
    required this.channel,
    required this.currentUserId,
    this.chatService,
    this.moderatorIds = const {},
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;

  /// The viewer, for "mine" styling only; authority comes from the service.
  final String currentUserId;

  /// Test seam; production builds the real service.
  final ClubChatService? chatService;

  /// The ids the server's own member roster returns with moderator power or
  /// above. A badge is drawn for exactly these and for nobody else: the
  /// message document carries no role, so an unread roster means no badge —
  /// never a guessed one (board 02's live chat).
  final Set<String> moderatorIds;

  /// Tighter paddings inside a context panel.
  final bool compact;

  @override
  State<ServerTextChannelScene> createState() => _ServerTextChannelSceneState();
}

class _ServerTextChannelSceneState extends State<ServerTextChannelScene> {
  /// Built on first use, never in `initState`: a held root reads nothing, so
  /// it must not even construct a message service.
  ClubChatService? _built;
  ClubChatService get _service =>
      _built ??= widget.chatService ?? ClubChatService();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Stream<List<ClubMessage>>? _messages;
  Stream<ClubChatAuthority>? _authority;
  bool _sending = false;

  /// How much of the scene the composer (or the read-only notice) may take
  /// before it starts scrolling inside its own band.
  static const _footShare = .62;

  bool get _announcement =>
      widget.channel.kind == ServerChannelKind.announcements ||
      widget.channel.kind == ServerChannelKind.rules;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ServerTextChannelScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.server.isHeld != widget.server.isHeld) {
      _listen();
    }
  }

  void _listen() {
    // Rules deny message reads on a held root (`isClubMember` requires an
    // active root), so nothing is subscribed while the server is preparing.
    if (widget.server.isHeld) {
      _messages = null;
      _authority = null;
      return;
    }
    // Resolved once per channel, never per build: a rebuilt stream would
    // resubscribe and flash the spinner over a thread still on screen.
    _messages = _service.watchMessages(
      clubId: widget.server.id,
      channelId: widget.channel.id,
    );
    _authority = _service.watchAuthority(widget.server.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final copy = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        clubId: widget.server.id,
        channelId: widget.channel.id,
        text: text,
      );
      _controller.clear();
      _focus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.serverSendFailed)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    if (widget.server.isHeld) {
      // Rules deny message reads on a held root (`isClubMember` requires an
      // active root), so the thread is not even subscribed.
      return SingleChildScrollView(
        child: YoEmptyState(
          icon: Icons.forum_outlined,
          title: copy.channelEmptyTitle(widget.channel.kind),
          subtitle: copy.serverHeldBody,
          compact: widget.compact,
        ),
      );
    }
    final currentUserId = widget.currentUserId;
    return StreamBuilder<ClubChatAuthority>(
      stream: _authority,
      initialData: ClubChatAuthority(viewerId: currentUserId),
      builder: (context, authoritySnapshot) {
        final authority =
            authoritySnapshot.data ??
            ClubChatAuthority(viewerId: currentUserId);
        final canWrite = authority.canSendToChannel(
          announcement: _announcement,
        );
        final foot = canWrite
            ? _Composer(
                controller: _controller,
                focusNode: _focus,
                sending: _sending,
                hint: copy.serverMessageHint(widget.channel.name),
                sendLabel: copy.serverSend,
                onSend: _send,
                compact: widget.compact,
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  _announcement
                      ? copy.serverAnnouncementsOnlyBody
                      : copy.serverReadOnlyBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              );
        // The composer — or the read-only sentence standing in for it — is the
        // one part of this scene that cannot shrink, and it is mounted in
        // columns whose height belongs to somebody else (the desktop context
        // panel, a phone tab). At 200 % text a short column made it taller
        // than the whole scene and the surface drew the overflow banner. It
        // now keeps a bounded share and scrolls inside it, so the thread above
        // is squeezed rather than the layout broken; at every ordinary size
        // this changes nothing, because the cap is larger than the composer.
        return LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              Expanded(child: _thread(copy, currentUserId)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight * _footShare
                      : double.infinity,
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: foot,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _thread(AppLocalizations copy, String currentUserId) =>
      StreamBuilder<List<ClubMessage>>(
        stream: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SingleChildScrollView(
              child: YoErrorState(
                error: snapshot.error,
                compact: widget.compact,
                onRetry: () => setState(_listen),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(
              child: Semantics(
                label: copy.serverChat,
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final messages = snapshot.data ?? const <ClubMessage>[];
          if (messages.isEmpty) {
            return SingleChildScrollView(
              child: YoEmptyState(
                icon: _announcement
                    ? Icons.campaign_outlined
                    : Icons.forum_outlined,
                title: copy.serverNoMessagesTitle,
                subtitle: copy.serverNoMessagesBody(widget.channel.name),
                compact: widget.compact,
              ),
            );
          }
          return ListView.builder(
            key: const ValueKey('server-message-list'),
            reverse: true,
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 12 : 16,
              12,
              widget.compact ? 12 : 16,
              16,
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) => _MessageTile(
              message: messages[index],
              isMine: messages[index].senderId == currentUserId,
              type: widget.server,
              isModerator: widget.moderatorIds.contains(
                messages[index].senderId,
              ),
            ),
          );
        },
      );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.isMine,
    required this.type,
    this.isModerator = false,
  });
  final ClubMessage message;
  final bool isMine;
  final Server type;
  final bool isModerator;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      type.type,
    ).resolve(Theme.of(context).brightness);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(message.sentAt.toLocal()));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            radius: 18,
            userId: message.senderId,
            displayName: message.senderName,
            backgroundColor: colors.iconSurface,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
              decoration: BoxDecoration(
                color: isMine ? colors.selectedWash : palette.surface,
                borderRadius: AppRadius.md,
                border: Border.all(
                  color: isMine ? colors.iconBorder : palette.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        message.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        time,
                        style: AppTypography.labelSmall.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                      if (isModerator)
                        Container(
                          key: ValueKey(
                            'server-moderator-badge-${message.id}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.selectedWash,
                            borderRadius: AppRadius.pill,
                            border: Border.all(color: colors.iconBorder),
                          ),
                          child: Text(
                            copy.serverModerator,
                            style: AppTypography.labelSmall.copyWith(
                              color: colors.selectedForeground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.isDeleted
                        ? copy.serverMessageDeleted
                        : message.content,
                    style: AppTypography.bodyMedium.copyWith(
                      color: message.isDeleted
                          ? palette.textTertiary
                          : palette.textPrimary,
                      fontStyle: message.isDeleted
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.hint,
    required this.sendLabel,
    required this.onSend,
    required this.compact,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String hint;
  final String sendLabel;
  final VoidCallback onSend;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 8 : 12, 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.appPalette.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: YoTextField(
            key: const ValueKey('server-composer'),
            controller: controller,
            focusNode: focusNode,
            hint: hint,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: sending
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : IconButton.filled(
                  key: const ValueKey('server-send'),
                  onPressed: onSend,
                  tooltip: sendLabel,
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
        ),
      ],
    ),
  );
}
