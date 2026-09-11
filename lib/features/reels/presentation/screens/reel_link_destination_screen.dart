import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';
import 'package:yovoice/features/reels/presentation/sharing/reel_share.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_private_overlay_guard.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// An identifier is not permission: no caller-supplied Reel snapshot is
/// accepted. Both the view and its media use the existing authorized service.
class ReelLinkDestinationScreen extends StatefulWidget {
  const ReelLinkDestinationScreen({
    required this.reelId,
    this.service,
    this.videoBuilder,
    this.videoPlaybackFactory,
    this.audioPlaybackFactory,
    this.now,
    super.key,
  });

  final String reelId;
  final ReelService? service;
  final ReelVideoBuilder? videoBuilder;
  final ReelVideoPlaybackFactory? videoPlaybackFactory;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;
  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<ReelLinkDestinationScreen> createState() =>
      _ReelLinkDestinationScreenState();
}

class _ReelLinkDestinationScreenState extends State<ReelLinkDestinationScreen>
    with WidgetsBindingObserver, RouteAware {
  late ReelService _service;
  String? _viewerId;
  StreamSubscription<String?>? _identity;
  Timer? _expiryTimer;
  ModalRoute<void>? _route;
  final ValueNotifier<bool> _soundOn = ValueNotifier<bool>(false);
  Reel? _reel;
  Object? _error;
  int _generation = 0;
  bool _identityEnded = false;
  bool _loading = true;
  bool _authorized = false;
  bool _foreground = true;
  bool _routeVisible = true;
  bool _likePending = false;

  DateTime get _now => (widget.now ?? DateTime.now)();
  bool get _sameViewer =>
      !_identityEnded &&
      _viewerId != null &&
      _service.currentUserId == _viewerId;
  bool get _canPresent =>
      _sameViewer &&
      _authorized &&
      _foreground &&
      _routeVisible &&
      (_reel?.availability.isAvailableAt(_now) ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _bindService();
    unawaited(_load());
  }

  void _bindService() {
    _service = widget.service ?? ReelService();
    _viewerId = _service.currentUserId;
    _identity = _service.identityChanges.listen((uid) {
      if (uid != _viewerId) _endIdentity();
    }, onError: (Object _) => _endIdentity());
  }

  void _endIdentity() {
    if (!mounted || _identityEnded) return;
    _generation++;
    _expiryTimer?.cancel();
    _soundOn.value = false;
    ReelService.clearAllMediaAccessCaches();
    setState(() {
      _identityEnded = true;
      _reel = null;
      _authorized = false;
      _loading = false;
      _likePending = false;
      _error = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (!identical(_route, route)) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    _routeVisible = route?.isCurrent ?? true;
  }

  @override
  void didUpdateWidget(covariant ReelLinkDestinationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reelId != widget.reelId ||
        !identical(oldWidget.service, widget.service)) {
      _generation++;
      unawaited(_identity?.cancel());
      _expiryTimer?.cancel();
      _reel = null;
      _authorized = false;
      _identityEnded = false;
      _likePending = false;
      _soundOn.value = false;
      _bindService();
      unawaited(_load());
    }
  }

  bool _matches(int generation, String? uid) =>
      mounted && generation == _generation && _sameViewer && _viewerId == uid;

  Future<void> _load() async {
    final generation = ++_generation;
    final uid = _viewerId;
    setState(() {
      _authorized = false;
      _loading = true;
      _error = null;
      _likePending = false;
    });
    try {
      if (!_sameViewer || !isSafeReelLinkId(widget.reelId)) return;
      final view = await _service.loadView(widget.reelId, commentLimit: 1);
      if (!_matches(generation, uid) || !_foreground || !_routeVisible) return;
      if (view.reel.id != widget.reelId ||
          !view.reel.availability.isAvailableAt(_now)) {
        _reel = null;
        return;
      }
      setState(() {
        _reel = view.reel;
        _authorized = true;
      });
      _armExpiry();
    } catch (error) {
      if (_matches(generation, uid)) {
        setState(() {
          _reel = null;
          _error = error;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _armExpiry() {
    _expiryTimer?.cancel();
    final expiry = _reel?.availability.contentExpiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(_now);
    if (remaining <= Duration.zero) {
      _generation++;
      setState(() {
        _reel = null;
        _authorized = false;
        _loading = false;
      });
      return;
    }
    // Browser-safe bounded timer; re-read the wall clock at each chunk.
    final delay = remaining > const Duration(hours: 12)
        ? const Duration(hours: 12)
        : remaining;
    _expiryTimer = Timer(delay, () {
      if (mounted) _armExpiry();
    });
  }

  void _suspend() {
    _generation++;
    setState(() {
      _authorized = false;
      _loading = false;
      _likePending = false;
    });
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _suspend();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    if (_foreground && _sameViewer) unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _suspend();
    } else if (_routeVisible && _sameViewer) {
      unawaited(_load());
    }
  }

  Future<void> _like() async {
    final reel = _reel;
    if (!_canPresent || _likePending || reel == null) return;
    if (!_service.isEmailVerified) {
      _announce(reelVerificationNotice(context));
      return;
    }
    final generation = _generation;
    final uid = _viewerId;
    setState(() => _likePending = true);
    try {
      final result = await _service.setLike(reel.id, liked: !reel.callerLiked);
      if (!_matches(generation, uid)) return;
      setState(
        () => _reel = _reel!.copyWithEngagement(
          callerLiked: result.liked,
          likeCount: result.likeCount,
        ),
      );
    } catch (error) {
      if (mounted && _matches(generation, uid)) {
        _announce(
          reelEngagementMessage(
            context,
            error,
            action: ReelEngagementAction.like,
          ),
        );
      }
    } finally {
      if (_matches(generation, uid)) setState(() => _likePending = false);
    }
  }

  void _comments() {
    final reel = _reel;
    if (!_canPresent || reel == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: false,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
        builder: (_) => _ReelLinkCommentsHost(
          reelId: reel.id,
          viewerId: _viewerId!,
          service: _service,
          now: widget.now ?? DateTime.now,
        ),
      ),
    );
  }

  void _announce(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _unavailableMessage(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (!_sameViewer) {
      return copy.text(
        'Sign in to open this Reel.',
        'Zaloguj się, aby otworzyć ten Reel.',
      );
    }
    if (_error is ReelEngagementException &&
        (_error as ReelEngagementException).reason ==
            ReelEngagementFailure.offline) {
      return copy.text(
        'Check your connection and try again.',
        'Sprawdź połączenie z internetem i spróbuj ponownie.',
      );
    }
    return copy.text(
      'This Reel is unavailable right now.',
      'Ten Reel jest teraz niedostępny.',
    );
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_identity?.cancel());
    _expiryTimer?.cancel();
    _soundOn.dispose();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final canPresent = _canPresent;
    final reel = _reel;
    return Scaffold(
      backgroundColor: context.appPalette.background,
      appBar: AppBar(
        title: Text(copy.text('Reels', 'Reels')),
        actions: [
          IconButton(
            key: const ValueKey('reel-link-share'),
            tooltip: copy.text('Share Reel', 'Udostępnij Reel'),
            onPressed: canPresent
                ? () => showReelShareSheet(
                    context,
                    reelId: widget.reelId,
                    service: _service,
                  )
                : null,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              // Keep the same player's element during same-account revalidation,
              // but remove every visible/semantic pixel until the fresh response.
              // Account exit or expiry removes the model AND the element.
              if (reel != null && _sameViewer)
                Offstage(
                  offstage: !canPresent,
                  child: Center(
                    child: SizedBox(
                      width: math.min(constraints.maxWidth, 480),
                      child: ReelCard(
                        key: ValueKey('reel-link-$_viewerId-${reel.id}'),
                        reel: reel,
                        service: _service,
                        videoBuilder: widget.videoBuilder,
                        videoPlaybackFactory: widget.videoPlaybackFactory,
                        audioPlaybackFactory: widget.audioPlaybackFactory,
                        now: widget.now,
                        soundOn: _soundOn,
                        // This remains the selected Reel while a sheet or
                        // fresh authorization temporarily obscures its host.
                        // Only a true page change resets seek/hand-pause.
                        isActive: true,
                        isHostVisible: canPresent,
                        onLike: _like,
                        likePending: _likePending,
                        onComments: _comments,
                      ),
                    ),
                  ),
                ),
              // Covering a valid destination is not an availability failure.
              // Hide private content while a sheet/route owns the foreground,
              // without painting a misleading error underneath that surface.
              if (!canPresent && _routeVisible && _foreground)
                Center(
                  child: SingleChildScrollView(
                    child: _loading
                        ? YoLoadingIndicator(
                            message: copy.text(
                              'Loading Reel',
                              'Ładowanie Reela',
                            ),
                          )
                        : YoErrorState(
                            message: _unavailableMessage(context),
                            onRetry:
                                _sameViewer && isSafeReelLinkId(widget.reelId)
                                ? _load
                                : null,
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

/// The existing thread owns paging, composer and moderation. This small host
/// only owns the lifetime of its private model, since a modal route is not
/// rebuilt when the underlying destination expires or changes auth epoch.
class _ReelLinkCommentsHost extends StatefulWidget {
  const _ReelLinkCommentsHost({
    required this.reelId,
    required this.viewerId,
    required this.service,
    required this.now,
  });

  final String reelId;
  final String viewerId;
  final ReelService service;
  final DateTime Function() now;

  @override
  State<_ReelLinkCommentsHost> createState() => _ReelLinkCommentsHostState();
}

class _ReelLinkCommentsHostState extends State<_ReelLinkCommentsHost>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _identity;
  Timer? _expiry;
  Reel? _reel;
  bool _loading = true;
  bool _identityEnded = false;
  bool _foreground = true;
  int _generation = 0;

  bool get _sameViewer =>
      !_identityEnded && widget.service.currentUserId == widget.viewerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _identity = widget.service.identityChanges.listen((uid) {
      if (uid != widget.viewerId) _clear(ended: true);
    }, onError: (Object _) => _clear(ended: true));
    unawaited(_load());
  }

  void _clear({bool ended = false}) {
    if (!mounted) return;
    _generation++;
    _expiry?.cancel();
    setState(() {
      _reel = null;
      _loading = false;
      _identityEnded = _identityEnded || ended;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _expiry?.cancel();
    setState(() {
      _reel = null;
      _loading = true;
    });
    try {
      if (!_sameViewer || !_foreground) return;
      final view = await widget.service.loadView(
        widget.reelId,
        commentLimit: 1,
      );
      if (!mounted ||
          generation != _generation ||
          !_sameViewer ||
          !_foreground) {
        return;
      }
      if (view.reel.id != widget.reelId ||
          !view.reel.availability.isAvailableAt(widget.now())) {
        return;
      }
      setState(() => _reel = view.reel);
      _armExpiry();
    } catch (_) {
      // Never reveal whether the Reel is private, blocked, missing or expired.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _armExpiry() {
    _expiry?.cancel();
    final deadline = _reel?.availability.contentExpiresAt;
    if (deadline == null) return;
    final remaining = deadline.difference(widget.now());
    if (remaining <= Duration.zero) {
      _clear();
      return;
    }
    _expiry = Timer(
      remaining > const Duration(hours: 12)
          ? const Duration(hours: 12)
          : remaining,
      () {
        if (mounted) _armExpiry();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _clear();
    } else if (_sameViewer) {
      unawaited(_load());
    }
  }

  Widget _guardOverlay(BuildContext context, WidgetBuilder contentBuilder) =>
      ReelPrivateOverlayGuard(
        service: widget.service,
        viewerId: widget.viewerId,
        now: widget.now,
        contentExpiresAt: _reel?.availability.contentExpiresAt,
        initiallyAllowed:
            mounted &&
            _sameViewer &&
            _foreground &&
            (_reel?.availability.isAvailableAt(widget.now()) ?? false),
        contentBuilder: contentBuilder,
      );

  @override
  void dispose() {
    _generation++;
    unawaited(_identity?.cancel());
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final media = MediaQuery.of(context);
    final title = copy.text('Comments', 'Komentarze');
    final reel =
        _sameViewer &&
            _foreground &&
            (_reel?.availability.isAvailableAt(widget.now()) ?? false)
        ? _reel
        : null;
    return Material(
      key: const ValueKey('reel-link-comments-host'),
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  math.max(0, media.size.height - media.viewInsets.bottom) *
                  .86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YoModalSheetChrome(
                  sheetLabel: title,
                  surfaceColor: palette.surfaceRaised,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: reel == null
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: _loading
                                ? YoLoadingIndicator(
                                    message: copy.text(
                                      'Loading Reel',
                                      'Ładowanie Reela',
                                    ),
                                  )
                                : YoErrorState(
                                    compact: true,
                                    message: _sameViewer
                                        ? copy.text(
                                            'This Reel is unavailable right now.',
                                            'Ten Reel jest teraz niedostępny.',
                                          )
                                        : copy.text(
                                            'Sign in to open this Reel.',
                                            'Zaloguj się, aby otworzyć ten Reel.',
                                          ),
                                    onRetry: _sameViewer && _foreground
                                        ? _load
                                        : null,
                                  ),
                          ),
                        )
                      : ReelCommentsView(
                          key: ValueKey(
                            'reel-link-comments-${widget.viewerId}-${widget.reelId}',
                          ),
                          reel: reel,
                          service: widget.service,
                          onReelUpdated: (_) {},
                          overlayBuilder: _guardOverlay,
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
