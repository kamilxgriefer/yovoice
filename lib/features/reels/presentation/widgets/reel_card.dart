import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/friend_request_error_copy.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_friend_relationship_store.dart';
import 'package:yovoice/features/reels/presentation/sharing/reel_share.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_overlay_measure.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_private_overlay_guard.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelVideoBuilder =
    Widget Function(BuildContext context, Uri mediaUri, Reel reel);

/// Test seam for the built-in network decoder. Production leaves this null so
/// [VideoPlayerController.networkUrl] keeps owning the platform configuration.
typedef ReelNetworkVideoControllerFactory =
    VideoPlayerController Function(Uri mediaUri);

/// Shadow under the Reel stage in each appearance: heavier in Dark where the
/// card floats over the moments-studio atmosphere, restrained plum in Pearl.
List<BoxShadow> reelCardShadow(BuildContext context) {
  final palette = context.appPalette;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: palette.shadow.withValues(alpha: dark ? .45 : .16),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];
}

/// One real Reel page. Photos render in-app with the non-destructive crop,
/// filter and overlays. Video uses an injected native player when available;
/// otherwise the signed media URL opens in the platform player instead of
/// pretending a static thumbnail is playback.
///
/// The card IS the 9:16 media: its border, radius and shadow are drawn on the
/// inscribed frame, never on a wider box around it, so no gutter of ordinary
/// surface colour ever appears inside the card.
class ReelCard extends StatefulWidget {
  const ReelCard({
    required this.reel,
    required this.service,
    this.videoBuilder,
    this.audioPlaybackFactory,
    this.videoPlaybackFactory,
    this.videoControllerFactory,
    this.soundOn,
    this.autoplay = true,
    this.isActive = true,
    this.isHostVisible = true,
    this.suspendPlayback = false,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onMediaLike,
    this.onComments,
    this.onShare,
    this.onOpenAuthor,
    this.friendService,
    this.friendRelationshipStore,
    this.likePending = false,
    this.commentsOpen = false,
    this.showIdentity = true,
    this.borderRadius = 24,
    this.fillViewport = false,
    this.mediaTopInset = 0,
    this.now,
    super.key,
  });

  final Reel reel;
  final ReelService service;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;

  /// Supplies the video engine instead of the built-in decoder. Production
  /// leaves it null; a host that already owns a player — and the autoplay
  /// coverage, which must not start a platform decoder — provides one.
  final ReelVideoPlaybackFactory? videoPlaybackFactory;

  @visibleForTesting
  final ReelNetworkVideoControllerFactory? videoControllerFactory;

  /// The viewer's sound preference, shared by every card in a feed so it is
  /// turned on once rather than per Reel. Null gives this card its own, which
  /// starts silent.
  final ValueNotifier<bool>? soundOn;

  /// Whether a video Reel starts itself once it is the active page. Photo
  /// Reels never do — their backing track is content, not ambience.
  final bool autoplay;
  final bool isActive;

  /// Host navigation obscures the same page; it is not a swipe away from it.
  /// Suspend without seeking or forgetting the viewer's deliberate pause.
  final bool isHostVisible;

  /// Held true while something ELSE inside the host must be the only thing
  /// sounding — today, a voice comment playing in the docked thread beside
  /// this Reel.
  ///
  /// It is a suspension, not a pause: releasing it restarts only what
  /// autoplay would have started on its own, so a video Reel resumes when
  /// the comment finishes and a photo Reel (whose backing track is content,
  /// never ambience) waits for a tap, exactly as each does after any other
  /// suspension. Separate from [isHostVisible] because that answers a
  /// different question — this Reel IS visible; it simply must not be heard.
  final bool suspendPlayback;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;

  /// Engagement is owned by the feed, not by the card: the card renders the
  /// counts it is given and reports intent upwards. That is what keeps a
  /// card, the wide context panel and an open thread showing one truth.
  ///
  /// Null means there is no viewer to act as. An unverified account keeps a
  /// live control that explains its gate rather than a dead button.
  final VoidCallback? onLike;

  /// One-way like intent from a double-tap on the media. Unlike [onLike],
  /// this never removes a like; the feed owns the idempotent mutation. The
  /// future lets the card hold only a real in-flight request. A synchronous
  /// preflight refusal (for example, an unverified email) completes at once,
  /// so a later double-tap is still allowed to retry.
  final Future<void> Function()? onMediaLike;
  final VoidCallback? onComments;
  final Future<void> Function()? onShare;

  /// What a tap on the author does. Production leaves it null and opens the
  /// shared profile preview; tests inject a seam so they never touch
  /// Firestore.
  final void Function(Reel reel)? onOpenAuthor;

  /// The existing friends graph behind the author's "Add friend" action.
  /// Null where the host cannot resolve Firebase; the action then stays
  /// absent instead of exposing a control that cannot complete.
  final FriendService? friendService;

  /// Feed-owned state shared by every mounted card for the same author.
  /// Direct card hosts may omit it; their one card then owns a local store.
  final ReelFriendRelationshipStore? friendRelationshipStore;
  final bool likePending;

  /// True while the wide layout already shows this Reel's thread beside it.
  final bool commentsOpen;

  /// False when a docked context panel already carries the author and the
  /// caption, so the frame shows only the action rail and the sound chip.
  final bool showIdentity;
  final double borderRadius;
  final bool fillViewport;
  final double mediaTopInset;
  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<ReelCard> with WidgetsBindingObserver {
  late Uri? _initialMediaUri = widget.service.cachedMediaUri(widget.reel.id);
  late Future<Uri> _media = _loadMedia();
  late ReelPlaybackCoordinator _playback = _createPlayback();
  Timer? _watchTimer;
  Timer? _mediaHeartTimer;
  Duration _watched = Duration.zero;
  bool _photoReady = false;
  bool _viewRecorded = false;
  int _mediaRevision = 0;
  int _automaticRefreshes = 0;
  int _mediaHeartPulse = 0;
  bool _mediaHeartVisible = false;
  Object? _mediaLikeFlight;
  // The stacked desktop card measures only the controls that actually sit
  // across the bottom of its 9:16 frame. The immersive phone composition has
  // a side rail, so treating that rail's HEIGHT as a bottom inset would push
  // authored stickers into the middle of the Yeel. Its bottom and trailing
  // safe zones are derived independently by `_ImmersiveOverlayGeometry`.
  double _frameControlsHeight = 0;

  /// Board 08's caption is two lines that open to eight on the card itself —
  /// the desktop stage has the room, so a reader never has to leave the Reel
  /// to finish a sentence. The immersive stage keeps its detail sheet.
  bool _captionExpanded = false;
  final Set<ValueNotifier<bool>> _detailLifetimes = {};
  DateTime get _now => (widget.now ?? DateTime.now)();

  void _retireDetails() {
    for (final lifetime in _detailLifetimes) {
      // This can run while a card is removed during tree finalization. The
      // callback's current() gate is already false; notify the separate modal
      // only after the locked build phase rather than setting its state here.
      scheduleMicrotask(() {
        if (_detailLifetimes.contains(lifetime)) lifetime.value = false;
      });
    }
  }

  Future<void> _openDetails({bool includeActions = false}) async {
    final reel = widget.reel;
    final service = widget.service;
    final uid = service.currentUserId;
    if (uid == null ||
        _playbackSuspended ||
        !widget.isActive ||
        !reel.availability.isAvailableAt(_now)) {
      return;
    }
    final lifetime = ValueNotifier<bool>(true);
    _detailLifetimes.add(lifetime);
    final identity = service.identityChanges.listen((id) {
      if (id != uid) lifetime.value = false;
    }, onError: (Object _) => lifetime.value = false);
    bool current() =>
        mounted &&
        lifetime.value &&
        _appResumed &&
        identical(widget.service, service) &&
        widget.reel.id == reel.id &&
        service.currentUserId == uid &&
        reel.availability.isAvailableAt(_now);
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: lifetime,
          builder: (context, alive, _) => ReelPrivateOverlayGuard(
            service: service,
            viewerId: uid,
            now: () => _now,
            contentExpiresAt: reel.availability.contentExpiresAt,
            initiallyAllowed: alive && current(),
            contentBuilder: (context) {
              final copy = AppLocalizations.of(context);
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        reel.authorName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (current()) Navigator.pop(context, 'profile');
                        },
                        icon: const Icon(Icons.person_outline_rounded),
                        label: Text(copy.profile),
                      ),
                      if (reel.composition.caption.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          key: const ValueKey('reel-details-caption-semantics'),
                          container: true,
                          label: reel.composition.caption,
                          child: ExcludeSemantics(
                            child: SelectableText(reel.composition.caption),
                          ),
                        ),
                      ],
                      for (final link in reel.composition.linkOverlays)
                        ListTile(
                          key: ValueKey('reel-details-link-${link.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded),
                          title: Text(link.label),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: () {
                            if (current()) {
                              unawaited(
                                launchUrl(
                                  link.uri,
                                  mode: LaunchMode.externalApplication,
                                ),
                              );
                            }
                          },
                        ),
                      if (includeActions && widget.onReport != null)
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(copy.text('Report Yeel', 'Zgłoś Yeel')),
                          onTap: () {
                            if (current()) Navigator.pop(context, 'report');
                          },
                        ),
                      if (includeActions && widget.onDelete != null)
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(copy.text('Delete Yeel', 'Usuń Yeel')),
                          onTap: () {
                            if (current()) Navigator.pop(context, 'delete');
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (!current()) return;
      if (action == 'profile') _openAuthor();
      if (action == 'report') await widget.onReport?.call();
      if (action == 'delete') await widget.onDelete?.call();
    } finally {
      unawaited(identity.cancel());
      _detailLifetimes.remove(lifetime);
      lifetime.dispose();
    }
  }

  EdgeInsets _frameCompositionInsets() =>
      EdgeInsets.fromLTRB(16, 56, 16, _frameControlsHeight + 8);

  /// Owned only when the host supplied none, so a card outside a feed still
  /// has a sound preference to toggle.
  ValueNotifier<bool>? _ownSoundOn;

  /// False while the app is not in the foreground, and while any route stands
  /// above the feed — the comment sheet, a profile preview, a report sheet, a
  /// confirmation dialog. One signal covers all of them because they are all
  /// pushed routes, so nothing new has to be threaded down for each.
  bool _appResumed = true;
  bool _routeIsCurrent = true;

