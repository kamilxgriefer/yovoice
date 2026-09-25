import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

typedef ProfileMediaImageProvider = ImageProvider<Object> Function(Uri uri);

/// Wraps a loaded profile image in extra layers that belong to the photo and
/// must appear with it — never over the fallback. [image] is the laid-out
/// photo; [provider] is the same provider it paints, so a second copy of the
/// photo (a blurred one, say) is an image-cache hit rather than a second
/// fetch or decode.
typedef ProfileMediaImageLayerBuilder =
    Widget Function(
      BuildContext context,
      Widget image,
      ImageProvider<Object> provider,
    );

/// Callable failure codes that describe an unlucky moment rather than an
/// answer. Everything else — above all `permission-denied`, which is the
/// normal, permanent response for friends-only visibility and for blocks
/// (`functions/profile/media.js`) — is a decision the server already made,
/// and re-asking would only spend the caller's `PROFILE_MEDIA_ACCESS_LIMIT`
/// budget (180 calls per minute) to hear the same thing.
const Set<String> _retryableGrantCodes = {
  'unavailable',
  'internal',
  'deadline-exceeded',
  'aborted',
  'unauthenticated',
  'cancelled',
};

/// Backoff for the automatic re-resolution below: one quick retry for a blip
/// during cold start, then one slower one for a network that needs a moment
/// longer. Two attempts is deliberate — a screenful of avatars shares a
/// single-flight grant per target, but a failing backend must not be turned
/// into an endless client-side poll.
const List<Duration> _grantRetryBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 8),
];

/// Whether a failed grant is worth asking about again.
///
/// [FormatException] means the response itself was rejected by the client
/// contract, and [Error]s (notably the [StateError] raised when the cache was
/// cleared mid-flight, i.e. logout) are boundary/programming failures: both
/// fail closed. Anything else that is not a decided Firebase answer — socket,
/// TLS and timeout exceptions — is treated as transport noise.
@visibleForTesting
bool isRetryableProfileMediaFailure(Object error) {
  if (error is FormatException) return false;
  if (error is FirebaseException) {
    final code = error.code.trim().toLowerCase().replaceAll('_', '-');
    final separator = code.lastIndexOf('/');
    return _retryableGrantCodes.contains(
      separator == -1 ? code : code.substring(separator + 1),
    );
  }
  if (error is Error) return false;
  return true;
}

/// Why [ProfileMediaImage] is showing its fallback instead of a photo.
///
/// The widget itself renders the same intentional fallback for all of these,
/// which is right for a 36px avatar in a list. A surface that promises a photo
/// — the fullscreen viewer — needs to tell them apart, because "still
/// loading", "this account has no photo" and "we could not load it" are three
/// different sentences and only one of them may be shown at a time.
enum ProfileMediaResolution { pending, available, absent, failed }

/// Viewer-aware profile image. It never dereferences a denormalized URL from
/// Firestore/Auth; the target uid is exchanged for a short-lived grant after
/// the server rechecks visibility, friendship, blocks and account state.
class ProfileMediaImage extends StatefulWidget {
  const ProfileMediaImage({
    required this.userId,
    required this.kind,
    required this.fit,
    required this.fallback,
    this.service,
    this.revision,
    this.imageProvider,
    this.imageKey,
    this.errorKey,
    this.onResolution,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.imageLayerBuilder,
    super.key,
  });

  final String? userId;
  final ProfileMediaKind kind;
  final BoxFit fit;
  final Widget fallback;
  final ProfileMediaService? service;
  final Object? revision;
  final ProfileMediaImageProvider? imageProvider;
  final Key? imageKey;
  final Key? errorKey;

  /// Optional observer of the resolution state above. Defaults to null, so
  /// every existing call site keeps today's behaviour exactly.
  final ValueChanged<ProfileMediaResolution>? onResolution;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;

