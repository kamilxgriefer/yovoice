import 'package:flutter/foundation.dart';

typedef EphemeralMediaAccessClear = void Function();

/// Process-wide logout boundary for short-lived media capabilities.
///
/// AuthService already owns the single logout hook through MomentService.
/// Individual media domains register here so adding another capability cache
/// cannot silently leave a signed URL alive after an account switch.
abstract final class EphemeralMediaAccessRegistry {
  static final Map<String, EphemeralMediaAccessClear> _clearers = {};

  static void register(String domain, EphemeralMediaAccessClear clear) {
    if (domain.trim().isEmpty) {
      throw ArgumentError.value(domain, 'domain', 'must not be empty');
    }
    _clearers[domain] = clear;
  }

  static void unregister(String domain) {
    _clearers.remove(domain);
  }

  static void clearAll() {
    for (final entry in List.of(_clearers.entries)) {
      try {
        entry.value();
      } catch (error, stackTrace) {
        // One domain must not prevent the remaining bearer caches from being
        // revoked during logout. Cache clearers are synchronous and should
        // never throw, so retain a debug signal for implementation mistakes.
        debugPrint(
          '[SECURITY] Failed to clear ${entry.key} media access: $error\n'
          '$stackTrace',
        );
      }
    }
  }

  @visibleForTesting
  static Set<String> get registeredDomains => Set.unmodifiable(_clearers.keys);
}
