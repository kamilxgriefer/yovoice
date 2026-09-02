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
  });

  final AppThemePreference theme;
  final AppLanguagePreference language;
  final bool soundEffectsEnabled;

  AppPreferences copyWith({
    AppThemePreference? theme,
    AppLanguagePreference? language,
    bool? soundEffectsEnabled,
  }) {
    return AppPreferences(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
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
    ]);
    _value = AppPreferences(
      theme: _parseTheme(values[0]),
      language: _parseLanguage(values[1]),
      soundEffectsEnabled: _parseSoundEffects(values[2]),
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

  static bool _parseSoundEffects(String? value) {
    return switch (value) {
      'false' => false,
      'true' || null => true,
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
}
