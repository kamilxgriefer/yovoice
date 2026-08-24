import 'package:flutter/material.dart';

/// The single close affordance for YO Voice modal bottom sheets.
///
/// Phones and tablets keep one attached drag cue. Pointer-first desktop
/// surfaces omit the cue (dragging is not their primary interaction) but keep
/// the same explicit close button. The cue ignores pointers so vertical drags
/// continue to reach the surrounding Material [BottomSheet].
class YoModalSheetChrome extends StatelessWidget {
  const YoModalSheetChrome({
    required this.sheetLabel,
    required this.surfaceColor,
    this.onClose,
    this.handleColor,
    this.closeColor,
    this.closeBackgroundColor = Colors.transparent,
    this.horizontalPadding = 8,
    super.key,
  });

  static const double desktopBreakpoint = 1100;

  final String sheetLabel;
  final Color surfaceColor;
  final VoidCallback? onClose;
  final Color? handleColor;
  final Color? closeColor;
  final Color closeBackgroundColor;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final showHandle = MediaQuery.sizeOf(context).width < desktopBreakpoint;
    final closeLabel = 'Close $sheetLabel';
    final close = onClose ?? () => Navigator.of(context).maybePop<void>();
    final surfaceIsDark =
        ThemeData.estimateBrightnessForColor(surfaceColor) == Brightness.dark;
    final surfaceForeground = surfaceIsDark ? Colors.white : Colors.black87;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: sheetLabel,
      child: SizedBox(
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (showHandle)
              ExcludeSemantics(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      key: const ValueKey('modal-sheet-drag-handle'),
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            handleColor ??
                            surfaceForeground.withValues(alpha: .56),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: horizontalPadding,
              child: Semantics(
                button: true,
                enabled: true,
                label: closeLabel,
                onTap: close,
                excludeSemantics: true,
                child: IconButton(
                  key: const ValueKey('modal-sheet-close'),
                  tooltip: closeLabel,
                  onPressed: close,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    foregroundColor: closeColor ?? surfaceForeground,
                    backgroundColor: closeBackgroundColor,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
