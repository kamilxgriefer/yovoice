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
  Future<Uri?>? _grant;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ProfileMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.kind != widget.kind ||
        oldWidget.service != widget.service ||
        oldWidget.revision != widget.revision) {
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
    final userId = widget.userId?.trim();
    if (userId == null || userId.isEmpty) {
      _grant = null;
      return;
    }
    try {
      _grant = (widget.service ?? ProfileMediaService()).resolve(
        userId: userId,
        kind: widget.kind,
      );
    } catch (error) {
      // Rendering identity media is optional. During app bootstrap, logout,
      // tests, or a revoked session the Firebase-backed resolver may be
      // unavailable synchronously. Fail closed to the intentional fallback
      // instead of taking down the surrounding screen.
      if (kDebugMode) {
        debugPrint('[IMAGE] profile media resolver unavailable: $error');
      }
      _grant = Future<Uri?>.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grant = _grant;
    if (grant == null) return widget.fallback;
    return FutureBuilder<Uri?>(
      future: grant,
      builder: (context, snapshot) {
        final uri = snapshot.data;
        if (uri == null) return widget.fallback;
        return Image(
          key: widget.imageKey,
          image:
              widget.imageProvider?.call(uri) ?? NetworkImage(uri.toString()),
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
      },
    );
  }
}
