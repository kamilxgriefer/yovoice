import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/friend_request_error_copy.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_request_decision.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_suggestion_card.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({
    this.friendService,
    this.socialGraphService,
    this.profileMediaService,
    super.key,
  });

  /// Optional injection seams, matching the established pattern on
  /// ChatScreen and NotificationsScreen: production passes nothing and
  /// gets the live services, tests pass fakes so the accept/decline
  /// wiring below can be exercised without a Firebase app.
  final FriendService? friendService;
  final SocialGraphService? socialGraphService;
  final ProfileMediaService? profileMediaService;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();
  ProfileMediaService? get _profileMediaService => widget.profileMediaService;
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<FriendUser> _results = const [];
  final Map<String, FriendRelationshipStatus> _relationshipStatuses = {};
  final Set<String> _processingIds = <String>{};
  final Map<String, FriendRelationshipStatus> _suggestionStatuses = {};

  bool _isSearching = false;
  String? _errorMessage;
  late Future<List<SuggestedFriend>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = _socialGraphService.getFriendSuggestions();
  }

  void _retrySuggestions() {
    setState(() {
      _suggestionsFuture = _socialGraphService.getFriendSuggestions();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// "Add" never accepts: an `incomingPending` answer opens the explicit
  /// Accept / Decline prompt; a later tap on the same card reopens it.
  Future<void> _addSuggestion(SuggestedFriend suggestion) async {
    if (_processingIds.contains(suggestion.uid)) return;
    final previous = _suggestionStatuses[suggestion.uid];
    if (previous == FriendRelationshipStatus.requestReceived) {
      await _promptIncomingSuggestion(suggestion);
      return;
    }
    setState(() {
      _processingIds.add(suggestion.uid);
      _suggestionStatuses[suggestion.uid] =
          FriendRelationshipStatus.requestSent;
    });
    try {
      final result = await _friendService.requestFriendship(
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
      setState(() => _suggestionStatuses[suggestion.uid] = result.status);
      if (result.incomingPending) {
        await _promptIncomingSuggestion(suggestion);
        return;
      }
      final copy = AppLocalizations.of(context);
      _showMessage(
        result.acceptedWithoutPrompt
            ? friendRequestAcceptedWithoutPromptMessage(
                copy,
                name: suggestion.displayName,
              )
            : result.status == FriendRelationshipStatus.friends
            ? copy.template(
                'You and {name} are now friends.',
                'Ty i {name} jesteście teraz znajomymi.',
                values: {'name': suggestion.displayName},
              )
            : copy.template(
                'Friend request sent to {name}.',
                'Wysłano zaproszenie do {name}.',
                values: {'name': suggestion.displayName},
              ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            _suggestionStatuses.remove(suggestion.uid);
          } else {
            _suggestionStatuses[suggestion.uid] = previous;
          }
        });
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(suggestion.uid));
    }
  }

  Future<void> _promptIncomingSuggestion(SuggestedFriend suggestion) async {
    final outcome = await showFriendRequestPrompt(
      context,
      senderId: suggestion.uid,
      senderName: suggestion.displayName,
      friendService: _friendService,
      profileMediaService: widget.profileMediaService,
    );
    if (!mounted || outcome == null) return;
    final next = await friendRelationshipAfterResponse(
      outcome,
      reread: () => _friendService.getRelationshipStatus(suggestion.uid),
    );
    if (!mounted) return;
    setState(() => _suggestionStatuses[suggestion.uid] = next);
    _showMessage(
      friendRequestResponseMessage(
        AppLocalizations.of(context),
        outcome,
        name: suggestion.displayName,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _results = const [];
        _relationshipStatuses.clear();
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _searchUsers(query);
    });
  }

  Future<void> _searchUsers(String query) async {
    try {
      final users = await _friendService.searchUsers(query);
      // New callables return the relationship in the same bounded response.
      // Only unresolved rows use the legacy lookup, keeping old deployed
      // backends compatible while removing the production N+1 read burst.
      final statuses = await Future.wait(
        users.map((user) async {
          final embedded = user.relationshipStatus;
          if (embedded != null) return embedded;
          return _friendService.getRelationshipStatus(user.id);
        }),
      );

      if (!mounted || _searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _results = users;
        _relationshipStatuses
          ..clear()
          ..addEntries(
            List.generate(
              users.length,
              (index) => MapEntry(users[index].id, statuses[index]),
            ),
          );
        _isSearching = false;
        _errorMessage = null;
      });
    } catch (error) {
      // A slower, older request must never erase a newer successful result.
      // The success path already has this guard; failures need the same race
      // protection because mobile networks commonly resolve out of order.
      if (!mounted || _searchController.text.trim() != query) return;

      setState(() {
        _results = const [];
        _relationshipStatuses.clear();
        _isSearching = false;
        _errorMessage = _readableError(error);
      });
    }
  }

  Future<void> _handlePrimaryAction(FriendUser user) async {
    if (_processingIds.contains(user.id)) return;

    final status =
        _relationshipStatuses[user.id] ?? FriendRelationshipStatus.none;

    if (status == FriendRelationshipStatus.friends) {
      return;
    }

    final optimisticStatus = switch (status) {
      FriendRelationshipStatus.requestSent => status,
      FriendRelationshipStatus.requestReceived => status,
      FriendRelationshipStatus.none => FriendRelationshipStatus.requestSent,
      FriendRelationshipStatus.friends ||
      FriendRelationshipStatus.blocked => status,
    };
    setState(() {
      _processingIds.add(user.id);
      _relationshipStatuses[user.id] = optimisticStatus;
    });

    try {
      if (status == FriendRelationshipStatus.requestSent) {
        await _friendService.cancelFriendRequest(user.id);

        if (!mounted) return;
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.none;
        });
        _showMessage(
          AppLocalizations.of(
            context,
          ).text('Friend request cancelled.', 'Anulowano zaproszenie.'),
        );
        return;
      }

      if (status == FriendRelationshipStatus.requestReceived) {
        // Accepting must go through the explicit accept mutation, never a
        // reciprocal sendFriendRequest — "Accept" relying on the server's
        // reciprocal-accept branch is exactly how sending auto-created a
        // friendship. Mirrors ProfilePreviewSheet's accept wiring.
        final outcome = await _friendService.respondToFriendRequest(
          user.id,
          accept: true,
        );

        if (!mounted) return;
        final next = await friendRelationshipAfterResponse(
          outcome,
          reread: () => _friendService.getRelationshipStatus(user.id),
        );
        if (!mounted) return;
        setState(() => _relationshipStatuses[user.id] = next);
        _showMessage(
          friendRequestResponseMessage(
            AppLocalizations.of(context),
            outcome,
            name: user.displayName,
          ),
        );
        return;
      }

      final result = await _friendService.requestFriendship(user);

      if (!mounted) return;

      setState(() {
        _relationshipStatuses[user.id] = result.status;
      });

      if (result.incomingPending) {
        // Nothing changed: they had already asked. The row now shows Accept
        // and Decline, and the explicit prompt asks right away.
        final outcome = await showFriendRequestPrompt(
          context,
          senderId: user.id,
          senderName: user.displayName,
          friendService: _friendService,
          profileMediaService: widget.profileMediaService,
        );
        if (!mounted || outcome == null) return;
        final next = await friendRelationshipAfterResponse(
          outcome,
          reread: () => _friendService.getRelationshipStatus(user.id),
        );
        if (!mounted) return;
        setState(() => _relationshipStatuses[user.id] = next);
        _showMessage(
          friendRequestResponseMessage(
            AppLocalizations.of(context),
            outcome,
            name: user.displayName,
          ),
        );
        return;
      }

      final copy = AppLocalizations.of(context);
      _showMessage(
        result.acceptedWithoutPrompt
            ? friendRequestAcceptedWithoutPromptMessage(
                copy,
                name: user.displayName,
              )
            : result.status == FriendRelationshipStatus.friends
            ? copy.template(
                'You and {name} are now friends.',
                'Ty i {name} jesteście teraz znajomymi.',
                values: {'name': user.displayName},
              )
            : copy.template(
                'Friend request sent to {name}.',
                'Wysłano zaproszenie do {name}.',
                values: {'name': user.displayName},
              ),
      );
    } catch (error) {
      if (!mounted) return;

      final message = _readableError(error);

      if (message ==
          AppLocalizations.of(
            context,
          ).text('You are already friends.', 'Jesteście już znajomymi.')) {
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.friends;
        });
      } else if (message ==
          AppLocalizations.of(context).text(
            'Friend request already sent.',
            'To zaproszenie zostało już wysłane.',
          )) {
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.requestSent;
        });
      } else {
        setState(() => _relationshipStatuses[user.id] = status);
      }

      _showError(message);
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(user.id));
      }
    }
  }

  Future<void> _declineRequest(FriendUser user) async {
    if (_processingIds.contains(user.id)) return;
    if (_relationshipStatuses[user.id] !=
        FriendRelationshipStatus.requestReceived) {
      return;
    }

    setState(() {
      _processingIds.add(user.id);
      _relationshipStatuses[user.id] = FriendRelationshipStatus.none;
    });

    try {
      final outcome = await _friendService.respondToFriendRequest(
        user.id,
        accept: false,
      );

      if (!mounted) return;
      final next = await friendRelationshipAfterResponse(
        outcome,
        reread: () => _friendService.getRelationshipStatus(user.id),
      );
      if (!mounted) return;
      setState(() => _relationshipStatuses[user.id] = next);
      _showMessage(
        outcome == FriendRequestResponseOutcome.declined
            ? AppLocalizations.of(
                context,
              ).text('Friend request declined.', 'Odrzucono zaproszenie.')
            : friendRequestResponseMessage(
                AppLocalizations.of(context),
                outcome,
                name: user.displayName,
              ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _relationshipStatuses[user.id] =
              FriendRelationshipStatus.requestReceived,
        );
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(user.id));
      }
    }
  }

  /// Shared with the Friends screen's suggestion rail so both surfaces
  /// describe the same failure identically.
  String _readableError(Object error) =>
      friendRequestErrorMessage(AppLocalizations.of(context), error);

  void _showMessage(String message) {
    final palette = context.appPalette;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: palette.successForeground),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.successSurface,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showError(String message) {
    final palette = context.appPalette;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: palette.dangerForeground),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.dangerSurface,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const ValueKey('add-friend-screen'),
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
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
            stops: const [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchField(),
                Expanded(child: _buildContent()),
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
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: copy.text('Back', 'Wstecz'),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Slim title: the screen's one headline, 22 px w800.
                Text(
                  copy.text('Add friends', 'Dodaj znajomych'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  copy.text(
                    'Search by name or username',
                    'Szukaj po nazwie lub pseudonimie',
                  ),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: copy.text('Search people...', 'Szukaj osób...'),
          hintStyle: TextStyle(color: palette.textTertiary, fontSize: 15),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  tooltip: copy.text('Clear search', 'Wyczyść wyszukiwanie'),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _results = const [];
                      _relationshipStatuses.clear();
                      _isSearching = false;
                      _errorMessage = null;
                    });
                  },
                  icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                )
              : null,
          filled: true,
          fillColor: palette.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.focus, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final query = _searchController.text.trim();
    final copy = AppLocalizations.of(context);

    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: context.appPalette.interactiveForeground,
        ),
      );
    }

    if (_errorMessage != null) {
      return _SearchState(
        icon: Icons.error_outline_rounded,
        title: copy.text(
          'Could not search users',
          'Nie udało się wyszukać osób',
        ),
        subtitle: _errorMessage!,
      );
    }

    if (query.length < 2) {
      return _buildSuggestions();
    }

    if (_results.isEmpty) {
      return _SearchState(
        icon: Icons.search_off_rounded,
        title: copy.text('No users found', 'Nie znaleziono osób'),
        subtitle: copy.text(
          'Try another display name or username.',
          'Wpisz inną nazwę lub pseudonim.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = _results[index];
        return _UserResultCard(
          user: user,
          profileMediaService: _profileMediaService,
          relationshipStatus:
              _relationshipStatuses[user.id] ?? FriendRelationshipStatus.none,
          isProcessing: _processingIds.contains(user.id),
          onPressed: () => _handlePrimaryAction(user),
          onDecline: () => _declineRequest(user),
        );
      },
    );
  }

  Widget _buildSuggestions() {
    final copy = AppLocalizations.of(context);
    return FutureBuilder<List<SuggestedFriend>>(
      future: _suggestionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: context.appPalette.interactiveForeground,
            ),
          );
        }
        if (snapshot.hasError) {
          return _SearchState(
            icon: Icons.cloud_off_rounded,
            title: copy.text(
              'Could not load suggestions',
              'Nie udało się wczytać propozycji',
            ),
            subtitle: copy.text(
              'Check your connection and try again.',
              'Sprawdź połączenie i spróbuj ponownie.',
            ),
            actionLabel: copy.text('Retry', 'Spróbuj ponownie'),
            onAction: _retrySuggestions,
          );
        }
        final suggestions = snapshot.data ?? const <SuggestedFriend>[];
        if (suggestions.isEmpty) {
          return _SearchState(
            icon: Icons.person_search_rounded,
            title: copy.text('Find someone you know', 'Znajdź znajomą osobę'),
            subtitle: copy.text(
              'Enter at least 2 characters from their display name or username.',
              'Wpisz co najmniej 2 znaki nazwy lub pseudonimu.',
            ),
          );
        }

        // THE section heading (ADR-209) owns the rhythm above and below
        // its ink, so the list adds no top air of its own.
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: HomeSectionHeader(
                title: copy.text('Suggested for you', 'Proponowane dla Ciebie'),
              ),
            ),
            ...suggestions.map(
              (suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FriendSuggestionCard(
                  suggestion: suggestion,
                  profileMediaService: _profileMediaService,
                  isProcessing: _processingIds.contains(suggestion.uid),
                  relationshipStatus: _suggestionStatuses[suggestion.uid],
                  onPressed: () => _addSuggestion(suggestion),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserResultCard extends StatelessWidget {
  const _UserResultCard({
    required this.user,
    this.profileMediaService,
    required this.relationshipStatus,
    required this.isProcessing,
    required this.onPressed,
    required this.onDecline,
  });

  final FriendUser user;
  final ProfileMediaService? profileMediaService;
  final FriendRelationshipStatus relationshipStatus;
  final bool isProcessing;
  final VoidCallback onPressed;

  /// Shown only while a request from this user is pending: Accept must
  /// always travel with a visible way to say no.
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final button = _buttonPresentation(
      relationshipStatus,
      palette,
      colors,
      copy,
    );
    final identity = Row(
      children: [
        _UserAvatar(user: user, profileMediaService: profileMediaService),
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
                    user.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  UserIdentityBadges(uid: user.id),
                ],
              ),
              if (user.username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final primary = FilledButton(
      onPressed:
          isProcessing ||
              relationshipStatus == FriendRelationshipStatus.friends ||
              relationshipStatus == FriendRelationshipStatus.blocked
          ? null
          : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: button.backgroundColor,
        disabledBackgroundColor: button.disabledBackgroundColor,
        foregroundColor: button.foregroundColor,
        disabledForegroundColor: button.disabledForegroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: isProcessing
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: button.foregroundColor,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(button.icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    button.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    );
    // A received request always shows both choices as words, never an
    // icon-only X beside a labelled Accept (friend-request consent ADR).
    final decline =
        relationshipStatus == FriendRelationshipStatus.requestReceived
        ? Tooltip(
            message: copy.text('Decline friend request', 'Odrzuć zaproszenie'),
            child: OutlinedButton.icon(
              key: ValueKey('friend-search-decline-${user.id}'),
              onPressed: isProcessing ? null : onDecline,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: palette.textPrimary,
                disabledForegroundColor: palette.textTertiary,
                side: BorderSide(color: palette.borderStrong),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(
                copy.text('Decline', 'Odrzuć'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
        : null;

    return Container(
      key: ValueKey('friend-search-result-${user.id}'),
      // One flat layer (1 px border, radius 12); a card because the row
      // carries its own action.
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final actions = Row(
            children: [
              Expanded(child: primary),
              if (decline != null) ...[
                const SizedBox(width: 8),
                Expanded(child: decline),
              ],
            ],
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 10),
              Flexible(child: primary),
              if (decline != null) ...[
                const SizedBox(width: 6),
                Flexible(child: decline),
              ],
            ],
          );
        },
      ),
    );
  }

  static _FriendButtonPresentation _buttonPresentation(
    FriendRelationshipStatus status,
    AppPalette palette,
    ColorScheme colors,
    AppLocalizations copy,
  ) {
    switch (status) {
      case FriendRelationshipStatus.friends:
        return _FriendButtonPresentation(
          label: copy.text('Friends', 'Znajomi'),
          icon: Icons.people_alt_rounded,
          backgroundColor: palette.successSurface,
          disabledBackgroundColor: palette.successSurface,
          foregroundColor: palette.successForeground,
          disabledForegroundColor: palette.successForeground,
        );
      case FriendRelationshipStatus.requestSent:
        return _FriendButtonPresentation(
          label: copy.text('Cancel', 'Anuluj'),
          icon: Icons.close_rounded,
          backgroundColor: palette.warningSurface,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: palette.warningForeground,
          disabledForegroundColor: palette.textTertiary,
        );
      case FriendRelationshipStatus.requestReceived:
        return _FriendButtonPresentation(
          label: copy.text('Accept', 'Akceptuj'),
          icon: Icons.check_rounded,
          backgroundColor: colors.primary,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: colors.onPrimary,
          disabledForegroundColor: palette.textTertiary,
        );
      // Tonal like the suggestion cards on this same screen: a result list
      // is not a stack of violet CTAs (Slim: one accent per screen).
      case FriendRelationshipStatus.none:
        return _FriendButtonPresentation(
          label: copy.text('Add', 'Dodaj'),
          icon: Icons.person_add_alt_1_rounded,
          backgroundColor: colors.primaryContainer,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: colors.onPrimaryContainer,
          disabledForegroundColor: palette.textTertiary,
        );
      case FriendRelationshipStatus.blocked:
        return _FriendButtonPresentation(
          label: copy.text('Blocked', 'Zablokowano'),
          icon: Icons.block_rounded,
          backgroundColor: palette.dangerSurface,
          disabledBackgroundColor: palette.dangerSurface,
          foregroundColor: palette.dangerForeground,
          disabledForegroundColor: palette.dangerForeground,
        );
    }
  }
}

class _FriendButtonPresentation {
  const _FriendButtonPresentation({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.disabledBackgroundColor,
    required this.foregroundColor,
    required this.disabledForegroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color disabledBackgroundColor;
  final Color foregroundColor;
  final Color disabledForegroundColor;
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, this.profileMediaService});

  final FriendUser user;
  final ProfileMediaService? profileMediaService;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    // Slim: a 2 px neutral ring replaces the decorative violet gradient (and
    // its two inline hexes); the 52 px geometry is unchanged.
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.border),
      child: ProfilePhotoButton(
        userId: user.id,
        displayName: user.displayName,
        mediaRevision: user.profileUpdatedAt,
        mediaService: profileMediaService,
        minimumSize: const Size(48, 48),
        child: UserAvatar(
          radius: 24,
          userId: user.id,
          mediaRevision: user.profileUpdatedAt,
          mediaService: profileMediaService,
          displayName: user.displayName,
          backgroundColor: palette.surfaceSunken,
        ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer, size: 34),
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 44),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
