import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/localization/translations/translations_startup.dart';

/// One headline for this process, including subsequent auth-loading surfaces.
/// Preparing it never delays rendering or the authentication destination.
abstract final class StartupLaunchCopy {
  static final _session = StartupHeadlineSession();

  static String get headlineKey => _session.headlineKey;

  static Future<void> prepare() => _session.prepare();
}

/// Rotates complete translation keys between launches, not between rebuilds.
///
/// The preferences factory also lets tests exercise slow or unavailable local
/// storage without involving Firebase or changing the app's global session.
class StartupHeadlineSession {
  StartupHeadlineSession({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const preferenceKey = 'startup.headline.last.v1';

  final Future<SharedPreferences> Function() _preferences;
  String? _headlineKey;
  Future<void>? _preparation;

  /// Reading before preferences are ready locks the approved default for this
  /// launch. A late preferences response must never change visible copy.
  String get headlineKey =>
      _headlineKey ??= startupHeadlineTranslationKeys.first;

  Future<void> prepare() => _preparation ??= _readAndRemember();

  Future<void> _readAndRemember() async {
    try {
      final preferences = await _preferences();
      if (_headlineKey == null) {
        final previous = preferences.get(preferenceKey);
        final previousIndex = previous is String
            ? startupHeadlineTranslationKeys.indexOf(previous)
            : -1;
        _headlineKey =
            startupHeadlineTranslationKeys[(previousIndex + 1) %
                startupHeadlineTranslationKeys.length];
      }
      // main() intentionally does not await this best-effort local write.
      // Its result cannot delay, fail, or change the current launch surface.
      await preferences.setString(preferenceKey, headlineKey);
    } catch (_) {
      // A damaged, unavailable, or full preferences store is not an auth error.
      // Keep the already-selected key, or use the same safe default this launch.
      _headlineKey ??= startupHeadlineTranslationKeys.first;
    }
  }
}
