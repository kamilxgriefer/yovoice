import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

/// The paint atoms every control laid directly on media is made of.
///
/// These were born inside Reels. They are shared the moment a second feed
/// puts controls over content of unknown luminance, which is what the
/// immersive Voice/Reels chrome does: one plate, one shadow stack, one
/// compact-count rule, so the two formats of one destination cannot drift
/// into two overlay vocabularies.
///
/// Black literals, not palette tokens, and deliberately so: the plate must
/// read the same over any frame in BOTH appearances, and a white glyph on it
/// clears 3:1 even on a pure-white frame. This is the media-overlay case the
/// semantic-colour guard documents as legitimately dark in both themes.
///
/// This denser pair backs white TEXT on media (the overlay metric pill, the
/// media send review, the Yeel sound pill): small text needs 4.5:1, and on a
/// pure-white frame 0xB8 keeps white text at about 7.9:1.
const Color overlayPlateColor = Color(0xB8000000);
const Color overlayPlateHoverColor = Color(0xD6000000);

/// The 48 px glyph plate ([OverlayPlate]) since the refine-look finish
/// (spec §8.4, Yeels): a lighter smoked disc, so the rail stops reading as
/// a column of black holes over bright footage. A white glyph on it still
/// holds about 4.7:1 on a pure-white frame — above the 3:1 a glyph needs —
/// and the hover plate darkens toward the old value.
const Color overlayGlyphPlateColor = Color(0x8C000000);
const Color overlayGlyphPlateHoverColor = Color(0xB3000000);

/// The plate's 1 px edge when it carries no ring: a white hairline that
/// separates the disc from dark footage, where a translucent black plate
/// alone would dissolve into the frame.
const Color overlayGlyphPlateHairline = Color(0x24FFFFFF);

/// Shadows behind every piece of white text laid directly on media.
const List<Shadow> overlayTextShadows = <Shadow>[
  Shadow(color: Color(0x8C000000), blurRadius: 8),
  Shadow(color: Color(0x59000000), blurRadius: 2),
];

/// 2400 -> "2.4K".
///
/// Shared by every overlay rail. The exact number always remains available in
/// the semantic label, so the compact form is an affordance and never a fact.
String compactCount(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  final text = thousands >= 10
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}K';
}

/// One 48 px overlay plate with a white glyph: the atom every control on a
/// media frame is made of, so report/delete look exactly like like/comment.
class OverlayPlateButton extends StatefulWidget {
  const OverlayPlateButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.tooltip,
    this.glyphColor = Colors.white,
    this.focusNode,
    this.plateColor,
    this.hoverPlateColor,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color glyphColor;
  final FocusNode? focusNode;

  /// The disc's fill. Null keeps the media plate: the smoked
  /// [overlayGlyphPlateColor] with its [overlayGlyphPlateHairline] edge, or
  /// the denser [overlayPlateColor] under high contrast (see
  /// [OverlayPlate]). A host that lays the same control on the page CANVAS
  /// (the Voice feed) passes palette roles instead, so Pearl never gets a
  /// black disc; a plate with a host fill draws no media hairline.
  final Color? plateColor;

  /// The disc's hovered fill; null keeps [overlayGlyphPlateHoverColor]
  /// ([overlayPlateHoverColor] under high contrast).
  final Color? hoverPlateColor;

  @override
  State<OverlayPlateButton> createState() => _OverlayPlateButtonState();
}

class _OverlayPlateButtonState extends State<OverlayPlateButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return OverlayPressScale(
      pressed: _pressed,
      enabled: widget.onTap != null,
      onPressedChanged: (value) => setState(() => _pressed = value),
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.tooltip ?? widget.semanticLabel,
        borderRadius: 24,
        minimumSize: const Size(48, 48),
        focusContrastColor: Colors.black,
        focusNode: widget.focusNode,
        onHover: (value) => setState(() => _hovered = value),
        child: OverlayPlate(
          icon: widget.icon,
          color: widget.onTap == null
              ? widget.glyphColor.withValues(alpha: .6)
              : widget.glyphColor,
          hovered: _hovered && widget.onTap != null,
          fill: widget.plateColor,
          hoverFill: widget.hoverPlateColor,
        ),
      ),
    );
  }
}

/// The 48 px disc itself.
///
/// Public only because the rail and the plate button live in different files
/// now that two features share them; it was private while Reels was the only
/// caller.
///
/// Over media it is the smoked [overlayGlyphPlateColor] plate with an
/// [overlayGlyphPlateHairline] edge whenever no [ring] is drawn (under high
/// contrast the denser [overlayPlateColor]); a canvas host that passes its
/// own [fill] gets neither (a white hairline on a Pearl canvas would be
/// noise, and the host owns its colours).
class OverlayPlate extends StatelessWidget {
  const OverlayPlate({
    required this.icon,
    required this.color,
    required this.hovered,
    this.ring,
    this.fill,
    this.hoverFill,
    super.key,
  });

