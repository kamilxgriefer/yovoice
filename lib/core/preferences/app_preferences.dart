import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_language.dart';

export 'package:yovoice/core/localization/app_language.dart';

enum AppThemePreference {
  system,
  dark,
  light;

  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.dark => ThemeMode.dark,
    AppThemePreference.light => ThemeMode.light,
  };
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.theme = AppThemePreference.dark,
    this.language = AppLanguagePreference.system,
    this.soundEffectsEnabled = true,
    this.gifAutoLoadEnabled = true,
    this.bugReportButtonVisible = true,
  });

  final AppThemePreference theme;
  final AppLanguagePreference language;
  final bool soundEffectsEnabled;

  /// Whether remote GIFs load as soon as they appear.
  ///
  /// YO Voice Originals are packaged with the app and always play
  /// automatically without contacting a third-party provider. If an optional
  /// remote provider is enabled, off means a placeholder carrying the stored
  /// title and no provider request until the person deliberately taps to load
  /// it. The preference covers external assets in the picker grid, the recents
  /// row and received GIF bubbles alike.
  ///
  /// Default on, matching [soundEffectsEnabled], so optional external GIFs
  /// retain the expected automatic-loading behavior.
  final bool gifAutoLoadEnabled;

  /// Whether the movable "Bug" button floats over the app on this device.
  ///
  /// Only consulted in builds that compile the button in at all
  /// (`YOVOICE_BUG_BUTTON`, see `bug_report_config.dart`). Default on, so a
  /// tester sees it without looking for it; turning it off here, or with the
  /// button's own long-press, hides it on this device only. "Report a bug" in
  /// Settings and the More menu stays available either way.
  final bool bugReportButtonVisible;

  AppPreferences copyWith({
    AppThemePreference? theme,
    AppLanguagePreference? language,
    bool? soundEffectsEnabled,
    bool? gifAutoLoadEnabled,
    bool? bugReportButtonVisible,
  }) {
    return AppPreferences(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      gifAutoLoadEnabled: gifAutoLoadEnabled ?? this.gifAutoLoadEnabled,
      bugReportButtonVisible:
          bugReportButtonVisible ?? this.bugReportButtonVisible,
    );
  }
}

abstract interface class AppPreferencesStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesAppPreferencesStore implements AppPreferencesStore {
  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, value);
    if (!saved) {
      throw StateError('Could not persist $key.');
    }
  }
}

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({
    required AppPreferencesStore store,
    AppPreferences initialValue = const AppPreferences(),
  }) : _store = store,
       _value = initialValue;

  static const _themeKey = 'appearance.theme.v1';
  static const _languageKey = 'appearance.language.v1';
  static const _soundEffectsKey = 'audio.sound_effects.enabled.v1';
  static const _gifAutoLoadKey = 'media.gif_auto_load.enabled.v1';
  static const _bugReportButtonKey = 'testing.bug_report_button.visible.v1';

  static final instance = AppPreferencesController(
    store: SharedPreferencesAppPreferencesStore(),
  );

  final AppPreferencesStore _store;
  AppPreferences _value;
  bool _loaded = false;

  AppPreferences get value => _value;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final values = await Future.wait([
      _store.read(_themeKey),
      _store.read(_languageKey),
      _store.read(_soundEffectsKey),
      _store.read(_gifAutoLoadKey),
      _store.read(_bugReportButtonKey),
    ]);
    _value = AppPreferences(
      theme: _parseTheme(values[0]),
      language: _parseLanguage(values[1]),
      soundEffectsEnabled: _parseSoundEffects(values[2]),
      gifAutoLoadEnabled: _parseFlag(values[3]),
      bugReportButtonVisible: _parseFlag(values[4]),
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setTheme(AppThemePreference theme) async {
    if (_value.theme == theme) return;
    final previous = _value;
    _value = _value.copyWith(theme: theme);
    notifyListeners();
    try {
      await _store.write(_themeKey, theme.name);
    } catch (_) {
      _value = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setLanguage(AppLanguagePreference language) async {
    if (_value.language == language) return;
    final previous = _value;
    _value = _value.copyWith(language: language);
    notifyListeners();
    try {
      await _store.write(_languageKey, language.name);
    } catch (_) {
      _value = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    if (_value.soundEffectsEnabled == enabled) return;
    final previous = _value;
    _value = _value.copyWith(soundEffectsEnabled: enabled);
    notifyListeners();
    try {
      await _store.write(_soundEffectsKey, enabled.toString());
    } catch (_) {
      _value = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setGifAutoLoadEnabled(bool enabled) async {
    if (_value.gifAutoLoadEnabled == enabled) return;
    final previous = _value;
    _value = _value.copyWith(gifAutoLoadEnabled: enabled);
    notifyListeners();
    try {
      await _store.write(_gifAutoLoadKey, enabled.toString());
    } catch (_) {
      _value = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setBugReportButtonVisible(bool visible) async {
    if (_value.bugReportButtonVisible == visible) return;
    final previous = _value;
    _value = _value.copyWith(bugReportButtonVisible: visible);
    notifyListeners();
    try {
      await _store.write(_bugReportButtonKey, visible.toString());
    } catch (_) {
      _value = previous;
      notifyListeners();
      rethrow;
    }
  }

  static AppThemePreference _parseTheme(String? value) {
    return AppThemePreference.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => AppThemePreference.dark,
    );
  }

  static AppLanguagePreference _parseLanguage(String? value) {
    if (value == null) return AppLanguagePreference.system;
    return AppLanguagePreference.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => AppLanguagePreference.english,
    );
  }

  static bool _parseSoundEffects(String? value) => _parseFlag(value);

  /// Absent, unreadable and unrecognised all mean the default (on). A
  /// preference store that cannot be read must never silently turn a feature
  /// off — the person would have no way to tell that from the feature being
  /// broken.
  static bool _parseFlag(String? value) {
    return switch (value) {
      'false' => false,
      _ => true,
    };
  }
}

class AppPreferencesScope extends InheritedNotifier<AppPreferencesController> {
  const AppPreferencesScope({
    required AppPreferencesController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppPreferencesController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppPreferencesScope>();
    assert(scope != null, 'No AppPreferencesScope found in this context.');
    return scope!.notifier!;
  }

  /// The controller, or null where no scope has been installed.
  ///
  /// [of] is right for a screen that cannot work without preferences. This is
  /// for a widget that merely READS one and has an honest default — a shared
  /// composer widget, say, which is also mounted by focused widget tests that
  /// have no reason to build the whole app shell. Asserting there would make
  /// every such test install a scope to exercise something unrelated.
  static AppPreferencesController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppPreferencesScope>()
        ?.notifier;
  }
}