  /// Optional layers drawn with the photo (the profile hero's scrim and soft
  /// focus). They fade in together with the first frame and vanish with it,
  /// so a surface can never show a photo's scrim over its fallback. Null —
  /// the default — keeps every existing call site's output unchanged.
  final ProfileMediaImageLayerBuilder? imageLayerBuilder;

  @override
  State<ProfileMediaImage> createState() => _ProfileMediaImageState();
}

class _ProfileMediaImageState extends State<ProfileMediaImage> {
  Uri? _resolvedUri;
  ImageProvider<Object>? _resolvedProvider;
  ProfileMediaResolution _resolution = ProfileMediaResolution.pending;
  int _resolutionGeneration = 0;
  Timer? _expiryTimer;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  StreamSubscription<ProfileMediaAccessBoundary>? _boundarySubscription;
  ProfileMediaService? _ownedService;

  @override
  void initState() {
    super.initState();
    _boundarySubscription = ProfileMediaService.accessBoundaries.listen(
      _handleAccessBoundary,
    );
    _resolve();
  }

  @override
  void didUpdateWidget(ProfileMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.kind != widget.kind ||
        oldWidget.service != widget.service;
    final revisionChanged = oldWidget.revision != widget.revision;
    if (identityChanged || revisionChanged) {
      if (oldWidget.service != widget.service) {
        _ownedService = null;
      }
      if (identityChanged) {
        _clearResolvedImage(notify: false);
      }
      // The revision is already part of the service cache key. Evicting here
      // made every mounted copy of the same avatar invalidate its siblings'
      // in-flight grant, causing duplicate callable traffic and intermittent
      // fallback initials across Home, Chats and profile surfaces.
      _resolve();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_boundarySubscription?.cancel());
    _evictProvider(_resolvedProvider);
    super.dispose();
  }

  void _handleAccessBoundary(ProfileMediaAccessBoundary boundary) {
    final userId = widget.userId?.trim();
    if (boundary.userId != null && boundary.userId != userId) return;
    _resolutionGeneration += 1;
    _expiryTimer?.cancel();
    // A queued retry belongs to the session that just ended. Dropping it here
    // is what keeps a logout fail-closed instead of re-asking two seconds
    // later, and what keeps `pumpAndSettle` from waiting on a dead timer.
    _cancelRetry();
    _clearResolvedImage(notify: mounted);
    // A global boundary is logout/account switching: fail closed and wait for
    // a new widget/session. Target boundaries represent an upload, explicit
    // access change or scheduled expiry and may safely reauthorize.
    if (boundary.userId != null && mounted) _resolve();
  }

