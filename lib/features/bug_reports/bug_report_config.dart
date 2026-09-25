import 'package:flutter/foundation.dart';

/// Compile-time switch for the testing-period floating "Bug" button.
///
/// ON unless a build passes `--dart-define=YOVOICE_BUG_BUTTON=false`. YO Voice
/// ships ONE binary per platform to TestFlight / Play testing and then to the
/// stores, and today every installed mobile build belongs to a tester, so the
/// default is on and the builds Kamil is shipping to testers need no new flag.
/// The first build meant for the general public turns it off with the define;
/// nothing else changes ("Report a bug" in Settings and the More menu stays).
///
/// Never on the web: app.yovoice.app is public, so the web build shows no
/// floating button regardless of this define.
const bool bugReportButtonCompiledIn = bool.fromEnvironment(
  'YOVOICE_BUG_BUTTON',
  defaultValue: true,
);

/// Whether this build may show the floating button at all (the per-device
/// preference then decides whether it does).
bool get bugReportButtonAvailable => bugReportButtonCompiledIn && !kIsWeb;
