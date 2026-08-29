import 'package:flutter/material.dart';

/// A paint-only directional fade-through over one retained set of tab pages.
///
/// Every child stays mounted under a stable key. Hidden pages are Offstage and
/// have tickers disabled, while the selected page and (briefly) the outgoing
/// page share the viewport. This preserves scroll/form/listener state without
/// rebuilding pages on each animation frame.
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
                final t = const Cubic(0.22, 1, 0.36, 1).transform(raw);
                final transitioning =
                    !reduceMotion && raw < 1 && previousIndex != selectedIndex;
                final isCurrent = index == selectedIndex;
                final isOutgoing = transitioning && index == previousIndex;
                final visible = isCurrent || isOutgoing;
                final opacity = isCurrent
                    ? .82 + .18 * t
                    : isOutgoing
                    ? 1 - .16 * t
                    : 1.0;
                final horizontalOffset = isCurrent && transitioning
                    ? direction * 12 * (1 - t)
                    : 0.0;

                return Offstage(
                  offstage: !visible,
                  child: TickerMode(
                    enabled: isCurrent,
                    child: IgnorePointer(
                      ignoring: !isCurrent,
                      child: Opacity(
                        key: ValueKey('yo-tab-opacity-$index'),
                        opacity: opacity,
                        child: Transform.translate(
                          key: ValueKey('yo-tab-translation-$index'),
                          offset: Offset(horizontalOffset, 0),
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
