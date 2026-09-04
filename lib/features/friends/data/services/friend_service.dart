import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';

import '../models/friend_request.dart';
import '../models/friend_user.dart';

export '../models/friend_user.dart' show FriendRelationshipStatus;

typedef FriendMutationInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

typedef PublicProfileSearchInvoker =
    Future<List<Map<String, dynamic>>> Function(String query, int limit);
typedef RelationshipStatusInvoker =
    Future<FriendRelationshipStatus> Function(String otherUserId);
typedef FriendRequestsWatch =
    Stream<List<FriendRequest>> Function(String currentUserId);
typedef FriendDocumentWatch =
    Stream<DocumentSnapshot<Map<String, dynamic>>> Function(String friendId);
typedef FriendChildRetryDelay = Duration Function(int attempt);
typedef FriendChildRetryScheduler =
    Timer Function(Duration delay, void Function() callback);

class FriendService {
  FriendService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
    FirebaseFunctions? functions,
    FriendMutationInvoker? mutationInvoker,
    PublicProfileSearchInvoker? searchInvoker,
    RelationshipStatusInvoker? relationshipStatusInvoker,
    FriendRequestsWatch? friendRequestsWatch,
    FriendDocumentWatch? publicProfileWatch,
    FriendDocumentWatch? socialPresenceWatch,
    FriendChildRetryDelay? childListenerRetryDelay,
    FriendChildRetryScheduler? childListenerRetryScheduler,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker,
       _searchInvoker = searchInvoker,
       _relationshipStatusInvoker = relationshipStatusInvoker,
       _friendRequestsWatch = friendRequestsWatch,
       _publicProfileWatch = publicProfileWatch,
       _socialPresenceWatch = socialPresenceWatch,
       _childListenerRetryDelay =
           childListenerRetryDelay ?? _defaultChildListenerRetryDelay,
       _childListenerRetryScheduler = childListenerRetryScheduler ?? Timer.new,
       _friendsReadVariant =
           publicProfileWatch != null ||
               socialPresenceWatch != null ||
               childListenerRetryDelay != null ||
               childListenerRetryScheduler != null
           ? Object()
           : null;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final FriendMutationInvoker? _mutationInvoker;
  final PublicProfileSearchInvoker? _searchInvoker;
  final RelationshipStatusInvoker? _relationshipStatusInvoker;
  final FriendRequestsWatch? _friendRequestsWatch;
  final FriendDocumentWatch? _publicProfileWatch;
  final FriendDocumentWatch? _socialPresenceWatch;
  final FriendChildRetryDelay _childListenerRetryDelay;
  final FriendChildRetryScheduler _childListenerRetryScheduler;
  final Object? _friendsReadVariant;

  static final Map<_FriendReadStreamKey, _SharedFriendStream>
  _sharedFriendStreams = <_FriendReadStreamKey, _SharedFriendStream>{};
  static final Map<_FriendReadStreamKey, _SharedFriendRequestStream>
  _sharedFriendRequestStreams =
      <_FriendReadStreamKey, _SharedFriendRequestStream>{};

