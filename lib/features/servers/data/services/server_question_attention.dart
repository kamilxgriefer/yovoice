import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_type.dart';
import 'server_service.dart';

/// Which of the account's podcast servers have listener questions the host
/// has not looked at yet — the one source for every "new questions" dot:
/// the server's tile in the directory, its squircle in the server rail, and,
/// inside the open server, the `Pytania` tab, the Questions channel row and
/// the phone's `Kanały` entry.
///
/// Only owners, admins and moderators of an active Podcast server are ever
/// watched, and per server only the two cheap reads of
/// [ServerQuestionAttentionRepository.watchPodcastQuestionsUnseen] (the
/// newest question and the host's own cursor). A server comes from one of two
/// places:
///
/// * the account's directory ([trackDirectory]) — the viewer's own directory
///   mirror carries the role, and the Questions channel is looked up once with
///   a single channel read;
/// * the workspace that has the server open ([claim], [pin], [release]) — it
///   already holds the live role and channel list, so its answer replaces the
///   directory's and costs nothing extra.
///
/// **Retained slots.** The shell keeps the Servers slot built inside an
/// `IndexedStack` while the person is on Home or Chats. While [isVisible] is
/// false every listener here is cancelled, so a hidden slot costs no reads;
/// the last known answers are kept, and when the slot comes back each
/// listener is opened again and its first snapshot corrects them. Null means
/// always visible.
class ServerQuestionAttention extends ChangeNotifier {
  ServerQuestionAttention({
    required ServerRepository repository,
    ValueListenable<bool>? isVisible,
    this.channelLookupTimeout = const Duration(seconds: 5),
  }) : _repository = repository,
       _isVisible = isVisible {
    _isVisible?.addListener(_onVisibility);
  }

  final ServerRepository _repository;
  final ValueListenable<bool>? _isVisible;

  /// How long the one channel read that finds a directory server's Questions
  /// channel may take before that server simply shows no dot.
  final Duration channelLookupTimeout;

  ServerQuestionAttentionRepository? get _attention {
    final repository = _repository;
    return repository is ServerQuestionAttentionRepository
        ? repository as ServerQuestionAttentionRepository
        : null;
  }

  /// Directory servers this viewer may moderate, by id.
  Set<String> _directory = const {};

  /// What an open workspace knows about its server. A pending pin (claimed,
  /// role or channels still loading) keeps whatever is already running and
  /// starts nothing.
  final _pins = <String, _Pin>{};

  /// A directory server's Questions channel, once looked up (null: it has
  /// none).
  final _channels = <String, String?>{};
  final _lookingUp = <String>{};

  /// Lookups that failed while visible; tried again when the slot returns.
  final _lookupFailed = <String>{};

  final _watches = <String, _Watch>{};
  final _waiting = <String>{};
  bool _disposed = false;

  bool get _active => _isVisible?.value ?? true;

  /// Whether [serverId] has listener questions this host has not seen.
  bool isWaiting(String serverId) => _waiting.contains(serverId);

  /// The Questions channel being watched for [serverId], if any.
  String? watchedChannel(String serverId) => _watches[serverId]?.channelId;

  /// Every listener currently open, for tests and diagnostics.
  @visibleForTesting
  int get openWatches => _watches.length;

  /// Whether this viewer should be told about a directory server's
  /// questions: an active Podcast server whose own directory row says the
  /// viewer may moderate it.
  static bool eligible(Server server) =>
      server.type == ServerType.podcast &&
      !server.isLegacy &&
      !server.isHeld &&
      (server.directoryRole?.canModerate ?? false);

  /// The account's servers, as the directory (or the rail) received them.
  void trackDirectory(Iterable<Server> servers) {
    if (_disposed) return;
    final next = {
      for (final server in servers)
        if (eligible(server)) server.id,
    };
    if (setEquals(next, _directory)) return;
    _directory = next;
    _sync();
  }

  /// An open workspace takes [serverId] over; until it [pin]s an answer the
  /// directory's lookup for it is suppressed and nothing new is started.
  void claim(String serverId) {
    if (_disposed) return;
    _pins.putIfAbsent(serverId, () => const _Pin.pending());
    _sync();
  }

  /// The workspace's live answer: the Questions channel to watch, or null
  /// when the viewer may not moderate it (or it has none, or is held).
  void pin(String serverId, {required String? questionsChannelId}) {
    if (_disposed) return;
    final next = _Pin.known(questionsChannelId);
    if (_pins[serverId] == next) return;
    _pins[serverId] = next;
    _sync();
  }

