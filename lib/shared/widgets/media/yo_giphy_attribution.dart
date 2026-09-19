import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// GIPHY's "Powered By GIPHY" attribution mark (ADR-210).
///
/// GIPHY's terms require its official mark wherever GIPHY search or browse
/// results appear. This widget renders the OFFICIAL artwork from the app
/// bundle, in the variant made for the current background:
///
///  * [onLightAsset] — the dark-ink mark, for light themes;
///  * [onDarkAsset] — the light-ink mark, for dark themes.
///
/// The artwork is GIPHY's and is not drawn, recoloured or approximated here.
/// Until the official files are placed at those two paths (they are listed in
/// docs/DEPLOYMENT.md as a release prerequisite), the widget falls back to the
/// attribution wording as plain text, so the attribution is never missing
/// while the image is.
class YoGiphyAttribution extends StatelessWidget {
  const YoGiphyAttribution({super.key, this.height = 16});

  /// Official "Powered By GIPHY" artwork for LIGHT backgrounds.
  static const onLightAsset = 'assets/images/giphy_powered_by_on_light.png';

  /// Official "Powered By GIPHY" artwork for DARK backgrounds.
  static const onDarkAsset = 'assets/images/giphy_powered_by_on_dark.png';

  /// Logical height of the mark. The width follows the artwork's own ratio,
  /// and the mark is never clipped or scaled below this height.
  final double height;

  /// GIPHY's own attribution wording, shown verbatim (never translated) as
  /// the visible fallback while the artwork is absent. The localized form is
  /// the accessibility label only.
  static const markWording = 'Powered By GIPHY';

  static String assetFor(Brightness brightness) =>
      brightness == Brightness.dark ? onDarkAsset : onLightAsset;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = copy.text('Powered by GIPHY', 'Dostarczane przez GIPHY');
    final fallback = Text(
      markWording,
      key: const ValueKey('giphy-attribution-text'),
      maxLines: 2,
      softWrap: true,
      style: TextStyle(
        color: palette.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
    return Semantics(
      key: const ValueKey('giphy-attribution'),
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          assetFor(Theme.of(context).brightness),
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}
