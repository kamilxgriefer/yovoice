import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The floating room control dock: a centered, rounded, translucent pill
/// over the dark page — never a full-width bar. Every room family renders
/// its controls through this one surface; only the BUTTON LIST differs by
/// room and role, and each screen keeps its own behavior wiring.
class RoomControlDock extends StatelessWidget {
  const RoomControlDock({required this.children, super.key});

  /// [RoomDockButton]s and [RoomDockDivider]s, in order. Destructive
  /// actions go last, after a divider — visually separated on purpose.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0612).withValues(alpha: .74),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .09),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final child in children)
                        child is RoomDockDivider
                            ? child
                            : Flexible(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual weight of one dock control. The identity accent is passed in by
/// the screen, so the same dock is violet in a community room, emerald in
/// a family lounge, gold in a club and coral in a podcast.
enum RoomDockStyle {
  /// The active/primary control (a live mic, Start voice).
  accent,

  /// A muted mic — bright amber, obviously tappable, never disabled-grey.
  warning,

  /// Ordinary tools (Chat, People, Share) and informative states.
  neutral,

  /// Broken audio ("Audio off") — dark maroon: wrong, but not an action.
  alert,

  /// Destructive (Leave, End). Always red.
  danger,
}

class RoomDockButton extends StatelessWidget {
  const RoomDockButton({
    required this.icon,
    required this.label,
    required this.style,
    required this.accentColor,
    this.onTap,
    this.enabled = true,
    this.showSpinner = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final RoomDockStyle style;

  /// The room identity's primary color — drives the accent style and glow.
  final Color accentColor;

  /// Null genuinely disables the control (a screen mid-teardown). A
  /// control that CANNOT act right now but can explain itself keeps a
  /// non-null handler — a tap must answer, never die silently.
  final VoidCallback? onTap;

  /// Visual-only: a briefly busy control dims but stays near-opaque, so
  /// it never reads as permanently dead.
  final bool enabled;
  final bool showSpinner;

  /// White on the emerald and gold accents measures 2.0-2.25:1 — a
  /// non-text contrast failure on the room's PRIMARY control. The glyph
  /// therefore follows the fill's brightness: near-black on a light accent,
  /// white on a dark one. `estimateBrightnessForColor` is the same estimate
  /// Material uses for foregrounds, so this cannot drift per-identity.
  static Color _foregroundFor(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.light
      ? const Color(0xFF120C1B)
      : Colors.white;

  static const _dangerRed = Color(0xFFE93A57);
  static const _mutedAmber = Color(0xFFB3801A);

  @override
  Widget build(BuildContext context) {
    final (
      Color fill,
      Color? borderColor,
      List<BoxShadow>? glow,
    ) = switch (style) {
      RoomDockStyle.accent => (
        accentColor,
        null,
        [
          BoxShadow(
            color: accentColor.withValues(alpha: .5),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      RoomDockStyle.warning => (_mutedAmber, null, null),
      RoomDockStyle.neutral => (
        Colors.white.withValues(alpha: .08),
        Colors.white.withValues(alpha: .1),
        null,
      ),
      RoomDockStyle.alert => (const Color(0xFF7A2436), null, null),
      RoomDockStyle.danger => (_dangerRed, null, null),
    };

    return Semantics(
      button: true,
      enabled: onTap != null && enabled,
      label: label,
      child: Opacity(
        opacity: onTap == null
            ? .45
            : enabled
            ? 1
            : .75,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // FittedBox keeps the control CIRCULAR when a narrow viewport
                // squeezes the dock — a scaled-down circle, never an oval.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: borderColor == null
                          ? null
                          : Border.all(color: borderColor),
                      boxShadow: glow,
                    ),
                    child: showSpinner
                        ? const Padding(
                            padding: EdgeInsets.all(15),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white70,
                            ),
                          )
                        : Icon(icon, color: _foregroundFor(fill), size: 23),
                  ),
                ),
                const SizedBox(height: 6),
                // Two lines and a capped caption scale, or 200% text
                // truncated the labels to "Sta…"/"Lea…" for exactly the users
                // who enlarged them. The cap applies ONLY to this caption:
                // the dock's width is bounded, the icon carries the meaning,
                // and the FULL label always reaches assistive tech through
                // the Semantics wrapper below — nothing is lost, it is just
                // not rendered at a size the pill cannot hold.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.6,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The thin separator that keeps destructive actions visually apart.
class RoomDockDivider extends StatelessWidget {
  const RoomDockDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: .1),
    );
  }
}
