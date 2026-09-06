import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/room_links.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Delivers one invitation to one friend. The production implementation
/// opens (or finds) the direct conversation and sends [text] as an ordinary
/// text message — there is no invite message type and no client-mintable
/// notification, so the link inside the text IS the invitation and the chat
/// bubble renders a room card for it.
typedef RoomInviteSend = Future<void> Function(FriendUser friend, String text);

/// Hands the invitation to the operating system share sheet.
typedef RoomInviteShare = Future<void> Function(String text, String subject);

/// How the panel is being presented; only the corner treatment differs.
enum InviteToRoomPresentation { sheet, dialog }

/// The width from which the invitation opens as a dialog instead of a
/// bottom sheet — the same threshold the availability picker uses.
const double inviteToRoomDialogBreakpoint = 900;

/// Opens the invitation surface for [room]: a bottom sheet under
/// [inviteToRoomDialogBreakpoint], a centred dialog above it.
///
/// Community rooms offer this to every participant; Broadcast rooms only to
/// the host (their Share sheet routes here). Both products share the same
/// panel because the invitation itself — a direct message carrying the
/// canonical `?room=` link — is identical; only the wording differs.
///
/// Nothing here touches Firebase until it has to: the friends stream and the
/// message facade are created lazily so previews and tests can pass their
/// own. An invitation never grants access, so private rooms get an
/// explanation instead of a friend list.
Future<void> showInviteToRoomSheet(
  BuildContext context, {
  required VoiceRoom room,
  Stream<List<FriendUser>>? friendsStream,
  FriendService? friendService,
  MessageService? messageService,
  RoomInviteShare? share,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= inviteToRoomDialogBreakpoint;
  final canInvite = room.visibility == 'public';
  final friends = canInvite
      ? (friendsStream ?? (friendService ?? FriendService()).watchFriends())
      : const Stream<List<FriendUser>>.empty();

  Future<void> send(FriendUser friend, String text) =>
      deliverRoomInvite(messageService ?? MessageService.live, friend, text);

  Widget panel(InviteToRoomPresentation presentation) => InviteToRoomPanel(
    room: room,
    friendsStream: friends,
    send: send,
    share: share ?? _shareThroughSystem,
    presentation: presentation,
  );

  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: canInvite ? 680 : 320,
          ),
          child: panel(InviteToRoomPresentation.dialog),
        ),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 560,
    ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final inset = media.viewInsets.bottom;
      final child = panel(InviteToRoomPresentation.sheet);
      if (!canInvite) {
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: child,
        );
      }
      // A fixed height keeps the list scrollable inside the sheet; the
      // keyboard shrinks it rather than pushing the header off-screen.
      final height = math.min(
        media.size.height * .8,
        media.size.height - inset - media.padding.top - 24,
      );
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(height: math.max(height, 240), child: child),
      );
    },
  );
}

/// The production delivery: conversation first, then the text message.
///
/// Public so the callable contract stays visible at the call site — the
/// deployed `sendDirectMessage` accepts text only, so this is a text DM by
/// design, not by omission.
Future<void> deliverRoomInvite(
  MessageService messages,
  FriendUser friend,
  String text,
) async {
  final conversationId = await messages.openOrCreateConversation(
    otherUserId: friend.id,
    otherDisplayName: friend.displayName,
    otherEmail: friend.email,
    otherPhotoUrl: friend.photoUrl ?? '',
  );
  await messages.sendTextMessage(
    conversationId: conversationId,
    recipientId: friend.id,
    text: text,
  );
}

Future<void> _shareThroughSystem(String text, String subject) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

/// The invitation text friends receive. One template for both products —
/// the room name already says what it is.
String roomInviteText(AppLocalizations copy, VoiceRoom room) {
  return copy.template(
    'Join me in {room} on YO Voice: {link}',
    'Dołącz do mnie w {room} w YO Voice: {link}',
    values: <String, Object>{'room': room.name, 'link': roomShareLink(room.id)},
  );
}

/// The invitation panel: friend list with search, per-friend Send/Sent with
/// busy and error states, plus system share and copy-link rows.
///
/// Presentation-only widget — every side effect arrives through [send] and
/// [share], so it renders identically in the room screens, previews and
/// tests.
class InviteToRoomPanel extends StatefulWidget {
  const InviteToRoomPanel({
    required this.room,
    required this.friendsStream,
    required this.send,
    required this.share,
    this.presentation = InviteToRoomPresentation.sheet,
    super.key,
  });

