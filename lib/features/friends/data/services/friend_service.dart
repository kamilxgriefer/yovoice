import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/services/notification_service.dart';

import '../models/friend_request.dart';
import '../models/friend_user.dart';

enum FriendRelationshipStatus {
  none,
  friends,
  requestSent,
  requestReceived,
  blocked,
}

typedef FriendMutationInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

typedef PublicProfileSearchInvoker =
    Future<List<Map<String, dynamic>>> Function(String query, int limit);

class FriendService {
  FriendService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
    FirebaseFunctions? functions,
    FriendMutationInvoker? mutationInvoker,
    PublicProfileSearchInvoker? searchInvoker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker,
       _searchInvoker = searchInvoker;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final FriendMutationInvoker? _mutationInvoker;
  final PublicProfileSearchInvoker? _searchInvoker;

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
    } on FirebaseFunctionsException catch (error) {
      throw StateError(
        error.message ?? 'The social action could not be completed.',
      );
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

    await _users.doc(user.uid).set({
      'uid': user.uid,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Watches the signed-in user's friends.
  ///
  /// The returned stream supports **multiple simultaneous listeners** and
  /// replays the most recent list to anyone who subscribes late.
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
    final controller = StreamController<List<FriendUser>>.broadcast();
    final profileSubscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final presenceSubscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final profiles = <String, FriendUser>{};
    final presences = <String, ({bool isOnline, DateTime? lastSeen})>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rootSubscription;
    var closed = false;
    List<FriendUser>? latest;

    void emit() {
      if (closed || controller.isClosed) return;
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

    Future<void> start() async {
      // A broadcast controller calls onListen again if every listener
      // cancels and a new one arrives later, so reset the teardown flag.
      closed = false;
      try {
        await ensureUserDocument();
        rootSubscription = _users
            .doc(currentUserId)
            .collection('friends')
            .snapshots()
            .listen((snapshot) {
              final ids = snapshot.docs.map((doc) => doc.id).toSet();

              for (final removed
                  in profileSubscriptions.keys
                      .where((id) => !ids.contains(id))
                      .toList(growable: false)) {
                profileSubscriptions.remove(removed)?.cancel();
                presenceSubscriptions.remove(removed)?.cancel();
                profiles.remove(removed);
                presences.remove(removed);
              }

              for (final id in ids) {
                if (profileSubscriptions.containsKey(id)) continue;
                profileSubscriptions[id] = _publicProfiles
                    .doc(id)
                    .snapshots()
                    .listen(
                      (document) {
                        if (!document.exists || document.data() == null) {
                          profiles.remove(id);
                        } else {
                          profiles[id] = FriendUser.fromFirestore(document);
                        }
                        emit();
                      },
                      onError: (_) {
                        // A friend may make their full profile private. The
                        // canonical relationship remains, but this complete
                        // projection is no longer authorised. Fail closed per
                        // row instead of turning the entire Friends surface
                        // into an error (or retaining a stale cached profile).
                        profiles.remove(id);
                        presences.remove(id);
                        emit();
                      },
                    );
                presenceSubscriptions[id] = _socialPresence
                    .doc(id)
                    .snapshots()
                    .listen(
                      (document) {
                        final data = document.data();
                        final lastSeen = data?['lastSeen'];
                        presences[id] = (
                          isOnline: data?['isOnline'] as bool? ?? false,
                          lastSeen: lastSeen is Timestamp
                              ? lastSeen.toDate()
                              : null,
                        );
                        emit();
                      },
                      // Presence is deliberately narrower than identity. A
                      // stale/non-canonical edge fails closed to offline
                      // without hiding the otherwise public profile.
                      onError: (_) {
                        presences.remove(id);
                        emit();
                      },
                    );
              }
              emit();
            }, onError: controller.addError);
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller.onListen = start;
    controller.onCancel = () async {
      closed = true;
      await rootSubscription?.cancel();
      rootSubscription = null;
      for (final subscription in profileSubscriptions.values) {
        await subscription.cancel();
      }
      for (final subscription in presenceSubscriptions.values) {
        await subscription.cancel();
      }
      profileSubscriptions.clear();
      presenceSubscriptions.clear();
    };

    // Stream.multi gives every listener its own subscription, which lets us
    // hand the cached list straight to late subscribers before forwarding
    // live updates.
    return Stream<List<FriendUser>>.multi((subscriber) {
      final cached = latest;
      if (cached != null) {
        subscriber.add(cached);
      }
      final subscription = controller.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = subscription.cancel;
    });
  }

  Stream<List<FriendRequest>> watchFriendRequests() {
    return _users
        .doc(_currentUser.uid)
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
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'User search is unavailable.');
    }
  }

  Future<FriendRelationshipStatus> getRelationshipStatus(
    String otherUserId,
  ) async {
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

  Future<void> sendFriendRequest(FriendUser receiver) async {
    if (receiver.id == _currentUser.uid) {
      throw StateError('You cannot add yourself.');
    }
    await _mutate('sendFriendRequest', {'targetUserId': receiver.id});
  }

  Future<void> cancelFriendRequest(String receiverId) async {
    await _mutate('cancelFriendRequest', {'targetUserId': receiverId});
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    await _mutate('respondToFriendRequest', {
      'senderId': request.senderId,
      'accept': true,
    });
  }

  Future<void> declineFriendRequest(String senderId) async {
    await _mutate('respondToFriendRequest', {
      'senderId': senderId,
      'accept': false,
    });
  }

  Future<void> removeFriend(String friendId) async {
    await _mutate('removeFriend', {'targetUserId': friendId});
  }

  Stream<List<FriendUser>> watchBlockedUsers() {
    return _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return const <FriendUser>[];
          final documents = await Future.wait(
            snapshot.docs.map((doc) => _publicProfiles.doc(doc.id).get()),
          );
          return documents
              .where((doc) => doc.exists && doc.data() != null)
              .map(FriendUser.fromFirestore)
              .toList(growable: false)
            ..sort(
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
  }

  Future<void> unblockUser(String targetUserId) async {
    await _mutate('setUserBlock', {
      'targetUserId': targetUserId,
      'blocked': false,
    });
  }
}
