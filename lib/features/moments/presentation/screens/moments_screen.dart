import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_card.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discovery_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// [MomentCard] used to live in this file and is imported from here by the
/// creator, profile and Home surfaces. It now has its own file — the
/// Following tab renders compact tiles and opens the card in a sheet, so
/// a screen importing a screen to get a card was the wrong shape — and is
/// re-exported so no existing importer had to change.
export 'package:yovoice/features/moments/presentation/widgets/moment_card.dart'
    show MomentCard;

/// Which half of the Moments destination is showing.
enum MomentsTab {
  /// Every published Voice Moment from every user, as a board of
  /// avatars ranked by engagement — with the popularity-weighted shuffle
  /// still one tap away.
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
///  * **Discover** — a board of avatar circles covering every published
///    Moment from ALL users, most-engaged first ([MomentDiscoveryView]).
///  * **Following** — the pre-existing personal feed. Same two streams,
///    same states, rendered as compact avatar tiles; the full card it
///    used to list is one tap away in a sheet.
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

  /// Opens one Moment from a Following tile. The tile is an index entry;
  /// the sheet carries the unchanged [MomentCard] with playback, like,
  /// comment, report and offline download.
  Future<void> _openMoment(VoiceMoment moment) async {
    final uid = _uid;
    await showMomentSheet(
      context,
      moment: moment,
      isOwn: uid.isNotEmpty && moment.authorId == uid,
      canReport: uid.isNotEmpty && moment.authorId != uid,
      feedService: _feedService,
      momentService: _moments,
      contentReportService: widget.contentReportService,
      playerFactory: widget.playerFactory,
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
                  onOpen: (moment) => unawaited(_openMoment(moment)),
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
    required this.onOpen,
    super.key,
  });

  final Stream<List<VoiceMoment>>? mine;
  final Stream<List<VoiceMoment>>? feed;
  final HomeFeedService? feedService;
  final String currentUserId;
  final ContentReportService? contentReportService;
  final VoidCallback onCreate;

  /// Opens one Moment in the player sheet. Tiles are an index, not a
  /// player: the card that can actually play, like, comment, report and
  /// download is one tap away and unchanged.
  final ValueChanged<VoiceMoment> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 600;
        // Capped rather than unbounded: a tile grid stretched across a
        // 1600 pt window becomes a wall of specks with no reading rhythm.
        // Wider than the old 720 pt column, because tiles want columns.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                4,
                compact ? 16 : 24,
                40,
              ),
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
                  // Three was a cap on tall cards. Tiles cost a fraction
                  // of the height, so more of your own work is visible
                  // without scrolling past someone else's.
                  take: 12,
                  isOwnSection: true,
                  feedService: feedService,
                  currentUserId: currentUserId,
                  contentReportService: contentReportService,
                  onOpen: onOpen,
                ),
                const SizedBox(height: 26),
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
                  onOpen: onOpen,
                ),
              ],
            ),
          ),
        );
      },
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
    required this.onOpen,
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
  final ValueChanged<VoiceMoment> onOpen;
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
        final shown = (take == null ? visible : visible.take(take!)).toList(
          growable: false,
        );
        return _MomentTileGrid(moments: shown, onOpen: onOpen);
      },
    );
  }
}

/// The compact Following grid: mini squares, each carrying its author's
/// avatar.
///
/// This replaced a column of full-width cards. Those cards are not gone —
/// tapping a tile opens exactly one of them in a sheet — but as a FEED
/// they spent most of a viewport on two or three entries, so a personal
/// feed of a dozen Moments read as an endless scroll of mostly empty
/// panels. A tile is an index entry: who, how long, and what it has
/// actually collected.
class _MomentTileGrid extends StatelessWidget {
  const _MomentTileGrid({required this.moments, required this.onOpen});

  final List<VoiceMoment> moments;
  final ValueChanged<VoiceMoment> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 10.0;
        // A target per breakpoint, then whole columns. The floor of two
        // keeps a 320 pt phone from rendering one card-width tile; the
        // ceiling of eight keeps a desktop grid from turning into specks.
        final target = width < 600
            ? 108.0
            : width < 980
            ? 122.0
            : 134.0;
        final columns = ((width + gap) / (target + gap)).floor().clamp(2, 8);
        final tile = (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final moment in moments)
              _MomentSquareTile(
                key: ValueKey('moment-square-${moment.id}'),
                moment: moment,
                extent: tile,
                onTap: () => onOpen(moment),
              ),
          ],
        );
      },
    );
  }
}

/// One mini square. Nothing on it is invented: the avatar and name come
/// from the Moment document, the duration is the recorded length, and a
/// counter is printed only when it is greater than zero.
class _MomentSquareTile extends StatelessWidget {
  const _MomentSquareTile({
    required this.moment,
    required this.extent,
    required this.onTap,
    super.key,
  });

  final VoiceMoment moment;
  final double extent;
  final VoidCallback onTap;

  String get _semanticLabel {
    final parts = <String>[
      'Open the Moment by ${moment.authorName}',
      if (moment.durationSeconds > 0) '${moment.durationSeconds} seconds',
      if (moment.likeCount > 0)
        '${moment.likeCount} ${moment.likeCount == 1 ? 'like' : 'likes'}',
      if (moment.commentCount > 0)
        '${moment.commentCount} '
            '${moment.commentCount == 1 ? 'comment' : 'comments'}',
      if (!moment.isPublished) 'still uploading',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final avatarRadius = (extent * .21).clamp(16.0, 30.0);
    // The square grows with the text scale instead of clipping its own
    // label: an accessibility setting must not cost the name.
    final height =
        extent + (scaler.scale(11) - 11) * 3.2 + (scaler.scale(10.5) - 10.5) * 2;

    return SizedBox(
      width: extent,
      height: height,
      child: Semantics(
        button: true,
        label: _semanticLabel,
        child: Material(
          color: AppColors.surface.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: .45),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        radius: avatarRadius,
                        photoUrl: moment.authorPhotoUrl,
                        displayName: moment.authorName,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Text(
                      moment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Flexible(child: _TileFooter(moment: moment)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one honest line under the face: what it is still doing, or what it
/// has collected, or how long it runs. Never a fabricated zero.
class _TileFooter extends StatelessWidget {
  const _TileFooter({required this.moment});

  final VoiceMoment moment;

  @override
  Widget build(BuildContext context) {
    if (!moment.isPublished) {
      return const Text(
        'Uploading…',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textHint, fontSize: 10.5),
      );
    }

    const style = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
    );

    if (moment.likeCount <= 0 && moment.commentCount <= 0) {
      return Text(
        moment.durationSeconds > 0 ? moment.durationLabel : '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textHint, fontSize: 10.5),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (moment.likeCount > 0) ...[
          const Icon(
            Icons.favorite_rounded,
            size: 11,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${moment.likeCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
        if (moment.likeCount > 0 && moment.commentCount > 0)
          const SizedBox(width: 7),
        if (moment.commentCount > 0) ...[
          const Icon(
            Icons.mode_comment_rounded,
            size: 10,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${moment.commentCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ],
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
