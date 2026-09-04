import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

class _DelayedUserChangesAuth extends MockFirebaseAuth {
  _DelayedUserChangesAuth(User initialUser) : activeUser = initialUser;

  User? activeUser;

  @override
  User? get currentUser => activeUser;

  @override
  Stream<User?> userChanges() => const Stream<User?>.empty();
}

class _SynchronousUserChangesAuth extends MockFirebaseAuth {
  _SynchronousUserChangesAuth({
    required this.activeUser,
    required this.nextUser,
  });

  final User activeUser;
  final User nextUser;
  int cancellations = 0;

  @override
  User? get currentUser => activeUser;

  @override
  Stream<User?> userChanges() => Stream<User?>.multi((controller) {
    controller.onCancel = () => cancellations += 1;
    controller.addSync(nextUser);
  });
}

class _ThrowingFirestore extends FakeFirebaseFirestore {
  int collectionReads = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collectionReads += 1;
    throw StateError('$path is unavailable');
  }
}

class _ManualRetryScheduler {
  final timers = <_ManualTimer>[];
  Completer<void> scheduled = Completer<void>();

  Timer call(Duration delay, void Function() callback) {
    final timer = _ManualTimer(delay, callback);
    timers.add(timer);
    if (!scheduled.isCompleted) scheduled.complete();
    return timer;
  }

