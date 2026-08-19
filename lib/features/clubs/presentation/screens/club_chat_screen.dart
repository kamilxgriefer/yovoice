import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/helpers/error_messages.dart';

import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ClubChatScreen extends StatefulWidget {
  const ClubChatScreen({
    required this.clubId,
    required this.clubName,
    required this.channel,
    this.firestore,
    this.auth,
    this.chatService,
    super.key,
  });

  final String clubId;
  final String clubName;
  final ClubChannel channel;

  /// Test seams, following the pattern already used by
  /// `ClubInviteResponseScreen` and `CreateClubScreen`. Production always
  /// passes nothing and gets the real instances.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final ClubChatService? chatService;

  @override
  State<ClubChatScreen> createState() => _ClubChatScreenState();
}

class _ClubChatScreenState extends State<ClubChatScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171120);
  static const _border = Color(0xFF33263F);
  static const _muted = Color(0xFF9F95A6);
  static const _purple = Color(0xFF9D20FF);

  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final ClubChatService _service =
      widget.chatService ??
      ClubChatService(firestore: _firestore, auth: _auth);
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  /// Both streams are resolved ONCE, not per build. `build()` runs again
  /// on every keystroke-driven `_sending` flip, and a freshly constructed
  /// stream makes `StreamBuilder` resubscribe — which drops the message
  /// list back to `ConnectionState.waiting` and flashes the spinner over
  /// a conversation that is still on screen.
  late final Stream<List<ClubMessage>> _messageStream = _service.watchMessages(
    clubId: widget.clubId,
    channelId: widget.channel.id,
  );
  late final Stream<ClubChatAuthority> _authorityStream = _service
      .watchAuthority(widget.clubId);

  /// What the viewer may do before either authority document has
  /// arrived: retract their own messages, and nothing else.
  late final ClubChatAuthority _initialAuthority = ClubChatAuthority(
    viewerId: _currentUserId,
  );

  String get _currentUserId => _auth.currentUser?.uid ?? '';
  bool get _isAnnouncements =>
      widget.channel.type == ClubChannelType.announcement;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        clubId: widget.clubId,
        channelId: widget.channel.id,
        text: text,
      );
      _controller.clear();
      _focusNode.requestFocus();
    } catch (error) {
      _showNotice(
        intentionalOrFriendly(
          error,
          fallback: 'Could not send your message. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The one entry point for the tile's context action.
  ///
  /// Either the removal is permitted — in which case it is confirmed and
  /// performed — or the viewer holds moderator power and is told, in
  /// words, why this particular message is out of their reach. A
  /// confirmation dialog is therefore only ever raised for a write the
  /// rules accept, and a refusal is never silence.
  Future<void> _handleMessageAction(
    ClubMessage message,
    ClubChatAuthority authority,
  ) async {
    if (!authority.canRemove(message)) {
      final refusal = authority.removalRefusal(message);
      if (refusal != null) _showNotice(refusal);
      return;
    }
    await _delete(message, authority);
  }

  /// [authority] is the same value that decided whether to OFFER this
  /// action, so the dialog can only ever be shown for a removal the rules
  /// permit — and can name what will actually happen.
  Future<void> _delete(ClubMessage message, ClubChatAuthority authority) async {
    final moderating = authority.isModeratingOthers(message);
    final name = _safeSenderName(message);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        // Long copy at a large text scale is silently CLIPPED by
        // AlertDialog's Flexible wrapper — no overflow stripe, no
        // exception, just a vanished sentence. The vanished sentence here
        // is the one naming what is about to happen and that it is
        // recorded, so this is not optional polish.
        scrollable: true,
        // Without a cap the card tracks the window and the body becomes a
        // single 700-1200 px line, with a long display name driving the
        // width. docs/UI.md's modal measure, applied through the shared
        // helper rather than a local number.
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text(
          moderating ? 'Remove this message?' : 'Delete message?',
          style: const TextStyle(color: Colors.white),
        ),
        content: ConstrainedBox(
          constraints:
              ResponsiveContentFrame.adaptiveModalConstraints(
                context,
                maxWidth: 460,
              ) ??
              const BoxConstraints(),
          child: Text(
            moderating
                ? 'This removes $name’s message for everyone in '
                      '#${widget.channel.name}, and records your account '
                      'against the removal.'
                : 'This message will be replaced with “Message '
                      'deleted”.',
            style: const TextStyle(color: _muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            // The theme's primary is 3.16:1 on this surface — below AA,
            // and it was the SAFE choice sitting next to a destructive
            // one. Stated explicitly rather than inherited.
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEAE4ED),
            ),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF668B),
            ),
            // An icon so the destructive action is not distinguished by
            // colour weight alone.
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(moderating ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteMessage(
        clubId: widget.clubId,
        channelId: widget.channel.id,
        message: message,
      );
      // The removed tile loses its action, so AccessibleContextAction
      // stops building a FocusableActionDetector and Flutter disposes the
      // node WHILE IT HOLDS FOCUS — traversal then restarts from the top
      // of the screen, once per removal. Park focus somewhere real, and
      // say what happened: the only other feedback is a text swap.
      if (mounted) {
        _focusNode.requestFocus();
        _announce(
          moderating ? 'Message removed.' : 'Message deleted.',
          assertive: false,
        );
      }
    } catch (error) {
      _showNotice(
        intentionalOrFriendly(
          error,
          fallback: 'Could not remove this message. Please try again.',
        ),
      );
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    // A SnackBar announces POLITELY, and ADR-058 records why that is not
    // enough for a failure here: the polite channel is one shared slot,
    // and the message list is changing in the same frame. The notice a
    // moderator most needs to hear is the one most likely to be dropped.
    _announce(message);
  }

  void _announce(String message, {bool assertive = true}) {
    final text = message.trim();
    if (!mounted || text.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
      assertiveness: assertive
          ? Assertiveness.assertive
          : Assertiveness.polite,
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: _border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_isAnnouncements ? '📣' : '#'} ${widget.channel.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.clubName,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<ClubChatAuthority>(
                  stream: _authorityStream,
                  initialData: _initialAuthority,
                  builder: (context, authoritySnapshot) {
                    final authority =
                        authoritySnapshot.data ?? _initialAuthority;
                    return _buildMessages(authority);
                  },
                ),
              ),
              _Composer(
                controller: _controller,
                focusNode: _focusNode,
                sending: _sending,
                hint: _isAnnouncements
                    ? 'Write an announcement…'
                    : 'Message #${widget.channel.name}',
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(ClubChatAuthority authority) {
    return StreamBuilder<List<ClubMessage>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        // `hasData` guards the spinner as well as the connection state:
        // a reconnect re-enters `waiting` while the already-delivered
        // conversation is still on screen, and blanking it would be a
        // regression, not a loading state.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        if (snapshot.hasError) {
          return _ChatState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load messages',
            subtitle: friendlyErrorMessage(
              snapshot.error ?? 'unknown',
              fallback: 'Could not load this chat.',
            ),
          );
        }
        final messages = snapshot.data ?? const <ClubMessage>[];
        if (messages.isEmpty) {
          return _ChatState(
            icon: _isAnnouncements
                ? Icons.campaign_rounded
                : Icons.forum_rounded,
            title: _isAnnouncements
                ? 'No announcements yet'
                : 'Start the club conversation',
            subtitle: _isAnnouncements
                ? 'Important club updates will appear here.'
                : 'Be the first member to write in #${widget.channel.name}.',
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            // The gate and the write consult one object, so an offered
            // action is always an action the rules accept. A moderator
            // blocked on THIS message still gets the action, and hears
            // why — silence would read as a broken gesture.
            final offered =
                authority.canRemove(message) ||
                authority.shouldExplainRefusal(message);
            return _ClubMessageTile(
              message: message,
              isMine: message.senderId == _currentUserId,
              isModeration: authority.isModeratingOthers(message),
              onRemove: offered
                  ? () => _handleMessageAction(message, authority)
                  : null,
            );
          },
        );
      },
    );
  }
}

