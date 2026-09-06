import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';

/// A 48 dp bar that appears only while the software keyboard is open and a
/// text field has focus, offering one obvious way to finish typing.
///
/// Multiline fields keep Return as "new line", so iOS shows no Done key and
/// Android's action key inserts a newline too; testers read that as "there is
/// no button to stop writing". This bar is that button. It renders nothing
/// when the keyboard is closed, so it never changes a screen's layout at rest.
/// Place it directly above the keyboard: as `bottomNavigationBar`, or as the
/// last child of a Column whose body is `Expanded`.
class YoKeyboardDoneBar extends StatefulWidget {
  const YoKeyboardDoneBar({super.key});

  @override
  State<YoKeyboardDoneBar> createState() => _YoKeyboardDoneBarState();
}

class _YoKeyboardDoneBarState extends State<YoKeyboardDoneBar> {
  bool _textFieldFocused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChanged);
    _handleFocusChanged();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    final focused =
        focus?.context?.widget is EditableText ||
        (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null);
    if (focused != _textFieldFocused && mounted) {
      setState(() => _textFieldFocused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!keyboardOpen || !_textFieldFocused) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('yo-keyboard-done-bar'),
      color: colors.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Column(
            children: [
              Divider(height: 1, thickness: 1, color: colors.outlineVariant),
              Expanded(
                child: Row(
                  children: [
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: copy.text(
                        'Done, hide keyboard',
                        'Gotowe, ukryj klawiaturę',
                      ),
                      child: TextButton.icon(
                        key: const ValueKey('yo-keyboard-done'),
                        onPressed: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        icon: const Icon(Icons.keyboard_hide_rounded, size: 20),
                        label: Text(copy.text('Done', 'Gotowe')),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
