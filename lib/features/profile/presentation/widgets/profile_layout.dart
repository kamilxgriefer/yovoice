import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// The profile's shared measures (refine-look §8.5), used by the own profile,
/// its header and a friend's profile so the three never drift apart.
///
/// Every threshold here reads the width the content is actually given —
/// never a device label — so a tablet in a split view and a narrow desktop
/// window resolve exactly like the phone or desktop they resemble.
abstract final class ProfileLayout {
  /// The readable measure of the profile's header cluster (stats and
  /// actions) and, on wide canvases, of every body section below it.
  static const double wideMeasure = 640;

  /// From this content width a profile's body sections take [wideMeasure],
  /// start-aligned under the header cluster; below it (phones) they use the
  /// whole column.
  ///
  /// One rule for the own profile and a friend's (spec §11: the two are
  /// identical). §8.5 names 900 for the own profile, but its header cluster
  /// is capped at [wideMeasure] at every width, so between 700 and 900 (a
  /// portrait tablet) a 900 threshold left the stats and actions, the vibe
  /// sticker and the blocks on three different right edges. A friend's
  /// profile sits on the narrower 880 pt list measure and never reaches 900
  /// at all. 700 is also the width at which the friend's profile switches to
  /// its wide layout (Follow beside the name, the quick-action toolbar) and
  /// the vibe sticker stops growing ([vibeCapFromWidth]), so every cap on the
  /// page engages together. Flagged for design sign-off with the §12.5
  /// wide-measure decision.
  static const double wideFromWidth = 700;

  /// The journey card shows its four counters side by side from this card
  /// width (below it, and at large text, it keeps one row per counter).
  static const double journeyCellsFromWidth = 560;

  /// The vibe sticker stops growing with the column from this width.
  static const double vibeCapFromWidth = 700;

  /// The widest the vibe sticker grows on a wide column.
  static const double vibeMaxWidth = 560;

  /// Body text at or above this scaled size (about 150 % of 14 pt) switches
  /// every side-by-side profile arrangement to its stacked form.
  static const double largeTextBody = 21;

  /// Whether the reader's text is large enough to stack side-by-side
  /// arrangements (the same rule as the stats row and the action bar).
  static bool largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) >= largeTextBody;

  /// The profile canvas (refine-look R1): the one `canvasGlow` radial every
  /// profile state paints — populated, loading and error alike — so a retry
  /// or a load never changes the page's atmosphere. Null (the flat canvas)
  /// under high contrast.
  static Decoration? canvas(BuildContext context) =>
      MediaQuery.highContrastOf(context)
      ? null
      : BoxDecoration(
          gradient: context.appPalette.canvasGlow(
            Theme.of(context).colorScheme.primary,
          ),
        );

  /// The width a body section takes inside a column of [available] width.
  static double bodyWidth(double available, {double from = wideFromWidth}) =>
      available >= from && available > wideMeasure ? wideMeasure : available;
}

/// A profile section on the profile's reading measure: the whole column
/// below [from], [ProfileLayout.wideMeasure] start-aligned from it. Body
/// blocks, the friend profile's hero row (so Follow ends on the blocks' right
/// edge) and its footer actions all use it, so a page never has two right
/// edges.
class ProfileMeasure extends StatelessWidget {
  const ProfileMeasure({
    required this.child,
    this.from = ProfileLayout.wideFromWidth,
    super.key,
  });

  final Widget child;

  /// The column width from which the section is capped.
  final double from;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final width = ProfileLayout.bodyWidth(available, from: from);
        if (width >= available) return child;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}

/// A 2 px keyboard-focus ring painted as a FOREGROUND over [child] while
/// [child] (or anything inside it) holds focus: no layout change, and it
/// lands above whatever the child paints.
///
/// Two profile controls need it:
///
/// * the gradient CTAs ("Edytuj profil", a friend's "Zadzwoń"). Their fill
///   is an `Ink` gradient laid through `backgroundBuilder`, and ink paints
///   above the button Material's own shape border, so the 2 px `onPrimary`
///   focus edge their styles resolve (R5) never reaches the screen. This
///   draws that same edge on top, inside the button's shape
///   ([inset] zero, [color] `onPrimary`, the button's [borderRadius]);
/// * the account rows, which get R16's 2 px `palette.focus` ring at radius
///   16, inset so it sits concentric inside the block's radius-20 clip.
///
/// It only listens (its own node never takes focus or a traversal stop and
/// adds no semantics), so keys, focus order and every button's own states
/// are unchanged.
class ProfileFocusRing extends StatefulWidget {
  const ProfileFocusRing({
    required this.child,
    required this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.inset = EdgeInsets.zero,
    this.width = 2,
    super.key,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;

  /// How far inside the child's box the ring's outer edge sits.
  final EdgeInsets inset;
  final double width;

  @override
  State<ProfileFocusRing> createState() => _ProfileFocusRingState();
}

class _ProfileFocusRingState extends State<ProfileFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (mounted && focused != _focused) {
          setState(() => _focused = focused);
        }
      },
      child: CustomPaint(
        foregroundPainter: _FocusRingPainter(
          visible: _focused,
          color: widget.color,
          borderRadius: widget.borderRadius,
          inset: widget.inset,
          width: widget.width,
        ),
        child: widget.child,
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.visible,
    required this.color,
    required this.borderRadius,
    required this.inset,
    required this.width,
  });

  final bool visible;
  final Color color;
  final BorderRadius borderRadius;
  final EdgeInsets inset;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    // The stroke is centred on its path: deflate by half of it so the whole
    // ring lies inside the inset box.
    final box = inset.deflateRect(Offset.zero & size).deflate(width / 2);
    if (box.isEmpty) return;
    final radius = borderRadius;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        box,
        topLeft: _shrink(radius.topLeft),
        topRight: _shrink(radius.topRight),
        bottomLeft: _shrink(radius.bottomLeft),
        bottomRight: _shrink(radius.bottomRight),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  Radius _shrink(Radius radius) => Radius.elliptical(
    (radius.x - width / 2).clamp(0, double.infinity),
    (radius.y - width / 2).clamp(0, double.infinity),
  );

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.visible != visible ||
      old.color != color ||
      old.borderRadius != borderRadius ||
      old.inset != inset ||
      old.width != width;
}
