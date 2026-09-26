import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

/// Feed-scoped source of truth for the friendship shown on every Yeel by an
/// author. Adjacent pages can be mounted at the same time and must never read
/// or mutate the same relationship independently.
class ReelFriendRelationshipStore {
  ReelFriendRelationshipStore({required this.friendService});

  final FriendService friendService;
  final Map<({String viewerUid, String authorId}), ReelFriendRelationshipEntry>
  _entries =
      <({String viewerUid, String authorId}), ReelFriendRelationshipEntry>{};
  bool _disposed = false;

  ReelFriendRelationshipEntry entryFor({
    required String viewerUid,
    required String authorId,
  }) {
    assert(!_disposed, 'A disposed relationship store cannot be reused.');
    final key = (viewerUid: viewerUid, authorId: authorId);
    return _entries.putIfAbsent(
      key,
      () => ReelFriendRelationshipEntry._(
        friendService: friendService,
        authorId: authorId,
      ),
    );
  }

  /// Drops account-owned state at an authentication boundary. Any late read
  /// or mutation can finish at the service boundary, but it can no longer
  /// publish into the replacement viewer's feed.
  void clear() {
    final entries = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in entries) {
      entry.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }
}

/// Observable relationship state shared by every mounted card for one author.
class ReelFriendRelationshipEntry extends ChangeNotifier {
  ReelFriendRelationshipEntry._({
    required FriendService friendService,
    required this.authorId,
  }) : _friendService = friendService {
    unawaited(refresh());
  }

  final FriendService _friendService;
  final String authorId;

  FriendRelationshipStatus? _status;
  Object? _loadError;
  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;
  Future<void>? _loadInFlight;
  Future<FriendRelationshipStatus>? _mutationInFlight;

  FriendRelationshipStatus? get status => _status;

  /// The service the card needs to open the explicit Accept / Decline prompt
  /// when "Add friend" finds the author already asked (`incomingPending`).
  FriendService get friendService => _friendService;

  /// How the last "Add friend" resolved, for the card's feedback only.
  FriendRequestSendResult? _lastSend;
  FriendRequestSendResult? get lastSend => _lastSend;
  Object? get loadError => _loadError;
  bool get loading => _loading;
  bool get busy => _busy;

  /// Loads once for the whole feed, or retries the same author after a visible
  /// error. Keeping the error while retrying prevents the action from
  /// disappearing and shifting the identity row.
  Future<void> refresh() async {
    final active = _loadInFlight;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _readRelationship();
    _loadInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_loadInFlight, operation)) _loadInFlight = null;
    }
  }

  Future<void> _readRelationship() async {
    if (_disposed) return;
    _loading = true;
    notifyListeners();
    try {
      final next = await _friendService.getRelationshipStatus(authorId);
      if (_disposed) return;
      _status = next;
      _loadError = null;
    } catch (error) {
      if (_disposed) return;
      // Unknown state stays fail-closed. The UI names this failure and offers
      // an explicit retry instead of guessing that no relationship exists.
      _status = null;
      _loadError = error;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Runs one mutation for the author even when more than one mounted card
  /// receives an activation in the same frame.
  Future<FriendRelationshipStatus> submit({required String displayName}) async {
    final active = _mutationInFlight;
    if (active != null) return active;

    final current = _status;
    if (current != FriendRelationshipStatus.none &&
        current != FriendRelationshipStatus.requestReceived) {
      return current ?? FriendRelationshipStatus.blocked;
    }

    late final Future<FriendRelationshipStatus> operation;
    operation = _mutate(current: current!, displayName: displayName);
    _mutationInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_mutationInFlight, operation)) _mutationInFlight = null;
    }
  }

  Future<FriendRelationshipStatus> _mutate({
    required FriendRelationshipStatus current,
    required String displayName,
  }) async {
    if (_disposed) return current;
    _busy = true;
    notifyListeners();
    try {
      final FriendRelationshipStatus next;
      if (current == FriendRelationshipStatus.requestReceived) {
        await _friendService.acceptFriendRequest(
          FriendRequest(
            senderId: authorId,
            senderName: displayName,
            senderEmail: '',
            senderPhotoUrl: null,
            createdAt: null,
          ),
        );
        next = FriendRelationshipStatus.friends;
      } else {
        final result = await _friendService.requestFriendship(
          FriendUser(
            id: authorId,
            displayName: displayName,
            email: '',
            photoUrl: null,
            isOnline: false,
            lastSeen: null,
          ),
        );
        _lastSend = result;
        next = result.status;
      }
      if (!_disposed) {
        _status = next;
        _loadError = null;
      }
      return next;
    } catch (error) {
      if (!_disposed) {
        final raw = error.toString();
        _status = raw.contains('already friends')
            ? FriendRelationshipStatus.friends
            : raw.contains('already sent')
            ? FriendRelationshipStatus.requestSent
            : current;
      }
      rethrow;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Records an answer given in the Accept / Decline prompt, so every card
  /// for this author shows the same relationship.
  ///
  /// A fresh answer is definitive. A stale one (`alreadyResolved`,
  /// `noLongerAvailable`) says nothing certain about the friendship — a
  /// Decline on a request accepted on another device keeps it — so the
  /// relationship is read again instead of assumed to be "not friends".
  void applyResponse(FriendRequestResponseOutcome outcome) {
    if (_disposed) return;
    switch (outcome) {
      case FriendRequestResponseOutcome.accepted:
      case FriendRequestResponseOutcome.alreadyFriends:
        _status = FriendRelationshipStatus.friends;
      case FriendRequestResponseOutcome.declined:
      case FriendRequestResponseOutcome.unavailable:
        _status = FriendRelationshipStatus.none;
      case FriendRequestResponseOutcome.alreadyResolved:
      case FriendRequestResponseOutcome.noLongerAvailable:
        unawaited(refresh());
        return;
    }
    _loadError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