/// `senderName` is client-written and the rules cap neither its length nor
/// its contents. Visually it is clipped to one ellipsised line, but a
/// semantic label and a dialog sentence are unbounded — so a display name
/// could otherwise script the words a blind moderator hears immediately
/// before a destructive action ("… Cancel button. Wrong message, press
/// Cancel."). Collapse and clamp before interpolating.
String _safeSenderName(ClubMessage message) {
  final collapsed = message.senderName.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return 'this member';
  // The model substitutes this placeholder for an empty name; saying
  // "YO Voice user's message" reads like an official account.
  if (collapsed == 'YO Voice user') return 'this member';
  return collapsed.length <= 40 ? collapsed : '${collapsed.substring(0, 40)}…';
}

class _ClubMessageTile extends StatelessWidget {
  const _ClubMessageTile({
    required this.message,
    required this.isMine,
    required this.isModeration,
    required this.onRemove,
  });

  final ClubMessage message;
  final bool isMine;

  /// Whether [onRemove] would be an act of moderation on somebody else's
  /// message rather than the author retracting their own. Only affects
  /// how the action is announced.
  final bool isModeration;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = message.senderPhotoUrl?.isNotEmpty ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AccessibleContextAction(
        onOpen: onRemove,
        // Two messages from one person produced byte-identical labels
        // before, so the button node could not be told apart from its
        // neighbour. The time and an opening fragment make each one
        // identifiable without a second stop on the content node.
        semanticLabel: _actionLabel(),
        borderRadius: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFF6C2D9A),
              backgroundImage: hasPhoto
                  ? NetworkImage(message.senderPhotoUrl!)
                  : null,
              child: hasPhoto
                  ? null
                  // Decorative: the sender's name is right beside it, so
                  // the initial only adds a stray letter before every
                  // message a screen reader reads.
                  : ExcludeSemantics(
                      child: Text(
                        message.senderName.isEmpty
                            ? '?'
                            : message.senderName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                decoration: BoxDecoration(
                  color: isMine
                      ? const Color(0xFF261436)
                      : const Color(0xFF171120),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMine
                        ? const Color(0xFF5B2A7B)
                        : const Color(0xFF33263F),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MessageHeader(
                      name: Text(
                        message.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMine
                              ? const Color(0xFFD8A9FF)
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      badges: UserIdentityBadges(uid: message.senderId),
                      time: Text(
                        _formatTime(context, message.sentAt),
                        style: const TextStyle(
                          // 0xFF817889 measured 4.38:1 here, under AA.
                          color: Color(0xFF9F95A6),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _bodyText(),
                      style: TextStyle(
                        color: message.isDeleted
                            ? const Color(0xFF8E8595)
                            : const Color(0xFFEAE4ED),
                        fontSize: 14,
                        height: 1.35,
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
      ),
    );
  }

  /// Three states, because a YO Voice staff redaction is not a club
  /// moderator's act. Telling members a moderator removed the owner's
  /// message would describe something the app tells moderators is
  /// impossible, and would pin a platform decision on club volunteers.
  String _bodyText() {
    if (message.wasRemovedByStaff) return 'Removed by YO Voice';
    if (message.wasRemovedByModerator) return 'Removed by a club moderator';
    if (message.isDeleted) return 'Message deleted';
    return message.content;
  }

  String _actionLabel() {
    final name = _safeSenderName(message);
    final opening = message.content.trim();
    final snippet = opening.length <= 40
        ? opening
        : '${opening.substring(0, 40)}…';
    final where = snippet.isEmpty ? '' : ': $snippet';
    return isModeration
        ? 'Remove $name’s message$where'
        : 'Delete your message$where';
  }

  static String _formatTime(BuildContext context, DateTime value) {
    // 24-hour was hard-coded; a 12-hour-clock locale heard "13:04".
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()));
  }
}

/// The sender / badges / timestamp line.
///
/// The previous `Flexible(name) … Spacer() … time` split free space
/// evenly between the name and the Spacer, so the name could never use
/// more than half the bubble however empty the rest was, and the badges
/// were laid out unbounded — a MODERATOR or SUPER MODERATOR pill next to
/// a VIP one erased the name entirely and still overflowed the row at
/// DEFAULT text size. That matters here beyond tidiness: a moderator
/// identifies who they are about to act against from this line.
///
/// A [Wrap] fixes both without a magic number. The name is constrained to
/// the real available width, so it ellipsises only when it genuinely runs
/// out; the badges drop to a second run rather than overflowing; and past
/// a large text scale the timestamp takes its own line, the pattern the
/// friends and achievements lists already use.
class _MessageHeader extends StatelessWidget {
  const _MessageHeader({
    required this.name,
    required this.badges,
    required this.time,
  });

  final Widget name;
  final Widget badges;
  final Widget time;

  @override
  Widget build(BuildContext context) {
    final identity = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [name, badges],
    );

    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [identity, const SizedBox(height: 2), time],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: identity),
        const SizedBox(width: 8),
        time,
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF100C17),
        border: Border(top: BorderSide(color: Color(0xFF33263F))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF817889)),
                filled: true,
                fillColor: const Color(0xFF171120),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF33263F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF9D20FF)),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF9D20FF),
              disabledBackgroundColor: const Color(0xFF513060),
              minimumSize: const Size(48, 48),
            ),
            icon: sending
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ChatState extends StatelessWidget {
  const _ChatState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFC17BFF), size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9F95A6), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