  ValueNotifier<bool> get _soundOn => widget.soundOn ?? _ownSoundOn!;

  Future<Uri> _loadMedia({bool forceRefresh = false}) => widget.service
      .resolveMediaUri(widget.reel.id, forceRefresh: forceRefresh);

  void _refreshMedia({bool automatic = false}) {
    if (!mounted || (automatic && _automaticRefreshes > 0)) return;
    if (automatic) _automaticRefreshes++;
    _photoReady = false;
    _syncWatchTimer();
    setState(() {
      _initialMediaUri = null;
      _mediaRevision++;
      _media = _loadMedia(forceRefresh: true);
    });
  }

  void _syncWatchTimer() {
    _watchTimer?.cancel();
    _watchTimer = null;
    if (!widget.isActive ||
        _playbackSuspended ||
        _viewRecorded ||
        !_photoReady ||
        widget.reel.media.kind != ReelMediaKind.image) {
      return;
    }
    _watchTimer = Timer(const Duration(seconds: 3), () {
      _watchTimer = null;
      _onViewedProgress(const Duration(seconds: 3));
    });
  }

  void _onViewedProgress(Duration progress) {
    if (!mounted ||
        _viewRecorded ||
        !widget.isActive ||
        _playbackSuspended ||
        !widget.reel.availability.isAvailableAt(_now.toUtc())) {
      return;
    }
    _watched += progress;
    if (_watched < const Duration(seconds: 3)) return;
    _viewRecorded = true;
    unawaited(widget.service.recordViewed(widget.reel));
  }

  void _onPhotoReady() {
    if (_photoReady) return;
    _photoReady = true;
    _syncWatchTimer();
  }

  ReelPlaybackCoordinator _createPlayback() => ReelPlaybackCoordinator(
    reel: widget.reel,
    resolveBackingAudioUri: () => widget.service.resolveMediaUri(
      widget.reel.id,
      asset: ReelAssetKind.backingAudio,
    ),
    audioPlaybackFactory: widget.audioPlaybackFactory,
    autoplay: widget.autoplay,
    // Autoplay is the only thing that ever starts without a gesture, so it
    // starts silent: a voice-first app opening loud in a quiet room is a real
    // harm, and a browser refuses an unmuted ungestured start outright.
    muted: !_soundOn.value,
    onVideoProgress: _onViewedProgress,
  );

  @override
  void initState() {
    super.initState();
    _appResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (widget.soundOn == null) _ownSoundOn = ValueNotifier<bool>(false);
    _soundOn.addListener(_onSoundPreferenceChanged);
    _playback.addListener(_onPlaybackChanged);
    if (!widget.isActive) {
      unawaited(_playback.setActive(false).catchError((Object _) {}));
    }
    if (_playbackSuspended) unawaited(_applyPlaybackSuspension());
    _syncWatchTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of registers this element as a dependent of the route's
    // "is current" status, so pushing or popping anything above the feed
    // brings us back here without a listener of our own.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current == _routeIsCurrent) return;
    _routeIsCurrent = current;
    unawaited(_applyPlaybackSuspension());
  }

