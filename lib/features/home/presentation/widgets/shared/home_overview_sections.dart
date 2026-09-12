import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Two real routes, with no permission request or room connection on Home.
///
/// One 44 px pill row rather than two 66 px cards: the routes are the same
/// (`home-quick-create-room`, `home-quick-friends`), the former subtitles
/// survive as tooltips, and Home gives the space back to people and rooms.
class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({
    required this.onCreateRoom,
    required this.onFriends,
    this.createRoomKey,
    super.key,
  });

  final VoidCallback onCreateRoom;
  final VoidCallback onFriends;

  /// The guided tour's mobile Create anchor. Attached to the create pill's
  /// box (not its ink) so the spotlight frames the whole control; null when
  /// no tour can run over this instance.
  final GlobalKey? createRoomKey;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final style = Theme.of(context).textTheme.labelLarge!;
        double labelWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        // Layout follows the actual localized labels, not a blanket text-
        // scale switch: a wide column can still keep both actions at 200%.
        final minimumActionWidth =
            (labelWidth(copy.homeCreateRoom) > labelWidth(copy.friends)
                ? labelWidth(copy.homeCreateRoom)
                : labelWidth(copy.friends)) +
            (AppRhythm.title * 2) +
            20 +
            AppRhythm.tight;
        final stacked =
            constraints.maxWidth < minimumActionWidth * 2 + AppRhythm.item;
        // Filled primary controls take their `onPrimary` foreground as the
        // 2 px keyboard boundary (UI.md); the neutral pill keeps `focus`.
        final createPill = _FocusOutline(
          radius: 999,
          color: colors.onPrimary,
          child: Tooltip(
            message: copy.homeStartConversation,
            child: FilledButton.icon(
              key: const ValueKey('home-quick-create-room'),
              onPressed: onCreateRoom,
              style: FilledButton.styleFrom(
                // Shrink-wrapped: Material otherwise inflates the LAYOUT
                // box to 48 px around a 44 px control, and those two
                // invisible pixels turned Home's declared 12 px gap into a
                // measured 14. The 44 px target is the `minimumSize`.
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                minimumSize: const Size(0, AppSizing.minimumTouchTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppRhythm.title,
                  vertical: AppRhythm.tight,
                ),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(copy.homeCreateRoom, textAlign: TextAlign.center),
            ),
          ),
        );
        final create = createRoomKey == null
            ? createPill
            : KeyedSubtree(key: createRoomKey, child: createPill);
        final friends = _FocusOutline(
          radius: 999,
          child: Tooltip(
            message: copy.homeGrowYourCircle,
            child: OutlinedButton.icon(
              key: const ValueKey('home-quick-friends'),
              onPressed: onFriends,
              style: OutlinedButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                minimumSize: const Size(0, AppSizing.minimumTouchTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppRhythm.title,
                  vertical: AppRhythm.tight,
                ),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              label: Text(copy.friends, textAlign: TextAlign.center),
            ),
          ),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  create,
                  const SizedBox(height: AppRhythm.item),
                  friends,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: create),
                  const SizedBox(width: AppRhythm.item),
                  Expanded(child: friends),
                ],
              );
      },
    );
  }
}

/// A genuine empty room directory is an invitation, not a blank live hero.
/// The two actions remain the same shell routes; displaying this card does
/// not create a room, join audio, or request microphone permission.
class HomeConversationInvitation extends StatelessWidget {
  const HomeConversationInvitation({
    required this.actions,
    this.onDiscover,
    super.key,
  });

  final Widget actions;

  /// The room directory. Needed here because the dock no longer carries a
  /// Rooms destination: without this link an account with nothing live and
  /// no friends has no way from Home to the rooms other people are in.
  final VoidCallback? onDiscover;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final onDiscover = this.onDiscover;
    return DecoratedBox(
      key: const ValueKey('home-conversation-invitation'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.homeInvitationHeadline,
              style: AppTypography.headlineMedium.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: AppRhythm.hairline),
            Text(
              copy.homeInvitationBody,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppRhythm.title),
            actions,
            if (onDiscover != null) ...[
              const SizedBox(height: AppRhythm.tight),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('home-invitation-discover'),
                  onPressed: onDiscover,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      AppSizing.minimumTouchTarget,
                      AppSizing.minimumTouchTarget,
                    ),
                    visualDensity: VisualDensity.standard,
                    foregroundColor: palette.interactiveForeground,
                  ),
                  child: Text(copy.homeDiscoverRooms),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A quiet recap of actual playable followed Moments. Input is relationship-
/// gated by the caller's existing subscription; this widget never reads data
/// or invents online/presence state. Own Moments remain in the avatar rail.
class HomeCircleActivity extends StatefulWidget {
  const HomeCircleActivity({
    required this.moments,
    required this.currentUserId,
    required this.onOpenMoment,
    required this.onFriends,
    this.onOpenChain,
    this.expiryClock,
    super.key,
  });

  final List<VoiceMoment> moments;
  final String currentUserId;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final ValueChanged<List<VoiceMoment>>? onOpenChain;
  final VoidCallback onFriends;
  final DateTime Function()? expiryClock;

