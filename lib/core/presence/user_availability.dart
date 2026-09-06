import 'package:yovoice/core/localization/app_localizations.dart';

/// The availability a user chooses for themselves.
///
/// Stored as `users/{uid}.availability` (owner-written, validated by rules).
/// Everyone else only ever sees the projected form in `socialPresence`:
/// `invisible` — and any state while offline — is projected as plain
/// offline, so an invisible account cannot be told apart from a signed-out
/// one. See ADR-150.
enum UserAvailability {
  available('available'),
  away('away'),
  busy('busy'),
  invisible('invisible');

  const UserAvailability(this.wire);

  /// The exact Firestore value.
  final String wire;

  /// Tolerant parse: unknown or missing values are `available`, which is
  /// what every account was before the field existed.
  static UserAvailability fromWire(Object? value) {
    for (final option in values) {
      if (option.wire == value) return option;
    }
    return UserAvailability.available;
  }

  String localizedLabel(AppLocalizations copy) => switch (this) {
    UserAvailability.available => copy.text('Available', 'Dostępny'),
    UserAvailability.away => copy.text('Be right back', 'Zaraz wracam'),
    UserAvailability.busy => copy.text('Do not disturb', 'Nie przeszkadzać'),
    UserAvailability.invisible => copy.text('Invisible', 'Niewidoczny'),
  };

  String localizedHint(AppLocalizations copy) => switch (this) {
    UserAvailability.available => copy.text(
      'Friends see a green ring.',
      'Znajomi widzą zielony pierścień.',
    ),
    UserAvailability.away => copy.text(
      'Friends see a yellow ring.',
      'Znajomi widzą żółty pierścień.',
    ),
    UserAvailability.busy => copy.text(
      'Friends see a red ring.',
      'Znajomi widzą czerwony pierścień.',
    ),
    UserAvailability.invisible => copy.text(
      'You appear offline to everyone.',
      'Dla wszystkich wyglądasz jak offline.',
    ),
  };
}
