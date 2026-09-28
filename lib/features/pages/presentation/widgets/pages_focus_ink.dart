import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// An [InkWell] that draws the app's 2 px `focus` ring (the one
/// `AccessibleTapRegion` and `YoCard` draw) while it holds keyboard focus.
///
/// Pages controls whose semantics are composed by their caller (a merged
/// card header, a labelled action, a photo tile) use it instead of a bare
/// InkWell, whose only focus cue is a 14 % wash that disappears on dark
/// surfaces, or a GestureDetector, which a keyboard never reaches.
class PagesFocusInk extends StatefulWidget {
  const PagesFocusInk({
    required this.onTap,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.circular = false,
    this.focusNode,
    this.excludeFromSemantics = false,
    this.ringInset = 0,
    super.key,
  });

  final VoidCallback? onTap;
  final Widget child;
  final BorderRadius borderRadius;
  final bool circular;
  final FocusNode? focusNode;

  /// True when an enclosing `Semantics` already carries the tap action.
  final bool excludeFromSemantics;

  /// Draws the ring this far inside the edges (artwork that runs to the
  /// card's edge keeps the whole ring visible).
  final double ringInset;

  @override
  State<PagesFocusInk> createState() => _PagesFocusInkState();
}

class _PagesFocusInkState extends State<PagesFocusInk> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return InkWell(
      onTap: widget.onTap,
      focusNode: widget.focusNode,
      borderRadius: widget.circular ? null : widget.borderRadius,
      customBorder: widget.circular ? const CircleBorder() : null,
      excludeFromSemantics: widget.excludeFromSemantics,
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: Stack(
        children: [
          widget.child,
          if (_focused)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(widget.ringInset),
                  child: DecoratedBox(
                    key: const ValueKey('pages-focus-ring'),
                    decoration: BoxDecoration(
                      shape: widget.circular
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: widget.circular
                          ? null
                          : widget.borderRadius,
                      border: Border.all(color: palette.focus, width: 2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Speaks [message] once through the platform's screen reader (the polite
/// channel unless [assertive]). Pages status changes that do not move focus
/// (results arriving, a page failing to load) use it, since a live region
/// alone is silent on iOS and on the web shares one element per frame.
void announcePages(
  BuildContext context,
  String message, {
  bool assertive = false,
}) {
  final text = message.trim();
  if (text.isEmpty || !context.mounted) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    text,
    Directionality.of(context),
    assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
  );
}
