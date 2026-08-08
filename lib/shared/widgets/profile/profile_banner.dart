import 'package:flutter/material.dart';

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
  const ProfileBanner({this.bannerUrl, this.overlay, super.key});

  final String? bannerUrl;

  /// Optional gradient painted over the image (e.g. the profile header's
  /// darkening scrim). Painted over the fallback too, so the two states
  /// keep identical depth.
  final Gradient? overlay;

  @override
  Widget build(BuildContext context) {
    final url = bannerUrl?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: kProfileBannerFallbackGradient),
        ),
        if (url != null && url.isNotEmpty)
          Image.network(
            url,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: child,
              );
            },
            // Fall through to the gradient underneath — but never
            // silently (see UserAvatar: a hidden load failure is
            // indistinguishable from "no banner set").
            errorBuilder: (context, error, stackTrace) {
              debugPrint(
                '[IMAGE] banner load failed '
                '${Uri.tryParse(url)?.path}: $error',
              );
              return const SizedBox.shrink();
            },
          ),
        if (overlay != null)
          DecoratedBox(decoration: BoxDecoration(gradient: overlay)),
      ],
    );
  }
}
