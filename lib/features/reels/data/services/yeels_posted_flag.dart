import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where "this account has published a Yeel" is remembered on this device.
abstract interface class YeelsPostedStore {
  Future<bool> read(String userId);
  Future<void> write(String userId);
}

/// The device-local store: one boolean per account.
///
/// Local on purpose. The flag only retires the create ring's invitation
/// echo (ADR-229), so it needs no backend field, and a fresh install that
/// forgets it merely shows a few gentle echoes again until the feed or the
/// composer confirms the account has Yeels.
final class SharedPreferencesYeelsPostedStore implements YeelsPostedStore {
  const SharedPreferencesYeelsPostedStore();

  @visibleForTesting
  static String keyFor(String userId) =>
      'yeels.create_invitation.posted.v1.$userId';

  @override
  Future<bool> read(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(keyFor(userId)) ?? false;
  }

  @override
  Future<void> write(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(keyFor(userId), true);
    if (!saved) throw StateError('Could not persist the Yeels posted flag.');
  }
}

/// Whether an account has published a Yeel, as far as this device knows.
///
/// Set when the Yeel composer completes a publish, and when a feed the app
/// already loaded shows the viewer's own Yeel — no new backend call. Kept in
/// memory as well, so a publish silences the invitation at once even when
/// the store cannot be written; listeners hear about every account newly
/// marked.
///
/// A store that cannot be read counts as "not known to have posted": the
/// only consequence is the bounded invitation echo, never a lost feature.
class YeelsPostedFlag extends ChangeNotifier {
  YeelsPostedFlag({YeelsPostedStore? store})
    : _store = store ?? const SharedPreferencesYeelsPostedStore();

  /// The app-wide flag the composer and the Yeels destination share.
  static final YeelsPostedFlag instance = YeelsPostedFlag();

  final YeelsPostedStore _store;
  final Set<String> _posted = <String>{};

  /// True when this session already knows [userId] has posted.
  bool knows(String userId) => _posted.contains(userId.trim());

  /// Whether [userId] has posted: memory first, then the store.
  Future<bool> hasPosted(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return false;
    if (_posted.contains(id)) return true;
    try {
      if (await _store.read(id)) _posted.add(id);
    } catch (_) {
      // Unreadable (no plugin in a test host, a damaged store): see the
      // class docs — treated as not known.
    }
    return _posted.contains(id);
  }

  /// Records that [userId] has published a Yeel.
  Future<void> markPosted(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || !_posted.add(id)) return;
    notifyListeners();
    try {
      await _store.write(id);
    } catch (_) {
      // The memory flag already holds for this session; the next launch
      // learns it again from the feed or the next publish.
    }
  }
}
