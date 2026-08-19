import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discovery_view.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Which half of the Moments destination is showing.
enum MomentsTab {
  /// Every published Voice Moment from every user, shuffled and weighted
  /// so genuinely popular ones surface more often.
  discover,

  /// The personal feed that has always lived here: your own Moments, then
  /// friends and people you follow. Kept, not replaced — a global
  /// discovery stack answers a different question than "what did the
  /// people I know just post".
  following,
}

/// The Moments destination.
///
/// Two surfaces behind one segmented control:
///
///  * **Discover** — a shuffled, popularity-weighted stack of published
///    Moments from ALL users ([MomentDiscoveryView]).
///  * **Following** — the pre-existing personal feed, unchanged in
///    substance and now with the loading and error states it never had.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({
    this.momentService,
    this.feedService,
    this.discoveryService,
    this.contentReportService,
    this.isRootTab = false,
    this.isVisible,
    this.initialTab = MomentsTab.discover,
    this.playerFactory,
    super.key,
  });

  final MomentService? momentService;
  final HomeFeedService? feedService;
  final MomentDiscoveryService? discoveryService;

  /// Injection seam for the report action on every Moment surface this
  /// screen owns; production passes nothing.
  final ContentReportService? contentReportService;

  /// True when the desktop shell renders this as a fixed content slot
  /// rather than pushing it as a route — the screen then draws no back
  /// button, because the shell owns navigation (ADR-047).
  final bool isRootTab;

  /// False while the shell is showing another tab, so playback stops
  /// instead of continuing from an invisible IndexedStack child.
  final ValueListenable<bool>? isVisible;

  final MomentsTab initialTab;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  MomentService? _moments;
  HomeFeedService? _feedService;
  Stream<List<VoiceMoment>>? _mine;
  Stream<List<VoiceMoment>>? _feed;
  late MomentsTab _tab = widget.initialTab;

  /// Guarded: `FirebaseAuth.instance` THROWS when no Firebase app has
  /// been initialised (a preview harness, a widget test, a cold start
  /// that raced initialisation). An unauthenticated viewer must see the
  /// screen's states, not a crash.
  String get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    // Each seam is guarded separately on purpose: one unavailable
    // service must not silently take the other down with it. Sharing a
    // single try block meant a MomentService that could not be
    // constructed also left the feed service null, disabling the like
    // control for a reason that had nothing to do with liking.
    try {
      _moments = widget.momentService ?? MomentService();
      _mine = _moments!.watchMyMoments();
    } catch (_) {
      // No session yet (or a preview harness): the section renders its
      // empty state rather than throwing.
    }
    try {
      _feedService = widget.feedService ?? HomeFeedService();
      _feed = _feedService!.watchSocialMoments();
    } catch (_) {
      // As above.
    }
  }

  Future<void> _createMoment() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecordVoiceMomentScreen()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice Moment posted.')));
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
        child: Column(
          children: [
            _MomentsHeader(
              // The shell owns the chrome when this is a root tab; a
              // pushed route keeps a real Back button.
              showBack: !widget.isRootTab && Navigator.of(context).canPop(),
              tab: _tab,
              onTabChanged: (tab) => setState(() => _tab = tab),
              onCreate: _createMoment,
            ),
            Expanded(
              child: switch (_tab) {
                MomentsTab.discover => MomentDiscoveryView(
                  key: const ValueKey('moments-discover'),
                  discoveryService: widget.discoveryService,
                  feedService: _feedService,
                  contentReportService: widget.contentReportService,
                  isVisible: widget.isVisible,
                  playerFactory: widget.playerFactory,
                  onOpenComments: (moment) => unawaited(_openComments(moment)),
                  onRecord: () => unawaited(_createMoment()),
                ),
                MomentsTab.following => _FollowingFeed(
                  key: const ValueKey('moments-following'),
                  mine: _mine,
                  feed: _feed,
                  feedService: _feedService,
                  currentUserId: _uid,
                  contentReportService: widget.contentReportService,
                  onCreate: () => unawaited(_createMoment()),
                  onComments: (moment) => unawaited(_openComments(moment)),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentsHeader extends StatelessWidget {
  const _MomentsHeader({
    required this.showBack,
    required this.tab,
    required this.onTabChanged,
    required this.onCreate,
  });

  final bool showBack;
  final MomentsTab tab;
  final ValueChanged<MomentsTab> onTabChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final title = Row(
          children: [
            if (showBack)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.textPrimary,
                  tooltip: 'Back',
                ),
              ),
            const Expanded(
              child: Text(
                'Moments',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _CreateMomentButton(onTap: onCreate, compact: compact),
          ],
        );

        final segments = SegmentedButton<MomentsTab>(
          segments: const [
            ButtonSegment<MomentsTab>(
              value: MomentsTab.discover,
              icon: Icon(Icons.explore_outlined, size: 18),
              label: Text('Discover'),
            ),
            ButtonSegment<MomentsTab>(
              value: MomentsTab.following,
              icon: Icon(Icons.people_outline_rounded, size: 18),
              label: Text('Following'),
            ),
          ],
          selected: <MomentsTab>{tab},
          onSelectionChanged: (selection) => onTabChanged(selection.first),
          showSelectedIcon: false,
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            14,
            compact ? 16 : 24,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              // Full width on phone, intrinsic on wider surfaces — a
              // two-segment control stretched across 1400 pt reads as a
              // toolbar, not a choice.
              if (compact)
                SizedBox(width: double.infinity, child: segments)
              else
                Align(alignment: Alignment.centerLeft, child: segments),
            ],
          ),
        );
      },
    );
  }
}

