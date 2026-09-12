import 'package:flutter/material.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/space_identity.dart';

import '../../data/models/server_type.dart';

/// Server identity seeds reuse the established Room/Family palette without
/// changing room experiences, role badges, status colours or the global logo.
///
/// Each template carries the reference's colour pair: [primary] is the deep
/// `--rgb` hue that tints the card wash, the decorative orbit and the symbol
/// tile; [accent] is the bright `--a` hue that paints the icon and the link.
/// [action] is the filled-button colour, which the reference does not define
/// for the selector; it defaults to the rule below and is overridden only
/// where a bright accent would not carry readable button text.
@immutable
class ServerIdentity {
  const ServerIdentity(this.type, this.primary, this.accent, {Color? action})
    : _action = action;

  final ServerType type;
  final Color primary;
  final Color accent;
  final Color? _action;

  static final _identities = <ServerType, ServerIdentity>{
    ServerType.friends: const ServerIdentity(
      ServerType.friends,
      AppColors.accent,
      AppColors.accent,
    ),
    // The reference pair is `--a:#c026ff; --rgb:192,38,255` — the same
    // magenta for tint and ink, not the shared community room's blueviolet
    // `primary`. That deep violet stays the filled action: white text on it
    // reads at 6:1, on the bright magenta it would not.
    ServerType.community: ServerIdentity(
      ServerType.community,
      AppColors.secondary,
      AppColors.secondary,
      action: SpaceIdentity.community.primary,
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
    final cardWash = primary.withValues(alpha: dark ? .085 : .045);
    final selectedWash = primary.withValues(alpha: dark ? .16 : .08);
    final selectedSurface = Color.alphaBlend(
      selectedWash,
      palette.surfaceMuted,
    );
    // The brighter reference fills need ink, the purple action needs white.
    final cta = dark ? (_action ?? accent) : scheme.primary;
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
      // The card's link is 13 px text, so it needs 4.5:1 everywhere on the
      // card — including the tinted top and the stronger hover wash, where
      // the reference's own magenta drops to 4.3:1. Every other template's
      // accent already clears 7:1 and comes back unchanged.
      linkForeground: _readableForeground(
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
      cardWash: cardWash,
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
    required this.linkForeground,
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

  /// The selector card's `Wybierz` row: the accent, lifted toward the theme
  /// ink only where the accent itself would not reach 4.5:1 on the card.
  final Color linkForeground;
  final Color cta;
  final Color onCta;
  final Color iconSurface;
  final Color iconBorder;
  final Color cardWash;
  final Color selectedWash;
  final Color orbit;
  final Color focus;
}

/// The keyboard focus ring for a control whose fill this slice overrides.
///
/// `docs/UI.md` (*Semantic colour ownership*) guarantees 3:1 for a filled
/// control's focus boundary by painting it in the control's own `onPrimary` /
/// `onError` foreground. That guarantee only holds while the fill IS the
/// Material primary or error: every identity-filled control here replaces the
/// fill and, with `side` unset, inherits a theme ring that was measured
/// against a different colour (1.24:1 on the leave control, 1.57–2.74:1 on
/// four of the five templates' primary actions). Handing the control its own
/// on-colour restores the written rule, and returns `null` off focus so
/// nothing is painted in any other state.
WidgetStateProperty<BorderSide?> serverFocusRing(Color foreground) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: foreground, width: 2)
          : null,
    );

/// The selector is an explicitly approved responsive exception to page rhythm.
abstract final class ServerSelectorMetrics {
  static const compactBreakpoint = 640.0;
  static const wideBreakpoint = 1150.0;
  static const maxWidth = 1540.0;
  static const compactRadius = 22.0;
  static const cardRadius = 26.0;
  static const touchTarget = 48.0;

  /// `main{padding:45px 48px 48px}` and `@media(max-width:640){main{padding:25px 20px}}`.
  static const sidePadding = 48.0;
  static const compactSidePadding = 20.0;

  /// `.cards{gap:16px}` between columns; `.cards{gap:11px}` between the
  /// stacked compact rows.
  static const columnGap = 16.0;
  static const compactRowGap = 11.0;

  /// `.lead{max-width:620px}` and `@media(max-width:640){h1{max-width:350px}}`.
  ///
  /// At today's Polish string lengths both fit their reference line count
  /// without a measure; the measure exists for the long case — a German or
  /// Arabic lead must not run the whole content width as one centred line.
  static const leadMeasure = 620.0;
  static const compactHeadingMeasure = 350.0;

  /// `linear-gradient(170deg, rgba(--rgb,.085), transparent 75%)`: the tint
  /// is gone by three-quarters of the card and the link row sits on the flat
  /// card fill. Hover stretches the fade to 90 %.
  static const washFadeStop = .75;
  static const hoverWashFadeStop = .9;

  /// The reference's `outline: 3px solid #F8F5FC`.
  ///
  /// It is painted as a foreground ring rather than a wider border: the cards
  /// live in equal `Expanded` slots separated by a 16 px gap, so the CSS
  /// `outline-offset: 6px` has nowhere to go without overlapping the next
  /// card, and growing the *border* on focus would shift the card's own copy
  /// by two pixels every time focus arrives. A foreground ring keeps the
  /// content perfectly still, which is what the outline does in the browser.
  static const focusRingWidth = 3.0;
}

/// The configuration step's three arrangements.
///
/// Below [wideBreakpoint] the form is one column with the seeded-channel
/// preview under the fields (narrow keeps the compact rhythm it already had).
/// From 1100 up the form sits beside the preview: the preview is what people
/// re-read while they type, so on a desktop it stays permanently visible in
/// its own scrolling column instead of being scrolled past.
abstract final class ServerConfigurationMetrics {
  static const wideBreakpoint = 1100.0;
  static const formColumnWidth = 560.0;
  static const asideWidth = 420.0;
  static const gutter = 32.0;
}

/// The selector's feature list, one step brighter than body copy.
///
/// The approved dark reference puts `#D4CBDC` on the `#100D18` card while the
/// description above it stays `#B8AFC2`; that half-step is what separates the
/// two levels of copy. Pearl keeps its own secondary ink, where a near-white
/// lilac would have almost no contrast against a light card.
Color serverSelectorFeatureInk(Brightness brightness, AppPalette palette) =>
    brightness == Brightness.dark
    ? const Color(0xFFD4CBDC)
    : palette.textSecondary;
