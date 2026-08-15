import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/messages/data/models/global_message.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_message_sheet.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The Global tab of Home's Conversations module: the live community
/// channel, embedded.
///
/// This is a real shared conversation, not a merged view of the signed-in
/// user's own chats — see [GlobalChatService] for the canonical path and
/// the guarantees firestore.rules enforces on it.
///
/// It stays a MODULE: a bounded feed plus a one-line composer, sized to
/// sit inside Home's card. It never grows to fill the page and it never
/// pushes a nested route from inside the card.
class GlobalChatPanel extends StatefulWidget {
  const GlobalChatPanel({
    required this.currentUserId,
    this.chatService,
    this.reportService,
    this.isStaff = false,
    super.key,
  });

  final String currentUserId;
  final GlobalChatService? chatService;
  final ReportService? reportService;

  /// Whether the signed-in account holds a platform staff role. Only
  /// changes which menu items are OFFERED — firestore.rules is what
  /// actually authorizes a moderator deletion.
  final bool isStaff;

  /// Roughly six rows at desktop density: enough to read the room,
  /// short enough that Home stays Home.
  static const double feedHeight = 244;

  @override
  State<GlobalChatPanel> createState() => _GlobalChatPanelState();
}

class _GlobalChatPanelState extends State<GlobalChatPanel> {
  GlobalChatService? _chat;
  ReportService? _reports;

  Stream<GlobalChatFeed>? _feed;
  Stream<Set<String>>? _blocked;

  final TextEditingController _composer = TextEditingController();
  int _limit = GlobalChatService.pageSize;
  bool _sending = false;
  String? _sendError;