  static Duration _defaultChildListenerRetryDelay(int attempt) {
    const delays = <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ];
    final index = attempt <= 1
        ? 0
        : attempt >= delays.length
        ? delays.length - 1
        : attempt - 1;
    return delays[index];
  }

  static const _childListenerStableWindow = Duration(seconds: 30);

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('publicProfiles');

  CollectionReference<Map<String, dynamic>> get _socialPresence =>
      _firestore.collection('socialPresence');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user;
  }

  Future<Map<String, dynamic>> _mutate(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final injected = _mutationInvoker;
    if (injected != null) return injected(functionName, data);
    try {
      final result = await _functions.httpsCallable(functionName).call(data);
      final value = result.data;
      return value is Map
          ? Map<String, dynamic>.from(value)
          : const <String, dynamic>{};
    } on FirebaseFunctionsException {
      throw StateError('The social action could not be completed.');
    }
  }

  /// Makes sure the signed-in user has a `users/{uid}` document so friend
  /// edges have something to point at.
  ///
  /// Deliberately does NOT write `displayName`, `email` or `photoUrl`.
  /// Those come from FirebaseAuth's `currentUser`, which is a *separate*
  /// and frequently stale source — `photoURL` is null for email/password
  /// accounts and holds the Google avatar for Google ones. Writing it here
  /// clobbered the profile photo that `ProfileService` owns, and this
  /// method runs on every `watchFriends()` start (Home's friends row and
  /// Messages both trigger it), so a freshly saved avatar could be wiped
  /// seconds later by a background stream.
  ///
  /// This is the same defect that was already fixed once in
  /// `PresenceService.setOnline()` — see docs/Bugs.md. Profile field
  /// bootstrapping for brand-new accounts belongs to
  /// `ProfileService.ensureProfile()`, which AuthGate already calls at
  /// sign-in and which no-ops when the document exists.
  Future<void> ensureUserDocument() async {
    final user = _currentUser;

    await _ensureUserDocumentFor(user.uid);
  }

  Future<void> _ensureUserDocumentFor(String userId) async {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('The authenticated account changed.');
    }

    await _users.doc(userId).set({
      'uid': userId,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Invalidates every process-wide friends fanout before an auth boundary.
  ///
  /// This is synchronous on purpose: cached identities and replayed values
  /// become unreachable before sign-out yields to any network cleanup. The
  /// underlying subscriptions finish cancelling in the background and cannot
  /// mutate a replacement fanout created by a new account.
  static void clearSharedReadCaches() {
    final cachedFriends = _sharedFriendStreams.values.toList(growable: false);
    final cachedRequests = _sharedFriendRequestStreams.values.toList(
      growable: false,
    );
    _sharedFriendStreams.clear();
    _sharedFriendRequestStreams.clear();
    for (final shared in cachedFriends) {
      shared.retire();
    }
    for (final shared in cachedRequests) {
      shared.retire();
    }
  }

  /// Watches the signed-in user's friends.
  ///
  /// The returned stream supports **multiple simultaneous listeners** and
  /// replays the most recent list to anyone who subscribes late.
  /// Instances backed by the same Firestore/Auth session also receive the
  /// same stream. Home and Chats construct their own service facades, but
  /// must not each create a root listener plus two point listeners per friend.
  ///
  /// Both matter: `MessagesScreen` creates this stream once and hands the
  /// same instance to `_FriendsRow` *and* to `NewMessageSheet`. While this
  /// returned a plain single-subscription controller, opening the New
  /// message sheet threw `Bad state: Stream has already been listened to`
  /// inside the sheet's StreamBuilder, and Flutter swapped that whole
  /// subtree for a bare [ErrorWidget] — which renders as an unlabelled
  /// light-grey rectangle in release web builds. Replay matters because the
  /// second listener joins after the first value was already emitted, and
  /// without it the sheet would sit on a spinner until a friend document
  /// happened to change.
  Stream<List<FriendUser>> watchFriends() {
    final currentUserId = _currentUser.uid;
    final key = _FriendReadStreamKey(
      firestore: _firestore,
      auth: _auth,
      userId: currentUserId,
      variant: _friendsReadVariant,
    );
    final existing = _sharedFriendStreams[key];
    if (existing != null) return existing.stream;

    late final _SharedFriendStream created;
    created = _buildFriendsStream(
      currentUserId,
      onRetired: () {
        final current = _sharedFriendStreams[key];
        if (current != null && identical(current.stream, created.stream)) {
          _sharedFriendStreams.remove(key);
        }
      },
    );
    _sharedFriendStreams[key] = created;
    return created.stream;
  }

  _SharedFriendStream _buildFriendsStream(
    String currentUserId, {
    required void Function() onRetired,
  }) {
    final controller = StreamController<List<FriendUser>>.broadcast();
    final profileSubscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final presenceSubscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final profileRetryTimers = <String, Timer>{};
    final presenceRetryTimers = <String, Timer>{};
    final profileStabilityTimers = <String, Timer>{};
    final presenceStabilityTimers = <String, Timer>{};
    final profileRetryAttempts = <String, int>{};
    final presenceRetryAttempts = <String, int>{};
    final childEpochs = <String, int>{};
    final activeFriendIds = <String>{};
    final profiles = <String, FriendUser>{};
    final presences = <String, ({bool isOnline, DateTime? lastSeen})>{};
    // Legacy mirror rows (`users/{me}/friends/{id}`) may carry a stored
    // displayName; canonical rows do not. Captured so a row whose public
    // profile is missing or unreadable can degrade to its last known name
    // instead of silently disappearing from the list and its counter.
    final mirrorNames = <String, String>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rootSubscription;
    StreamSubscription<User?>? authSubscription;
    var retired = false;
    var terminalErrorQueued = false;
    late void Function() retire;
    List<FriendUser>? latest;

    // Identity fallback for a friend whose `publicProfiles/{id}` read is
    // unavailable. No photo, and presence is never fabricated here — the
    // separately authorised presence listener still owns that join.
    FriendUser degradedFriend(String id) => FriendUser(
      id: id,
      displayName: mirrorNames[id] ?? 'YO Voice member',
      email: '',
      photoUrl: null,
      isOnline: false,
      lastSeen: null,
    );

    void emit() {
      if (retired || controller.isClosed) return;
      final result =
          profiles.entries
              .map((entry) {
                final presence = presences[entry.key];
                return entry.value.copyWith(
                  isOnline: presence?.isOnline ?? false,
                  lastSeen: presence?.lastSeen,
                  clearLastSeen: presence?.lastSeen == null,
                );
              })
              .toList(growable: false)
            ..sort((a, b) {
              if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
              return a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
            });
      latest = result;
      controller.add(result);
    }

    bool childIsCurrent(String id, int epoch) {
      if (!retired && _auth.currentUser?.uid != currentUserId) {
        retire();
        return false;
      }
      return !retired &&
          activeFriendIds.contains(id) &&
          childEpochs[id] == epoch;
    }

    Stream<DocumentSnapshot<Map<String, dynamic>>> profileSource(String id) {
      final injected = _publicProfileWatch;
      return injected?.call(id) ?? _publicProfiles.doc(id).snapshots();
    }

    Stream<DocumentSnapshot<Map<String, dynamic>>> presenceSource(String id) {
      final injected = _socialPresenceWatch;
      return injected?.call(id) ?? _socialPresence.doc(id).snapshots();
    }

    late void Function(String id, int epoch) attachProfile;
    late void Function(String id, int epoch) attachPresence;

    void markProfileListenerHealthy(
      String id,
      int epoch,
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> subscription,
    ) {
      if (!profileRetryAttempts.containsKey(id) ||
          profileStabilityTimers.containsKey(id)) {
        return;
      }
      late final Timer stabilityTimer;
      stabilityTimer = _childListenerRetryScheduler(
        _childListenerStableWindow,
        () {
          if (!identical(profileStabilityTimers[id], stabilityTimer)) return;
          profileStabilityTimers.remove(id);
          if (childIsCurrent(id, epoch) &&
              identical(profileSubscriptions[id], subscription)) {
            profileRetryAttempts.remove(id);
          }
        },
      );
      profileStabilityTimers[id] = stabilityTimer;
    }

    void markPresenceListenerHealthy(
      String id,
      int epoch,
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> subscription,
    ) {
      if (!presenceRetryAttempts.containsKey(id) ||
          presenceStabilityTimers.containsKey(id)) {
        return;
      }
      late final Timer stabilityTimer;
      stabilityTimer = _childListenerRetryScheduler(
        _childListenerStableWindow,
        () {
          if (!identical(presenceStabilityTimers[id], stabilityTimer)) return;
          presenceStabilityTimers.remove(id);
          if (childIsCurrent(id, epoch) &&
              identical(presenceSubscriptions[id], subscription)) {
            presenceRetryAttempts.remove(id);
          }
        },
      );
      presenceStabilityTimers[id] = stabilityTimer;
    }

    void scheduleProfileRetry(String id, int epoch) {
      if (!childIsCurrent(id, epoch) ||
          profileSubscriptions.containsKey(id) ||
          profileRetryTimers.containsKey(id)) {
        return;
      }
      final attempt = (profileRetryAttempts[id] ?? 0) + 1;
      profileRetryAttempts[id] = attempt;
      late final Timer retryTimer;
      retryTimer = _childListenerRetryScheduler(
        _childListenerRetryDelay(attempt),
        () {
          if (!identical(profileRetryTimers[id], retryTimer)) return;
          profileRetryTimers.remove(id);
          if (childIsCurrent(id, epoch) &&
              !profileSubscriptions.containsKey(id)) {
            attachProfile(id, epoch);
          }
        },
      );
      profileRetryTimers[id] = retryTimer;
    }

    void schedulePresenceRetry(String id, int epoch) {
      if (!childIsCurrent(id, epoch) ||
          presenceSubscriptions.containsKey(id) ||
          presenceRetryTimers.containsKey(id)) {
        return;
      }
      final attempt = (presenceRetryAttempts[id] ?? 0) + 1;
      presenceRetryAttempts[id] = attempt;
      late final Timer retryTimer;
      retryTimer = _childListenerRetryScheduler(
        _childListenerRetryDelay(attempt),
        () {
          if (!identical(presenceRetryTimers[id], retryTimer)) return;
          presenceRetryTimers.remove(id);
          if (childIsCurrent(id, epoch) &&
              !presenceSubscriptions.containsKey(id)) {
            attachPresence(id, epoch);
          }
        },
      );
      presenceRetryTimers[id] = retryTimer;
    }

    attachProfile = (String id, int epoch) {
      if (!childIsCurrent(id, epoch) || profileSubscriptions.containsKey(id)) {
        return;
      }

      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? candidate;

      void detachAndRetry() {
        profileStabilityTimers.remove(id)?.cancel();
        scheduleMicrotask(() {
          final failed = candidate;
          if (failed == null ||
              !childIsCurrent(id, epoch) ||
              !identical(profileSubscriptions[id], failed)) {
            return;
          }
          profileSubscriptions.remove(id);
          unawaited(failed.cancel());
          scheduleProfileRetry(id, epoch);
        });
      }

      try {
        candidate = profileSource(id).listen(
          (document) {
            if (!childIsCurrent(id, epoch)) return;
            try {
              if (!document.exists || document.data() == null) {
                // The relationship edge is canonical even when the public
                // projection is missing. Keep the row and its counter.
                profiles[id] = degradedFriend(id);
              } else {
                profiles[id] = FriendUser.fromFirestore(document);
              }
              final subscription = candidate;
              if (subscription != null) {
                // A cached snapshot followed immediately by a terminal error
                // is not a healthy listener. Reset exponential backoff only
                // after this exact subscription has remained viable for a full
                // stability window; otherwise repeated cache/error cycles
                // would reconnect every 250 ms forever.
                markProfileListenerHealthy(id, epoch, subscription);
              }
              emit();
            } catch (_) {
              // Public projections are server-managed, but legacy or partially
              // migrated rows can still contain an unexpected field type. A
              // malformed friend must degrade in place rather than disappear
              // because an exception escaped the stream callback.
              profiles[id] = degradedFriend(id);
              emit();
              detachAndRetry();
            }
          },
          onError: (_) {
            if (!childIsCurrent(id, epoch)) return;
            // Never retain the last readable avatar after profile access
            // fails. Degrade immediately, then replace the failed listener.
            profiles[id] = degradedFriend(id);
            emit();
            detachAndRetry();
          },
          onDone: detachAndRetry,
        );
      } catch (_) {
        if (!childIsCurrent(id, epoch)) return;
        profiles[id] = degradedFriend(id);
        emit();
        scheduleProfileRetry(id, epoch);
        return;
      }

      final subscription = candidate;
      if (!childIsCurrent(id, epoch)) {
        unawaited(subscription.cancel());
        return;
      }
      profileSubscriptions[id] = subscription;
    };

    attachPresence = (String id, int epoch) {
      if (!childIsCurrent(id, epoch) || presenceSubscriptions.containsKey(id)) {
        return;
      }

      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? candidate;

      void detachAndRetry() {
        presenceStabilityTimers.remove(id)?.cancel();
        scheduleMicrotask(() {
          final failed = candidate;
          if (failed == null ||
              !childIsCurrent(id, epoch) ||
              !identical(presenceSubscriptions[id], failed)) {
            return;
          }
          presenceSubscriptions.remove(id);
          unawaited(failed.cancel());
          schedulePresenceRetry(id, epoch);
        });
      }

      try {
        candidate = presenceSource(id).listen(
          (document) {
            if (!childIsCurrent(id, epoch)) return;
            try {
              final data = document.data();
              final rawOnline = data?['isOnline'];
              if (rawOnline != null && rawOnline is! bool) {
                throw const FormatException('Invalid presence availability.');
              }
              final lastSeen = data?['lastSeen'];
              presences[id] = (
                isOnline: rawOnline as bool? ?? false,
                lastSeen: lastSeen is Timestamp ? lastSeen.toDate() : null,
              );
              final subscription = candidate;
              if (subscription != null) {
                markPresenceListenerHealthy(id, epoch, subscription);
              }
              emit();
            } catch (_) {
              // Presence is advisory and must fail closed. Never let malformed
              // legacy data leave somebody appearing online or escape as an
              // uncaught asynchronous callback exception.
              presences.remove(id);
              emit();
              detachAndRetry();
            }
          },
          onError: (_) {
            if (!childIsCurrent(id, epoch)) return;
            // Presence fails closed to offline while its point listener is
            // replaced independently from the readable public identity.
            presences.remove(id);
            emit();
            detachAndRetry();
          },
          onDone: detachAndRetry,
        );
      } catch (_) {
        if (!childIsCurrent(id, epoch)) return;
        presences.remove(id);
        emit();
        schedulePresenceRetry(id, epoch);
        return;
      }

      final subscription = candidate;
      if (!childIsCurrent(id, epoch)) {
        unawaited(subscription.cancel());
        return;
      }
      presenceSubscriptions[id] = subscription;
    };

    void removeChild(String id) {
      activeFriendIds.remove(id);
      childEpochs[id] = (childEpochs[id] ?? 0) + 1;
      profileRetryTimers.remove(id)?.cancel();
      presenceRetryTimers.remove(id)?.cancel();
      profileStabilityTimers.remove(id)?.cancel();
      presenceStabilityTimers.remove(id)?.cancel();
      profileRetryAttempts.remove(id);
      presenceRetryAttempts.remove(id);
      unawaited(profileSubscriptions.remove(id)?.cancel());
      unawaited(presenceSubscriptions.remove(id)?.cancel());
      profiles.remove(id);
      presences.remove(id);
      mirrorNames.remove(id);
    }

    Future<void> finishRetirement(
      List<StreamSubscription<dynamic>> subscriptions,
      Future<void> closing,
    ) async {
      for (final subscription in subscriptions) {
        try {
          await subscription.cancel();
        } catch (_) {
          // Generation state was already detached synchronously below, so a
          // cancellation failure cannot publish stale identity into a newer
          // account's fanout.
        }
      }
      try {
        await closing;
      } catch (_) {
        // Local cache cleanup must never make sign-out fail.
      }
    }

    retire = () {
      if (retired) return;
      retired = true;
      latest = null;

      // Capture and detach every mutable reference before awaiting anything.
      // A new account can now create its own fanout immediately, and a late
      // completion from this generation has no reference it could clear.
      final subscriptions = <StreamSubscription<dynamic>>[
        ?authSubscription,
        ?rootSubscription,
        ...profileSubscriptions.values,
        ...presenceSubscriptions.values,
      ];
      authSubscription = null;
      rootSubscription = null;
      for (final timer in profileRetryTimers.values) {
        timer.cancel();
      }
      for (final timer in presenceRetryTimers.values) {
        timer.cancel();
      }
      for (final timer in profileStabilityTimers.values) {
        timer.cancel();
      }
      for (final timer in presenceStabilityTimers.values) {
        timer.cancel();
      }
      profileRetryTimers.clear();
      presenceRetryTimers.clear();
      profileStabilityTimers.clear();
      presenceStabilityTimers.clear();
      profileSubscriptions.clear();
      presenceSubscriptions.clear();
      profileRetryAttempts.clear();
      presenceRetryAttempts.clear();
      activeFriendIds.clear();
      childEpochs.clear();
      profiles.clear();
      presences.clear();
      mirrorNames.clear();
      onRetired();

      final closing = controller.isClosed
          ? Future<void>.value()
          : controller.close();
      unawaited(finishRetirement(subscriptions, closing));
    };

    Future<void> start() async {
      if (retired || _auth.currentUser?.uid != currentUserId) {
        retire();
        return;
      }

      // The cache is bound to the exact account that created it. This catches
      // auth transitions that bypass AuthService.signOut() as well.
      final authCandidate = _auth.userChanges().listen((user) {
        if (user?.uid != currentUserId) retire();
      }, onError: (_, __) => retire());
      if (retired) {
        unawaited(authCandidate.cancel());
        return;
      }
      authSubscription = authCandidate;
      try {
        await _ensureUserDocumentFor(currentUserId);
        if (retired || _auth.currentUser?.uid != currentUserId) {
          retire();
          return;
        }
        rootSubscription = _users
            .doc(currentUserId)
            .collection('friends')
            .snapshots()
            .listen(
              (snapshot) {
                if (retired) return;
                final ids = <String>{};
                for (final doc in snapshot.docs) {
                  ids.add(doc.id);
                  final mirrorName = (doc.data()['displayName'] as String?)
                      ?.trim();
                  if (mirrorName != null && mirrorName.isNotEmpty) {
                    mirrorNames[doc.id] = mirrorName;
                  }
                }

                final removedIds = activeFriendIds
                    .difference(ids)
                    .toList(growable: false);
                for (final removed in removedIds) {
                  // The active-id set, retry timers and epoch are invalidated
                  // together. A timer queued by a terminal child-listener
                  // error cannot resurrect a removed relationship.
                  removeChild(removed);
                }

                for (final id in ids) {
                  if (!activeFriendIds.contains(id)) {
                    activeFriendIds.add(id);
                    childEpochs[id] = (childEpochs[id] ?? 0) + 1;
                  }
                  final epoch = childEpochs[id]!;
                  if (!profileSubscriptions.containsKey(id) &&
                      !profileRetryTimers.containsKey(id)) {
                    attachProfile(id, epoch);
                  }
                  if (!presenceSubscriptions.containsKey(id) &&
                      !presenceRetryTimers.containsKey(id)) {
                    attachPresence(id, epoch);
                  }
                }
                emit();
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!retired && !controller.isClosed) {
                  terminalErrorQueued = true;
                  controller.addError(error, stackTrace);
                  // Firestore snapshot streams do not guarantee a matching
                  // done event after a fatal listener error. Retire this
                  // source-less generation now so a later caller can build a
                  // fresh fanout instead of joining a permanently dead cache.
                  retire();
                }
              },
            );
      } catch (error, stackTrace) {
        if (!retired && !controller.isClosed) {
          terminalErrorQueued = true;
          controller.addError(error, stackTrace);
          // Startup failed before a viable root subscription existed. Keeping
          // the auth subscription and cache entry alive would poison every
          // FriendService facade for the rest of this generation.
          retire();
        }
      }
    }

    controller.onListen = start;
    controller.onCancel = retire;

    // Stream.multi gives every listener its own subscription, which lets us
    // hand the cached list straight to late subscribers before forwarding
    // live updates.
    final stream = Stream<List<FriendUser>>.multi((subscriber) {
      // Do not rely only on userChanges(): its notification is asynchronous,
      // while a retained stream can be listened to immediately after the
      // FirebaseAuth identity has already switched. Check the authoritative
      // synchronous identity before replaying any cached profile data.
      if (retired || _auth.currentUser?.uid != currentUserId) {
        retire();
        subscriber.close();
        return;
      }
      final cached = latest;
      if (cached != null) {
        subscriber.add(cached);
      }
      final subscription = controller.stream.listen(
        (friends) {
          if (retired || _auth.currentUser?.uid != currentUserId) {
            retire();
            return;
          }
          subscriber.add(friends);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_auth.currentUser?.uid != currentUserId) {
            retire();
            return;
          }
          // The source failure is enqueued on the async broadcast controller
          // immediately before this generation retires. Preserve that one
          // terminal signal; ordinary queued errors after retirement remain
          // suppressed just like queued data.
          if (retired && !terminalErrorQueued) return;
          subscriber.addError(error, stackTrace);
        },
        onDone: subscriber.close,
      );
      subscriber.onCancel = subscription.cancel;
    });
    return _SharedFriendStream(stream: stream, retire: retire);
  }

  Stream<List<FriendRequest>> watchFriendRequests() {
    final currentUserId = _currentUser.uid;
    final key = _FriendReadStreamKey(
      firestore: _firestore,
      auth: _auth,
      userId: currentUserId,
      variant: _friendRequestsWatch,
    );
    final existing = _sharedFriendRequestStreams[key];
    if (existing != null) return existing.stream;

    late final _SharedFriendRequestStream created;
    created = _buildFriendRequestsStream(
      currentUserId,
      onRetired: () {
        if (identical(_sharedFriendRequestStreams[key], created)) {
          _sharedFriendRequestStreams.remove(key);
        }
      },
    );
    _sharedFriendRequestStreams[key] = created;
    return created.stream;
  }

  _SharedFriendRequestStream _buildFriendRequestsStream(
    String currentUserId, {
    required void Function() onRetired,
  }) {
    final controller = StreamController<List<FriendRequest>>.broadcast();
    StreamSubscription<List<FriendRequest>>? rootSubscription;
    StreamSubscription<User?>? authSubscription;
    List<FriendRequest>? latest;
    var retired = false;
    var terminalErrorQueued = false;

    Future<void> finishRetirement(
      List<StreamSubscription<dynamic>> subscriptions,
      Future<void> closing,
    ) async {
      for (final subscription in subscriptions) {
        try {
          await subscription.cancel();
        } catch (_) {
          // The fanout is already detached and cannot publish stale requests.
        }
      }
      try {
        await closing;
      } catch (_) {
        // Cache invalidation must not make an auth transition fail.
      }
    }

    void retire() {
      if (retired) return;
      retired = true;
      latest = null;
      final subscriptions = <StreamSubscription<dynamic>>[
        ?authSubscription,
        ?rootSubscription,
      ];
      authSubscription = null;
      rootSubscription = null;
      onRetired();
      final closing = controller.isClosed
          ? Future<void>.value()
          : controller.close();
      unawaited(finishRetirement(subscriptions, closing));
    }

    Stream<List<FriendRequest>> source() {
      final injected = _friendRequestsWatch;
      if (injected != null) return injected(currentUserId);
      return _users
          .doc(currentUserId)
          .collection('friendRequests')
          .snapshots()
          .map((snapshot) {
            final requests = snapshot.docs
                .map(FriendRequest.fromFirestore)
                .toList(growable: false);
            requests.sort((a, b) {
              if (a.createdAt == null && b.createdAt == null) return 0;
              if (a.createdAt == null) return 1;
              if (b.createdAt == null) return -1;
              return b.createdAt!.compareTo(a.createdAt!);
            });
            return requests;
          });
    }

    void start() {
      if (retired || _auth.currentUser?.uid != currentUserId) {
        retire();
        return;
      }

      final authCandidate = _auth.userChanges().listen((user) {
        if (user?.uid != currentUserId) retire();
      }, onError: (_, __) => retire());
      if (retired) {
        unawaited(authCandidate.cancel());
        return;
      }
      authSubscription = authCandidate;

      try {
        final rootCandidate = source().listen(
          (requests) {
            if (retired) return;
            if (_auth.currentUser?.uid != currentUserId) {
              retire();
              return;
            }
            latest = requests;
            controller.add(requests);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (retired) return;
            if (_auth.currentUser?.uid != currentUserId) {
              retire();
              return;
            }
            terminalErrorQueued = true;
            controller.addError(error, stackTrace);
            // A fatal Firestore listener error may never be followed by done.
            // Evict immediately so future request/count consumers can retry.
            retire();
          },
          onDone: retire,
        );
        if (retired) {
          unawaited(rootCandidate.cancel());
          return;
        }
        rootSubscription = rootCandidate;
      } catch (error, stackTrace) {
        if (!retired && !controller.isClosed) {
          // Test seams and platform setup can fail before listen returns. Turn
          // that synchronous failure into the same observable terminal error
          // and fully detach the half-started generation.
          terminalErrorQueued = true;
          controller.addError(error, stackTrace);
          retire();
        }
      }
    }

    controller.onListen = start;
    controller.onCancel = retire;

    final stream = Stream<List<FriendRequest>>.multi((subscriber) {
      if (retired || _auth.currentUser?.uid != currentUserId) {
        retire();
        subscriber.close();
        return;
      }
      final cached = latest;
      if (cached != null) subscriber.add(cached);
      final subscription = controller.stream.listen(
        (requests) {
          if (retired || _auth.currentUser?.uid != currentUserId) {
            retire();
            return;
          }
          subscriber.add(requests);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_auth.currentUser?.uid != currentUserId) {
            retire();
            return;
          }
          if (retired && !terminalErrorQueued) return;
          subscriber.addError(error, stackTrace);
        },
        onDone: subscriber.close,
      );
      subscriber.onCancel = subscription.cancel;
    });
    return _SharedFriendRequestStream(stream: stream, retire: retire);
  }

  Stream<int> watchPendingFriendRequestCount() =>
      watchFriendRequests().map((items) => items.length).distinct();

  Future<List<FriendUser>> searchUsers(String query) async {
    final search = query.trim();
    if (search.length < 2) return const [];

    final injected = _searchInvoker;
    final rawProfiles = injected != null
        ? await injected(search, 20)
        : await _searchPublicProfiles(search, limit: 20);
    return rawProfiles
        .map(
          (data) =>
              FriendUser.fromMap(id: data['uid'] as String? ?? '', data: data),
        )
        .where((profile) => profile.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _searchPublicProfiles(
    String query, {
    required int limit,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('searchPublicProfiles')
          .call({'query': query, 'limit': limit});
      final data = Map<String, dynamic>.from(result.data as Map);
      return (data['profiles'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } on FirebaseFunctionsException {
      throw StateError('User search is unavailable.');
    }
  }

  Future<FriendRelationshipStatus> getRelationshipStatus(
    String otherUserId,
  ) async {
    final injected = _relationshipStatusInvoker;
    if (injected != null) return injected(otherUserId);
    final me = _currentUser.uid;
    final results = await Future.wait([
      _users.doc(me).collection('friends').doc(otherUserId).get(),
      _users.doc(otherUserId).collection('friendRequests').doc(me).get(),
      _users.doc(me).collection('friendRequests').doc(otherUserId).get(),
      _users.doc(me).collection('blocked').doc(otherUserId).get(),
    ]);
    if (results[3].exists) return FriendRelationshipStatus.blocked;
    if (results[0].exists) return FriendRelationshipStatus.friends;
    if (results[1].exists) return FriendRelationshipStatus.requestSent;
    if (results[2].exists) return FriendRelationshipStatus.requestReceived;
    return FriendRelationshipStatus.none;
  }

  Future<FriendRelationshipStatus> sendFriendRequest(
    FriendUser receiver,
  ) async {
    if (receiver.id == _currentUser.uid) {
      throw StateError('You cannot add yourself.');
    }
    final result = await _mutate('sendFriendRequest', {
      'targetUserId': receiver.id,
    });
    final status = switch (result['outcome']) {
      'accepted' || 'alreadyFriends' => FriendRelationshipStatus.friends,
      'requested' || 'alreadyPending' => FriendRelationshipStatus.requestSent,
      _ => throw StateError('The friend request returned an invalid response.'),
    };
    if (status == FriendRelationshipStatus.friends) {
      ProfileMediaService.evictUser(receiver.id);
    }
    return status;
  }

  Future<void> cancelFriendRequest(String receiverId) async {
    await _mutate('cancelFriendRequest', {'targetUserId': receiverId});
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    await _mutate('respondToFriendRequest', {
      'senderId': request.senderId,
      'accept': true,
    });
    ProfileMediaService.evictUser(request.senderId);
  }

  Future<void> declineFriendRequest(String senderId) async {
    await _mutate('respondToFriendRequest', {
      'senderId': senderId,
      'accept': false,
    });
  }

  Future<void> removeFriend(String friendId) async {
    await _mutate('removeFriend', {'targetUserId': friendId});
    ProfileMediaService.evictUser(friendId);
  }

  Stream<List<FriendUser>> watchBlockedUsers() {
    return _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return const <FriendUser>[];
          final users = await Future.wait(
            snapshot.docs.map((blockedDoc) async {
              try {
                final profile = await _publicProfiles.doc(blockedDoc.id).get();
                if (profile.exists && profile.data() != null) {
                  return FriendUser.fromFirestore(profile);
                }
              } on FirebaseException {
                // A private/deleted profile must not make the block itself
                // disappear. Keeping the uid-backed row preserves Unblock.
              }
              return FriendUser(
                id: blockedDoc.id,
                displayName: 'Blocked user',
                email: '',
                photoUrl: null,
                isOnline: false,
                lastSeen: null,
              );
            }),
          );
          return users.toList(growable: false)..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
        });
  }

  Future<bool> isBlocked(String userId) async {
    final doc = await _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// Blocks [targetUserId]: severs any friendship, pending friend request
  /// (either direction), and follow relationship (either direction) with
  /// them, then records the block. Firestore rules use the resulting
  /// `blocked` doc to reject any new friend request/follow/conversation
  /// between the two users in either direction going forward.
  Future<void> blockUser(String targetUserId) async {
    if (targetUserId == _currentUser.uid) {
      throw StateError('You cannot block yourself.');
    }
    await _mutate('setUserBlock', {
      'targetUserId': targetUserId,
      'blocked': true,
    });
    ProfileMediaService.evictUser(targetUserId);
  }

  Future<void> unblockUser(String targetUserId) async {
    await _mutate('setUserBlock', {
      'targetUserId': targetUserId,
      'blocked': false,
    });
    ProfileMediaService.evictUser(targetUserId);
  }
}

class _FriendReadStreamKey {
  const _FriendReadStreamKey({
    required this.firestore,
    required this.auth,
    required this.userId,
    this.variant,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final String userId;
  final Object? variant;

  @override
  bool operator ==(Object other) =>
      other is _FriendReadStreamKey &&
      identical(firestore, other.firestore) &&
      identical(auth, other.auth) &&
      userId == other.userId &&
      identical(variant, other.variant);

  @override
  int get hashCode => Object.hash(
    identityHashCode(firestore),
    identityHashCode(auth),
    userId,
    identityHashCode(variant),
  );
}

class _SharedFriendStream {
  const _SharedFriendStream({required this.stream, required this.retire});

  final Stream<List<FriendUser>> stream;
  final void Function() retire;
}

class _SharedFriendRequestStream {
  const _SharedFriendRequestStream({
    required this.stream,
    required this.retire,
  });

  final Stream<List<FriendRequest>> stream;
  final void Function() retire;
}
