import 'dart:async';
import 'dart:ui' show Locale;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/preferences/app_preferences.dart'
    show AppPreferencesStore, SharedPreferencesAppPreferencesStore;

/// Tells the server which language this account's app is shown in, so a push
/// can be written in it (ADR-237).
///
/// The value is `users/{uid}.appLanguage`: one of the 43 selectable locale
/// keys (`pl`, `pt_BR`, `zh_TW`, …) — the language actually on screen, so
/// "Use device language" stores the language the device resolved to, never
/// the word "system". Firestore rules accept exactly those keys.
///
/// It is written when it CHANGES, not on every start: the pair
/// `(uid, language)` last confirmed by the server is remembered on the
/// device, and an unchanged pair costs no write. A change of language, a
/// change of device language under "Use device language", a different
/// account signing in on this device, or a first start of a build that knows
/// this field each produce exactly one merge write.
///
/// Best effort by design. A failed write is logged and retried the next time
/// the app resolves its locale; the language of a push is never worth
/// blocking the app for, and an account with no stored language simply keeps
/// receiving English pushes, as every account did before.
class AppLanguageSync {
  AppLanguageSync({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AppPreferencesStore? store,
    void Function(String message)? log,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _store = store ?? SharedPreferencesAppPreferencesStore(),
       _log = log ?? debugPrint;

  static final AppLanguageSync instance = AppLanguageSync();

  /// The users/{uid} field; firestore.rules and
  /// functions/notifications/push_locale.js name the same one.
  static const String field = 'appLanguage';

  /// Remembers the last `(uid, language)` the server confirmed.
  static const String storeKey = 'notifications.app_language.synced.v1';

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final AppPreferencesStore _store;
  final void Function(String message) _log;

  // Resolved lazily: constructing the singleton must not touch Firebase
  // before the app has initialised it.
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? _requestedKey;
  String? _confirmed;
  bool _confirmedLoaded = false;
  bool _isDraining = false;
  Future<void>? _drain;
  StreamSubscription<User?>? _authSubscription;

  static String _pair(String uid, String localeKey) => '$uid|$localeKey';

  /// Records [locale] as the app's language and writes it for the signed-in
  /// account when it differs from what the server already holds. Safe to
  /// call on every build; completes when nothing is left to write.
  Future<void> synchronize(Locale locale) {
    _requestedKey = localizationKeyForLocale(locale);
    try {
      // A sign-in that happens AFTER the locale was resolved still has to
      // store it, and a second account on this device has to store its own.
      _authSubscription ??= _auth.authStateChanges().listen(
        (_) => unawaited(_start()),
        onError: (Object _) {},
      );
    } catch (error) {
      // No Firebase app (a focused widget test, a preview): nothing to sync.
      _log(
        'AppLanguageSync: auth is unavailable (${error.runtimeType}); '
        'the app language is not stored.',
      );
      return Future<void>.value();
    }
    return _start();
  }

  Future<void> _start() {
    if (_isDraining) return _drain!;
    _isDraining = true;
    return _drain = _run();
  }

  Future<void> _run() async {
    try {
      while (true) {
        final localeKey = _requestedKey;
        final uid = _auth.currentUser?.uid;
        if (localeKey == null || uid == null || uid.isEmpty) return;
        final pair = _pair(uid, localeKey);
        if (!_confirmedLoaded) {
          try {
            _confirmed = await _store.read(storeKey);
          } catch (_) {
            // An unreadable store only costs one extra write.
            _confirmed = null;
          }
          _confirmedLoaded = true;
        }
        if (_confirmed == pair) return;
        try {
          await _firestore.collection('users').doc(uid).set(<String, Object?>{
            field: localeKey,
          }, SetOptions(merge: true));
        } catch (error) {
          _log(
            'AppLanguageSync: could not store the app language '
            '(${error.runtimeType}); pushes stay in the previous language '
            'until the next attempt.',
          );
          // Retry at once only when the request itself moved on meanwhile;
          // the same failing write is left for the next locale resolution.
          if (_requestedKey == localeKey && _auth.currentUser?.uid == uid) {
            return;
          }
          continue;
        }
        _confirmed = pair;
        try {
          await _store.write(storeKey, pair);
        } catch (_) {
          // Not remembered: the next start writes the same value again.
        }
        // Loop: the language or the account may have changed meanwhile.
      }
    } finally {
      _isDraining = false;
      _drain = null;
    }
  }

  /// Test seam: stops listening to the auth stream.
  @visibleForTesting
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }
}
