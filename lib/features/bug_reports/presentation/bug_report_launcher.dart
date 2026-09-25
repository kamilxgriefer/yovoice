import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:yovoice/features/bug_reports/data/bug_report_context.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_route_tracker.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_service.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_capture.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_sheet.dart';

/// Opens the bug reporter from any entry point (Settings, the More menu, the
/// floating "Bug" button).
///
/// Order matters: the screen is captured and named FIRST, while the person's
/// screen is still what is showing, then the reporter is pushed. The capture
/// is only a candidate the reporter may review and attach.
abstract final class BugReportLauncher {
  static final ValueNotifier<bool> _open = ValueNotifier<bool>(false);

  /// True while the reporter is open; the floating button hides meanwhile.
  static ValueListenable<bool> get isOpen => _open;

  /// Injected by tests to observe or replace the opening step.
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugOpenOverride;

  static Future<void> open(
    BuildContext context, {
    BugReportService? service,
    BugReportRouteTracker? tracker,
  }) async {
    final override = debugOpenOverride;
    if (override != null) return override(context);
    if (_open.value) return;
    _open.value = true;
    try {
      // Let any closing menu or sheet leave the screen before it is captured.
      await WidgetsBinding.instance.endOfFrame;
      final routes = tracker ?? bugReportRouteTracker;
      final route = routes.currentScreenName();
      final depth = routes.depth;
      final blocked = BugReportCaptureGuard.isActive;
      final screenshot = blocked ? null : await captureBugReportScreenshot();
      if (!context.mounted) return;
      // Read now, from the screen being reported, not when Send is pressed:
      // the synchronous part reads MediaQuery, locale and theme immediately.
      final reportContext = collectBugReportContext(
        context,
        route: route,
        routeDepth: depth,
      )..ignore();
      await showBugReportSheet(
        context,
        screenshot: screenshot,
        captureBlocked: blocked,
        service: service,
        contextBuilder: () => reportContext,
      );
    } finally {
      _open.value = false;
    }
  }
}
