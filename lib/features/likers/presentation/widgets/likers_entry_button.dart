import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_typography.dart';

/// The visible, focusable "see who liked" text control of owner variant A
/// (spec §5.1, §13): a label and a trailing chevron — "See who liked ›"
/// beside the Top reactions avatars, or "Likes · 24 ›" where there is no
/// avatar row to sit beside.
///
/// A Material [TextButton], so it keeps the 48 px tap target, Enter/Space,
/// hover, the theme's 2 px focus ring and interactive foreground. The label
/// wraps onto more lines instead of truncating when it cannot fit.
/// [semanticLabel] replaces the visible words for assistive technology when
/// the host has a fuller sentence to say (the likers' names, the count).
class LikersEntryButton extends StatelessWidget {
  const LikersEntryButton({
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.focusNode,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final spoken = semanticLabel;
    // The label wraps rather than truncates: at 200 % text on a 320 px phone
    // "Zobacz, kto polubił" (and ru/uk/fi/el) no longer fit one line, and an
    // ellipsis would hide the control's visible name (WCAG 1.4.4). The
    // chevron stays beside the label block, never alone on a line.
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, softWrap: true)),
        const SizedBox(width: 2),
        const Icon(Icons.chevron_right_rounded, size: 18),
      ],
    );
    return TextButton(
      focusNode: focusNode,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: AppTypography.labelLarge,
      ),
      child: spoken == null
          ? content
          : Semantics(label: spoken, excludeSemantics: true, child: content),
    );
  }
}
