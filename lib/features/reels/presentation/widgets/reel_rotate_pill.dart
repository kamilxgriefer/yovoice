import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// "Obróć": turns the composer's video a quarter turn clockwise per tap
/// (owner decision B, ADR-235). It sits in the preview's top-end corner, on
/// the problem it fixes, drawn with the media-overlay atoms every control on
/// footage uses: the dense text plate ([overlayPlateColor], 4.5:1 for white
/// text on any frame), a hairline edge, white glyph and shadowed label.
///
/// Geometry: a 36 px stadium plate centred in a ≥ 48×48 target, laid 4 px
/// in from the corner — inside the preview's 24 px rounded clip. Narrow
/// previews and large text drop the label (a 36 px disc in the same 48 px
/// target); the label stays in the tooltip and the semantics either way.
///
/// Every state is drawn on the PLATE, never on the larger target: hover
/// lifts the plate's fill, a press scales it, and keyboard focus draws a
/// two-tone ring (black outside white) hugging it by [focusRingGap] — so
/// there is no second outline 6 px outside the hairline, and the ring stays
/// inside the preview's rounded corner.
class ReelRotatePill extends StatefulWidget {
  const ReelRotatePill({
    required this.previewWidth,
    required this.quarterTurns,
    required this.onTap,
    super.key = const ValueKey<String>('reel-rotate-video'),
  });

  /// The preview's width; the labelled pill shows while it takes at most
  /// [maximumPreviewShare] of it.
  final double previewWidth;

  /// The pending rotation, announced as the control's value.
  final int quarterTurns;

  /// Null disables the pill (publishing, reserved) at 60% glyph alpha.
  final VoidCallback? onTap;

  /// Distance from the preview's top and end edges to the tap target.
  static const double inset = 4;
  static const double plateHeight = 36;
  static const double targetExtent = 48;
  static const double maximumPreviewShare = .6;

  /// How far the focus ring reaches outside the plate.
  static const double focusRingGap = 4;
  static const double _iconSize = 20;
  static const double _gap = 6;
  static const double _paddingStart = 10;
  static const double _paddingEnd = 14;

  static const TextStyle labelStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    shadows: overlayTextShadows,
  );

  @override
  State<ReelRotatePill> createState() => _ReelRotatePillState();
}

class _ReelRotatePillState extends State<ReelRotatePill> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  /// True when the labelled pill fits the preview at the current text scale.
  bool _labelFits(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(
          context,
        ).style.merge(ReelRotatePill.labelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width =
        ReelRotatePill._paddingStart +
        ReelRotatePill._iconSize +
        ReelRotatePill._gap +
        painter.width +
        ReelRotatePill._paddingEnd;
    painter.dispose();
    return width <= widget.previewWidth * ReelRotatePill.maximumPreviewShare;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = copy.contextualText(
      'reels.composer.rotate',
      'Rotate',
      'Obróć',
    );
    final description = copy.text(
      'Rotate video 90° clockwise',
      'Obróć film o 90° w prawo',
    );
    final turns = widget.quarterTurns % 4;
    final value = turns == 0
        ? null
        : copy.template(
            'Rotated {degrees}°',
            'Obrócono o {degrees}°',
            values: <String, Object>{'degrees': turns * 90},
          );
    final enabled = widget.onTap != null;
    final foreground = enabled
        ? Colors.white
        : Colors.white.withValues(alpha: .6);
    final showLabel = _labelFits(context, label);
    final plate = DecoratedBox(
      key: const ValueKey<String>('reel-rotate-video-plate'),
      decoration: BoxDecoration(
        color: _hovered && enabled ? overlayPlateHoverColor : overlayPlateColor,
        borderRadius: BorderRadius.circular(ReelRotatePill.plateHeight / 2),
        border: Border.all(color: overlayGlyphPlateHairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: ReelRotatePill.plateHeight,
          minWidth: ReelRotatePill.plateHeight,
        ),
        child: Padding(
          padding: showLabel
              ? const EdgeInsetsDirectional.only(
                  start: ReelRotatePill._paddingStart,
                  end: ReelRotatePill._paddingEnd,
                )
              : EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.rotate_90_degrees_cw_rounded,
                size: ReelRotatePill._iconSize,
                color: foreground,
                shadows: overlayTextShadows,
              ),
              if (showLabel) ...<Widget>[
                const SizedBox(width: ReelRotatePill._gap),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: ReelRotatePill.labelStyle.copyWith(color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    const plateRadius = ReelRotatePill.plateHeight / 2;
    const gap = ReelRotatePill.focusRingGap;
    final framedPlate = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        plate,
        if (showsFocus)
          Positioned(
            left: -gap,
            top: -gap,
            right: -gap,
            bottom: -gap,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('reel-rotate-video-focus-ring'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(plateRadius + gap),
                  border: Border.all(color: Colors.black, width: gap),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(gap / 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        plateRadius + gap / 2,
                      ),
                      border: Border.all(color: Colors.white, width: gap / 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return OverlayPressScale(
      pressed: _pressed,
      enabled: enabled,
      onPressedChanged: (value) {
        if (_pressed != value) setState(() => _pressed = value);
      },
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: description,
        semanticValue: value,
        tooltip: description,
        // A 24 px radius on the 48 px target IS the circle of the icon-only
        // form, so the region never switches shape (and never tweens a
        // circle into a rounded rectangle) when the label comes or goes.
        borderRadius: ReelRotatePill.targetExtent / 2,
        minimumSize: const Size.square(ReelRotatePill.targetExtent),
        // The plate draws hover, press and focus itself (see above); the
        // region keeps the semantics, tooltip, Enter/Space and the target.
        paintsIndicators: false,
        onHover: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onFocusChange: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: ExcludeSemantics(child: framedPlate),
      ),
    );
  }
}
