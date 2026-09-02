import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';

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
    final copy = AppLocalizations.of(context);
    final showHandle = MediaQuery.sizeOf(context).width < desktopBreakpoint;
    final closeLabel = copy.template(
      'Close {sheet}',
      'Zamknij: {sheet}',
      values: <String, Object>{'sheet': sheetLabel},
    );
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
              child: YoIconButton(
                key: const ValueKey('modal-sheet-close'),
                icon: Icons.close_rounded,
                tooltip: closeLabel,
                semanticLabel: closeLabel,
                onPressed: close,
                size: 44,
                iconSize: 22,
                foregroundColor: closeColor ?? surfaceForeground,
                backgroundColor: closeBackgroundColor,
                borderColor: Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