  /// Notifies [ProfileMediaImage.onResolution] of a real transition only.
  ///
  /// Some transitions are reported from `initState`, `didUpdateWidget` or an
  /// `errorBuilder`, i.e. while the tree is building; a listener that calls
  /// `setState` must not be invoked there, so those are deferred to the end
  /// of the frame and re-checked for staleness.
  void _reportResolution(ProfileMediaResolution resolution) {
    if (_resolution == resolution) return;
    _resolution = resolution;
    final callback = widget.onResolution;
    if (callback == null) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      callback(resolution);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _resolution == resolution) callback(resolution);
    });
  }

  void _clearResolvedImage({required bool notify}) {
    _reportResolution(ProfileMediaResolution.pending);
    final provider = _resolvedProvider;
    void clear() {
      _resolvedUri = null;
      _resolvedProvider = null;
    }

    if (notify) {
      setState(clear);
    } else {
      clear();
    }
    _evictProvider(provider);
  }

  void _evictProvider(ImageProvider<Object>? provider) {
    if (provider != null) unawaited(provider.evict());
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Re-resolves a grant that failed for a reason that may not still be true.
  ///
  /// The generation captured when the request was made is re-checked inside
  /// the callback, so a retry queued before an eviction, a revision change or
  /// a logout resolves into a no-op rather than a second callable.
  void _scheduleRetry(int generation, Object error) {
    if (_retryAttempts >= _grantRetryBackoff.length) return;
    if (!isRetryableProfileMediaFailure(error)) return;
    final delay = _grantRetryBackoff[_retryAttempts];
    _retryAttempts += 1;
    _cancelRetry();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted || generation != _resolutionGeneration) return;
      _resolve(isRetry: true);
    });
  }

  void _resolve({bool isRetry = false}) {
    _cancelRetry();
    // Only a fresh resolution — mount, identity change, revision change or an
    // access boundary — earns a new pair of attempts.
    if (!isRetry) _retryAttempts = 0;
    final generation = ++_resolutionGeneration;
    _reportResolution(ProfileMediaResolution.pending);
    final userId = widget.userId?.trim();
    if (userId == null || userId.isEmpty) {
      _clearResolvedImage(notify: false);
      return;
    }
    Future<ProfileMediaAccess> grant;
    late ProfileMediaService service;
    try {
      service = widget.service ?? (_ownedService ??= ProfileMediaService());
      grant = service.resolveAccess(
        userId: userId,
        kind: widget.kind,
        revision: widget.revision,
      );
    } catch (error) {
      // Rendering identity media is optional. During app bootstrap, logout,
      // tests, or a revoked session the Firebase-backed resolver may be
      // unavailable synchronously. Fail closed to the intentional fallback
      // instead of taking down the surrounding screen.
      if (kDebugMode) {
        debugPrint('[IMAGE] profile media resolver unavailable: $error');
      }
      _reportResolution(ProfileMediaResolution.failed);
      return;
    }
    grant.then(
      (access) {
        if (!mounted || generation != _resolutionGeneration) return;
        // A successful `available: false` response is authoritative and
        // clears a removed photo. While this future is pending (or if it
        // fails), [_resolvedUri] deliberately keeps the last successful
        // public-profile revision on screen instead of flashing an initial.
        final uri = access.uri;
        _reportResolution(
          uri == null
              ? ProfileMediaResolution.absent
              : ProfileMediaResolution.available,
        );
        final provider = uri == null
            ? null
            : widget.imageProvider?.call(uri) ?? NetworkImage(uri.toString());
        final previousProvider = _resolvedProvider;
        final previousUri = _resolvedUri;
        setState(() {
          _resolvedUri = uri;
          _resolvedProvider = provider;
        });
        if (previousUri != uri) _evictProvider(previousProvider);
        _expiryTimer?.cancel();
        final remaining = access.expiresAt.difference(service.nowUtc);
        if (remaining <= Duration.zero) {
          ProfileMediaService.evictUser(userId);
        } else {
          _expiryTimer = Timer(
            remaining,
            () => ProfileMediaService.evictUser(userId),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('[IMAGE] profile media grant failed: $error');
        }
        if (mounted && generation == _resolutionGeneration) {
          _reportResolution(ProfileMediaResolution.failed);
          _scheduleRetry(generation, error);
        }
        // Transient network/auth refresh failures retain the last resolved
        // image, and the retry above re-resolves them without waiting for a
        // publicProfiles revision, an eviction or a new screen.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = _resolvedUri;
    if (uri == null) return widget.fallback;
    final provider = _resolvedProvider ?? NetworkImage(uri.toString());
    final layers = widget.imageLayerBuilder;
    return Image(
      key: widget.imageKey,
      image: provider,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      frameBuilder: (context, child, frame, synchronous) {
        final layered = layers == null
            ? child
            : layers(context, child, provider);
        if (synchronous) return layered;
        // Reduce Motion: the photo simply appears — no 180 ms fade.
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: AppMotion.resolve(context, AppMotion.standard),
          child: layered,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[IMAGE] profile media grant failed to load: $error');
        }
        _reportResolution(ProfileMediaResolution.failed);
        return KeyedSubtree(key: widget.errorKey, child: widget.fallback);
      },
    );
  }
}
