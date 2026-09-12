import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

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
const Color overlayPlateColor = Color(0xB8000000);
const Color overlayPlateHoverColor = Color(0xD6000000);

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
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color glyphColor;

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
        onHover: (value) => setState(() => _hovered = value),
        child: OverlayPlate(
          icon: widget.icon,
          color: widget.onTap == null
              ? widget.glyphColor.withValues(alpha: .6)
              : widget.glyphColor,
          hovered: _hovered && widget.onTap != null,
        ),
      ),
    );
  }
}

/// The 48 px disc itself.
///
/// Public only because the rail and the plate button live in different files
/// now that two features share them; it was private while Reels was the only
/// caller and its behaviour is unchanged.
class OverlayPlate extends StatelessWidget {
  const OverlayPlate({
    required this.icon,
    required this.color,
    required this.hovered,
    this.ring,
    super.key,
  });

  final IconData icon;
  final Color color;
  final bool hovered;

  /// Drawn on the plate rather than around the whole control: a rail item is
  /// a circle with a number under it, and a ring that enclosed both would run
  /// straight through the number.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ringColor = ring;
    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.quick),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: hovered ? overlayPlateHoverColor : overlayPlateColor,
        shape: BoxShape.circle,
        border: ringColor == null || ringColor.a == 0
            ? null
            : Border.all(color: ringColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 24, color: color),
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
