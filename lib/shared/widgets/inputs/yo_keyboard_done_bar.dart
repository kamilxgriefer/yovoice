import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

/// A bar that appears only while the software keyboard is open and a text
/// field has focus, offering one obvious way to finish typing — and, when the
/// screen hands one over, its primary action docked right next to it.
///
/// Multiline fields keep Return as "new line", so iOS shows no Done key and
/// Android's action key inserts a newline too; testers read that as "there is
/// no button to stop writing". This bar is that button. It renders nothing
/// when the keyboard is closed, so it never changes a screen's layout at rest,
/// and nothing when a hardware keyboard is attached (no inset is reported),
/// where the screen's own resting chrome is already visible.
///
/// ## Placement — the part that is easy to get wrong
///
/// `Scaffold` does **not** lift `bottomNavigationBar` above the keyboard. It
/// shrinks the body and leaves the bottom slot pinned to the bottom of the
/// window (`_ScaffoldLayout.performLayout`: `bottom = size.height`), so bottom
/// chrome placed there is drawn *behind* the keyboard — present in the tree,
/// invisible on the device. Measured on a 390x844 surface with a 336 px
/// keyboard: a bare `bottomNavigationBar` lands at y 796–844, fully covered.
///
/// There are exactly three placements that put this bar where a thumb can
/// reach it, and every one of them is verified by a widget test that measures
/// the rendered rectangle against the top of the keyboard:
///
/// 1. `Scaffold.bottomNavigationBar` wrapped in [YoKeyboardSafeBottomBar],
///    which lifts the whole bottom chrome by the keyboard inset (390x844 with
///    a 336 px keyboard: y 460–508, resting on the keyboard).
/// 2. The last child of a `Column` inside `Scaffold.body` whose other child is
///    `Expanded` — the body has already been shrunk above the keyboard.
/// 3. The last child of a sheet's `Column` that sits inside its own
///    `viewInsets` padding.
///
/// `Scaffold` strips the bottom view inset from the **body** slot
/// (`removeBottomInset: resizeToAvoidBottomInset`), so in placement 2 the
/// inherited `viewInsets.bottom` is 0 while the keyboard is open. That is why
/// [_keyboardInset] falls back to the `FlutterView`'s own inset: without it,
/// the body placement renders nothing at all.
class YoKeyboardDoneBar extends StatefulWidget {
  const YoKeyboardDoneBar({super.key, this.action});

  /// The screen's primary action (Publish, Send, Save…), docked opposite
  /// Done while the keyboard covers the screen's own footer.
  ///
  /// Pass `null` — the default — when that action is already visible above
  /// the keyboard (an app bar action, or a footer in `bottomNavigationBar`).
  /// Callers that pass an action must hide their in-body copy of it while it
  /// is docked here, so a screen reader never meets the same button twice.
  final Widget? action;

  @override
  State<YoKeyboardDoneBar> createState() => _YoKeyboardDoneBarState();
}

class _YoKeyboardDoneBarState extends State<YoKeyboardDoneBar>
    with WidgetsBindingObserver {
  bool _textFieldFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_handleFocusChanged);
    // Never inspect the focused element from inside `initState`: the widget
    // that holds focus may be the one currently being deactivated (a route
    // with a focused field popping while this bar mounts), and an ancestor
    // lookup on a deactivated element asserts in debug.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveFocus());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The keyboard inset is not a MediaQuery dependency in every placement —
  /// inside a `Scaffold.body` the inset is stripped, so the stripped data
  /// never changes and no rebuild is scheduled. React to the metrics change
  /// itself instead of trusting the inherited value to notify.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (duringFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveFocus());
      return;
    }
    _resolveFocus();
  }

  void _resolveFocus() {
    if (!mounted) return;
    final focused = _focusIsEditable();
    if (focused != _textFieldFocused) {
      setState(() => _textFieldFocused = focused);
    }
  }

  bool _focusIsEditable() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// The larger of the inherited inset and the view's own, in logical pixels.
  ///
  /// The inherited value is authoritative everywhere except inside a
  /// `Scaffold.body`, where it has been stripped to zero; the view's value is
  /// authoritative there. Widget tests inject a synthetic MediaQuery with no
  /// matching view inset, so the maximum is what keeps both honest.
  double _keyboardInset(BuildContext context) {
    final inherited = MediaQuery.viewInsetsOf(context).bottom;
    final view = View.maybeOf(context);
    if (view == null) return inherited;
    final ratio = view.devicePixelRatio;
    final fromView = ratio > 0 ? view.viewInsets.bottom / ratio : 0.0;
    return math.max(inherited, fromView);
  }

  @override
  Widget build(BuildContext context) {
    if (_keyboardInset(context) <= 0 || !_textFieldFocused) {
      return const SizedBox.shrink();
    }
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final action = widget.action;

    final done = Semantics(
      button: true,
      label: copy.text('Done, hide keyboard', 'Gotowe, ukryj klawiaturę'),
      child: TextButton.icon(
        key: const ValueKey('yo-keyboard-done'),
        onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
        // docs/UI.md sets a 44x44 floor; Material 3's TextButton default is
        // a 40 px painted height.
        style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
        icon: const Icon(Icons.keyboard_hide_rounded, size: 20),
        label: Text(copy.text('Done', 'Gotowe')),
      ),
    );

    return Material(
      key: const ValueKey('yo-keyboard-done-bar'),
      color: colors.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            // The frame keeps the controls under the form on a tablet or a
            // desktop window instead of pinning them to the screen edges.
            ResponsiveContentFrame(
              width: ResponsiveContentWidth.form,
              fillHeight: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                // A minimum, not a fixed height: enlarged text grows the row
                // instead of overflowing it.
                constraints: BoxConstraints(
                  minHeight: action == null ? 47 : 55,
                ),
                child: Row(
                  children: action == null
                      ? [const Spacer(), done, const SizedBox(width: 8)]
                      : [
                          done,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: action,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom chrome that stays visible while the software keyboard is open.
///
/// Wrap whatever a screen puts in `Scaffold.bottomNavigationBar` — the
/// [YoKeyboardDoneBar], a pinned primary-action footer, or both in a Column.
/// `Scaffold` shrinks its body for the keyboard but leaves the bottom slot at
/// the bottom of the window, behind the keyboard; this lifts it by the same
/// inset, and the Scaffold then shrinks the body by the chrome's full height,
/// so nothing ends up hidden or overlapped.
///
/// At rest the inset is 0 and this changes no layout at all. Do NOT use it
/// inside a sheet that already pads itself by `viewInsets` — that would lift
/// the chrome twice.
class YoKeyboardSafeBottomBar extends StatelessWidget {
  const YoKeyboardSafeBottomBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
