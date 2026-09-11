import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/sharing/reel_share.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_overlay_measure.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_private_overlay_guard.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelVideoBuilder =
    Widget Function(BuildContext context, Uri mediaUri, Reel reel);

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
    this.soundOn,
    this.autoplay = true,
    this.isActive = true,
    this.isHostVisible = true,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
    this.onShare,
    this.onOpenAuthor,
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
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;

  /// Engagement is owned by the feed, not by the card: the card renders the
  /// counts it is given and reports intent upwards. That is what keeps a
  /// card, the wide context panel and an open thread showing one truth.
  ///
  /// Null means there is no viewer to act as. An unverified account keeps a
  /// live control that explains its gate rather than a dead button.
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final Future<void> Function()? onShare;

  /// What a tap on the author does. Production leaves it null and opens the
  /// shared profile preview; tests inject a seam so they never touch
  /// Firestore.
  final void Function(Reel reel)? onOpenAuthor;
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
  Duration _watched = Duration.zero;
  bool _photoReady = false;
  bool _viewRecorded = false;
  int _mediaRevision = 0;
  int _automaticRefreshes = 0;
  double _footerHeight = 0;
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
                        SelectableText(reel.composition.caption),
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
                          title: Text(copy.text('Report Reel', 'Zgłoś Reel')),
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
                          title: Text(copy.text('Delete Reel', 'Usuń Reel')),
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

  EdgeInsets get _compositionInsets => EdgeInsets.fromLTRB(
    16,
    widget.fillViewport ? widget.mediaTopInset + 12 : 56,
    16,
    _footerHeight + 8,
  );

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
    if (oldWidget.commentsOpen != widget.commentsOpen ||
        oldWidget.isHostVisible != widget.isHostVisible) {
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
  bool get _playbackSuspended =>
      !_appResumed ||
      !_routeIsCurrent ||
      !widget.isHostVisible ||
      widget.commentsOpen;

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

  Widget _buildMedia(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return FutureBuilder<Uri>(
      key: ValueKey(_mediaRevision),
      future: _media,
      initialData: _initialMediaUri,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return YoErrorState(
            message: copy.text(
              'This Reel is unavailable right now.',
              'Ten Reel jest teraz niedostępny.',
            ),
            onRetry: _refreshMedia,
            compact: true,
          );
        }
        final uri = snapshot.data;
        if (uri == null) {
          return YoLoadingIndicator(
            message: copy.text('Loading Reel', 'Ładowanie Reela'),
          );
        }
        final videoPlaybackFactory = widget.videoPlaybackFactory;
        if (widget.reel.media.kind == ReelMediaKind.video &&
            videoPlaybackFactory != null) {
          return _HostedReelVideoPlayer(
            uri: uri,
            reel: widget.reel,
            playback: _playback,
            playbackFactory: videoPlaybackFactory,
            videoBuilder: widget.videoBuilder,
            onToggle: _togglePlayback,
            fillViewport: widget.fillViewport,
            overlaySafeInsets: _compositionInsets,
          );
        }
        if (widget.reel.media.kind == ReelMediaKind.video &&
            widget.videoBuilder == null) {
          return _DefaultReelVideoPlayer(
            uri: uri,
            reel: widget.reel,
            playback: _playback,
            onToggle: _togglePlayback,
            onRetry: _refreshMedia,
            onFailure: () => _refreshMedia(automatic: true),
            fillViewport: widget.fillViewport,
            overlaySafeInsets: _compositionInsets,
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
        return ReelCompositionFrame(
          fillViewport: widget.fillViewport,
          overlayInsetsInViewport: true,
          overlaySafeInsets: _compositionInsets,
          composition: widget.reel.composition,
          media: media,
          mediaForeground: const _LegibilityScrim(),
          onOpenLink: (overlay) =>
              launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final radius = widget.borderRadius;
    return Semantics(
      container: true,
      label: copy.template(
        'Reel by {author}',
        'Reel użytkownika {author}',
        values: <String, Object>{'author': widget.reel.authorName},
      ),
      child: LayoutBuilder(
        builder: (context, viewport) => Center(
          child: AspectRatio(
            aspectRatio:
                widget.fillViewport &&
                    viewport.hasBoundedHeight &&
                    viewport.maxHeight > 0
                ? viewport.maxWidth / viewport.maxHeight
                : 9 / 16,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mediaHeight = constraints.maxHeight;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    // Only visible while the media loads or fails.
                    color: palette.surfaceSunken,
                    borderRadius: BorderRadius.circular(radius),
                    border: widget.fillViewport
                        ? null
                        : Border.all(color: palette.border),
                    boxShadow: widget.fillViewport
                        ? null
                        : reelCardShadow(context),
                  ),
                  child: ClipRRect(
                    key: const ValueKey('reel-viewport'),
                    borderRadius: BorderRadius.circular(
                      (radius - 1).clamp(0, double.infinity),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _buildMedia(context),
                        // Autoplay is silent, so the way back to sound has to
                        // be visible on the frame itself and never move: top
                        // trailing corner, clear of the footer at every height.
                        if (widget.reel.media.kind == ReelMediaKind.video &&
                            !widget.fillViewport)
                          PositionedDirectional(
                            top: 8,
                            end: 8,
                            child: _SoundToggle(
                              soundOn: _soundOn.value,
                              onToggle: _toggleSound,
                            ),
                          ),
                        // The empty area of this layer takes no hits — its scrim
                        // is behind an IgnorePointer — so the playback surface
                        // underneath still receives them.
                        PositionedDirectional(
                          start: 0,
                          end: 0,
                          bottom: 0,
                          child: ReelOverlayMeasure(
                            key: const ValueKey('reel-footer'),
                            onSize: (size) {
                              if (mounted &&
                                  (_footerHeight - size.height).abs() > .5) {
                                setState(() => _footerHeight = size.height);
                              }
                            },
                            child: _OverlayFooter(
                              reel: widget.reel,
                              // Chrome consumes readable space even though it
                              // overlays the video. Fold controls before they
                              // cover authored links on a short/large-text view.
                              mediaHeight:
                                  mediaHeight -
                                  (widget.fillViewport
                                      ? widget.mediaTopInset
                                      : 0),
                              showIdentity: widget.showIdentity,
                              audioPlaying: _playback.isPlaying,
                              audioLoading: _playback.isLoading,
                              audioEnabled: _playback.canToggle,
                              showAudioToggle: widget.reel.backingAudio != null,
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
                              immersive: widget.fillViewport,
                              soundToggle:
                                  widget.fillViewport &&
                                      widget.reel.media.kind ==
                                          ReelMediaKind.video
                                  ? _SoundToggle(
                                      soundOn: _soundOn.value,
                                      onToggle: _toggleSound,
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
      ),
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
        return YoErrorState(
          compact: true,
          message: AppLocalizations.of(context).text(
            'This Reel is unavailable right now.',
            'Ten Reel jest teraz niedostępny.',
          ),
          onRetry: onRetry,
        );
      },
    );
  }
}

/// The sound switch for a video Reel.
///
/// It exists because autoplay is silent: without a control on the frame the
/// only way back to sound would be a second tap that also stops the video.
/// It shows the state the viewer is in, not the action, which is why the
/// glyph is a crossed-out speaker while muted.
class _SoundToggle extends StatelessWidget {
  const _SoundToggle({required this.soundOn, required this.onToggle});

  final bool soundOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return ReelOverlayPlateButton(
      key: const ValueKey<String>('reel-sound-toggle'),
      icon: soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      semanticLabel: soundOn
          ? copy.text('Turn sound off', 'Wyłącz dźwięk')
          : copy.text('Turn sound on', 'Włącz dźwięk'),
      onTap: onToggle,
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
    if (driver != null) playback.detachVideo(driver);
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
    required this.onToggle,
    required this.onRetry,
    required this.onFailure,
    this.fillViewport = false,
    required this.overlaySafeInsets,
  });

  final Uri uri;
  final Reel reel;
  final ReelPlaybackCoordinator playback;
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
  Object? _error;
  bool _lastPlaying = false;

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
        !identical(oldWidget.playback, widget.playback)) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(
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
      await controller.setLooping(false);
      await controller.setVolume(
        widget.reel.composition.originalAudioVolume / 100,
      );
      await controller.seekTo(
        Duration(milliseconds: widget.reel.composition.trimStartMs),
      );
      final driver = _VideoPlayerPlayback(controller);
      _playbackDriver = driver;
      _attachedPlayback = widget.playback;
      _lastPlaying = controller.value.isPlaying;
      controller.addListener(_handlePlayback);
      await widget.playback.attachVideo(driver);
      if (!mounted || !identical(_controller, controller)) return;
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        setState(() => _error = error);
        widget.onFailure();
      }
    }
  }

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
    final controller = _controller;
    final driver = _playbackDriver;
    final attachedPlayback = _attachedPlayback;
    _controller = null;
    _playbackDriver = null;
    _attachedPlayback = null;
    if (driver != null) attachedPlayback?.detachVideo(driver);
    if (controller != null) {
      controller.removeListener(_handlePlayback);
      unawaited(controller.dispose());
    }
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
                opacity: controller.value.isPlaying ? 0 : 1,
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

/// Identity column bottom-start, action rail bottom-end, one footer scrim
/// under both: a ~100 px ramp and then flat 84 % black beneath every line, so
/// white text clears 4.5:1 even on a pure-white frame.
class _OverlayFooter extends StatelessWidget {
  const _OverlayFooter({
    required this.reel,
    required this.mediaHeight,
    required this.showIdentity,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    required this.showAudioToggle,
    required this.likePending,
    required this.commentsOpen,
    required this.onOpenAuthor,
    required this.onCaption,
    required this.onMore,
    required this.immersive,
    this.soundToggle,
    this.onAudio,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
    required this.onShare,
  });

  final Reel reel;
  final double mediaHeight;
  final bool showIdentity;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final bool showAudioToggle;
  final bool likePending;
  final bool commentsOpen;
  final VoidCallback onOpenAuthor;
  final VoidCallback onCaption;
  final VoidCallback onMore;
  final bool immersive;
  final Widget? soundToggle;
  final VoidCallback? onAudio;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Short media (a phone with the header and the dock on screen) folds the
    // rail into a row and trims the caption instead of covering the frame.
    final extraScale = (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
        .clamp(0.0, 2.0);
    final compact = mediaHeight < 400 + extraScale * 180;
    // Smaller still — a 320x568 window with the shell's dock leaves a frame
    // roughly 110 x 196, and three 48 px controls already fill it. The
    // identity column is dropped here rather than laid out and then clipped
    // off the top of the card: a half-cut name is worse than none, and the
    // author is still announced by the card's own semantics. This is a
    // graceful floor, not a target — a viewport this short really wants a
    // collapsed header or a dedicated immersive route.
    final micro = mediaHeight < 320;
    final captionLines = compact
        ? 1
        : mediaHeight < 560
        ? 2
        : 3;
    final showSound =
        showAudioToggle || reel.composition.audioAttribution.isNotEmpty;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showIdentity && !micro) ...<Widget>[
          if (compact)
            Row(
              children: [
                Expanded(
                  child: ReelAuthorRow(
                    reel: reel,
                    showAvatar: false,
                    onTap: onOpenAuthor,
                  ),
                ),
                if (reel.composition.caption.isNotEmpty)
                  _ReelCaption(
                    reel: reel,
                    onTap: onCaption,
                    child: const Icon(Icons.notes_rounded, color: Colors.white),
                  ),
              ],
            )
          else
            ReelAuthorRow(reel: reel, onTap: onOpenAuthor),
          if (!compact && reel.composition.caption.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _ReelCaption(
              reel: reel,
              onTap: onCaption,
              child: Text(
                reel.composition.caption,
                maxLines: captionLines,
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
        if (showSound && !micro) ...<Widget>[
          if (showIdentity) const SizedBox(height: 8),
          _SoundChip(
            reel: reel,
            showToggle: showAudioToggle,
            audioPlaying: audioPlaying,
            audioLoading: audioLoading,
            audioEnabled: audioEnabled,
            onAudio: onAudio,
          ),
        ],
      ],
    );

    final rail = ReelEngagementBar(
      likeCount: reel.likeCount,
      commentCount: reel.commentCount,
      liked: reel.callerLiked,
      likePending: likePending,
      commentsOpen: commentsOpen,
      railAxis: compact ? Axis.horizontal : Axis.vertical,
      railAdditional: [
        ReelOverlayPlateButton(
          key: const ValueKey('reel-share-action'),
          icon: Icons.send_outlined,
          semanticLabel: copy.text('Share Reel', 'Udostępnij Reel'),
          onTap: onShare,
        ),
      ],
      railTrailing: Wrap(
        direction: compact ? Axis.horizontal : Axis.vertical,
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ?soundToggle,
          _ReelOverflowButton(onTap: onMore),
        ],
      ),
      onLike: onLike,
      onComments: onComments,
    );

    // The scrim is a sibling behind the controls, not their parent: a
    // BoxDecoration hit-tests as opaque over its whole box, so a gradient
    // wrapped around this footer swallows every tap in the lower part of the
    // frame — including the tap that pauses the video.
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xD6000000)],
                  stops: <double>[0, .40],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            16,
            compact
                ? 8
                : immersive
                ? 24
                // The desktop context panel already carries the identity.
                // Do not reserve its decorative fade above an empty column:
                // that space belongs to the authored, large-text links.
                : !showIdentity
                ? 8
                : 96,
            12,
            16,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    identity,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: rail,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(child: identity),
                    const SizedBox(width: 16),
                    rail,
                  ],
                ),
        ),
      ],
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

/// The audio line of the frame: attribution (or the generic name) on a 72 %
/// plate, with the playback toggle leading it when the Reel has backing audio.
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
        child: Stack(
          children: <Widget>[
            // The visible pill is 32 tall; the toggle keeps a 44 px target
            // that overhangs it by 6 px above and below.
            const PositionedDirectional(
              start: 0,
              end: 0,
              top: 6,
              bottom: 6,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: reelOverlayPlateColor,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showToggle)
                  IconButton(
                    key: const ValueKey('reel-playback-toggle'),
                    tooltip: toggleLabel,
                    onPressed: audioLoading || !audioEnabled ? null : onAudio,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white.withValues(
                        alpha: .5,
                      ),
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
                          ),
                  )
                else
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 10, end: 6),
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: IgnorePointer(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