  Future<void> waitForActive(Duration delay) async {
    for (var turn = 0; turn < 100; turn += 1) {
      if (timers.any(
        (candidate) => candidate.isActive && candidate.delay == delay,
      )) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('No active timer was scheduled for $delay.');
  }

  void fireNext([Duration? delay]) {
    final timer = timers.firstWhere(
      (candidate) =>
          candidate.isActive && (delay == null || candidate.delay == delay),
    );
    scheduled = Completer<void>();
    timer.fire();
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  var _active = true;
  var _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick += 1;
    _callback();
  }
}

/// `watchFriends()` must never silently drop a canonical friend edge just
/// because the `publicProfiles/{id}` projection is missing or unreadable —
/// that made the Friends counter disagree with search ("counter 0 while
/// search says Friends"). Such rows degrade: last known mirror name or a
/// neutral label, no photo, presence never fabricated.
void main() {
  const meUid = 'me-uid';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late FriendService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid));
    service = FriendService(firestore: db, auth: auth);
  });

  tearDown(FriendService.clearSharedReadCaches);

  Future<void> seedFriendEdge(String friendId, Map<String, dynamic> data) {
    return db
        .collection('users')
        .doc(meUid)
        .collection('friends')
        .doc(friendId)
        .set(data);
  }

  test('friends whose public profile is missing still appear, and the '
      'count includes them', () async {
    await seedFriendEdge('ada-uid', {'userId': 'ada-uid'});
    await seedFriendEdge('bea-uid', {
      'userId': 'bea-uid',
      // Legacy mirror rows stored a displayName; canonical ones do not.
      'displayName': 'Bea Legacy',
    });
    await seedFriendEdge('cal-uid', {'userId': 'cal-uid'});
    await db.collection('publicProfiles').doc('ada-uid').set({
      'displayName': 'Ada',
      'photoUrl': 'https://example.com/ada.png',
    });
    // bea-uid and cal-uid have NO publicProfiles document.

    final friends = await service
        .watchFriends()
        .firstWhere((list) => list.length == 3)
        .timeout(const Duration(seconds: 5));

    expect(
      friends.map((friend) => friend.id).toSet(),
      {'ada-uid', 'bea-uid', 'cal-uid'},
      reason: 'no silent row drop: the count must include degraded rows',
    );

    FriendUser byId(String id) =>
        friends.singleWhere((friend) => friend.id == id);

    final ada = byId('ada-uid');
    expect(ada.displayName, 'Ada');
    expect(
      ada.photoUrl,
      isNull,
      reason: 'friends resolve avatars from uid through the media callable',
    );

    final bea = byId('bea-uid');
    expect(
      bea.displayName,
      'Bea Legacy',
      reason: 'degraded rows fall back to the mirror row stored name',
    );
    expect(bea.photoUrl, isNull);
    expect(bea.isOnline, isFalse, reason: 'presence is never fabricated');
    expect(bea.lastSeen, isNull);

    final cal = byId('cal-uid');
    expect(
      cal.displayName,
      'YO Voice member',
      reason: 'no mirror name available: neutral label, not a dropped row',
    );
    expect(cal.photoUrl, isNull);
    expect(cal.isOnline, isFalse);
  });

  test('a degraded row upgrades in place when the profile appears', () async {
    await seedFriendEdge('dee-uid', {'userId': 'dee-uid'});

    final states = <List<FriendUser>>[];
    final subscription = service.watchFriends().listen(states.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states, isNotEmpty);
    expect(states.last, hasLength(1));
    expect(states.last.single.displayName, 'YO Voice member');

    await db.collection('publicProfiles').doc('dee-uid').set({
      'displayName': 'Dee',
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(states.last, hasLength(1));
    expect(states.last.single.displayName, 'Dee');
  });

  test(
    'a terminal public-profile listener error self-heals without restart',
    () async {
      const friendId = 'recover-profile-uid';
      await seedFriendEdge(friendId, {
        'userId': friendId,
        'displayName': 'Mirror fallback',
      });
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Recovered profile',
      });

      var attempts = 0;
      final retryScheduler = _ManualRetryScheduler();
      final recoveringService = FriendService(
        firestore: db,
        auth: auth,
        publicProfileWatch: (id) {
          attempts += 1;
          if (attempts == 1) {
            return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
              StateError('profile listener terminated'),
            );
          }
          return db.collection('publicProfiles').doc(id).snapshots();
        },
        childListenerRetryScheduler: retryScheduler.call,
      );
      final degraded = Completer<void>();
      final recovered = Completer<FriendUser>();
      final subscription = recoveringService.watchFriends().listen((friends) {
        if (friends.length != 1) return;
        final friend = friends.single;
        if (friend.displayName == 'Mirror fallback' && !degraded.isCompleted) {
          degraded.complete();
        }
        if (friend.displayName == 'Recovered profile' &&
            !recovered.isCompleted) {
          recovered.complete(friend);
        }
      });
      addTearDown(subscription.cancel);

      await degraded.future.timeout(const Duration(seconds: 5));
      await retryScheduler.scheduled.future.timeout(const Duration(seconds: 5));
      await retryScheduler.waitForActive(const Duration(milliseconds: 250));
      retryScheduler.fireNext(const Duration(milliseconds: 250));
      final friend = await recovered.future.timeout(const Duration(seconds: 5));

      expect(friend.id, friendId);
      expect(attempts, 2, reason: 'the dead point listener must be replaced');
    },
  );

  test(
    'a terminal presence listener error self-heals and restores presence',
    () async {
      const friendId = 'recover-presence-uid';
      await seedFriendEdge(friendId, {'userId': friendId});
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Online again',
      });
      await db.collection('socialPresence').doc(friendId).set({
        'isOnline': true,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 9, 4, 12)),
      });

      var attempts = 0;
      final retryScheduler = _ManualRetryScheduler();
      final recoveringService = FriendService(
        firestore: db,
        auth: auth,
        socialPresenceWatch: (id) {
          attempts += 1;
          if (attempts == 1) {
            return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
              StateError('presence listener terminated'),
            );
          }
          return db.collection('socialPresence').doc(id).snapshots();
        },
        childListenerRetryScheduler: retryScheduler.call,
      );
      final recovered = Completer<FriendUser>();
      final subscription = recoveringService.watchFriends().listen((friends) {
        if (friends.length == 1 &&
            friends.single.isOnline &&
            !recovered.isCompleted) {
          recovered.complete(friends.single);
        }
      });
      addTearDown(subscription.cancel);

      await retryScheduler.scheduled.future.timeout(const Duration(seconds: 5));
      await retryScheduler.waitForActive(const Duration(milliseconds: 250));
      retryScheduler.fireNext(const Duration(milliseconds: 250));
      final friend = await recovered.future.timeout(const Duration(seconds: 5));

      expect(friend.displayName, 'Online again');
      expect(friend.lastSeen, isNotNull);
      expect(attempts, 2, reason: 'the dead point listener must be replaced');
    },
  );

  test(
    'cached profile data followed by repeated terminal errors backs off',
    () async {
      const friendId = 'cached-profile-error-uid';
      const stableWindow = Duration(seconds: 30);
      const expectedRetryDelays = <Duration>[
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
        Duration(seconds: 1),
        Duration(seconds: 2),
      ];
      await seedFriendEdge(friendId, {'userId': friendId});
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Cached friend',
      });
      final profileDocument = await db
          .collection('publicProfiles')
          .doc(friendId)
          .get();

      final profileAttempts = List.generate(
        expectedRetryDelays.length,
        (_) =>
            Completer<
              StreamController<DocumentSnapshot<Map<String, dynamic>>>
            >(),
      );
      final openedControllers =
          <StreamController<DocumentSnapshot<Map<String, dynamic>>>>[];
      final presenceController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      addTearDown(presenceController.close);
      var attempts = 0;
      final retryScheduler = _ManualRetryScheduler();
      final retryingService = FriendService(
        firestore: db,
        auth: auth,
        publicProfileWatch: (_) {
          final controller =
              StreamController<DocumentSnapshot<Map<String, dynamic>>>();
          openedControllers.add(controller);
          profileAttempts[attempts].complete(controller);
          attempts += 1;
          return controller.stream;
        },
        socialPresenceWatch: (_) => presenceController.stream,
        childListenerRetryScheduler: retryScheduler.call,
      );
      addTearDown(() async {
        for (final controller in openedControllers) {
          await controller.close();
        }
      });
      final subscription = retryingService.watchFriends().listen((_) {});
      addTearDown(subscription.cancel);

      for (var index = 0; index < expectedRetryDelays.length; index += 1) {
        final controller = await profileAttempts[index].future.timeout(
          const Duration(seconds: 5),
        );
        controller.add(profileDocument);
        if (index > 0) {
          await retryScheduler.waitForActive(stableWindow);
        }
        controller.addError(StateError('listener terminated after cache'));
        final retryDelay = expectedRetryDelays[index];
        await retryScheduler.waitForActive(retryDelay);

        if (index > 0) {
          expect(
            retryScheduler.timers
                .where((timer) => timer.delay == stableWindow)
                .every((timer) => !timer.isActive),
            isTrue,
            reason: 'terminal failure must cancel every health-window timer',
          );
        }
        if (index < expectedRetryDelays.length - 1) {
          retryScheduler.fireNext(retryDelay);
        }
      }

      expect(
        retryScheduler.timers
            .where((timer) => timer.delay != stableWindow)
            .map((timer) => timer.delay),
        expectedRetryDelays,
        reason:
            'a cached event is not proof of a healthy listener and must not '
            'reset exponential backoff',
      );
      expect(attempts, expectedRetryDelays.length);
    },
  );

  test('removing a friend cancels its pending stability timer', () async {
    const friendId = 'removed-during-stability-uid';
    const stableWindow = Duration(seconds: 30);
    await seedFriendEdge(friendId, {'userId': friendId});
    await db.collection('publicProfiles').doc(friendId).set({
      'displayName': 'Transient friend',
    });
    final profileDocument = await db
        .collection('publicProfiles')
        .doc(friendId)
        .get();

    final profileController =
        StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    final presenceController =
        StreamController<DocumentSnapshot<Map<String, dynamic>>>();
    addTearDown(profileController.close);
    addTearDown(presenceController.close);
    final profileAttached = Completer<void>();
    final retryScheduler = _ManualRetryScheduler();
    final timerService = FriendService(
      firestore: db,
      auth: auth,
      publicProfileWatch: (_) {
        if (!profileAttached.isCompleted) profileAttached.complete();
        return profileController.stream;
      },
      socialPresenceWatch: (_) => presenceController.stream,
      childListenerRetryScheduler: retryScheduler.call,
    );
    final populated = Completer<void>();
    final removed = Completer<void>();
    final subscription = timerService.watchFriends().listen((friends) {
      if (friends.length == 1 &&
          friends.single.displayName == 'Transient friend' &&
          !populated.isCompleted) {
        populated.complete();
      }
      if (populated.isCompleted && friends.isEmpty && !removed.isCompleted) {
        removed.complete();
      }
    });
    addTearDown(subscription.cancel);

    await profileAttached.future.timeout(const Duration(seconds: 5));
    profileController.addError(StateError('force one retry'));
    await retryScheduler.waitForActive(const Duration(milliseconds: 250));
    retryScheduler.fireNext(const Duration(milliseconds: 250));
    profileController.add(profileDocument);
    await populated.future.timeout(const Duration(seconds: 5));
    await retryScheduler.waitForActive(stableWindow);
    final stabilityTimer = retryScheduler.timers.singleWhere(
      (timer) => timer.delay == stableWindow && timer.isActive,
    );

    await db
        .collection('users')
        .doc(meUid)
        .collection('friends')
        .doc(friendId)
        .delete();
    await removed.future.timeout(const Duration(seconds: 5));

    expect(stabilityTimer.isActive, isFalse);
    stabilityTimer.fire();
    expect(
      retryScheduler.timers.where((timer) => timer.isActive),
      isEmpty,
      reason: 'a stale health callback must not retain or revive the child',
    );
  });

  test(
    'a stable recovered listener resets backoff for a later outage',
    () async {
      const friendId = 'stable-profile-reset-uid';
      const firstDelay = Duration(milliseconds: 250);
      const stableWindow = Duration(seconds: 30);
      await seedFriendEdge(friendId, {'userId': friendId});
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Stable friend',
      });
      final profileDocument = await db
          .collection('publicProfiles')
          .doc(friendId)
          .get();

      final profileController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
      final presenceController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      addTearDown(profileController.close);
      addTearDown(presenceController.close);
      final firstAttach = Completer<void>();
      var attaches = 0;
      final retryScheduler = _ManualRetryScheduler();
      final resettingService = FriendService(
        firestore: db,
        auth: auth,
        publicProfileWatch: (_) {
          attaches += 1;
          if (!firstAttach.isCompleted) firstAttach.complete();
          return profileController.stream;
        },
        socialPresenceWatch: (_) => presenceController.stream,
        childListenerRetryScheduler: retryScheduler.call,
      );
      final subscription = resettingService.watchFriends().listen((_) {});
      addTearDown(subscription.cancel);

      await firstAttach.future.timeout(const Duration(seconds: 5));
      profileController.addError(StateError('first outage'));
      await retryScheduler.waitForActive(firstDelay);
      retryScheduler.fireNext(firstDelay);
      expect(attaches, 2);

      profileController.add(profileDocument);
      await retryScheduler.waitForActive(stableWindow);
      retryScheduler.fireNext(stableWindow);
      profileController.addError(StateError('later independent outage'));
      await retryScheduler.waitForActive(firstDelay);

      expect(
        retryScheduler.timers
            .where((timer) => timer.delay == firstDelay)
            .length,
        2,
        reason: '30 seconds of health resets the next outage to attempt one',
      );
    },
  );

  test(
    'a malformed public profile degrades and retries without escaping',
    () async {
      const friendId = 'malformed-profile-uid';
      await seedFriendEdge(friendId, {
        'userId': friendId,
        'displayName': 'Safe fallback',
      });
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Malformed profile',
        'premiumIdentity': 'true',
      });
      final presenceController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      addTearDown(presenceController.close);
      final retryScheduler = _ManualRetryScheduler();
      final malformedService = FriendService(
        firestore: db,
        auth: auth,
        socialPresenceWatch: (_) => presenceController.stream,
        childListenerRetryScheduler: retryScheduler.call,
      );

      final degraded = Completer<FriendUser>();
      final subscription = malformedService.watchFriends().listen((friends) {
        if (friends.length == 1 && !degraded.isCompleted) {
          degraded.complete(friends.single);
        }
      });
      addTearDown(subscription.cancel);
      final friend = await degraded.future.timeout(const Duration(seconds: 5));

      expect(friend.displayName, 'Safe fallback');
      expect(friend.isOnline, isFalse);
      await retryScheduler.waitForActive(const Duration(milliseconds: 250));
    },
  );

  test(
    'malformed presence fails closed and retries without escaping',
    () async {
      const friendId = 'malformed-presence-uid';
      await seedFriendEdge(friendId, {'userId': friendId});
      await db.collection('publicProfiles').doc(friendId).set({
        'displayName': 'Visible friend',
      });
      await db.collection('socialPresence').doc(friendId).set({
        'isOnline': 'true',
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 9, 4, 12)),
      });
      final retryScheduler = _ManualRetryScheduler();
      final malformedService = FriendService(
        firestore: db,
        auth: auth,
        childListenerRetryScheduler: retryScheduler.call,
      );

      final failedClosed = Completer<FriendUser>();
      final subscription = malformedService.watchFriends().listen((friends) {
        if (friends.length == 1 &&
            friends.single.displayName == 'Visible friend' &&
            !friends.single.isOnline &&
            !failedClosed.isCompleted) {
          failedClosed.complete(friends.single);
        }
      });
      addTearDown(subscription.cancel);
      final friend = await failedClosed.future.timeout(
        const Duration(seconds: 5),
      );

      expect(friend.isOnline, isFalse);
      expect(friend.lastSeen, isNull);
      await retryScheduler.waitForActive(const Duration(milliseconds: 250));
    },
  );

  test(
    'a removed friend cannot be resurrected by a queued profile retry',
    () async {
      const friendId = 'removed-before-retry-uid';
      await seedFriendEdge(friendId, {
        'userId': friendId,
        'displayName': 'Removed fallback',
      });

      var attempts = 0;
      final retryScheduler = _ManualRetryScheduler();
      final retryingService = FriendService(
        firestore: db,
        auth: auth,
        publicProfileWatch: (_) {
          attempts += 1;
          return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
            StateError('profile listener terminated'),
          );
        },
        childListenerRetryScheduler: retryScheduler.call,
      );
      final degraded = Completer<void>();
      final removed = Completer<void>();
      final subscription = retryingService.watchFriends().listen((friends) {
        if (friends.length == 1 && !degraded.isCompleted) degraded.complete();
        if (degraded.isCompleted && friends.isEmpty && !removed.isCompleted) {
          removed.complete();
        }
      });
      addTearDown(subscription.cancel);

      await degraded.future.timeout(const Duration(seconds: 5));
      await retryScheduler.scheduled.future.timeout(const Duration(seconds: 5));
      await db
          .collection('users')
          .doc(meUid)
          .collection('friends')
          .doc(friendId)
          .delete();
      await removed.future.timeout(const Duration(seconds: 5));
      final retryTimer = retryScheduler.timers.singleWhere(
        (timer) => timer.delay == const Duration(milliseconds: 250),
      );
      expect(retryTimer.isActive, isFalse);
      retryTimer.fire();

      expect(attempts, 1);
    },
  );

  test(
    'an auth-boundary clear cancels a queued child-listener retry',
    () async {
      const friendId = 'signed-out-before-retry-uid';
      await seedFriendEdge(friendId, {
        'userId': friendId,
        'displayName': 'Signed-out fallback',
      });

      var attempts = 0;
      final retryScheduler = _ManualRetryScheduler();
      final retryingService = FriendService(
        firestore: db,
        auth: auth,
        publicProfileWatch: (_) {
          attempts += 1;
          return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
            StateError('profile listener terminated'),
          );
        },
        childListenerRetryScheduler: retryScheduler.call,
      );
      final degraded = Completer<void>();
      final done = Completer<void>();
      final subscription = retryingService.watchFriends().listen((friends) {
        if (friends.length == 1 && !degraded.isCompleted) degraded.complete();
      }, onDone: done.complete);
      addTearDown(subscription.cancel);

      await degraded.future.timeout(const Duration(seconds: 5));
      await retryScheduler.scheduled.future.timeout(const Duration(seconds: 5));
      FriendService.clearSharedReadCaches();
      await done.future.timeout(const Duration(seconds: 5));
      final retryTimer = retryScheduler.timers.singleWhere(
        (timer) => timer.delay == const Duration(milliseconds: 250),
      );
      expect(retryTimer.isActive, isFalse);
      retryTimer.fire();

      expect(attempts, 1);
    },
  );

  test(
    'service instances share one friends fanout for the same session',
    () async {
      final otherSurface = FriendService(firestore: db, auth: auth);
      final firstSurfaceStream = service.watchFriends();
      final otherSurfaceStream = otherSurface.watchFriends();
      expect(
        identical(firstSurfaceStream, otherSurfaceStream),
        isTrue,
        reason: 'Home and Chats must not build duplicate 2N+1 listener graphs',
      );

      await seedFriendEdge('shared-uid', {'displayName': 'Shared fallback'});
      final values = await Future.wait([
        firstSurfaceStream.firstWhere((items) => items.isNotEmpty),
        otherSurfaceStream.firstWhere((items) => items.isNotEmpty),
      ]).timeout(const Duration(seconds: 5));

      expect(values.first.single.id, 'shared-uid');
      expect(values.last.single.id, 'shared-uid');
    },
  );

  test(
    'the last cancellation evicts the shared fanout synchronously',
    () async {
      await seedFriendEdge('fresh-uid', {'displayName': 'Fresh'});
      final first = service.watchFriends();
      final firstValue = Completer<List<FriendUser>>();
      final subscription = first.listen((friends) {
        if (friends.isNotEmpty && !firstValue.isCompleted) {
          firstValue.complete(friends);
        }
      });
      addTearDown(subscription.cancel);
      await firstValue.future.timeout(const Duration(seconds: 5));

      final cancellation = subscription.cancel();
      final replacement = service.watchFriends();
      expect(
        identical(first, replacement),
        isFalse,
        reason:
            'the retired stream must leave the process cache before async '
            'Firestore cancellations finish',
      );
      await cancellation;

      final friends = await replacement
          .firstWhere((items) => items.isNotEmpty)
          .timeout(const Duration(seconds: 5));
      expect(friends.single.id, 'fresh-uid');
    },
  );

  test(
    'an auth-boundary clear closes active streams without replaying them',
    () async {
      await seedFriendEdge('old-uid', {'displayName': 'Old account friend'});
      final oldStream = service.watchFriends();
      final oldValue = Completer<void>();
      final oldDone = Completer<void>();
      final subscription = oldStream.listen((friends) {
        if (friends.isNotEmpty && !oldValue.isCompleted) oldValue.complete();
      }, onDone: oldDone.complete);
      addTearDown(subscription.cancel);
      await oldValue.future.timeout(const Duration(seconds: 5));

      FriendService.clearSharedReadCaches();
      await oldDone.future.timeout(const Duration(seconds: 5));

      final replacement = service.watchFriends();
      expect(identical(oldStream, replacement), isFalse);
      final friends = await replacement
          .firstWhere((items) => items.isNotEmpty)
          .timeout(const Duration(seconds: 5));
      expect(friends.single.id, 'old-uid');
    },
  );

  test(
    'a retained stream cannot replay old-account friends after auth switches',
    () async {
      final delayedAuth = _DelayedUserChangesAuth(MockUser(uid: meUid));
      final switchedService = FriendService(firestore: db, auth: delayedAuth);
      await seedFriendEdge('old-uid', {'displayName': 'Old account friend'});

      final oldStream = switchedService.watchFriends();
      final firstValue = Completer<void>();
      final firstSubscription = oldStream.listen((friends) {
        if (friends.isNotEmpty && !firstValue.isCompleted) {
          firstValue.complete();
        }
      });
      addTearDown(firstSubscription.cancel);
      await firstValue.future.timeout(const Duration(seconds: 5));

      // Model the interval after FirebaseAuth.currentUser changes but before
      // userChanges delivers its asynchronous notification.
      delayedAuth.activeUser = MockUser(uid: 'new-account');
      final lateValues = <List<FriendUser>>[];
      final lateDone = Completer<void>();
      final lateSubscription = oldStream.listen(
        lateValues.add,
        onDone: lateDone.complete,
      );
      addTearDown(lateSubscription.cancel);

      await lateDone.future.timeout(const Duration(seconds: 5));
      expect(
        lateValues,
        isEmpty,
        reason: 'cached identities from the prior account must not replay',
      );
    },
  );

  test(
    'active listeners drop old-account events during delayed auth notification',
    () async {
      final delayedAuth = _DelayedUserChangesAuth(MockUser(uid: meUid));
      final switchedService = FriendService(firestore: db, auth: delayedAuth);
      await seedFriendEdge('old-uid', {'displayName': 'Old account friend'});
      await db.collection('publicProfiles').doc('old-uid').set({
        'displayName': 'Before switch',
      });

      final values = <List<FriendUser>>[];
      final firstValue = Completer<void>();
      final done = Completer<void>();
      final subscription = switchedService.watchFriends().listen((friends) {
        values.add(friends);
        if (friends.isNotEmpty && !firstValue.isCompleted) {
          firstValue.complete();
        }
      }, onDone: done.complete);
      addTearDown(subscription.cancel);
      await firstValue.future.timeout(const Duration(seconds: 5));

      delayedAuth.activeUser = MockUser(uid: 'new-account');
      await db.collection('publicProfiles').doc('old-uid').update({
        'displayName': 'Must not cross the auth boundary',
      });

      await done.future.timeout(const Duration(seconds: 5));
      expect(
        values.expand((friends) => friends).map((friend) => friend.displayName),
        isNot(contains('Must not cross the auth boundary')),
      );
    },
  );

  test(
    'a synchronous auth retirement cancels its candidate subscription',
    () async {
      final synchronousAuth = _SynchronousUserChangesAuth(
        activeUser: MockUser(uid: meUid),
        nextUser: MockUser(uid: 'new-account'),
      );
      final synchronousService = FriendService(
        firestore: db,
        auth: synchronousAuth,
      );
      final done = Completer<void>();
      final subscription = synchronousService.watchFriends().listen(
        (_) {},
        onDone: done.complete,
      );
      addTearDown(subscription.cancel);

      await done.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(synchronousAuth.cancellations, 1);
    },
  );

  test(
    'friend requests replay to late listeners of a non-replay source',
    () async {
      final source = StreamController<List<FriendRequest>>.broadcast();
      addTearDown(source.close);
      final requestService = FriendService(
        firestore: db,
        auth: auth,
        friendRequestsWatch: (_) => source.stream,
      );
      final requestsStream = requestService.watchFriendRequests();
      final initialCount = Completer<void>();
      final countSubscription = requestService
          .watchPendingFriendRequestCount()
          .listen((requestCount) {
            if (requestCount == 1 && !initialCount.isCompleted) {
              initialCount.complete();
            }
          });
      addTearDown(countSubscription.cancel);

      source.add(const [
        FriendRequest(
          senderId: 'sender',
          senderName: 'Ola',
          senderEmail: '',
          senderPhotoUrl: null,
          createdAt: null,
        ),
      ]);
      await initialCount.future.timeout(const Duration(seconds: 5));

      final replayed = await requestsStream.first.timeout(
        const Duration(seconds: 5),
      );
      expect(replayed.single.senderName, 'Ola');
    },
  );

  test(
    'a friends setup error retires the poisoned shared generation',
    () async {
      final failingDb = _ThrowingFirestore();
      final failingService = FriendService(firestore: failingDb, auth: auth);
      final first = failingService.watchFriends();
      final firstError = Completer<Object>();
      final firstDone = Completer<void>();
      final firstSubscription = first.listen(
        (_) {},
        onError: (Object error) => firstError.complete(error),
        onDone: firstDone.complete,
      );
      addTearDown(firstSubscription.cancel);

      expect(
        await firstError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
      await firstDone.future.timeout(const Duration(seconds: 5));

      final replacement = failingService.watchFriends();
      expect(
        identical(first, replacement),
        isFalse,
        reason: 'a later surface must not inherit a source-less fanout',
      );

      final replacementError = Completer<Object>();
      final replacementSubscription = replacement.listen(
        (_) {},
        onError: (Object error) => replacementError.complete(error),
      );
      addTearDown(replacementSubscription.cancel);
      expect(
        await replacementError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
      expect(
        failingDb.collectionReads,
        2,
        reason: 'the replacement must make a fresh setup attempt',
      );
    },
  );

  test(
    'a non-closing request error evicts and resubscribes the fanout',
    () async {
      final source = StreamController<List<FriendRequest>>.broadcast();
      addTearDown(source.close);
      var sourceSubscriptions = 0;
      final requestService = FriendService(
        firestore: db,
        auth: auth,
        friendRequestsWatch: (_) {
          sourceSubscriptions += 1;
          return source.stream;
        },
      );
      final first = requestService.watchFriendRequests();
      final firstError = Completer<Object>();
      final firstDone = Completer<void>();
      final firstSubscription = first.listen(
        (_) {},
        onError: (Object error) => firstError.complete(error),
        onDone: firstDone.complete,
      );
      addTearDown(firstSubscription.cancel);

      source.addError(StateError('listener failed without closing'));
      expect(
        await firstError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
      await firstDone.future.timeout(const Duration(seconds: 5));

      final replacement = requestService.watchFriendRequests();
      expect(identical(first, replacement), isFalse);
      final replacementValue = Completer<List<FriendRequest>>();
      final replacementSubscription = replacement.listen(
        replacementValue.complete,
      );
      addTearDown(replacementSubscription.cancel);
      source.add(const [
        FriendRequest(
          senderId: 'retry-sender',
          senderName: 'Retry succeeded',
          senderEmail: '',
          senderPhotoUrl: null,
          createdAt: null,
        ),
      ]);

      final requests = await replacementValue.future.timeout(
        const Duration(seconds: 5),
      );
      expect(requests.single.senderId, 'retry-sender');
      expect(sourceSubscriptions, 2);
    },
  );

  test(
    'a synchronous request setup failure retires its half-started fanout',
    () async {
      var setupAttempts = 0;
      final requestService = FriendService(
        firestore: db,
        auth: auth,
        friendRequestsWatch: (_) {
          setupAttempts += 1;
          throw StateError('request setup failed');
        },
      );
      final first = requestService.watchFriendRequests();
      final firstError = Completer<Object>();
      final firstDone = Completer<void>();
      final firstSubscription = first.listen(
        (_) {},
        onError: (Object error) => firstError.complete(error),
        onDone: firstDone.complete,
      );
      addTearDown(firstSubscription.cancel);

      expect(
        await firstError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
      await firstDone.future.timeout(const Duration(seconds: 5));

      final replacement = requestService.watchFriendRequests();
      expect(identical(first, replacement), isFalse);
      final replacementError = Completer<Object>();
      final replacementSubscription = replacement.listen(
        (_) {},
        onError: (Object error) => replacementError.complete(error),
      );
      addTearDown(replacementSubscription.cancel);
      expect(
        await replacementError.future.timeout(const Duration(seconds: 5)),
        isA<StateError>(),
      );
      expect(setupAttempts, 2);
    },
  );

  test(
    'a block stays visible and unblockable when its profile is missing',
    () async {
      await db
          .collection('users')
          .doc(meUid)
          .collection('blocked')
          .doc('private-uid')
          .set({'blockedAt': DateTime.now()});

      final blocked = await service.watchBlockedUsers().first;
      expect(blocked, hasLength(1));
      expect(blocked.single.id, 'private-uid');
      expect(blocked.single.displayName, 'Blocked user');
    },
  );
}
