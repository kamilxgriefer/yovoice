import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// One roster read, as Home sees it.
///
/// The three states are deliberately distinct. A roster that has not arrived
/// is NOT an empty room, and a roster the caller may not read is NOT an empty
/// room either — Home says "couldn't check who is talking" instead of
/// printing a claim about people it never saw.
@immutable
class HomeRosterEntry {
  const HomeRosterEntry({this.participants, this.failed = false});

  /// Null while the first snapshot is in flight.
  final List<RoomParticipant>? participants;

  /// The read errored (a permission denial included).
  final bool failed;

  bool get isLoading => participants == null && !failed;

  List<RoomParticipant> get orderedSpeakersFirst {
    final all = [...?participants];
    all.sort((a, b) {
      if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
      if (a.isSpeaker != b.isSpeaker) return a.isSpeaker ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return all;
  }
}

/// THE bounded roster subscription pool for one Home.
///
/// Home shows real faces in three places — the "Tu i teraz" hero, the live
/// rows under "W Twoich serwerach", and the friend intersection that decides
/// which live room the hero features. Left to themselves those would each
/// open their own `watchParticipants` listener per room, which on a busy
/// account is an unbounded fan-out of Firestore listeners for decoration.
///
/// This pool is the single owner: at most [budget] rooms are subscribed at
/// once, in the priority order the caller asks for, and a room that falls out
/// of that order is unsubscribed. Nothing here writes, joins audio, or
/// requests a microphone — it is a read of a roster the caller is already
/// allowed to read.
class HomeRosterCache extends ChangeNotifier {
  HomeRosterCache({RoomService? service, this.budget = 4}) : _service = service;

  final RoomService? _service;

  /// The maximum number of concurrent `watchParticipants` listeners.
  final int budget;

  final Map<String, StreamSubscription<List<RoomParticipant>>> _subscriptions =
      {};
  final Map<String, HomeRosterEntry> _entries = {};
  bool _disposed = false;

  /// How many roster listeners are open right now. Exposed so a test can
  /// assert the budget rather than trust it.
  @visibleForTesting
  int get openSubscriptionCount => _subscriptions.length;

  HomeRosterEntry? entryFor(String roomId) => _entries[roomId];

  List<RoomParticipant> participantsFor(String roomId) =>
      _entries[roomId]?.participants ?? const <RoomParticipant>[];

  bool failedFor(String roomId) => _entries[roomId]?.failed ?? false;

  bool isLoadingFor(String roomId) => _entries[roomId]?.isLoading ?? false;

  /// Subscribes to the first [budget] of [roomIds] and drops everything else.
  ///
  /// Safe to call from `build`: it never notifies synchronously, because the
  /// only thing that changes here and now is WHICH rooms are subscribed, and
  /// a freshly requested room renders as "loading" until its first snapshot.
  void request(Iterable<String> roomIds) {
    if (_disposed) return;
    final wanted = <String>[];
    for (final id in roomIds) {
      if (id.isEmpty || wanted.contains(id)) continue;
      wanted.add(id);
      if (wanted.length >= budget) break;
    }
    final service = _service;
    for (final id in _subscriptions.keys.toList(growable: false)) {
      if (wanted.contains(id)) continue;
      unawaited(_subscriptions.remove(id)!.cancel());
      _entries.remove(id);
    }
    if (service == null) return;
    for (final id in wanted) {
      if (_subscriptions.containsKey(id)) continue;
      _entries[id] = const HomeRosterEntry();
      try {
        _subscriptions[id] = service
            .watchParticipants(id)
            .listen(
              (participants) => _publish(
                id,
                HomeRosterEntry(
                  participants: List<RoomParticipant>.unmodifiable(
                    participants,
                  ),
                ),
              ),
              onError: (Object _) =>
                  _publish(id, const HomeRosterEntry(failed: true)),
            );
      } catch (_) {
        // No Firebase app, or a service that cannot build the query: the
        // room simply has no readable roster. Never an exception on Home.
        _entries[id] = const HomeRosterEntry(failed: true);
      }
    }
  }

  void _publish(String roomId, HomeRosterEntry entry) {
    if (_disposed || !_subscriptions.containsKey(roomId)) return;
    _entries[roomId] = entry;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _entries.clear();
    super.dispose();
  }
}
