import 'package:flutter/material.dart';

import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';

class YoSearchField extends StatelessWidget {
  const YoSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return YoTextField(
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: controller != null && controller!.text.isNotEmpty
          ? IconButton(
              onPressed: () {
                controller!.clear();
                onChanged?.call('');
                onClear?.call();
              },
              icon: const Icon(Icons.close_rounded),
            )
          : null,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      enabled: enabled,
    );
  }
}
