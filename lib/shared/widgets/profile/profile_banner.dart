import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// The cosmic gradient every banner surface falls back to. Public so the
/// profile header and edit-profile preview stay on the same fallback
/// instead of drifting.
const LinearGradient kProfileBannerFallbackGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF53108C), Color(0xFF21102E), Color(0xFF09050F)],
);

/// The one way to render a profile banner.
///
/// Replaces `DecorationImage(image: NetworkImage(...))`, which silently
/// swallows load errors: a broken banner URL rendered as if the user had
/// no banner at all, which is indistinguishable from the bug this
/// refactor chases. Here a failed load falls back to the brand gradient
/// deliberately (never an empty rectangle), and the caller decides the
/// shape — the widget always fills whatever constraints it's given.
class ProfileBanner extends StatelessWidget {
  const ProfileBanner({
    this.userId,
    this.bannerUrl,
    this.mediaRevision,
    this.mediaService,
    this.overlay,
    this.fallback,
    this.alignment = Alignment.center,
    this.imageProvider,
    this.imageLayerBuilder,
    super.key,
  });

  final String? userId;

  /// Legacy source compatibility only; never dereferenced directly.
  final String? bannerUrl;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;

  /// Optional gradient painted over the image (e.g. the profile header's
  /// darkening scrim). Painted over the fallback too, so the two states
  /// keep identical depth.
  final Gradient? overlay;

  /// What is painted while there is no photo on screen — pending, absent or
  /// failed. Null keeps [kProfileBannerFallbackGradient]; the profile hero
  /// passes a theme-aware base so Pearl never flashes a dark slab.
  final Widget? fallback;

  /// Where `BoxFit.cover` anchors the photo when the box crops it.
  final AlignmentGeometry alignment;

  /// Test/preview seam, the same one [ProfileMediaImage] exposes.
  final ProfileMediaImageProvider? imageProvider;

  /// Layers that belong to the photo (see [ProfileMediaImageLayerBuilder]).
  final ProfileMediaImageLayerBuilder? imageLayerBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback ??
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: kProfileBannerFallbackGradient,
              ),
            ),
        ProfileMediaImage(
          userId: userId,
          kind: ProfileMediaKind.banner,
          fallback: const SizedBox.shrink(),
          fit: BoxFit.cover,
          alignment: alignment,
          revision: mediaRevision,
          service: mediaService,
          imageProvider: imageProvider,
          imageLayerBuilder: imageLayerBuilder,
        ),
        if (overlay != null)
          DecoratedBox(decoration: BoxDecoration(gradient: overlay)),
      ],
    );
  }
}