  final VoiceRoom room;
  final Stream<List<FriendUser>> friendsStream;
  final RoomInviteSend send;
  final RoomInviteShare share;
  final InviteToRoomPresentation presentation;

  @override
  State<InviteToRoomPanel> createState() => _InviteToRoomPanelState();
}

class _InviteToRoomPanelState extends State<InviteToRoomPanel> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _busy = <String>{};
  final Set<String> _sent = <String>{};
  final Map<String, String> _errors = <String, String>{};
  String _query = '';

  bool get _canInvite => widget.room.visibility == 'public';

  @override
  void initState() {
    super.initState();
    _search.addListener(_handleSearch);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    final value = _search.text.trim().toLowerCase();
    if (value == _query) return;
    setState(() => _query = value);
  }

  String _title(AppLocalizations copy) => widget.room.isBroadcast
      ? copy.text('Invite to the podcast', 'Zaproś do podcastu')
      : copy.text('Invite to the room', 'Zaproś do pokoju');

  String _shareSubject(AppLocalizations copy) => copy.template(
    'Join {room} on YO Voice',
    'Dołącz do {room} w YO Voice',
    values: <String, Object>{'room': widget.room.name},
  );

  void _notify(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _copyLink() async {
    final copy = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: roomShareLink(widget.room.id)));
    if (!mounted) return;
    _notify(copy.text('Link copied.', 'Link skopiowany.'));
  }

  Future<void> _shareLink() async {
    final copy = AppLocalizations.of(context);
    try {
      await widget.share(
        roomInviteText(copy, widget.room),
        _shareSubject(copy),
      );
    } catch (_) {
      if (!mounted) return;
      _notify(
        copy.text(
          'Sharing is not available here. Copy the link instead.',
          'Udostępnianie nie jest tu dostępne. Skopiuj link.',
        ),
      );
    }
  }

  Future<void> _send(FriendUser friend) async {
    if (_busy.contains(friend.id) || _sent.contains(friend.id)) return;
    final copy = AppLocalizations.of(context);
    final text = roomInviteText(copy, widget.room);
    setState(() {
      _busy.add(friend.id);
      _errors.remove(friend.id);
    });
    try {
      await widget.send(friend, text);
      if (!mounted) return;
      setState(() => _sent.add(friend.id));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors[friend.id] = _failureCopy(error, copy));
    } finally {
      if (mounted) setState(() => _busy.remove(friend.id));
    }
  }

  /// Friendly copy only — the callable's refusals (blocked, not friends,
  /// privacy, rate limit) arrive as gRPC codes and must never reach the row
  /// as raw exception text.
  static String _failureCopy(Object error, AppLocalizations copy) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission-denied') ||
        raw.contains('permission_denied') ||
        raw.contains('failed-precondition')) {
      return copy.text(
        "You can't message this person right now.",
        'Nie możesz teraz wysłać wiadomości do tej osoby.',
      );
    }
    if (raw.contains('resource-exhausted')) {
      return copy.text(
        "You're sending invitations too quickly. Try again in a moment.",
        'Wysyłasz zaproszenia zbyt szybko. Spróbuj ponownie za chwilę.',
      );
    }
    return friendlyErrorMessage(
      error,
      fallback: copy.text(
        "Couldn't send the invitation. Please try again.",
        'Nie udało się wysłać zaproszenia. Spróbuj ponownie.',
      ),
      copy: copy,
    );
  }

  List<FriendUser> _filter(List<FriendUser> friends) {
    if (_query.isEmpty) return friends;
    return friends
        .where((friend) {
          return friend.displayName.toLowerCase().contains(_query) ||
              friend.username.toLowerCase().contains(_query) ||
              friend.email.toLowerCase().contains(_query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final isSheet = widget.presentation == InviteToRoomPresentation.sheet;
    final title = _title(copy);

    return Material(
      key: const ValueKey('invite-to-room-panel'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: isSheet
          ? const BorderRadius.vertical(top: Radius.circular(28))
          : BorderRadius.circular(24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: _canInvite ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoModalSheetChrome(
              sheetLabel: copy.text('room invitation', 'zaproszenie do pokoju'),
              surfaceColor: palette.surfaceRaised,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: const ValueKey('invite-to-room-title'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            if (!_canInvite)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Row(
                  key: const ValueKey('invite-private-note'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        copy.text(
                          'This room is private. Invitations cannot grant access to it, so there is nobody to invite from here.',
                          'Ten pokój jest prywatny. Zaproszenia nie dają do niego dostępu, więc nie ma tu kogo zapraszać.',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _LinkActions(onShare: _shareLink, onCopy: _copyLink),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: TextField(
                  key: const ValueKey('invite-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.surfaceMuted,
                    hintText: copy.text('Search friends', 'Szukaj znajomych'),
                    hintStyle: TextStyle(color: palette.textSecondary),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: palette.textSecondary,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: copy.text(
                              'Clear search',
                              'Wyczyść wyszukiwanie',
                            ),
                            onPressed: _search.clear,
                            icon: Icon(
                              Icons.close_rounded,
                              color: palette.textSecondary,
                            ),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<FriendUser>>(
                  stream: widget.friendsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _Notice(
                        icon: Icons.cloud_off_rounded,
                        text: copy.text(
                          "Couldn't load your friends. Please try again.",
                          'Nie udało się wczytać znajomych. Spróbuj ponownie.',
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      );
                    }
                    final all = snapshot.data!;
                    if (all.isEmpty) {
                      return _Notice(
                        icon: Icons.person_add_alt_1_rounded,
                        text: copy.text(
                          'Add friends first, then invite them here.',
                          'Najpierw dodaj znajomych, a potem zaproś ich tutaj.',
                        ),
                      );
                    }
                    final items = _filter(all);
                    if (items.isEmpty) {
                      return _Notice(
                        icon: Icons.search_off_rounded,
                        text: copy.text(
                          'No friends match your search.',
                          'Brak znajomych pasujących do wyszukiwania.',
                        ),
                      );
                    }
                    return ListView.separated(
                      key: const ValueKey('invite-friend-list'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: palette.border, height: 1),
                      itemBuilder: (context, index) {
                        final friend = items[index];
                        return _FriendRow(
                          friend: friend,
                          busy: _busy.contains(friend.id),
                          sent: _sent.contains(friend.id),
                          error: _errors[friend.id],
                          onSend: () => _send(friend),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Share + Copy side by side when the panel is wide enough for two
/// readable labels, stacked otherwise.
class _LinkActions extends StatelessWidget {
  const _LinkActions({required this.onShare, required this.onCopy});

  final Future<void> Function() onShare;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final share = OutlinedButton.icon(
      key: const ValueKey('invite-share-link'),
      onPressed: onShare,
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(copy.text('Share link', 'Udostępnij link')),
    );
    final copyLink = OutlinedButton.icon(
      key: const ValueKey('invite-copy-link'),
      onPressed: onCopy,
      icon: const Icon(Icons.link_rounded, size: 18),
      label: Text(copy.text('Copy link', 'Kopiuj link')),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 400) {
          return Row(
            children: [
              Expanded(child: share),
              const SizedBox(width: 10),
              Expanded(child: copyLink),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [share, const SizedBox(height: 8), copyLink],
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: palette.textTertiary, size: 28),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.busy,
    required this.sent,
    required this.error,
    required this.onSend,
  });

  final FriendUser friend;
  final bool busy;
  final bool sent;
  final String? error;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final handle = friend.username.trim();
    final subtitle =
        error ??
        (friend.isOnline
            ? copy.text('Online', 'Online')
            : handle.isNotEmpty
            ? '@$handle'
            : friend.email);

    final Widget trailing;
    if (busy) {
      trailing = FilledButton(
        key: ValueKey('invite-busy-${friend.id}'),
        onPressed: null,
        child: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (sent) {
      trailing = FilledButton.tonalIcon(
        key: ValueKey('invite-sent-${friend.id}'),
        onPressed: null,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: palette.successSurface,
          disabledForegroundColor: palette.successForeground,
        ),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: Text(copy.text('Sent', 'Wysłano')),
      );
    } else {
      trailing = FilledButton(
        key: ValueKey('invite-send-${friend.id}'),
        onPressed: onSend,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
        child: Text(
          error == null
              ? copy.text('Send', 'Wyślij')
              : copy.text('Retry', 'Ponów'),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      leading: UserAvatar(
        radius: 21,
        userId: friend.id,
        photoUrl: friend.photoUrl,
        displayName: friend.displayName,
      ),
      title: Text(
        friend.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: error == null
              ? palette.textSecondary
              : palette.dangerForeground,
          fontSize: 12.5,
        ),
      ),
      trailing: trailing,
    );
  }
}
