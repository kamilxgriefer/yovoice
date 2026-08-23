@JS()
library;

import 'dart:js_interop';

/// `Intl.DateTimeFormat().resolvedOptions()` — the browser's own answer to
/// "which zone is this machine in".
///
/// The `@JS('Intl.DateTimeFormat')` binding is load-bearing: an
/// `external factory` on a bare extension type has no idea which global
/// constructor it names, so without it the call resolves to nothing and
/// this function silently returns null — which is exactly how it failed
/// the first time, in a browser that reported `Europe/Amsterdam` perfectly
/// well from the console.
@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external String? get timeZone;
}

/// The browser's IANA zone name, e.g. `Europe/Warsaw`.
///
/// THIS IS NOT GEOLOCATION. It reads a setting the browser already exposes
/// to every page without a permission prompt; it never touches
/// `navigator.geolocation`, never makes a network request, and never sees
/// an IP address. A wrong or spoofed system clock simply yields a
/// different zone name, which is the user's own business.
///
/// Wrapped in a try/catch because a hardened or unusual runtime can throw
/// or report an empty string here; the caller then falls back to
/// `DateTime.now().timeZoneName` and finally to the raw UTC offset.
String? readPlatformIanaTimezone() {
  try {
    final resolved = _DateTimeFormat().resolvedOptions().timeZone?.trim();
    if (resolved == null || resolved.isEmpty) return null;
    return resolved;
  } catch (_) {
    return null;
  }
}
