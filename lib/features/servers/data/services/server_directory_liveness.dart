import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import 'server_service.dart';

/// Which of the account's servers have a conversation live right now — the
/// one source for the LIVE lamp on the Servers board's "Twoje serwery" rows.
///
/// Every answer comes from the server-owned liveness projection on the
/// channel document (ADR-177: `{isLive, startedAt}`) that the workspace and
/// Start's "Na żywo teraz" already read through
/// [ServerRepository.watchChannels]. A server is live exactly when one of its
/// media channels (voice, stage, meeting) says so and carries the instant it
/// started; there is no participant or viewer count in that projection and
/// none is derived here.
///
/// **Bounded by construction**, like `HomeLiveNowSection`: only the first
/// [budget] servers of the directory get a channel listener, keyed by server
/// id so a rebuild never resubscribes. A legacy club and a held server have
/// no projection and are never watched. A server whose channels fail to read
/// simply has no lamp.
///
/// **Retained slots.** The desktop shell keeps the Servers slot built inside
/// an `IndexedStack`, the board stays mounted under a server it hosts
/// inline, and on a phone it stays mounted under every full-screen route
/// pushed over it — the workspace of the server a person has just opened
/// first of all. While [isVisible] is false, the board says it is not on
/// screen ([track] with `active: false`) or a route covers it ([covered]),
/// every listener is cancelled AND every answer is dropped: a lamp is a
/// claim about now, so a hidden board never carries one back from the past.
/// The first snapshot after it returns lights it again.
class ServerDirectoryLiveness extends ChangeNotifier {
  ServerDirectoryLiveness({
    required ServerRepository repository,
    ValueListenable<bool>? isVisible,
  }) : _repository = repository,
       _isVisible = isVisible {
    _isVisible?.addListener(_sync);
  }

  /// How many servers get a channel listener.
  static const int budget = 8;

  final ServerRepository _repository;
  final ValueListenable<bool>? _isVisible;

  List<String> _tracked = const [];
  bool _boardActive = true;
  bool _covered = false;
  bool _disposed = false;

  final _subscriptions = <String, StreamSubscription<List<ServerChannel>>>{};
  final _liveSince = <String, DateTime>{};

  /// Servers whose repository refused to list channels; not asked again
  /// until the board comes back on screen.
  final _refused = <String>{};

  bool get _active => _boardActive && !_covered && (_isVisible?.value ?? true);

  /// Whether a full-screen route covers the board.
  ///
  /// On a phone a server opens as a pushed route, and the board stays built
  /// under it for the whole visit. Without this the board kept up to
  /// [budget] channel listeners running behind a screen nobody could see,
  /// next to the ones the open workspace holds itself. The board feeds it
  /// from the ambient `TickerMode`, which `Overlay` switches off for every
  /// route below an opaque one — whichever route that is, and through any
  /// chain of replacements — and never for a sheet or a dialog.
  bool get covered => _covered;
  set covered(bool value) {
    if (_disposed || _covered == value) return;
    _covered = value;
    _sync();
  }

  /// Whether [serverId] has a live conversation.
  bool isLive(String serverId) => _liveSince.containsKey(serverId);

  /// When the server's most recent live conversation started, if any.
  DateTime? liveSince(String serverId) => _liveSince[serverId];

  /// Every listener currently open, for tests and diagnostics.
  @visibleForTesting
  int get openWatches => _subscriptions.length;

  /// Whether a server can carry the projection at all.
  static bool eligible(Server server) => !server.isLegacy && !server.isHeld;

  /// The account's servers in directory order, and whether the board that
  /// shows them is on screen.
  void track(Iterable<Server> servers, {bool active = true}) {
    if (_disposed) return;
    final next = [
      for (final server in servers)
        if (eligible(server)) server.id,
    ].take(budget).toList(growable: false);
    if (listEquals(next, _tracked) && active == _boardActive) return;
    _tracked = next;
    _boardActive = active;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final wanted = _active ? _tracked.toSet() : const <String>{};
    var changed = false;
    for (final id in _subscriptions.keys.toList()) {
      if (wanted.contains(id)) continue;
      unawaited(_subscriptions.remove(id)?.cancel());
      if (_liveSince.remove(id) != null) changed = true;
    }
    if (!_active) _refused.clear();
    for (final id in wanted) {
      if (_subscriptions.containsKey(id) || _refused.contains(id)) continue;
      try {
        _subscriptions[id] = _repository
            .watchChannels(id)
            .listen(
              (channels) => _set(id, _newestLive(channels)),
              onError: (Object _, StackTrace _) => _set(id, null),
            );
      } on Object {
        // A repository that cannot list this server's channels (or hands
        // out a stream that takes no listener) is a server with no lamp.
        _refused.add(id);
      }
    }
    if (changed) _notifySoon();
  }

  static DateTime? _newestLive(List<ServerChannel> channels) {
    DateTime? newest;
    for (final channel in channels) {
      final startedAt = channel.liveness.startedAt;
      if (!channel.kind.isMedia ||
          !channel.liveness.isLive ||
          startedAt == null) {
        continue;
      }
      if (newest == null || startedAt.isAfter(newest)) newest = startedAt;
    }
    return newest;
  }

  void _set(String id, DateTime? since) {
    if (_disposed || !_subscriptions.containsKey(id)) return;
    if (_liveSince[id] == since) return;
    if (since == null) {
      _liveSince.remove(id);
    } else {
      _liveSince[id] = since;
    }
    _notifySoon();
  }

  /// [track] is reached while the board builds; the listeners hear about a
  /// change once that build is over.
  bool _notifyScheduled = false;
  void _notifySoon() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _isVisible?.removeListener(_sync);
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    super.dispose();
  }
}
