import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

/// Opens the production New message route.
///
/// Kept public so route-level tests and the dev preview exercise the exact
/// BottomSheet configuration used by [MessagesScreen], including handle
/// ownership and dismissal behavior.
Future<void> showNewMessageSheet(
  BuildContext context, {
  required Stream<List<FriendUser>> friendsStream,
  required Stream<List<Conversation>> conversationsStream,
  required String currentUserId,
  required ValueChanged<FriendUser> onFriendSelected,
  required ValueChanged<Conversation> onConversationSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    builder: (sheetContext) => NewMessageSheet(
      friendsStream: friendsStream,
      conversationsStream: conversationsStream,
      currentUserId: currentUserId,
      onFriendSelected: (friend) {
        Navigator.pop(sheetContext);
        onFriendSelected(friend);
      },
      onConversationSelected: (conversation) {
        Navigator.pop(sheetContext);
        onConversationSelected(conversation);
      },
    ),
  );
}

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    this.messageService,
    this.friendService,
    this.auth,
    super.key,
  });

  /// Optional injection seams, matching the established pattern on
  /// FriendProfileScreen and NotificationsScreen: production passes
  /// nothing and gets the live singletons, tests pass fakes so the
  /// failure paths below can be exercised without a Firebase app.
  final MessageService? messageService;
  final FriendService? friendService;
  final FirebaseAuth? auth;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final MessageService _messageService =
      widget.messageService ?? MessageService.live;
  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  final TextEditingController _searchController = TextEditingController();

  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;

  late final Stream<List<Conversation>> _conversationsStream;
  late final Stream<List<FriendUser>> _friendsStream;

  String _query = '';
  bool _showArchived = false;
  bool _conversationNavigationInFlight = false;

  @override
  void initState() {
    super.initState();
    _conversationsStream = _messageService.watchConversations(
      includeArchived: true,
    );
    _friendsStream = _friendService.watchFriends();
    _searchController.addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    final value = _searchController.text.trim().toLowerCase();

    if (value == _query) {
      return;
    }

    setState(() => _query = value);
  }

  Future<void> _openConversation(
    Conversation conversation, {
    FriendUser? liveFriend,
  }) => _runConversationNavigation(
    () => _openConversationOnce(conversation, liveFriend: liveFriend),
  );

  Future<void> _runConversationNavigation(
    Future<void> Function() navigate,
  ) async {
    if (_conversationNavigationInFlight) return;
    _conversationNavigationInFlight = true;
    try {
      await navigate();
    } finally {
      _conversationNavigationInFlight = false;
    }
  }

  Future<void> _openConversationOnce(
    Conversation conversation, {
    FriendUser? liveFriend,
  }) async {
    final currentUserId = _auth.currentUser?.uid;

    if (currentUserId == null) {
      return;
    }

    final otherUserId = conversation.otherUserId(currentUserId);

    if (conversation.isArchivedFor(currentUserId)) {
      try {
        await _messageService.unarchiveConversation(conversation.id);
      } catch (error) {
        // Opening is the tap's intent; un-archiving is the side effect. A
        // rejected un-archive must not swallow the tap AND stay silent —
        // this method is fired through `unawaited`, so without this the
        // conversation simply never opened and nothing was ever said.
        if (mounted) {
          final copy = AppLocalizations.of(context);
          _showMessage(
            intentionalOrFriendly(
              error,
              fallback: copy.text(
                'Could not move this conversation out of Archived.',
                'Nie udało się przenieść tej rozmowy z archiwum.',
              ),
            ),
            isError: true,
          );
        }
      }
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
          otherDisplayName:
              liveFriend?.displayName ??
              conversation.displayNameFor(otherUserId),
          otherEmail: '',
          otherPhotoUrl: liveFriend == null
              ? conversation.photoUrlFor(otherUserId)
              : liveFriend.photoUrl ?? '',
          otherProfileUpdatedAt: liveFriend?.profileUpdatedAt,
          messageService: widget.messageService,
          auth: widget.auth,
        ),
      ),
    );
  }

  Future<void> _startChat(FriendUser friend) =>
      _runConversationNavigation(() => _startChatOnce(friend));

  Future<void> _startChatOnce(FriendUser friend) async {
    try {
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: '',
        otherPhotoUrl: friend.photoUrl ?? '',
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: '',
            otherPhotoUrl: friend.photoUrl ?? '',
            otherProfileUpdatedAt: friend.profileUpdatedAt,
            messageService: widget.messageService,
            auth: widget.auth,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        intentionalOrFriendly(
          error,
          fallback: AppLocalizations.of(context).text(
            'Could not open this conversation.',
            'Nie udało się otworzyć tej rozmowy.',
          ),
        ),
        isError: true,
      );
    }
  }

  Future<void> _showNewMessageSheet() async {
    await showNewMessageSheet(
      context,
      friendsStream: _friendsStream,
      conversationsStream: _conversationsStream,
      currentUserId: _auth.currentUser?.uid ?? '',
      onFriendSelected: (friend) => unawaited(_startChat(friend)),
      onConversationSelected: (conversation) =>
          unawaited(_openConversation(conversation)),
    );
  }

  Future<void> _archiveConversation(Conversation conversation) async {
    try {
      await _messageService.archiveConversation(conversation.id);
      if (mounted) {
        _showMessage(
          AppLocalizations.of(
            context,
          ).text('Conversation archived.', 'Rozmowa została zarchiwizowana.'),
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).text(
            'Could not archive this conversation.',
            'Nie udało się zarchiwizować tej rozmowy.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _unarchiveConversation(Conversation conversation) async {
    try {
      await _messageService.unarchiveConversation(conversation.id);
      if (mounted) {
        _showMessage(
          AppLocalizations.of(
            context,
          ).text('Conversation restored.', 'Rozmowa została przywrócona.'),
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).text(
            'Could not restore this conversation.',
            'Nie udało się przywrócić tej rozmowy.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _toggleMute(Conversation conversation, bool isMuted) async {
    try {
      await _messageService.setConversationMuted(
        conversationId: conversation.id,
        muted: !isMuted,
      );

      if (mounted) {
        final copy = AppLocalizations.of(context);
        _showMessage(
          isMuted
              ? copy.text(
                  'Notifications turned on.',
                  'Powiadomienia zostały włączone.',
                )
              : copy.text(
                  'Conversation muted.',
                  'Powiadomienia dla rozmowy zostały wyciszone.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).text(
            'Could not update notifications.',
            'Nie udało się zmienić ustawień powiadomień.',
          ),
          isError: true,
        );
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final palette = context.appPalette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: isError
                  ? palette.dangerForeground
                  : palette.infoForeground,
            ),
          ),
          backgroundColor: isError
              ? palette.dangerSurface
              : palette.infoSurface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: const ValueKey('messages-screen'),
      backgroundColor: palette.background,
      body: YoPageBackground(
        section: YoPageSection.chats,
        key: const ValueKey('messages-screen-background'),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.86, -.96),
            radius: 1.25,
            colors: [
              Color.lerp(
                palette.backgroundTop,
                colors.primary,
                isDark ? .18 : .055,
              )!,
              palette.backgroundTop,
              palette.background,
            ],
            stops: const [0, .38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: StreamBuilder<List<FriendUser>>(
              stream: _friendsStream,
              builder: (context, friendsSnapshot) {
                final friends = friendsSnapshot.data ?? const <FriendUser>[];
                final friendsById = {
                  for (final friend in friends) friend.id: friend,
                };
                // Header, search and friend rail can leave the viewport on a
                // short screen / enlarged text. Conversations stay lazy rather
                // than being shrink-wrapped into an eager all-message column.
                return NestedScrollView(
                  key: const ValueKey('messages-coordinated-scroll'),
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverToBoxAdapter(
                      child: _MessagesHeader(
                        showArchived: _showArchived,
                        onNewMessage: _showNewMessageSheet,
                        onToggleArchived: () {
                          setState(() => _showArchived = !_showArchived);
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 13),
                        child: _SearchField(controller: _searchController),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _FriendsRow(
                          friends: friends,
                          onFriendSelected: _startChat,
                          onAdd: _showNewMessageSheet,
                        ),
                      ),
                    ),
                  ],
                  body: StreamBuilder<List<Conversation>>(
                    stream: _conversationsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: palette.interactiveForeground,
                            strokeWidth: 2.5,
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return _MessagesError(
                          message: _readableError(snapshot.error),
                        );
                      }

                      if (currentUserId == null) {
                        return _MessagesError(
                          message: AppLocalizations.of(context).text(
                            'Sign in to open your chats.',
                            'Zaloguj się, aby otworzyć swoje czaty.',
                          ),
                        );
                      }

                      final allConversations =
                          snapshot.data ?? const <Conversation>[];
                      final conversations = allConversations
                          .where((conversation) {
                            final archived = conversation.isArchivedFor(
                              currentUserId,
                            );

                            if (_showArchived != archived) {
                              return false;
                            }

                            if (_query.isEmpty) {
                              return true;
                            }

                            final otherId = conversation.otherUserId(
                              currentUserId,
                            );
                            final name =
                                (friendsById[otherId]?.displayName ??
                                        conversation.displayNameFor(otherId))
                                    .toLowerCase();
                            final preview = _localizedConversationPreview(
                              conversation,
                              currentUserId,
                              AppLocalizations.of(context),
                            ).toLowerCase();

                            return name.contains(_query) ||
                                preview.contains(_query);
                          })
                          .toList(growable: false);

                      if (conversations.isEmpty) {
                        return _EmptyMessages(
                          archived: _showArchived,
                          hasSearch: _query.isNotEmpty,
                          onNewMessage: _showNewMessageSheet,
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 118),
                        itemCount: conversations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final conversation = conversations[index];
                          final muted = conversation.isMutedFor(currentUserId);
                          final otherUserId = conversation.otherUserId(
                            currentUserId,
                          );
                          final liveFriend = friendsById[otherUserId];

                          return _ConversationTile(
                            conversation: conversation,
                            currentUserId: currentUserId,
                            liveFriend: liveFriend,
                            muted: muted,
                            service: _messageService,
                            onTap: () => _openConversation(
                              conversation,
                              liveFriend: liveFriend,
                            ),
                            onArchive: () => _archiveConversation(conversation),
                            onUnarchive: () =>
                                _unarchiveConversation(conversation),
                            onToggleMute: () =>
                                _toggleMute(conversation, muted),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _readableError(Object? error) {
    // Developer-speak ("check your security rules", "needs an index")
    // never belongs in user-facing copy — route through the shared
    // mapping with a flow-specific fallback.
    final fallback = AppLocalizations.of(context).text(
      'Could not load your conversations.',
      'Nie udało się wczytać rozmów.',
    );
    if (error == null) return fallback;
    return friendlyErrorMessage(error, fallback: fallback);
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({
    required this.showArchived,
    required this.onNewMessage,
    required this.onToggleArchived,
  });

  final bool showArchived;
  final VoidCallback onNewMessage;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showArchived
                      ? copy.text('Archived', 'Archiwum')
                      : copy.text('Chats', 'Czaty'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  showArchived
                      ? copy.text(
                          'Conversations kept out of your inbox.',
                          'Rozmowy przeniesione poza główną skrzynkę.',
                        )
                      : copy.text(
                          'Private conversations with your friends.',
                          'Prywatne rozmowy ze znajomymi.',
                        ),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          _HeaderButton(
            icon: showArchived ? Icons.inbox_rounded : Icons.archive_outlined,
            tooltip: showArchived
                ? copy.text('Show inbox', 'Pokaż skrzynkę odbiorczą')
                : copy.text(
                    'Show archived conversations',
                    'Pokaż zarchiwizowane rozmowy',
                  ),
            onTap: onToggleArchived,
          ),
          const SizedBox(width: 9),
          _HeaderButton(
            icon: Icons.edit_square,
            tooltip: copy.text(
              'Start a new message',
              'Rozpocznij nową rozmowę',
            ),
            onTap: onNewMessage,
            highlighted: true,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: AccessibleTapRegion(
        semanticLabel: tooltip,
        onTap: onTap,
        borderRadius: 15,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: highlighted ? colors.primary : palette.surfaceRaised,
            borderRadius: BorderRadius.circular(15),
            border: highlighted
                ? null
                : Border.all(color: palette.borderStrong),
          ),
          child: ExcludeSemantics(
            child: Icon(
              icon,
              color: highlighted ? colors.onPrimary : palette.textPrimary,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return TextField(
      controller: controller,
      style: TextStyle(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: copy.text('Search', 'Szukaj'),
        hintStyle: TextStyle(color: palette.textTertiary),
        prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }

            return IconButton(
              onPressed: controller.clear,
              tooltip: copy.text('Clear search', 'Wyczyść wyszukiwanie'),
              icon: Icon(Icons.close_rounded, color: palette.textSecondary),
            );
          },
        ),
        filled: true,
        fillColor: palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: palette.focus, width: 2),
        ),
      ),
    );
  }
}

class _FriendsRow extends StatelessWidget {
  const _FriendsRow({
    required this.friends,
    required this.onFriendSelected,
    required this.onAdd,
  });

  final List<FriendUser> friends;
  final ValueChanged<FriendUser> onFriendSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final labelScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final height = 92.0 + (labelScale - 1).clamp(0.0, 2.0) * 14.0;

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          _FriendStory(
            label: copy.text('New', 'Nowa'),
            semanticLabel: copy.text('New message', 'Nowa wiadomość'),
            icon: Icons.add_rounded,
            onTap: onAdd,
          ),
          ...friends
              .take(12)
              .map(
                (friend) => _FriendStory(
                  label: friend.displayName,
                  semanticLabel:
                      '${friend.displayName}, ${friend.isOnline ? copy.text('online', 'aktywny') : copy.text('offline', 'nieaktywny')}',
                  friend: friend,
                  onTap: () => onFriendSelected(friend),
                ),
              ),
        ],
      ),
    );
  }
}

class _FriendStory extends StatelessWidget {
  const _FriendStory({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.friend,
    this.icon,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final FriendUser? friend;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final user = friend;
    final hasPhoto = user?.photoUrl?.trim().isNotEmpty == true;
    final palette = context.appPalette;

    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: 18,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFFF416C),
                          Color(0xFFB42DFF),
                          Color(0xFF5D00D7),
                        ],
                      ),
                    ),
                    child: UserAvatar(
                      radius: 27,
                      userId: user?.id,
                      photoUrl: hasPhoto ? user!.photoUrl : null,
                      mediaRevision: user?.profileUpdatedAt,
                      displayName: user?.displayName,
                      fallbackIcon: icon,
                    ),
                  ),
                  if (user?.isOnline == true)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: palette.successForeground,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.background,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.liveFriend,
    required this.muted,
    required this.service,
    required this.onTap,
    required this.onArchive,
    required this.onUnarchive,
    required this.onToggleMute,
  });

  final Conversation conversation;
  final String currentUserId;
  final FriendUser? liveFriend;
  final bool muted;

  /// The screen's own service, rather than one built inside `build` —
  /// see [_ConversationAvatar].
  final MessageService service;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onToggleMute;

  bool get _archived => conversation.isArchivedFor(currentUserId);

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final friend = liveFriend;
    final name =
        friend?.displayName ?? conversation.displayNameFor(otherUserId);
    final photoUrl = friend == null
        ? conversation.photoUrlFor(otherUserId)
        : friend.photoUrl ?? '';
    final unread = conversation.unreadCountFor(currentUserId);
    final preview = _localizedConversationPreview(
      conversation,
      currentUserId,
      AppLocalizations.of(context),
    );
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showActions(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: unread > 0
                ? colors.primary.withValues(alpha: .09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: enlargedText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ConversationAvatar(
                          name: name,
                          photoUrl: photoUrl,
                          userId: otherUserId,
                          mediaRevision: friend?.profileUpdatedAt,
                          service: service,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _relativeTime(
                                  context,
                                  conversation.updatedAt,
                                  copy,
                                ),
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              if (muted)
                                Icon(
                                  Icons.notifications_off_outlined,
                                  color: palette.textSecondary,
                                  size: 18,
                                ),
                              if (unread > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: TextStyle(
                                      color: colors.onPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showActions(context),
                          tooltip: copy.template(
                            'Conversation actions for {name}',
                            'Opcje rozmowy z {name}',
                            values: {'name': name},
                          ),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      name,
                      key: ValueKey(
                        'conversation-expanded-name-${conversation.id}',
                      ),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: unread > 0
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _ConversationAvatar(
                      name: name,
                      photoUrl: photoUrl,
                      userId: otherUserId,
                      mediaRevision: friend?.profileUpdatedAt,
                      service: service,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 15,
                                    fontWeight: unread > 0
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _relativeTime(
                                  context,
                                  conversation.updatedAt,
                                  copy,
                                ),
                                style: TextStyle(
                                  color: unread > 0
                                      ? palette.focus
                                      : palette.textTertiary,
                                  fontSize: 11,
                                  fontWeight: unread > 0
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: unread > 0
                                        ? palette.textPrimary
                                        : palette.textSecondary,
                                    fontSize: 13,
                                    fontWeight: unread > 0
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (muted) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.notifications_off_outlined,
                                  color: palette.textSecondary,
                                  size: 16,
                                ),
                              ],
                              if (unread > 0) ...[
                                const SizedBox(width: 9),
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: TextStyle(
                                      color: colors.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showActions(context),
                      tooltip: copy.template(
                        'Conversation actions for {name}',
                        'Opcje rozmowy z {name}',
                        values: {'name': name},
                      ),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      builder: (sheetContext) {
        return _ConversationActionsSheet(
          muted: muted,
          archived: _archived,
          onMute: () {
            Navigator.pop(sheetContext);
            onToggleMute();
          },
          onArchive: () {
            Navigator.pop(sheetContext);
            if (_archived) {
              onUnarchive();
            } else {
              onArchive();
            }
          },
        );
      },
    );
  }

  static String _relativeTime(
    BuildContext context,
    DateTime date,
    AppLocalizations copy,
  ) {
    if (date.millisecondsSinceEpoch == 0) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return copy.text('now', 'teraz');
    if (difference.inMinutes < 60) {
      return copy.text(
        '${difference.inMinutes}m',
        '${difference.inMinutes} min',
      );
    }
    if (difference.inHours < 24) {
      return copy.text('${difference.inHours}h', '${difference.inHours} godz.');
    }
    if (difference.inDays < 7) {
      const english = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const polish = ['pon.', 'wt.', 'śr.', 'czw.', 'pt.', 'sob.', 'niedz.'];
      if (copy.locale.languageCode == 'en') return english[date.weekday - 1];
      if (copy.isPolish) return polish[date.weekday - 1];
      final localizations = MaterialLocalizations.of(context);
      return localizations.narrowWeekdays[date.weekday % 7];
    }
    return copy.text('${date.day}/${date.month}', '${date.day}.${date.month}');
  }
}

/// Stateful on purpose: this used to construct a brand new
/// [MessageService] and open a brand new presence subscription on EVERY
/// build, which both coupled the tile to the live Firebase singletons and
/// leaked a Firestore listener per rebuild. The screen's service is passed
/// in and the stream is opened once.
class _ConversationAvatar extends StatefulWidget {
  const _ConversationAvatar({
    required this.name,
    required this.photoUrl,
    required this.userId,
    required this.mediaRevision,
    required this.service,
  });

  final String name;
  final String photoUrl;
  final String userId;
  final Object? mediaRevision;
  final MessageService service;

  @override
  State<_ConversationAvatar> createState() => _ConversationAvatarState();
}

class _ConversationAvatarState extends State<_ConversationAvatar> {
  late Stream<ChatPresence> _presence = widget.service.watchUserPresence(
    widget.userId,
  );

  @override
  void didUpdateWidget(_ConversationAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.service != widget.service) {
      _presence = widget.service.watchUserPresence(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final photoUrl = widget.photoUrl;

    return StreamBuilder<ChatPresence>(
      stream: _presence,
      builder: (context, snapshot) {
        final online = snapshot.data?.isOnline ?? false;
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);

        return Semantics(
          label:
              '$name, ${online ? copy.text('online', 'aktywny') : copy.text('offline', 'nieaktywny')}',
          image: true,
          excludeSemantics: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                radius: 29,
                userId: widget.userId,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? palette.surfaceSunken
                    : Theme.of(context).colorScheme.primary,
                photoUrl: photoUrl,
                mediaRevision: widget.mediaRevision,
                displayName: name,
              ),
              if (online)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: palette.successForeground,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.background, width: 3),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationActionsSheet extends StatelessWidget {
  const _ConversationActionsSheet({
    required this.muted,
    required this.archived,
    required this.onMute,
    required this.onArchive,
  });

  final bool muted;

  /// An archived thread offers "Unarchive" — the sheet used to say
  /// "Archive" even inside the Archived view, so testers saw no way back.
  final bool archived;
  final VoidCallback onMute;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return Material(
      color: palette.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          18 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoModalSheetChrome(
              sheetLabel: copy.text('conversation actions', 'opcje rozmowy'),
              surfaceColor: palette.surfaceRaised,
            ),
            const SizedBox(height: 2),
            ListTile(
              onTap: onMute,
              leading: Icon(
                muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: palette.textPrimary,
              ),
              title: Text(
                muted
                    ? copy.text('Unmute messages', 'Włącz powiadomienia')
                    : copy.text('Mute messages', 'Wycisz powiadomienia'),
                style: TextStyle(color: palette.textPrimary),
              ),
            ),
            ListTile(
              key: const ValueKey('conversation-archive-action'),
              onTap: onArchive,
              leading: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                color: palette.textPrimary,
              ),
              title: Text(
                archived
                    ? copy.text('Unarchive conversation', 'Przywróć z archiwum')
                    : copy.text('Archive conversation', 'Archiwizuj rozmowę'),
                style: TextStyle(color: palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "New message" bottom sheet.
///
/// Public (rather than library-private) so it can be driven directly by
/// widget tests and by `lib/dev/new_message_preview.dart` with controlled
/// loading/empty/error streams — reaching it through [MessagesScreen] would
/// otherwise require a live Firebase session.
class NewMessageSheet extends StatefulWidget {
  const NewMessageSheet({
    required this.friendsStream,
    required this.conversationsStream,
    required this.currentUserId,
    required this.onFriendSelected,
    required this.onConversationSelected,
    super.key,
  });

  final Stream<List<FriendUser>> friendsStream;
  final Stream<List<Conversation>> conversationsStream;
  final String currentUserId;
  final ValueChanged<FriendUser> onFriendSelected;
  final ValueChanged<Conversation> onConversationSelected;

  @override
  State<NewMessageSheet> createState() => NewMessageSheetState();
}

class NewMessageSheetState extends State<NewMessageSheet> {
  final TextEditingController _controller = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final value = _controller.text.trim().toLowerCase();

      if (value != _query) {
        setState(() => _query = value);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .76,
      minChildSize: .5,
      maxChildSize: .94,
      builder: (context, scrollController) {
        // A Material (not a bare DecoratedBox/Container) owns this surface:
        // showModalBottomSheet is invoked with a transparent background, so
        // this is the sheet's real surface, and the ListTiles below paint
        // their background + ink splashes onto the nearest Material
        // ancestor. Painting it with a plain Container instead put an
        // opaque box between those tiles and the Material, hiding taps.
        return Material(
          key: const ValueKey('new-message-sheet-surface'),
          color: palette.surfaceRaised,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Column(
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text('New message', 'Nowa wiadomość'),
                surfaceColor: palette.surfaceRaised,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    copy.text('New message', 'Nowa wiadomość'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SearchField(controller: _controller),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: StreamBuilder<List<Conversation>>(
                  stream: widget.conversationsStream,
                  builder: (context, conversationSnapshot) {
                    final conversations =
                        conversationSnapshot.data ?? const <Conversation>[];

                    return StreamBuilder<List<FriendUser>>(
                      stream: widget.friendsStream,
                      builder: (context, friendSnapshot) {
                        final friends =
                            friendSnapshot.data ?? const <FriendUser>[];
                        final friendsById = {
                          for (final friend in friends) friend.id: friend,
                        };
                        final loading =
                            conversationSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            friendSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            conversations.isEmpty &&
                            friends.isEmpty;

                        if (loading) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: palette.interactiveForeground,
                            ),
                          );
                        }

                        // Without this the sheet answered a failed query
                        // with "You're all caught up", which reads as "you
                        // have no friends" rather than "we couldn't load
                        // them".
                        final failed =
                            (conversationSnapshot.hasError ||
                                friendSnapshot.hasError) &&
                            conversations.isEmpty &&
                            friends.isEmpty;

                        if (failed) {
                          return const _NewMessageErrorState();
                        }

                        final recent =
                            conversations
                                .where(
                                  (c) =>
                                      !c.isArchivedFor(widget.currentUserId) &&
                                      c.lastMessage.isNotEmpty,
                                )
                                .map((conversation) {
                                  final otherId = conversation.otherUserId(
                                    widget.currentUserId,
                                  );
                                  final friend = friendsById[otherId];
                                  if (friend == null) return conversation;
                                  return conversation.withParticipantIdentity(
                                    userId: otherId,
                                    displayName: friend.displayName,
                                    photoUrl: friend.photoUrl ?? '',
                                  );
                                })
                                .toList(growable: false)
                              ..sort(
                                (a, b) => b.updatedAt.compareTo(a.updatedAt),
                              );
                        final recentIds = recent
                            .map((c) => c.otherUserId(widget.currentUserId))
                            .toSet();

                        bool matchesQuery(String name, [String handle = '']) {
                          if (_query.isEmpty) return true;
                          return name.toLowerCase().contains(_query) ||
                              handle.toLowerCase().contains(_query);
                        }

                        final filteredRecent = recent
                            .take(6)
                            .where((c) {
                              final otherId = c.otherUserId(
                                widget.currentUserId,
                              );
                              return matchesQuery(c.displayNameFor(otherId));
                            })
                            .toList(growable: false);

                        final filteredFriends = friends
                            .where(
                              (friend) =>
                                  !recentIds.contains(friend.id) &&
                                  matchesQuery(
                                    friend.displayName,
                                    friend.username,
                                  ),
                            )
                            .toList(growable: false);

                        if (filteredRecent.isEmpty && filteredFriends.isEmpty) {
                          return _NewMessageEmptyState(
                            hasSearch: _query.isNotEmpty,
                            hasNoFriendsAtAll: friends.isEmpty,
                          );
                        }

                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                          children: [
                            if (filteredRecent.isNotEmpty) ...[
                              _NewMessageSectionLabel(
                                copy.text('Recent', 'Ostatnie'),
                              ),
                              for (final conversation in filteredRecent)
                                _RecentChatTile(
                                  conversation: conversation,
                                  currentUserId: widget.currentUserId,
                                  liveFriend:
                                      friendsById[conversation.otherUserId(
                                        widget.currentUserId,
                                      )],
                                  onTap: () => widget.onConversationSelected(
                                    conversation,
                                  ),
                                ),
                              const SizedBox(height: 6),
                            ],
                            if (filteredFriends.isNotEmpty) ...[
                              _NewMessageSectionLabel(
                                copy.text('Friends', 'Znajomi'),
                              ),
                              for (final friend in filteredFriends)
                                _FriendTile(
                                  friend: friend,
                                  onTap: () => widget.onFriendSelected(friend),
                                ),
                            ],
                            const SizedBox(height: 10),
                            _InviteFriendsTile(
                              onTap: () => SharePlus.instance.share(
                                ShareParams(
                                  text: copy.text(
                                    'Join me on YO Voice — the app for live voice rooms and communities: https://yovoice.app/download',
                                    'Dołącz do mnie w YO Voice — aplikacji z pokojami głosowymi na żywo i społecznościami: https://yovoice.app/download',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewMessageSectionLabel extends StatelessWidget {
  const _NewMessageSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _RecentChatTile extends StatelessWidget {
  const _RecentChatTile({
    required this.conversation,
    required this.currentUserId,
    required this.liveFriend,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final FriendUser? liveFriend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherId = conversation.otherUserId(currentUserId);
    final name =
        liveFriend?.displayName ?? conversation.displayNameFor(otherId);
    final photoUrl = liveFriend?.photoUrl ?? conversation.photoUrlFor(otherId);
    final palette = context.appPalette;

    return ListTile(
      onTap: onTap,
      leading: UserAvatar(
        radius: 25,
        userId: otherId,
        backgroundColor: palette.surfaceSunken,
        photoUrl: photoUrl,
        mediaRevision: liveFriend?.profileUpdatedAt,
        displayName: name,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        _localizedConversationPreview(
          conversation,
          currentUserId,
          AppLocalizations.of(context),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, required this.onTap});

  final FriendUser friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return ListTile(
      onTap: onTap,
      leading: Semantics(
        label:
            '${friend.displayName}, ${friend.isOnline ? copy.text('online', 'aktywny') : copy.text('offline', 'nieaktywny')}',
        image: true,
        excludeSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              radius: 25,
              userId: friend.id,
              backgroundColor: palette.surfaceSunken,
              photoUrl: friend.photoUrl,
              mediaRevision: friend.profileUpdatedAt,
              displayName: friend.displayName,
            ),
            if (friend.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: palette.successForeground,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.surfaceRaised, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        friend.displayName,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        friend.isOnline
            ? copy.text('Active now', 'Aktywny teraz')
            : friend.username.trim().isNotEmpty
            ? '@${friend.username.trim()}'
            : copy.text('Offline', 'Nieaktywny'),
        style: TextStyle(color: palette.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
    );
  }
}

class _InviteFriendsTile extends StatelessWidget {
  const _InviteFriendsTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: copy.text(
        'Invite friends to YO Voice',
        'Zaproś znajomych do YO Voice',
      ),
      borderRadius: 16,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.primary.withValues(alpha: .55)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.person_add_alt_1_rounded,
                color: colors.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.text('Invite friends', 'Zaproś znajomych'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    copy.text(
                      'Not on YO Voice yet? Send them an invite.',
                      'Nie korzystają jeszcze z YO Voice? Wyślij im zaproszenie.',
                    ),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11.5,
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

class _NewMessageEmptyState extends StatelessWidget {
  const _NewMessageEmptyState({
    required this.hasSearch,
    required this.hasNoFriendsAtAll,
  });

  final bool hasSearch;
  final bool hasNoFriendsAtAll;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final title = hasSearch
        ? copy.text('No matches', 'Brak wyników')
        : copy.text("You're all caught up", 'Wszystko gotowe');
    final subtitle = hasSearch
        ? copy.text(
            'Try another name or email.',
            'Wpisz inną nazwę lub adres e-mail.',
          )
        : hasNoFriendsAtAll
        ? copy.text(
            'Add friends to start messaging them here.',
            'Dodaj znajomych, aby rozpocząć z nimi rozmowę.',
          )
        : copy.text(
            "You've already started every conversation you can.",
            'Masz już rozpoczęte rozmowy ze wszystkimi znajomymi.',
          );
    final palette = context.appPalette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: palette.borderStrong),
              ),
              child: Icon(
                hasSearch
                    ? Icons.search_off_rounded
                    : Icons.chat_bubble_outline_rounded,
                color: palette.textSecondary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the friends/conversations queries fail. Deliberately mirrors
/// [_NewMessageEmptyState]'s treatment so a failure stays visually integrated
/// with the sheet instead of falling back to Flutter's generic ErrorWidget.
class _NewMessageErrorState extends StatelessWidget {
  const _NewMessageErrorState();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.dangerSurface,
                shape: BoxShape.circle,
                border: Border.all(color: palette.dangerForeground),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                color: palette.dangerForeground,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              copy.text(
                "We couldn't load your people",
                'Nie udało się wczytać kontaktów',
              ),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              copy.text(
                'Check your connection and try again.',
                'Sprawdź połączenie i spróbuj ponownie.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({
    required this.archived,
    required this.hasSearch,
    required this.onNewMessage,
  });

  final bool archived;
  final bool hasSearch;
  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final title = hasSearch
        ? copy.text('No matching chats', 'Brak pasujących czatów')
        : archived
        ? copy.text('No archived chats', 'Brak zarchiwizowanych czatów')
        : copy.text('Your inbox is quiet', 'W skrzynce jest cicho');
    final subtitle = hasSearch
        ? copy.text(
            'Try another name or message.',
            'Wpisz inną nazwę lub treść wiadomości.',
          )
        : archived
        ? copy.text(
            'Archived conversations will appear here.',
            'Tutaj pojawią się zarchiwizowane rozmowy.',
          )
        : copy.text(
            'Start a private conversation with one of your friends.',
            'Rozpocznij prywatną rozmowę ze znajomym.',
          );
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 56).clamp(0, double.infinity),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB82FFF), Color(0xFF6D19E7)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Icon(
                    archived
                        ? Icons.archive_outlined
                        : Icons.chat_bubble_outline_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (!archived && !hasSearch) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onNewMessage,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                    ),
                    icon: const Icon(Icons.edit_square),
                    label: Text(
                      copy.text('New message', 'Nowa wiadomość'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagesError extends StatelessWidget {
  const _MessagesError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 14),
        ),
      ),
    );
  }
}

String _localizedConversationPreview(
  Conversation conversation,
  String currentUserId,
  AppLocalizations copy,
) {
  if (conversation.lastMessage.isEmpty) {
    return copy.text('Start a conversation', 'Rozpocznij rozmowę');
  }
  final prefix = conversation.lastMessageSenderId == currentUserId
      ? copy.text('You: ', 'Ty: ')
      : '';
  final content = switch (conversation.lastMessageType) {
    MessageType.voice => copy.text('Voice message', 'Wiadomość głosowa'),
    MessageType.image => copy.text('Photo', 'Zdjęcie'),
    MessageType.video => copy.text('Video', 'Film'),
    MessageType.text => conversation.lastMessage,
  };
  return '$prefix$content';
}
