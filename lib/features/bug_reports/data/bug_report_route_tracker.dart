import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Watches the app navigator for the bug reporter.
///
/// Two jobs, both read-only:
///
///  * [transientRouteOpen] is true while a dialog, bottom sheet or menu is on
///    top, so the floating "Bug" button never sits over a modal (including
///    the reporter itself).
///  * [currentScreenName] names the screen the person was on — the Dart class
///    name of the topmost visible `…Screen`/`…Page` widget, or a named
///    route. It is a NAME, never an id: no conversation, server, user or
///    message id can reach a report through it. Only three of the app's routes
///    carry a `RouteSettings.name`, which is why it looks at the widget tree.
class BugReportRouteTracker extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  final ValueNotifier<bool> _transient = ValueNotifier<bool>(false);

  ValueListenable<bool> get transientRouteOpen => _transient;

  /// How many routes are on the app navigator (the root shell counts as one).
  int get depth => _stack.length;

  void _changed() {
    final transient = _stack.any((route) => route is PopupRoute);
    if (_transient.value != transient) {
      // Observers are called during navigator updates; notify after the frame
      // so a listener that rebuilds never does so mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = _stack.any((route) => route is PopupRoute);
        if (_transient.value != current) _transient.value = current;
      });
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else {
      if (oldRoute != null) _stack.remove(oldRoute);
      if (newRoute != null) _stack.add(newRoute);
    }
    _changed();
  }

  /// The topmost page (non-popup) route's screen name, or `unknown`.
  String currentScreenName() {
    try {
      for (final route in _stack.reversed) {
        if (route is PopupRoute) continue;
        final named = route.settings.name;
        if (named != null && isSafeScreenName(named)) return named;
        if (route is ModalRoute) {
          final context = route.subtreeContext;
          if (context != null) {
            final found = findScreenName(context);
            if (found != null) return found;
          }
        }
        break;
      }
    } catch (_) {
      // Diagnostics must never break reporting.
    }
    return 'unknown';
  }
}

final RegExp _safeScreenName = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$<>.,:-]{0,79}$');

/// The server's route pattern (functions/bug_reports/contract.js).
bool isSafeScreenName(String value) => _safeScreenName.hasMatch(value);

/// The first visible widget below [context] whose class name ends in
/// `Screen` or `Page`, skipping subtrees that are offstage, hidden or
/// ticker-disabled. [IndexedStack] wraps every non-selected child in an
/// invisible [Visibility], so the shell's retained tabs are skipped too.
/// Bounded, so a deep tree cannot stall the reporter.
@visibleForTesting
String? findScreenName(BuildContext context, {int budget = 6000}) {
  var remaining = budget;
  String? result;

  bool hidden(Widget widget) {
    if (widget is Offstage) return widget.offstage;
    if (widget is Visibility) return !widget.visible;
    if (widget is TickerMode) return !widget.enabled;
    return false;
  }

  String? nameOf(Widget widget) {
    final raw = widget.runtimeType.toString();
    final base = raw.split('<').first;
    if ((base.endsWith('Screen') || base.endsWith('Page')) &&
        isSafeScreenName(base)) {
      return base;
    }
    return null;
  }

  void visit(Element element) {
    if (result != null || remaining-- <= 0) return;
    final widget = element.widget;
    if (hidden(widget)) return;
    final name = nameOf(widget);
    if (name != null) {
      result = name;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return result;
}

/// The app-wide tracker, registered on MaterialApp.navigatorObservers.
final BugReportRouteTracker bugReportRouteTracker = BugReportRouteTracker();
