import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Keeps the clock, signal and battery legible over scrolled content.
///
/// Root mobile pages that pad themselves below the status bar instead of
/// sitting in a `SafeArea` (Home does, so its artwork can reach the top edge)
/// let scrolled headings slide under the system glyphs, where the two
/// collide. This paints a non-interactive band in the page's own background
/// colour, exactly as tall as the top inset, over [child]. With no top inset
/// (desktop, web, most landscape tablets) it paints nothing at all.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({required this.child, super.key});

  final Widget child;

  static const Key bandKey = ValueKey<String>('status-bar-scrim-band');

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    if (inset <= 0) return child;
    final background = context.appPalette.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: inset,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                key: bandKey,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background.withValues(alpha: .96),
                      background.withValues(alpha: .84),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
