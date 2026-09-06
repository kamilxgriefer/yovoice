import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/friend_request_error_copy.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_suggestions_section.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

enum _FriendsFilter { all, online, requests }

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    this.isRootTab = false,
    this.showRequestsInitially = false,
    this.friendService,
    this.messageService,
    this.socialGraphService,
    this.profileMediaService,
    this.firestore,
    this.auth,
    super.key,
  });

  /// True when hosted as the shell's Friends tab — there is nothing to
  /// pop back to, so the header hides its back button.
  final bool isRootTab;
  final bool showRequestsInitially;
  final FriendService? friendService;
  final MessageService? messageService;

  /// Server-computed friend suggestions ("People you may know"). Friend
  /// lists are private in firestore.rules, so this must stay a callable —
  /// see SocialGraphService. Injected the same way as the services above so
  /// tests can drive the rail without a Firebase app.
  final SocialGraphService? socialGraphService;
  final ProfileMediaService? profileMediaService;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final FriendService _friendService =
      widget.friendService ?? FriendService(firestore: _firestore, auth: _auth);
  late final MessageService? _ownedMessageService =
      widget.messageService == null &&
          (widget.firestore != null || widget.auth != null)
      ? MessageService(firestore: _firestore, auth: _auth)
      : null;
  late final MessageService _messageService =
      widget.messageService ?? _ownedMessageService ?? MessageService.live;
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();
  late final ProfileMediaService? _profileMediaService =
      widget.profileMediaService ??
      (widget.auth != null ? ProfileMediaService(auth: _auth) : null);
  final TextEditingController _searchController = TextEditingController();

  /// Bounded on purpose: the callable is rate limited and the rail only ever
  /// shows a handful of people.
  static const int _suggestionLimit = 8;

  /// Null while a foreground load is running; a list (possibly empty) once
  /// the callable answered. An empty list renders nothing at all.
  List<SuggestedFriend>? _suggestions;
  Object? _suggestionsError;
  int _suggestionsRequest = 0;
  final Map<String, FriendRelationshipStatus> _suggestionStatuses = {};
  final Set<String> _processingSuggestionIds = <String>{};

  /// People this session already sent a request to. The server drops them
  /// from later responses, but its 30 s discovery cache can still replay a
  /// ranked entry, so they are filtered out of every reload too.
  final Set<String> _sentSuggestionIds = <String>{};

  final Set<String> _processingRequestIds = <String>{};
  late Stream<int> _requestCountStream;
  bool _navigationInFlight = false;

  /// Friend whose conversation is being opened right now — drives the
  /// bubble's busy state on that one row.
  String? _openingChatFriendId;
  bool _requestFanoutFailed = false;
  String _query = '';
  _FriendsFilter _filter = _FriendsFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.showRequestsInitially) {
      _filter = _FriendsFilter.requests;
    }
    _requestCountStream = _friendService.watchPendingFriendRequestCount();
    _searchController.addListener(_handleSearchChanged);
    // The callable is quota limited (a couple of calls a minute), so a
    // deep link straight into Requests must not spend one on a rail it
    // will not render. _selectFilter picks it up when All is opened.
    if (_filter == _FriendsFilter.all) unawaited(_loadSuggestions());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    unawaited(_ownedMessageService?.dispose());
    super.dispose();
  }

  void _handleSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();
    if (value == _query) return;
    setState(() => _query = value);
  }

  void _selectFilter(_FriendsFilter filter) {
    if (filter == _FriendsFilter.all && _suggestionsRequest == 0) {
      unawaited(_loadSuggestions());
    }
    // A terminal request-source failure evicts its shared generation. Keep the
    // count stream stable during ordinary rebuilds, but explicitly reacquire a
    // replacement when the user next interacts with the filters.
    if (_requestFanoutFailed) {
      _requestCountStream = _friendService.watchPendingFriendRequestCount();
      _requestFanoutFailed = false;
    }
    if (_filter == filter) {
      setState(() {});
      return;
    }
    setState(() => _filter = filter);
  }

  Future<void> _runNavigation(Future<void> Function() navigate) async {
    if (_navigationInFlight) return;
    _navigationInFlight = true;
    try {
      await navigate();
    } finally {
      _navigationInFlight = false;
    }
  }

  Future<void> _openAddFriend() => _runNavigation(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AddFriendScreen(
          friendService: _friendService,
          socialGraphService: _socialGraphService,
          profileMediaService: _profileMediaService,
        ),
      ),
    ),
  );

  Future<void> _openBlockedUsers() => _runNavigation(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BlockedUsersScreen(
          friendService: _friendService,
          profileMediaService: _profileMediaService,
        ),
      ),
    ),
  );

  Future<void> _openProfile(FriendUser friend) => _runNavigation(
    () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(
          friend: friend,
          friendService: _friendService,
          messageService: _messageService,
          profileMediaService: _profileMediaService,
          firestore: _firestore,
          auth: _auth,
        ),
      ),
    ),
  );

  Future<void> _startChat(FriendUser friend) => _runNavigation(() async {
    // The bubble shows its own progress and disables itself while the
    // server opens the conversation; without it the first tap looked
    // ignored and the guarded repeat taps were silently dropped.
    setState(() => _openingChatFriendId = friend.id);
    try {
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      );

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: friend.email,
            otherPhotoUrl: friend.photoUrl ?? '',
            otherProfileUpdatedAt: friend.profileUpdatedAt,
            messageService: _messageService,
            profileMediaService: _profileMediaService,
            firestore: _firestore,
            auth: _auth,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // `openOrCreateConversation` no longer swallows a refusal from
      // `openDirectConversation` (ADR-062), so a blocked pair, a
      // communication mute or a rate limit arrives here as a real
      // FirebaseFunctionsException. Raw exception text must never be what
      // the user reads.
      final copy = AppLocalizations.of(context);
      final timedOut =
          error is TimeoutException ||
          (error is FirebaseFunctionsException &&
              error.code == 'deadline-exceeded');
      _showMessage(
        timedOut
            ? copy.text(
                'Opening this conversation is taking too long. Try again.',
                'Otwieranie rozmowy trwa zbyt długo. Spróbuj ponownie.',
              )
            : copy.isPolish
            ? 'Nie udało się otworzyć rozmowy.'
            : intentionalOrFriendly(
                error,
                fallback: 'Could not open this conversation.',
              ),
        isError: true,
      );
    } finally {
      if (mounted && _openingChatFriendId == friend.id) {
        setState(() => _openingChatFriendId = null);
      }
    }
  });

  /// Loads "People you may know".
  ///
  /// [background] is used after a successful send: the rail keeps rendering
  /// what is already on screen, and a failed or rate-limited refresh leaves
  /// the list and the "Sent" confirmation alone instead of replacing a
  /// working section with an error.
  Future<void> _loadSuggestions({bool background = false}) async {
    final request = ++_suggestionsRequest;
    // Guarded so the first load — kicked off from initState, when the state
    // already reads as "loading" — never has to call setState.
    if (!background && (_suggestions != null || _suggestionsError != null)) {
      setState(() {
        _suggestions = null;
        _suggestionsError = null;
      });
    }
    try {
      final loaded = await _socialGraphService.getFriendSuggestions(
        limit: _suggestionLimit,
      );
      if (!mounted || request != _suggestionsRequest) return;
      setState(() {
        _suggestions = loaded
            .where((suggestion) => !_sentSuggestionIds.contains(suggestion.uid))
            .toList(growable: false);
        _suggestionsError = null;
      });
    } catch (error) {
      if (!mounted || request != _suggestionsRequest || background) return;
      setState(() {
        _suggestions = null;
        _suggestionsError = error;
      });
    }
  }

  AsyncSnapshot<List<SuggestedFriend>> get _suggestionsSnapshot {
    final error = _suggestionsError;
    if (error != null) {
      return AsyncSnapshot<List<SuggestedFriend>>.withError(
        ConnectionState.done,
        error,
      );
    }
    final loaded = _suggestions;
    if (loaded == null) {
      return const AsyncSnapshot<List<SuggestedFriend>>.waiting();
    }
    return AsyncSnapshot<List<SuggestedFriend>>.withData(
      ConnectionState.done,
      loaded,
    );
  }

  /// Same FriendService path, optimistic state and error copy as the Add
  /// friends screen's suggestion list, so the two rails behave identically.
  Future<void> _addSuggestion(SuggestedFriend suggestion) async {
    if (_processingSuggestionIds.contains(suggestion.uid)) return;
    final previous = _suggestionStatuses[suggestion.uid];
    setState(() {
      _processingSuggestionIds.add(suggestion.uid);
      _suggestionStatuses[suggestion.uid] =
          FriendRelationshipStatus.requestSent;
    });
    try {
      final relationship = await _friendService.sendFriendRequest(
        FriendUser(
          id: suggestion.uid,
          displayName: suggestion.displayName,
          email: '',
          photoUrl: suggestion.photoUrl,
          isOnline: false,
          lastSeen: null,
          profileUpdatedAt: suggestion.profileUpdatedAt,
        ),
      );
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      setState(() {
        _suggestionStatuses[suggestion.uid] = relationship;
        _sentSuggestionIds.add(suggestion.uid);
      });
      _showMessage(
        relationship == FriendRelationshipStatus.friends
            ? copy.template(
                'You and {name} are now friends.',
                'Ty i {name} jesteście teraz znajomymi.',
                values: <String, Object>{'name': suggestion.displayName},
              )
            : copy.template(
                'Friend request sent to {name}.',
                'Wysłano zaproszenie do {name}.',
                values: <String, Object>{'name': suggestion.displayName},
              ),
      );
      unawaited(_loadSuggestions(background: true));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _suggestionStatuses.remove(suggestion.uid);
        } else {
          _suggestionStatuses[suggestion.uid] = previous;
        }
      });
      // Same mapping as the Add friends screen: a refusal is named, and an
      // unexpected failure never reaches the user as raw exception text.
      _showMessage(
        friendRequestErrorMessage(AppLocalizations.of(context), error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _processingSuggestionIds.remove(suggestion.uid));
      }
    }
  }

  Widget _buildSuggestions(Set<String> friendIds) {
    return FriendSuggestionsSection(
      snapshot: _suggestionsSnapshot,
      statuses: _suggestionStatuses,
      processingIds: _processingSuggestionIds,
      excludedUserIds: friendIds,
      profileMediaService: _profileMediaService,
      onAdd: _addSuggestion,
      onRetry: () => unawaited(_loadSuggestions()),
    );
  }

  /// Same confirmation and service call as the profile screen's Remove
  /// button, reachable from the list row so the option is discoverable.
  Future<void> _confirmRemoveFriend(FriendUser friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Remove friend?', 'Usunąć znajomego?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.template(
              '{name} will be removed from your friends. You can send a new request later.',
              '{name} zniknie z Twoich znajomych. Później możesz wysłać nowe zaproszenie.',
              values: <String, Object>{'name': friend.displayName},
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              key: const ValueKey('friend-remove-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Remove', 'Usuń')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await _friendService.removeFriend(friend.id);
      if (!mounted) return;
      _showMessage(
        AppLocalizations.of(context).template(
          '{name} was removed from your friends.',
          '{name} to już nie Twój znajomy.',
          values: <String, Object>{'name': friend.displayName},
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        AppLocalizations.of(context).text(
          'Could not remove this friend.',
          'Nie udało się usunąć znajomego.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _acceptRequest(FriendRequest request) async {
    await _runRequestAction(
      request.senderId,
      () => _friendService.acceptFriendRequest(request),
      AppLocalizations.of(context).text(
        '${request.senderName} is now your friend.',
        '${request.senderName} jest teraz w gronie Twoich znajomych.',
      ),
    );
  }

  Future<void> _declineRequest(FriendRequest request) async {
    await _runRequestAction(
      request.senderId,
      () => _friendService.declineFriendRequest(request.senderId),
      AppLocalizations.of(
        context,
      ).text('Friend request declined.', 'Odrzucono zaproszenie.'),
    );
  }

  Future<void> _runRequestAction(
    String requestId,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_processingRequestIds.contains(requestId)) return;

    setState(() => _processingRequestIds.add(requestId));
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) {
        _showMessage(
          AppLocalizations.of(context).isPolish
              ? 'Nie udało się zaktualizować zaproszenia. Spróbuj ponownie.'
              : intentionalOrFriendly(
                  error,
                  fallback: 'Could not update this friend request. Try again.',
                ),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(requestId));
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
                  : palette.successForeground,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? palette.dangerSurface
              : palette.successSurface,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const ValueKey('friends-screen'),
      backgroundColor: palette.background,
      body: YoPageBackground(
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
            child: Column(
              children: [
                _buildHeader(),
                _buildSearch(),
                _buildFilters(),
                const SizedBox(height: 8),
                Expanded(
                  child: _filter == _FriendsFilter.requests
                      ? _buildRequests()
                      : _buildFriends(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          final leading = <Widget>[
            if (!widget.isRootTab) ...[
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                size: 40,
                backgroundColor: palette.surface,
                borderColor: palette.border,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
            ],
          ];
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Friends', 'Znajomi'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                copy.text(
                  'Your people, one tap away.',
                  'Twoi znajomi zawsze pod ręką.',
                ),
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<int>(
                stream: _friendService.watchPendingFriendRequestCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return _HeaderButton(
                    tooltip: copy.text(
                      'Friend requests',
                      'Zaproszenia do znajomych',
                    ),
                    icon: Icons.notifications_none_rounded,
                    badgeCount: count,
                    onTap: () =>
                        setState(() => _filter = _FriendsFilter.requests),
                  );
                },
              ),
              const SizedBox(width: 9),
              _HeaderButton(
                tooltip: copy.text('Blocked users', 'Zablokowani użytkownicy'),
                icon: Icons.block_rounded,
                onTap: _openBlockedUsers,
              ),
              const SizedBox(width: 9),
              _HeaderButton(
                tooltip: copy.text('Add friend', 'Dodaj znajomego'),
                icon: Icons.person_add_alt_1_rounded,
                highlighted: true,
                onTap: _openAddFriend,
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    ...leading,
                    Expanded(child: title),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              ...leading,
              Expanded(child: title),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearch() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: _filter == _FriendsFilter.requests
              ? copy.text('Search requests...', 'Szukaj zaproszeń...')
              : copy.text('Search friends...', 'Szukaj znajomych...'),
          hintStyle: TextStyle(color: palette.textTertiary),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: copy.text('Clear search', 'Wyczyść wyszukiwanie'),
                onPressed: _searchController.clear,
                icon: Icon(Icons.close_rounded, color: palette.textSecondary),
              );
            },
          ),
          filled: true,
          fillColor: palette.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: palette.focus, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 0),
      child: StreamBuilder<int>(
        stream: _requestCountStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            _requestFanoutFailed = true;
          }
          final requestCount = snapshot.data ?? 0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: copy.text('All', 'Wszyscy'),
                  selected: _filter == _FriendsFilter.all,
                  onTap: () => _selectFilter(_FriendsFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: copy.text('Online', 'Online'),
                  selected: _filter == _FriendsFilter.online,
                  onTap: () => _selectFilter(_FriendsFilter.online),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: requestCount > 0
                      ? copy.text(
                          'Requests $requestCount',
                          'Zaproszenia $requestCount',
                        )
                      : copy.text('Requests', 'Zaproszenia'),
                  selected: _filter == _FriendsFilter.requests,
                  onTap: () => _selectFilter(_FriendsFilter.requests),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriends() {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<FriendUser>>(
      // The shared fanout retires when its final listener goes away. The
      // Requests filter removes this StreamBuilder entirely, so reacquire the
      // current generation when the friends view mounts again.
      stream: _friendService.watchFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: context.appPalette.interactiveForeground,
            ),
          );
        }

        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: copy.text(
              'Could not load friends',
              'Nie udało się wczytać znajomych',
            ),
            subtitle: copy.isPolish
                ? 'Sprawdź połączenie i spróbuj ponownie.'
                : friendlyErrorMessage(snapshot.error!),
          );
        }

        final allFriends = snapshot.data ?? const <FriendUser>[];
        // Suggestions answer "who else do I know?", so they belong to the
        // unfiltered list only: they are noise inside a name search and
        // meaningless under the Online presence filter.
        final showSuggestions = _filter == _FriendsFilter.all && _query.isEmpty;
        final friendIds = allFriends.map((friend) => friend.id).toSet();
        final filtered = allFriends
            .where((friend) {
              if (_filter == _FriendsFilter.online && !friend.isOnline) {
                return false;
              }
              if (_query.isEmpty) return true;
              return friend.displayName.toLowerCase().contains(_query) ||
                  friend.searchableUsername.contains(_query);
            })
            .toList(growable: false);

        if (filtered.isEmpty) {
          final isSearching = _query.isNotEmpty;
          return _EmptyState(
            icon: isSearching
                ? Icons.search_off_rounded
                : _filter == _FriendsFilter.online
                ? Icons.wifi_off_rounded
                : Icons.people_outline_rounded,
            title: isSearching
                ? copy.text('No matching friends', 'Brak pasujących znajomych')
                : _filter == _FriendsFilter.online
                ? copy.text('Nobody is online', 'Nikt nie jest teraz online')
                : copy.text('No friends yet', 'Nie masz jeszcze znajomych'),
            subtitle: isSearching
                ? copy.text(
                    'Try another name or username.',
                    'Wpisz inną nazwę lub pseudonim.',
                  )
                : _filter == _FriendsFilter.online
                ? copy.text(
                    'Online friends will appear here.',
                    'Znajomi dostępni online pojawią się tutaj.',
                  )
                : copy.text(
                    'Find someone and start building your circle.',
                    'Znajdź kogoś i zacznij budować swoje grono.',
                  ),
            actionLabel: _filter == _FriendsFilter.all && !isSearching
                ? copy.text('Add friend', 'Dodaj znajomego')
                : null,
            onAction: _filter == _FriendsFilter.all && !isSearching
                ? _openAddFriend
                : null,
            // An account with no friends yet is exactly who the rail helps,
            // so it sits under the empty message instead of being reserved
            // for people who already have a list.
            footer: showSuggestions ? _buildSuggestions(friendIds) : null,
          );
        }

        final onlineCount = allFriends
            .where((friend) => friend.isOnline)
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
          children: [
            _FriendsSummary(
              totalCount: allFriends.length,
              onlineCount: onlineCount,
            ),
            const SizedBox(height: 10),
            if (showSuggestions) _buildSuggestions(friendIds),
            ...filtered.map(
              (friend) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FriendCard(
                  friend: friend,
                  profileMediaService: _profileMediaService,
                  openingChat: _openingChatFriendId == friend.id,
                  onProfile: () => _openProfile(friend),
                  onMessage: () => _startChat(friend),
                  onRemove: () => _confirmRemoveFriend(friend),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRequests() {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<FriendRequest>>(
      // A terminal source error retires and evicts the shared generation.
      // Reacquiring here lets a filter round trip attach to its replacement
      // instead of retaining a closed stream for the lifetime of the screen.
      stream: _friendService.watchFriendRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: context.appPalette.interactiveForeground,
            ),
          );
        }

        if (snapshot.hasError) {
          _requestFanoutFailed = true;
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: copy.text(
              'Could not load requests',
              'Nie udało się wczytać zaproszeń',
            ),
            subtitle: copy.isPolish
                ? 'Sprawdź połączenie i spróbuj ponownie.'
                : friendlyErrorMessage(snapshot.error!),
          );
        }

        final requests = (snapshot.data ?? const <FriendRequest>[])
            .where((request) {
              if (_query.isEmpty) return true;
              return request.senderName.toLowerCase().contains(_query);
            })
            .toList(growable: false);

        if (requests.isEmpty) {
          return _EmptyState(
            icon: _query.isEmpty
                ? Icons.mark_email_read_outlined
                : Icons.search_off_rounded,
            title: _query.isEmpty
                ? copy.text(
                    'No pending requests',
                    'Brak oczekujących zaproszeń',
                  )
                : copy.text(
                    'No matching requests',
                    'Brak pasujących zaproszeń',
                  ),
            subtitle: _query.isEmpty
                ? copy.text(
                    'New friend requests will appear here.',
                    'Nowe zaproszenia pojawią się tutaj.',
                  )
                : copy.text('Try another name.', 'Wpisz inną nazwę.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final request = requests[index];
            return FriendRequestCard(
              request: request,
              profileMediaService: _profileMediaService,
              processing: _processingRequestIds.contains(request.senderId),
              onAccept: () => _acceptRequest(request),
              onDecline: () => _declineRequest(request),
            );
          },
        );
      },
    );
  }
}

