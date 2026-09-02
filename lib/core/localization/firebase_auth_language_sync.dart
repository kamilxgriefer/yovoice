import 'dart:ui' show Locale;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

typedef FirebaseAuthLanguageSetter = Future<void> Function(String languageCode);

/// Serializes Firebase Auth language updates and exposes a readiness boundary
/// for operations that can show provider UI or send localized email.
///
/// Locale changes can arrive while a platform update is still in flight. The
/// drain always applies the latest requested locale before [ready] completes,
/// so an auth action never races an older language request.
class FirebaseAuthLanguageSync {
  FirebaseAuthLanguageSync({
    FirebaseAuthLanguageSetter? setLanguageCode,
    void Function(String message)? log,
  }) : _setLanguageCode =
           setLanguageCode ??
           ((languageCode) {
             return FirebaseAuth.instance.setLanguageCode(languageCode);
           }),
       _log = log ?? debugPrint;

  static final FirebaseAuthLanguageSync instance = FirebaseAuthLanguageSync();

  final FirebaseAuthLanguageSetter _setLanguageCode;
  final void Function(String message) _log;

  String? _requestedLanguageCode;
  String? _appliedLanguageCode;
  bool _isDraining = false;
  Future<void>? _readiness;

  /// Requests the locale used by Firebase Auth and completes after the latest
  /// queued request has either been applied or failed best-effort.
  Future<void> synchronize(Locale locale) {
    _requestedLanguageCode = locale.toLanguageTag();
    if (_requestedLanguageCode == _appliedLanguageCode && !_isDraining) {
      return Future<void>.value();
    }

    if (!_isDraining) {
      _isDraining = true;
      _readiness = _drain();
    }
    return _readiness!;
  }

  /// Completes only when every locale request currently queued by the app has
  /// reached Firebase Auth. Failures are logged and do not block sign-in.
  Future<void> get ready => _readiness ?? Future<void>.value();

  Future<void> _drain() async {
    try {
      while (true) {
        final languageCode = _requestedLanguageCode;
        if (languageCode == null || languageCode == _appliedLanguageCode) {
          return;
        }

        try {
          await _setLanguageCode(languageCode);
          _appliedLanguageCode = languageCode;
        } catch (error) {
          _log(
            'FirebaseAuthLanguageSync: could not apply $languageCode '
            '(${error.runtimeType}).',
          );
          return;
        }
      }
    } finally {
      _isDraining = false;
      _readiness = null;
    }
  }
}
