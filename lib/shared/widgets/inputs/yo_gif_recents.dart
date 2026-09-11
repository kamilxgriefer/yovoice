import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';

/// Per-device "recently used" GIFs for the composer picker.
///
/// Mirrors [YoEmojiRecentsStore] line for line — same [AppPreferencesStore]
/// seam, same versioned `feature.key.vN` naming, same
/// optimistic-write-then-roll-back discipline, same in-memory test seam — for
/// the same reason: this is an interaction history that changes on every tap,
/// not a user setting the Settings screen owns, so it follows the preferences
/// PATTERN without joining the preferences OBJECT.
///
/// ## Recents never leave the device
///
/// This is a privacy property, not an implementation detail. The server keeps
/// no per-user GIF history — a search reaches the proxy with no identifier
/// attached to it beyond the caller's auth, and nothing per-account is stored.
/// Recents live in `SharedPreferences` and nowhere else, exactly like emoji
/// recents, and they are what makes the picker feel personal without anybody
/// holding a record of what somebody sends.
///
/// The stored value is JSON rather than the emoji store's separator-joined
/// string, because a GIF entry is a record (provider, id, title, dimensions)
/// and a title can contain any character a separator might have used.
class YoGifRecentsStore extends ChangeNotifier {
  YoGifRecentsStore({AppPreferencesStore? store})
    : _store = store ?? SharedPreferencesAppPreferencesStore();

  /// Shared by every composer, so a GIF sent in a club is already waiting in
  /// the room chat sheet.
  static final instance = YoGifRecentsStore();

  static const _key = 'composer.recent_gifs.v1';

  /// The same cap as emoji recents. A history longer than the row is history
  /// nobody can see.
  static const maxEntries = 24;

  final AppPreferencesStore _store;

  List<GifAsset> _value = const <GifAsset>[];
  bool _loaded = false;

  /// Most recently used first.
  List<GifAsset> get value => _value;

  bool get isLoaded => _loaded;

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

  /// Moves [asset] to the front, de-duplicating and trimming to [maxEntries].
  Future<void> register(GifAsset asset) async {
    final previous = _value;
    final next = <GifAsset>[
      asset,
      ...previous.where((candidate) => candidate != asset),
    ];
    if (next.length > maxEntries) next.removeRange(maxEntries, next.length);
    _value = List<GifAsset>.unmodifiable(next);
    _loaded = true;
    notifyListeners();
    try {
      await _store.write(_key, _encode(next));
    } catch (_) {
      // The picker stays usable for this session; only persistence is lost.
      _value = previous;
      notifyListeners();
    }
  }

  /// Forget one asset — used when a person reports it, so the thing they just
  /// objected to is not waiting for them the next time they open the picker.
  Future<void> forget(GifAsset asset) async {
    if (!_value.contains(asset)) return;
    final previous = _value;
    final next = previous.where((candidate) => candidate != asset).toList();
    _value = List<GifAsset>.unmodifiable(next);
    notifyListeners();
    try {
      await _store.write(_key, _encode(next));
    } catch (_) {
      _value = previous;
      notifyListeners();
    }
  }

  static String _encode(List<GifAsset> assets) =>
      jsonEncode(assets.map((asset) => asset.toWire()).toList());

  static List<GifAsset> _parse(String? stored) {
    if (stored == null || stored.isEmpty) return const <GifAsset>[];
    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } catch (_) {
      // A value written by a future version, or a corrupted one. Starting
      // empty is correct; throwing here would break the picker for good.
      return const <GifAsset>[];
    }
    if (decoded is! List) return const <GifAsset>[];
    final parsed = <GifAsset>[];
    for (final entry in decoded) {
      final asset = GifAsset.fromWire(entry);
      if (asset != null && !parsed.contains(asset)) parsed.add(asset);
      if (parsed.length >= maxEntries) break;
    }
    return List<GifAsset>.unmodifiable(parsed);
  }

  /// Test seam: an in-memory store so a widget test never touches
  /// `SharedPreferences`.
  @visibleForTesting
  static YoGifRecentsStore inMemory({List<GifAsset> initial = const []}) {
    return YoGifRecentsStore(
      store: _InMemoryGifStore(initial.isEmpty ? null : _encode(initial)),
    );
  }
}

class _InMemoryGifStore implements AppPreferencesStore {
  _InMemoryGifStore(this._value);

  String? _value;

  @override
  Future<String?> read(String key) async => _value;

  @override
  Future<void> write(String key, String value) async => _value = value;
}