  @override
  State<HomeCircleActivity> createState() => _HomeCircleActivityState();
}

class _HomeCircleActivityState extends State<HomeCircleActivity> {
  // Nodes belong to MomentExpiryListTransition, not to this observer.
  final Map<String, FocusNode> _visibleFocusNodes = {};
  bool _showEmptyRecovery = false;

  List<MomentChain> _chains(HomeCircleActivity configuration) =>
      buildMomentChains(
        configuration.moments
            .where(
              (moment) =>
                  moment.hasMediaReference &&
                  moment.authorId != configuration.currentUserId,
            )
            .toList(),
      ).take(2).toList(growable: false);

  @override
  void didUpdateWidget(covariant HomeCircleActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chains = _chains(widget);
    final ids = {
      for (final chain in chains)
        for (final moment in chain.moments) moment.id,
    };
    final now = (widget.expiryClock ?? DateTime.now)();
    if (chains.isNotEmpty) _showEmptyRecovery = false;
    if (chains.isEmpty &&
        oldWidget.moments.any(
          (moment) =>
              !ids.contains(moment.id) &&
              !moment.isActiveAt(now) &&
              (_visibleFocusNodes[moment.id]?.hasFocus ?? false),
        )) {
      // A real, visible route replaces the last focused row. Fresh empty
      // circles remain absent; keyboard recovery never targets an invisible box.
      _showEmptyRecovery = true;
    }
    _visibleFocusNodes.removeWhere((id, _) => !ids.contains(id));
  }

  FocusNode _rememberFocus(String id, FocusNode Function(String) resolve) =>
      _visibleFocusNodes[id] = resolve(id);

  @override
  Widget build(BuildContext context) {
    final chains = _chains(widget);
    return MomentExpiryListTransition(
      moments: [for (final chain in chains) ...chain.moments],
      clock: widget.expiryClock ?? DateTime.now,
      transitionScope: 'home-circle-activity',
      // The existing avatar rail already announces these same removals.
      announcementBuilder: (_) => '',
      builder: (context, recoveryFocus, tileFocusNode) =>
          _buildActivity(context, chains, recoveryFocus, tileFocusNode),
    );
  }

  Widget _buildActivity(
    BuildContext context,
    List<MomentChain> chains,
    FocusNode recoveryFocus,
    FocusNode Function(String) tileFocusNode,
  ) {
    if (chains.isEmpty && !_showEmptyRecovery) return const SizedBox.shrink();
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chains.isNotEmpty)
            MomentExpiryFocusTarget(
              key: const ValueKey('home-circle-expiry-heading'),
              focusNode: recoveryFocus,
              semanticLabel: copy.homeYourCircle,
              child: Text(
                copy.homeYourCircle,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (chains.isEmpty)
            _FocusOutline(
              radius: 999,
              child: OutlinedButton.icon(
                key: const ValueKey('home-circle-expiry-friends'),
                focusNode: recoveryFocus,
                onPressed: widget.onFriends,
                icon: const Icon(Icons.people_outline_rounded),
                label: Text(copy.friends),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          if (chains.isNotEmpty) ...[
            const SizedBox(height: 10),
            Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(19),
                side: BorderSide(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < chains.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, indent: 64, color: palette.border),
                    _FocusOutline(
                      radius: 12,
                      child: ListTile(
                        focusNode: _rememberFocus(
                          chains[index].moments.last.id,
                          tileFocusNode,
                        ),
                        key: ValueKey('home-circle-${chains[index].authorId}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        minVerticalPadding: 12,
                        leading: UserAvatar(
                          radius: 21,
                          userId: chains[index].authorId,
                          photoUrl: chains[index].authorPhotoUrl,
                          displayName: chains[index].authorName,
                        ),
                        title: Text(
                          chains[index].authorName,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          copy.text('Voice Moment', 'Voice Moment'),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.graphic_eq_rounded,
                          color: palette.interactiveForeground,
                          size: 22,
                        ),
                        onTap: () => widget.onOpenChain != null
                            ? widget.onOpenChain!(chains[index].moments)
                            : widget.onOpenMoment(chains[index].moments.last),
                      ),
                    ),
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

/// Loading has no fake room name, status, count or action target.
class HomeRoomsLoading extends StatelessWidget {
  const HomeRoomsLoading({super.key});
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('home-rooms-loading'),
    height: 136,
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.appPalette.border),
    ),
    alignment: Alignment.center,
    child: const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// A parent focus scope paints the boundary without stealing the native
/// control's keyboard focus or introducing a second semantic action.
class _FocusOutline extends StatefulWidget {
  const _FocusOutline({required this.child, required this.radius, this.color});
  final Widget child;
  final double radius;

  /// The boundary colour; defaults to the palette `focus` ring for neutral
  /// surfaces. A filled primary control passes its `onPrimary`.
  final Color? color;
  @override
  State<_FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<_FocusOutline> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) => setState(() => _focused = focused),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          width: 2,
          color: _focused
              ? (widget.color ?? context.appPalette.focus)
              : Colors.transparent,
        ),
      ),
      child: widget.child,
    ),
  );
}
