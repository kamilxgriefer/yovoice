/// Pure, platform-free parsing of an IANA timezone name into the two
/// strings the sidebar card renders.
///
/// Kept out of the interop files ON PURPOSE, the same way
/// `web_mime_negotiation.dart` is kept out of `audio_capture_web.dart`:
/// anything importing `dart:js_interop` cannot be reached by the VM test
/// runner, so the logic worth testing lives here where a plain
/// `flutter test` can drive it.
library;

/// What the app actually knows about where someone is — never more.
///
/// PRIVACY IS THE SHAPE OF THIS CLASS, not a policy bolted onto it. There
/// is no latitude, no longitude, no city, no country and no IP anywhere in
/// it, because none of those are collected. A timezone is a band of
/// longitude shared by tens of millions of people; that is the whole
/// resolution this feature has, and the map is drawn to match.
class TimezoneReading {
  const TimezoneReading({
    required this.offset,
    this.ianaName,
    this.platformLabel,
  });

  /// Always available, on every platform: `DateTime.now().timeZoneOffset`.
  final Duration offset;

  /// `Europe/Warsaw` on web, where the browser reports it. Null elsewhere.
  final String? ianaName;

  /// `DateTime.now().timeZoneName` — a long name on macOS ("Central
  /// European Summer Time"), an abbreviation on most other platforms, and
  /// occasionally a bare numeric offset. Null when it is not usable.
  final String? platformLabel;

  /// The prominent line: a place-ish word when one is genuinely known,
  /// never invented.
  ///
  /// Order, and why: the IANA city is the most specific thing the browser
  /// actually told us; the platform label is next because it is a real
  /// zone name rather than a guess; the UTC offset is the honest floor.
  String get primaryLabel {
    final city = ianaCity;
    if (city != null) return city;
    final platform = platformLabel?.trim();
    if (platform != null && platform.isNotEmpty && !_looksNumeric(platform)) {
      return platform;
    }
    return utcOffsetLabel(offset);
  }

  /// The quiet second line: the IANA region, or nothing.
  ///
  /// Returns null rather than a filler string — the card renders the row
  /// only when there is something true to put in it.
  String? get regionLabel => ianaRegion;

  /// `Europe/Warsaw` -> `Warsaw`; `America/Argentina/Buenos_Aires` ->
  /// `Buenos Aires`. Null when no IANA name was resolved, and null for
  /// the special zones that name no place.
  String? get ianaCity {
    final name = ianaName?.trim();
    if (name == null || name.isEmpty) return null;
    if (!name.contains('/')) return null;
    final segments = name.split('/');
    final last = segments.last.replaceAll('_', ' ').trim();
    return last.isEmpty ? null : last;
  }

  /// `Europe/Warsaw` -> `Europe`. Null when no IANA name was resolved.
  String? get ianaRegion {
    final name = ianaName?.trim();
    if (name == null || name.isEmpty) return null;
    if (!name.contains('/')) return null;
    final first = name.split('/').first.replaceAll('_', ' ').trim();
    return first.isEmpty ? null : first;
  }

  static bool _looksNumeric(String value) =>
      RegExp(r'^[+-]?\d').hasMatch(value) ||
      value.toUpperCase().startsWith('GMT') && RegExp(r'\d').hasMatch(value);

  /// `UTC+02:00`. The one label that is always derivable, on every
  /// platform, with no interop and no lookup.
  static String utcOffsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final hours = absolute.inHours.toString().padLeft(2, '0');
    final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }
}
