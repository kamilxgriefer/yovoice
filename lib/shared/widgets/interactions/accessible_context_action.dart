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
    this.ringInsets = EdgeInsets.zero,
    super.key,
  });

  final VoidCallback? onOpen;
  final Widget child;
  final String semanticLabel;
  final double borderRadius;

  /// Draws the focus ring and the hover / press wash this far inside the
  /// child's edges, so a child that carries layout margin (a chat bubble's
  /// 48 px gutter and its gap to the next message) is ringed where the
  /// message is, not around the empty margin.
  final EdgeInsetsGeometry ringInsets;

  @override
  State<AccessibleContextAction> createState() =>
      _AccessibleContextActionState();
}

class _AccessibleContextActionState extends State<AccessibleContextAction> {
  /// The detector's own node. `onShowFocusHighlight` reports focus WITHIN
  /// the detector, so a focusable child (a voice row, a photo, a room link)
  /// taking focus would otherwise light this ring as well as its own: two
  /// rings for one focused control. The ring shows only while this node
  /// itself holds primary focus and the highlight mode is the keyboard's.
  final FocusNode _focusNode = FocusNode(debugLabel: 'AccessibleContextAction');
  bool _highlightMode = false;
  bool _primaryFocus = false;
  bool _hovered = false;
  bool _pressed = false;

  bool get _showsFocusHighlight => _highlightMode && _primaryFocus;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    final primary = _focusNode.hasPrimaryFocus;
    if (primary != _primaryFocus) setState(() => _primaryFocus = primary);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  void _open() => widget.onOpen?.call();

  @override
  Widget build(BuildContext context) {
    if (widget.onOpen == null) return widget.child;
    final palette = context.appPalette;

    return FocusableActionDetector(
      focusNode: _focusNode,
      mouseCursor: SystemMouseCursors.contextMenu,
      onShowFocusHighlight: (value) {
        if (_highlightMode != value) setState(() => _highlightMode = value);
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
                // This widget owns the long-press. A Tooltip anywhere below
                // it would otherwise claim every touch long-press for itself:
                // RawTooltip registers its own LongPressGestureRecognizer on
                // pointer down, deeper in the hit-test path, so its deadline
                // fires first and wins the arena — which is how a photo
                // bubble's "View photo" tooltip hid message reactions on
                // phones. Hover-only tooltips keep the desktop affordance and
                // the semantics tooltip, and give the touch long-press back
                // to the action that owns it.
                TooltipTheme(
                  data: TooltipTheme.of(
                    context,
                  ).copyWith(triggerMode: TooltipTriggerMode.manual),
                  child: widget.child,
                ),
                Positioned.fill(
                  child: Padding(
                    padding: widget.ringInsets,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
