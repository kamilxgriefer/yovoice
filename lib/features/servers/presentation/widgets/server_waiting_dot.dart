import 'package:flutter/material.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// The small "somebody is waiting for you" dot.
///
/// One shared mark for every entry that leads to a queue a host or moderator
/// has to answer — the raised hands of a stage today, listener questions next —
/// so the product has one visual word for "waiting", in Dark and Pearl alike.
/// It is drawn only from a real, readable queue that is not empty; it never
/// stands in for a count nobody wrote.
///
/// The dot is decoration for sighted people and a sentence for everybody else:
/// [semanticLabel] carries the count ("3 waiting to speak"), so it is never
/// conveyed by colour alone. Use [ServerWaitingDot.on] to pin it to the corner
/// of an icon or an avatar.
class ServerWaitingDot extends StatelessWidget {
  const ServerWaitingDot({
    required this.semanticLabel,
    this.size = defaultSize,
    super.key,
  });

  /// Wraps [child] and pins a dot to its top end corner while [waiting] is
  /// true. With [waiting] false the child is returned unchanged, so a caller
  /// never has to build two trees.
  static Widget on({
    required Widget child,
    required bool waiting,
    required String semanticLabel,
    Key? dotKey,
    double size = defaultSize,
  }) {
    if (!waiting) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: -size / 4,
          end: -size / 4,
          child: ServerWaitingDot(
            key: dotKey,
            semanticLabel: semanticLabel,
            size: size,
          ),
        ),
      ],
    );
  }

  /// Large enough to read at arm's length on a phone, small enough to sit on
  /// the corner of a 22 px glyph without covering it.
  static const double defaultSize = 10;

  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.warningForeground,
            // A ring in the surface colour keeps the dot legible on a
            // selected row, a filled control or an avatar alike.
            border: Border.all(color: palette.surface, width: 1.5),
          ),
        ),
      ),
    );
  }
}
