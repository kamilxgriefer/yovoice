import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The Moments destination: the signed-in user's own Voice Moments first,
/// then the real social feed (self + friends + following, via the
/// existing [HomeFeedService]). Audio-first cards — no photo-post
/// styling, no invented content: each section shows a compact empty
/// state when its real source is empty.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({
    this.momentService,
    this.feedService,
    super.key,
  });

  final MomentService? momentService;
  final HomeFeedService? feedService;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  MomentService? _moments;
  Stream<List<VoiceMoment>>? _mine;
  Stream<List<VoiceMoment>>? _feed;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    try {
      _moments = widget.momentService ?? MomentService();
      _mine = _moments!.watchMyMoments();
      _feed = (widget.feedService ?? HomeFeedService()).watchSocialMoments();
    } catch (_) {
      // No session yet (or a preview harness): the screen renders its
      // empty states rather than throwing.
    }
  }

  Future<void> _createMoment() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecordVoiceMomentScreen()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice Moment posted.')),
      );
    }
  }

  Future<void> _openComments(VoiceMoment moment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(moment: moment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: [
                Row(
                  children: [
                    if (Navigator.of(context).canPop())
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                          tooltip: 'Back',
                        ),
                      ),
                    const Expanded(
                      child: Text(
                        'Moments',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _CreateMomentButton(onTap: _createMoment),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionTitle('Your Moments'),
                StreamBuilder<List<VoiceMoment>>(
                  stream: _mine,
                  builder: (context, snapshot) {
                    final mine = snapshot.data ?? const <VoiceMoment>[];
                    if (mine.isEmpty) {
                      return _EmptyState(
                        icon: Icons.mic_none_rounded,
                        title: 'No Moments yet',
                        body: 'Record a short voice update — it appears here '
                            'and in your followers’ feeds.',
                        actionLabel: 'Create your Moment',
                        onAction: _createMoment,
                      );
                    }
                    return Column(
                      children: [
                        for (final moment in mine.take(3))
                          MomentCard(
                            moment: moment,
                            isOwn: moment.authorId == _uid,
                            onComments: () => _openComments(moment),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                const _SectionTitle('From people you follow'),
                StreamBuilder<List<VoiceMoment>>(
                  stream: _feed,
                  builder: (context, snapshot) {
                    final feed = (snapshot.data ?? const <VoiceMoment>[])
                        .where((moment) => moment.authorId != _uid)
                        .toList(growable: false);
                    if (feed.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.graphic_eq_rounded,
                        title: 'Nothing here yet',
                        body: 'Moments from friends and people you follow '
                            'will show up here.',
                      );
                    }
                    return Column(
                      children: [
                        for (final moment in feed)
                          MomentCard(
                            moment: moment,
                            isOwn: false,
                            onComments: () => _openComments(moment),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CreateMomentButton extends StatelessWidget {
  const _CreateMomentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
      label: const Text(
        'Create your Moment',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// An audio-first Moment card: identity, caption, a compact waveform with
/// play state and duration, and the real reaction/comment counts.
class MomentCard extends StatefulWidget {
  const MomentCard({
    required this.moment,
    required this.onComments,
    this.isOwn = false,
    super.key,
  });

  final VoiceMoment moment;
  final VoidCallback onComments;
  final bool isOwn;

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  String _age(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final playable = (moment.audioUrl?.trim().isNotEmpty ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .5),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => showProfilePreview(
                  context,
                  userId: moment.authorId,
                  displayName: moment.authorName,
                  photoUrl: moment.authorPhotoUrl,
                ),
                child: UserAvatar(
                  radius: 18,
                  photoUrl: moment.authorPhotoUrl,
                  displayName: moment.authorName,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          moment.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        UserIdentityBadges(uid: moment.authorId),
                      ],
                    ),
                    Text(
                      _age(moment.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9A90AC),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!moment.isPublished)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    'Uploading…',
                    style: TextStyle(color: Color(0xFF9A90AC), fontSize: 11),
                  ),
                ),
            ],
          ),
          if (moment.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.caption,
              style: const TextStyle(
                color: Color(0xFFE6DFF0),
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _PlayButton(
                playing: _playing,
                enabled: playable,
                onTap: _toggle,
              ),
              const SizedBox(width: 12),
              const Expanded(child: _Waveform()),
              const SizedBox(width: 10),
              Text(
                moment.durationLabel,
                style: const TextStyle(
                  color: Color(0xFF9A90AC),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 15,
                color: Color(0xFFE879F9),
              ),
              const SizedBox(width: 5),
              Text(
                '${moment.likeCount}',
                style: const TextStyle(
                  color: Color(0xFF9A90AC),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 16),
              TextButton.icon(
                onPressed: widget.onComments,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(
                  Icons.mode_comment_outlined,
                  size: 15,
                  color: Color(0xFFD3A5FF),
                ),
                label: Text(
                  moment.commentCount == 0
                      ? 'Comment'
                      : '${moment.commentCount}',
                  style: const TextStyle(
                    color: Color(0xFFD3A5FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.enabled,
    required this.onTap,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.primary
          : AppColors.primary.withValues(alpha: .25),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// A static waveform silhouette — deliberately decorative: the real
/// per-moment amplitude data is not recorded, and inventing a fake
/// waveform shape per moment would be fabricated data.
class _Waveform extends StatelessWidget {
  const _Waveform();

  static const _bars = <double>[
    .35, .6, .45, .8, .55, .3, .7, .5, .85, .4,
    .65, .3, .55, .75, .45, .6, .35, .5, .7, .4,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final bar in _bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.2),
                child: Container(
                  height: 26 * bar,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .35),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: const Color(0xFFD3A5FF)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: .55),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: Color(0xFFD3A5FF),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
