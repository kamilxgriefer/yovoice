import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/bug_reports/bug_report_config.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_launcher.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';

/// The visual and touch size of the floating "Bug" button.
const double bugButtonSize = 48;

/// Space the button always leaves for what can sit above the dock: the
/// dock's own expanded-label growth (its reserved height covers the compact
/// form) and the live-conversation mini bar.
const double _dockLabelAllowance = 28;
const double _miniBarAllowance = 88;

/// The rectangle the WHOLE button must stay inside, or null when the screen
/// has no room for it (a landscape phone, a split-screen sliver).
///
/// It is derived only from what the platform and the dock themselves report:
///
///  * left/right: the safe area AND the system gesture insets (Android's
///    back-gesture edges), so the button never sits where a swipe means Back;
///  * top: the status bar plus a toolbar, so it never covers app bar actions;
///  * bottom: the floating dock's own reserved height for this text scale and
///    bottom inset, plus room for its expanded labels and the mini bar, plus
///    the system gesture inset — so it never overlaps, pushes or moves the
///    dock (the dock is not touched; the button simply stays above it).
Rect? bugButtonAllowedArea(MediaQueryData media) {
  final size = media.size;
  final gesture = media.systemGestureInsets;
  final padding = media.viewPadding;
  const margin = AppRhythm.tight;
  final left = math.max(padding.left, gesture.left) + margin;
  final right = size.width - math.max(padding.right, gesture.right) - margin;
  final top = padding.top + kToolbarHeight + margin;
  final dockBand =
      YoFloatingNavigationDock.reservedHeightFor(
        safeBottom: math.max(padding.bottom, gesture.bottom),
        textScale: media.textScaler.scale(1),
      ) +
      _dockLabelAllowance +
      _miniBarAllowance;
  final bottom = size.height - dockBand - margin;
  if (right - left < bugButtonSize * 2 || bottom - top < bugButtonSize * 2) {
    return null;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Hosts the testing-period floating "Bug" button above the app.
///
/// Mounted once, in MaterialApp.builder, OUTSIDE the screenshot boundary so it
/// never appears in a bug-report screenshot. It is shown only when:
///   * the build compiles it in and this is not the web ([bugReportButtonAvailable]);
///   * this device has not hidden it (the Settings switch or a long-press);
///   * someone is signed in (reports need an account);
///   * no dialog, sheet or menu is open, the reporter is not open, and the
///     keyboard is down;
///   * the screen has room for it ([bugButtonAllowedArea]).
///
/// It can be dragged anywhere inside the allowed area and snaps to the nearer
/// side edge (right edge only on the desktop layout, whose left edge is the
/// navigation rail).
class BugReportFloatingButtonHost extends StatefulWidget {
  const BugReportFloatingButtonHost({
    required this.child,
    required this.navigatorKey,
    this.available,
    this.signedInChanges,
    this.initiallySignedIn,
    this.routeTracker,
    this.onOpenReporter,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Test seams. Production: [bugReportButtonAvailable], FirebaseAuth, the
  /// app-wide [bugReportRouteTracker] and [BugReportLauncher.open].
  final bool? available;
  final Stream<bool>? signedInChanges;
  final bool? initiallySignedIn;
  final BugReportRouteTracker? routeTracker;
  final void Function(BuildContext navigatorContext)? onOpenReporter;

  @override
  State<BugReportFloatingButtonHost> createState() =>
      _BugReportFloatingButtonHostState();
}

class _BugReportFloatingButtonHostState
    extends State<BugReportFloatingButtonHost> {
  StreamSubscription<bool>? _auth;
  bool _signedIn = false;

  // Resting place: which side, and where along the allowed height (0..1).
  bool _onRight = true;
  double _fraction = .58;
  Offset? _dragging;

  BugReportRouteTracker get _tracker =>
      widget.routeTracker ?? bugReportRouteTracker;

  bool get _available => widget.available ?? bugReportButtonAvailable;

  @override
  void initState() {
    super.initState();
    _tracker.transientRouteOpen.addListener(_changed);
    BugReportLauncher.isOpen.addListener(_changed);
    if (!_available) return;
    final changes = widget.signedInChanges ?? _firebaseSignedInChanges();
    _signedIn = widget.initiallySignedIn ?? _firebaseSignedIn();
    _auth = changes?.listen((signedIn) {
      if (mounted && signedIn != _signedIn) {
        setState(() => _signedIn = signedIn);
      }
    });
  }

  static bool _firebaseSignedIn() {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  static Stream<bool>? _firebaseSignedInChanges() {
    try {
      return FirebaseAuth.instance.authStateChanges().map(
        (user) => user != null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant BugReportFloatingButtonHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTracker = oldWidget.routeTracker ?? bugReportRouteTracker;
    if (!identical(oldTracker, _tracker)) {
      oldTracker.transientRouteOpen.removeListener(_changed);
      _tracker.transientRouteOpen.addListener(_changed);
    }
    if (oldWidget.initiallySignedIn != widget.initiallySignedIn &&
        widget.initiallySignedIn != null) {
      _signedIn = widget.initiallySignedIn!;
    }
    if (oldWidget.signedInChanges != widget.signedInChanges && _available) {
      unawaited(_auth?.cancel());
      _auth = (widget.signedInChanges ?? _firebaseSignedInChanges())?.listen((
        signedIn,
      ) {
        if (mounted && signedIn != _signedIn) {
          setState(() => _signedIn = signedIn);
        }
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tracker.transientRouteOpen.removeListener(_changed);
    BugReportLauncher.isOpen.removeListener(_changed);
    unawaited(_auth?.cancel());
    super.dispose();
  }

  Offset _restingOffset(Rect area, bool desktop) {
    final onRight = desktop || _onRight;
    final x = onRight ? area.right - bugButtonSize : area.left;
    final y = area.top + _fraction * (area.height - bugButtonSize);
    return Offset(x, y);
  }

  Offset _clamp(Offset offset, Rect area) => Offset(
    offset.dx.clamp(area.left, area.right - bugButtonSize).toDouble(),
    offset.dy.clamp(area.top, area.bottom - bugButtonSize).toDouble(),
  );

  void _open() {
    final navigatorContext = widget.navigatorKey.currentState?.overlay?.context;
    if (navigatorContext == null) return;
    final override = widget.onOpenReporter;
    if (override != null) {
      override(navigatorContext);
      return;
    }
    unawaited(BugReportLauncher.open(navigatorContext));
  }

  Future<void> _confirmHide() async {
    final navigatorContext = widget.navigatorKey.currentState?.overlay?.context;
    final preferences = AppPreferencesScope.maybeOf(context);
    if (navigatorContext == null || preferences == null) return;
    final hide = await showDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          key: const ValueKey('bug-button-hide-dialog'),
          title: Text(copy.text('Hide the Bug button?', 'Ukryć przycisk Bug?')),
          content: Text(
            copy.text(
              'You can still report a bug from Settings or the More menu, and bring the button back in Settings > Help.',
              'Nadal możesz zgłosić błąd w Ustawieniach lub w menu Więcej, a przycisk przywrócisz w Ustawienia > Pomoc.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Keep', 'Zostaw')),
            ),
            FilledButton(
              key: const ValueKey('bug-button-hide-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(copy.text('Hide', 'Ukryj')),
            ),
          ],
        );
      },
    );
    if (hide == true) {
      try {
        await preferences.setBugReportButtonVisible(false);
      } catch (_) {
        // The switch in Settings shows the real state.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferencesScope.maybeOf(context);
    final media = MediaQuery.of(context);
    final area = bugButtonAllowedArea(media);
    final visible =
        _available &&
        _signedIn &&
        (preferences?.value.bugReportButtonVisible ?? true) &&
        !_tracker.transientRouteOpen.value &&
        !BugReportLauncher.isOpen.value &&
        media.viewInsets.bottom == 0 &&
        area != null;

    // The app is ALWAYS the first child of the same Stack, whether or not the
    // button shows, so toggling the button never re-parents (and so never
    // rebuilds or resets) the navigator underneath it.
    final app = Positioned.fill(
      key: const ValueKey('bug-button-host-app'),
      child: widget.child,
    );
    if (!visible) {
      return Stack(textDirection: TextDirection.ltr, children: [app]);
    }

    // The shell's own desktop predicate (MainShell.usesDesktopLayout).
    final desktop =
        media.size.width >= MainShell.desktopBreakpoint &&
        media.size.height >= DesktopSidebar.minimumSupportedHeight;
    final position = _dragging ?? _restingOffset(area, desktop);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        app,
        Positioned(
          left: position.dx,
          top: position.dy,
          width: bugButtonSize,
          height: bugButtonSize,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _dragging = position),
            onPanUpdate: (details) => setState(() {
              _dragging = _clamp((_dragging ?? position) + details.delta, area);
            }),
            onPanEnd: (_) => setState(() {
              final end = _dragging ?? position;
              _onRight =
                  desktop || end.dx + bugButtonSize / 2 >= area.center.dx;
              final travel = area.height - bugButtonSize;
              _fraction = travel <= 0
                  ? 0
                  : ((end.dy - area.top) / travel).clamp(0.0, 1.0);
              _dragging = null;
            }),
            child: _BugButton(
              onPressed: _open,
              onHide: () => unawaited(_confirmHide()),
            ),
          ),
        ),
      ],
    );
  }
}

class _BugButton extends StatelessWidget {
  const _BugButton({required this.onPressed, required this.onHide});

  final VoidCallback onPressed;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('bug-report-floating-button'),
      button: true,
      label: copy.text('Report a bug', 'Zgłoś błąd'),
      hint: copy.text(
        'Drag to move. Touch and hold to hide.',
        'Przeciągnij, aby przesunąć. Przytrzymaj, aby ukryć.',
      ),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(
          label: copy.text('Hide the Bug button', 'Ukryj przycisk Bug'),
        ): onHide,
      },
      excludeSemantics: true,
      child: Material(
        color: palette.surfaceRaised.withValues(alpha: .94),
        elevation: 3,
        // A fully opaque shadow reads as a hard dark ring on the Home canvas
        // (the More popover hit the same thing); a translucent one is depth.
        shadowColor: palette.shadow.withValues(alpha: .24),
        shape: CircleBorder(side: BorderSide(color: palette.borderStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          onLongPress: onHide,
          child: Center(
            child: Icon(
              Icons.bug_report_rounded,
              size: 24,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
