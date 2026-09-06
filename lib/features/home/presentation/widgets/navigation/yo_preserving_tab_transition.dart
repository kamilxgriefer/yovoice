import 'package:flutter/material.dart';

/// A paint-only fade-through over one retained set of tab pages.
///
/// Every child stays mounted under a stable key. Hidden pages are Offstage and
/// have tickers disabled, while the selected page and (briefly) the outgoing
/// page share the viewport. This preserves scroll/form/listener state without
/// rebuilding pages on each animation frame.
///
/// Timing follows Material's fade-through: the outgoing page fades out
/// completely during the first part of the run, and only then does the
/// incoming page fade in with a slight scale-up. The two are never both
/// translucent over each other and the incoming page is never offset, so no
/// strip or ghost of the previous tab can show through while the new tab is
/// already selected (the "torn screen" reported on Home). [direction] is kept
/// for callers and tests; it no longer drives a horizontal slide.
class YoPreservingTabTransition extends StatelessWidget {
  const YoPreservingTabTransition({
    required this.selectedIndex,
    required this.previousIndex,
    required this.direction,
    required this.animation,
    required this.children,
    super.key,
  });

  final int selectedIndex;
  final int previousIndex;
  final int direction;
  final Animation<double> animation;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    assert(selectedIndex >= 0 && selectedIndex < children.length);
    assert(previousIndex >= 0 && previousIndex < children.length);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final order = <int>[
      for (var index = 0; index < children.length; index++)
        if (index != selectedIndex && index != previousIndex) index,
      if (previousIndex != selectedIndex) previousIndex,
      selectedIndex,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final index in order)
          KeyedSubtree(
            key: ValueKey('yo-tab-layer-$index'),
            child: AnimatedBuilder(
              animation: animation,
              child: children[index],
              builder: (context, child) {
                final raw = reduceMotion ? 1.0 : animation.value;
                final transitioning =
                    !reduceMotion && raw < 1 && previousIndex != selectedIndex;
                final isCurrent = index == selectedIndex;
                final isOutgoing = transitioning && index == previousIndex;
                final visible = isCurrent || isOutgoing;

                // Outgoing: gone by 35 % of the run. Incoming: starts at
                // 30 % and eases in over the remainder, scaling 96 % → 100 %.
                // The brief overlap happens while the outgoing page is
                // already nearly transparent, so nothing of it lingers.
                final outgoingOpacity = transitioning
                    ? 1 - Curves.easeIn.transform((raw / .35).clamp(0.0, 1.0))
                    : 0.0;
                final incomingProgress = transitioning
                    ? Curves.easeOutCubic.transform(
                        ((raw - .3) / .7).clamp(0.0, 1.0),
                      )
                    : 1.0;
                final opacity = isCurrent
                    ? incomingProgress
                    : isOutgoing
                    ? outgoingOpacity
                    : 1.0;
                final scale = isCurrent ? .96 + .04 * incomingProgress : 1.0;

                return Offstage(
                  offstage: !visible,
                  child: TickerMode(
                    enabled: isCurrent,
                    child: IgnorePointer(
                      ignoring: !isCurrent,
                      child: Opacity(
                        key: ValueKey('yo-tab-opacity-$index'),
                        opacity: opacity,
                        child: Transform.scale(
                          key: ValueKey('yo-tab-translation-$index'),
                          scale: scale,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
