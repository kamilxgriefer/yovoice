import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/media/data/services/giphy_client.dart';

/// Where the per-install GIPHY random id lives.
abstract interface class GiphyRandomIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesGiphyRandomIdStore implements GiphyRandomIdStore {
  const SharedPreferencesGiphyRandomIdStore();

  /// Device-local only. It is never written to Firestore or sent to YO Voice,
  /// and it is not derived from the account, so it cannot link GIPHY's
  /// analytics back to a YO Voice identity.
  static const key = 'media.giphy.random_id.v1';

  @override
  Future<String?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
    } catch (_) {
      // A lost id costs one more /randomid call next time, nothing else.
    }
  }
}

/// The three GIPHY Action Register events.
enum GiphyPingbackEvent { onLoad, onClick, onSent }

/// GIPHY Action Register pingbacks (ADR-213).
///
/// GIPHY's API terms ask integrations to register `onload` when a result is
/// shown, `onclick` when one is chosen and `onsent` when it is sent, each
/// tagged with a stable per-install id (a GIPHY `random_id`, sent as the
/// `customer_id` parameter the current docs name) and a millisecond timestamp.
///
/// ## Gated on "Load GIFs automatically"
///
/// Every public method takes `enabled`, which callers pass from
/// `AppPreferences.gifAutoLoadEnabled`. Off means NO pingback of any kind and
/// no `/randomid` request: that setting is the person's switch for contact with
/// GIPHY, and analytics beacons are contact.
///
/// ## Exactly once
///
/// `onload` is registered once per result per [GiphyPingbacks] (a picker
/// session), however often a scrolling grid rebuilds its cell. `onclick` fires
/// per deliberate choice. `onsent` fires only for a choice that was armed by a
/// click while enabled, and only once, when the send succeeds.
class GiphyPingbacks {
  GiphyPingbacks({
    required GiphyClient client,
    GiphyRandomIdStore store = const SharedPreferencesGiphyRandomIdStore(),
    DateTime Function()? clock,
  }) : _client = client,
       _store = store,
       _clock = clock ?? DateTime.now;

  final GiphyClient _client;
  final GiphyRandomIdStore _store;
  final DateTime Function() _clock;

  final Map<String, GiphyAnalytics> _analytics = <String, GiphyAnalytics>{};
  final Set<String> _loaded = <String>{};
  final Map<String, Uri> _armedSends = <String, Uri>{};
  Future<String?>? _randomId;

  static const int _capacity = 400;

  /// Remember the analytics URLs a page of results came with.
  void remember(Iterable<GiphyResult> results) {
    for (final result in results) {
      _analytics[result.asset.id] = result.analytics;
    }
    while (_analytics.length > _capacity) {
      _analytics.remove(_analytics.keys.first);
    }
  }

  /// A result became visible in the picker.
  Future<void> loaded(String gifId, {required bool enabled}) async {
    if (!enabled || _loaded.contains(gifId)) return;
    final url = _analytics[gifId]?.onLoad;
    if (url == null) return;
    _loaded.add(gifId);
    await _fire(url);
  }

  /// A result was chosen. Arms the matching `onsent` for a later success.
  Future<void> clicked(String gifId, {required bool enabled}) async {
    if (!enabled) {
      _armedSends.remove(gifId);
      return;
    }
    final analytics = _analytics[gifId];
    if (analytics == null) return;
    final sent = analytics.onSent;
    if (sent != null) _armedSends[gifId] = sent;
    final click = analytics.onClick;
    if (click != null) await _fire(click);
  }

  /// The message carrying [gifId] was committed by the server.
  Future<void> sent(String gifId) async {
    final url = _armedSends.remove(gifId);
    if (url != null) await _fire(url);
  }

  /// The choice was abandoned (resolve refused, send discarded).
  void disarm(String gifId) => _armedSends.remove(gifId);

  Future<void> _fire(Uri url) async {
    final id = await (_randomId ??= _loadRandomId());
    if (id == null) {
      // Retry the id next time rather than pinning a failure for the session.
      _randomId = null;
      return;
    }
    final tagged = url.replace(
      queryParameters: <String, String>{
        ...url.queryParameters,
        'customer_id': id,
        'ts': '${_clock().millisecondsSinceEpoch}',
      },
    );
    await _client.ping(tagged);
  }

  Future<String?> _loadRandomId() async {
    final stored = await _store.read();
    if (stored != null && stored.isNotEmpty) return stored;
    final fetched = await _client.randomId();
    if (fetched != null) await _store.write(fetched);
    return fetched;
  }
}

/// The app-wide pingback registry, shared by the picker (which sees `onload`
/// and `onclick`) and the send controllers (which see `onsent`). Null when the
/// build carries no GIPHY key, which makes every call site a no-op.
class GiphyPingbackRegistry {
  GiphyPingbackRegistry._();

  static GiphyPingbacks? _instance;
  static bool _initialized = false;

  static GiphyPingbacks? get instance {
    if (!_initialized) {
      _initialized = true;
      final client = GiphyClient.fromEnvironment();
      _instance = client == null ? null : GiphyPingbacks(client: client);
    }
    return _instance;
  }

  /// Test seam.
  static set instance(GiphyPingbacks? value) {
    _initialized = true;
    _instance = value;
  }
}
