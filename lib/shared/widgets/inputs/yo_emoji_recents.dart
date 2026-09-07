import 'package:flutter/foundation.dart';

import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_catalog.dart';

/// Per-device "recently used" emoji for the composer picker.
///
/// ## Why this is not a field on [AppPreferences]
///
/// [AppPreferencesController] models user *settings* — theme, language, sound
/// effects — each of which is a single enum or flag the Settings screen owns,
/// loaded once at startup and read synchronously everywhere. Recent emoji are
/// none of those things: they are a per-surface interaction history that
/// changes on every tap, is meaningless outside the picker, and would make
/// every consumer of `AppPreferences.value` rebuild on each emoji sent.
///
/// So this follows the established preferences *pattern* rather than joining
/// the preferences *object*: it writes through the same
/// [AppPreferencesStore] interface, uses the same versioned `feature.key.vN`
/// naming, and applies the same optimistic-update-then-roll-back-on-failure
/// discipline. Swapping in an in-memory store is what makes it testable, which
/// is exactly why that interface exists.
class YoEmojiRecentsStore extends ChangeNotifier {
  YoEmojiRecentsStore({AppPreferencesStore? store})
    : _store = store ?? SharedPreferencesAppPreferencesStore();

  /// Shared by every composer, so an emoji used in a direct message is already
  /// waiting in the room chat sheet.
  static final instance = YoEmojiRecentsStore();

  static const _key = 'composer.recent_emoji.v1';

  /// One row on the narrowest supported width still shows six cells, and a
  /// history longer than the row is history nobody can see.
  static const maxEntries = 24;

  /// A space can never appear inside an emoji sequence — not in a ZWJ
  /// sequence, a keycap, or a regional-indicator flag — so it is a separator
  /// that cannot corrupt a stored entry.
  static const _separator = ' ';

  final AppPreferencesStore _store;

  List<String> _value = const [];
  bool _loaded = false;

  /// Most recently used first.
  List<String> get value => _value;

  bool get isLoaded => _loaded;

  /// Recents resolved against the catalogue, dropping anything the catalogue
  /// no longer offers. That drop matters: it is what stops a persisted emoji
  /// from outliving a future narrowing of the platform-support ceiling.
  List<YoEmoji> get emoji => [
    for (final char in _value)
      if (yoEmojiByChar[char] != null) yoEmojiByChar[char]!,
  ];

  Future<void> load() async {
    if (_loaded) return;
    String? stored;
    try {
      stored = await _store.read(_key);
    } catch (_) {
      // A device whose preference store is unavailable still gets a working
      // picker; it just starts with no history.
      stored = null;
    }
    _value = _parse(stored);
    _loaded = true;
    notifyListeners();
  }

  /// Moves [char] to the front, de-duplicating and trimming to [maxEntries].
  Future<void> register(String char) async {
    if (char.isEmpty) return;
    final previous = _value;
    final next = <String>[
      char,
      ...previous.where((candidate) => candidate != char),
    ];
    if (next.length > maxEntries) next.removeRange(maxEntries, next.length);
    if (listEquals(next, previous)) return;
    _value = List<String>.unmodifiable(next);
    _loaded = true;
    notifyListeners();
    try {
      await _store.write(_key, next.join(_separator));
    } catch (_) {
      // The picker stays usable for this session; only persistence is lost.
      _value = previous;
      notifyListeners();
    }
  }

  static List<String> _parse(String? stored) {
    if (stored == null || stored.isEmpty) return const [];
    final parsed = stored
        .split(_separator)
        .where((entry) => entry.isNotEmpty && yoEmojiByChar.containsKey(entry))
        .toList(growable: false);
    return List<String>.unmodifiable(
      parsed.length > maxEntries ? parsed.sublist(0, maxEntries) : parsed,
    );
  }

  /// Test seam: an in-memory store so a widget test never touches
  /// `SharedPreferences`.
  @visibleForTesting
  static YoEmojiRecentsStore inMemory({List<String> initial = const []}) {
    final store = _InMemoryEmojiStore(
      initial.isEmpty ? null : initial.join(_separator),
    );
    return YoEmojiRecentsStore(store: store);
  }
}

class _InMemoryEmojiStore implements AppPreferencesStore {
  _InMemoryEmojiStore(this._value);

  String? _value;

  @override
  Future<String?> read(String key) async => _value;

  @override
  Future<void> write(String key, String value) async => _value = value;
}
