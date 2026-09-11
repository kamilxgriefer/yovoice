import 'package:flutter/material.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/space_identity.dart';

import '../../data/models/server_type.dart';

/// Server identity seeds reuse the established Room/Family palette without
/// changing room experiences, role badges, status colours or the global logo.
@immutable
class ServerIdentity {
  const ServerIdentity(this.type, this.primary, this.accent);

  final ServerType type;
  final Color primary;
  final Color accent;

  static final _identities = <ServerType, ServerIdentity>{
    ServerType.friends: const ServerIdentity(
      ServerType.friends,
      AppColors.accent,
      AppColors.accent,
    ),
    ServerType.community: ServerIdentity(
      ServerType.community,
      SpaceIdentity.community.primary,
      SpaceIdentity.community.accent,
    ),
    ServerType.podcast: ServerIdentity(
      ServerType.podcast,
      SpaceIdentity.podcast.primary,
      SpaceIdentity.podcast.accent,
    ),
    ServerType.family: ServerIdentity(
      ServerType.family,
      SpaceIdentity.family.primary,
      SpaceIdentity.family.accent,
    ),
    ServerType.company: const ServerIdentity(
      ServerType.company,
      AppColors.info,
      Color(0xFF63C7FF),
    ),
  };

  static ServerIdentity of(ServerType type) => _identities[type]!;

  ServerIdentityVisuals resolve(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );
    final palette = dark ? AppPalette.dark : AppPalette.light;
    final foreground = dark ? accent : scheme.primary;
    final selectedWash = primary.withValues(alpha: dark ? .16 : .08);
    final selectedSurface = Color.alphaBlend(
      selectedWash,
      palette.surfaceMuted,
    );
    // The brighter reference fills need ink, the purple action needs white.
    final cta = dark
        ? (type == ServerType.community ? primary : accent)
        : scheme.primary;
    final onCta = cta.computeLuminance() > .32
        ? AppColors.contrastInk
        : AppColors.white;
    return ServerIdentityVisuals(
      foreground: foreground,
      selectedForeground: _readableForeground(
        foreground,
        selectedSurface,
        palette.textPrimary,
      ),
      cta: cta,
      onCta: onCta,
      iconSurface: dark
          ? primary.withValues(alpha: .12)
          : scheme.primaryContainer,
      iconBorder: dark ? primary.withValues(alpha: .25) : scheme.primary,
      cardWash: primary.withValues(alpha: dark ? .085 : .045),
      selectedWash: selectedWash,
      orbit: primary.withValues(alpha: dark ? .09 : .12),
      focus: palette.textPrimary,
    );
  }

  // A selected channel's translucent wash changes the actual text/background
  // pair. Preserve the identity hue, adjusting only this semantic foreground
  // toward the readable theme ink when the composite needs more contrast.
  static Color _readableForeground(Color preferred, Color surface, Color ink) {
    final surfaceLuminance = surface.computeLuminance();
    for (var step = 0; step <= 20; step++) {
      final candidate = Color.lerp(preferred, ink, step / 20)!;
      final luminance = candidate.computeLuminance();
      final contrast = luminance > surfaceLuminance
          ? (luminance + .05) / (surfaceLuminance + .05)
          : (surfaceLuminance + .05) / (luminance + .05);
      if (contrast >= 4.5) return candidate;
    }
    return ink;
  }
}

@immutable
class ServerIdentityVisuals {
  const ServerIdentityVisuals({
    required this.foreground,
    required this.selectedForeground,
    required this.cta,
    required this.onCta,
    required this.iconSurface,
    required this.iconBorder,
    required this.cardWash,
    required this.selectedWash,
    required this.orbit,
    required this.focus,
  });
  final Color foreground;
  final Color selectedForeground;
  final Color cta;
  final Color onCta;
  final Color iconSurface;
  final Color iconBorder;
  final Color cardWash;
  final Color selectedWash;
  final Color orbit;
  final Color focus;
}

/// The selector is an explicitly approved responsive exception to page rhythm.
abstract final class ServerSelectorMetrics {
  static const compactBreakpoint = 640.0;
  static const wideBreakpoint = 1150.0;
  static const maxWidth = 1540.0;
  static const compactRadius = 22.0;
  static const cardRadius = 26.0;
  static const touchTarget = 48.0;
}