/// The personal feed: the signed-in user's own Voice Moments first, then
/// the real social feed (self + friends + following, via the existing
/// [HomeFeedService]).
///
/// Both streams now render four distinct states. Previously each was a
/// bare `snapshot.data ?? const <VoiceMoment>[]` with no `hasError` and
/// no `connectionState` check, so a permission error, a missing index and
/// a still-connecting stream all rendered as the same "No Moments yet"
/// card — one state that lied three ways.
class _FollowingFeed extends StatelessWidget {
  const _FollowingFeed({
    required this.mine,
    required this.feed,
    required this.feedService,
    required this.currentUserId,
    required this.contentReportService,
    required this.onCreate,
    required this.onComments,
    super.key,
  });

  final Stream<List<VoiceMoment>>? mine;
  final Stream<List<VoiceMoment>>? feed;
  final HomeFeedService? feedService;
  final String currentUserId;
  final ContentReportService? contentReportService;
  final VoidCallback onCreate;
  final ValueChanged<VoiceMoment> onComments;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            const _SectionTitle('Your Moments'),
            _MomentSection(
              stream: mine,
              emptyIcon: Icons.mic_none_rounded,
              emptyTitle: 'No Moments yet',
              emptyBody:
                  'Record a short voice update — it appears here '
                  'and in your followers’ feeds.',
              emptyActionLabel: 'Create your Moment',
              onEmptyAction: onCreate,
              errorTitle: 'Your Moments could not load',
              take: 3,
              isOwnSection: true,
              feedService: feedService,
              currentUserId: currentUserId,
              contentReportService: contentReportService,
              onComments: onComments,
            ),
            const SizedBox(height: 22),
            const _SectionTitle('From people you follow'),
            _MomentSection(
              stream: feed,
              excludeAuthorId: currentUserId,
              emptyIcon: Icons.graphic_eq_rounded,
              emptyTitle: 'Nothing here yet',
              emptyBody:
                  'Moments from friends and people you follow '
                  'will show up here.',
              errorTitle: 'This feed could not load',
              isOwnSection: false,
              feedService: feedService,
              currentUserId: currentUserId,
              contentReportService: contentReportService,
              onComments: onComments,
            ),
          ],
        ),
      ),
    );
  }
}

/// One stream-backed section with genuinely distinct loading, error,
/// empty and populated states.
class _MomentSection extends StatelessWidget {
  const _MomentSection({
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.errorTitle,
    required this.isOwnSection,
    required this.feedService,
    required this.currentUserId,
    required this.contentReportService,
    required this.onComments,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.excludeAuthorId,
    this.take,
  });