  final IconData icon;
  final Color color;
  final bool hovered;

  /// Optional fills for a canvas host; null keeps the media plate colours.
  final Color? fill;
  final Color? hoverFill;

  /// Drawn on the plate rather than around the whole control: a rail item is
  /// a circle with a number under it, and a ring that enclosed both would run
  /// straight through the number.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ringColor = ring;
    final hasRing = ringColor != null && ringColor.a > 0;
    final onMedia = fill == null;
    // High contrast keeps the denser plate: more ink between the glyph and
    // an unknown frame, instead of the lighter finish.
    final highContrast = MediaQuery.highContrastOf(context);
    final mediaFill = highContrast ? overlayPlateColor : overlayGlyphPlateColor;
    final mediaHoverFill = highContrast
        ? overlayPlateHoverColor
        : overlayGlyphPlateHoverColor;
    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.quick),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: hovered ? hoverFill ?? mediaHoverFill : fill ?? mediaFill,
        shape: BoxShape.circle,
        border: hasRing
            ? Border.all(color: ringColor, width: 2)
            : onMedia
            ? Border.all(color: overlayGlyphPlateHairline)
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 24, color: color),
    );
  }
}

/// The icon-only brand CTA on a feed's chrome — the create `+` — as the
/// refine-look R6 disc at 48 (`YoGradientDisc(emphasis: lift)`): the logo's
/// gradient with a white glyph and the screen's one coloured lift.
///
/// The same control over footage and on the page canvas (spec §8.4): only
/// the light differs. Over media ([onMedia]) the disc is drawn in the
/// immersive Dark palette in both appearances, so its lift reads the same on
/// any frame; on the canvas it follows the app theme (Pearl's lift is the
/// softer plum-violet). High contrast keeps the gradient and drops the lift.
///
/// Tap, semantics, tooltip and focus stay on the [AccessibleTapRegion]
/// every overlay control uses (48 px target, a black companion edge on the
/// focus ring for media of any luminance); the disc itself is draw-only.
class OverlayBrandDiscButton extends StatefulWidget {
  const OverlayBrandDiscButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.tooltip,
    this.onMedia = true,
    this.focusNode,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;

  /// True over footage; false on the page canvas.
  final bool onMedia;
  final FocusNode? focusNode;

  /// The disc's diameter (R6 "+" on the canvas and over media).
  static const double size = 48;

  @override
  State<OverlayBrandDiscButton> createState() => _OverlayBrandDiscButtonState();
}

class _OverlayBrandDiscButtonState extends State<OverlayBrandDiscButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget disc = YoGradientDisc(
      size: OverlayBrandDiscButton.size,
      icon: widget.icon,
      emphasis: enabled ? YoDiscEmphasis.lift : YoDiscEmphasis.rest,
      status: enabled ? YoDiscStatus.idle : YoDiscStatus.disabled,
      hovered: _hovered && enabled,
    );
    if (widget.onMedia) {
      // Only the disc reads the palette: give it the immersive one, so the
      // lift over footage does not change with the app's appearance.
      disc = Theme(
        data: Theme.of(context).copyWith(
          extensions: const <ThemeExtension<dynamic>>[AppPalette.dark],
        ),
        child: disc,
      );
    }
    return YoPressFeedback(
      scale: YoPressFeedback.disc,
      enabled: enabled,
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.tooltip ?? widget.semanticLabel,
        circular: true,
        minimumSize: const Size.square(OverlayBrandDiscButton.size),
        focusContrastColor: Colors.black,
        focusNode: widget.focusNode,
        onHover: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        child: disc,
      ),
    );
  }
}

/// Pressed feedback without a second gesture arena: a raw pointer listener
/// shrinks the control to .94 and lets the tap region keep the tap.
class OverlayPressScale extends StatelessWidget {
  const OverlayPressScale({
    required this.pressed,
    required this.enabled,
    required this.onPressedChanged,
    required this.child,
    super.key,
  });

  final bool pressed;
  final bool enabled;
  final ValueChanged<bool> onPressedChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (_) => onPressedChanged(true) : null,
      onPointerUp: (_) => onPressedChanged(false),
      onPointerCancel: (_) => onPressedChanged(false),
      child: AnimatedScale(
        scale: pressed && enabled ? .94 : 1,
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        child: child,
      ),
    );
  }
}
