import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Canonical content measures for YO Voice screens.
///
/// Backgrounds may stay full-bleed; this frame limits only the interactive
/// content so a desktop screen never becomes a stretched phone layout.
enum ResponsiveContentWidth {
  form(720),
  list(880),
  feed(1040),
  dashboard(1200),
  workbench(1440);

  const ResponsiveContentWidth(this.maxWidth);

  final double maxWidth;
}

enum ResponsiveContentAlignment { topLeft, topCenter }

/// Keeps page content at a readable measure while preserving full-height
/// layouts such as `Column` + `Expanded` lists.
///
/// Existing screens usually own their internal 16–18 px phone padding, so
/// [padding] defaults to zero. New screens can use [adaptivePagePadding] when
/// the frame should own the page gutter as well.
class ResponsiveContentFrame extends StatelessWidget {
  const ResponsiveContentFrame({
    required this.child,
    this.width = ResponsiveContentWidth.feed,
    this.alignment = ResponsiveContentAlignment.topCenter,
    this.padding = EdgeInsets.zero,
    this.fillHeight = true,
    super.key,
  });

  final Widget child;
  final ResponsiveContentWidth width;
  final ResponsiveContentAlignment alignment;
  final EdgeInsetsGeometry padding;

  /// Keep this true for root screens whose child contains `Expanded`.
  final bool fillHeight;

  static EdgeInsets adaptivePagePadding(double availableWidth) {
    if (availableWidth < 600) {
      return const EdgeInsets.symmetric(horizontal: 16);
    }
    if (availableWidth < 1100) {
      return const EdgeInsets.symmetric(horizontal: 24);
    }
    return const EdgeInsets.symmetric(horizontal: 32);
  }

  /// Prevents phone-style bottom sheets from spanning an entire desktop
  /// window while preserving the native full-width mobile presentation.
  static BoxConstraints? adaptiveModalConstraints(
    BuildContext context, {
    double maxWidth = 640,
  }) {
    if (MediaQuery.sizeOf(context).width < 600) return null;
    return BoxConstraints(maxWidth: maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    // Intrinsic surfaces (bottom bars, compact dialogs) must not use a
    // LayoutBuilder: LayoutBuilder itself expands to the parent's maximum
    // height, which would make a 60 px bottom bar consume the whole screen.
    if (!fillHeight) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: alignment == ResponsiveContentAlignment.topLeft
              ? Alignment.topLeft
              : Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width.maxWidth),
            child: child,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - resolvedPadding.horizontal,
        );
        final contentWidth = math.min(width.maxWidth, availableWidth);
        final contentHeight = fillHeight && constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - resolvedPadding.vertical)
            : null;

        return Padding(
          padding: resolvedPadding,
          child: Align(
            alignment: alignment == ResponsiveContentAlignment.topLeft
                ? Alignment.topLeft
                : Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              height: contentHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