  @override
  void didUpdateWidget(covariant ReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.soundOn, widget.soundOn)) {
      (oldWidget.soundOn ?? _ownSoundOn)?.removeListener(
        _onSoundPreferenceChanged,
      );
      if (widget.soundOn == null) _ownSoundOn ??= ValueNotifier<bool>(false);
      _soundOn.addListener(_onSoundPreferenceChanged);
      _onSoundPreferenceChanged();
    }
    final sourceChanged =
        oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.audioPlaybackFactory, widget.audioPlaybackFactory);
    if (sourceChanged) {
      _mediaHeartTimer?.cancel();
      _mediaHeartVisible = false;
      _mediaLikeFlight = null;
      _retireDetails();
      _playback.removeListener(_onPlaybackChanged);
      _playback.dispose();
      _playback = _createPlayback()..addListener(_onPlaybackChanged);
      _initialMediaUri = widget.service.cachedMediaUri(widget.reel.id);
      _media = _loadMedia();
      _watched = Duration.zero;
      _viewRecorded = false;
      _photoReady = false;
      _automaticRefreshes = 0;
      if (!widget.isActive) {
        unawaited(_playback.setActive(false).catchError((Object _) {}));
      }
      // Page selection and host visibility are independent. A replaced
      // coordinator must retain both gates even when this page is inactive;
      // selecting it later must not start a decoder behind a hidden host.
      if (_playbackSuspended) {
        unawaited(_applyPlaybackSuspension());
      }
    } else if (oldWidget.isActive != widget.isActive) {
      unawaited(_playback.setActive(widget.isActive).catchError((Object _) {}));
    }
    if (oldWidget.isHostVisible != widget.isHostVisible ||
        oldWidget.suspendPlayback != widget.suspendPlayback) {
      unawaited(_applyPlaybackSuspension());
    }
    if (sourceChanged || oldWidget.isActive != widget.isActive) {
      _syncWatchTimer();
    }
  }

  @override
  void dispose() {
    _retireDetails();
    _watchTimer?.cancel();
    _mediaHeartTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _soundOn.removeListener(_onSoundPreferenceChanged);
    _ownSoundOn?.dispose();
    _playback.removeListener(_onPlaybackChanged);
    _playback.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    if (!resumed) _retireDetails();
    unawaited(_applyPlaybackSuspension());
  }

  /// Everything that must silence a Reel without counting as a hand-pause.
  ///
  /// A DOCKED thread is deliberately absent from this list (D5, the ADR-170
  /// amendment): the wide panel sits beside the Reel and covers none of it,
  /// so reading the conversation while the Reel plays is the whole point of
  /// that layout. The phone SHEET does cover the Reel, and it still suspends
  /// — through [_routeIsCurrent], because a sheet is a pushed route.
  bool get _playbackSuspended =>
      !_appResumed ||
      !_routeIsCurrent ||
      !widget.isHostVisible ||
      widget.suspendPlayback;

  Future<void> _applyPlaybackSuspension() {
    _syncWatchTimer();
    return _playback
        .setAutoplaySuspended(_playbackSuspended)
        .catchError((Object _) {});
  }

  void _onSoundPreferenceChanged() {
    unawaited(_playback.setMuted(!_soundOn.value).catchError((Object _) {}));
    if (mounted) setState(() {});
  }

  void _toggleSound() => _soundOn.value = !_soundOn.value;

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    try {
      await _playback.toggle();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              AppLocalizations.of(context).text(
                'This audio is unavailable right now.',
                'Ten dźwięk jest teraz niedostępny.',
              ),
            ),
          ),
        );
    }
  }

  /// The backing-track line: attribution and, when the Reel has one, its own
  /// play/pause. It predates board 08 and is kept on BOTH stages — removing a
  /// Reel's only way to start its authored audio would be a regression, not a
  /// redesign.
  Widget? _buildSoundChip() {
    final hasChip =
        widget.reel.backingAudio != null ||
        widget.reel.composition.audioAttribution.isNotEmpty;
    if (!hasChip) return null;
    return _SoundChip(
      reel: widget.reel,
      showToggle: widget.reel.backingAudio != null,
      audioPlaying: _playback.isPlaying,
      audioLoading: _playback.isLoading,
      audioEnabled: _playback.canToggle,
      onAudio: _togglePlayback,
    );
  }

  void _openAuthor() {
    final seam = widget.onOpenAuthor;
    if (seam != null) {
      seam(widget.reel);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: widget.reel.authorId,
        displayName: widget.reel.authorName,
      ),
    );
  }

  Future<void> _share() =>
      widget.onShare?.call() ??
      showReelShareSheet(
        context,
        reelId: widget.reel.id,
        service: widget.service,
      );

  void _handleMediaDoubleTap() {
    if (!widget.isActive ||
        _playbackSuspended ||
        !widget.reel.availability.isAvailableAt(_now.toUtc())) {
      return;
    }
    final mediaLike = widget.onMediaLike;
    // An already-liked Yeel still acknowledges the familiar gesture. Without
    // either that state or a mutation seam, drawing a heart would promise a
    // change the current viewer cannot make.
    if (mediaLike == null && !widget.reel.callerLiked) return;

    _mediaHeartTimer?.cancel();
    setState(() {
      _mediaHeartPulse++;
      _mediaHeartVisible = true;
    });
    _mediaHeartTimer = Timer(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      setState(() => _mediaHeartVisible = false);
    });

    // Double-tap is one-way. The regular heart remains the explicit toggle.
    if (widget.reel.callerLiked ||
        widget.likePending ||
        _mediaLikeFlight != null ||
        mediaLike == null) {
      return;
    }
    final flight = Object();
    _mediaLikeFlight = flight;
    unawaited(_submitMediaLike(mediaLike, flight));
  }

  Future<void> _submitMediaLike(
    Future<void> Function() mediaLike,
    Object flight,
  ) async {
    try {
      await mediaLike();
    } finally {
      // The feed has already published callerLiked/likePending before its
      // future completes. Clearing this local single-flight latch therefore
      // permits only a genuine retry after a refusal, never a parallel call.
      // Identity protects a replacement Reel from a late completion that
      // belonged to the old source.
      if (identical(_mediaLikeFlight, flight)) _mediaLikeFlight = null;
    }
  }

  Widget _buildMediaLikeSurface(BuildContext context, Widget child) {
    final duration = AppMotion.resolve(
      context,
      const Duration(milliseconds: 180),
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          key: const ValueKey<String>('reel-media-like-surface'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onDoubleTap: _handleMediaDoubleTap,
          child: child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                key: const ValueKey<String>('reel-media-like-heart-effect'),
                duration: duration,
                reverseDuration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .72, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: _mediaHeartVisible
                    ? Icon(
                        Icons.favorite_rounded,
                        key: ValueKey<int>(_mediaHeartPulse),
                        size: 104,
                        color: Colors.white,
                        shadows: const <Shadow>[
                          Shadow(color: Color(0x8A000000), blurRadius: 22),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('reel-media-like-heart-hidden'),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The decoder must survive a change of SHAPE, not only of size: crossing
  /// 600 swaps the immersive stack for the stacked card, and a short window
  /// swaps it back. A global key reparents the one media subtree instead of
  /// letting Flutter rebuild it — and build a second decoder with it
  /// (`reels_immersive_redesign_test.dart` "one decoder survives responsive
  /// reflow").
  final GlobalKey _mediaKey = GlobalKey();

  /// Wraps the visible progress hairline on whichever stage is mounted, so
  /// the scrub band maps a finger onto the bar's real extent.
  final GlobalKey _progressTrackKey = GlobalKey();

  Widget _buildMedia(
    BuildContext context, {
    required EdgeInsets overlaySafeInsets,
  }) => KeyedSubtree(
    key: _mediaKey,
    child: _buildMediaSource(context, overlaySafeInsets: overlaySafeInsets),
  );

  Widget _buildMediaSource(
    BuildContext context, {
    required EdgeInsets overlaySafeInsets,
  }) {
    final copy = AppLocalizations.of(context);
    return FutureBuilder<Uri>(
      key: ValueKey(_mediaRevision),
      future: _media,
      initialData: _initialMediaUri,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return YoErrorState(
            message: copy.text(
              'This Yeel is unavailable right now.',
              'Ten Yeel jest teraz niedostępny.',
            ),
            onRetry: _refreshMedia,
            compact: true,
          );
        }
        final uri = snapshot.data;
        if (uri == null) {
          return YoLoadingIndicator(
            message: copy.text('Loading Yeel', 'Ładowanie Yeela'),
          );
        }
        final videoPlaybackFactory = widget.videoPlaybackFactory;
        if (widget.reel.media.kind == ReelMediaKind.video &&
            videoPlaybackFactory != null) {
          return _buildMediaLikeSurface(
            context,
            _HostedReelVideoPlayer(
              uri: uri,
              reel: widget.reel,
              playback: _playback,
              playbackFactory: videoPlaybackFactory,
              videoBuilder: widget.videoBuilder,
              onToggle: _togglePlayback,
              fillViewport: widget.fillViewport,
              overlaySafeInsets: overlaySafeInsets,
            ),
          );
        }
        if (widget.reel.media.kind == ReelMediaKind.video &&
            widget.videoBuilder == null) {
          return _buildMediaLikeSurface(
            context,
            _DefaultReelVideoPlayer(
              uri: uri,
              reel: widget.reel,
              playback: _playback,
              controllerFactory: widget.videoControllerFactory,
              onToggle: _togglePlayback,
              onRetry: _refreshMedia,
              onFailure: () => _refreshMedia(automatic: true),
              fillViewport: widget.fillViewport,
              overlaySafeInsets: overlaySafeInsets,
            ),
          );
        }
        final media = widget.reel.media.kind == ReelMediaKind.image
            ? _ReelPhoto(
                uri: uri,
                onReady: _onPhotoReady,
                onRetry: _refreshMedia,
                onFailure: () => _refreshMedia(automatic: true),
              )
            : widget.videoBuilder!(context, uri, widget.reel);
        return _buildMediaLikeSurface(
          context,
          ReelCompositionFrame(
            fillViewport: widget.fillViewport,
            overlayInsetsInViewport: true,
            overlaySafeInsets: overlaySafeInsets,
            composition: widget.reel.composition,
            media: media,
            mediaForeground: const _LegibilityScrim(),
            onOpenLink: (overlay) =>
                launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: copy.template(
        'Yeel by {author}',
        'Yeel użytkownika {author}',
        values: <String, Object>{'author': widget.reel.authorName},
      ),
      child: widget.fillViewport
          ? _buildImmersiveStage(context)
          : _buildCardStage(context),
    );
  }

  /// Below 600 inside the destination the media IS the screen. Its compact
  /// chrome follows the familiar short-video reading path: identity at the
  /// lower leading edge, actions down the trailing edge, sound above them
  /// and one hairline timeline at the bottom.
  ///
  /// [asCard] is the same composition inside a bordered 9:16 card: the shape
  /// a pointer width falls back to when the window is too short to stack a
  /// frame and a footer bar at a legible size. Nothing is lost there — the
  /// author, the caption and the four actions are the same controls, laid
  /// over the media instead of under it.
  Widget _buildImmersiveStage(BuildContext context, {bool asCard = false}) {
    final palette = context.appPalette;
    final radius = widget.borderRadius;
    return LayoutBuilder(
      builder: (context, viewport) => Center(
        child: AspectRatio(
          aspectRatio: asCard
              ? 9 / 16
              : viewport.hasBoundedHeight && viewport.maxHeight > 0
              ? viewport.maxWidth / viewport.maxHeight
              : 9 / 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final topInset = asCard ? 0.0 : widget.mediaTopInset;
              final mediaHeight = math.max(
                0.0,
                constraints.maxHeight - topInset,
              );
              final geometry = _ImmersiveOverlayGeometry.resolve(
                context,
                width: constraints.maxWidth,
                mediaHeight: mediaHeight,
                showIdentity: widget.showIdentity,
                showSound:
                    widget.reel.backingAudio != null ||
                    widget.reel.composition.audioAttribution.isNotEmpty,
              );
              final overlaySafeInsets = geometry.compositionInsets(
                context,
                top: asCard ? 56 : widget.mediaTopInset + 12,
              );
              return DecoratedBox(
                decoration: BoxDecoration(
                  // Only visible while the media loads or fails.
                  color: palette.surfaceSunken,
                  borderRadius: BorderRadius.circular(radius),
                  border: asCard ? Border.all(color: palette.border) : null,
                  boxShadow: asCard ? reelCardShadow(context) : null,
                ),
                child: ClipRRect(
                  key: const ValueKey('reel-viewport'),
                  borderRadius: BorderRadius.circular(
                    (radius - 1).clamp(0, double.infinity),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _buildMedia(
                        context,
                        overlaySafeInsets: overlaySafeInsets,
                      ),
                      // The empty area of this layer takes no hits — its scrim
                      // is behind an IgnorePointer — so the playback surface
                      // underneath still receives them.
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: 0,
                        child: KeyedSubtree(
                          key: const ValueKey('reel-footer'),
                          child: _OverlayFooter(
                            reel: widget.reel,
                            geometry: geometry,
                            showIdentity: widget.showIdentity,
                            audioPlaying: _playback.isPlaying,
                            audioLoading: _playback.isLoading,
                            audioEnabled: _playback.canToggle,
                            showAudioToggle: widget.reel.backingAudio != null,
                            position: _playback.position,
                            timeline: _playback.timelineDuration,
                            scrub: _playback,
                            trackKey: _progressTrackKey,
                            friendService: widget.friendService,
                            friendRelationshipStore:
                                widget.friendRelationshipStore,
                            viewerUid: widget.service.currentUserId,
                            onAudio: _togglePlayback,
                            onOpenAuthor: _openAuthor,
                            onCaption: () => _openDetails(),
                            onMore: () => _openDetails(includeActions: true),
                            onDelete: widget.onDelete,
                            onReport: widget.onReport,
                            onLike: widget.onLike,
                            onComments: widget.onComments,
                            onShare: _share,
                            likePending: widget.likePending,
                            commentsOpen: widget.commentsOpen,
                            soundToggle:
                                widget.reel.media.kind == ReelMediaKind.video
                                ? (showLabel) => _SoundToggle(
                                    soundOn: _soundOn.value,
                                    onToggle: _toggleSound,
                                    showLabel: showLabel,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// From 600 up: board 08's card — the authored frame on top, and under it
  /// a real footer bar with the author, the friend control, the caption and
  /// the four actions, on the card's own surface instead of over the media.
  ///
  /// The frame stays height-bound: it takes what the stage has left after the
  /// footer, so a short window shrinks the Reel instead of pushing its
  /// actions off the bottom.
  /// Narrower than this and the stacked shape stops being a Reel: the frame
  /// and its footer both give way to the overlay composition.
  static const double _minimumStackedFrameWidth =
      ReelStageFooterBar.minimumFrameWidth;

  /// One derivation, owned by the footer bar itself, so the stage that has
  /// to anchor overlays to this frame reads the same number the card does.
  double _stageFooterHeight(BuildContext context, {required bool sideBySide}) =>
      ReelStageFooterBar.heightFor(
        context,
        hasCaption: widget.reel.composition.caption.isNotEmpty,
        sideBySide: sideBySide,
      );

  Widget _buildCardStage(BuildContext context) {
    final palette = context.appPalette;
    final radius = widget.borderRadius;
    return LayoutBuilder(
      builder: (context, viewport) {
        double frameWidthFor({required bool sideBySide}) {
          if (!viewport.hasBoundedHeight) return viewport.maxWidth;
          final available = math.max(
            0.0,
            viewport.maxHeight -
                _stageFooterHeight(context, sideBySide: sideBySide),
          );
          return math.min(viewport.maxWidth, available * 9 / 16);
        }

        // Two closed-form steps rather than a feedback loop: assume the
        // roomy footer, and fall back to the folded one only if the frame
        // that assumption produces is too narrow to hold it.
        final wideFooter = frameWidthFor(sideBySide: true);
        final frameWidth =
            wideFooter >= ReelStageFooterBar.sideBySideWidthFor(context)
            ? wideFooter
            : frameWidthFor(sideBySide: false);
        // A window short enough that stacking would leave a sliver of a Reel
        // — a desktop browser at 420 px of height, or an accessibility text
        // size that doubles every row of the footer — gets the overlay
        // composition instead. A 79 px wide Reel is not a smaller design, it
        // is a broken one.
        if (frameWidth < _minimumStackedFrameWidth) {
          return _buildImmersiveStage(context, asCard: true);
        }
        return Center(
          child: SizedBox(
            width: frameWidth > 0 ? frameWidth : viewport.maxWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: palette.border),
                boxShadow: reelCardShadow(context),
              ),
              child: ClipRRect(
                key: const ValueKey('reel-viewport'),
                borderRadius: BorderRadius.circular(
                  (radius - 1).clamp(0, double.infinity),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Flexible as well as measured: on the very first frame
                    // the footer's real height is not known yet, and the
                    // frame must give way rather than overflow the stage.
                    Flexible(
                      // `Align` is here only to LOOSEN the stretch Column's
                      // tight width for this one child. With a tight width
                      // the 9:16 band keeps the card's width and gives up
                      // height, and the media inside it letterboxes against
                      // `surfaceSunken` — the ledge S13 named. Loosened, the
                      // band gives up WIDTH instead: it stays exactly 9:16,
                      // the sunken well is exactly the media, and anything
                      // the footer overruns its budget by shows as the
                      // card's own surface beside the frame. When the budget
                      // holds — every width and text size the boards use —
                      // the band is the card's full width and this changes
                      // nothing. The reader-expanded caption is the case no
                      // closed-form budget can predict.
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: 1,
                        child: AspectRatio(
                          key: const ValueKey<String>('reel-media-band'),
                          aspectRatio: 9 / 16,
                          child: ColoredBox(
                            // Only visible while the media loads or fails.
                            color: palette.surfaceSunken,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                _buildMedia(
                                  context,
                                  overlaySafeInsets: _frameCompositionInsets(),
                                ),
                                PositionedDirectional(
                                  start: 0,
                                  end: 0,
                                  bottom: 0,
                                  child: ReelOverlayMeasure(
                                    key: const ValueKey('reel-footer'),
                                    onSize: (size) {
                                      if (mounted &&
                                          (_frameControlsHeight - size.height)
                                                  .abs() >
                                              .5) {
                                        setState(
                                          () => _frameControlsHeight =
                                              size.height,
                                        );
                                      }
                                    },
                                    child: _StageFrameControls(
                                      position: _playback.position,
                                      total: _playback.timelineDuration,
                                      scrub: _playback,
                                      trackKey: _progressTrackKey,
                                      showProgressTimes:
                                          widget.reel.media.kind ==
                                          ReelMediaKind.video,
                                      soundChip: _buildSoundChip(),
                                      soundToggle:
                                          widget.reel.media.kind ==
                                              ReelMediaKind.video
                                          ? (showLabel) => _SoundToggle(
                                              soundOn: _soundOn.value,
                                              onToggle: _toggleSound,
                                              showLabel: showLabel,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    ReelStageFooterBar(
                      key: const ValueKey('reel-stage-footer'),
                      reel: widget.reel,
                      friendService: widget.friendService,
                      friendRelationshipStore: widget.friendRelationshipStore,
                      viewerUid: widget.service.currentUserId,
                      captionExpanded: _captionExpanded,
                      onToggleCaption: () =>
                          setState(() => _captionExpanded = !_captionExpanded),
                      onOpenAuthor: _openAuthor,
                      onLike: widget.onLike,
                      onComments: widget.onComments,
                      onShare: _share,
                      onMore: () => _openDetails(includeActions: true),
                      likePending: widget.likePending,
                      commentsOpen: widget.commentsOpen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReelPhoto extends StatelessWidget {
  const _ReelPhoto({
    required this.uri,
    required this.onReady,
    required this.onRetry,
    required this.onFailure,
  });

  final Uri uri;
  final VoidCallback onReady;
  final VoidCallback onRetry;
  final VoidCallback onFailure;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      frameBuilder: (context, child, frame, synchronouslyLoaded) {
        if (frame != null || synchronouslyLoaded) onReady();
        return child;
      },
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onFailure());
        return _ReelMediaError(
          message: AppLocalizations.of(context).text(
            'This Yeel is unavailable right now.',
            'Ten Yeel jest teraz niedostępny.',
          ),
          onRetry: onRetry,
        );
      },
    );
  }
}

/// A media-frame error has to fit landscape and keyboard-reduced canvases.
/// The shared page error includes a large illustration and heading; inside a
/// Yeel those consume more height than the fitted composition owns. This local
/// state keeps the same live explanation and a full-size retry target. On a
/// very shallow canvas it reduces to that labelled target, which also leaves
/// the feed's vertical swipe gesture unobstructed.
class _ReelMediaError extends StatelessWidget {
  const _ReelMediaError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final compact =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < 220 + math.max(0, scale - 1) * 80;
        final retry = copy.text('Try again', 'Spróbuj ponownie');
        if (compact) {
          return Center(
            child: Semantics(
              container: true,
              liveRegion: true,
              button: true,
              label: '$message $retry',
              onTap: onRetry,
              excludeSemantics: true,
              child: IconButton(
                tooltip: retry,
                onPressed: onRetry,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: palette.dangerForeground,
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  container: true,
                  liveRegion: true,
                  label: message,
                  excludeSemantics: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 32,
                        color: palette.dangerForeground,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(retry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The sound switch for a video Reel.
///
/// It exists because autoplay is silent: without a control on the frame the
/// only way back to sound would be a second tap that also stops the video.
///
/// Sound is not playback. This pill says which of the two states the AUDIO is
/// in — glyph and words together, never colour alone — while pausing remains
/// the tap on the frame itself. The spoken name stays the ACTION, because
/// that is what activating it does, and the semantic `toggled` carries the
/// state a second time for a reader who never sees the words.
class _SoundToggle extends StatelessWidget {
  const _SoundToggle({
    required this.soundOn,
    required this.onToggle,
    this.showLabel = true,
  });

  final bool soundOn;
  final VoidCallback onToggle;

  /// False only on a frame with no room for the words. The control itself
  /// never disappears — sound would then have no way back on — so it falls
  /// back to the 48 px plate it was before board 08 gave it a label.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final action = soundOn
        ? copy.text('Turn sound off', 'Wyłącz dźwięk')
        : copy.text('Turn sound on', 'Włącz dźwięk');
    final state = soundOn
        ? copy.contextualText('reels.soundOn', 'Sound on', 'Dźwięk włączony')
        : copy.contextualText(
            'reels.soundOff',
            'Sound off',
            'Dźwięk wyłączony',
          );
    final icon = soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded;
    if (!showLabel) {
      return Semantics(
        container: true,
        button: true,
        toggled: soundOn,
        label: action,
        onTap: onToggle,
        excludeSemantics: true,
        child: ReelOverlayPlateButton(
          key: const ValueKey<String>('reel-sound-toggle'),
          icon: icon,
          semanticLabel: action,
          onTap: onToggle,
        ),
      );
    }
    return Semantics(
      container: true,
      button: true,
      toggled: soundOn,
      label: action,
      onTap: onToggle,
      excludeSemantics: true,
      child: AccessibleTapRegion(
        key: const ValueKey<String>('reel-sound-toggle'),
        onTap: onToggle,
        semanticLabel: action,
        tooltip: action,
        borderRadius: 999,
        minimumSize: const Size(48, 48),
        focusContrastColor: Colors.black,
        // Slim look: a 32 px pill (the 48 px target is the tap region's),
        // 18 px glyph, 13 px label. Same plate, same words, same toggle.
        child: Container(
          // A floor, not a height: an accessibility text size grows the
          // pill instead of clipping its word.
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: reelOverlayPlateColor,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    shadows: reelOverlayTextShadows,
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

/// What board 08 draws inside the frame's own bottom inset: the sound state
/// and the progress row, over the media and clear of the subject.
class _StageFrameControls extends StatelessWidget {
  const _StageFrameControls({
    required this.position,
    required this.total,
    required this.scrub,
    required this.trackKey,
    required this.showProgressTimes,
    this.soundToggle,
    this.soundChip,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final ReelScrubTarget scrub;
  final GlobalKey trackKey;
  final bool showProgressTimes;

  /// Built with the frame's own answer to "is there room for the words".
  final Widget Function(bool showLabel)? soundToggle;

  /// The backing-track attribution and transport, where the Reel has one.
  final Widget? soundChip;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // A frame narrower than its own labels keeps the progress bar and
        // drops the plates: sound is still reachable from the frame tap and
        // the bar still carries the spoken position.
        final roomForLabels =
            !constraints.hasBoundedWidth || constraints.maxWidth >= 200 * scale;
        return _frameControls(
          context,
          toggle: soundToggle == null ? null : soundToggle!(roomForLabels),
          chip: roomForLabels ? soundChip : null,
        );
      },
    );
  }

  Widget _frameControls(
    BuildContext context, {
    required Widget? toggle,
    required Widget? chip,
  }) {
    return Stack(
      // The scrub band's time label may rise above this block at large text.
      clipBehavior: Clip.none,
      children: <Widget>[
        // A sibling behind the controls, never their parent: a decorated box
        // hit-tests as opaque over its whole area and would swallow the tap
        // that pauses the video.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0x99000000)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Photo Yeels intentionally omit numeric elapsed time. Stretch
            // the remaining bar across the frame so removing that label does
            // not also collapse its only progress cue to zero width.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (toggle != null || chip != null) ...<Widget>[
                _ScrubChromeFade(
                  scrubbing: scrub.isScrubbing,
                  child: Wrap(
                    spacing: AppRhythm.tight,
                    runSpacing: AppRhythm.tight,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[?toggle, ?chip],
                  ),
                ),
                const SizedBox(height: AppRhythm.title),
              ],
              if (showProgressTimes)
                ReelProgressRow(
                  position: position,
                  total: total,
                  announce: !scrub.canSeek,
                  barKey: trackKey,
                )
              else
                KeyedSubtree(
                  key: trackKey,
                  child: ReelProgressBar(
                    position: position,
                    total: total,
                    announce: !scrub.canSeek,
                  ),
                ),
            ],
          ),
        ),
        // An overlay, not a row: the Column above keeps its measured height,
        // so the frame geometry every stage test pins does not move.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _frameScrubBandHeight,
          child: ReelProgressScrubber(
            key: const ValueKey<String>('reel-progress-scrub'),
            target: scrub,
            position: position,
            total: total,
            trackKey: trackKey,
            showTimeLabel: !showProgressTimes,
          ),
        ),
      ],
    );
  }
}

/// Board 08's footer bar: who published this Reel, whether you can add them,
/// what they wrote, and the four things you can do about it — on the card's
/// own surface, under the media, never over the subject.
///
/// Horizontal by contract (spec §7 line 127): the actions are a row of four,
/// not a copied vertical column. The row folds onto a second line only when
/// it is measured not to fit, so a long locale at an accessibility text size
/// keeps every 48 px target instead of clipping one.
class ReelStageFooterBar extends StatelessWidget {
  const ReelStageFooterBar({
    required this.reel,
    required this.captionExpanded,
    required this.onToggleCaption,
    required this.onOpenAuthor,
    required this.onShare,
    required this.onMore,
    required this.likePending,
    required this.commentsOpen,
    this.friendService,
    this.friendRelationshipStore,
    this.viewerUid,
    this.onLike,
    this.onComments,
    super.key,
  });

  final Reel reel;
  final FriendService? friendService;
  final ReelFriendRelationshipStore? friendRelationshipStore;
  final String? viewerUid;
  final bool captionExpanded;
  final VoidCallback onToggleCaption;
  final VoidCallback onOpenAuthor;
  final Future<void> Function() onShare;
  final VoidCallback onMore;
  final bool likePending;
  final bool commentsOpen;
  final VoidCallback? onLike;
  final VoidCallback? onComments;

  static const double minimumHeight = 88;

  /// Narrower than this and the stacked shape stops being a Reel: the frame
  /// and its footer both give way to the overlay composition, and the card
  /// then fills the column it is centred in.
  static const double minimumFrameWidth = 200;

  /// Below this the actions take their own line: four 48 px targets with
  /// their counts need roughly 260, and the author's name needs the rest.
  /// It grows with the reader's text size, because so do all of those.
  static const double sideBySideWidth = 480;

  static double sideBySideWidthFor(BuildContext context) =>
      sideBySideWidth * MediaQuery.textScalerOf(context).scale(1);

  /// What the footer bar will be tall, computed rather than measured.
  ///
  /// Measuring it would be circular — the footer's height decides the
  /// frame's width, and the frame's width decides whether the footer's row
  /// folds — and a layout that feeds its own measurement back into itself
  /// never settles. Every part of this height is a known text metric at the
  /// reader's own size, so it can simply be derived.
  static double heightFor(
    BuildContext context, {
    required bool hasCaption,
    required bool sideBySide,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    // A 48 target that grows with the label inside it.
    final control = math.max(48.0, scaler.scale(14) * 1.4 + 16);
    // Both text runs are budgeted at the WHOLE pixel the engine lays them
    // out on, and the caption at `bodyMedium`'s real 1.5 line height. The
    // 1.45 this used to assume was 0.7 px short per line, which at x1 left
    // the media 0.4 px narrower than the card it sits in on every width —
    // a budget that is short by any amount is a ledge, not a rounding.
    final name = (scaler.scale(18) * 1.4).ceilToDouble();
    final captionLine = (scaler.scale(14) * 1.5).ceilToDouble();
    // At an accessibility text size the name and the friend control take a
    // line each; below that they share one — and the footer now lays them
    // out that way, so this budget and the widget agree.
    final identityRow = scaler.scale(1) >= 1.6
        ? math.max(control, name) + AppRhythm.hairline + control
        : math.max(control, name);
    final identity =
        identityRow + (hasCaption ? AppRhythm.tight + 2 * captionLine + 4 : 0);
    final content = sideBySide
        ? math.max(identity, control)
        : identity + AppRhythm.item + control;
    // The 16/16 vertical padding, and never less than the bar's own floor.
    return math.max(minimumHeight, 32 + content);
  }

  /// The width the card — and therefore the media frame inside it — will
  /// take in [viewport]. The stage uses it to anchor the `›` next
  /// affordance to the frame rather than to the column the frame is
  /// centred in, which is what left the plate standing in open background.
  static double frameWidthFor(
    BuildContext context,
    BoxConstraints viewport, {
    required bool hasCaption,
  }) {
    if (!viewport.hasBoundedHeight) return viewport.maxWidth;
    double widthFor({required bool sideBySide}) {
      final available = math.max(
        0.0,
        viewport.maxHeight -
            heightFor(context, hasCaption: hasCaption, sideBySide: sideBySide),
      );
      return math.min(viewport.maxWidth, available * 9 / 16);
    }

    final wide = widthFor(sideBySide: true);
    return wide >= sideBySideWidthFor(context)
        ? wide
        : widthFor(sideBySide: false);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final friends = friendService;
    final viewer = viewerUid;
    final caption = reel.composition.caption;

    final actions = ReelEngagementBar(
      likeCount: reel.likeCount,
      commentCount: reel.commentCount,
      liked: reel.callerLiked,
      likePending: likePending,
      commentsOpen: commentsOpen,
      variant: ReelEngagementBarVariant.footer,
      railAdditional: <Widget>[
        ReelFooterAction(
          actionKey: const ValueKey('reel-share-action'),
          icon: Icons.send_outlined,
          semanticLabel: copy.text('Share Yeel', 'Udostępnij Yeel'),
          onTap: () => unawaited(onShare()),
        ),
      ],
      railTrailing: ReelFooterAction(
        actionKey: const ValueKey('reel-more-action'),
        icon: Icons.more_horiz_rounded,
        semanticLabel: MaterialLocalizations.of(context).moreButtonTooltip,
        onTap: onMore,
      ),
      onLike: onLike,
      onComments: onComments,
    );

    // The relationship action is live data: its localized error and pending
    // labels can be materially wider than the normal CTA. Let the identity
    // group take a second row when it needs one instead of squeezing the
    // author's avatar/name below their own minimum readable width.
    final author = ReelAuthorRow(
      reel: reel,
      variant: ReelAuthorRowVariant.panel,
      onTap: onOpenAuthor,
    );
    final friend = friends != null && viewer != null && viewer != reel.authorId
        ? _ReelFriendButton(
            userId: reel.authorId,
            displayName: reel.authorName,
            viewerUid: viewer,
            friendService: friends,
            relationshipStore: friendRelationshipStore,
          )
        : null;
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppRhythm.item,
          runSpacing: AppRhythm.hairline,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[author, ?friend],
        ),
        if (caption.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppRhythm.tight),
          Semantics(
            container: true,
            button: true,
            expanded: captionExpanded,
            label: caption,
            onTap: onToggleCaption,
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey<String>('reel-stage-caption'),
              onTap: onToggleCaption,
              borderRadius: AppRadius.sm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  caption,
                  maxLines: captionExpanded ? 8 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Container(
      key: const ValueKey<String>('reel-stage-footer-bar'),
      color: palette.surface,
      constraints: const BoxConstraints(minHeight: minimumHeight),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide =
              constraints.maxWidth >= sideBySideWidthFor(context);
          if (sideBySide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: identity),
                const SizedBox(width: AppRhythm.title),
                Flexible(child: actions),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              identity,
              const SizedBox(height: AppRhythm.item),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// The Yeel author action backed by the app's canonical friend-request flow.
///
/// Relationship state is resolved before the action appears, so an existing
/// friend never flashes an invalid CTA. A request already sent stays visibly
/// pending and disabled, while an incoming request uses the same explicit
/// accept mutation as Add friends and the profile preview.
class _ReelFriendButton extends StatefulWidget {
  const _ReelFriendButton({
    required this.userId,
    required this.displayName,
    required this.viewerUid,
    required this.friendService,
    this.relationshipStore,
    this.onMedia = false,
  });

  final String userId;
  final String displayName;
  final String viewerUid;
  final FriendService friendService;
  final ReelFriendRelationshipStore? relationshipStore;
  final bool onMedia;

  @override
  State<_ReelFriendButton> createState() => _ReelFriendButtonState();
}

class _ReelFriendButtonState extends State<_ReelFriendButton> {
  ReelFriendRelationshipStore? _ownedStore;
  ReelFriendRelationshipEntry? _entry;

  @override
  void initState() {
    super.initState();
    _attachEntry();
  }

  @override
  void didUpdateWidget(covariant _ReelFriendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.viewerUid != widget.viewerUid ||
        !identical(oldWidget.friendService, widget.friendService) ||
        !identical(oldWidget.relationshipStore, widget.relationshipStore)) {
      _detachEntry();
      _ownedStore?.dispose();
      _ownedStore = null;
      _attachEntry();
    }
  }

  void _attachEntry() {
    final store =
        widget.relationshipStore ??
        (_ownedStore ??= ReelFriendRelationshipStore(
          friendService: widget.friendService,
        ));
    _entry = store.entryFor(
      viewerUid: widget.viewerUid,
      authorId: widget.userId,
    )..addListener(_relationshipChanged);
  }

  void _detachEntry() {
    _entry?.removeListener(_relationshipChanged);
    _entry = null;
  }

  void _relationshipChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _detachEntry();
    _ownedStore?.dispose();
    super.dispose();
  }

  Future<void> _act() async {
    final entry = _entry;
    final previous = entry?.status;
    if (entry == null ||
        entry.busy ||
        (previous != FriendRelationshipStatus.none &&
            previous != FriendRelationshipStatus.requestReceived)) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = AppLocalizations.of(context);
    try {
      final next = await entry.submit(displayName: widget.displayName);
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              next == FriendRelationshipStatus.friends
                  ? copy.template(
                      'You and {name} are now friends.',
                      'Ty i {name} jesteście teraz znajomymi.',
                      values: <String, Object>{'name': widget.displayName},
                    )
                  : copy.template(
                      'Friend request sent to {name}.',
                      'Wysłano zaproszenie do {name}.',
                      values: <String, Object>{'name': widget.displayName},
                    ),
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(friendRequestErrorMessage(copy, error)),
          ),
        );
    }
  }

  void _retry() {
    final entry = _entry;
    if (entry == null || entry.loading) return;
    unawaited(entry.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final status = entry?.status;
    if (widget.userId.isEmpty ||
        widget.userId == widget.viewerUid ||
        status == FriendRelationshipStatus.friends ||
        status == FriendRelationshipStatus.blocked) {
      return const SizedBox.shrink();
    }

    final copy = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final loadError = entry?.loadError;
    if (entry == null || (entry.loading && loadError == null)) {
      return const SizedBox.shrink();
    }
    if (loadError != null) {
      return _relationshipError(
        context,
        copy: copy,
        checking: entry.loading,
        reduceMotion: reduceMotion,
      );
    }
    if (status == null) return const SizedBox.shrink();
    final requested = status == FriendRelationshipStatus.requestSent;
    final received = status == FriendRelationshipStatus.requestReceived;
    final enabled = !entry.busy && !requested;
    final label = entry.busy
        ? copy.text('Sending…', 'Wysyłanie…')
        : requested
        ? copy.text('Requested', 'Wysłano zaproszenie')
        : received
        ? copy.text('Accept', 'Akceptuj')
        : copy.text('Add friend', 'Dodaj znajomego');
    final semanticLabel = entry.busy
        ? copy.template(
            'Updating friend request for {name}',
            'Aktualizowanie zaproszenia dla {name}',
            values: <String, Object>{'name': widget.displayName},
          )
        : requested
        ? copy.template(
            'Friend request sent to {name}',
            'Wysłano zaproszenie do {name}',
            values: <String, Object>{'name': widget.displayName},
          )
        : received
        ? copy.template(
            'Accept friend request from {name}',
            'Akceptuj zaproszenie od {name}',
            values: <String, Object>{'name': widget.displayName},
          )
        : copy.template(
            'Add {name} as a friend',
            'Dodaj {name} do znajomych',
            values: <String, Object>{'name': widget.displayName},
          );
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(
        AppSizing.minimumTouchTarget,
        AppSizing.minimumTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
      shape: const StadiumBorder(),
      foregroundColor: widget.onMedia ? Colors.white : null,
      disabledForegroundColor: widget.onMedia
          ? Colors.white.withValues(alpha: .72)
          : null,
      side: widget.onMedia
          ? BorderSide(color: Colors.white.withValues(alpha: .72))
          : null,
    );
    final icon = entry.busy && !reduceMotion
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            requested
                ? Icons.hourglass_top_rounded
                : received
                ? Icons.check_circle_rounded
                : Icons.person_add_alt_1_rounded,
            size: 18,
          );
    return Semantics(
      container: true,
      // Reuse the button's one semantics node as the status announcement.
      // A second hidden live region would speak the same update twice.
      liveRegion: entry.busy,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? () => unawaited(_act()) : null,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        key: ValueKey<String>('reel-friend-${widget.userId}'),
        onPressed: enabled ? () => unawaited(_act()) : null,
        style: style,
        icon: icon,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _relationshipError(
    BuildContext context, {
    required AppLocalizations copy,
    required bool checking,
    required bool reduceMotion,
  }) {
    final colors = Theme.of(context).colorScheme;
    final label = checking
        ? copy.text('Checking…', 'Sprawdzanie…')
        : copy.text('Try again', 'Spróbuj ponownie');
    final semanticLabel = checking
        ? copy.template(
            'Checking friendship with {name}',
            'Sprawdzanie relacji ze znajomym {name}',
            values: <String, Object>{'name': widget.displayName},
          )
        : copy.template(
            'Could not check friendship with {name}. Try again.',
            'Nie udało się sprawdzić relacji z {name}. Spróbuj ponownie.',
            values: <String, Object>{'name': widget.displayName},
          );
    final foreground = widget.onMedia ? Colors.white : colors.error;
    final icon = checking && !reduceMotion
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Icon(
            checking ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
            size: 18,
          );
    return Semantics(
      key: ValueKey<String>('reel-friend-error-${widget.userId}'),
      container: true,
      liveRegion: true,
      button: true,
      enabled: !checking,
      label: semanticLabel,
      onTap: checking ? null : _retry,
      excludeSemantics: true,
      child: ConstrainedBox(
        // Polish "Spróbuj ponownie" is deliberately allowed two lines here.
        // Its full phrase remains visible without taking the entire identity
        // row away from the author's avatar and name.
        constraints: const BoxConstraints(maxWidth: 154),
        child: Tooltip(
          message: semanticLabel,
          excludeFromSemantics: true,
          child: OutlinedButton(
            key: ValueKey<String>('reel-friend-${widget.userId}'),
            onPressed: checking ? null : _retry,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(
                AppSizing.minimumTouchTarget,
                AppSizing.minimumTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppRhythm.item,
                vertical: AppRhythm.hairline,
              ),
              shape: const StadiumBorder(),
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: .72),
              backgroundColor: widget.onMedia
                  ? Colors.black.withValues(alpha: .54)
                  : null,
              side: BorderSide(color: foreground.withValues(alpha: .82)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                icon,
                const SizedBox(width: AppRhythm.tight),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
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

/// A Reel driven by a video engine the host supplied instead of the built-in
/// decoder. It owns exactly the same contract as [_DefaultReelVideoPlayer]:
/// attach on ready — which is what arms autoplay — and detach on disposal.
class _HostedReelVideoPlayer extends StatefulWidget {
  const _HostedReelVideoPlayer({
    required this.uri,
    required this.reel,
    required this.playback,
    required this.playbackFactory,
    required this.onToggle,
    this.videoBuilder,
    this.fillViewport = false,
    required this.overlaySafeInsets,
  });

  final Uri uri;
  final Reel reel;
  final ReelPlaybackCoordinator playback;
  final ReelVideoPlaybackFactory playbackFactory;
  final ReelVideoBuilder? videoBuilder;
  final bool fillViewport;
  final EdgeInsets overlaySafeInsets;
  final Future<void> Function() onToggle;

  @override
  State<_HostedReelVideoPlayer> createState() => _HostedReelVideoPlayerState();
}

class _HostedReelVideoPlayerState extends State<_HostedReelVideoPlayer> {
  ReelVideoPlayback? _driver;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant _HostedReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.playback, widget.playback)) {
      _detach(oldWidget.playback);
      _attach();
    }
  }

  void _attach() {
    final driver = widget.playbackFactory(widget.uri, widget.reel);
    _driver = driver;
    unawaited(widget.playback.attachVideo(driver).catchError((Object _) {}));
  }

  void _detach(ReelPlaybackCoordinator playback) {
    final driver = _driver;
    _driver = null;
    if (driver != null) {
      unawaited(playback.detachVideo(driver).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _detach(widget.playback);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.videoBuilder;
    return ReelPlaybackSurface(
      isPlaying: widget.playback.isPlaying,
      onToggle: widget.onToggle,
      child: ReelCompositionFrame(
        fillViewport: widget.fillViewport,
        overlayInsetsInViewport: true,
        overlaySafeInsets: widget.overlaySafeInsets,
        composition: widget.reel.composition,
        media: builder == null
            ? const ColoredBox(color: Colors.black)
            : builder(context, widget.uri, widget.reel),
        mediaForeground: const _LegibilityScrim(),
        onOpenLink: (overlay) =>
            launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
      ),
    );
  }
}

class _DefaultReelVideoPlayer extends StatefulWidget {
  const _DefaultReelVideoPlayer({
    required this.uri,
    required this.reel,
    required this.playback,
    this.controllerFactory,
    required this.onToggle,
    required this.onRetry,
    required this.onFailure,
    this.fillViewport = false,
    required this.overlaySafeInsets,
  });

  final Uri uri;
  final Reel reel;
  final ReelPlaybackCoordinator playback;
  final ReelNetworkVideoControllerFactory? controllerFactory;
  final Future<void> Function() onToggle;
  final VoidCallback onRetry;
  final VoidCallback onFailure;
  final bool fillViewport;
  final EdgeInsets overlaySafeInsets;

  @override
  State<_DefaultReelVideoPlayer> createState() =>
      _DefaultReelVideoPlayerState();
}

class _DefaultReelVideoPlayerState extends State<_DefaultReelVideoPlayer> {
  VideoPlayerController? _controller;
  _VideoPlayerPlayback? _playbackDriver;
  ReelPlaybackCoordinator? _attachedPlayback;
  final Map<VideoPlayerController, Future<void>> _controllerRetirements =
      Map<VideoPlayerController, Future<void>>.identity();
  final Map<VideoPlayerController, Future<void>> _controllerAttachments =
      Map<VideoPlayerController, Future<void>>.identity();
  Object? _error;
  bool _lastPlaying = false;
  int _controllerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _DefaultReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.playback, widget.playback) ||
        !identical(oldWidget.controllerFactory, widget.controllerFactory)) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_controllerGeneration;
    final reel = widget.reel;
    final playback = widget.playback;
    final controller =
        widget.controllerFactory?.call(widget.uri) ??
        VideoPlayerController.networkUrl(
          widget.uri,
          // A Reel that starts itself must never take the audio route away from
          // something the person is actually in. AVAudioSession is process-global
          // on iOS and the codebase keeps it under LiveKit/recording control, so
          // this player mixes rather than interrupting a live room or a recording.
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
    _controller = controller;
    try {
      await controller.initialize();
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller);
        return;
      }
      await controller.setLooping(false);
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller);
        return;
      }
      await controller.setVolume(reel.composition.originalAudioVolume / 100);
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller);
        return;
      }
      await controller.seekTo(
        Duration(milliseconds: reel.composition.trimStartMs),
      );
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller);
        return;
      }
      final driver = _VideoPlayerPlayback(controller);
      _playbackDriver = driver;
      _attachedPlayback = playback;
      _lastPlaying = controller.value.isPlaying;
      controller.addListener(_handlePlayback);
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller, driver: driver, playback: playback);
        return;
      }
      final attachment = playback.attachVideo(driver);
      _controllerAttachments[controller] = attachment;
      try {
        await attachment;
      } finally {
        if (identical(_controllerAttachments[controller], attachment)) {
          _controllerAttachments.remove(controller);
        }
      }
      if (!_isCurrentController(generation, controller)) {
        await _retireController(controller, driver: driver, playback: playback);
        return;
      }
      setState(() => _error = null);
    } catch (error) {
      if (_isCurrentController(generation, controller)) {
        setState(() => _error = error);
        widget.onFailure();
      } else {
        await _retireController(controller);
      }
    }
  }

  bool _isCurrentController(int generation, VideoPlayerController controller) =>
      mounted &&
      generation == _controllerGeneration &&
      identical(_controller, controller);

  void _handlePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      unawaited(widget.playback.pause().catchError((Object _) {}));
      if (_error == null && mounted) {
        setState(
          () => _error = StateError(
            controller.value.errorDescription ?? 'Video playback failed.',
          ),
        );
        widget.onFailure();
      }
      return;
    }
    unawaited(widget.playback.synchronizeVideoTick().catchError((Object _) {}));
    final playing = controller.value.isPlaying;
    if (playing != _lastPlaying && mounted) {
      _lastPlaying = playing;
      setState(() {});
    }
  }

  void _disposeController() {
    _controllerGeneration += 1;
    final controller = _controller;
    final driver = _playbackDriver;
    final attachedPlayback = _attachedPlayback;
    _controller = null;
    _playbackDriver = null;
    _attachedPlayback = null;
    if (controller != null) {
      unawaited(
        _retireController(
          controller,
          driver: driver,
          playback: attachedPlayback,
        ),
      );
    }
  }

  Future<void> _retireController(
    VideoPlayerController controller, {
    _VideoPlayerPlayback? driver,
    ReelPlaybackCoordinator? playback,
  }) {
    controller.removeListener(_handlePlayback);
    final detachment = driver != null && playback != null
        ? Future<void>.microtask(() => playback.detachVideo(driver))
        : null;
    final existing = _controllerRetirements[controller];
    if (existing != null) return existing;
    final attachment = _controllerAttachments[controller];
    final retirement = (() async {
      // A controller replacement can happen from didUpdateWidget while an
      // ancestor is still building. Detach on the next microtask so the
      // coordinator cannot synchronously notify that ancestor during build.
      if (detachment != null) {
        try {
          await detachment;
        } catch (_) {
          // A failed native pause must not prevent decoder disposal.
        }
      }
      // `attachVideo` owns queued setVolume/seek work for this controller.
      // Detach makes every not-yet-started step stale; waiting here also
      // lets a platform call that had already started finish before disposal.
      if (attachment != null) {
        try {
          await attachment;
        } catch (_) {
          // A failed attach still must release the decoder.
        }
      }
      try {
        await controller.dispose();
      } catch (_) {
        // Retirement has no live UI surface and must remain idempotent.
      }
    })();
    _controllerRetirements[controller] = retirement;
    return retirement;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final controller = _controller;
    if (_error != null) {
      return ColoredBox(
        color: palette.surfaceSunken,
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(copy.text('Retry', 'Spróbuj ponownie')),
              ),
              TextButton.icon(
                onPressed: () =>
                    launchUrl(widget.uri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(copy.text('Open video', 'Otwórz film')),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return YoLoadingIndicator(
        message: copy.text('Loading video', 'Ładowanie filmu'),
      );
    }
    return ReelPlaybackSurface(
      isPlaying: controller.value.isPlaying,
      onToggle: widget.onToggle,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ReelCompositionFrame(
            fillViewport: widget.fillViewport,
            overlayInsetsInViewport: true,
            overlaySafeInsets: widget.overlaySafeInsets,
            composition: widget.reel.composition,
            media: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            mediaForeground: const _LegibilityScrim(),
            onOpenLink: (overlay) =>
                launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
          ),
          Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                // Hidden under a finger on the timeline too: the viewer is
                // looking for a frame, not asking to play.
                opacity:
                    controller.value.isPlaying || widget.playback.isScrubbing
                    ? 0
                    : 1,
                duration: AppMotion.resolve(context, AppMotion.quick),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 72,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(color: Color(0x73000000), blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accessible full-canvas playback action shared by the real decoder and its
/// deterministic widget coverage. [AccessibleTapRegion] supplies pointer,
/// assistive-technology, Enter and Space activation plus a visible focus ring.
class ReelPlaybackSurface extends StatelessWidget {
  const ReelPlaybackSurface({
    required this.isPlaying,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = isPlaying
        ? copy.text('Pause video', 'Wstrzymaj film')
        : copy.text('Play video', 'Odtwórz film');
    return AccessibleTapRegion(
      key: const ValueKey('reel-video-playback-surface'),
      onTap: onToggle,
      semanticLabel: label,
      tooltip: label,
      borderRadius: 0,
      focusContrastColor: Colors.black,
      child: child,
    );
  }
}

class _VideoPlayerPlayback implements ReelVideoPlayback {
  const _VideoPlayerPlayback(this.controller);

  final VideoPlayerController controller;

  @override
  bool get isPlaying => controller.value.isPlaying;

  @override
  Duration get position => controller.value.position;

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> play() => controller.play();

  @override
  Future<void> seek(Duration position) => controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
}

/// A light base wash inside the composition space: it settles the top edge
/// and the centre play glyph. The text no longer relies on it — the footer
/// scrim in card space carries every line.
class _LegibilityScrim extends StatelessWidget {
  const _LegibilityScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x1F000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0x59000000),
            ],
            stops: <double>[0, .35, .60, 1],
          ),
        ),
      ),
    );
  }
}

/// Geometry shared by the immersive controls and the authored composition.
///
/// A vertical action rail consumes only the TRAILING safe zone. The compact
/// identity block consumes only the BOTTOM safe zone. Keeping those axes
/// independent is what leaves stickers at their authored height instead of
/// pushing every one of them above a 270 px-tall rail.
class _ImmersiveOverlayGeometry {
  const _ImmersiveOverlayGeometry({
    required this.width,
    required this.mediaHeight,
    required this.compact,
    required this.micro,
    required this.horizontalActions,
    required this.showInformation,
    required this.showSound,
    required this.informationWraps,
    required this.textScale,
  });

  factory _ImmersiveOverlayGeometry.resolve(
    BuildContext context, {
    required double width,
    required double mediaHeight,
    required bool showIdentity,
    required bool showSound,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final micro = mediaHeight < 330 || width < 158 * scale;
    // The two counted controls grow vertically with accessible text. Keep a
    // little more room between the mute button and the rail before choosing a
    // column at x2, otherwise their hit targets overlap around 360 px high.
    final horizontalActions = mediaHeight < 360 + math.max(0, scale - 1) * 32;
    final compact =
        micro ||
        mediaHeight < 520 + math.max(0, scale - 1) * 100 ||
        width < 340;
    final informationWidth = math.max(0.0, width - 96);
    return _ImmersiveOverlayGeometry(
      width: width,
      mediaHeight: mediaHeight,
      compact: compact,
      micro: micro,
      // Four 48 px targets plus their gaps remain a single shallow row when
      // a landscape/keyboard-squeezed frame cannot hold the vertical rail.
      horizontalActions: horizontalActions,
      // The horizontal action row owns the lower edge. Identity remains
      // available from More on this deliberately reduced-height state; drawing
      // both into the same strip makes neither reliably tappable.
      showInformation:
          !micro && !horizontalActions && (showIdentity || showSound),
      showSound: showSound,
      // Avatar + name + the 48 px friend action need roughly 310 logical
      // pixels at ordinary text size. Once they wrap, the authored bottom
      // edge must clear two identity rows plus the one-line caption.
      informationWraps:
          informationWidth < 310 * math.min(1.4, math.max(1, scale)),
      textScale: scale,
    );
  }

  final double width;
  final double mediaHeight;
  final bool compact;
  final bool micro;
  final bool horizontalActions;
  final bool showInformation;
  final bool showSound;
  final bool informationWraps;
  final double textScale;

  double get trailingSafeInset => horizontalActions ? 16 : 76;

  double get bottomSafeInset {
    if (horizontalActions) return 72;
    if (!showInformation) return 16;
    // This is the author/caption/audio footprint, never the height of the
    // action rail. Large text receives a compact one-line caption.
    if (compact) {
      if (informationWraps) return showSound ? 240 : 196;
      final growth = math.max(0, textScale - 1) * 28;
      return (showSound ? 164.0 : 120.0) + growth;
    }
    if (informationWraps) return showSound ? 240 : 196;
    final growth = math.max(0, textScale - 1) * 28;
    return (showSound ? 170.0 : 132.0) + growth;
  }

  double get identityEndInset => horizontalActions ? 16 : 80;

  double get scrimHeight {
    if (!showInformation) return horizontalActions ? 84 : 48;
    return math.min(
      mediaHeight * .38,
      showSound || informationWraps ? 220.0 : 184.0,
    );
  }

  EdgeInsets compositionInsets(BuildContext context, {required double top}) {
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return EdgeInsets.fromLTRB(
      ltr ? 16 : trailingSafeInset,
      top,
      ltr ? trailingSafeInset : 16,
      bottomSafeInset,
    );
  }
}

/// The immersive, media-first Yeels chrome.
///
/// Only a soft bottom gradient crosses the footage. Actions occupy a narrow
/// trailing rail, identity stays at the lower leading edge, mute lives below
/// the host chrome and the progress track hugs the final pixels of the frame.
/// Empty overlay space stays transparent to taps, so the media remains the
/// play/pause surface.
class _OverlayFooter extends StatelessWidget {
  const _OverlayFooter({
    required this.reel,
    required this.geometry,
    required this.showIdentity,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    required this.showAudioToggle,
    required this.position,
    required this.timeline,
    required this.scrub,
    required this.trackKey,
    required this.likePending,
    required this.commentsOpen,
    required this.onOpenAuthor,
    required this.onCaption,
    required this.onMore,
    required this.onShare,
    this.friendService,
    this.friendRelationshipStore,
    this.viewerUid,
    this.soundToggle,
    this.onAudio,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
  });

  final Reel reel;
  final _ImmersiveOverlayGeometry geometry;
  final bool showIdentity;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final bool showAudioToggle;
  final ValueListenable<Duration> position;
  final Duration timeline;

  /// What a finger on the timeline drives, and the key that wraps the
  /// visible hairline so the finger maps onto its real extent.
  final ReelScrubTarget scrub;
  final GlobalKey trackKey;
  final FriendService? friendService;
  final ReelFriendRelationshipStore? friendRelationshipStore;
  final String? viewerUid;
  final bool likePending;
  final bool commentsOpen;
  final VoidCallback onOpenAuthor;
  final VoidCallback onCaption;
  final VoidCallback onMore;

  /// Built with this frame's own answer to "is there room for the words".
  final Widget Function(bool showLabel)? soundToggle;
  final VoidCallback? onAudio;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final friends = friendService;
    final viewer = viewerUid;
    final showSound =
        showAudioToggle || reel.composition.audioAttribution.isNotEmpty;
    // Immersive mute is deliberately glyph-only. Tooltip and semantics retain
    // the full translated action, while the footage loses the old wide pill.
    final toggle = soundToggle?.call(false);
    final soundChip = showSound
        ? _SoundChip(
            reel: reel,
            showToggle: showAudioToggle,
            audioPlaying: audioPlaying,
            audioLoading: audioLoading,
            audioEnabled: audioEnabled,
            onAudio: onAudio,
          )
        : null;
    final author = ReelAuthorRow(reel: reel, onTap: onOpenAuthor);
    final friend = friends != null && viewer != null && viewer != reel.authorId
        ? _ReelFriendButton(
            userId: reel.authorId,
            displayName: reel.authorName,
            viewerUid: viewer,
            friendService: friends,
            relationshipStore: friendRelationshipStore,
            onMedia: true,
          )
        : null;
    final identity = friend == null
        ? author
        : geometry.informationWraps
        ? Wrap(
            spacing: AppRhythm.tight,
            runSpacing: AppRhythm.hairline,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[author, friend],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // A long display name yields its remaining width to Add friend
              // ellipsizes; it must not silently create a second identity row
              // after geometry has budgeted the inline composition.
              Flexible(child: author),
              const SizedBox(width: AppRhythm.tight),
              friend,
            ],
          );

    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showIdentity && !geometry.micro) ...<Widget>[
          identity,
          if (reel.composition.caption.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppRhythm.hairline),
            _ReelCaption(
              reel: reel,
              onTap: onCaption,
              child: Text(
                reel.composition.caption,
                maxLines: geometry.compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.35,
                  shadows: reelOverlayTextShadows,
                ),
              ),
            ),
          ],
        ],
        if (soundChip != null && !geometry.micro) ...<Widget>[
          if (showIdentity) const SizedBox(height: AppRhythm.hairline),
          soundChip,
        ],
      ],
    );

    final actions = ReelEngagementBar(
      likeCount: reel.likeCount,
      commentCount: reel.commentCount,
      liked: reel.callerLiked,
      likePending: likePending,
      commentsOpen: commentsOpen,
      railAxis: geometry.horizontalActions ? Axis.horizontal : Axis.vertical,
      railAlignment: geometry.horizontalActions
          ? WrapAlignment.spaceEvenly
          : WrapAlignment.end,
      railAdditional: <Widget>[
        ReelOverlayPlateButton(
          key: const ValueKey('reel-share-action'),
          icon: Icons.send_outlined,
          semanticLabel: copy.text('Share Yeel', 'Udostępnij Yeel'),
          onTap: () => unawaited(onShare()),
        ),
      ],
      railTrailing: _ReelOverflowButton(onTap: onMore),
      onLike: onLike,
      onComments: onComments,
    );

    final topControl = toggle ?? (!geometry.showInformation ? soundChip : null);
    return SizedBox(
      height: geometry.mediaHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            height: geometry.scrimHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('reel-bottom-scrim'),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0x26000000),
                      Color(0xB8000000),
                    ],
                    stops: <double>[0, .42, 1],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            child: KeyedSubtree(
              key: trackKey,
              child: ReelProgressBar(
                position: position,
                total: timeline,
                announce: !scrub.canSeek,
              ),
            ),
          ),
          if (topControl != null)
            PositionedDirectional(
              top: AppRhythm.tight,
              end: AppRhythm.item,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(48, math.min(240, geometry.width - 32)),
                ),
                child: _ScrubChromeFade(
                  scrubbing: scrub.isScrubbing,
                  child: topControl,
                ),
              ),
            ),
          if (geometry.showInformation)
            PositionedDirectional(
              start: AppRhythm.item,
              end: geometry.identityEndInset,
              bottom: AppRhythm.item,
              child: KeyedSubtree(
                key: const ValueKey<String>('reel-identity-block'),
                child: _ScrubChromeFade(
                  scrubbing: scrub.isScrubbing,
                  child: information,
                ),
              ),
            ),
          if (geometry.horizontalActions)
            PositionedDirectional(
              start: AppRhythm.tight,
              end: AppRhythm.tight,
              bottom: AppRhythm.tight,
              child: KeyedSubtree(
                key: const ValueKey<String>('reel-action-rail'),
                child: _ScrubChromeFade(
                  scrubbing: scrub.isScrubbing,
                  child: actions,
                ),
              ),
            )
          else
            PositionedDirectional(
              end: AppRhythm.item,
              bottom: AppRhythm.item,
              child: KeyedSubtree(
                key: const ValueKey<String>('reel-action-rail'),
                // Counts may reach four digits even after compaction, and x2
                // text can make that wider than the reserved trailing safe
                // zone. Keep the visual rail exactly one 48 px column; the
                // exact total remains in each action's semantic label.
                child: _ScrubChromeFade(
                  scrubbing: scrub.isScrubbing,
                  child: SizedBox(width: 48, child: actions),
                ),
              ),
            ),
          // Last, so it is first to see a pointer — but translucent and
          // drag-only, so every tap inside it still reaches the controls
          // above and the playback surface below (ADR-210). The visible bar
          // above keeps its 2 px and its place.
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            height: _immersiveScrubBandHeight,
            child: ReelProgressScrubber(
              key: const ValueKey<String>('reel-progress-scrub'),
              target: scrub,
              position: position,
              total: timeline,
              trackKey: trackKey,
              respectSystemGestureInsets: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Height of the drag band over the phone stage's hairline. It stays inside
/// the footer scrim (at least 48 px), so the clear-media band is unchanged.
const double _immersiveScrubBandHeight = 40;

/// Height of the drag band on the card stage: the frame's 16 px bottom
/// padding, the 2 px bar and 30 px above it.
const double _frameScrubBandHeight = 48;

/// Overlay chrome steps back while a finger scrubs the timeline, so the
/// previewed frame is visible (ADR-210). Under Reduce Motion nothing fades:
/// the chrome simply stays.
class _ScrubChromeFade extends StatelessWidget {
  const _ScrubChromeFade({required this.scrubbing, required this.child});

  final bool scrubbing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hidden = scrubbing && !MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: hidden ? 0 : 1,
      duration: AppMotion.quick,
      curve: AppMotion.standardCurve,
      child: IgnorePointer(ignoring: hidden, child: child),
    );
  }
}

/// Long captions remain reachable without expanding over the action rail.
/// A modal route also suspends playback through the card's route visibility.
class _ReelCaption extends StatelessWidget {
  const _ReelCaption({
    required this.reel,
    required this.onTap,
    required this.child,
  });
  final Reel reel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => AccessibleTapRegion(
    semanticLabel: reel.composition.caption,
    minimumSize: const Size(44, 44),
    borderRadius: 8,
    focusContrastColor: Colors.black,
    onTap: onTap,
    child: child,
  );
}

class _ReelOverflowButton extends StatelessWidget {
  const _ReelOverflowButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ReelOverlayPlateButton(
    key: const ValueKey('reel-more-action'),
    icon: Icons.more_horiz_rounded,
    semanticLabel: MaterialLocalizations.of(context).moreButtonTooltip,
    onTap: onTap,
  );
}

/// Where a [ReelAuthorRow] is drawn, which decides its foreground.
///
/// [overlay] sits on artwork of unknown luminance: fixed white with the
/// shared text shadows. [panel] sits on an ordinary app surface in the wide
/// layout and uses semantic palette roles.
enum ReelAuthorRowVariant { overlay, panel }

/// The author of a Reel, as one tappable identity control.
///
/// One widget serves the card overlay and the wide context panel so the two
/// can never disagree about who published a Reel or what tapping the name
/// does. The avatar resolves through the existing viewer-authorised profile
/// media service — the Reel wire carries no photo URL and none is invented,
/// so the initial is the honest fallback.
class ReelAuthorRow extends StatelessWidget {
  const ReelAuthorRow({
    required this.reel,
    required this.onTap,
    this.showAvatar = true,
    this.variant = ReelAuthorRowVariant.overlay,
    this.secondaryLine,
    super.key,
  });

  final Reel reel;
  final VoidCallback onTap;
  final bool showAvatar;
  final ReelAuthorRowVariant variant;

  /// Panel only: a second line under the name, such as the publish time.
  final String? secondaryLine;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final overlay = variant == ReelAuthorRowVariant.overlay;
    final radius = overlay ? 16.0 : 20.0;
    final name = Text(
      reel.authorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: overlay ? Colors.white : palette.textPrimary,
        fontSize: overlay ? 16 : 18,
        fontWeight: FontWeight.w800,
        height: 1.2,
        shadows: overlay ? reelOverlayTextShadows : null,
      ),
    );
    final secondary = secondaryLine;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      // The author is an inline identity control. Without a width factor an
      // Align under Wrap expands to the whole information column, forcing the
      // friend button onto a second line even when both labels comfortably
      // fit. That extra unbudgeted row can overlap a bottom-authored sticker.
      widthFactor: 1,
      child: AccessibleTapRegion(
        onTap: onTap,
        semanticLabel: copy.template(
          'Open profile for {author}',
          'Otwórz profil: {author}',
          values: <String, Object>{'author': reel.authorName},
        ),
        borderRadius: overlay ? 999 : 16,
        minimumSize: const Size(44, 44),
        focusContrastColor: overlay ? Colors.black : null,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 4, overlay ? 10 : 8, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showAvatar) ...<Widget>[
                ExcludeSemantics(
                  child: UserAvatar(
                    radius: radius,
                    userId: reel.authorId,
                    displayName: reel.authorName,
                  ),
                ),
                SizedBox(width: overlay ? 8 : 12),
              ],
              Flexible(
                child: secondary == null || secondary.isEmpty
                    ? name
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          name,
                          const SizedBox(height: 2),
                          Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textTertiary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The audio line of the frame: attribution (or the generic name), with the
/// playback toggle leading it when the Reel has backing audio.
///
/// Slim look: one line of shadowed white text straight on the scrim, led by
/// a music glyph — no plate, so the frame's text reads as one layer over the
/// media. The logic (when it shows, the label, the toggle's gate) is the
/// same as before.
///
/// The toggle stays an [IconButton] — its key, tooltips and 44 px target are
/// the contract the playback coordinator coverage holds it to.
class _SoundChip extends StatelessWidget {
  const _SoundChip({
    required this.reel,
    required this.showToggle,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    this.onAudio,
  });

  final Reel reel;
  final bool showToggle;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final VoidCallback? onAudio;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final attribution = reel.composition.audioAttribution;
    final text = attribution.isNotEmpty
        ? attribution
        : copy.text('Backing audio', 'Podkład');
    final toggleLabel = reel.media.kind == ReelMediaKind.video
        ? audioPlaying
              ? copy.text('Pause video', 'Wstrzymaj film')
              : copy.text('Play video', 'Odtwórz film')
        : audioPlaying
        ? copy.text('Pause backing audio', 'Wstrzymaj podkład')
        : copy.text('Play backing audio', 'Odtwórz podkład');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showToggle)
              IconButton(
                key: const ValueKey('reel-playback-toggle'),
                tooltip: toggleLabel,
                onPressed: audioLoading || !audioEnabled ? null : onAudio,
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: .5),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: audioLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        audioPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        shadows: reelOverlayTextShadows,
                      ),
              )
            else
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 6),
                child: Icon(
                  Icons.music_note_rounded,
                  size: 16,
                  color: Colors.white,
                  shadows: reelOverlayTextShadows,
                ),
              ),
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: IgnorePointer(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      shadows: reelOverlayTextShadows,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
