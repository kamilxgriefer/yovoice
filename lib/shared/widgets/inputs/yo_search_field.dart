import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';

/// The design system's search field: a [YoTextField] in its
/// [YoTextFieldVariant.search] pill (refine-look R9) with a leading
/// magnifier and, while there is text, a clear action.
///
/// Clearing hands focus back to the field. The clear action leaves the tree
/// the moment the text is empty, and a focused node that leaves the tree
/// drops focus to its scope — the next Tab would restart from the top of the
/// route and a screen reader would lose its place (WCAG 2.4.3). The field
/// therefore always has a node this widget can reach: the caller's
/// [focusNode], or one it owns.
///
/// The clear target is 44 × 44 so the pill can rest at 44 px: the project's
/// minimum (`AppSizing.minimumTouchTarget`, WCAG 2.5.5), 4 dp under
/// Android's 48 dp guideline — see docs/UI.md.
class YoSearchField extends StatefulWidget {
  const YoSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool enabled;

  @override
  State<YoSearchField> createState() => _YoSearchFieldState();
}

class _YoSearchFieldState extends State<YoSearchField> {
  FocusNode? _ownFocusNode;

  // Kept until dispose even if a caller node arrives later: the field may
  // still be detaching from it during that rebuild.
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode(debugLabel: 'search'));

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _clear(TextEditingController controller) {
    controller.clear();
    // Before the clear action unmounts with the text: focus goes back to the
    // field, not to the route's first control.
    _focusNode.requestFocus();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return _field(context, null, hasText: false);
    // The clear action follows the text itself, not the caller's rebuilds:
    // a caller that only listens through [onChanged] still gets it.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _field(context, controller, hasText: value.text.isNotEmpty),
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController? controller, {
    required bool hasText,
  }) {
    final copy = AppLocalizations.of(context);
    return YoTextField(
      variant: YoTextFieldVariant.search,
      controller: controller,
      focusNode: _focusNode,
      hint: widget.hint ?? copy.text('Search', 'Szukaj'),
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: controller != null && hasText
          ? IconButton(
              tooltip: copy.text('Clear search', 'Wyczyść wyszukiwanie'),
              onPressed: widget.enabled ? () => _clear(controller) : null,
              // A 44 px target that fits inside the 44 px pill.
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: AppSizing.minimumTouchTarget,
                height: AppSizing.minimumTouchTarget,
              ),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // Follows large text like the magnifier (20 → 28 px).
              iconSize: YoTextField.searchGlyphSizeOf(context),
              icon: const Icon(Icons.close_rounded),
            )
          : null,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
    );
  }
}
