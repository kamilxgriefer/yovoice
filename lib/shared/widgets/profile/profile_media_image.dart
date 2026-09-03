import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

typedef ProfileMediaImageProvider = ImageProvider<Object> Function(Uri uri);

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
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
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
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;

  @override
  State<ProfileMediaImage> createState() => _ProfileMediaImageState();
}

class _ProfileMediaImageState extends State<ProfileMediaImage> {
  Uri? _resolvedUri;
  int _resolutionGeneration = 0;

  @override
  void initState() {
    super.initState();
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
      if (identityChanged) {
        _resolvedUri = null;
      }
      if (oldWidget.revision != widget.revision) {
        final userId = widget.userId?.trim();
        if (userId != null && userId.isNotEmpty) {
          ProfileMediaService.evictUser(userId);
        }
      }
      _resolve();
    }
  }

  void _resolve() {
    final generation = ++_resolutionGeneration;
    final userId = widget.userId?.trim();
    if (userId == null || userId.isEmpty) {
      _resolvedUri = null;
      return;
    }
    Future<Uri?> grant;
    try {
      grant = (widget.service ?? ProfileMediaService()).resolve(
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
      return;
    }
    grant.then(
      (uri) {
        if (!mounted || generation != _resolutionGeneration) return;
        // A successful `available: false` response is authoritative and
        // clears a removed photo. While this future is pending (or if it
        // fails), [_resolvedUri] deliberately keeps the last successful
        // public-profile revision on screen instead of flashing an initial.
        setState(() => _resolvedUri = uri);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('[IMAGE] profile media grant failed: $error');
        }
        // Transient network/auth refresh failures retain the last resolved
        // image. A later publicProfiles revision will trigger another grant.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = _resolvedUri;
    if (uri == null) return widget.fallback;
    return Image(
      key: widget.imageKey,
      image: widget.imageProvider?.call(uri) ?? NetworkImage(uri.toString()),
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      frameBuilder: (context, child, frame, synchronous) => synchronous
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[IMAGE] profile media grant failed to load: $error');
        }
        return KeyedSubtree(key: widget.errorKey, child: widget.fallback);
      },
    );
  }
}
