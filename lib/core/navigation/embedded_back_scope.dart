import 'dart:async';

import 'package:flutter/widgets.dart';

/// One level of Back owned by a view INSIDE a route rather than by a route of
/// its own: a sub-view of a retained root tab, such as the Yeels "Twoje
/// Yeels" pool, which reads as a page of its own but is only a state of the
/// feed.
///
/// While [claimed] is true the scope holds the route (a [PopScope] with
/// `canPop: false`), so a system Back — Android's button or gesture, the
/// browser's Back — reaches [onBack] instead of leaving the screen. The
/// framework only asks the system to hand Back to Flutter while something
/// holds the route, which is why the claim is a real [PopScope] and not a
/// listener.
///
/// A [PopScope] alone is not enough inside the mobile shell: the shell holds
/// the same root route for its tab history, and a route calls EVERY pop
/// entry when it refuses a pop. Without coordination one Back would both
/// leave the sub-view and switch tabs. The shell therefore offers the
/// gesture to [dispatch] first and moves through its history only when no
/// scope on its route took it. [onBack] runs at most once per Back, whichever
/// of the two listeners is called first.
class EmbeddedBackScope extends StatefulWidget {
  const EmbeddedBackScope({
    required this.claimed,
    required this.onBack,
    required this.child,
    super.key,
  });

  /// True while the sub-view is showing and visible. False costs nothing:
  /// the route pops, and the shell's history moves, exactly as without it.
  final bool claimed;

  /// Leaves the sub-view. Called once per Back while [claimed].
  final VoidCallback onBack;

  final Widget child;

  static final Set<_EmbeddedBackScopeState> _mounted =
      <_EmbeddedBackScopeState>{};

  /// Offers a Back to the scope that currently claims [context]'s route.
  ///
  /// Returns true when one took it, in which case the caller must not act on
  /// the same Back. The most recently mounted claiming scope wins, so a
  /// nested sub-view answers before the view it sits in.
  static bool dispatch(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) return false;
    for (final scope in _mounted.toList(growable: false).reversed) {
      if (scope._claims(route)) {
        scope._handle();
        return true;
      }
    }
    return false;
  }

  @override
  State<EmbeddedBackScope> createState() => _EmbeddedBackScopeState();
}

class _EmbeddedBackScopeState extends State<EmbeddedBackScope> {
  ModalRoute<Object?>? _route;

  /// Set while one Back is being delivered: the shell's [dispatch] and this
  /// scope's own [PopScope] callback both see the same Back, in either
  /// order, and the second must not leave a second level.
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    EmbeddedBackScope._mounted.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    EmbeddedBackScope._mounted.remove(this);
    super.dispose();
  }

  bool _claims(ModalRoute<Object?> route) =>
      mounted && widget.claimed && identical(_route, route);

  void _handle() {
    if (_handling) return;
    _handling = true;
    // Every listener of one Back runs in the same synchronous pass, so the
    // latch only has to outlive that pass.
    scheduleMicrotask(() => _handling = false);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.claimed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.claimed) _handle();
      },
      child: widget.child,
    );
  }
}
