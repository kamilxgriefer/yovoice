import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Home's "Discover clubs" section: public community clubs from
/// [HomeFeedService.watchSuggestedClubs], presented with a state for every
/// answer that stream can give.
///
/// WHY THIS IS A WIDGET AND NOT A METHOD ON HOME.
/// The section it replaces was `snapshot.data ?? const <Club>[]` followed by
/// `if (clubs.isEmpty) return const SizedBox.shrink()` — one branch for four
/// different situations. A permission denial, a dead connection, a feed that
/// has not emitted yet and a genuinely empty result all rendered as the same
/// nothing, heading included, which is exactly why the rail being denied by
/// `firestore.rules` for the entire life of the product went unnoticed. The
/// states are separated here so each one is reachable, visible and testable
/// on its own.
///
/// The caller owns the stream and passes the [AsyncSnapshot] — the same
/// contract `RecentChats` uses — so every state can be pumped in a widget
/// test without a Firebase app.
///
/// RESPONSIVE BEHAVIOUR, by available width rather than device label:
///  * narrow (< 600): a horizontally scrolling rail whose cards bleed off
///    the trailing edge, so the swipe affordance is visible on a phone;
///  * medium (600–999): a three-column grid — a phone rail stretched across
///    a tablet would leave most of the row empty;
///  * wide (>= 1000): a four-column grid.
/// Card heights come from `IntrinsicHeight` per row, not from a magic
/// number, so a long club name or a doubled text scale grows the row
/// instead of overflowing it.
class DiscoverClubsRail extends StatelessWidget {
  const DiscoverClubsRail({
    required this.snapshot,
    required this.onOpenClub,
    this.onRetry,
    this.gutter = 18,
    super.key,
  });

  /// The suggested-clubs stream's current state, error included.
  final AsyncSnapshot<List<Club>> snapshot;

  final ValueChanged<Club> onOpenClub;

  /// Re-subscribes the stream. A Firestore snapshot subscription is
  /// terminated by its first error, so without this a transient failure
  /// would leave the rail dead until the screen is rebuilt. Omitted (null)
  /// the error state still renders — it just cannot offer the retry.
  final VoidCallback? onRetry;

  /// Horizontal page gutter. The rail's scrolling content uses it as
  /// padding rather than an outer inset, which is what lets a card bleed
  /// past the trailing edge on a phone.
  final double gutter;

  static const double _mediumBreakpoint = 600;
  static const double _wideBreakpoint = 1000;
  static const double _gap = 11;

  /// How many placeholder cards the loading state shows. Three reads as a
  /// row in progress at every width without implying a result count.
  static const int _skeletonCount = 3;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final waiting =
        snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData;
    final clubs = snapshot.data ?? const <Club>[];

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Semantics(
              header: true,
              child: Text(
                copy.text('Discover clubs', 'Odkrywaj kluby'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (waiting) {
                return _lane(
                  width,
                  List<Widget>.generate(
                    _skeletonCount,
                    (_) => const _ClubCardSkeleton(),
                  ),
                );
              }

              // Before any read of `data`, and its own branch: a denied
              // query and an empty collection are different facts and the
              // rail must not present them as one.
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: _RailNote(
                    icon: Icons.cloud_off_rounded,
                    tone: palette.dangerForeground,
                    liveRegion: true,
                    title: copy.text(
                      'Clubs could not be loaded.',
                      'Nie udało się wczytać klubów.',
                    ),
                    message: friendlyErrorMessage(
                      snapshot.error!,
                      fallback: copy.text(
                        'Check your connection and try again.',
                        'Sprawdź połączenie i spróbuj ponownie.',
                      ),
                    ),
                    actionLabel: onRetry == null
                        ? null
                        : copy.text('Try again', 'Spróbuj ponownie'),
                    onAction: onRetry,
                  ),
                );
              }

              if (clubs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: _RailNote(
                    icon: Icons.groups_2_rounded,
                    tone: AppColors.accent,
                    title: copy.text(
                      'No public clubs yet.',
                      'Nie ma jeszcze publicznych klubów.',
                    ),
                    message: copy.text(
                      'Community clubs show up here as soon as someone opens one to everyone.',
                      'Kluby społeczności pojawią się tutaj, gdy ktoś otworzy pierwszy z nich dla wszystkich.',
                    ),
                  ),
                );
              }

              return _lane(width, [
                for (final club in clubs)
                  _ClubCard(club: club, onTap: () => onOpenClub(club)),
              ]);
            },
          ),
        ],
      ),
    );
  }

  /// One layout for cards and placeholders alike, so the loading state
  /// occupies the same shape the result will.
  Widget _lane(double width, List<Widget> items) {
    if (width < _mediumBreakpoint) {
      // Two full cards plus a peek at the third on a typical phone: the
      // peek is the only thing that says the row scrolls.
      final cardWidth = ((width - gutter * 2 - _gap) / 2).clamp(150.0, 190.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0) const SizedBox(width: _gap),
                SizedBox(width: cardWidth, child: items[index]),
              ],
            ],
          ),
        ),
      );
    }

    final columns = width >= _wideBreakpoint ? 4 : 3;
    final available = math.max(0.0, width - gutter * 2);
    // Floored so the row can never exceed `available` by a rounding error.
    final cardWidth = math
        .max(0.0, (available - _gap * (columns - 1)) / columns)
        .floorToDouble();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var start = 0; start < items.length; start += columns) ...[
            if (start > 0) const SizedBox(height: _gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var index = start;
                    index < math.min(start + columns, items.length);
                    index++
                  ) ...[
                    if (index > start) const SizedBox(width: _gap),
                    SizedBox(width: cardWidth, child: items[index]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A public community club, as Home offers it. Nothing here is computed or
/// guessed: the name, artwork and member count are the club document's own.
class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.onTap});

  final Club club;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final members = club.memberCount == 1
        ? copy.text('1 member', '1 członek')
        : copy.text(
            '${club.memberCount} members',
            '${club.memberCount} członków',
          );

    return Material(
      key: ValueKey('discover-club-card-${club.id}'),
      color: palette.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The canonical avatar: a revoked or broken club image falls
              // back to the club's initial instead of an empty disc.
              UserAvatar(
                radius: 28,
                photoUrl: club.avatarUrl,
                displayName: club.name,
              ),
              const SizedBox(height: 12),
              Text(
                club.name,
                // Two lines rather than one: most club names that matter
                // are longer than a 155 px card fits, and truncating at
                // the first word helps nobody.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                members,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Text(
                copy.text('View club', 'Zobacz klub'),
                style: TextStyle(
                  color: palette.interactiveForeground,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The loading state's silhouette — the card's own shape, with the blocks
/// where its content will land. Deliberately unanimated: it must not read
/// as content, and a widget test should not have to settle an infinite
/// animation to reach the states after it.
class _ClubCardSkeleton extends StatelessWidget {
  const _ClubCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Semantics(
      key: const ValueKey('discover-club-skeleton'),
      label: copy.text('Loading clubs', 'Wczytywanie klubów'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 12),
            block(double.infinity, 13),
            const SizedBox(height: 8),
            block(72, 10),
            const SizedBox(height: 12),
            block(54, 10),
          ],
        ),
      ),
    );
  }
}

/// The empty and error states. They share a shape so the section keeps its
/// rhythm, and differ in icon, tone and words so they can never be mistaken
/// for one another.
class _RailNote extends StatelessWidget {
  const _RailNote({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.liveRegion = false,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Announced by a screen reader when it replaces the loading state.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      key: const ValueKey('discover-clubs-note'),
      liveRegion: liveRegion,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: tone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
