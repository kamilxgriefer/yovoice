import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/delete_conversation_dialog.dart';
import 'package:yovoice/shared/widgets/badges/yo_count_badge.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/availability_dot.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
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
    this.firestore,
    this.onFindFriends,
    this.gifService,
    this.gifMessageInvoker,
    super.key,
  });

  /// Optional injection seams, matching the established pattern on
  /// FriendProfileScreen and NotificationsScreen: production passes
  /// nothing and gets the live singletons, tests pass fakes so the
  /// failure paths below can be exercised without a Firebase app.
  final MessageService? messageService;
  final FriendService? friendService;
  final FirebaseAuth? auth;

  /// Handed to the profile preview opened from a conversation avatar, the
  /// same way [ChatScreen] does. Production leaves it null and the preview
  /// resolves the live instance itself.
  final FirebaseFirestore? firestore;

  /// Optional direct-chat GIF seams for local previews and widget tests.
  /// Production leaves both null, so [ChatScreen] keeps its authoritative
  /// Cloud Functions catalog and send path.
  final GifCatalogService? gifService;
  final GifMessageInvoker? gifMessageInvoker;

  /// Opens the shell's retained Friends destination when Chats is one of the
  /// root content slots. Keeping this as a callback lets the app shell switch
  /// its active index instead of pushing a second Friends route over the Hub.
  final VoidCallback? onFindFriends;

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
  final Set<String> _preferenceUpdatesInFlight = <String>{};

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

  bool _beginPreferenceUpdate(String conversationId) {
    if (_preferenceUpdatesInFlight.contains(conversationId)) return false;
    setState(() => _preferenceUpdatesInFlight.add(conversationId));
    return true;
  }

  void _finishPreferenceUpdate(String conversationId) {
    if (!mounted) {
      _preferenceUpdatesInFlight.remove(conversationId);
      return;
    }
    setState(() => _preferenceUpdatesInFlight.remove(conversationId));
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
      if (!_beginPreferenceUpdate(conversation.id)) return;
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
      } finally {
        _finishPreferenceUpdate(conversation.id);
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
          gifService: widget.gifService,
          gifMessageInvoker: widget.gifMessageInvoker,
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
            gifService: widget.gifService,
            gifMessageInvoker: widget.gifMessageInvoker,
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
    await _updateArchivePreference(conversation, archived: true);
  }

  Future<void> _unarchiveConversation(Conversation conversation) async {
    await _updateArchivePreference(conversation, archived: false);
  }

  Future<void> _updateArchivePreference(
    Conversation conversation, {
    required bool archived,
  }) async {
    if (!_beginPreferenceUpdate(conversation.id)) return;
    try {
      if (archived) {
        await _messageService.archiveConversation(conversation.id);
      } else {
        await _messageService.unarchiveConversation(conversation.id);
      }
      if (mounted) {
        _showMessage(
          archived
              ? AppLocalizations.of(context).text(
                  'Conversation archived.',
                  'Rozmowa została zarchiwizowana.',
                )
              : AppLocalizations.of(context).text(
                  'Conversation restored.',
                  'Rozmowa została przywrócona.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          archived
              ? AppLocalizations.of(context).text(
                  'Could not archive this conversation.',
                  'Nie udało się zarchiwizować tej rozmowy.',
                )
              : AppLocalizations.of(context).text(
                  'Could not restore this conversation.',
                  'Nie udało się przywrócić tej rozmowy.',
                ),
          isError: true,
        );
      }
    } finally {
      _finishPreferenceUpdate(conversation.id);
    }
  }

  /// Delete-for-me, confirmed first.
  ///
  /// The confirmation says plainly that only this account's copy goes: a
  /// dialog that let someone believe they were erasing a conversation from
  /// the other person's phone would be a lie, and one that let them believe
  /// the opposite would stop them using the feature at all.
  Future<void> _deleteConversation(Conversation conversation) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final name = conversation.displayNameFor(
      conversation.otherUserId(currentUserId),
    );
    final confirmed = await confirmDeleteConversation(context, name: name);
    if (confirmed != true || !mounted) return;
    try {
      await _messageService.deleteConversationForMe(conversation.id);
      if (!mounted) return;
      _showMessage(
        AppLocalizations.of(
          context,
        ).text('Chat deleted for you.', 'Czat usunięty u Ciebie.'),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        intentionalOrFriendly(
          error,
          fallback: AppLocalizations.of(context).text(
            'Could not delete this chat.',
            'Nie udało się usunąć tego czatu.',
          ),
        ),
        isError: true,
      );
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

  /// The first-run inbox (the §4 logo moment): signed in, loaded, not
  /// searching or browsing the archive, and nothing left in the inbox. It
  /// is exactly the state in which the list below shows `_EmptyMessages`
  /// with the real logo.
  bool _showsFirstRunInbox(
    AsyncSnapshot<List<Conversation>> snapshot,
    String? currentUserId,
  ) {
    if (currentUserId == null || snapshot.hasError || !snapshot.hasData) {
      return false;
    }
    if (_showArchived || _query.isNotEmpty) return false;
    return snapshot.data!.every(
      (conversation) => conversation.isArchivedFor(currentUserId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final canvas = BoxDecoration(gradient: palette.canvasGlow(colors.primary));

    return Scaffold(
      key: const ValueKey('messages-screen'),
      backgroundColor: palette.background,
      // The conversations are read above the canvas: the first-run inbox
      // quiets the page's own brand art (see `_QuietCanvas`), so the canvas
      // has to know what the list below it shows.
      body: StreamBuilder<List<Conversation>>(
        stream: _conversationsStream,
        builder: (context, conversationsSnapshot) => YoPageBackground(
          // Refine-look R1: Pearl takes the quiet watermark path instead of
          // the lounge photo, whose furniture read as grey haze on the paper.
          section: palette.isDark ? YoPageSection.chats : null,
          key: const ValueKey('messages-screen-background'),
          // The Chats radial, promoted unchanged to the palette (R1).
          decoration: canvas,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _QuietCanvas(
                visible: _showsFirstRunInbox(
                  conversationsSnapshot,
                  currentUserId,
                ),
                decoration: canvas,
              ),
              SafeArea(
                bottom: false,
                child: ResponsiveContentFrame(
                  width: ResponsiveContentWidth.list,
                  alignment: ResponsiveContentAlignment.topLeft,
                  child: StreamBuilder<List<FriendUser>>(
                    stream: _friendsStream,
                    builder: (context, friendsSnapshot) {
                      final friends =
                          friendsSnapshot.data ?? const <FriendUser>[];
                      final friendsById = {
                        for (final friend in friends) friend.id: friend,
                      };
                      // Header, search and friend rail can leave the
                      // viewport on a short screen / enlarged text.
                      // Conversations stay lazy rather than being
                      // shrink-wrapped into an eager all-message column.
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
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: _SearchField(
                                controller: _searchController,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: _FriendsRow(
                                friends: friends,
                                onFriendSelected: _startChat,
                                onFindFriends: widget.onFindFriends,
                                onNewMessage: _showNewMessageSheet,
                              ),
                            ),
                          ),
                        ],
                        body: _conversationList(
                          context,
                          conversationsSnapshot,
                          currentUserId: currentUserId,
                          friendsById: friendsById,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The list under the header: loading, error, the empty states or the
  /// lazy conversation rows.
  Widget _conversationList(
    BuildContext context,
    AsyncSnapshot<List<Conversation>> snapshot, {
    required String? currentUserId,
    required Map<String, FriendUser> friendsById,
  }) {
    final palette = context.appPalette;
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
      return _MessagesError(message: _readableError(snapshot.error));
    }

    if (currentUserId == null) {
      return _MessagesError(
        message: AppLocalizations.of(context).text(
          'Sign in to open your chats.',
          'Zaloguj się, aby otworzyć swoje czaty.',
        ),
      );
    }

    final allConversations = snapshot.data ?? const <Conversation>[];
    final conversations = allConversations
        .where((conversation) {
          final archived = conversation.isArchivedFor(currentUserId);

          if (_showArchived != archived) {
            return false;
          }

          if (_query.isEmpty) {
            return true;
          }

          final otherId = conversation.otherUserId(currentUserId);
          final name =
              (friendsById[otherId]?.displayName ??
                      conversation.displayNameFor(otherId))
                  .toLowerCase();
          final preview = conversationPreview(
            conversation,
            currentUserId,
            AppLocalizations.of(context),
          ).toLowerCase();

          return name.contains(_query) || preview.contains(_query);
        })
        .toList(growable: false);

    if (conversations.isEmpty) {
      return _EmptyMessages(
        archived: _showArchived,
        hasSearch: _query.isNotEmpty,
        onNewMessage: _showNewMessageSheet,
      );
    }

    // One scroll view: the group label rides with the rows it
    // names, and the rows stay lazy. The label exists only
    // when there is a row under it (a section title is a
    // promise about content).
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ConversationsGroupLabel(
            label: AppLocalizations.of(context).text('Messages', 'Wiadomości'),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 118),
          sliver: SliverList.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final muted = conversation.isMutedFor(currentUserId);
              final otherUserId = conversation.otherUserId(currentUserId);
              final liveFriend = friendsById[otherUserId];

              return _ConversationTile(
                conversation: conversation,
                currentUserId: currentUserId,
                liveFriend: liveFriend,
                muted: muted,
                preferenceBusy: _preferenceUpdatesInFlight.contains(
                  conversation.id,
                ),
                service: _messageService,
                onTap: () =>
                    _openConversation(conversation, liveFriend: liveFriend),
                onOpenProfile: () => showProfilePreview(
                  context,
                  userId: otherUserId,
                  displayName:
                      liveFriend?.displayName ??
                      conversation.displayNameFor(otherUserId),
                  photoUrl: liveFriend?.photoUrl ?? '',
                  firestore: widget.firestore,
                  auth: _auth,
                  messageService: _messageService,
                ),
                onArchive: () => _archiveConversation(conversation),
                onUnarchive: () => _unarchiveConversation(conversation),
                onToggleMute: () => _toggleMute(conversation, muted),
                onDelete: () => _deleteConversation(conversation),
              );
            },
          ),
        ),
      ],
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

    // Slim title row (ADR-209) with the refine-look finish: the calm
    // `screenTitle` (22 / w700), a bare 44 px archive action and the
    // screen's one lifted CTA, the compose disc. The row stays within 56 px
    // at 1.0 text.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
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
                  style: AppTypography.screenTitle.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
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
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(
            icon: showArchived ? Icons.inbox_rounded : AppIcons.archive,
            tooltip: showArchived
                ? copy.text('Show inbox', 'Pokaż skrzynkę odbiorczą')
                : copy.text(
                    'Show archived conversations',
                    'Pokaż zarchiwizowane rozmowy',
                  ),
            onTap: onToggleArchived,
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            key: const ValueKey('messages-compose'),
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

class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  /// The compose disc: 40 px visual inside the 44 px target (R6).
  static const double discSize = 40;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    // 44 px targets. Only the primary action (New message) carries the
    // screen's one CTA lift: the R6 icon disc in the logo's gradient with a
    // white glyph. The archive action stays a bare glyph with no card.
    final Widget face = widget.highlighted
        ? YoPressFeedback(
            scale: YoPressFeedback.disc,
            child: YoGradientDisc(
              size: _HeaderButton.discSize,
              icon: widget.icon,
              glyphSize: 20,
              emphasis: YoDiscEmphasis.lift,
              hovered: _hovered,
            ),
          )
        : SizedBox(
            width: 44,
            height: 44,
            child: Icon(widget.icon, color: palette.textPrimary, size: 22),
          );
    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: AccessibleTapRegion(
        semanticLabel: widget.tooltip,
        onTap: widget.onTap,
        circular: widget.highlighted,
        borderRadius: 12,
        onHover: widget.highlighted
            ? (hovered) {
                if (_hovered != hovered) setState(() => _hovered = hovered);
              }
            : null,
        child: ExcludeSemantics(child: face),
      ),
    );
  }
}

/// The Chats search pill (refine-look R9): the shared `YoSearchField` — a
/// 44 px stadium with its own magnifier, clear action and focus ring.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return YoSearchField(controller: controller);
  }
}

class _FriendsRow extends StatelessWidget {
  const _FriendsRow({
    required this.friends,
    required this.onFriendSelected,
    required this.onFindFriends,
    required this.onNewMessage,
  });

  final List<FriendUser> friends;
  final ValueChanged<FriendUser> onFriendSelected;
  final VoidCallback? onFindFriends;
  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final labelScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    // Large text: a label wraps to a second line and its tile widens with
    // the reader's text (up to a cap), so "Dodaj znajomego" or a first name
    // and surname read in full instead of as a clipped stub. At 1.0 the
    // rail is unchanged: one line, 108 px action tiles, 76 px friends.
    final labelLines = labelScale > _FriendStory.wrapScale ? 2 : 1;
    final actionWidth =
        _FriendStory.actionWidth *
        labelScale.clamp(1.0, _FriendStory.actionGrowthCap);
    final friendWidth =
        _FriendStory.friendWidth *
        labelScale.clamp(1.0, _FriendStory.friendGrowthCap);

    return SizedBox(
      height: _FriendStory.railHeight(labelScale, labelLines),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _FriendStory(
            key: const ValueKey('messages-add-friend'),
            label: copy.text('Add friend', 'Dodaj znajomego'),
            semanticLabel: copy.text('Add friend', 'Dodaj znajomego'),
            icon: AppIcons.addFriend,
            onTap: onFindFriends,
            width: actionWidth,
            labelLines: labelLines,
          ),
          _FriendStory(
            key: const ValueKey('messages-new-message'),
            label: copy.text('New message', 'Nowa wiadomość'),
            semanticLabel: copy.text('New message', 'Nowa wiadomość'),
            icon: AppIcons.compose,
            onTap: onNewMessage,
            width: actionWidth,
            labelLines: labelLines,
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
                  width: friendWidth,
                  labelLines: labelLines,
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
    this.width = friendWidth,
    this.labelLines = 1,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;
  final FriendUser? friend;
  final IconData? icon;
  final double width;

  /// 1 at rest; 2 once the reader's text is larger than [wrapScale].
  final int labelLines;

  /// The tile widths at 1.0 text.
  static const double actionWidth = 108;
  static const double friendWidth = 76;

  /// How far a tile widens with the text scale: an action tile to 1.3×
  /// (140 px at 200 %), a friend to 1.9× (144 px), which holds two lines of
  /// a Polish first name and surname at 200 %.
  static const double actionGrowthCap = 1.3;
  static const double friendGrowthCap = 1.9;

  /// Above this text scale the label may take a second line.
  static const double wrapScale = 1.15;

  static const double _labelSize = 11;
  static const double _labelHeight = 1.2;
  static const double _labelGap = 6;

  /// The breathing room under the label (focus ring and press scale).
  static const double _railSlack = 14.8;

  /// The rail's height for a text scale and label line count: 92 px at 1.0.
  static double railHeight(double labelScale, int labelLines) =>
      _markSize +
      _labelGap +
      labelLines * _labelSize * _labelHeight * labelScale +
      _railSlack;

  @override
  Widget build(BuildContext context) {
    final user = friend;
    final hasPhoto = user?.photoUrl?.trim().isNotEmpty == true;
    final palette = context.appPalette;
    // The one presence mapping (ADR-150): offline wins, `away` reads as be
    // right back, `busy` as do not disturb. Only a real friend carries it;
    // the two action tiles have no presence at all.
    final status = user == null
        ? null
        : PeopleStatus.fromPresence(
            isOnline: user.isOnline,
            availability: user.availability,
          );

    final highContrast = MediaQuery.highContrastOf(context);
    final action = icon;
    // Refine-look §8.3: the two action tiles are R7-accent ghost discs (the
    // one voice-of-the-app accent, never a filled violet coin); a friend is
    // the brand-finished avatar inside a hairline band. The geometry is
    // unchanged: a 58 px mark (2 px band around a radius-27 avatar).
    final Widget mark = action != null
        ? Container(
            width: _markSize,
            height: _markSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highContrast
                  ? palette.surface
                  : palette.interactiveForeground.withValues(alpha: .06),
              border: Border.all(
                color: highContrast
                    ? palette.borderStrong
                    : palette.interactiveForeground.withValues(alpha: .55),
                width: 1.5,
              ),
            ),
            child: Icon(action, color: palette.interactiveForeground, size: 24),
          )
        : Container(
            padding: const EdgeInsets.all(2),
            // A quiet hairline band, never a story gradient and never a
            // status ring: this rail carries no Moments state, and presence
            // is already the dot below. One presence mark per avatar
            // (ADR-209, presence dot).
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highContrast ? palette.borderStrong : palette.hairline,
            ),
            child: UserAvatar(
              radius: 27,
              userId: user?.id,
              photoUrl: hasPhoto ? user!.photoUrl : null,
              mediaRevision: user?.profileUpdatedAt,
              displayName: user?.displayName,
              finish: UserAvatarFinish.brand,
            ),
          );

    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      borderRadius: 18,
      minimumSize: const Size(48, 48),
      child: ExcludeSemantics(
        child: YoPressFeedback(
          scale: YoPressFeedback.tile,
          enabled: onTap != null,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    mark,
                    if (status != null && status != PeopleStatus.away)
                      PositionedDirectional(
                        end: 2,
                        bottom: 2,
                        child: AvailabilityDot(
                          status: status,
                          size: 15,
                          borderColor: palette.background,
                          borderWidth: 2.5,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: _labelGap),
                Text(
                  label,
                  maxLines: labelLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: action != null
                        ? palette.interactiveForeground
                        : palette.textSecondary,
                    fontSize: _labelSize,
                    height: _labelHeight,
                    fontWeight: action != null
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rail's mark: a radius-27 avatar in its 2 px band.
  static const double _markSize = 58;
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.liveFriend,
    required this.muted,
    required this.preferenceBusy,
    required this.service,
    required this.onTap,
    required this.onOpenProfile,
    required this.onArchive,
    required this.onUnarchive,
    required this.onToggleMute,
    required this.onDelete,
  });

  final Conversation conversation;
  final String currentUserId;
  final FriendUser? liveFriend;
  final bool muted;
  final bool preferenceBusy;

  /// The screen's own service, rather than one built inside `build` —
  /// see [_ConversationAvatar].
  final MessageService service;
  final VoidCallback onTap;

  /// Opens the profile preview for the other participant. See
  /// [_ConversationAvatar.onOpenProfile].
  final VoidCallback onOpenProfile;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;

  bool get _archived => conversation.isArchivedFor(currentUserId);

  /// The leading glyph of a voice, photo or video preview (refine-look
  /// §8.3); null for text, GIFs and an empty thread.
  IconData? get _previewGlyph {
    if (conversation.lastMessage.isEmpty) return null;
    return switch (conversation.lastMessageType) {
      MessageType.voice => Icons.mic_rounded,
      MessageType.image => Icons.photo_outlined,
      MessageType.video => Icons.videocam_outlined,
      MessageType.text || MessageType.gif => null,
    };
  }

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
    final preview = conversationPreview(
      conversation,
      currentUserId,
      AppLocalizations.of(context),
    );
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final isUnread = unread > 0;
    // Refine-look §8.3: one layer in both states — no unread slab, no edge.
    // Unread is carried by weight AND the count, never by colour alone: the
    // name at w700 (w600 read), the preview in `textPrimary` at w500
    // (`textSecondary` w400 read), the time in `focus` w700 and the gradient
    // count. At 1.0 text the row is exactly 68 px: the 58 px avatar plus
    // 5 px above and below.
    final nameStyle =
        (isUnread ? AppTypography.rowTitleUnread : AppTypography.rowTitle)
            .copyWith(color: palette.textPrimary);
    final previewStyle =
        (isUnread ? AppTypography.rowPreviewUnread : AppTypography.rowPreview)
            .copyWith(
              color: isUnread ? palette.textPrimary : palette.textSecondary,
            );
    final timeStyle = TextStyle(
      color: isUnread ? palette.focus : palette.textTertiary,
      fontSize: 11,
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
    );
    final time = _relativeTime(context, conversation.lastActivityAt, copy);
    final glyph = _previewGlyph;
    final glyphColor = glyph == Icons.mic_rounded
        ? palette.audioAccent
        : previewStyle.color;
    final avatar = _ConversationAvatar(
      name: name,
      photoUrl: photoUrl,
      userId: otherUserId,
      mediaRevision: friend?.profileUpdatedAt,
      service: service,
      onOpenProfile: onOpenProfile,
    );
    final badgeKey = ValueKey('conversation-unread-badge-${conversation.id}');

    return _ConversationRowSurface(
      rowKey: ValueKey('conversation-row-${conversation.id}'),
      onTap: preferenceBusy ? null : onTap,
      onLongPress: preferenceBusy ? null : () => _showActions(context),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: enlargedText ? 10 : 5,
        ),
        child: enlargedText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(time, style: timeStyle),
                            if (muted)
                              Icon(
                                Icons.notifications_off_outlined,
                                color: palette.textSecondary,
                                size: 18,
                              ),
                            if (isUnread)
                              // A Wrap hands its children the full run
                              // width; keep the count to its own content.
                              IntrinsicWidth(
                                child: _UnreadBadge(
                                  key: badgeKey,
                                  count: unread,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _actionsControl(context, name),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    name,
                    key: ValueKey(
                      'conversation-expanded-name-${conversation.id}',
                    ),
                    style: nameStyle,
                  ),
                  const SizedBox(height: 5),
                  _PreviewLine(
                    glyph: glyph,
                    glyphColor: glyphColor,
                    text: preview,
                    style: previewStyle,
                    maxLines: 3,
                  ),
                ],
              )
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
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
                                style: nameStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(time, style: timeStyle),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _PreviewLine(
                                glyph: glyph,
                                glyphColor: glyphColor,
                                text: preview,
                                style: previewStyle,
                                maxLines: 1,
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
                            if (isUnread) ...[
                              const SizedBox(width: 9),
                              _UnreadBadge(key: badgeKey, count: unread),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _actionsControl(context, name),
                ],
              ),
      ),
    );
  }

  Widget _actionsControl(BuildContext context, String name) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    if (!preferenceBusy) {
      // Always visible, never hover-only: a quiet 20 px glyph on a 48 px
      // target.
      return IconButton(
        onPressed: () => _showActions(context),
        tooltip: copy.template(
          'Conversation actions for {name}',
          'Opcje rozmowy z {name}',
          values: {'name': name},
        ),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(Icons.more_horiz_rounded, color: palette.textTertiary),
      );
    }

    final label = _archived
        ? copy.text('Restoring conversation', 'Przywracanie rozmowy z archiwum')
        : copy.text('Archiving conversation', 'Archiwizowanie rozmowy');
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      key: ValueKey('conversation-preference-busy-${conversation.id}'),
      container: true,
      liveRegion: true,
      button: true,
      enabled: false,
      label: label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: reduceMotion
                  ? Icon(
                      Icons.hourglass_top_rounded,
                      key: ValueKey(
                        'conversation-preference-static-${conversation.id}',
                      ),
                      color: palette.interactiveForeground,
                      size: 20,
                    )
                  : SizedBox.square(
                      key: ValueKey(
                        'conversation-preference-progress-${conversation.id}',
                      ),
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.interactiveForeground,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    if (preferenceBusy) return;
    var preferenceSubmitted = false;
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
            if (preferenceSubmitted) return;
            preferenceSubmitted = true;
            Navigator.pop(sheetContext);
            if (_archived) {
              onUnarchive();
            } else {
              onArchive();
            }
          },
          onDelete: () {
            Navigator.pop(sheetContext);
            onDelete();
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

/// The "WIADOMOŚCI" group label above the conversation rows: the Slim group
/// label (11 px, w700, uppercase, .08em tracking) drawn from the existing
/// `Messages` / `Wiadomości` copy. The capitals are presentation only, so a
/// screen reader hears the word as a heading, not letter by letter.
class _ConversationsGroupLabel extends StatelessWidget {
  const _ConversationsGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Padding(
      key: const ValueKey('messages-group-label'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Semantics(
        header: true,
        label: label,
        child: ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 11 * .08,
            ),
          ),
        ),
      ),
    );
  }
}

/// The unread count: the one gradient [YoCountBadge] (refine-look R11). The
/// badge itself is silent, so this node says the count in words.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);

    return Semantics(
      label: copy.unreadMessages(count),
      child: ExcludeSemantics(child: YoCountBadge(count: count)),
    );
  }
}

