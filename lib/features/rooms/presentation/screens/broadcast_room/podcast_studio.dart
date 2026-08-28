import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_energy_wave.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The podcast's editorial identity. Unlike the shared room hero this makes
/// the episode topic the headline and the persistent show name its context.
class PodcastEpisodeHero extends StatelessWidget {
  const PodcastEpisodeHero({
    required this.room,
    required this.live,
    required this.hostName,
    required this.hostPhotoUrl,
    required this.hostId,
    required this.onStage,
    required this.speakingNow,
    required this.listeners,
    required this.energy,
    super.key,
  });

  final VoiceRoom room;
  final bool live;
  final String hostName;
  final String? hostPhotoUrl;
  final String hostId;
  final int onStage;
  final int speakingNow;
  final int listeners;
  final double energy;

  @override
  Widget build(BuildContext context) {
    final episodeTitle = room.topic.trim().isNotEmpty
        ? room.topic.trim()
        : room.name;
    final showName = room.topic.trim().isNotEmpty ? room.name : null;
    final image = room.imageUrl?.trim();

    return ClipRRect(
      key: const ValueKey('podcast-episode-hero'),
      borderRadius: BorderRadius.circular(26),
      child: Container(
        constraints: const BoxConstraints(minHeight: 214),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SpaceIdentity.podcast.primary.withValues(alpha: .34),
              const Color(0xFF230C15),
              const Color(0xFF0B0710),
            ],
          ),
          border: Border.all(
            color: SpaceIdentity.podcast.primary.withValues(alpha: .24),
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Stack(
          children: [
            if (image != null && image.isNotEmpty) ...[
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        const Color(0xFF08050D).withValues(alpha: .94),
                        const Color(0xFF1B0710).withValues(alpha: .72),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusChip(live: live),
                      _FormatChip(label: room.showFormat?.label ?? 'Live show'),
                      if (room.visibility == 'private')
                        const _FormatChip(label: 'Private'),
                    ],
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'TODAY’S EPISODE',
                    style: TextStyle(
                      color: BroadcastRoomColors.accentSoft,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    episodeTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.08,
                      letterSpacing: -.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (showName != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      showName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .66),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (room.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      room.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      UserAvatar(
                        radius: 15,
                        photoUrl: hostPhotoUrl,
                        displayName: hostName,
                        backgroundColor: const Color(0xFF7A1E34),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          'Hosted by $hostName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      UserIdentityBadges(
                        uid: hostId,
                        variant: IdentityBadgeVariant.icon,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Metric(value: '$onStage', label: 'on stage'),
                      const _MetricDivider(),
                      _Metric(value: '$speakingNow', label: 'speaking now'),
                      const _MetricDivider(),
                      _Metric(value: '$listeners', label: 'listening'),
                    ],
                  ),
                  if (live) ...[
                    const SizedBox(height: 14),
                    RoomEnergyWave(
                      energy: energy,
                      color: BroadcastRoomColors.accentSoft,
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

class PodcastProducerDesk extends StatelessWidget {
  const PodcastProducerDesk({
    required this.requests,
    required this.onStage,
    required this.stageLimit,
    required this.onRequests,
    required this.onGuests,
    required this.onSettings,
    super.key,
  });

  final int requests;
  final int onStage;
  final int stageLimit;
  final VoidCallback onRequests;
  final VoidCallback onGuests;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('podcast-producer-desk'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0813).withValues(alpha: .95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: requests > 0
              ? BroadcastRoomColors.accent.withValues(alpha: .38)
              : Colors.white.withValues(alpha: .07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: BroadcastRoomColors.wash,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: BroadcastRoomColors.accentSoft,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Producer desk',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Run the show without leaving the stage.',
                      style: TextStyle(
                        color: BroadcastRoomColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _DeskAction(
                  icon: Icons.back_hand_rounded,
                  value: '$requests',
                  label: requests == 1 ? 'request' : 'requests',
                  highlighted: requests > 0,
                  onTap: onRequests,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DeskAction(
                  icon: Icons.mic_rounded,
                  value: '$onStage/$stageLimit',
                  label: 'stage',
                  onTap: onGuests,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DeskAction(
                  icon: Icons.settings_rounded,
                  value: 'Edit',
                  label: 'show',
                  onTap: onSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PodcastListenerStatus extends StatelessWidget {
  const PodcastListenerStatus({
    required this.onStage,
    required this.handRaised,
    required this.requestsEnabled,
    super.key,
  });

  final bool onStage;
  final bool handRaised;
  final bool requestsEnabled;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = onStage
        ? (
            Icons.mic_rounded,
            'You’re on stage',
            'Your microphone control is in the dock below.',
          )
        : handRaised
        ? (
            Icons.pan_tool_alt_rounded,
            'Request sent',
            'The host can bring you on stage when ready.',
          )
        : requestsEnabled
        ? (
            Icons.headphones_rounded,
            'You’re in the audience',
            'Listen freely or request the stage from the dock below.',
          )
        : (
            Icons.headphones_rounded,
            'Listening mode',
            'Stage requests are closed for this episode.',
          );
    return Semantics(
      liveRegion: handRaised,
      label: '$title. $detail',
      child: Container(
        key: const ValueKey('podcast-listener-status'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: handRaised
              ? BroadcastRoomColors.wash
              : const Color(0xFF0D0813).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: handRaised
                ? BroadcastRoomColors.accent.withValues(alpha: .44)
                : Colors.white.withValues(alpha: .07),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: BroadcastRoomColors.accentSoft, size: 20),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: BroadcastRoomColors.muted,
                      fontSize: 11.5,
                      height: 1.25,
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

class PodcastStudioRail extends StatelessWidget {
  const PodcastStudioRail({
    required this.chat,
    required this.queue,
    required this.showQueue,
    required this.requests,
    required this.onChat,
    required this.onQueue,
    required this.queueAvailable,
    super.key,
  });

  final Widget chat;
  final Widget queue;
  final bool showQueue;
  final int requests;
  final VoidCallback onChat;
  final VoidCallback onQueue;
  final bool queueAvailable;

  @override
  Widget build(BuildContext context) {
    if (!queueAvailable) return chat;
    return Container(
      decoration: BoxDecoration(
        color: BroadcastRoomColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BroadcastRoomColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: _RailTab(
                    icon: Icons.forum_rounded,
                    label: 'Live chat',
                    selected: !showQueue,
                    onTap: onChat,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _RailTab(
                    icon: Icons.back_hand_rounded,
                    label: requests > 0 ? 'Requests $requests' : 'Requests',
                    selected: showQueue,
                    highlighted: requests > 0,
                    onTap: onQueue,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: showQueue ? 1 : 0,
              children: [chat, queue],
            ),
          ),
        ],
      ),
    );
  }
}

class PodcastRequestQueue extends StatelessWidget {
  const PodcastRequestQueue({
    required this.requests,
    required this.busyUserIds,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final List<RoomParticipant> requests;
  final Set<String> busyUserIds;
  final ValueChanged<RoomParticipant> onAccept;
  final ValueChanged<RoomParticipant> onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('podcast-request-queue'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Stage requests',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Expanded(
          child: requests.isEmpty
              ? const _EmptyQueue()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 18),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final person = requests[index];
                    final busy = busyUserIds.contains(person.userId);
                    return Container(
                      padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                      decoration: BoxDecoration(
                        color: BroadcastRoomColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: BroadcastRoomColors.accent.withValues(
                            alpha: .18,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            radius: 19,
                            photoUrl: person.photoUrl,
                            displayName: person.displayName,
                            backgroundColor: const Color(0xFF76213A),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              person.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: BroadcastRoomColors.accentSoft,
                                ),
                              ),
                            )
                          else ...[
                            IconButton(
                              tooltip: 'Decline ${person.displayName}',
                              onPressed: () => onDecline(person),
                              icon: const Icon(Icons.close_rounded),
                              color: BroadcastRoomColors.muted,
                            ),
                            IconButton.filled(
                              tooltip: 'Bring ${person.displayName} to stage',
                              onPressed: () => onAccept(person),
                              style: IconButton.styleFrom(
                                backgroundColor: BroadcastRoomColors.accent,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.mic_rounded, size: 19),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: live
            ? BroadcastRoomColors.accent.withValues(alpha: .22)
            : Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: live
              ? BroadcastRoomColors.accent.withValues(alpha: .62)
              : Colors.white.withValues(alpha: .14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: live ? BroadcastRoomColors.accentSoft : Colors.white54,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            live ? 'LIVE' : 'NOT LIVE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: .78),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: const TextStyle(color: BroadcastRoomColors.muted),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 15,
    margin: const EdgeInsets.symmetric(horizontal: 9),
    color: Colors.white.withValues(alpha: .14),
  );
}

class _DeskAction extends StatelessWidget {
  const _DeskAction({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$value $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: highlighted
                ? BroadcastRoomColors.accent.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: highlighted
                  ? BroadcastRoomColors.accent.withValues(alpha: .44)
                  : Colors.white.withValues(alpha: .06),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: highlighted
                    ? BroadcastRoomColors.accentSoft
                    : Colors.white70,
                size: 17,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BroadcastRoomColors.muted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? BroadcastRoomColors.wash : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? BroadcastRoomColors.accent.withValues(alpha: .38)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected || highlighted
                    ? BroadcastRoomColors.accentSoft
                    : BroadcastRoomColors.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : BroadcastRoomColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: BroadcastRoomColors.wash,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.back_hand_outlined,
                color: BroadcastRoomColors.accentSoft,
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              'The queue is clear',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'New stage requests will appear here in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BroadcastRoomColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
