import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Two real routes, with no permission request or room connection on Home.
class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({
    required this.onCreateRoom,
    required this.onFriends,
    super.key,
  });

  final VoidCallback onCreateRoom;
  final VoidCallback onFriends;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 350 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final create = _QuickAction(
          key: const ValueKey('home-quick-create-room'),
          icon: Icons.add_rounded,
          title: copy.homeCreateRoom,
          subtitle: copy.homeStartConversation,
          onTap: onCreateRoom,
        );
        final friends = _QuickAction(
          key: const ValueKey('home-quick-friends'),
          icon: Icons.person_add_alt_1_rounded,
          title: copy.friends,
          subtitle: copy.homeGrowYourCircle,
          onTap: onFriends,
        );
        return stacked
            ? Column(children: [create, const SizedBox(height: 10), friends])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: create),
                  const SizedBox(width: 12),
                  Expanded(child: friends),
                ],
              );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return _FocusOutline(
      radius: 19,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: palette.interactiveForeground,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
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
          ),
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
  const _FocusOutline({required this.child, required this.radius});
  final Widget child;
  final double radius;
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
          color: _focused ? context.appPalette.focus : Colors.transparent,
        ),
      ),
      child: widget.child,
    ),
  );
}
