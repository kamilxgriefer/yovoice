/// Native builds have no IANA timezone name to offer.
///
/// `DateTime.now().timeZoneName` already gives a usable zone label on
/// every native platform, and the card falls back to it — so this returns
/// null rather than pulling in a timezone database for one sidebar line.
String? readPlatformIanaTimezone() => null;
