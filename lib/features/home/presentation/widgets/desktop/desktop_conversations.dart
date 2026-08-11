import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/global_chat_panel.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Which conversation the hub is showing.
///
/// [global] is a DIFFERENT KIND of thing from the other three and is
/// first on purpose: it is one shared public channel, while Friends,
/// Clubs and Private are filters over this account's own existing
/// conversations. There is deliberately no "All" tab — merging a public
/// community channel into a list of someone's private chats would present
/// public and private messages as the same kind of thing, which is
/// exactly the confusion the separation exists to prevent.
///
/// Switching tabs is local state, so the desktop shell, the rail and the
/// profile card never rebuild.
enum ConversationFilter { global, friends, clubs, private }

/// "Conversations" — the desktop Home hub under For you.
///
/// DATA, all of it already in the product:
///  - direct messages → [MessageService.watchConversations] (the exact
///    stream the Chats screen and the rail's unread badge read)
///  - club chat       → [ClubService.watchMyClubs] + one
///    [ClubChatService.watchLatestMessage] per club's default chat channel
///  - friend edges    → [FriendService.watchFriends]
///
///  - Global Chat     → [GlobalChatService], the canonical
///    `globalChat/main/messages` channel shared by the whole community
///
/// SCHEMA LIMIT, stated rather than papered over: for the three personal
/// tabs the data model has two conversation types — club channels and 1:1
/// direct conversations. There is no third "private" record. So `Private`
/// is every direct conversation (the model's own direct/private type) and
/// `Friends` is the subset of those whose counterpart is a confirmed
/// friend; Friends is therefore a subset of Private, not a disjoint
/// bucket. Club chat also has no per-member unread counter, so club rows
/// carry no unread badge — none is invented.
///
/// Global has no unread badge either: nothing in the schema records a
/// per-user last-seen marker for it, and inventing one would be a number
/// with nothing behind it. Global messages live in their own collection
/// and are never merged into the direct-message unread count the rail
/// badge shows. See docs/Decisions.md ADR-036 and ADR-037.
class DesktopConversations extends StatefulWidget {
  const DesktopConversations({
    required this.currentUserId,
    required this.onOpenConversation,
    required this.onOpenClub,
    required this.onSeeAllChats,
    required this.onFindFriends,
    required this.onOpenClubs,
    this.messageService,
    this.clubService,
    this.clubChatService,
    this.friendService,
    this.globalChatService,
    this.reportService,
    this.firebaseAuth,
    super.key,
  });

  final String currentUserId;

  /// Opens the existing ChatScreen for that conversation.
  final ValueChanged<Conversation> onOpenConversation;

  /// Opens the existing club surface (ClubOverviewScreen), which owns the
  /// club's channels and chat.
  final ValueChanged<Club> onOpenClub;

  /// Chats, in the fixed desktop shell's content slot.
  final VoidCallback onSeeAllChats;

  /// Friends, in the fixed desktop shell's content slot.
  final VoidCallback onFindFriends;

  /// Clubs, in the fixed desktop shell's content slot.
  final VoidCallback onOpenClubs;

  final MessageService? messageService;
  final ClubService? clubService;
  final ClubChatService? clubChatService;
  final FriendService? friendService;
  final GlobalChatService? globalChatService;
  final ReportService? reportService;
  final FirebaseAuth? firebaseAuth;

  /// Dense but scannable: five rows is the most the column fits without
  /// pushing the page into a second screen of scrolling.
  static const int visibleRows = 5;

  @override
  State<DesktopConversations> createState() => _DesktopConversationsState();
}

class _DesktopConversationsState extends State<DesktopConversations> {
  /// Global is this module's default view.
  ConversationFilter _filter = ConversationFilter.global;

  /// Resolved once from the ID token's `role` claim. Only decides which
  /// menu items are OFFERED on a message; firestore.rules is what
  /// authorizes a moderator deletion.
  bool _isStaff = false;

  Stream<List<Conversation>>? _conversations;
  Stream<List<FriendUser>>? _friends;
  Stream<List<Club>>? _clubs;
  ClubChatService? _clubChat;

  /// clubId → newest message in its default chat channel. Only clubs the
  /// user is actually a member of are ever subscribed.
  final Map<String, ClubMessage?> _clubPreviews = <String, ClubMessage?>{};
  final Map<String, StreamSubscription<ClubMessage?>> _clubSubs =
      <String, StreamSubscription<ClubMessage?>>{};

  @override
  void initState() {
    super.initState();
    // Every dependency is optional at runtime: Home degrades to empty
    // states rather than throwing when a service cannot be constructed.
    try {
      _conversations = (widget.messageService ?? MessageService())
          .watchConversations();
    } catch (_) {
      _conversations = null;
    }
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (_) {
      _friends = null;
    }
    try {
      _clubs = (widget.clubService ?? ClubService()).watchMyClubs();
      _clubChat = widget.clubChatService ?? ClubChatService();
    } catch (_) {
      _clubs = null;
      _clubChat = null;
    }
    unawaited(_resolveStaffClaim());
  }

