import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

enum _MomentDetailRefreshTrigger {
  initial,
  appResume,
  routeReturn,
  mutation,
  retry,
}

bool _momentDetailIsGoneError(Object error) =>
    error is FirebaseFunctionsException &&
    const <String>{
      'permission-denied',
      'not-found',
      'gone',
    }.contains(error.code);

/// One Voice Moment, full page: author identity, the caption as the
/// heading, a real player with a position-fed waveform, engagement,
/// the likers' avatar row, and the comment thread with its composer.
///
/// Every fact rendered is a document's fact. Moments carry no separate
/// title and no tags, so the caption IS the heading and no tag chips
/// exist; there is no play counter in the schema, so none is printed;
/// the "Top reactions" avatars come from the same privacy-filtered v2
/// projection as the Moment, best-effort.
///
/// Pushed as a plain route it carries its own Back control; the shell
/// hosts it inside the persistent bottom navigation (Moments active) on
/// mobile. The author additionally sees the availability line — a real
/// countdown, or "Stays until deleted" for a permanent Moment — and the
/// Delete action.
class MomentDetailScreen extends StatefulWidget {
  const MomentDetailScreen({
    required this.moment,
    this.momentService,
    this.feedService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.playerFactory,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final MomentService? momentService;
  final HomeFeedService? feedService;
  final MomentViewsService? viewsService;
  final ContentReportService? contentReportService;
  final FirebaseAuth? auth;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen>
    with RouteAware, WidgetsBindingObserver {
  MomentService? _moments;
  HomeFeedService? _feed;
  MomentViewsService? _views;

  late VoiceMoment _moment = widget.moment;

  /// The document disappeared. Either it never loaded (opened from a
  /// stale reference) or it was deleted while open — both render the
  /// graceful gone-state; the author's own delete pops instead.
  bool _missing = false;
  bool _selfDeleted = false;
  bool _deleting = false;
  bool _liking = false;
  late final MomentExpiryScheduler _expiry;
  DateTime? _expiredThrough;
  bool _expiredByDeadline = false;

  Future<List<MomentReactor>>? _reactions;
  List<MomentComment>? _comments;
  bool _commentsTruncated = false;
  String? _nextCommentCursor;
  Object? _commentsError;
  bool _loadingMoreComments = false;
  ModalRoute<void>? _observedRoute;
  final Set<_MomentDetailRefreshTrigger> _canonicalRefreshesInFlight =
      <_MomentDetailRefreshTrigger>{};
  int _viewLoadGeneration = 0;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  bool _isPlaying = false;
  bool _everPlayed = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _playbackError;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'Moment comment');
  final FocusNode _goneBackFocus = FocusNode(debugLabel: 'Expired Moment back');
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();
  bool _sending = false;

  AppLocalizations get _copy => AppLocalizations.of(context);

  String get _uid {
    try {
      return (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  bool get _isOwn => _uid.isNotEmpty && _uid == _moment.authorId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expiry = MomentExpiryScheduler(
      onDeadline: _handleExpiryDeadline,
      clock: widget.expiryClock,
      timerFactory: widget.expiryTimerFactory,
    );
    _expiredByDeadline = !_moment.isActiveAt(_effectiveNow());
    if (!_expiredByDeadline) _expiry.schedule([_moment]);
    // Each seam guarded separately, matching the other Moment surfaces:
    // one service that cannot be constructed must not take the others
    // down with it.
    try {
      _moments = widget.momentService ?? MomentService();
    } catch (_) {
      _moments = null;
    }
    try {
      _feed = widget.feedService ?? HomeFeedService();
    } catch (_) {
      _feed = null;
    }
    try {
      _views = widget.viewsService ?? MomentViewsService();
    } catch (_) {
      _views = null;
    }

    final moments = _moments;
    if (moments != null) {
      unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.initial));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _observedRoute)) return;
    if (_observedRoute != null) appRouteObserver.unsubscribe(this);
    _observedRoute = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.routeReturn));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.appResume));
  }

  Future<void> _loadView({
    String? commentCursor,
    bool append = false,
    _MomentDetailRefreshTrigger trigger = _MomentDetailRefreshTrigger.retry,
  }) async {
    final service = _moments;
    if (service == null || (append && _loadingMoreComments)) return;
    if (!append && !_canonicalRefreshesInFlight.add(trigger)) return;
    final requestGeneration = append
        ? _viewLoadGeneration
        : ++_viewLoadGeneration;
    if (append && mounted) {
      setState(() {
        _loadingMoreComments = true;
        _commentsError = null;
      });
    }
    try {
      final view = await service.loadMomentView(
        widget.moment.id,
        commentCursor: commentCursor,
      );
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      final expired = !view.moment.isActiveAt(_effectiveNow());
      final previous = _comments ?? const <MomentComment>[];
      final merged = <String, MomentComment>{
        if (append)
          for (final comment in previous) comment.id: comment,
        for (final comment in view.comments) comment.id: comment,
      }.values.toList(growable: false);
      setState(() {
        _missing = false;
        _moment = view.moment;
        _expiredByDeadline = expired;
        _comments = merged;
        _commentsTruncated = view.commentsTruncated;
        _nextCommentCursor = view.nextCommentCursor;
        _commentsError = null;
        _loadingMoreComments = false;
        _reactions = Future<List<MomentReactor>>.value(view.topReactions);
      });
      _expiry.schedule(expired ? const <VoiceMoment>[] : [view.moment]);
      if (expired) {
        _stopPlaybackForGone();
        _announceGone(previousFocus: null);
      }
    } catch (error) {
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      if (_momentDetailIsGoneError(error)) {
        _clearProjectionAndShowGone();
      } else {
        setState(() => _commentsError = error);
      }
    } finally {
      if (!append) _canonicalRefreshesInFlight.remove(trigger);
      if (mounted && append && _loadingMoreComments) {
        setState(() => _loadingMoreComments = false);
      }
    }
  }

  void _clearProjectionAndShowGone() {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiry.schedule(const <VoiceMoment>[]);
    _stopPlaybackForGone(notify: false);
    setState(() {
      _missing = true;
      _comments = null;
      _commentsTruncated = false;
      _nextCommentCursor = null;
      _commentsError = null;
      _loadingMoreComments = false;
      _reactions = null;
      _playbackError = null;
    });
    _announceGone(previousFocus: recoverFocus ? previousFocus : null);
  }

  Future<void> _loadMoreComments() async {
    final cursor = _nextCommentCursor;
    if (!_commentsTruncated || cursor == null) return;
    await _loadView(commentCursor: cursor, append: true);
  }

  @override
  void dispose() {
    _viewLoadGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _expiry.dispose();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _goneBackFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- playback

  DateTime _effectiveNow() {
    final now = _expiry.now();
    final floor = _expiredThrough;
    return floor != null && floor.isAfter(now) ? floor : now;
  }

  void _stopPlaybackForGone({bool notify = true}) {
    final player = _player;
    if (player != null) {
      unawaited(player.stop().catchError((Object _) {}));
    }
    if (!mounted) return;
    void clearPlaybackState() {
      _isPlaying = false;
      _position = Duration.zero;
      _duration = null;
    }

    if (notify) {
      setState(clearPlaybackState);
    } else {
      clearPlaybackState();
    }
  }

  void _handleExpiryDeadline(DateTime deadline) {
    if (!mounted) return;
    if (_expiredThrough == null || deadline.isAfter(_expiredThrough!)) {
      _expiredThrough = deadline;
    }
    if (_moment.isActiveAt(_effectiveNow())) {
      _expiry.schedule([_moment]);
      return;
    }
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _stopPlaybackForGone();
    setState(() => _expiredByDeadline = true);
    _expiry.schedule(const <VoiceMoment>[]);
    _announceGone(previousFocus: recoverFocus ? previousFocus : null);
  }

  void _announceGone({required FocusNode? previousFocus}) {
    _expiryAnnouncer.announce(
      context,
      transition: 'detail-gone-${widget.moment.id}',
      message: _copy.text(
        'Voice Moment is no longer available.',
        'Ten Voice Moment nie jest już dostępny.',
      ),
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _goneBackFocus,
      previousFocus: previousFocus,
    );
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _player = player;
    _playerSubscriptions
      ..add(
        player.onPositionChanged.listen((position) {
          if (!mounted) return;
          setState(() {
            _position = position;
            _playbackError = null;
          });
        }),
      )
      ..add(
        player.onDurationChanged.listen((duration) {
          if (!mounted) return;
          setState(() => _duration = duration);
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _position = _duration ?? _position;
          });
        }),
      );
    return player;
  }

  Future<void> _togglePlay() async {
    final moments = _moments;
    if (moments == null || !_moment.hasMediaReference) {
      setState(
        () => _playbackError = _copy.text(
          'This Moment has no audio to play.',
          'Ten Moment nie zawiera nagrania do odtworzenia.',
        ),
      );
      return;
    }
    final player = _ensurePlayer();

    if (_isPlaying) {
      try {
        await player.pause();
      } catch (_) {
        // Nothing to pause.
      }
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    final resuming = _everPlayed && _position > Duration.zero;
    setState(() {
      _isPlaying = true;
      _playbackError = null;
    });

    // Playback starting IS the viewed event, wherever it starts.
    final views = _views;
    if (!resuming && views != null) {
      unawaited(views.markViewed(_moment.id).catchError((Object _) {}));
    }

    try {
      if (resuming) {
        await player.resume();
      } else {
        _everPlayed = true;
        final uri = await moments.resolveMediaUri(momentId: _moment.id);
        if (!mounted || _missing) return;
        await player.play(UrlSource(uri.toString()));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackError = _copy.text(
          'This Moment could not be played. Try again.',
          'Nie udało się odtworzyć tego Momentu. Spróbuj ponownie.',
        );
      });
    }
  }

  Future<void> _seek(Duration target) async {
    final player = _player;
    if (player == null || !_everPlayed) return;
    try {
      await player.seek(target);
    } catch (_) {
      // Seeking an unloaded source is a no-op, not a fault.
    }
  }

  // ------------------------------------------------------------- actions

  Future<void> _share() async {
    // The same real link mechanism every other Moment surface uses: the
    // website resolves ?moment= on yovoice.app.
    await SharePlus.instance.share(
      ShareParams(
        text: _copy.text(
          'Listen to ${_moment.authorName} on YO Voice: '
              'https://yovoice.app/?moment=${_moment.id}',
          'Posłuchaj ${_moment.authorName} w YO Voice: '
              'https://yovoice.app/?moment=${_moment.id}',
        ),
      ),
    );
  }

  Future<void> _report() async {
    final copy = _copy;
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(
        momentId: _moment.id,
        reportReceipt: _moment.reportReceipt,
      ),
      title: copy.text('Report this Voice Moment', 'Zgłoś ten Voice Moment'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'Moment attached. ${_moment.authorName} is not told who reported '
            'it.',
        'Zgłoszenie wraz z tym Momentem trafi do zespołu moderacji YO Voice. '
            '${_moment.authorName} nie dowie się, kto je wysłał.',
      ),
    );
  }

  /// The author's exit — for a permanent Moment the only one. On success
  /// the page pops back to the feed; the feed prunes the row through its
  /// own-Moments listener.
  Future<void> _confirmDelete() async {
    final service = _moments;
    if (service == null || _deleting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Delete this moment?', 'Usunąć ten Moment?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              'This cannot be undone.',
              'Tej operacji nie można cofnąć.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              key: const ValueKey('moment-detail-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              key: const ValueKey('moment-detail-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(copy.text('Delete', 'Usuń')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final player = _player;
      if (player != null) {
        try {
          await player.stop();
        } catch (_) {
          // Nothing was playing.
        }
      }
      _selfDeleted = true;
      await service.deleteMoment(_moment);
    } catch (_) {
      _selfDeleted = false;
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'The Moment could not be deleted. Try again.',
                'Nie udało się usunąć Momentu. Spróbuj ponownie.',
              ),
            ),
          ),
        );
      return;
    }
    if (!mounted) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _copy.text('Voice Moment deleted.', 'Voice Moment usunięty.'),
          ),
        ),
      );
    navigator.maybePop();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final service = _moments;
    if (text.isEmpty || service == null || _sending) return;
    setState(() => _sending = true);
    try {
      await service.createTextComment(momentId: _moment.id, text: text);
      _composer.clear();
      await _loadView(trigger: _MomentDetailRefreshTrigger.mutation);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _copy.text(
                'Could not post your comment. Try again.',
                'Nie udało się dodać komentarza. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final gone =
        (_missing && !_selfDeleted) ||
        _expiredByDeadline ||
        !_moment.isActiveAt(_effectiveNow());

    return Scaffold(
      key: const ValueKey('moment-detail-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: gone
            ? _GoneState(
                backFocus: _goneBackFocus,
                onBack: () => Navigator.of(context).maybePop(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // One readable column at every width: the page is a
                  // mobile-first route, and on a wider window the content
                  // holds a comfortable measure instead of stretching.
                  final compact = constraints.maxWidth < 600;
                  final side = compact ? 16.0 : 24.0;
                  return Column(
                    children: [
                      _Header(
                        onBack: () => Navigator.of(context).maybePop(),
                        onShare: () => unawaited(_share()),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: ListView(
                              key: const ValueKey('moment-detail-scroll'),
                              padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                              children: [
                                _authorBlock(),
                                const SizedBox(height: 14),
                                _captionHeading(),
                                const SizedBox(height: 16),
                                _playerPanel(),
                                if (_playbackError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _playbackError!,
                                    style: TextStyle(
                                      color: colors.error,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _engagementRow(),
                                _reactionsSection(),
                                const SizedBox(height: 16),
                                Divider(color: palette.border, height: 1),
                                const SizedBox(height: 14),
                                _commentsSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _composerBar(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _authorBlock() {
    final moment = _moment;
    final palette = context.appPalette;
    final copy = _copy;
    final age = momentRelativeAge(moment.createdAt, copy: copy);
    // The author sees the availability fact even for a permanent Moment
    // ("Stays until deleted"); everyone else only a real countdown.
    final availability = _isOwn
        ? momentAvailabilityLabel(moment.expiresAt, copy: copy)
        : momentExpiryLabel(moment.expiresAt, copy: copy);
    return Row(
      children: [
        AccessibleTapRegion(
          onTap: () => showProfilePreview(
            context,
            userId: moment.authorId,
            displayName: moment.authorName,
            photoUrl: moment.authorPhotoUrl,
          ),
          semanticLabel: copy.text(
            'Open profile for ${moment.authorName}',
            'Otwórz profil: ${moment.authorName}',
          ),
          tooltip: copy.text(
            'Open ${moment.authorName}\'s profile',
            'Otwórz profil ${moment.authorName}',
          ),
          circular: true,
          child: UserAvatar(
            radius: 23,
            userId: moment.authorId,
            photoUrl: moment.authorPhotoUrl,
            displayName: moment.authorName,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      moment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  UserIdentityBadges(uid: moment.authorId),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  if (age.isNotEmpty)
                    Text(
                      age,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  if (availability != null)
                    Text(
                      availability,
                      key: const ValueKey('moment-detail-availability'),
                      style: TextStyle(
                        // A permanent Moment's label is a calm fact, not
                        // a warning-coloured countdown.
                        color: moment.isPermanent
                            ? palette.textTertiary
                            : palette.warningForeground,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Moments carry a caption and nothing else — no separate title, no
  /// tags — so the caption IS the page heading and no tag chips exist.
  Widget _captionHeading() {
    final caption = _moment.caption.trim();
    return Text(
      caption.isEmpty ? _copy.text('Voice Moment', 'Voice Moment') : caption,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.appPalette.textPrimary,
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _playerPanel() {
    final moment = _moment;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final copy = _copy;
    final totalSeconds = _duration?.inSeconds ?? moment.durationSeconds;
    final hasTotal = totalSeconds > 0;
    final progress = hasTotal
        ? (_position.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.surface, colors.primary, isDark ? .5 : .14)!,
            Color.lerp(palette.surface, colors.secondary, isDark ? .26 : .08)!,
            palette.surface,
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .35)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, waveConstraints) {
              final waveWidth = waveConstraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: hasTotal && waveWidth > 0
                    ? (details) {
                        final fraction = (details.localPosition.dx / waveWidth)
                            .clamp(0.0, 1.0);
                        unawaited(
                          _seek(
                            Duration(
                              milliseconds: (totalSeconds * 1000 * fraction)
                                  .round(),
                            ),
                          ),
                        );
                      }
                    : null,
                child: StoryWaveform(progress: progress, height: 52),
              );
            },
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            label: _isPlaying
                ? copy.text('Pause this Moment', 'Wstrzymaj ten Moment')
                : copy.text('Play this Moment', 'Odtwórz ten Moment'),
            child: Material(
              color: colors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                key: const ValueKey('moment-detail-play'),
                customBorder: const CircleBorder(),
                onTap: () => unawaited(_togglePlay()),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: colors.onPrimary,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasTotal
                ? '${_clock(_position.inSeconds)} / ${_clock(totalSeconds)}'
                : '',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _engagementRow() {
    final moment = _moment;
    final feed = _feed;
    final canReport = _uid.isNotEmpty && !_isOwn;
    final copy = _copy;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (feed == null)
          _ActionChip(
            icon: Icons.favorite_border_rounded,
            label: moment.likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '${moment.likeCount}',
            active: false,
            onTap: null,
          )
        else
          _ActionChip(
            key: const ValueKey('moment-detail-like'),
            icon: moment.callerLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: moment.likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '${moment.likeCount}',
            active: moment.callerLiked,
            semanticLabel: moment.callerLiked
                ? copy.text(
                    'Unlike this Moment',
                    'Usuń polubienie tego Momentu',
                  )
                : copy.text('Like this Moment', 'Polub ten Moment'),
            onTap: _liking ? null : () => unawaited(_toggleLike(feed)),
          ),
        _ActionChip(
          key: const ValueKey('moment-detail-comments'),
          icon: Icons.mode_comment_outlined,
          label: moment.commentCount == 0
              ? copy.text('Comment', 'Komentarz')
              : '${moment.commentCount}',
          active: false,
          semanticLabel: copy.text('Write a comment', 'Napisz komentarz'),
          onTap: _composerFocus.requestFocus,
        ),
        _ActionChip(
          key: const ValueKey('moment-detail-share'),
          icon: Icons.share_outlined,
          label: copy.text('Share', 'Udostępnij'),
          active: false,
          semanticLabel: copy.text(
            'Share this Moment',
            'Udostępnij ten Moment',
          ),
          onTap: () => unawaited(_share()),
        ),
        if (canReport)
          _ActionChip(
            key: ValueKey('moment-detail-report-${moment.id}'),
            icon: Icons.flag_outlined,
            label: copy.text('Report', 'Zgłoś'),
            active: false,
            semanticLabel: copy.text(
              'Report this Voice Moment',
              'Zgłoś ten Voice Moment',
            ),
            onTap: () => unawaited(_report()),
          ),
        if (_isOwn)
          _ActionChip(
            key: ValueKey('moment-detail-delete-${moment.id}'),
            icon: Icons.delete_outline_rounded,
            label: copy.text('Delete', 'Usuń'),
            active: false,
            destructive: true,
            semanticLabel: copy.text(
              'Delete this Voice Moment',
              'Usuń ten Voice Moment',
            ),
            onTap: _deleting ? null : () => unawaited(_confirmDelete()),
          ),
      ],
    );
  }

  Future<void> _toggleLike(HomeFeedService feed) async {
    if (_liking) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final previous = _moment;
    final desiredLiked = !previous.callerLiked;
    setState(() {
      _liking = true;
      _moment = previous.copyWith(
        callerLiked: desiredLiked,
        likeCount: (previous.likeCount + (desiredLiked ? 1 : -1)).clamp(
          0,
          1 << 31,
        ),
      );
    });
    try {
      await feed.setLike(previous.id, liked: desiredLiked);
      if (!mounted || _moment.id != previous.id) return;
      setState(() => _liking = false);
      await _loadView(trigger: _MomentDetailRefreshTrigger.mutation);
    } catch (_) {
      if (mounted && _moment.id == previous.id) {
        setState(() {
          _moment = previous;
          _liking = false;
        });
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'Your like could not be saved. Try again.',
                'Nie udało się zapisać polubienia. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    }
  }

  /// The likers' avatar row from the server-owned v2 projection. Absent while
  /// loading, absent when nobody has liked, absent when no identity could be
  /// safely projected — never a spinner, never an invented face.
  Widget _reactionsSection() {
    final reactions = _reactions;
    final likeCount = _moment.likeCount;
    if (reactions == null || likeCount <= 0) return const SizedBox.shrink();
    final copy = _copy;
    return FutureBuilder<List<MomentReactor>>(
      future: reactions,
      builder: (context, snapshot) {
        final palette = context.appPalette;
        final reactors = snapshot.data ?? const <MomentReactor>[];
        if (reactors.isEmpty) return const SizedBox.shrink();
        final remainder = likeCount - reactors.length;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Top reactions', 'Najpopularniejsze reakcje'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('moment-detail-reactions'),
                children: [
                  for (final reactor in reactors)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: reactor.displayName,
                        child: UserAvatar(
                          radius: 15,
                          userId: reactor.uid,
                          photoUrl: reactor.photoUrl,
                          displayName: reactor.displayName,
                        ),
                      ),
                    ),
                  if (remainder > 0)
                    Container(
                      // Content-sized, not a fixed circle: "+409" is a
                      // real value here and must widen the pill instead
                      // of wrapping and clipping inside 30 px.
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: palette.surfaceRaised,
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        '+$remainder',
                        maxLines: 1,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _commentsSection() {
    final service = _moments;
    final palette = context.appPalette;
    final copy = _copy;
    final commentsLabel = copy.text('Comments', 'Komentarze');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _moment.commentCount > 0
              ? '$commentsLabel (${_moment.commentCount})'
              : commentsLabel,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (service == null)
          Text(
            copy.text(
              'Comments are unavailable right now.',
              'Komentarze są teraz niedostępne.',
            ),
            style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
          )
        else if (_commentsError != null && _comments == null)
          TextButton.icon(
            key: const ValueKey('moment-comments-retry'),
            onPressed: () => unawaited(
              _loadView(trigger: _MomentDetailRefreshTrigger.retry),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              copy.text(
                'Could not load comments. Try again.',
                'Nie udało się wczytać komentarzy. Spróbuj ponownie.',
              ),
            ),
          )
        else if (_comments == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_comments!.isEmpty)
          Text(
            copy.text('Be the first to comment.', 'Napisz pierwszy komentarz.'),
            style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final comment in _comments!) _CommentRow(comment: comment),
              if (_commentsTruncated || _loadingMoreComments) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('moment-comments-load-more'),
                  onPressed: _loadingMoreComments
                      ? null
                      : () => unawaited(_loadMoreComments()),
                  icon: _loadingMoreComments
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(copy.text('Load more', 'Wczytaj więcej')),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _composerBar() {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = _copy;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('moment-detail-comment-field'),
              controller: _composer,
              focusNode: _composerFocus,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(_send()),
              enabled: _moments != null,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: copy.text('Write a comment...', 'Napisz komentarz…'),
                hintStyle: TextStyle(color: palette.textTertiary),
                filled: true,
                fillColor: palette.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('moment-detail-comment-send'),
            tooltip: copy.text('Post comment', 'Dodaj komentarz'),
            onPressed: _sending || _moments == null
                ? null
                : () => unawaited(_send()),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            icon: _sending
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

/// Back and Share — the page's own chrome, present in both hosting modes
/// (the shell keeps the bottom navigation, a plain push keeps only this).
class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onShare});

  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('moment-detail-back'),
            onPressed: onBack,
            tooltip: copy.text('Back', 'Wstecz'),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          ),
          Expanded(
            child: Text(
              'Moment',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('moment-detail-share-top'),
            onPressed: onShare,
            tooltip: copy.text('Share this Moment', 'Udostępnij ten Moment'),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.share_outlined, color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The graceful gone-state: the Moment expired, was deleted, or never
/// loaded. A real explanation and a way back — never a spinner that spins
/// forever and never a stale page pretending the audio still exists.
class _GoneState extends StatelessWidget {
  const _GoneState({required this.backFocus, required this.onBack});

  final FocusNode backFocus;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('moment-detail-gone'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_off_outlined,
              size: 34,
              color: palette.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              copy.text(
                'This Moment is no longer available',
                'Ten Moment nie jest już dostępny',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy.text(
                'It reached the end of its availability or was deleted by '
                    'its author.',
                'Minął czas jego dostępności lub autor go usunął.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('moment-detail-gone-back'),
              focusNode: backFocus,
              onPressed: onBack,
              child: Text(copy.text('Back to Moments', 'Wróć do Momentów')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final MomentComment comment;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            radius: 15,
            userId: comment.authorId,
            photoUrl: comment.authorPhotoUrl,
            displayName: comment.authorName,
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
                      comment.authorName,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    UserIdentityBadges(
                      uid: comment.authorId,
                      variant: IdentityBadgeVariant.icon,
                    ),
                    Text(
                      momentRelativeAge(comment.createdAt, copy: copy),
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // No like counts on comments: comment documents carry
                // none in the schema, so none are printed.
                if (comment.isVoice)
                  Text(
                    copy.text(
                      'Voice reply · ${comment.durationSeconds}s'
                          '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                      'Odpowiedź głosowa · ${comment.durationSeconds} s'
                          '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                    ),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  )
                else
                  Text(
                    comment.text,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.4,
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.destructive = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Delete wears the error tint so a destructive action never looks
  /// like one more neutral chip.
  final bool destructive;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final tint = destructive
        ? colors.error
        : (active ? colors.secondary : palette.textSecondary);
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      child: Material(
        color: destructive ? palette.dangerSurface : palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: tint),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: destructive ? colors.error : palette.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
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

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
