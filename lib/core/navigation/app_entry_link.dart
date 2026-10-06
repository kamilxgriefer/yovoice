import 'package:flutter/foundation.dart';

/// The URL this page was loaded with, for the entry links that are opened
/// once per page load (ADR-238: `?user=` and `?moment=`).
///
/// Why not `Uri.base` at the moment the shell mounts: on the web the
/// Navigator reports every *named* top route to the browser, and the hash
/// URL strategy writes it into the address. `…/?user=<id>` becomes
/// `…/?user=<id>#/verify-email` while a new member confirms their e-mail
/// address, and `…#/auth-session` after a sign-out or an account switch. The
/// shell mounts under exactly those routes, so a parser reading the address
/// at that point sees a fragment the visitor never typed and — failing
/// closed, as it must — refuses the very link the person was invited with.
///
/// The app captures the address in its first `initState`, before any route
/// exists, and the shell takes it exactly once: the first signed-in shell of
/// the page load opens the link; a later one (a sign-out and a sign-in, or
/// another account in the same tab) neither opens it again nor apologises
/// for it.
abstract final class AppEntryLink {
  static Uri? _captured;
  static bool _taken = false;

  /// Records the entry URL. Only the first call counts.
  static void capture(Uri uri) {
    _captured ??= uri;
  }

  /// The entry URL while no shell has taken it yet, null afterwards. When
  /// nothing was captured (a native start, a widget test) this is the current
  /// address.
  static Uri? get pending => _taken ? null : (_captured ?? Uri.base);

  /// Hands the entry URL to its first caller and null to every later one.
  static Uri? take() {
    final uri = pending;
    _taken = true;
    return uri;
  }

  @visibleForTesting
  static void resetForTest() {
    _captured = null;
    _taken = false;
  }
}
