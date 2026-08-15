import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The Rooms 2.0 stage system — pure, data-driven widgets shared by the
/// room screens and the dev preview harness.
///
/// Design contract (the scalability rule): the STAGE renders only people
/// with a reason to be looked at — host, moderators, speakers — in a
/// calm grid that never grows past [StageGrid.maxTiles]. The audience is
/// a number and a drawer, never floating avatars. A room with 500
/// listeners renders exactly as many stage tiles as a room with 5.
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
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final bool isHost;
  final bool isModerator;
  final bool isMuted;
  final bool isSpeaking;

  /// 0..1, already smoothed by the caller. Drives the subtle ring only —
  /// no constant motion when nobody talks.
  final double audioLevel;
}

/// Room identity, painted into the stage instead of a black void: the
/// cover (or a premium gradient fallback), the topic, and — when the
/// room is quiet — a conversation prompt, so an empty stage still says
/// what this place is about.
class RoomIdentityCard extends StatelessWidget {
  const RoomIdentityCard({
    required this.roomName,
    required this.topic,
    required this.accent,
    this.imageUrl,
    this.quiet = false,
    super.key,
  });

  final String roomName;
  final String topic;
  final Color accent;
  final String? imageUrl;

  /// True when nobody is speaking — the card leans in with the topic
  /// instead of receding behind speakers.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .32),
              const Color(0xFF120B1B),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (imageUrl != null && imageUrl!.trim().isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: .34,
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                    ),
                  ),
                  if (topic.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      topic,
                      maxLines: quiet ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (quiet) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .14),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 14, color: accent),
                          const SizedBox(width: 7),
                          const Flexible(
                            child: Text(
                              "It's quiet — unmute and say hi",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One person on stage: premium tile, avatar-forward, with a
/// speaking ring that breathes with their real audio level and a small
/// role/mute badge. No idle animation — a silent stage is a still stage.
class SpeakerTile extends StatelessWidget {
  const SpeakerTile({
    required this.speaker,
    required this.accent,
    this.onTap,
    super.key,
  });

  final StageSpeaker speaker;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ringStrength =
        speaker.isSpeaking ? (.45 + .55 * speaker.audioLevel) : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF17101F).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: speaker.isSpeaking
                ? accent.withValues(alpha: .35 + .45 * speaker.audioLevel)
                : const Color(0xFF2C2138),
            width: speaker.isSpeaking ? 1.6 : 1,
          ),
          boxShadow: speaker.isSpeaking
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: .28 * ringStrength),
                    blurRadius: 22,
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: speaker.isSpeaking
                          ? accent
                          : Colors.white.withValues(alpha: .12),
                      width: speaker.isSpeaking ? 2 : 1.2,
                    ),
                  ),
                  child: UserAvatar(
                    radius: 27,
                    photoUrl: speaker.photoUrl,
                    displayName: speaker.displayName,
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: speaker.isMuted
                          ? const Color(0xFF3A2C49)
                          : accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF17101F),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      speaker.isMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (speaker.isHost) ...[
                  const Icon(
                    Icons.workspace_premium_rounded,
                    size: 12,
                    color: Color(0xFFFFC94D),
                  ),
                  const SizedBox(width: 3),
                ] else if (speaker.isModerator) ...[
                  const Icon(
                    Icons.shield_rounded,
                    size: 11,
                    color: Color(0xFF6FC3FF),
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
                      fontSize: 12,
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
            Text(
              speaker.isHost
                  ? 'Host'
                  : speaker.isModerator
                  ? 'Moderator'
                  : 'Speaker',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The calm stage: at most [maxTiles] speaker tiles in a fixed-height
/// grid — host first, then moderators, then whoever is actually
/// speaking, then the rest. Overflow becomes a "+N on stage" tile that
/// opens the People drawer. Complexity never grows with audience size.
class StageGrid extends StatelessWidget {
  const StageGrid({
    required this.speakers,
    required this.accent,
    required this.onOverflowTap,
    this.onSpeakerTap,
    this.maxTiles = 8,
    super.key,
  });

  final List<StageSpeaker> speakers;
  final Color accent;
  final VoidCallback onOverflowTap;
  final void Function(StageSpeaker speaker)? onSpeakerTap;
  final int maxTiles;

  List<StageSpeaker> get _ordered {
    final sorted = [...speakers]..sort((a, b) {
      int rank(StageSpeaker s) =>
          s.isHost ? 0 : s.isModerator ? 1 : s.isSpeaking ? 2 : 3;
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final overflow = ordered.length - maxTiles;
    final visible = overflow > 0 ? ordered.take(maxTiles - 1).toList() : ordered;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 4 : 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final speaker in visible)
              SizedBox(
                width:
                    (constraints.maxWidth - (columns - 1) * 10) / columns,
                child: SpeakerTile(
                  speaker: speaker,
                  accent: accent,
                  onTap: onSpeakerTap == null
                      ? null
                      : () => onSpeakerTap!(speaker),
                ),
              ),
            if (overflow > 0)
              SizedBox(
                width:
                    (constraints.maxWidth - (columns - 1) * 10) / columns,
                child: _OverflowTile(
                  count: overflow + 1,
                  accent: accent,
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
    required this.accent,
    required this.onTap,
  });

  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF17101F).withValues(alpha: .6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2C2138)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .14),
                border: Border.all(color: accent.withValues(alpha: .4)),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$count',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'On stage',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'View all',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .45),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The audience, as a number: a few avatars, the count, a tap into the
/// People drawer. This is the ONLY place listeners appear outside the
/// drawer — never as floating orbit avatars.
class ListenersStrip extends StatelessWidget {
  const ListenersStrip({
    required this.count,
    required this.accent,
    required this.onTap,
    this.previewPhotoUrls = const [],
    this.previewNames = const [],
    super.key,
  });

  final int count;
  final Color accent;
  final VoidCallback onTap;
  final List<String?> previewPhotoUrls;
  final List<String> previewNames;

  @override
  Widget build(BuildContext context) {
    final previews = previewPhotoUrls.take(4).toList();

    return Material(
      color: const Color(0xFF130D1C).withValues(alpha: .92),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2C2138)),
          ),
          child: Row(
            children: [
              if (previews.isEmpty)
                Icon(Icons.headphones_rounded, color: accent, size: 20)
              else
                SizedBox(
                  width: 24.0 + 16.0 * (previews.length - 1),
                  height: 26,
                  child: Stack(
                    children: [
                      for (var i = previews.length - 1; i >= 0; i--)
                        Positioned(
                          left: 16.0 * i,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF130D1C),
                                width: 2,
                              ),
                            ),
                            child: UserAvatar(
                              radius: 11,
                              photoUrl: previews[i],
                              displayName: i < previewNames.length
                                  ? previewNames[i]
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  count == 1 ? '1 listening' : '$count listening',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                'People',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              Icon(Icons.expand_less_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
