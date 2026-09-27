import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// The one keyboard-focus indicator of a filled labelled action (the R5
/// gradient, and a filled danger action): painted over everything the button
/// draws and outside its clip, so it moves nothing.
///
/// Inner band: [edge] — the fill's own on-colour (`onPrimary`, `onError`,
/// a template's `onCta`) — the 2 px just inside the shape, at least 3:1
/// against the fill. Outer band: [halo] — `palette.focus` — the 2 px just
/// outside it, which [haloFor] asks for on a light canvas (Pearl) and under
/// high contrast, because white alone melts into a light page (1.1:1 on
/// Pearl's `background`) and the button then only seems to shrink.
///
/// The halo is laid first from 1 px inside the edge to 2 px outside, then the
/// inner band over it, so the shape's edge always falls on solid colour and
/// the curved ends never show a seam of the page between the two bands.
///
/// It paints only while [states] holds [WidgetState.focused] and [edge] is
/// set. Keep the `CustomPaint` that carries it in the tree in every state: a
/// wrapper that came and went would remount the button and drop its focus.
class YoActionFocusIndicatorPainter extends CustomPainter {
  YoActionFocusIndicatorPainter({
    required this.states,
    required this.shape,
    required this.edge,
    required this.halo,
    required this.textDirection,
  }) : super(repaint: states);

  /// Each band's width, in logical pixels.
  static const double bandWidth = 2;

  /// The outer band a filled action needs on this canvas: `palette.focus` on
  /// a light canvas or under high contrast, none on Dark (where the white
  /// band alone reads at 18:1 against the page).
  static Color? haloFor(AppPalette palette, {required bool highContrast}) =>
      palette.isDark && !highContrast ? null : palette.focus;

  /// The button's own states. The button reports focus through this
  /// controller, sometimes while it is being built; listening here only
  /// repaints, which is safe at any point in the frame.
  final WidgetStatesController states;
  final OutlinedBorder shape;
  final Color? edge;
  final Color? halo;
  final TextDirection? textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = this.edge;
    if (edge == null || !states.value.contains(WidgetState.focused)) return;
    final rect = Offset.zero & size;
    final halo = this.halo;
    if (halo != null) {
      // One stroke spanning [-1, +band] around the shape's edge (for a
      // 2 px band: 3 px wide at strokeAlign 1/3); the inner band then covers
      // its inner pixel.
      const width = bandWidth + 1;
      shape
          .copyWith(
            side: BorderSide(
              color: halo,
              width: width,
              strokeAlign: (bandWidth - 1) / width,
            ),
          )
          .paint(canvas, rect, textDirection: textDirection);
    }
    shape
        .copyWith(
          side: BorderSide(color: edge, width: bandWidth),
        )
        .paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool shouldRepaint(YoActionFocusIndicatorPainter old) =>
      old.states != states ||
      old.shape != shape ||
      old.edge != edge ||
      old.halo != halo ||
      old.textDirection != textDirection;
}
