import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// The look of a [YoTextField].
enum YoTextFieldVariant {
  /// A form field (auth, edit profile, channel names): the unchanged
  /// `borderStrong` edge at radius 20 with a soft focus glow.
  standard,

  /// The search pill (refine-look R9): at least 44 px tall, a stadium, a
  /// `surface` (Dark) / `surfaceRaised` (Pearl) fill with a 1 px `border`
  /// edge, a 2 px `focus` ring at pill radius painted over the edge (so
  /// focusing never shifts the text), a 20 px `textTertiary` leading glyph
  /// and no lift. High contrast restores the `borderStrong` edge.
  ///
  /// The faint edge is decoration; the magnifier (5.6:1 or more on the fill)
  /// and the hint identify the field. A search pill WITHOUT a [prefixIcon]
  /// has nothing left once the user types, so it keeps the form field's
  /// `borderStrong` edge (WCAG 1.4.11). Its glyphs follow large text up to
  /// [searchGlyphMax]; disabled, the hint and glyph dim to
  /// [searchDisabledInkAlpha] and the edge to the block hairline.
  search,
}

class YoTextField extends StatefulWidget {
  const YoTextField({
    super.key,
    this.variant = YoTextFieldVariant.standard,
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
    this.onTapOutside,
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
    this.onTapOutside,
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
  }) : variant = YoTextFieldVariant.standard,
       keyboardType = TextInputType.emailAddress,
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
    this.onTapOutside,
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
  }) : variant = YoTextFieldVariant.standard,
       keyboardType = TextInputType.visiblePassword,
       textCapitalization = TextCapitalization.none,
       obscureText = true,
       showPasswordToggle = true,
       enableSuggestions = false,
       autocorrect = false,
       maxLines = 1,
       minLines = 1,
       expands = false,
       textAlignVertical = TextAlignVertical.center;

  /// Form field or search pill.
  final YoTextFieldVariant variant;

  /// The search pill's minimum height (it grows with larger text).
  static const double searchHeight = 44;

  /// A disabled search pill dims its magnifier and hint to this alpha of
  /// `textTertiary`, so it reads as disabled in Dark too (its fill moves only
  /// `surface` → `surfaceMuted`, 1.05:1 there).
  static const double searchDisabledInkAlpha = .55;

  /// The search pill's glyphs (magnifier, clear): 20 px at 100 % text,
  /// following the text scale up to [searchGlyphMax] (reached at 140 %), so
  /// a 200 % hint is not flanked by specks. The clear target stays 44 px.
  static const double searchGlyphSize = 20;
  static const double searchGlyphMax = 28;

  /// [searchGlyphSize] under the ambient text scale, clamped to
  /// [searchGlyphSize]..[searchGlyphMax].
  static double searchGlyphSizeOf(BuildContext context) => MediaQuery.textScalerOf(
    context,
  ).scale(searchGlyphSize).clamp(searchGlyphSize, searchGlyphMax).toDouble();

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

  /// Forwarded to the underlying field. Left null, Flutter's default applies
  /// (no unfocus for touch on Android and iOS); a composer that wants a tap
  /// elsewhere to put the keyboard away passes its own handler.
  final TapRegionCallback? onTapOutside;
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
    final standardDuration = AppMotion.resolve(context, AppMotion.standard);
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
              duration: standardDuration,
              curve: Curves.easeOut,
              constraints: _isSearch
                  ? const BoxConstraints(minHeight: YoTextField.searchHeight)
                  : null,
              decoration: _isSearch
                  ? BoxDecoration(
                      color: widget.enabled
                          ? widget.fillColor ??
                                (palette.isDark
                                    ? palette.surface
                                    : palette.surfaceRaised)
                          : palette.surfaceMuted,
                      borderRadius: AppRadius.pill,
                    )
                  : BoxDecoration(
                      color: widget.enabled
                          ? widget.fillColor ?? palette.surfaceRaised
                          : palette.surfaceMuted,
                      borderRadius: AppRadius.lg,
                      border: Border.all(
                        color: _borderColor(hasError, palette),
                        width: _focusNode.hasFocus ? 2 : 1,
                      ),
                      boxShadow:
                          _focusNode.hasFocus && !hasError && widget.enabled
                          ? <BoxShadow>[
                              BoxShadow(
                                color: palette.focus.withValues(alpha: 0.14),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ]
                          : const <BoxShadow>[],
                    ),
              // The search pill's edge and focus ring are painted over the
              // fill, so the 1 → 2 px change never moves the text.
              foregroundDecoration: _isSearch
                  ? BoxDecoration(
                      borderRadius: AppRadius.pill,
                      border: Border.all(
                        color: _borderColor(hasError, palette),
                        width: _focusNode.hasFocus && widget.enabled ? 2 : 1,
                      ),
                    )
                  : null,
              alignment: _isSearch ? AlignmentDirectional.centerStart : null,
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
                cursorColor:
                    widget.cursorColor ?? palette.interactiveForeground,
                style: AppTypography.bodyLarge.copyWith(
                  color: widget.enabled
                      ? palette.textPrimary
                      : palette.textTertiary,
                ),
                onTap: widget.onTap,
                onTapOutside: widget.onTapOutside,
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
                  // Keep validation attached to the editable semantics node.
                  // The zero-height theme below prevents a second visual copy;
                  // `_YoSupportingText` remains the single visible message.
                  errorText: hasError ? visibleError : null,
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: _isSearch && !widget.enabled
                        ? _searchDisabledInk(palette)
                        : palette.textTertiary,
                  ),
                  prefixIcon: _buildPrefixIcon(),
                  suffixIcon: _buildSuffixIcon(),
                  // The pill's glyph slots may be smaller than Material's
                  // 48 px default so the field can rest at 44 px.
                  prefixIconConstraints: _isSearch
                      ? const BoxConstraints(minWidth: 40, minHeight: 40)
                      : null,
                  suffixIconConstraints: _isSearch
                      ? const BoxConstraints(minWidth: 40, minHeight: 40)
                      : null,
                  contentPadding:
                      widget.contentPadding ??
                      (_isSearch
                          ? EdgeInsetsDirectional.only(
                              start: widget.prefixIcon == null ? 18 : 0,
                              end: 16,
                              top: 10,
                              bottom: 10,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 17,
                            )),
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
                color: palette.dangerForeground,
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

  Color _borderColor(bool hasError, AppPalette palette) {
    if (!widget.enabled) {
      // A disabled pill steps down to the block hairline, so it no longer
      // looks like the resting one (whose edge is `border`).
      return _isSearch ? palette.hairline : palette.border;
    }

    if (hasError) {
      return palette.dangerForeground;
    }

    if (_focusNode.hasFocus) {
      return palette.focus;
    }

    // The search pill's faint edge relies on its magnifier to identify it;
    // without one it keeps the strong edge, as does high contrast.
    if (_isSearch &&
        widget.prefixIcon != null &&
        !MediaQuery.highContrastOf(context)) {
      return palette.border;
    }

    return palette.borderStrong;
  }

  bool get _isSearch => widget.variant == YoTextFieldVariant.search;

  Color _searchDisabledInk(AppPalette palette) => palette.textTertiary
      .withValues(alpha: YoTextField.searchDisabledInkAlpha);

  Widget? _buildPrefixIcon() {
    if (widget.prefixIcon == null) {
      return null;
    }

    final palette = context.appPalette;
    if (_isSearch) {
      return IconTheme(
        data: IconThemeData(
          color: widget.enabled
              ? palette.textTertiary
              : _searchDisabledInk(palette),
          size: YoTextField.searchGlyphSizeOf(context),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
          child: widget.prefixIcon,
        ),
      );
    }
    return IconTheme(
      data: IconThemeData(
        color: _focusNode.hasFocus
            ? palette.interactiveForeground
            : palette.textSecondary,
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
        size: _isSearch ? YoTextField.searchGlyphSizeOf(context) : 21,
      ),
      child: Padding(
        // The pill's trailing action (clear) carries its own 44 px target.
        padding: _isSearch
            ? const EdgeInsetsDirectional.only(end: 2)
            : const EdgeInsets.only(left: 10, right: 14),
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
    return Semantics(
      container: icon != null,
      liveRegion: icon != null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...[
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 14, color: color),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: color,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
