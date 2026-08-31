import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Gives a long-press context action equivalent keyboard, pointer and
/// assistive-technology paths without changing the action's business logic.
class AccessibleContextAction extends StatefulWidget {
  const AccessibleContextAction({
    required this.onOpen,
    required this.child,
    this.semanticLabel = 'Open message actions',
    this.borderRadius = 18,
    super.key,
  });

  final VoidCallback? onOpen;
  final Widget child;
  final String semanticLabel;
  final double borderRadius;

  @override
  State<AccessibleContextAction> createState() =>
      _AccessibleContextActionState();
}

class _AccessibleContextActionState extends State<AccessibleContextAction> {
  bool _showsFocusHighlight = false;
  bool _hovered = false;
  bool _pressed = false;

  void _open() => widget.onOpen?.call();

  @override
  Widget build(BuildContext context) {
    if (widget.onOpen == null) return widget.child;
    final palette = context.appPalette;

    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.contextMenu,
      onShowFocusHighlight: (value) {
        if (_showsFocusHighlight != value) {
          setState(() => _showsFocusHighlight = value);
        }
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _open();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        button: true,
        label: widget.semanticLabel,
        onTap: _open,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: _open,
            onLongPressStart: (_) => setState(() => _pressed = true),
            onLongPressEnd: (_) => setState(() => _pressed = false),
            onLongPressCancel: () => setState(() => _pressed = false),
            onSecondaryTap: _open,
            child: Stack(
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: _pressed
                            ? palette.interactiveForeground.withValues(
                                alpha: .14,
                              )
                            : _hovered
                            ? palette.interactiveForeground.withValues(
                                alpha: .06,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        border: Border.all(
                          color: _showsFocusHighlight
                              ? palette.focus
                              : _hovered
                              ? palette.borderStrong
                              : Colors.transparent,
                          width: _showsFocusHighlight ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
