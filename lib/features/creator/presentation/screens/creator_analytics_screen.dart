import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// Creator analytics that can be proven from data the app already stores.
///
/// This deliberately does not manufacture growth rates, views, retention or
/// historical attendance. Those measurements need an event/time-series model
/// that YO Voice does not have yet.
class CreatorAnalyticsScreen extends StatelessWidget {
  const CreatorAnalyticsScreen({
    required this.profile,
    required this.rooms,
    required this.clubs,
    required this.moments,
    this.isRootTab = false,
    super.key,
  });

  final UserProfile profile;
  final List<VoiceRoom> rooms;
  final List<Club> clubs;
  final List<VoiceMoment> moments;
  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final summary = CreatorAnalyticsSummary.fromData(
      profile: profile,
      rooms: rooms,
      clubs: clubs,
      moments: moments,
    );

    final content = Scaffold(
      backgroundColor: AppImmersiveColors.background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.dashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 48),
            children: [
              _Header(isRootTab: isRootTab),
              const SizedBox(height: 18),
              const _TruthNotice(),
              const SizedBox(height: 24),
              _SectionHeading(
                title: copy.text('Audience snapshot', 'Stan odbiorców'),
                subtitle: copy.text(
                  'Totals captured when Analytics opened — no estimated growth or reach.',
                  'Dane z chwili otwarcia Statystyk — bez szacowanego wzrostu ani zasięgu.',
                ),
              ),
              const SizedBox(height: 12),
              _MetricGrid(
                items: [
                  _Metric(
                    key: const ValueKey('analytics-followers'),
                    icon: Icons.people_alt_outlined,
                    value: '${summary.currentFollowers}',
                    label: copy.text('Followers', 'Obserwujący'),
                    supporting: copy.text(
                      'Profile count when Analytics opened',
                      'Liczba na profilu w chwili otwarcia Statystyk',
                    ),
                  ),
                  _Metric(
                    key: const ValueKey('analytics-hosted-rooms'),
                    icon: Icons.meeting_room_outlined,
                    value: '${summary.hostedRooms}',
                    label: copy.text('Rooms hosted', 'Utworzone pokoje'),
                    supporting: copy.text(
                      'Rooms currently stored under your account',
                      'Pokoje obecnie zapisane na Twoim koncie',
                    ),
                  ),
                  _Metric(
                    key: const ValueKey('analytics-owned-clubs'),
                    icon: Icons.groups_2_outlined,
                    value: '${summary.ownedClubs}',
                    label: copy.text('Clubs owned', 'Własne kluby'),
                    supporting: copy.text(
                      'Excludes clubs where you are only a member',
                      'Bez klubów, w których jesteś tylko członkiem',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SectionHeading(
                title: copy.text(
                  'Room status when opened',
                  'Stan pokojów przy otwarciu',
                ),
                subtitle: copy.text(
                  'Go back and reopen Analytics to capture a newer room snapshot.',
                  'Wróć i otwórz Statystyki ponownie, aby odświeżyć stan pokojów.',
                ),
              ),
              const SizedBox(height: 12),
              _MetricGrid(
                items: [
                  _Metric(
                    key: const ValueKey('analytics-live-rooms'),
                    icon: Icons.graphic_eq_rounded,
                    value: '${summary.liveRooms}',
                    label: copy.text(
                      'Rooms marked live',
                      'Pokoje oznaczone jako aktywne',
                    ),
                    supporting: copy.text(
                      'Active hosted rooms in this snapshot',
                      'Aktywne pokoje utworzone przez Ciebie',
                    ),
                    accent: AppColors.live,
                  ),
                  _Metric(
                    key: const ValueKey('analytics-live-people'),
                    icon: Icons.headphones_rounded,
                    value: '${summary.peopleInLiveRooms}',
                    label: copy.text(
                      'People in rooms marked live',
                      'Osoby w aktywnych pokojach',
                    ),
                    supporting: copy.text(
                      'Snapshot participant counters, not attendance',
                      'Stan liczników uczestników, a nie statystyka obecności',
                    ),
                    accent: AppColors.live,
                  ),
                  _Metric(
                    key: const ValueKey('analytics-room-memberships'),
                    icon: Icons.group_work_outlined,
                    value: '${summary.roomMemberships}',
                    label: copy.text(
                      'Room memberships',
                      'Członkostwa w pokojach',
                    ),
                    supporting: copy.text(
                      'Member slots across your hosted rooms',
                      'Łączna liczba członkostw w Twoich pokojach',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SectionHeading(
                title: copy.text('Voice Moments', 'Voice Moment'),
                subtitle: copy.text(
                  'Only published Moments contribute to this open-time snapshot.',
                  'W tym zestawieniu uwzględniamy tylko opublikowane materiały Voice Moment.',
                ),
              ),
              const SizedBox(height: 12),
              _MetricGrid(
                items: [
                  _Metric(
                    key: const ValueKey('analytics-published-moments'),
                    icon: Icons.mic_none_rounded,
                    value: '${summary.publishedMoments}',
                    label: copy.text('Published', 'Opublikowane'),
                    supporting: copy.text(
                      'Drafts and failed uploads are excluded',
                      'Bez wersji roboczych i nieudanych publikacji',
                    ),
                  ),
                  _Metric(
                    key: const ValueKey('analytics-moment-likes'),
                    icon: Icons.favorite_border_rounded,
                    value: '${summary.momentLikes}',
                    label: copy.text('Likes', 'Polubienia'),
                    supporting: copy.text(
                      'Stored likes across published Moments',
                      'Zapisane polubienia opublikowanych materiałów Voice Moment',
                    ),
                    accent: AppColors.secondary,
                  ),
                  _Metric(
                    key: const ValueKey('analytics-moment-comments'),
                    icon: Icons.chat_bubble_outline_rounded,
                    value: '${summary.momentComments}',
                    label: copy.text('Comments', 'Komentarze'),
                    supporting: copy.text(
                      'Stored comments across published Moments',
                      'Zapisane komentarze opublikowanych materiałów Voice Moment',
                    ),
                  ),
                  _Metric(
                    key: const ValueKey('analytics-published-audio'),
                    icon: Icons.timer_outlined,
                    value: _formatDuration(summary.publishedAudioSeconds, copy),
                    label: copy.text(
                      'Published audio',
                      'Opublikowane nagrania',
                    ),
                    supporting: copy.text(
                      'Combined duration of published Moments',
                      'Łączny czas opublikowanych materiałów Voice Moment',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _TopMoments(moments: summary.topPublishedMoments),
              const SizedBox(height: 28),
              _OwnedSpaces(summary: summary),
            ],
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

@immutable
class CreatorAnalyticsSummary {
  const CreatorAnalyticsSummary({
    required this.currentFollowers,
    required this.hostedRooms,
    required this.liveRooms,
    required this.peopleInLiveRooms,
    required this.roomMemberships,
    required this.ownedClubs,
    required this.clubMemberships,
    required this.publishedMoments,
    required this.momentLikes,
    required this.momentComments,
    required this.publishedAudioSeconds,
    required this.topPublishedMoments,
  });

  factory CreatorAnalyticsSummary.fromData({
    required UserProfile profile,
    required List<VoiceRoom> rooms,
    required List<Club> clubs,
    required List<VoiceMoment> moments,
  }) {
    final liveRooms = rooms
        .where((room) => room.isActive && room.isLive)
        .toList(growable: false);
    final ownedClubs = clubs
        .where((club) => club.ownerId == profile.uid)
        .toList(growable: false);
    final publishedMoments =
        moments.where((moment) => moment.isPublished).toList(growable: false)
          ..sort((a, b) {
            final interactionComparison = (b.likeCount + b.commentCount)
                .compareTo(a.likeCount + a.commentCount);
            if (interactionComparison != 0) return interactionComparison;
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    return CreatorAnalyticsSummary(
      currentFollowers: profile.followerCount,
      hostedRooms: rooms.length,
      liveRooms: liveRooms.length,
      peopleInLiveRooms: liveRooms.fold(
        0,
        (total, room) => total + room.participantCount,
      ),
      roomMemberships: rooms.fold(0, (total, room) => total + room.memberCount),
      ownedClubs: ownedClubs.length,
      clubMemberships: ownedClubs.fold(
        0,
        (total, club) => total + club.memberCount,
      ),
      publishedMoments: publishedMoments.length,
      momentLikes: publishedMoments.fold(
        0,
        (total, moment) => total + moment.likeCount,
      ),
      momentComments: publishedMoments.fold(
        0,
        (total, moment) => total + moment.commentCount,
      ),
      publishedAudioSeconds: publishedMoments.fold(
        0,
        (total, moment) => total + moment.durationSeconds,
      ),
      topPublishedMoments: publishedMoments.take(3).toList(growable: false),
    );
  }

  final int currentFollowers;
  final int hostedRooms;
  final int liveRooms;
  final int peopleInLiveRooms;
  final int roomMemberships;
  final int ownedClubs;
  final int clubMemberships;
  final int publishedMoments;
  final int momentLikes;
  final int momentComments;
  final int publishedAudioSeconds;
  final List<VoiceMoment> topPublishedMoments;
}

class _Header extends StatelessWidget {
  const _Header({required this.isRootTab});

  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isRootTab) ...[
          IconButton.filledTonal(
            tooltip: copy.text(
              'Back to Creator Studio',
              'Wróć do Studia twórcy',
            ),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Analytics', 'Statystyki'),
                style: const TextStyle(
                  color: AppImmersiveColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                copy.text(
                  'A truthful snapshot of your audience and content.',
                  'Rzetelny obraz Twoich odbiorców i treści.',
                ),
                style: const TextStyle(
                  color: AppImmersiveColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TruthNotice extends StatelessWidget {
  const _TruthNotice();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppImmersiveColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppImmersiveColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            color: AppColors.success,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.text(
                    'Real data, clearly labeled',
                    'Prawdziwe dane, jasno opisane',
                  ),
                  style: const TextStyle(
                    color: AppImmersiveColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.text(
                    'These are snapshot totals from your profile, rooms, clubs '
                        'and published Voice Moments, captured when Analytics '
                        'opened. Historical audience trends '
                        'are not recorded yet, so this page never invents growth '
                        'percentages, views or attendance.',
                    'To stan danych z Twojego profilu, pokojów, klubów i '
                        'opublikowanych materiałów Voice Moment w chwili otwarcia Statystyk. '
                        'YO Voice nie zapisuje jeszcze historycznych trendów odbiorców, '
                        'dlatego nie pokazujemy wymyślonych wzrostów, wyświetleń ani obecności.',
                  ),
                  style: const TextStyle(
                    color: AppImmersiveColors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppImmersiveColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppImmersiveColors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric({
    required this.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.supporting,
    this.accent = AppColors.primary,
  });

  final Key key;
  final IconData icon;
  final String value;
  final String label;
  final String supporting;
  final Color accent;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = math.max(
          0.0,
          (constraints.maxWidth - gap * (columns - 1)) / columns,
        );

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                key: item.key,
                width: width,
                child: _MetricCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _Metric item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppImmersiveColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppImmersiveColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: item.accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.value,
                  style: const TextStyle(
                    color: AppImmersiveColors.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppImmersiveColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.supporting,
                  style: const TextStyle(
                    color: AppImmersiveColors.textSecondary,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMoments extends StatelessWidget {
  const _TopMoments({required this.moments});

  final List<VoiceMoment> moments;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: copy.text('Most interacted with', 'Najwięcej interakcji'),
          subtitle: copy.text(
            'Published Moments ranked by stored likes and comments.',
            'Opublikowane materiały Voice Moment według liczby zapisanych polubień i komentarzy.',
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppImmersiveColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppImmersiveColors.border),
          ),
          child: moments.isEmpty
              ? _EmptyInline(
                  icon: Icons.mic_none_rounded,
                  text: copy.text(
                    'Publish a Voice Moment to see its stored likes and comments here.',
                    'Opublikuj Voice Moment, aby zobaczyć tutaj zapisane polubienia i komentarze.',
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < moments.length; index++) ...[
                      _MomentRow(index: index, moment: moments[index]),
                      if (index != moments.length - 1)
                        const Divider(
                          color: AppImmersiveColors.divider,
                          height: 24,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.index, required this.moment});

  final int index;
  final VoiceMoment moment;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final caption = moment.caption.trim().isEmpty
        ? copy.text('Untitled Voice Moment', 'Voice Moment bez tytułu')
        : moment.caption.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppImmersiveColors.surfaceRaised,
          foregroundColor: AppImmersiveColors.textPrimary,
          child: Text(
            '${index + 1}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppImmersiveColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _TinyStat(
                    icon: Icons.favorite_rounded,
                    value: _localizedLikeCount(moment.likeCount, copy),
                  ),
                  _TinyStat(
                    icon: Icons.chat_bubble_rounded,
                    value: _localizedCommentCount(moment.commentCount, copy),
                  ),
                  _TinyStat(
                    icon: Icons.timer_outlined,
                    value: moment.durationLabel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(icon, color: AppImmersiveColors.textTertiary, size: 13),
        Text(
          value,
          style: const TextStyle(
            color: AppImmersiveColors.textSecondary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _OwnedSpaces extends StatelessWidget {
  const _OwnedSpaces({required this.summary});

  final CreatorAnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppImmersiveColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppImmersiveColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('Owned spaces', 'Twoje przestrzenie'),
            style: const TextStyle(
              color: AppImmersiveColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copy.text(
              'Membership counters are current totals per space. The same person may belong to more than one space, so they are not labeled as unique audience.',
              'Liczniki pokazują aktualną liczbę członkostw w każdej przestrzeni. Jedna osoba może należeć do kilku przestrzeni, dlatego nie traktujemy tych wartości jako liczby unikalnych odbiorców.',
            ),
            style: const TextStyle(
              color: AppImmersiveColors.textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CountChip(
                label: copy.text('Room memberships', 'członkostwa w pokojach'),
                value: summary.roomMemberships,
              ),
              _CountChip(
                label: copy.text('Club memberships', 'członkostwa w klubach'),
                value: summary.clubMemberships,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppImmersiveColors.surfaceRaised,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppImmersiveColors.border),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(
          color: AppImmersiveColors.textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppImmersiveColors.textTertiary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppImmersiveColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(int seconds, AppLocalizations copy) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  if (hours > 0) {
    return copy.isPolish
        ? minutes == 0
              ? '$hours godz.'
              : '$hours godz. $minutes min'
        : minutes == 0
        ? '${hours}h'
        : '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return copy.isPolish
        ? rest == 0
              ? '$minutes min'
              : '$minutes min $rest s'
        : rest == 0
        ? '${minutes}m'
        : '${minutes}m ${rest}s';
  }
  return copy.isPolish ? '$rest s' : '${rest}s';
}

String _localizedLikeCount(int count, AppLocalizations copy) {
  if (!copy.isPolish) return '$count likes';
  return '$count ${_polishPlural(count, 'polubienie', 'polubienia', 'polubień')}';
}

String _localizedCommentCount(int count, AppLocalizations copy) {
  if (!copy.isPolish) return '$count comments';
  return '$count ${_polishPlural(count, 'komentarz', 'komentarze', 'komentarzy')}';
}

String _polishPlural(int count, String one, String few, String many) {
  if (count == 1) return one;
  final tens = count % 100;
  final units = count % 10;
  if (tens < 12 || tens > 14) {
    if (units >= 2 && units <= 4) return few;
  }
  return many;
}