  Future<void> _resolveStaffClaim() async {
    try {
      final user = (widget.firebaseAuth ?? FirebaseAuth.instance).currentUser;
      if (user == null) return;
      final token = await user.getIdTokenResult();
      final role = token.claims?['role'];
      final staff =
          role is String &&
          const ['moderator', 'admin', 'superAdmin'].contains(role);
      if (mounted && staff) setState(() => _isStaff = true);
    } catch (_) {
      // No claim, no token, or a harness without auth: no staff actions
      // are offered, which is the safe default.
    }
  }

  @override
  void dispose() {
    for (final sub in _clubSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  /// One preview listener per club currently in the list — dropped again
  /// as soon as a club leaves it.
  void _syncClubPreviews(List<Club> clubs) {
    final chat = _clubChat;
    if (chat == null) return;

    final ids = clubs.map((club) => club.id).toSet();
    for (final id in _clubSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _clubSubs.remove(id)?.cancel();
        _clubPreviews.remove(id);
      }
    }
    for (final club in clubs) {
      if (_clubSubs.containsKey(club.id)) continue;
      final channelId = club.defaultChatChannelId.trim();
      if (channelId.isEmpty) continue;
      _clubSubs[club.id] = chat
          .watchLatestMessage(clubId: club.id, channelId: channelId)
          .listen((message) {
            if (!mounted) return;
            setState(() => _clubPreviews[club.id] = message);
          }, onError: (_) {});
    }
  }

  List<_ConversationRow> _rowsFor(
    ConversationFilter filter,
    List<Conversation> direct,
    Set<String> friendIds,
    List<Club> clubs,
  ) {
    final uid = widget.currentUserId;

    List<_ConversationRow> clubRows() => [
      for (final club in clubs)
        () {
          final message = _clubPreviews[club.id];
          return _ConversationRow(
            id: 'club:${club.id}',
            name: club.name,
            photoUrl: club.avatarUrl,
            fallbackIcon: Icons.groups_rounded,
            preview: message == null
                ? 'No messages yet'
                : message.isDeleted
                ? 'Message deleted'
                : '${message.senderId == uid ? 'You' : message.senderName}: '
                      '${message.content}',
            timestamp: message?.sentAt,
            // Club channels keep no per-member read state; a badge here
            // would be a number nothing in the schema backs.
            unread: 0,
            muted: false,
            typeLabel: 'Club',
            onTap: () => widget.onOpenClub(club),
          );
        }(),
    ];

    List<_ConversationRow> directRows(Iterable<Conversation> source) => [
      for (final conversation in source)
        () {
          final otherId = conversation.otherUserId(uid);
          final isFriend = friendIds.contains(otherId);
          return _ConversationRow(
            id: 'dm:${conversation.id}',
            name: conversation.displayNameFor(otherId),
            photoUrl: conversation.photoUrlFor(otherId),
            fallbackIcon: Icons.person_rounded,
            preview: conversation.previewFor(uid),
            timestamp: conversation.updatedAt,
            unread: conversation.unreadCountFor(uid),
            muted: conversation.isMutedFor(uid),
            typeLabel: isFriend ? 'Friend' : 'Direct',
            onTap: () => widget.onOpenConversation(conversation),
          );
        }(),
    ];

    final rows = switch (filter) {
      // Global is not a row list at all — it renders the live channel.
      ConversationFilter.global => <_ConversationRow>[],
      ConversationFilter.clubs => clubRows(),
      ConversationFilter.friends => directRows(
        direct.where(
          (conversation) => friendIds.contains(conversation.otherUserId(uid)),
        ),
      ),
      // The model's own direct/private conversation type, in full.
      ConversationFilter.private => directRows(direct),
    };

    rows.sort((a, b) {
      final aAt = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return rows;
  }

  (String, String, VoidCallback) _emptyFor(ConversationFilter filter) {
    return switch (filter) {
      // Unused: the Global tab renders its own states inside the panel.
      ConversationFilter.global => ('', '', widget.onFindFriends),
      ConversationFilter.clubs => (
        'You have not joined a club yet.',
        'Browse Clubs',
        widget.onOpenClubs,
      ),
      ConversationFilter.friends => (
        'No chats with your friends yet.',
        'Find friends',
        widget.onFindFriends,
      ),
      ConversationFilter.private => (
        'No direct messages yet.',
        'Find friends',
        widget.onFindFriends,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Conversation>>(
      stream: _conversations,
      builder: (context, conversationSnapshot) {
        return StreamBuilder<List<FriendUser>>(
          stream: _friends,
          builder: (context, friendSnapshot) {
            return StreamBuilder<List<Club>>(
              stream: _clubs,
              builder: (context, clubSnapshot) {
                final direct =
                    conversationSnapshot.data ?? const <Conversation>[];
                final clubs = clubSnapshot.data ?? const <Club>[];
                final friendIds = {
                  for (final friend in friendSnapshot.data ?? const <FriendUser>[])
                    friend.id,
                };

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _syncClubPreviews(clubs);
                });

                final isGlobal = _filter == ConversationFilter.global;
                final rows = _rowsFor(_filter, direct, friendIds, clubs);
                final (emptyText, emptyAction, onEmptyAction) = _emptyFor(
                  _filter,
                );

                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFF120C1D).withValues(alpha: .75),
                    border: Border.all(color: const Color(0xFF241A33)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Conversations',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          // Says whose conversation this is, so a public
                          // channel is never mistaken for a private one.
                          if (isGlobal) ...[
                            const SizedBox(width: 9),
                            const _CommunityIndicator(),
                          ],
                          const Spacer(),
                          // "See all chats" goes to the direct-message
                          // inbox, which is not where Global lives.
                          if (!isGlobal)
                            _SeeAllChats(onTap: widget.onSeeAllChats),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _FilterBar(
                        active: _filter,
                        onChanged: (filter) => setState(() => _filter = filter),
                      ),
                      const SizedBox(height: 6),
                      if (isGlobal)
                        GlobalChatPanel(
                          currentUserId: widget.currentUserId,
                          chatService: widget.globalChatService,
                          reportService: widget.reportService,
                          isStaff: _isStaff,
                        )
                      else if (rows.isEmpty)
                        _FilterEmptyState(
                          text: emptyText,
                          actionLabel: emptyAction,
                          onAction: onEmptyAction,
                        )
                      else
                        for (final row
                            in rows.take(DesktopConversations.visibleRows))
                          _ConversationTile(key: ValueKey(row.id), row: row),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Names the audience of the Global tab in one glance.
class _CommunityIndicator extends StatelessWidget {
  const _CommunityIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.primary.withValues(alpha: .14),
        border: Border.all(color: AppColors.primary.withValues(alpha: .38)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded, size: 12, color: Color(0xFFD3A5FF)),
          SizedBox(width: 5),
          Text(
            'YO Voice community',
            style: TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAllChats extends StatelessWidget {
  const _SeeAllChats({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'See all chats',
            style: TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 3),
          Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD3A5FF)),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.active, required this.onChanged});

  final ConversationFilter active;
  final ValueChanged<ConversationFilter> onChanged;

  static const _labels = <ConversationFilter, String>{
    ConversationFilter.global: 'Global',
    ConversationFilter.friends: 'Friends',
    ConversationFilter.clubs: 'Clubs',
    ConversationFilter.private: 'Private',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final entry in _labels.entries)
          _FilterPill(
            label: entry.value,
            selected: entry.key == active,
            onTap: () => onChanged(entry.key),
          ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? AppColors.primary.withValues(alpha: .20)
                : Colors.white.withValues(alpha: .03),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: .55)
                  : const Color(0xFF2E2140),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFB3A8C4),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the hub, built from whichever real record it came from.
class _ConversationRow {
  const _ConversationRow({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.fallbackIcon,
    required this.preview,
    required this.timestamp,
    required this.unread,
    required this.muted,
    required this.typeLabel,
    required this.onTap,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final IconData fallbackIcon;
  final String preview;
  final DateTime? timestamp;
  final int unread;
  final bool muted;
  final String typeLabel;
  final VoidCallback onTap;
}

class _ConversationTile extends StatefulWidget {
  const _ConversationTile({required this.row, super.key});

  final _ConversationRow row;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hover = false;

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
    final row = widget.row;
    final unread = row.unread > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: row.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _hover
                ? Colors.white.withValues(alpha: .04)
                : Colors.transparent,
            border: Border.all(
              color: _hover
                  ? AppColors.primary.withValues(alpha: .30)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              UserAvatar(
                radius: 18,
                photoUrl: row.photoUrl,
                displayName: row.name,
                fallbackIcon: row.fallbackIcon,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: unread
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _TypeLabel(row.typeLabel),
                        if (row.muted) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.notifications_off_rounded,
                            size: 12,
                            color: Color(0xFF7E7895),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread
                            ? const Color(0xFFCFC6DC)
                            : const Color(0xFF9A90AC),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _stamp(row.timestamp),
                    style: const TextStyle(
                      color: Color(0xFF7E7895),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (unread)
                    Container(
                      constraints: const BoxConstraints(minWidth: 19),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        row.unread > 99 ? '99+' : '${row.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeLabel extends StatelessWidget {
  const _TypeLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withValues(alpha: .04),
        border: Border.all(color: const Color(0xFF2E2140)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9A90AC),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _FilterEmptyState extends StatelessWidget {
  const _FilterEmptyState({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: Color(0xFFD3A5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