class _FriendsSummary extends StatelessWidget {
  const _FriendsSummary({required this.totalCount, required this.onlineCount});

  final int totalCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.6;
          final total = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_2_rounded,
                color: palette.interactiveForeground,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  totalCount == 1
                      ? copy.text('1 friend', '1 znajomy')
                      : copy.text(
                          '$totalCount friends',
                          '$totalCount znajomych',
                        ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
          final online = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.successForeground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  copy.text('$onlineCount online', '$onlineCount online'),
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            ],
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [total, const SizedBox(height: 10), online],
            );
          }
          return Row(children: [total, const Spacer(), online]);
        },
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    this.profileMediaService,
    this.openingChat = false,
    required this.onProfile,
    required this.onMessage,
    required this.onRemove,
  });

  final FriendUser friend;
  final ProfileMediaService? profileMediaService;

  /// True while this friend's conversation is being opened: the bubble
  /// shows a spinner and stops accepting taps (same pattern as the
  /// profile screen's Message button).
  final bool openingChat;
  final VoidCallback onProfile;
  final VoidCallback onMessage;
  final VoidCallback onRemove;

  Future<void> _showOptions(BuildContext context) async {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
      // Material, not a decorated Container: ListTile paints its ink on the
      // nearest Material, and a coloured box above it would hide the ripple.
      builder: (sheetContext) => Material(
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
            18 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.template(
                  'options for {name}',
                  'opcje dla {name}',
                  values: <String, Object>{'name': friend.displayName},
                ),
                surfaceColor: palette.surfaceRaised,
              ),
              const SizedBox(height: 2),
              ListTile(
                onTap: () {
                  Navigator.pop(sheetContext);
                  onProfile();
                },
                leading: Icon(
                  Icons.person_outline_rounded,
                  color: palette.textPrimary,
                ),
                title: Text(
                  copy.text('View profile', 'Zobacz profil'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              ListTile(
                onTap: () {
                  Navigator.pop(sheetContext);
                  onMessage();
                },
                leading: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: palette.textPrimary,
                ),
                title: Text(
                  copy.text('Message', 'Wiadomość'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              ListTile(
                key: const ValueKey('friend-remove-action'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRemove();
                },
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: colors.error,
                ),
                title: Text(
                  copy.text('Remove friend', 'Usuń znajomego'),
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onProfile,
        onLongPress: () => _showOptions(context),
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
                      ),
                    ),
                    child: UserAvatar(
                      radius: 27,
                      userId: friend.id,
                      mediaRevision: friend.profileUpdatedAt,
                      mediaService: profileMediaService,
                      displayName: friend.displayName,
                      backgroundColor: palette.surfaceSunken,
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: PeopleStatus.fromPresence(
                          isOnline: friend.isOnline,
                          availability: friend.availability,
                        ).foreground(palette),
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surface, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          friend.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        UserIdentityBadges(uid: friend.id),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _presenceLabel(friend, copy) ??
                          (friend.username.isNotEmpty
                              ? '@${friend.username}'
                              : copy.text('Offline', 'Offline')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _presenceColor(friend, palette),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: openingChat
                    ? copy.text('Opening chat…', 'Otwieranie czatu…')
                    : copy.text('Message', 'Wiadomość'),
                onPressed: openingChat ? null : onMessage,
                style: IconButton.styleFrom(
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  disabledBackgroundColor: colors.secondaryContainer,
                  disabledForegroundColor: colors.onSecondaryContainer,
                ),
                icon: openingChat
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSecondaryContainer,
                        ),
                      )
                    : const Icon(Icons.chat_bubble_rounded, size: 20),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey('friend-options-${friend.id}'),
                tooltip: copy.template(
                  'Options for {name}',
                  'Opcje dla {name}',
                  values: <String, Object>{'name': friend.displayName},
                ),
                onPressed: () => _showOptions(context),
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FriendRequestCard extends StatelessWidget {
  const FriendRequestCard({
    required this.request,
    this.profileMediaService,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final FriendRequest request;
  final ProfileMediaService? profileMediaService;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : copy.text('YO Voice user', 'Użytkownik YO Voice');

    return Container(
      key: ValueKey('friend-request-card-${request.senderId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          UserAvatar(
            radius: 27,
            userId: request.senderId,
            mediaService: profileMediaService,
            displayName: name,
            backgroundColor: palette.surfaceSunken,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.text(
                    'Wants to be your friend',
                    'Chce dodać Cię do znajomych',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 11),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final stackActions =
                        textScale > 1.4 || constraints.maxWidth < 250;
                    final accept = FilledButton.icon(
                      key: const ValueKey('friend-request-accept'),
                      onPressed: processing ? null : onAccept,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: processing
                          ? SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(copy.text('Accept', 'Akceptuj')),
                    );
                    final decline = OutlinedButton.icon(
                      key: const ValueKey('friend-request-decline'),
                      onPressed: processing ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: palette.textPrimary,
                        side: BorderSide(color: palette.borderStrong),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(copy.text('Decline', 'Odrzuć')),
                    );

                    if (stackActions) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [accept, const SizedBox(height: 8), decline],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: accept),
                        const SizedBox(width: 8),
                        Expanded(child: decline),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return AccessibleTapRegion(
      selected: selected,
      semanticLabel: label,
      onTap: onTap,
      borderRadius: 99,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.primary : palette.surface,
          borderRadius: BorderRadius.circular(99),
          border: selected ? null : Border.all(color: palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.onPrimary : palette.textPrimary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
    this.badgeCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final semanticLabel = badgeCount > 0
        ? copy.text(
            '$tooltip, $badgeCount pending',
            '$tooltip, oczekujących: $badgeCount',
          )
        : tooltip;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: AccessibleTapRegion(
        semanticLabel: semanticLabel,
        onTap: onTap,
        borderRadius: 15,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: highlighted ? colors.primary : palette.surface,
            borderRadius: BorderRadius.circular(15),
            border: highlighted ? null : Border.all(color: palette.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: highlighted ? colors.onPrimary : palette.textPrimary,
                size: 21,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: palette.dangerSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: palette.dangerForeground,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: TextStyle(
                        color: palette.dangerForeground,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional full-width content under the message. It owns its own gutter
  /// so a horizontally scrolling rail is not inset by the 28 px the centred
  /// message uses.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Icon(
                      icon,
                      color: colors.onPrimaryContainer,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
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
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Online now" keeps its meaning; a chosen availability replaces it with
/// the same words the picker uses, so both sides read the same state.
/// Null when the friend is offline, so the row can fall back to the
/// username line exactly as before.
String? _presenceLabel(FriendUser friend, AppLocalizations copy) {
  final status = PeopleStatus.fromPresence(
    isOnline: friend.isOnline,
    availability: friend.availability,
  );
  return switch (status) {
    PeopleStatus.online => copy.text('Online now', 'Teraz online'),
    PeopleStatus.away => null,
    _ => status.localizedLabel(copy),
  };
}

Color _presenceColor(FriendUser friend, AppPalette palette) {
  final status = PeopleStatus.fromPresence(
    isOnline: friend.isOnline,
    availability: friend.availability,
  );
  return status == PeopleStatus.away
      ? palette.textSecondary
      : status.foreground(palette);
}