  /// The workspace closed or moved to another server.
  void release(String serverId) {
    if (_disposed) return;
    if (_pins.remove(serverId) == null) return;
    _sync();
  }

  void _onVisibility() {
    if (_disposed) return;
    if (_active) _lookupFailed.clear();
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final attention = _attention;
    final targets = <String, String>{};
    final tracked = {..._directory, ..._pins.keys};
    for (final serverId in tracked) {
      final pin = _pins[serverId];
      if (pin != null) {
        if (!pin.known) {
          // Keep what runs; start nothing until the workspace knows.
          final running = _watches[serverId];
          if (running != null) targets[serverId] = running.channelId;
          continue;
        }
        final channelId = pin.channelId;
        if (channelId != null) targets[serverId] = channelId;
        continue;
      }
      if (_channels.containsKey(serverId)) {
        final channelId = _channels[serverId];
        if (channelId != null) targets[serverId] = channelId;
      } else if (_active &&
          attention != null &&
          !_lookingUp.contains(serverId) &&
          !_lookupFailed.contains(serverId)) {
        unawaited(_lookUp(serverId));
      }
    }

    // A pending pin keeps its last answer until the workspace knows.
    final keep = <String>{
      ...targets.keys,
      for (final serverId in tracked)
        if (_pins[serverId]?.known == false) serverId,
    };
    var changed = false;
    for (final serverId in _waiting.toList()) {
      if (!keep.contains(serverId)) {
        _waiting.remove(serverId);
        changed = true;
      }
    }
    for (final entry in _watches.entries.toList()) {
      final target = targets[entry.key];
      if (_active && target == entry.value.channelId) continue;
      unawaited(entry.value.subscription?.cancel());
      _watches.remove(entry.key);
      // Hidden, the last answer stands until the listener reopens; another
      // channel is another question list, so its answer does not carry over.
      if (target != entry.value.channelId && _waiting.remove(entry.key)) {
        changed = true;
      }
    }
    if (_active && attention != null) {
      for (final entry in targets.entries) {
        if (_watches.containsKey(entry.key)) continue;
        _watches[entry.key] = _watch(attention, entry.key, entry.value);
      }
    }
    if (changed) _notifySoon();
  }

  /// Callers reach [trackDirectory] and [pin] while building; the listeners
  /// hear about it once that build is over.
  bool _notifyScheduled = false;
  void _notifySoon() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  _Watch _watch(
    ServerQuestionAttentionRepository attention,
    String serverId,
    String channelId,
  ) {
    final watch = _Watch(channelId);
    void set(bool waiting) {
      if (_disposed || !identical(_watches[serverId], watch)) return;
      final changed = waiting
          ? _waiting.add(serverId)
          : _waiting.remove(serverId);
      if (changed) _notifySoon();
    }

    try {
      watch.subscription = attention
          .watchPodcastQuestionsUnseen(serverId, channelId)
          .listen(set, onError: (Object _) => set(false));
    } on Object {
      // An id the repository refuses simply has no dot.
    }
    return watch;
  }

  Future<void> _lookUp(String serverId) async {
    _lookingUp.add(serverId);
    try {
      final channels = await _repository
          .watchChannels(serverId)
          .first
          .timeout(channelLookupTimeout);
      if (_disposed) return;
      _channels[serverId] = channels
          .where((channel) => channel.kind == ServerChannelKind.questions)
          .firstOrNull
          ?.id;
    } on Object {
      if (_disposed) return;
      _lookupFailed.add(serverId);
    } finally {
      _lookingUp.remove(serverId);
    }
    _sync();
  }

  @override
  void dispose() {
    _disposed = true;
    _isVisible?.removeListener(_onVisibility);
    for (final watch in _watches.values) {
      unawaited(watch.subscription?.cancel());
    }
    _watches.clear();
    super.dispose();
  }
}

@immutable
class _Pin {
  const _Pin.pending() : known = false, channelId = null;
  const _Pin.known(this.channelId) : known = true;
  final bool known;
  final String? channelId;

  @override
  bool operator ==(Object other) =>
      other is _Pin && other.known == known && other.channelId == channelId;

  @override
  int get hashCode => Object.hash(known, channelId);
}

class _Watch {
  _Watch(this.channelId);
  final String channelId;
  StreamSubscription<bool>? subscription;
}
