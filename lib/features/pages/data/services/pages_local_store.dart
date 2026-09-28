import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-device, per-account Treści state that never leaves the device:
/// the dismissed "Utwórz swoją stronę" phone card (R5) and the unseen-dot
/// baselines (D10: a local timestamp compared with `lastPostAtMs`, no server
/// read cursor and no counts).
abstract interface class PagesLocalStore {
  Future<bool> createCardDismissed(String userId);
  Future<void> dismissCreateCard(String userId);

  /// The last `lastPostAtMs` the viewer has seen per Page.
  Future<Map<String, int>> seenBaselines(String userId);
  Future<void> writeSeenBaselines(String userId, Map<String, int> baselines);
}

final class SharedPreferencesPagesLocalStore implements PagesLocalStore {
  const SharedPreferencesPagesLocalStore();

  /// Oldest entries are dropped past this many Pages (the follow cap is
  /// 1000, §1.6).
  static const int maxBaselines = 1000;

  static String _cardKey(String userId) =>
      'pages.createCard.dismissed.v1.$userId';
  static String _seenKey(String userId) => 'pages.seen.v1.$userId';

  @override
  Future<bool> createCardDismissed(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_cardKey(userId)) ?? false;
  }

  @override
  Future<void> dismissCreateCard(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_cardKey(userId), true);
  }

  @override
  Future<Map<String, int>> seenBaselines(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_seenKey(userId));
    if (raw == null) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on FormatException {
      return <String, int>{};
    }
  }

  @override
  Future<void> writeSeenBaselines(
    String userId,
    Map<String, int> baselines,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    var entries = baselines.entries.toList();
    if (entries.length > maxBaselines) {
      entries.sort((a, b) => b.value.compareTo(a.value));
      entries = entries.take(maxBaselines).toList();
    }
    await preferences.setString(
      _seenKey(userId),
      jsonEncode(<String, int>{for (final e in entries) e.key: e.value}),
    );
  }
}

/// An in-memory store for tests and previews.
final class MemoryPagesLocalStore implements PagesLocalStore {
  final Set<String> dismissed = <String>{};
  final Map<String, Map<String, int>> baselines = <String, Map<String, int>>{};

  @override
  Future<bool> createCardDismissed(String userId) async =>
      dismissed.contains(userId);

  @override
  Future<void> dismissCreateCard(String userId) async => dismissed.add(userId);

  @override
  Future<Map<String, int>> seenBaselines(String userId) async =>
      Map<String, int>.of(baselines[userId] ?? const <String, int>{});

  @override
  Future<void> writeSeenBaselines(
    String userId,
    Map<String, int> values,
  ) async => baselines[userId] = Map<String, int>.of(values);
}