  /// Set when a send is refused by one of the two server-side rate
  /// limits, so the composer can name the limit and when it lifts
  /// instead of leaving the person poking a button that does nothing.
  GlobalSendAllowance? _cooldown;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    // Each dependency is resolved on its own: a reporting service that
    // cannot be constructed must not take the whole channel down with
    // it, it should only cost the Report action.
    try {
      _chat = widget.chatService ?? GlobalChatService();
      _feed = _chat!.watchMessages(limit: _limit);
      _blocked = _chat!.watchBlockedUserIds();
    } catch (_) {
      // No session (or a preview harness): the panel shows its signed-out
      // state rather than throwing inside the shell.
      _chat = null;
      _feed = null;
      _blocked = null;
    }
    try {
      _reports = widget.reportService ?? ReportService();
    } catch (_) {
      _reports = null;
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  /// Incremental history: widen the single ordered query rather than
  /// stitching cursors together, so a page boundary cannot duplicate or
  /// reorder anything.
  void _loadEarlier() {
    final chat = _chat;
    if (chat == null) return;
    setState(() {
      _limit += GlobalChatService.pageSize;
      _feed = chat.watchMessages(limit: _limit);
    });
  }

  Future<void> _send() async {
    final chat = _chat;
    final text = _composer.text.trim();
    if (chat == null || text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
      _cooldown = null;
    });
    try {
      // Ask first so a refusal is explained precisely. Rules remain the
      // enforcement — this only decides the wording.
      final allowance = await chat.sendAllowance();
      if (!allowance.canSend) {
        if (mounted) setState(() => _cooldown = allowance);
        return;
      }
      await chat.sendMessage(text);
      _composer.clear();
    } catch (error) {
      if (!mounted) return;
      // A rules refusal arrives as permission-denied whatever the cause,
      // so re-read the state to find out which limit was hit.
      final allowance = await chat.sendAllowance().catchError(
        (_) => const GlobalSendAllowance.allowed(),
      );
      if (!mounted) return;
      setState(() {
        if (!allowance.canSend) {
          _cooldown = allowance;
        } else {
          _sendError = intentionalOrFriendly(error);
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _cooldownMessage(GlobalSendAllowance allowance) {
    final seconds = allowance.retryAfter.inSeconds.clamp(1, 3600);
    if (allowance.reason == GlobalSendBlock.hourlyLimit) {
      final minutes = (allowance.retryAfter.inMinutes + 1).clamp(1, 60);
      return 'You have reached the hourly limit of '
          '${GlobalChatService.fixedWindowLimit} community messages. '
          'You can post again in about $minutes '
          '${minutes == 1 ? 'minute' : 'minutes'}.';
    }
    return 'Global Chat allows one message every '
        '${GlobalChatService.sendCooldown.inSeconds} seconds — '
        '$seconds to go.';
  }

  Future<void> _delete(GlobalMessage message) async {
    try {
      await _chat?.deleteMessage(message.id);
    } catch (error) {
      if (!mounted) return;
      _toast(intentionalOrFriendly(error));
    }
  }

  Future<void> _report(GlobalMessage message) async {
    final reports = _reports;
    if (reports == null) return;

    // Check the limit BEFORE asking for a reason: making someone fill in
    // a form and then telling them it was refused is worse than telling
    // them up front.
    final allowance = await reports.allowance().catchError(
      (_) => const ReportAllowance.allowed(),
    );
    if (!mounted) return;
    if (!allowance.canReport) {
      _toast(
        allowance.atDailyLimit
            ? 'You have filed the maximum of '
                  '${ReportService.dailyLimit} reports for now. '
                  'Existing reports are still being reviewed.'
            : 'One report at a time — try again in '
                  '${allowance.retryAfter.inSeconds.clamp(1, 60)}s.',
      );
      return;
    }

    final submission = await showReportMessageSheet(
      context,
      senderName: message.senderName,
    );
    // Cancelled: nothing is filed, nothing is said.
    if (submission == null || !mounted) return;

    try {
      await reports.report(
        targetType: ReportTargetType.globalMessage,
        targetId: message.id,
        reportedUserId: message.senderId,
        reason: submission.reason,
        note: submission.note,
        contextPath:
            'globalChat/${GlobalChatService.channelId}/messages/${message.id}',
      );
      if (!mounted) return;
      _toast('Reported. Thanks — our team reviews these.');
    } on ReportAlreadyFiledException {
      if (!mounted) return;
      _toast('You have already reported this message.');
    } catch (error) {
      if (!mounted) return;
      _toast(intentionalOrFriendly(error));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: _blocked,
      builder: (context, blockedSnapshot) {
        // Global Chat is PUBLIC: Firestore returns every message in the
        // channel to every active account, including ones from people
        // this reader has blocked. Hiding them is a local UI filter, not
        // a confidentiality boundary — see ADR-037.
        //
        // Because it is local, the block list has to be in hand BEFORE
        // anything renders, or a blocked sender's message would appear
        // for the frame between the two streams arriving. Until the list
        // resolves the panel shows its loading state.
        final blockedReady =
            _blocked == null || blockedSnapshot.connectionState != ConnectionState.waiting;
        final blocked = blockedSnapshot.data ?? const <String>{};

        return StreamBuilder<GlobalChatFeed>(
          stream: _feed,
          builder: (context, snapshot) {
            final feed = blockedReady ? snapshot.data : null;
            final messages = (feed?.messages ?? const <GlobalMessage>[])
                .where((message) => !blocked.contains(message.senderId))
                .toList(growable: false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feed?.isFromCache ?? false) const _OfflineStrip(),
                SizedBox(
                  height: GlobalChatPanel.feedHeight,
                  child: _body(snapshot, feed, messages),
                ),
                const SizedBox(height: 10),
                _Composer(
                  controller: _composer,
                  sending: _sending,
                  enabled: _chat != null,
                  error: _sendError,
                  cooldown: _cooldown == null
                      ? null
                      : _cooldownMessage(_cooldown!),
                  onSend: _send,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _body(
    AsyncSnapshot<GlobalChatFeed> snapshot,
    GlobalChatFeed? feed,
    List<GlobalMessage> messages,
  ) {
    if (_chat == null) {
      return const _PanelState(
        icon: Icons.lock_outline_rounded,
        text: 'Sign in to join the YO Voice community chat.',
      );
    }
    if (snapshot.hasError) {
      return _PanelState(
        icon: Icons.error_outline_rounded,
        text: intentionalOrFriendly(snapshot.error!),
      );
    }
    if (feed == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (messages.isEmpty) {
      return const _PanelState(
        icon: Icons.forum_outlined,
        text: 'No one has said anything yet. Start the conversation.',
      );
    }

    // Newest-first from Firestore, rendered bottom-up so the latest
    // message sits above the composer, where a reader expects it.
    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.zero,
      itemCount: messages.length + (feed.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _LoadEarlierButton(onTap: _loadEarlier);
        }
        final message = messages[index];
        return _MessageRow(
          key: ValueKey(message.id),
          message: message,
          isMine: message.senderId == widget.currentUserId,
          canModerate: widget.isStaff,
          onDelete: () => _delete(message),
          onReport: () => _report(message),
        );
      },
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.warning.withValues(alpha: .10),
        border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 13, color: AppColors.warning),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Offline — showing the last messages this device received.',
              style: TextStyle(color: Color(0xFFCFC6DC), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.isMine,
    required this.canModerate,
    required this.onDelete,
    required this.onReport,
    super.key,
  });

  final GlobalMessage message;
  final bool isMine;
  final bool canModerate;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _hover = false;

  /// The menu is hover-revealed, but opening it puts the pointer on the
  /// popup overlay, which fires this row's MouseRegion.onExit. Without
  /// this flag the button would be unmounted while its own menu is open
  /// — and PopupMenuButton silently drops onSelected when its State is
  /// gone, so Report and Delete would do nothing at all.
  bool _menuOpen = false;

  static String _stamp(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${at.day}/${at.month}';
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    if (message.isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            const Icon(
              Icons.block_rounded,
              size: 13,
              color: Color(0xFF564C63),
            ),
            const SizedBox(width: 8),
            Text(
              message.removedByModerator
                  ? 'Message removed by a moderator'
                  : 'Message deleted',
              style: const TextStyle(
                color: Color(0xFF7E7895),
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _hover ? Colors.white.withValues(alpha: .03) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => showProfilePreview(
                context,
                userId: message.senderId,
                displayName: message.senderName,
                photoUrl: message.senderPhotoUrl,
              ),
              child: UserAvatar(
                radius: 14,
                photoUrl: message.senderPhotoUrl,
                displayName: message.senderName,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Identity comes from the public badge projection,
                      // resolved by uid — the message's own staff flag is
                      // client-era history and is not trusted for
                      // rendering identity. Creator remains an account
                      // type, not a role, so its chip stays.
                      const SizedBox(width: 6),
                      UserIdentityBadges(uid: message.senderId),
                      if (message.senderIsCreator) ...[
                        const SizedBox(width: 6),
                        const _SenderBadge(
                          label: 'Creator',
                          color: Color(0xFFE879F9),
                        ),
                      ],
                      const SizedBox(width: 7),
                      Text(
                        _stamp(message.sentAt),
                        style: const TextStyle(
                          color: Color(0xFF7E7895),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.content,
                    style: const TextStyle(
                      color: Color(0xFFCFC6DC),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 26,
              child: _hover || _menuOpen
                  ? _MessageMenu(
                      canDelete: widget.isMine || widget.canModerate,
                      canReport: !widget.isMine,
                      onOpened: () => setState(() => _menuOpen = true),
                      onClosed: () {
                        if (mounted) setState(() => _menuOpen = false);
                      },
                      onDelete: widget.onDelete,
                      onReport: widget.onReport,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageMenu extends StatelessWidget {
  const _MessageMenu({
    required this.canDelete,
    required this.canReport,
    required this.onOpened,
    required this.onClosed,
    required this.onDelete,
    required this.onReport,
  });

  final bool canDelete;
  final bool canReport;

  /// Let the row know its menu is open, so the row keeps this widget
  /// mounted even once the pointer moves onto the popup.
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    if (!canDelete && !canReport) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Message options',
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: const Color(0xFF171024),
      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF9A90AC)),
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (value) {
        onClosed();
        if (value == 'delete') onDelete();
        if (value == 'report') onReport();
      },
      itemBuilder: (context) => [
        if (canReport)
          const PopupMenuItem<String>(
            value: 'report',
            height: 38,
            child: Text(
              'Report message',
              style: TextStyle(color: Color(0xFFCFC6DC), fontSize: 12.5),
            ),
          ),
        if (canDelete)
          const PopupMenuItem<String>(
            value: 'delete',
            height: 38,
            child: Text(
              'Delete message',
              style: TextStyle(color: Color(0xFFFF7A93), fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

class _SenderBadge extends StatelessWidget {
  const _SenderBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .40)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _LoadEarlierButton extends StatelessWidget {
  const _LoadEarlierButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Load earlier messages',
          style: TextStyle(
            color: Color(0xFFD3A5FF),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.error,
    required this.cooldown,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final String? error;

  /// A deliberate, explained rate-limit state — distinct from [error],
  /// which means something actually went wrong.
  final String? cooldown;

  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final length = widget.controller.text.characters.length;
    final canSend =
        widget.enabled &&
        !widget.sending &&
        widget.controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                enabled: widget.enabled && !widget.sending,
                maxLength: GlobalChatService.maxMessageLength,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => canSend ? widget.onSend() : null,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'Message the YO Voice community',
                  hintStyle: const TextStyle(
                    color: Color(0xFF7E7895),
                    fontSize: 12.5,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .03),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Color(0xFF2E2140)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Color(0xFF2E2140)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: AppColors.primary.withValues(alpha: .60),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(
              enabled: canSend,
              sending: widget.sending,
              onTap: widget.onSend,
            ),
          ],
        ),
        if (widget.cooldown != null)
          Padding(
            padding: const EdgeInsets.only(top: 7, left: 2),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_bottom_rounded,
                  size: 13,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.cooldown!,
                    style: const TextStyle(
                      color: Color(0xFFCFC6DC),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 6),
            child: Text(
              widget.error!,
              style: const TextStyle(color: Color(0xFFFF7A93), fontSize: 11.5),
            ),
          )
        // The limit is only worth mentioning as it approaches.
        else if (length > GlobalChatService.maxMessageLength - 80)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$length / ${GlobalChatService.maxMessageLength}',
                style: const TextStyle(
                  color: Color(0xFF7E7895),
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: .04),
          border: enabled
              ? null
              : Border.all(color: const Color(0xFF2E2140)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Center(
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      size: 17,
                      color: enabled ? Colors.white : const Color(0xFF564C63),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelState extends StatelessWidget {
  const _PanelState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: const Color(0xFF564C63)),
            const SizedBox(height: 9),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
