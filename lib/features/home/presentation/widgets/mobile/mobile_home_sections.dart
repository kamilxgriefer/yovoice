import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Mobile-native presentations of the desktop Home sections.
///
/// These are NOT the desktop cards. Those were built for a ~320pt column
/// inside a wide viewport and carry fixed heights and hard-coded row
/// widths, which overflow a phone. What is shared is what should be
/// shared — the services, models and callbacks — while the geometry here
/// is flexible: intrinsic heights, `Expanded`/`Flexible` rows, and text
/// that wraps or ellipsizes rather than pushing a row past the edge.
///
/// Every section is safe down to a 320pt viewport minus page padding.

/// Shared section heading. `See all` is optional and always a 44pt target.
class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    required this.title,
    this.live = false,
    this.onSeeAll,
    super.key,
  });

  final String title;
  final bool live;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.visible,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
      ),
    );
    final viewAllButton = onSeeAll == null
        ? null
        : TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: palette.interactiveForeground,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy.text('View all', 'Zobacz wszystkie'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          );
    final titleAndStatus = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: titleWidget),
        if (live) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.live,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: enlargedText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleAndStatus,
                if (viewAllButton != null)
                  Align(alignment: Alignment.centerRight, child: viewAllButton),
              ],
            )
          : Row(
              children: [
                Expanded(child: titleAndStatus),
                if (viewAllButton != null) ...[
                  const SizedBox(width: 8),
                  viewAllButton,
                ],
              ],
            ),
    );
  }
}

/// `Moments from your circle` — your own tile first, then the circle's.
class MobileMomentsStrip extends StatelessWidget {
  const MobileMomentsStrip({
    required this.moments,
    required this.profile,
    required this.currentUserId,
    required this.onOpenMoment,
    required this.onCreateMoment,
    this.onOpenChain,
    this.expiryClock,
    this.expandedLabels = false,
    super.key,
  });

  final List<VoiceMoment> moments;
  final UserProfile? profile;
  final String currentUserId;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final bool expandedLabels;

  /// Opens the signed-in user's whole ACTIVE chain in the story viewer.
  /// Optional so existing callers keep working; when null the bubble
  /// falls back to [onOpenMoment] with the newest.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  /// Uses the same instant as an injected [HomeFeedService] in widget tests.
  final DateTime Function()? expiryClock;

  static const double _tile = 66;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final playable = moments
        .where((moment) => moment.hasMediaReference)
        .toList(growable: false);
    final chains = buildMomentChains(playable);
    MomentChain? mineChain;
    if (currentUserId.isNotEmpty) {
      for (final chain in chains) {
        if (chain.authorId == currentUserId) {
          mineChain = chain;
          break;
        }
      }
    }
    final others = chains
        .where((chain) => chain.authorId != currentUserId)
        .toList(growable: false);
    final shown = others.take(12).toList(growable: false);
    // Keep the same oldest-to-newest chain contract for every author,
    // including the signed-in user.
    final mineAll = mineChain?.moments ?? const <VoiceMoment>[];
    final mine = mineAll.isEmpty ? null : mineAll.last;
    final visibleMoments = <VoiceMoment>[
      ...?mineChain?.moments,
      for (final chain in shown) ...chain.moments,
    ];

