import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_suggestion_card.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

/// "People you may know" — friends of the signed-in user's friends.
///
/// Purely presentational, snapshot-driven (same shape as Home's
/// `DiscoverClubsRail`): the hosting screen owns the [SocialGraphService]
/// future, the per-row busy/sent state and the send action, so the section can
/// move between the populated list and the empty state without restarting a
/// rate-limited callable.
///
/// Never renders a placeholder person. An empty or fully filtered result
/// renders nothing at all, and a failure says it failed instead of claiming
/// there is nobody to suggest.
class FriendSuggestionsSection extends StatelessWidget {
  const FriendSuggestionsSection({
    required this.snapshot,
    required this.statuses,
    required this.processingIds,
    required this.onAdd,
    required this.onRetry,
    this.excludedUserIds = const <String>{},
    this.profileMediaService,
    super.key,
  });

  final AsyncSnapshot<List<SuggestedFriend>> snapshot;

  /// Relationship reported by the server for suggestions the user acted on.
  final Map<String, FriendRelationshipStatus> statuses;

  /// Suggestions whose friend request is in flight right now.
  final Set<String> processingIds;

  final void Function(SuggestedFriend suggestion) onAdd;
  final VoidCallback onRetry;

  /// People the hosting screen already knows about — the live friend list.
  /// The callable excludes existing friends and pending requests server-side,
  /// but its result is cached for 30 s, so an accept that lands in between
  /// must not leave a stale suggestion on screen.
  final Set<String> excludedUserIds;

  final ProfileMediaService? profileMediaService;

  static const double _horizontalGutter = 2;

  double _cardWidth(BuildContext context, double availableWidth) {
    final base = availableWidth < 420
        ? 158.0
        : availableWidth < 840
        ? 168.0
        : 176.0;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final scaled = base + 56 * (scale - 1);
    // Always leave room for a peek of the next card so the rail reads as
    // scrollable instead of looking like a single cropped tile.
    final ceiling = math.max(140.0, availableWidth - 48);
    return math.min(scaled, ceiling);
  }

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) {
      return _frame(context, child: _buildSkeleton(context));
    }
    if (snapshot.hasError) {
      return _frame(context, child: _buildError(context));
    }

    final suggestions = (snapshot.data ?? const <SuggestedFriend>[])
        .where((suggestion) => !excludedUserIds.contains(suggestion.uid))
        .toList(growable: false);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return _frame(context, child: _buildRail(context, suggestions));
  }

  Widget _frame(BuildContext context, {required Widget child}) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_horizontalGutter, 0, 12, 10),
          child: Semantics(
            header: true,
            child: Text(
              copy.text('People you may know', 'Może ich znasz'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        child,
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildRail(BuildContext context, List<SuggestedFriend> suggestions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _cardWidth(context, constraints.maxWidth);
        return SingleChildScrollView(
          key: const ValueKey('friend-suggestions-rail'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _horizontalGutter),
          // IntrinsicHeight equalises the cards instead of a guessed fixed
          // height, so a long name or a 200% text scale grows the whole rail
          // rather than overflowing one card.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < suggestions.length; index += 1) ...[
                  if (index > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: cardWidth,
                    child: FriendSuggestionCard(
                      suggestion: suggestions[index],
                      layout: FriendSuggestionCardLayout.rail,
                      profileMediaService: profileMediaService,
                      isProcessing: processingIds.contains(
                        suggestions[index].uid,
                      ),
                      relationshipStatus: statuses[suggestions[index].uid],
                      onPressed: () => onAdd(suggestions[index]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final palette = context.appPalette;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _cardWidth(context, constraints.maxWidth);
        Widget bar(double widthFactor, double height) => Center(
          child: Container(
            width: (cardWidth - 24) * widthFactor,
            height: height,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );

        return ExcludeSemantics(
          child: SingleChildScrollView(
            key: const ValueKey('friend-suggestions-loading'),
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: _horizontalGutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < 3; index += 1) ...[
                  if (index > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: cardWidth,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: palette.surfaceMuted,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          bar(.8, 13 * scale),
                          const SizedBox(height: 8),
                          bar(.55, 11 * scale),
                          const SizedBox(height: 16),
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.surfaceMuted,
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.text(
            'Could not load suggestions',
            'Nie udało się wczytać propozycji',
          ),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          copy.text(
            'Check your connection and try again.',
            'Sprawdź połączenie i spróbuj ponownie.',
          ),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
    final retry = SizedBox(
      height: 44,
      child: FilledButton(
        key: const ValueKey('friend-suggestions-retry'),
        onPressed: onRetry,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Text(
          copy.text('Retry', 'Spróbuj ponownie'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );

    return Container(
      key: const ValueKey('friend-suggestions-error'),
      margin: const EdgeInsets.symmetric(horizontal: _horizontalGutter),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.cloud_off_rounded,
              color: palette.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stack =
                    constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.4;
                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      message,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: retry),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: message),
                    const SizedBox(width: 12),
                    retry,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
