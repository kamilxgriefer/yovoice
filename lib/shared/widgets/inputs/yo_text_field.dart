import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

class YoTextField extends StatefulWidget {
  const YoTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.obscureText = false,
    this.showPasswordToggle = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.textAlign = TextAlign.start,
    this.textAlignVertical = TextAlignVertical.center,
    this.cursorColor,
    this.fillColor,
    this.contentPadding,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  const YoTextField.email({
    super.key,
    this.controller,
    this.focusNode,
    this.label = 'Email',
    this.hint = 'Enter your email',
    this.helperText,
    this.errorText,
    this.prefixIcon = const Icon(Icons.mail_outline_rounded),
    this.suffixIcon,
    this.textInputAction = TextInputAction.next,
    this.autofillHints = const <String>[
      AutofillHints.email,
      AutofillHints.username,
    ],
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.cursorColor,
    this.fillColor,
    this.contentPadding,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  }) : keyboardType = TextInputType.emailAddress,
       textCapitalization = TextCapitalization.none,
       obscureText = false,
       showPasswordToggle = false,
       enableSuggestions = true,
       autocorrect = false,
       maxLines = 1,
       minLines = 1,
       expands = false,
       textAlignVertical = TextAlignVertical.center;

  const YoTextField.password({
    super.key,
    this.controller,
    this.focusNode,
    this.label = 'Password',
    this.hint = 'Enter your password',
    this.helperText,
    this.errorText,
    this.prefixIcon = const Icon(Icons.lock_outline_rounded),
    this.suffixIcon,
    this.textInputAction = TextInputAction.done,
    this.autofillHints = const <String>[AutofillHints.password],
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.cursorColor,
    this.fillColor,
    this.contentPadding,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  }) : keyboardType = TextInputType.visiblePassword,
       textCapitalization = TextCapitalization.none,
       obscureText = true,
       showPasswordToggle = true,
       enableSuggestions = false,
       autocorrect = false,
       maxLines = 1,
       minLines = 1,
       expands = false,
       textAlignVertical = TextAlignVertical.center;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onEditingComplete;
  final bool obscureText;
  final bool showPasswordToggle;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool enableSuggestions;
  final bool autocorrect;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final bool expands;
  final TextAlign textAlign;
  final TextAlignVertical textAlignVertical;
  final Color? cursorColor;
  final Color? fillColor;
  final EdgeInsetsGeometry? contentPadding;
  final AutovalidateMode autovalidateMode;

  @override
  State<YoTextField> createState() => _YoTextFieldState();
}

class _YoTextFieldState extends State<YoTextField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  late bool _isObscured;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _isObscured = widget.obscureText;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant YoTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);

      if (_ownsFocusNode) {
        _focusNode.dispose();
      }

      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }

    if (oldWidget.obscureText != widget.obscureText) {
      _isObscured = widget.obscureText;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);

    if (_ownsFocusNode) {
      _focusNode.dispose();
    }

    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _togglePasswordVisibility() {
    setState(() {
      _isObscured = !_isObscured;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final bool hasExternalError =
        widget.errorText != null && widget.errorText!.trim().isNotEmpty;

    return FormField<String>(
      initialValue: widget.controller?.text,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      builder: (FormFieldState<String> field) {
        final String? visibleError = hasExternalError
            ? widget.errorText
            : field.errorText;

        final bool hasError =
            visibleError != null && visibleError.trim().isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.label != null && widget.label!.trim().isNotEmpty) ...[
              Text(
                widget.label!,
                style: AppTypography.labelMedium.copyWith(
                  color: widget.enabled
                      ? palette.textSecondary
                      : palette.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: widget.enabled
                    ? widget.fillColor ?? palette.surfaceRaised
                    : palette.surfaceMuted.withValues(alpha: 0.72),
                borderRadius: AppRadius.lg,
                border: Border.all(
                  color: _borderColor(hasError, palette, colors),
                  width: _focusNode.hasFocus ? 1.5 : 1,
                ),
                boxShadow: _focusNode.hasFocus && !hasError && widget.enabled
                    ? <BoxShadow>[
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.14),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: TextFormField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                autofocus: widget.autofocus,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                textCapitalization: widget.textCapitalization,
                autofillHints: widget.autofillHints,
                inputFormatters: widget.inputFormatters,
                obscureText: widget.showPasswordToggle
                    ? _isObscured
                    : widget.obscureText,
                enableSuggestions: widget.enableSuggestions,
                autocorrect: widget.autocorrect,
                maxLength: widget.maxLength,
                maxLines: widget.obscureText ? 1 : widget.maxLines,
                minLines: widget.obscureText ? 1 : widget.minLines,
                expands: widget.expands,
                textAlign: widget.textAlign,
                textAlignVertical: widget.textAlignVertical,
                cursorColor: widget.cursorColor ?? colors.primary,
                style: AppTypography.bodyLarge.copyWith(
                  color: widget.enabled
                      ? palette.textPrimary
                      : palette.textTertiary,
                ),
                onTap: widget.onTap,
                onEditingComplete: widget.onEditingComplete,
                onChanged: (String value) {
                  field.didChange(value);
                  widget.onChanged?.call(value);
                },
                onFieldSubmitted: widget.onSubmitted,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  counterText: '',
                  hintText: widget.hint,
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: palette.textTertiary,
                  ),
                  prefixIcon: _buildPrefixIcon(),
                  suffixIcon: _buildSuffixIcon(),
                  contentPadding:
                      widget.contentPadding ??
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  errorStyle: const TextStyle(
                    fontSize: 0,
                    height: 0,
                    color: AppColors.transparent,
                  ),
                ),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 7),
              _YoSupportingText(
                text: visibleError,
                icon: Icons.error_outline_rounded,
                color: colors.error,
              ),
            ] else if (widget.helperText != null &&
                widget.helperText!.trim().isNotEmpty) ...[
              const SizedBox(height: 7),
              _YoSupportingText(
                text: widget.helperText!,
                color: palette.textTertiary,
              ),
            ],
          ],
        );
      },
    );
  }

  Color _borderColor(bool hasError, AppPalette palette, ColorScheme colors) {
    if (!widget.enabled) {
      return palette.border;
    }

    if (hasError) {
      return colors.error;
    }

    if (_focusNode.hasFocus) {
      return palette.focus;
    }

    return palette.borderStrong;
  }

  Widget? _buildPrefixIcon() {
    if (widget.prefixIcon == null) {
      return null;
    }

    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return IconTheme(
      data: IconThemeData(
        color: _focusNode.hasFocus ? colors.primary : palette.textSecondary,
        size: 21,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: widget.prefixIcon,
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    final palette = context.appPalette;
    if (widget.showPasswordToggle) {
      return IconButton(
        onPressed: widget.enabled ? _togglePasswordVisibility : null,
        tooltip: _isObscured ? 'Show password' : 'Hide password',
        icon: Icon(
          _isObscured
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: widget.enabled ? palette.textSecondary : palette.textTertiary,
          size: 21,
        ),
      );
    }

    if (widget.suffixIcon == null) {
      return null;
    }

    return IconTheme(
      data: IconThemeData(
        color: widget.enabled ? palette.textSecondary : palette.textTertiary,
        size: 21,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 14),
        child: widget.suffixIcon,
      ),
    );
  }
}

class _YoSupportingText extends StatelessWidget {
  const _YoSupportingText({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(color: color, height: 1.35),
          ),
        ),
      ],
    );
  }
}