  final Stream<List<VoiceMoment>>? stream;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final String errorTitle;
  final bool isOwnSection;
  final HomeFeedService? feedService;
  final String currentUserId;
  final ContentReportService? contentReportService;
  final ValueChanged<VoiceMoment> onComments;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String? excludeAuthorId;
  final int? take;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VoiceMoment>>(
      stream: stream,
      builder: (context, snapshot) {
        // Error FIRST. An errored stream carries no data, and treating
        // it as an empty list is how two live defects stayed hidden in
        // this repo.
        if (snapshot.hasError) {
          return _FeedErrorState(title: errorTitle, error: snapshot.error);
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _SectionSkeleton();
        }
        final all = snapshot.data ?? const <VoiceMoment>[];
        final visible = <VoiceMoment>[
          for (final moment in all)
            if (excludeAuthorId == null || moment.authorId != excludeAuthorId)
              moment,
        ];
        if (visible.isEmpty) {
          return _EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            body: emptyBody,
            actionLabel: emptyActionLabel,
            onAction: onEmptyAction,
          );
        }
        final shown = take == null ? visible : visible.take(take!);
        return Column(
          children: [
            for (final moment in shown)
              MomentCard(
                moment: moment,
                isOwn: isOwnSection && moment.authorId == currentUserId,
                canReport:
                    currentUserId.isNotEmpty &&
                    moment.authorId != currentUserId,
                feedService: feedService,
                contentReportService: contentReportService,
                onComments: () => onComments(moment),
              ),
          ],
        );
      },
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('moments-section-loading'),
      children: [
        for (var i = 0; i < 2; i++)
          Container(
            height: 132,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surface.withValues(alpha: .35),
              border: Border.all(
                color: AppColors.border.withValues(alpha: .45),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeedErrorState extends StatelessWidget {
  const _FeedErrorState({required this.title, required this.error});

  final String title;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('moments-section-error'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .35),
        border: Border.all(color: AppColors.error.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 26, color: AppColors.error),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (kDebugMode && error != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
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
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CreateMomentButton extends StatelessWidget {
  const _CreateMomentButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // On a phone the title, the segmented control and a full-width
      // label cannot all fit; the icon button keeps a 48 pt target.
      return IconButton.filled(
        onPressed: onTap,
        tooltip: 'Create your Moment',
        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
        icon: const Icon(Icons.mic_rounded, color: AppColors.textPrimary),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(
        Icons.mic_rounded,
        size: 18,
        color: AppColors.textPrimary,
      ),
      label: const Text(
        'Create your Moment',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// An audio-first Moment card: identity, caption, a compact waveform with
/// play state and duration, and the real reaction/comment counts.
///
/// Shared with the creator pinned-Moment surfaces and mobile Home — its
/// constructor is deliberately backward compatible.
class MomentCard extends StatefulWidget {
  const MomentCard({
    required this.moment,
    required this.onComments,
    this.isOwn = false,
    this.canReport = false,
    this.offlineService,
    this.feedService,
    this.contentReportService,
    super.key,
  });

  final VoiceMoment moment;
  final VoidCallback onComments;
  final bool isOwn;

  /// True only when the viewer is known AND is not the author. Kept
  /// separate from [isOwn], which is false for a signed-out viewer too —
  /// offering "report" to someone with no session is a control that can
  /// only ever fail.
  final bool canReport;
  final OfflineVoiceMomentService? offlineService;

  /// Injection seam for the report action, matching [offlineService] and
  /// [feedService]: production passes nothing, tests pass a fake so the
  /// success and failure paths can be exercised without a Firebase app.
  final ContentReportService? contentReportService;

  /// Backs the like control. When null the heart renders as a disabled
  /// indicator rather than a button that silently does nothing.
  final HomeFeedService? feedService;

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  final AudioPlayer _player = AudioPlayer();
  late final OfflineVoiceMomentService _offline =
      widget.offlineService ?? OfflineVoiceMomentService.instance;
  bool _playing = false;
  bool _downloaded = false;
  bool _downloading = false;
  int _downloadLookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refreshDownloadState();
  }

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id) {
      _downloaded = false;
      _refreshDownloadState();
    }
  }

  Future<void> _refreshDownloadState() async {
    final generation = ++_downloadLookupGeneration;
    final momentId = widget.moment.id;
    try {
      final downloaded = await _offline.isDownloaded(momentId);
      if (mounted &&
          generation == _downloadLookupGeneration &&
          widget.moment.id == momentId) {
        setState(() => _downloaded = downloaded);
      }
    } catch (_) {
      // The parent screen is authenticated, but a concurrent logout can race
      // this lightweight local lookup. It must not make the feed fail.
    }
  }

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
      final offline = _downloaded
          ? await _offline.readPlayback(widget.moment.id)
          : null;
      if (_downloaded && offline == null && mounted) {
        setState(() => _downloaded = false);
      }
      final source = offline?.deviceFilePath != null
          ? DeviceFileSource(offline!.deviceFilePath!)
          : offline?.bytes != null
          ? BytesSource(offline!.bytes!)
          : UrlSource(url);
      await _player.play(source);
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  Future<void> _toggleDownload() async {
    if (_downloading) return;
    final momentId = widget.moment.id;
    final removing = _downloaded;
    setState(() => _downloading = true);
    try {
      if (removing) {
        await _offline.delete(momentId);
      } else {
        await _offline.download(widget.moment);
      }
      if (!mounted || widget.moment.id != momentId) return;
      setState(() => _downloaded = !removing);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _downloaded
                  ? 'Voice Moment downloaded for offline listening.'
                  : 'Offline download removed.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: Text(
              error is OfflineAudioException
                  ? error.message
                  : 'The Voice Moment could not be downloaded.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _toggleLike() async {
    final service = widget.feedService;
    if (service == null) return;
    try {
      await service.toggleLike(widget.moment.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Your like could not be saved.'),
          ),
        );
    }
  }

  /// Reports this Voice Moment to moderation.
  ///
  /// `voiceMoment` is one of the three targets `createContentReport`
  /// already accepts, and until now nothing in the app called it — the
  /// feed rendered other people's audio with no way to say anything was
  /// wrong with it.
  Future<void> _report() async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(momentId: widget.moment.id),
      title: 'Report this Voice Moment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'Moment attached. ${widget.moment.authorName} is not told who '
          'reported it.',
    );
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
        border: Border.all(color: AppColors.border.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccessibleTapRegion(
                onTap: () => showProfilePreview(
                  context,
                  userId: moment.authorId,
                  displayName: moment.authorName,
                  photoUrl: moment.authorPhotoUrl,
                ),
                semanticLabel: 'Open profile for ${moment.authorName}',
                tooltip: 'Open ${moment.authorName}\'s profile',
                circular: true,
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
                    // Row + Flexible, not Wrap: a long display name
                    // truncates and the identity badges stay on the line.
                    // A Wrap dropped the badges onto a second row.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            moment.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserIdentityBadges(uid: moment.authorId),
                      ],
                    ),
                    Text(
                      _age(moment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
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
                    style: TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (moment.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.caption,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _PlayButton(playing: _playing, enabled: playable, onTap: _toggle),
              const SizedBox(width: 12),
              const Expanded(child: _Waveform()),
              const SizedBox(width: 10),
              // Hidden rather than asserting "0:00": legacy documents
              // carry no duration and a fabricated zero is still fabricated.
              if (moment.durationSeconds > 0)
                Text(
                  moment.durationLabel,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LikeControl(
                momentId: moment.id,
                likeCount: moment.likeCount,
                feedService: widget.feedService,
                onToggle: _toggleLike,
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: widget.onComments,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(
                  Icons.mode_comment_outlined,
                  size: 17,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  moment.commentCount == 0
                      ? 'Comment'
                      : '${moment.commentCount}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              // Not offered on your own Moment: reporting yourself is not
              // a real intent, and each such report is a row a moderator
              // opens before finding nothing to do. Deleting your own
              // Moment is the action that belongs there instead, and it
              // already exists elsewhere.
              if (widget.canReport && !moment.isDeleted)
                IconButton(
                  key: ValueKey('report-moment-${moment.id}'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: 'Report this Voice Moment',
                  onPressed: _report,
                  icon: const Icon(
                    Icons.flag_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (playable && moment.isPublished && !moment.isDeleted)
                IconButton(
                  key: ValueKey('download-moment-${moment.id}'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: _downloaded
                      ? 'Remove offline download'
                      : 'Download for offline listening',
                  onPressed: _downloading ? null : _toggleDownload,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _downloaded
                              ? Icons.download_done_rounded
                              : Icons.download_for_offline_outlined,
                          color: _downloaded
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The heart, as a REAL control.
///
/// It previously rendered as an icon plus static text with no tap target:
/// the screen displayed engagement it gave no way to create, while
/// [HomeFeedService.toggleLike] / [HomeFeedService.watchLiked] and the
/// `setMomentLike` callable worked and Home already used them.
class _LikeControl extends StatelessWidget {
  const _LikeControl({
    required this.momentId,
    required this.likeCount,
    required this.feedService,
    required this.onToggle,
  });

  final String momentId;
  final int likeCount;
  final HomeFeedService? feedService;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    // Zero reads as a verb, not a number — no invented social proof, and
    // no hiding the control either.
    final label = likeCount == 0 ? 'Like' : '$likeCount';

    if (service == null) {
      return _LikeButton(liked: false, label: label, onTap: null);
    }
    return StreamBuilder<bool>(
      stream: service.watchLiked(momentId),
      builder: (context, snapshot) {
        final liked = snapshot.hasError ? false : (snapshot.data ?? false);
        return _LikeButton(liked: liked, label: label, onTap: onToggle);
      },
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.label,
    required this.onTap,
  });

  final bool liked;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: liked ? 'Unlike this Moment' : 'Like this Moment',
      child: TextButton.icon(
        key: ValueKey('like-moment-$label-$liked'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 44),
        ),
        icon: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 17,
          // Tint carries STATE, never meaning. The count label stays
          // textSecondary: `secondary` on `background` is roughly 4:1,
          // fine for a glyph and not for 12 pt text.
          color: liked ? AppColors.secondary : AppColors.textSecondary,
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    return Semantics(
      button: enabled,
      label: playing ? 'Pause this Moment' : 'Play this Moment',
      child: Material(
        color: enabled
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: .25),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
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
    .35,
    .6,
    .45,
    .8,
    .55,
    .3,
    .7,
    .5,
    .85,
    .4,
    .65,
    .3,
    .55,
    .75,
    .45,
    .6,
    .35,
    .5,
    .7,
    .4,
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
      key: const ValueKey('moments-section-empty'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .35),
        border: Border.all(color: AppColors.border.withValues(alpha: .45)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
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
                  color: AppColors.textPrimary,
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