/// A conversation row's one layer (refine-look R16): no fill at rest; a
/// hover wash (textPrimary @ .04 Dark / interactiveForeground @ .05 Pearl),
/// a pressed wash (interactiveForeground @ .10) and a 2 px focus ring at
/// radius 16, painted over the row so focus never moves a pixel.
class _ConversationRowSurface extends StatefulWidget {
  const _ConversationRowSurface({
    required this.rowKey,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final Key rowKey;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_ConversationRowSurface> createState() =>
      _ConversationRowSurfaceState();
}

class _ConversationRowSurfaceState extends State<_ConversationRowSurface> {
  /// The row's own node. The ring follows its PRIMARY focus: the InkWell's
  /// `onFocusChange` reports focus-within, so the row's "…" button taking
  /// focus would otherwise light a second ring around the whole row
  /// (as `YoChannelRow` does it).
  final FocusNode _focusNode = FocusNode(debugLabel: 'ConversationRow');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    final focused = _focusNode.hasPrimaryFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  /// R2 / R16: the pressed wash is the feedback. No ink ripple on iOS,
  /// macOS, web or desktop; Android keeps its sparkle (as `YoCard` does).
  static InteractiveInkFeatureFactory get splashFactory =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? InkSparkle.splashFactory
      : NoSplash.splashFactory;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    const radius = AppRadius.tile;

    return AnimatedContainer(
      key: widget.rowKey,
      duration: AppMotion.resolve(context, AppMotion.standard),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: radius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: _focused ? palette.focus : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: _focusNode,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: radius,
          splashFactory: splashFactory,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return palette.interactiveForeground.withValues(alpha: .10);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.isDark
                  ? palette.textPrimary.withValues(alpha: .04)
                  : palette.interactiveForeground.withValues(alpha: .05);
            }
            // Focus is the ring above, not a second wash.
            return Colors.transparent;
          }),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A preview line with an optional leading type glyph (15 px at 100 %). The
/// glyph follows the reader's text size and sits centred on the first line;
/// it is decoration (`ExcludeSemantics`) and the preview string is unchanged.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.glyph,
    required this.glyphColor,
    required this.text,
    required this.style,
    required this.maxLines,
  });

  static const double glyphSize = 15;

  final IconData? glyph;
  final Color? glyphColor;
  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final icon = glyph;
    if (icon == null) return label;
    final scaler = MediaQuery.textScalerOf(context);
    final size = scaler.scale(glyphSize);
    final lineHeight =
        scaler.scale(style.fontSize ?? 13) * (style.height ?? 1.35);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: ((lineHeight - size) / 2).clamp(0, double.infinity),
          ),
          child: ExcludeSemantics(
            child: Icon(icon, size: size, color: glyphColor),
          ),
        ),
        SizedBox(width: scaler.scale(4)),
        Flexible(child: label),
      ],
    );
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
    required this.onOpenProfile,
  });

  final String name;
  final String photoUrl;
  final String userId;
  final Object? mediaRevision;
  final MessageService service;

  /// The avatar is a door to the person, not a second door to the thread.
  /// Tapping the row opens the conversation; tapping the photo opens the
  /// canonical profile preview, which is where the full-size photo lives.
  final VoidCallback onOpenProfile;

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
        // The dot draws the same PeopleStatus the chat header prints, so a
        // "do not disturb" friend is not shown as plainly online here.
        final status = PeopleStatus.fromPresence(
          isOnline: online,
          availability: snapshot.data?.availability,
        );
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);

        final openProfileLabel = copy.template(
          'Open {name} profile',
          'Otwórz profil użytkownika {name}',
          values: {'name': name},
        );
        final presenceLabel = online
            ? copy.text('online', 'aktywny')
            : copy.text('offline', 'nieaktywny');

        // The hover hint is mounted here rather than through
        // AccessibleTapRegion's `tooltip`, which would use Tooltip's default
        // long-press trigger. That recognizer sits below the row's own
        // InkWell and would win the arena, costing the row its long-press
        // mute/archive/delete sheet on exactly the 58 px the photo covers.
        // Manual mode registers no recognizer; pointer hover is unaffected.
        return Tooltip(
          message: openProfileLabel,
          triggerMode: TooltipTriggerMode.manual,
          excludeFromSemantics: true,
          child: AccessibleTapRegion(
            onTap: widget.onOpenProfile,
            circular: true,
            // The avatar already occupies 58 px, so promoting it to its own
            // target changes nothing about the row's layout at any width.
            minimumSize: const Size(58, 58),
            semanticLabel: '$openProfileLabel, $presenceLabel',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Refine-look R10: the one brand letter fill (the near-black
                // Dark hole and the Pearl violet coin are both gone).
                UserAvatar(
                  radius: 29,
                  userId: widget.userId,
                  photoUrl: photoUrl,
                  mediaRevision: widget.mediaRevision,
                  displayName: name,
                  finish: UserAvatarFinish.brand,
                ),
                if (status != PeopleStatus.away)
                  PositionedDirectional(
                    end: 1,
                    bottom: 1,
                    child: AvailabilityDot(
                      status: status,
                      size: 16,
                      borderColor: palette.background,
                      borderWidth: 2.5,
                    ),
                  ),
              ],
            ),
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
    required this.onDelete,
  });

  final bool muted;

  /// An archived thread offers "Unarchive" — the sheet used to say
  /// "Archive" even inside the Archived view, so testers saw no way back.
  final bool archived;
  final VoidCallback onMute;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: _sheetEdge(context),
      child: Material(
        color: palette.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: _sheetRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            18 + MediaQuery.paddingOf(context).bottom,
          ),
          // Scrollable since Delete joined Mute and Archive: three rows, one of
          // them two-line, no longer fit a bottom sheet's default height at an
          // enlarged text scale.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.text(
                    'conversation actions',
                    'opcje rozmowy',
                  ),
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
                    archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    color: palette.textPrimary,
                  ),
                  title: Text(
                    archived
                        ? copy.text(
                            'Unarchive conversation',
                            'Przywróć z archiwum',
                          )
                        : copy.text(
                            'Archive conversation',
                            'Archiwizuj rozmowę',
                          ),
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ),
                // Last, and in the error colour: archiving is reversible and this
                // is not.
                ListTile(
                  key: const ValueKey('conversation-delete-action'),
                  onTap: onDelete,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: colors.error,
                  ),
                  title: Text(
                    copy.text('Delete chat', 'Usuń czat'),
                    style: TextStyle(color: colors.error),
                  ),
                  subtitle: Text(
                    copy.text(
                      'Removes it for you only',
                      'Usuwa tylko u Ciebie',
                    ),
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet's radius (refine-look §3.0, `AppRadius.xl`).
const BorderRadius _sheetRadius = BorderRadius.vertical(
  top: Radius.circular(28),
);

/// A bottom sheet's hairline top edge (R16), painted over the sheet;
/// `borderStrong` under high contrast.
BoxDecoration _sheetEdge(BuildContext context) {
  final palette = context.appPalette;
  return BoxDecoration(
    borderRadius: _sheetRadius,
    border: Border(
      top: BorderSide(
        color: MediaQuery.highContrastOf(context)
            ? palette.borderStrong
            : palette.hairline,
      ),
    ),
  );
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
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: _sheetEdge(context),
          child: Material(
            key: const ValueKey('new-message-sheet-surface'),
            color: palette.surfaceRaised,
            clipBehavior: Clip.antiAlias,
            borderRadius: _sheetRadius,
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
                      style: AppTypography.screenTitle.copyWith(
                        color: palette.textPrimary,
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
                                        !c.isArchivedFor(
                                          widget.currentUserId,
                                        ) &&
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
                                ..sort(Conversation.compareByRecentActivity);
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

                          if (filteredRecent.isEmpty &&
                              filteredFriends.isEmpty) {
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
                                    onTap: () =>
                                        widget.onFriendSelected(friend),
                                  ),
                              ],
                              const SizedBox(height: 10),
                              _InviteFriendsTile(
                                onTap: () => SharePlus.instance.share(
                                  ShareParams(
                                    text: copy.text(
                                      'Join me on YO Voice — the app for voice servers, Moments and real conversations: https://yovoice.app/download',
                                      'Dołącz do mnie w YO Voice — aplikacji z serwerami głosowymi, Momentami i prawdziwymi rozmowami: https://yovoice.app/download',
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
          fontWeight: FontWeight.w700,
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
    // The name is the row's label: at large text it may take a second line
    // (as the friend tiles below already do) rather than end in a stub.
    final nameLines =
        MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3 ? 2 : 1;

    return ListTile(
      onTap: onTap,
      leading: UserAvatar(
        radius: 25,
        userId: otherId,
        photoUrl: photoUrl,
        mediaRevision: liveFriend?.profileUpdatedAt,
        displayName: name,
        finish: UserAvatarFinish.brand,
      ),
      title: Text(
        name,
        maxLines: nameLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        conversationPreview(
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
              photoUrl: friend.photoUrl,
              mediaRevision: friend.profileUpdatedAt,
              displayName: friend.displayName,
              finish: UserAvatarFinish.brand,
            ),
            if (friend.isOnline)
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: AvailabilityDot(
                  status: PeopleStatus.online,
                  size: 14,
                  borderColor: palette.surfaceRaised,
                  borderWidth: 2.5,
                ),
              ),
          ],
        ),
      ),
      title: Text(
        friend.displayName,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
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
              // The R16 glyph box: the scheme's container pair, radius 12.
              decoration: AppFinish.glyphBox(
                colors,
                highContrast: MediaQuery.highContrastOf(context),
              ),
              child: Icon(
                AppIcons.addFriend,
                color: palette.interactiveForeground,
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
                      fontWeight: FontWeight.w700,
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
            _QuietGlyphDisc(
              icon: hasSearch ? Icons.search_off_rounded : AppIcons.chat,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w700,
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

  /// The first-run logo: 88 px, 72 on a short viewport (refine-look §4).
  static const double logoSize = 88;
  static const double compactLogoSize = 72;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final inbox = !archived && !hasSearch;
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
                // The first-run invitation carries the real logo (bloom in
                // Dark, a contact shadow in Pearl); the archived and search
                // states keep a quiet topic glyph.
                if (inbox)
                  _LogoEntrance(
                    child: YoBrandMark(
                      key: const ValueKey('messages-empty-logo'),
                      size: MediaQuery.sizeOf(context).height < 560
                          ? compactLogoSize
                          : logoSize,
                    ),
                  )
                else
                  _QuietGlyphDisc(
                    icon: archived
                        ? AppIcons.archive
                        : Icons.search_off_rounded,
                  ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
                if (inbox) ...[
                  const SizedBox(height: 20),
                  // The labelled gradient without a second lift: the
                  // header's compose disc is this screen's one CTA lift.
                  YoGradientFilledButton(
                    key: const ValueKey('messages-empty-new-message'),
                    onPressed: onNewMessage,
                    emphasis: YoActionEmphasis.flat,
                    minimumSize: const Size(64, 48),
                    icon: const Icon(Icons.edit_square),
                    child: Text(copy.text('New message', 'Nowa wiadomość')),
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

/// The first-run logo's entrance: a fade with a .96 → 1 scale over
/// [AppMotion.entrance], played once, when the invitation first appears.
/// Where decorative motion is off at that moment the logo starts at rest, and
/// motion switching off mid-entrance finishes it at rest.
///
/// The same two transitions stay mounted in every state, so a return to the
/// Chats tab, a covering route popping, or Reduce Motion / accessible
/// navigation / `TickerMode` changing never swaps the subtree and never
/// replays the entrance (spec §2.7: motion starts only from a real event).
class _LogoEntrance extends StatefulWidget {
  const _LogoEntrance({required this.child});

  final Widget child;

  @override
  State<_LogoEntrance> createState() => _LogoEntranceState();
}

class _LogoEntranceState extends State<_LogoEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.entrance,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.entranceCurve,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: .96,
    end: 1,
  ).animate(_progress);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = AppMotion.decorative(context);
    if (!_started) {
      _started = true;
      if (animate) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    } else if (!animate && _controller.isAnimating) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: const ValueKey('messages-empty-logo-entrance'),
      opacity: _progress,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// The first-run inbox's quiet canvas (spec §4, R17). While the real logo is
/// on screen it is the page's only YO: the Dark lounge's neon wall sign sits
/// right above it and Pearl's watermark ring right behind it, so the canvas
/// drops to the bare radial for as long as the invitation shows.
///
/// The shared page background has no switch for its art, so this paints the
/// same radial over it. It fades rather than being inserted or removed, so
/// the list above never loses state, and it is omitted under high contrast,
/// where the page draws no art anyway.
class _QuietCanvas extends StatelessWidget {
  const _QuietCanvas({required this.visible, required this.decoration});

  final bool visible;
  final Decoration decoration;

  @override
  Widget build(BuildContext context) {
    final shown = visible && !MediaQuery.highContrastOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('messages-quiet-canvas'),
        opacity: shown ? 1 : 0,
        duration: AppMotion.decorative(context)
            ? AppMotion.entrance
            : Duration.zero,
        curve: AppMotion.entranceCurve,
        child: DecoratedBox(decoration: decoration),
      ),
    );
  }
}

/// A quiet 64 px topic disc for the archived, search and sheet empty states:
/// the block fill with its hairline and a `textSecondary` glyph.
class _QuietGlyphDisc extends StatelessWidget {
  const _QuietGlyphDisc({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highContrast ? palette.surface : null,
        gradient: highContrast ? null : palette.blockGradient,
        border: Border.all(
          color: highContrast ? palette.borderStrong : palette.hairline,
        ),
        boxShadow: AppFinish.blockShadows(palette, highContrast: highContrast),
      ),
      child: Icon(icon, color: palette.textSecondary, size: 28),
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