    return MomentExpiryListTransition(
      // Expiry announcements and focus recovery must describe only avatars
      // that actually exist in the capped rail.
      moments: visibleMoments,
      clock: expiryClock ?? DateTime.now,
      transitionScope: 'mobile-home-moments',
      announcementBuilder: (count) => count == 1
          ? copy.text(
              'One Voice Moment expired and was removed from Home.',
              'Jeden Voice Moment wygasł i został usunięty ze strony głównej.',
            )
          : copy.text(
              '$count Voice Moments expired and were removed from Home.',
              '$count Voice Moments wygasło i zostało usuniętych ze strony głównej.',
            ),
      builder: (context, recoveryFocus, tileFocusNode) {
        final yours = _MomentBubble(
          expandedLabel: expandedLabels,
          key: const ValueKey('home-your-moment'),
          // This avatar always exists, even when the last own Moment expires.
          // It is the visible, actionable recovery target for the whole rail.
          focusNode: recoveryFocus,
          label: copy.homeYou,
          userId: profile?.uid ?? currentUserId,
          // The profile is authoritative. A Moment's denormalized photo can
          // be older than a newly saved avatar.
          photoUrl: profile?.photoUrl,
          mediaRevision: profile?.profileUpdatedAt,
          displayName: profile?.displayName,
          showAdd: true,
          // A real count of YOUR live Moments — the chain badge.
          count: mineAll.length > 1 ? mineAll.length : null,
          semanticLabel: mine == null
              ? copy.text(
                  'Record your first Voice Moment',
                  'Nagraj swój pierwszy Voice Moment',
                )
              : (mineAll.length > 1
                    ? copy.text(
                        'Play your ${mineAll.length} Voice Moments',
                        'Odtwórz swoje Voice Moments (${mineAll.length})',
                      )
                    : copy.text(
                        'Play your Voice Moment',
                        'Odtwórz swój Voice Moment',
                      )),
          onTap: mine == null
              ? onCreateMoment
              : (onOpenChain != null
                    ? () => onOpenChain!(mineAll)
                    : () => onOpenMoment(mine)),
          onAddTap: onCreateMoment,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // This is a story rail, not an empty-state card. The signed-in
            // avatar is always first; every other avatar proves that person
            // has an active Voice Moment the viewer can open.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (focused) {
                      if (!focused) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final target = recoveryFocus.context;
                        if (target == null ||
                            !target.mounted ||
                            !recoveryFocus.hasFocus) {
                          return;
                        }
                        // The expired author can be far along a scrolled
                        // rail. Recovery must reveal the actual own action,
                        // not merely move keyboard focus offscreen. Jumping
                        // avoids motion and respects Reduce Motion as well.
                        Scrollable.ensureVisible(target);
                      });
                    },
                    child: ListenableBuilder(
                      listenable: recoveryFocus,
                      child: yours,
                      builder: (context, child) => DecoratedBox(
                        key: const ValueKey('home-own-moment-focus-outline'),
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            width: 2,
                            color: recoveryFocus.hasFocus
                                ? context.appPalette.focus
                                : Colors.transparent,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                  for (final chain in shown) ...[
                    const SizedBox(width: 12),
                    _MomentBubble(
                      expandedLabel: expandedLabels,
                      key: ValueKey('home-moment-${chain.moments.last.id}'),
                      focusNode: tileFocusNode(chain.moments.last.id),
                      label: chain.authorName,
                      userId: chain.authorId,
                      photoUrl: chain.authorPhotoUrl,
                      displayName: chain.authorName,
                      semanticLabel: chain.length == 1
                          ? copy.text(
                              'Play Voice Moment from ${chain.authorName}',
                              'Odtwórz Voice Moment użytkownika ${chain.authorName}',
                            )
                          : copy.text(
                              'Play ${chain.length} Voice Moments from ${chain.authorName}',
                              'Odtwórz ${chain.length} Voice Moments użytkownika ${chain.authorName}',
                            ),
                      onTap: onOpenChain == null
                          ? () => onOpenMoment(chain.moments.last)
                          : () => onOpenChain!(chain.moments),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MomentBubble extends StatelessWidget {
  const _MomentBubble({
    required this.label,
    required this.onTap,
    this.userId,
    this.photoUrl,
    this.mediaRevision,
    this.displayName,
    this.showAdd = false,
    this.count,
    this.semanticLabel,
    this.onAddTap,
    this.focusNode,
    this.expandedLabel = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? userId;
  final String? photoUrl;
  final Object? mediaRevision;
  final String? displayName;
  final bool showAdd;
  final bool expandedLabel;

  /// A real chain count (own live Moments); null hides the badge.
  final int? count;

  /// What the bubble DOES, for a screen reader — "Your Moment" names the
  /// tile, it does not say whether tapping plays or records.
  final String? semanticLabel;

  /// The plus badge's own action. Without it the badge inherits [onTap],
  /// which is right for a person who has never posted and wrong for one
  /// who has.
  final VoidCallback? onAddTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    // The own tile reserves a separate 44px + target beside the main
    // playback target; shrinking that hit area over the avatar's centre
    // makes an ordinary "play mine" tap record instead.
    final tileWidth = showAdd
        ? (enlargedText ? 118.0 : 94.0)
        : expandedLabel
        ? (enlargedText ? 180.0 : 128.0)
        : (enlargedText ? 104.0 : 64.0);
    return Semantics(
      button: true,
      // Followed-author tiles are one atomic action. The own tile keeps
      // descendants because its nested plus exposes a separate record action.
      excludeSemantics: !showAdd,
      label: semanticLabel ?? label,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: tileWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: tileWidth,
                height: MobileMomentsStrip._tile,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.surfaceSunken,
                          ),
                          child: UserAvatar(
                            radius: MobileMomentsStrip._tile / 2 - 9,
                            userId: userId,
                            photoUrl: photoUrl,
                            mediaRevision: mediaRevision,
                            displayName: displayName,
                            fallbackIcon: Icons.person_rounded,
                          ),
                        ),
                      ),
                    ),
                    if (count != null)
                      Positioned(
                        left: (tileWidth - 64) / 2,
                        top: -3,
                        child: Container(
                          key: const ValueKey('home-your-moment-count'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.secondary],
                            ),
                            border: Border.all(
                              color: palette.surfaceSunken,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (showAdd)
                      Positioned(
                        right: enlargedText ? 6 : 0,
                        bottom: 0,
                        child: _AddMomentBadge(
                          onTap: onAddTap,
                          child: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                              border: Border.all(
                                color: palette.surfaceSunken,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: enlargedText || expandedLabel ? 2 : 1,
                overflow: enlargedText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plus on your own bubble. A nested tap target inside the bubble's
/// InkWell: the innermost recognizer wins, so the badge means "record"
/// while the rest of the bubble means "play mine".
class _AddMomentBadge extends StatelessWidget {
  const _AddMomentBadge({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: copy.text('Record a Voice Moment', 'Nagraj Voice Moment'),
      child: InkWell(
        key: const ValueKey('home-record-moment'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(alignment: Alignment.bottomRight, child: child),
        ),
      ),
    );
  }
}

/// `Live around you` — a swipeable rail of compact room cards.
class MobileLiveRail extends StatelessWidget {
  const MobileLiveRail({
    required this.rooms,
    required this.onOpenRoom,
    required this.onSeeAll,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final ValueChanged<VoiceRoom> onOpenRoom;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two cards and a peek of the third, whatever the viewport is —
        // never a hard-coded card width.
        final cardWidth = (constraints.maxWidth - 22) / 2.35;
        final cover = cardWidth - 20;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MobileSectionHeader(
              title: copy.text('Live around you', 'Na żywo w pobliżu'),
              live: true,
              onSeeAll: onSeeAll,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final room in rooms.take(8)) ...[
                    if (room != rooms.first) const SizedBox(width: 11),
                    _MobileRoomCard(
                      room: room,
                      width: cardWidth,
                      cover: cover,
                      onTap: () => onOpenRoom(room),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileRoomCard extends StatelessWidget {
  const _MobileRoomCard({
    required this.room,
    required this.width,
    required this.cover,
    required this.onTap,
  });

  final VoiceRoom room;
  final double width;
  final double cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: copy.text(
        '${room.name}, live, ${room.participantCount} listening',
        '${room.name}, na żywo, liczba uczestników: ${room.participantCount}',
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: palette.surface,
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  // The SAME cover widget desktop uses: identical
                  // imageUrl handling and branded gradient fallback.
                  RoomVisual(room: room, size: cover, radius: 12),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.black.withValues(alpha: .55),
                      ),
                      child: Text(
                        copy.text('LIVE', 'NA ŻYWO'),
                        style: const TextStyle(
                          color: Color(0xFFFF7A93),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 11,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${room.participantCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact `Voice Trending`: two live moments, up to two creators.
class MobileVoiceTrending extends StatelessWidget {
  const MobileVoiceTrending({
    required this.rooms,
    required this.creators,
    required this.onOpenRoom,
    required this.onOpenCreator,
    required this.onSeeAll,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final List<FollowUser> creators;
  final ValueChanged<VoiceRoom> onOpenRoom;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final live = rooms.take(2).toList(growable: false);
    final people = creators.take(2).toList(growable: false);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copy.text('Voice Trending', 'Popularne teraz'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _MiniLabel(copy.text('Trending Moments', 'Popularne Momenty')),
          const SizedBox(height: 6),
          if (live.isEmpty)
            _MiniNote(
              copy.text(
                'No one is live right now.',
                'Nikt nie nadaje teraz na żywo.',
              ),
            )
          else
            for (final room in live)
              _MiniRow(
                title: room.name,
                subtitle: room.description,
                trailing: const _MiniLivePill(),
                leading: RoomVisual(room: room, size: 34, radius: 10),
                onTap: () => onOpenRoom(room),
              ),
          const SizedBox(height: 12),
          _MiniLabel(copy.text('People to Follow', 'Osoby warte obserwowania')),
          const SizedBox(height: 6),
          if (people.isEmpty)
            _MiniNote(
              copy.text(
                'No suggestions right now.',
                'Brak propozycji na ten moment.',
              ),
            )
          else
            for (final person in people)
              _MiniRow(
                title: person.displayName,
                titleBadge: UserIdentityBadges(
                  uid: person.uid,
                  variant: IdentityBadgeVariant.icon,
                ),
                subtitle: person.username.isEmpty
                    ? copy.text('On YO Voice', 'W YO Voice')
                    : '@${person.username}',
                leading: UserAvatar(
                  radius: 17,
                  userId: person.uid,
                  photoUrl: person.photoUrl,
                  displayName: person.displayName,
                ),
                onTap: () => onOpenCreator(person),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: colors.primary,
              ),
              child: Text(
                copy.text('See all', 'Zobacz wszystkie'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.appPalette.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _MiniNote extends StatelessWidget {
  const _MiniNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(color: context.appPalette.textTertiary, fontSize: 11.5),
    ),
  );
}

class _MiniLivePill extends StatelessWidget {
  const _MiniLivePill();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.primaryContainer,
      ),
      child: Text(
        copy.text('Live', 'Na żywo'),
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
    this.trailing,
    this.titleBadge,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final Widget? trailing;
  final VoidCallback onTap;

  /// Identity badges rendered beside the title when the row is a person.
  final Widget? titleBadge;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (titleBadge != null) ...[
                        const SizedBox(width: 4),
                        titleBadge!,
                      ],
                    ],
                  ),
                  if (subtitle.trim().isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Premium, mobile-shaped: benefits wrap instead of forcing three
/// columns into a phone, then the existing plans action.
class MobilePremiumCard extends StatelessWidget {
  const MobilePremiumCard({required this.onCheckPlans, super.key});

  final VoidCallback onCheckPlans;

  static const _icons = [
    (Icons.mic_rounded, Color(0xFFD3A5FF)),
    (Icons.workspace_premium_rounded, Color(0xFFFFC24D)),
    (Icons.auto_awesome_rounded, Color(0xFFE879F9)),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < PremiumPlans.benefits.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Icon(_icons[i].$1, size: 20, color: _icons[i].$2),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        copy.text(
                          PremiumPlans.benefits[i].$1,
                          const [
                            'Zostań twórcą',
                            'Twórz własne kluby',
                            'Wyróżnij się',
                          ][i],
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        copy.text(
                          PremiumPlans.benefits[i].$2,
                          const [
                            'Odblokuj pełne narzędzia dla twórców',
                            'Buduj przestrzenie dla swojej społeczności',
                            'Zyskaj wygląd Premium w całym YO Voice',
                          ][i],
                        ),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          YoButton(
            key: const ValueKey('home-premium-check-plans'),
            label: copy.text('Check plans  ›', 'Zobacz plany  ›'),
            onPressed: onCheckPlans,
            height: 48,
          ),
        ],
      ),
    );
  }
}

/// `Top creators you follow`, as compact rows.
class MobileTopCreators extends StatelessWidget {
  const MobileTopCreators({
    required this.creators,
    required this.onOpenCreator,
    required this.onViewAll,
    super.key,
  });

  final List<FollowUser> creators;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  copy.text(
                    'Top creators you follow',
                    'Najpopularniejsi obserwowani twórcy',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (creators.isNotEmpty)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: colors.primary,
                  ),
                  child: Text(
                    copy.text('View all', 'Zobacz wszystkie'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (creators.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              copy.text(
                'You are not following anyone yet.',
                'Nie obserwujesz jeszcze żadnych osób.',
              ),
              style: TextStyle(color: palette.textTertiary, fontSize: 11.5),
            ),
          ] else
            for (final creator in creators.take(4))
              _MiniRow(
                title: creator.displayName,
                titleBadge: UserIdentityBadges(
                  uid: creator.uid,
                  variant: IdentityBadgeVariant.icon,
                ),
                subtitle: creator.username.isEmpty
                    ? copy.text('On YO Voice', 'W YO Voice')
                    : '@${creator.username}',
                leading: UserAvatar(
                  radius: 17,
                  userId: creator.uid,
                  photoUrl: creator.photoUrl,
                  displayName: creator.displayName,
                ),
                onTap: () => onOpenCreator(creator),
              ),
        ],
      ),
    );
  }
}
