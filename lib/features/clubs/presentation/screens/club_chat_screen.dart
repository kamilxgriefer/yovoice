import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

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
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final ClubChatService _service =
      widget.chatService ?? ClubChatService(firestore: _firestore, auth: _auth);
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _emojiPickerOpen = false;

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

  /// Swaps the system keyboard for the emoji picker and back, keeping focus
  /// on the composer so the caret survives the swap.
  void _toggleEmojiPicker() {
    final opening = !_emojiPickerOpen;
    setState(() => _emojiPickerOpen = opening);
    if (opening) {
      if (!_focusNode.hasFocus) _focusNode.requestFocus();
      yoHideSystemKeyboard();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    yoInsertEmojiAtCaret(_controller, emoji);
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final copy = AppLocalizations.of(context);
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
        copy.isPolish
            ? 'Nie udało się wysłać wiadomości. Spróbuj ponownie.'
            : intentionalOrFriendly(
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
      if (refusal != null) _showNotice(_localizedRemovalRefusal(refusal));
      return;
    }
    await _delete(message, authority);
  }

  /// [authority] is the same value that decided whether to OFFER this
  /// action, so the dialog can only ever be shown for a removal the rules
  /// permit — and can name what will actually happen.
  Future<void> _delete(ClubMessage message, ClubChatAuthority authority) async {
    final moderating = authority.isModeratingOthers(message);
    final copy = AppLocalizations.of(context);
    final name = _safeSenderName(
      message,
      fallback: copy.text('this member', 'ten członek'),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final dialogCopy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
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
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          title: Text(
            moderating
                ? dialogCopy.text(
                    'Remove this message?',
                    'Usunąć tę wiadomość?',
                  )
                : dialogCopy.text('Delete message?', 'Usunąć wiadomość?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: ConstrainedBox(
            constraints:
                ResponsiveContentFrame.adaptiveModalConstraints(
                  dialogContext,
                  maxWidth: 460,
                ) ??
                const BoxConstraints(),
            child: Text(
              moderating
                  ? dialogCopy.text(
                      'This removes $name’s message for everyone in '
                          '#${widget.channel.name}, and records your account '
                          'against the removal.',
                      'Wiadomość użytkownika $name zniknie u wszystkich na kanale '
                          '#${widget.channel.name}, a usunięcie zostanie przypisane do Twojego konta.',
                    )
                  : dialogCopy.text(
                      'This message will be replaced with “Message deleted”.',
                      'Wiadomość zostanie zastąpiona tekstem „Wiadomość usunięta”.',
                    ),
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              // The theme's primary is 3.16:1 on this surface — below AA,
              // and it was the SAFE choice sitting next to a destructive
              // one. Stated explicitly rather than inherited.
              style: TextButton.styleFrom(foregroundColor: palette.textPrimary),
              child: Text(dialogCopy.text('Cancel', 'Anuluj')),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              // An icon so the destructive action is not distinguished by
              // colour weight alone.
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                moderating
                    ? dialogCopy.text('Remove', 'Usuń')
                    : dialogCopy.text('Delete', 'Usuń'),
              ),
            ),
          ],
        );
      },
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
          moderating
              ? copy.text('Message removed.', 'Wiadomość usunięta.')
              : copy.text('Message deleted.', 'Wiadomość usunięta.'),
          assertive: false,
        );
      }
    } catch (error) {
      _showNotice(
        copy.isPolish
            ? 'Nie udało się usunąć wiadomości. Spróbuj ponownie.'
            : intentionalOrFriendly(
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
      assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
    );
  }

  String _localizedRemovalRefusal(String refusal) {
    final copy = AppLocalizations.of(context);
    if (!copy.isPolish) return refusal;
    return switch (refusal) {
      'You must be signed in to use club chat.' =>
        'Musisz się zalogować, aby korzystać z czatu klubu.',
      'This message has already been removed.' =>
        'Ta wiadomość została już usunięta.',
      'Your role cannot remove this message.' =>
        'Twoja rola nie pozwala usunąć tej wiadomości.',
      'Verify your email address to moderate club chat.' =>
        'Zweryfikuj adres e-mail, aby moderować czat klubu.',
      'You cannot moderate club chat while your account is muted. You can still delete your own messages.' =>
        'Nie możesz moderować czatu, gdy Twoje konto jest wyciszone. Nadal możesz usuwać własne wiadomości.',
      'We could not confirm who owns this club. Please try again in a moment.' =>
        'Nie udało się potwierdzić właściciela klubu. Spróbuj ponownie za chwilę.',
      'The club owner’s messages can only be removed by YO Voice staff. Report it instead.' =>
        'Wiadomości właściciela klubu może usuwać tylko zespół YO Voice. Zamiast tego zgłoś wiadomość.',
      _ => 'Nie możesz teraz usunąć tej wiadomości.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('club-chat-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        titleSpacing: 0,
        shape: Border(bottom: BorderSide(color: palette.border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_isAnnouncements ? '📣' : '#'} ${widget.channel.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.clubName,
              style: TextStyle(color: palette.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          child: StreamBuilder<ClubChatAuthority>(
            stream: _authorityStream,
            initialData: _initialAuthority,
            builder: (context, snapshot) {
              final authority = snapshot.data ?? _initialAuthority;
              return Column(
                children: [
                  Expanded(child: _buildMessages(authority)),
                  if (!authority.canSendToChannel(
                    announcement: _isAnnouncements,
                  ))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      child: Text(
                        _isAnnouncements
                            ? copy.text(
                                'Announcements can be posted by club moderators.',
                                'Ogłoszenia mogą publikować moderatorzy klubu.',
                              )
                            : copy.text(
                                'This channel is read-only for your current role.',
                                'Dla Twojej roli ten kanał jest tylko do odczytu.',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    _Composer(
                      controller: _controller,
                      focusNode: _focusNode,
                      sending: _sending,
                      emojiPickerOpen: _emojiPickerOpen,
                      hint: _isAnnouncements
                          ? copy.text(
                              'Write an announcement…',
                              'Napisz ogłoszenie…',
                            )
                          : copy.text(
                              'Message #${widget.channel.name}',
                              'Wiadomość na #${widget.channel.name}',
                            ),
                      onSend: _send,
                      onToggleEmoji: _toggleEmojiPicker,
                    ),
                  // Below the composer, never over it: the send button is laid
                  // out first, so no picker height can cover it.
                  if (_emojiPickerOpen &&
                      authority.canSendToChannel(
                        announcement: _isAnnouncements,
                      ))
                    YoEmojiPicker(
                      onSelected: _insertEmoji,
                      onBackspace: () {
                        yoDeleteBackAtCaret(_controller);
                        if (!_focusNode.hasFocus) _focusNode.requestFocus();
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(ClubChatAuthority authority) {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<ClubMessage>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        // `hasData` guards the spinner as well as the connection state:
        // a reconnect re-enters `waiting` while the already-delivered
        // conversation is still on screen, and blanking it would be a
        // regression, not a loading state.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        if (snapshot.hasError) {
          return _ChatState(
            icon: Icons.cloud_off_rounded,
            title: copy.text(
              'Could not load messages',
              'Nie udało się wczytać wiadomości',
            ),
            subtitle: copy.isPolish
                ? 'Sprawdź połączenie i spróbuj ponownie.'
                : friendlyErrorMessage(
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
                ? copy.text('No announcements yet', 'Brak ogłoszeń')
                : copy.text(
                    'Start the club conversation',
                    'Rozpocznij rozmowę w klubie',
                  ),
            subtitle: _isAnnouncements
                ? copy.text(
                    'Important club updates will appear here.',
                    'Ważne aktualizacje klubu pojawią się tutaj.',
                  )
                : copy.text(
                    'Be the first member to write in #${widget.channel.name}.',
                    'Napisz pierwszą wiadomość na #${widget.channel.name}.',
                  ),
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
String _safeSenderName(ClubMessage message, {String fallback = 'this member'}) {
  final collapsed = message.senderName.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return fallback;
  // The model substitutes this placeholder for an empty name; saying
  // "YO Voice user's message" reads like an official account.
  if (collapsed == 'YO Voice user') return fallback;
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AccessibleContextAction(
        onOpen: onRemove,
        // Two messages from one person produced byte-identical labels
        // before, so the button node could not be told apart from its
        // neighbour. The time and an opening fragment make each one
        // identifiable without a second stop on the content node.
        semanticLabel: _actionLabel(copy),
        borderRadius: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              radius: 19,
              userId: message.senderId,
              displayName: message.senderName,
              backgroundColor: colors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                decoration: BoxDecoration(
                  color: isMine ? colors.primaryContainer : palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMine
                        ? colors.primary.withValues(alpha: .55)
                        : palette.border,
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
                              ? colors.onPrimaryContainer
                              : palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      badges: UserIdentityBadges(uid: message.senderId),
                      time: Text(
                        _formatTime(context, message.sentAt),
                        style: TextStyle(
                          // 0xFF817889 measured 4.38:1 here, under AA.
                          color: palette.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _bodyText(copy),
                      style: TextStyle(
                        color: message.isDeleted
                            ? palette.textTertiary
                            : palette.textPrimary,
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
  String _bodyText(AppLocalizations copy) {
    if (message.wasRemovedByStaff) {
      return copy.text('Removed by YO Voice', 'Usunięto przez YO Voice');
    }
    if (message.wasRemovedByModerator) {
      return copy.text(
        'Removed by a club moderator',
        'Usunięto przez moderatora klubu',
      );
    }
    if (message.isDeleted) {
      return copy.text('Message deleted', 'Wiadomość usunięta');
    }
    return message.content;
  }

  String _actionLabel(AppLocalizations copy) {
    final name = _safeSenderName(
      message,
      fallback: copy.text('this member', 'ten członek'),
    );
    final opening = message.content.trim();
    final snippet = opening.length <= 40
        ? opening
        : '${opening.substring(0, 40)}…';
    final where = snippet.isEmpty ? '' : ': $snippet';
    return isModeration
        ? copy.text(
            'Remove $name’s message$where',
            'Usuń wiadomość użytkownika $name$where',
          )
        : copy.text('Delete your message$where', 'Usuń swoją wiadomość$where');
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
    required this.emojiPickerOpen,
    required this.hint,
    required this.onSend,
    required this.onToggleEmoji,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool emojiPickerOpen;
  final String hint;
  final VoidCallback onSend;
  final VoidCallback onToggleEmoji;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
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
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                counterText: '',
                hintText: hint,
                hintStyle: TextStyle(color: palette.textTertiary),
                filled: true,
                fillColor: palette.surfaceSunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              onSubmitted: (_) => onSend(),
              // Reaching for the keyboard is the natural way to put the
              // picker away again.
              onTap: emojiPickerOpen ? onToggleEmoji : null,
            ),
          ),
          const SizedBox(width: 2),
          YoEmojiComposerButton(
            open: emojiPickerOpen,
            onPressed: onToggleEmoji,
            color: palette.textTertiary,
          ),
          const SizedBox(width: 2),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            tooltip: AppLocalizations.of(
              context,
            ).text('Send message', 'Wyślij wiadomość'),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: palette.surfaceMuted,
              minimumSize: const Size(48, 48),
            ),
            icon: sending
                ? SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : Icon(Icons.arrow_upward_rounded, color: colors.onPrimary),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.primary, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
