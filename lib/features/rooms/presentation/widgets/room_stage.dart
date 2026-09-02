import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The shared room stage system — pure, data-driven widgets used by every
/// room family (Community, Family, Club, Podcast) and the screenshot
/// harness.
///
/// Design contract (the scalability rule): the STAGE renders only people
/// with a reason to be looked at — host, moderators, speakers — in a calm
/// grid that never grows past [StageGrid.maxTiles]. The audience is a
/// compact strip and a drawer, never floating avatars. A room with 500
/// listeners paints exactly as many stage tiles as a room with 5.
class StageSpeaker {
  const StageSpeaker({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    this.isHost = false,
    this.isModerator = false,
    this.isMuted = false,
    this.isSpeaking = false,
    this.audioLevel = 0,
    this.roleLabel,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final bool isHost;
  final bool isModerator;
  final bool isMuted;
  final bool isSpeaking;

  /// 0..1, already smoothed by the caller. Drives the ring and glow only —
  /// no constant motion when nobody talks.
  final double audioLevel;
  final String? roleLabel;
}

/// Responsive room workspace shared by every live-room family.
///
/// Desktop (>= [desktopBreakpoint] of usable width) keeps the voice stage
/// readable on the left and gives chat a permanent, bounded rail on the
/// right. Compact layouts keep the stage mounted and present chat as a
/// bounded bottom dock. The dock can be dismissed and reopened without
/// turning the whole room into a chat-only screen.
class RoomWorkspace extends StatelessWidget {
  const RoomWorkspace({
    required this.stage,
    required this.chat,
    required this.showCompactChat,
    this.desktopBreakpoint = 1100,
    super.key,
  });

  final Widget stage;
  final Widget chat;
  final bool showCompactChat;
  final double desktopBreakpoint;

  /// Kept in lockstep with [desktopBreakpoint]: the chat rail earns its
  /// place only when the stage still gets a generous column beside it —
  /// a tablet is never a squeezed desktop.
  static bool usesDesktopLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= desktopBreakpoint;
        if (!desktop) {
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : 720.0;
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          // Keep the conversation present without letting accessibility text
          // turn the room into a chat-only screen. The dock itself scrolls, so
          // a shorter bounded surface is more useful than hiding the stage.
          final chatHeight = textScale >= 1.75
              ? (availableHeight * .36).clamp(230.0, 300.0)
              : textScale >= 1.35
              ? (availableHeight * .42).clamp(240.0, 330.0)
              : (availableHeight * .46).clamp(220.0, 380.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: KeyedSubtree(
                    key: const ValueKey('room-stage-pane'),
                    child: stage,
                  ),
                ),
                if (showCompactChat)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SizedBox(
                        key: const ValueKey('room-compact-chat-dock'),
                        width: double.infinity,
                        height: chatHeight,
                        child: KeyedSubtree(
                          key: const ValueKey('room-chat-pane'),
                          child: chat,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey('room-stage-pane'),
                      child: stage,
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 350,
                    child: KeyedSubtree(
                      key: const ValueKey('room-chat-pane'),
                      child: chat,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One person on stage: an avatar-forward hero card with an accent ring, a
/// soft glow and a subtle pulse ONLY while genuinely speaking (bound to
/// the real LiveKit speaking state), a mic badge, the name with the real
/// identity badges and a role line. No idle animation — a silent stage is
/// a still stage.
class SpeakerTile extends StatefulWidget {
  const SpeakerTile({
    required this.speaker,
    required this.identity,
    this.avatarRadius = 30,
    this.onTap,
    super.key,
  });

  final StageSpeaker speaker;
  final SpaceIdentity identity;

  /// Larger when the stage holds only one or two people, so a lone host
  /// reads as the hero rather than a tiny card in an empty panel.
  final double avatarRadius;
  final VoidCallback? onTap;

  @override
  State<SpeakerTile> createState() => _SpeakerTileState();
}

class _SpeakerTileState extends State<SpeakerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also the FIRST sync: initState cannot read MediaQuery, and the
    // reduced-motion flag lives there.
    _syncPulse();
  }

  @override
  void didUpdateWidget(SpeakerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  /// The pulse runs on exactly one condition: this person is genuinely
  /// speaking right now AND the platform has not asked for reduced motion.
  /// The static cues (ring width, glow, the equaliser chip glyph) carry the
  /// state on their own, so honouring `disableAnimations` costs nothing.
  void _syncPulse() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.speaker.isSpeaking && !reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final speaker = widget.speaker;
    final identity = widget.identity;
    final accent = identity.primary;
    final ringStrength = speaker.isSpeaking
        ? (.45 + .55 * speaker.audioLevel)
        : 0.0;

    return Semantics(
      button: widget.onTap != null,
      excludeSemantics: widget.onTap != null,
      label: widget.onTap == null
          ? null
          : copy.text(
              '${speaker.displayName}, '
                  '${speaker.isHost
                      ? 'host'
                      : speaker.isModerator
                      ? 'moderator'
                      : (speaker.roleLabel ?? 'speaker').toLowerCase()}, '
                  '${speaker.isMuted
                      ? 'muted'
                      : speaker.isSpeaking
                      ? 'speaking'
                      : 'not speaking'}. Open profile',
              '${speaker.displayName}, '
                  '${speaker.isHost
                      ? 'gospodarz'
                      : speaker.isModerator
                      ? 'moderator'
                      : 'mówca'}, '
                  '${speaker.isMuted
                      ? 'wyciszony'
                      : speaker.isSpeaking
                      ? 'mówi'
                      : 'nie mówi'}. Otwórz profil',
            ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          decoration: BoxDecoration(
            color: identity.surface.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: speaker.isSpeaking
                  ? accent.withValues(alpha: .4 + .4 * speaker.audioLevel)
                  : Colors.white.withValues(alpha: .06),
              width: speaker.isSpeaking ? 1.5 : 1,
            ),
            boxShadow: speaker.isSpeaking
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .3 * ringStrength),
                      blurRadius: 26,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => Transform.scale(
                      scale: speaker.isSpeaking ? 1 + .022 * _pulse.value : 1,
                      child: child,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: speaker.isSpeaking
                              ? accent
                              : accent.withValues(alpha: .32),
                          width: speaker.isSpeaking ? 2.2 : 1.4,
                        ),
                        boxShadow: speaker.isSpeaking
                            ? [
                                BoxShadow(
                                  color: accent.withValues(
                                    alpha: .35 * ringStrength,
                                  ),
                                  blurRadius: 18,
                                ),
                              ]
                            : null,
                      ),
                      child: UserAvatar(
                        radius: widget.avatarRadius,
                        userId: speaker.userId,
                        photoUrl: speaker.photoUrl,
                        displayName: speaker.displayName,
                        // The initial-letter fallback follows the ROOM, not
                        // the app default. Without this the largest object
                        // on a Family or Club stage was a purple disc inside
                        // a green or gold room — the one element loud enough
                        // to break the room's identity. Deepened well below
                        // the accent so it reads as a surface behind a
                        // letter, never as a second accent competing with
                        // the ring and the speaking glow.
                        backgroundColor: Color.lerp(
                          accent,
                          const Color(0xFF120C1B),
                          .45,
                        )!,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: speaker.isMuted
                            ? const Color(0xFF3A3151)
                            : accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0D0813),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        speaker.isMuted
                            ? Icons.mic_off_rounded
                            // The equaliser glyph while GENUINELY speaking
                            // is the non-color cue: without it the accent
                            // ring and glow were the only signal, invisible
                            // to anyone who cannot rely on hue.
                            : speaker.isSpeaking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                        size: 10,
                        // White fails 2.0-2.25:1 on the emerald and gold
                        // accents (same measurement as the dock), so the
                        // glyph follows the chip fill's brightness.
                        color:
                            ThemeData.estimateBrightnessForColor(
                                  speaker.isMuted
                                      ? const Color(0xFF3A3151)
                                      : accent,
                                ) ==
                                Brightness.light
                            ? const Color(0xFF120C1B)
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaker.isHost) ...[
                    const Icon(
                      Icons.workspace_premium_rounded,
                      size: 12,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 3),
                  ] else if (speaker.isModerator) ...[
                    const Icon(
                      Icons.shield_rounded,
                      size: 11,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      speaker.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // The tile is the app's narrowest identity surface: the
                  // official role (and VIP) shrink to icon dots with the
                  // full label in the tooltip — compact, never hidden.
                  const SizedBox(width: 4),
                  UserIdentityBadges(
                    uid: speaker.userId,
                    variant: IdentityBadgeVariant.icon,
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                speaker.isHost
                    ? copy.text('Host', 'Gospodarz')
                    : speaker.isModerator
                    ? 'Moderator'
                    : speaker.roleLabel ?? copy.text('Speaker', 'Mówca'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .45),
                  fontSize: 10,
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

/// The calm stage: at most [maxTiles] speaker tiles in a centered wrap —
/// host first, then moderators, then whoever is actually speaking, then
/// the rest. Overflow becomes a "+N on stage" tile that opens the People
/// drawer. With one or two people the tiles grow, so a lone host is the
/// hero rather than a lost thumbnail.
class StageGrid extends StatelessWidget {
  const StageGrid({
    required this.speakers,
    required this.identity,
    required this.onOverflowTap,
    this.onSpeakerTap,
    this.maxTiles = 8,
    this.roomy = false,
    super.key,
  });

  /// The stage was given the column's leftover height, so a small cast can
  /// afford to be larger. Purely presentational: the tile COUNT, ordering
  /// and overflow behaviour are identical either way, so a crowded stage
  /// still packs the same tiles at the same size.
  final bool roomy;

  final List<StageSpeaker> speakers;
  final SpaceIdentity identity;
  final VoidCallback onOverflowTap;
  final void Function(StageSpeaker speaker)? onSpeakerTap;
  final int maxTiles;

  List<StageSpeaker> get _ordered {
    final sorted = [...speakers]
      ..sort((a, b) {
        int rank(StageSpeaker s) => s.isHost
            ? 0
            : s.isModerator
            ? 1
            : s.isSpeaking
            ? 2
            : 3;
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final overflow = ordered.length - maxTiles;
    final visible = overflow > 0
        ? ordered.take(maxTiles - 1).toList()
        : ordered;
    final few = ordered.length <= 2 && overflow <= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;
        // A filling stage with one or two speakers gets a wider tile and a
        // bigger avatar, so the host reads as the room's centre rather than
        // a small card marooned in a tall panel.
        final tileWidth = few
            ? ((constraints.maxWidth - 10) / 2).clamp(
                roomy ? 210.0 : 158.0,
                roomy ? 300.0 : 230.0,
              )
            : ((constraints.maxWidth - (columns - 1) * 10) / columns).clamp(
                132.0,
                190.0,
              );
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final speaker in visible)
              SizedBox(
                width: tileWidth,
                child: SpeakerTile(
                  speaker: speaker,
                  identity: identity,
                  avatarRadius: few ? (roomy ? 54 : 40) : 30,
                  onTap: onSpeakerTap == null
                      ? null
                      : () => onSpeakerTap!(speaker),
                ),
              ),
            if (overflow > 0)
              SizedBox(
                width: tileWidth,
                child: _OverflowTile(
                  count: overflow + 1,
                  identity: identity,
                  onTap: onOverflowTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OverflowTile extends StatelessWidget {
  const _OverflowTile({
    required this.count,
    required this.identity,
    required this.onTap,
  });

  final int count;
  final SpaceIdentity identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final accent = identity.primary;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: copy.text(
        '$count more people on stage. Open everyone',
        '$count dodatkowych osób na scenie. Otwórz pełną listę',
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          decoration: BoxDecoration(
            color: identity.surface.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .14),
                  border: Border.all(color: accent.withValues(alpha: .4)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$count',
                  style: const TextStyle(
                    // Measured 3.25:1 as accent-on-dark at this size — small
                    // text needs 4.5:1, so the number is white and the
                    // accent stays on the chip wash and border around it.
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                copy.text('On stage', 'Na scenie'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                copy.text('View all', 'Zobacz wszystkich'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .45),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The audience as a compact strip: headphones icon, up to six REAL
/// participant avatars overlapping, a "+N" chip when more are listening,
/// the live count and a chevron into the existing People surface. This is
/// the ONLY place listeners appear outside the drawer — never as floating
/// orbit avatars, never as a tall empty box.
class AudienceStrip extends StatelessWidget {
  const AudienceStrip({
    required this.count,
    required this.identity,
    required this.onTap,
    this.previewPhotoUrls = const [],
    this.previewNames = const [],
    this.previewUserIds = const [],
    super.key,
  });

  final int count;
  final SpaceIdentity identity;
  final VoidCallback onTap;

  /// REAL participant data from the roster stream — up to six are shown.
  final List<String?> previewPhotoUrls;
  final List<String> previewNames;
  final List<String> previewUserIds;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final accent = identity.primary;
    final previews = previewPhotoUrls.take(6).toList();
    final more = count - previews.length;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: copy.text(
        '$count listening. Open people',
        '$count słucha. Otwórz listę osób',
      ),
      child: Material(
        key: ValueKey('room-listeners-${identity.kind.name}'),
        color: const Color(0xFF0D0813).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .06)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showLabel = constraints.maxWidth >= 420;
                return Row(
                  children: [
                    Icon(Icons.headphones_rounded, color: accent, size: 19),
                    if (showLabel) ...[
                      const SizedBox(width: 9),
                      Text(
                        copy.text('Audience', 'Publiczność'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                    if (previews.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 26.0 + 15.0 * (previews.length - 1),
                        height: 26,
                        child: Stack(
                          children: [
                            for (var i = previews.length - 1; i >= 0; i--)
                              Positioned(
                                left: 15.0 * i,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0D0813),
                                      width: 2,
                                    ),
                                  ),
                                  child: UserAvatar(
                                    radius: 11,
                                    userId: i < previewUserIds.length
                                        ? previewUserIds[i]
                                        : null,
                                    photoUrl: previews[i],
                                    displayName: i < previewNames.length
                                        ? previewNames[i]
                                        : null,
                                    // Same rule as the stage and the header:
                                    // a letter fallback wears the room's
                                    // colour, so a gold room's audience is
                                    // not a row of purple discs.
                                    backgroundColor: Color.lerp(
                                      accent,
                                      const Color(0xFF120C1B),
                                      .45,
                                    )!,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (more > 0) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '+$more',
                            style: const TextStyle(
                              // Same rule as the stage overflow tile: the
                              // wash carries the identity, the small number
                              // itself must clear 4.5:1, which the violet
                              // variant missed (4.24:1 measured).
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        count == 1
                            ? copy.text('1 listening', '1 osoba słucha')
                            : copy.text(
                                '$count listening',
                                '$count osób słucha',
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: previews.isEmpty ? 1 : .75,
                          ),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (previews.isEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        copy.text('People', 'Osoby'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .8),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    Icon(Icons.chevron_right_rounded, color: accent, size: 19),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A bounded stage surface shared by Community, Podcast, Club and Family:
/// a subtle dark panel with one quiet border, the "On stage" header with
/// the waveform icon and the live speaker count, and the speaker cards as
/// the heroes. The product logic stays in each room screen; this
/// component only keeps hierarchy, spacing and participant density
/// consistent.
class RoomStagePanel extends StatelessWidget {
  const RoomStagePanel({
    required this.speakers,
    required this.identity,
    required this.onOverflowTap,
    this.onSpeakerTap,
    this.fill = false,
    this.title = 'On stage',
    this.emptyMessage = 'The stage is ready for the first voice.',
    this.icon = Icons.graphic_eq_rounded,
    super.key,
  });

  final List<StageSpeaker> speakers;
  final SpaceIdentity identity;
  final VoidCallback onOverflowTap;
  final void Function(StageSpeaker speaker)? onSpeakerTap;

  /// Take the height the parent offers instead of hugging the speakers.
  ///
  /// A stage is the room's centre of gravity, so on a desktop column it
  /// should OWN the space left between the hero and the audience strip
  /// rather than leaving a dead band underneath — the defect the operator
  /// described as "a huge stage container with a tiny user card in the
  /// middle". Filling also lets the speakers sit optically centred, which
  /// is what makes one host read as deliberate rather than stranded.
  ///
  /// Off by default: on a narrow screen the panel is one card in a scroll
  /// view, and an unbounded-height parent would have nothing to give it.
  final bool fill;
  final String title;
  final String emptyMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final resolvedTitle = copy.isPolish && title == 'On stage'
        ? 'Na scenie'
        : title;
    final resolvedEmptyMessage =
        copy.isPolish &&
            emptyMessage == 'The stage is ready for the first voice.'
        ? 'Scena czeka na pierwszy głos.'
        : emptyMessage;
    return Container(
      key: ValueKey('room-stage-${identity.kind.name}'),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0813).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: identity.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resolvedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: identity.wash,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${speakers.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (fill)
            Expanded(
              child: Center(child: _speakerArea(context, resolvedEmptyMessage)),
            )
          else
            _speakerArea(context, resolvedEmptyMessage),
        ],
      ),
    );
  }

  Widget _speakerArea(BuildContext context, String resolvedEmptyMessage) {
    if (speakers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: Text(
            resolvedEmptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              height: 1.35,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: StageGrid(
        speakers: speakers,
        identity: identity,
        roomy: fill,
        onOverflowTap: onOverflowTap,
        onSpeakerTap: onSpeakerTap,
      ),
    );
  }
}
