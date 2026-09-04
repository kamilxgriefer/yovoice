import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/services/firestore_service.dart';

/// Signing out owns the server-side cleanup that requires a live session and
/// the local privacy cleanup that must complete before another account starts:
///
///  * `users/{uid}` presence — `firestore.rules` gates the update on
///    `isSignedIn() && isOwner(uid)`.
///  * `fcmTokens/{token}` — deleting it needs `isOwner(uid)`.
///  * persisted pending texts and attachment payloads — removing them keeps a
///    shared device from exposing one account's unsent private content.
///
/// Both used to be written on the wrong side of that boundary (presence) or
/// skipped entirely (the token, on three of five sign-out entry points).
/// These tests pin the seam, not Firebase: what matters is that both
/// cleanups are issued BEFORE `FirebaseAuth.signOut()` clears the session,
/// on every path, and that neither one failing can trap the user in a
/// session they asked to leave.

/// Records every offline write together with whether the auth session was
/// still alive at the moment it was issued. That boolean is the whole point:
/// a write recorded with `false` is a write the deployed ruleset denies.
class _RecordingPresenceService extends PresenceService {
  _RecordingPresenceService(FirebaseAuth auth, FirebaseFirestore firestore)
    : _auth = auth,
      super(auth: auth, firestore: firestore);

  final FirebaseAuth _auth;

  final List<String> offlineWrites = <String>[];
  final List<bool> sessionAliveAtWrite = <bool>[];
  Object? failure;
  bool neverCompletes = false;

  @override
  Future<void> setOfflineForUser(String userId) async {
    offlineWrites.add(userId);
    sessionAliveAtWrite.add(_auth.currentUser != null);

    final thrown = failure;
    if (thrown != null) throw thrown;
    if (neverCompletes) await Completer<void>().future;

    await super.setOfflineForUser(userId);
  }
}

class _RecordingDeviceUnregister {
  _RecordingDeviceUnregister(this._auth);

  final FirebaseAuth _auth;

  int calls = 0;
  final List<bool> sessionAliveAtCall = <bool>[];
  Object? failure;
  bool neverCompletes = false;

  Future<void> call() async {
    calls += 1;
    sessionAliveAtCall.add(_auth.currentUser != null);

    final thrown = failure;
    if (thrown != null) throw thrown;
    if (neverCompletes) await Completer<void>().future;
  }
}

class _RecordingLocalSensitiveDataClear {
  _RecordingLocalSensitiveDataClear(this._auth);

  final FirebaseAuth _auth;
  final List<String> owners = <String>[];
  final List<bool> sessionAliveAtCall = <bool>[];
  Object? failure;
  bool neverCompletes = false;

  Future<void> call(String userId) async {
    owners.add(userId);
    sessionAliveAtCall.add(_auth.currentUser != null);
    final thrown = failure;
    if (thrown != null) throw thrown;
    if (neverCompletes) await Completer<void>().future;
  }
}

class _RecordingEphemeralMediaAccessClear {
  _RecordingEphemeralMediaAccessClear(this._auth);

  final FirebaseAuth _auth;
  int calls = 0;
  final List<bool> sessionAliveAtCall = <bool>[];

  void call() {
    calls += 1;
    sessionAliveAtCall.add(_auth.currentUser != null);
  }
}

class _RecordingVoiceCleanup {
  _RecordingVoiceCleanup(this._auth, {required this.active});

  final FirebaseAuth _auth;
  bool active;
  bool roomSession = true;
  String? roomId = 'room-1';
  String? directCallId;
  bool neverCompletes = false;
  Object? leaveFailure;
  int disconnectCalls = 0;
  final List<String> leftRooms = <String>[];
  final List<String> endedCalls = <String>[];
  final List<bool> sessionAliveAtDisconnect = <bool>[];
  final List<bool> sessionAliveAtLeave = <bool>[];

  ({String? directCallId, bool isActive, bool isRoomSession, String? roomId})
  read() => (
    directCallId: directCallId,
    isActive: active,
    isRoomSession: roomSession,
    roomId: roomId,
  );

  Future<void> disconnect() async {
    disconnectCalls += 1;
    sessionAliveAtDisconnect.add(_auth.currentUser != null);
    // Mirrors VoiceCallService: local identity and microphone state are
    // cleared before the asynchronous LiveKit disposal begins.
    active = false;
    roomId = null;
    if (neverCompletes) await Completer<void>().future;
  }

  Future<void> leave(String roomId) async {
    leftRooms.add(roomId);
    sessionAliveAtLeave.add(_auth.currentUser != null);
    final failure = leaveFailure;
    if (failure != null) throw failure;
    if (neverCompletes) await Completer<void>().future;
  }

  Future<void> endCall(String callId) async {
    endedCalls.add(callId);
    sessionAliveAtLeave.add(_auth.currentUser != null);
    if (neverCompletes) await Completer<void>().future;
  }
}

class _Harness {
  _Harness({
    String uid = 'user-1',
    Duration cleanupTimeout = const Duration(seconds: 10),
    bool activeVoiceSession = false,
  }) : auth = MockFirebaseAuth(
         signedIn: true,
         mockUser: MockUser(uid: uid, email: 'signed-in@example.com'),
       ),
       firestore = FakeFirebaseFirestore() {
    presence = _RecordingPresenceService(auth, firestore);
    unregister = _RecordingDeviceUnregister(auth);
    localData = _RecordingLocalSensitiveDataClear(auth);
    mediaGrants = _RecordingEphemeralMediaAccessClear(auth);
    voice = _RecordingVoiceCleanup(auth, active: activeVoiceSession);
    service = AuthService(
      firebaseAuth: auth,
      firestoreService: FirestoreService(firestore: firestore),
      presenceService: presence,
      unregisterDeviceToken: unregister.call,
      clearLocalSensitiveData: localData.call,
      clearEphemeralMediaAccess: mediaGrants.call,
      activeVoiceSessionReader: voice.read,
      disconnectActiveVoice: voice.disconnect,
      leaveActiveRoom: voice.leave,
      endActiveDirectCall: voice.endCall,
      bestEffortCleanupTimeout: cleanupTimeout,
    );
  }

  final MockFirebaseAuth auth;
  final FakeFirebaseFirestore firestore;
  late final _RecordingPresenceService presence;
  late final _RecordingDeviceUnregister unregister;
  late final _RecordingLocalSensitiveDataClear localData;
  late final _RecordingEphemeralMediaAccessClear mediaGrants;
  late final _RecordingVoiceCleanup voice;
  late final AuthService service;
}

void main() {
  tearDown(FriendService.clearSharedReadCaches);

  group('AuthService.signOut cleanup ordering', () {
    test('marks the account offline while the session is still live', () async {
      final harness = _Harness();

      await harness.service.signOut();

      expect(
        harness.presence.offlineWrites,
        <String>['user-1'],
        reason:
            'the offline write must target the uid that is signing out, '
            'exactly once',
      );
      expect(
        harness.presence.sessionAliveAtWrite,
        <bool>[true],
        reason:
            'users/{uid} updates require isSignedIn() && isOwner(uid); a '
            'write issued after FirebaseAuth.signOut() is denied and leaves '
            'the account showing as Online to its friends',
      );
      expect(harness.auth.currentUser, isNull);
    });

    test('the offline write actually lands on users/{uid}', () async {
      final harness = _Harness();
      await harness.firestore.collection('users').doc('user-1').set({
        'isOnline': true,
      });

      await harness.service.signOut();

      final stored = await harness.firestore
          .collection('users')
          .doc('user-1')
          .get();
      expect(stored.data()?['isOnline'], isFalse);
      expect(stored.data()?['lastSeen'], isNotNull);
      expect(stored.data()?['presenceUpdatedAt'], isNotNull);
    });

    test(
      'unregisters this device for push while the session is still live',
      () async {
        final harness = _Harness();

        await harness.service.signOut();

        expect(harness.unregister.calls, 1);
        expect(
          harness.unregister.sessionAliveAtCall,
          <bool>[true],
          reason:
              'deleting fcmTokens/{token} requires isOwner(uid); skipping it '
              'leaves the previous account receiving push on a shared device',
        );
      },
    );

    test(
      'purges pending private local data before the account changes',
      () async {
        final harness = _Harness();

        await harness.service.signOut();

        expect(harness.localData.owners, <String>['user-1']);
        expect(harness.localData.sessionAliveAtCall, <bool>[true]);
        expect(harness.auth.currentUser, isNull);
      },
    );

    test(
      'invalidates ephemeral media grants immediately while the session is live',
      () async {
        final harness = _Harness();

        final signOut = harness.service.signOut();
        expect(harness.mediaGrants.calls, 1);
        expect(harness.mediaGrants.sessionAliveAtCall, <bool>[true]);

        await signOut;
        expect(harness.auth.currentUser, isNull);
      },
    );

    test('does no cleanup when nobody is signed in', () async {
      final harness = _Harness();
      await harness.auth.signOut();

      await harness.service.signOut();

      expect(harness.presence.offlineWrites, isEmpty);
      expect(harness.unregister.calls, 0);
      expect(harness.localData.owners, isEmpty);
    });
  });

  group('AuthService.signOut resilience', () {
    test(
      'a failed Firebase sign-out keeps the authenticated friends stream live',
      () async {
        final harness = _Harness();
        await harness.firestore
            .collection('users')
            .doc('user-1')
            .collection('friends')
            .doc('friend-1')
            .set({'displayName': 'Friend'});
        await harness.firestore
            .collection('publicProfiles')
            .doc('friend-1')
            .set({'displayName': 'Before failed sign-out'});
        final friends = FriendService(
          firestore: harness.firestore,
          auth: harness.auth,
        );
        final initial = Completer<void>();
        final updated = Completer<void>();
        final subscription = friends.watchFriends().listen((items) {
          if (items.any(
                (friend) => friend.displayName == 'Before failed sign-out',
              ) &&
              !initial.isCompleted) {
            initial.complete();
          }
          if (items.any(
                (friend) => friend.displayName == 'After failed sign-out',
              ) &&
              !updated.isCompleted) {
            updated.complete();
          }
        });
        addTearDown(subscription.cancel);
        await initial.future.timeout(const Duration(seconds: 5));

        whenCalling(
          Invocation.method(#signOut, [null]),
        ).on(harness.auth).thenThrow(FirebaseAuthException(code: 'internal'));

        await expectLater(
          harness.service.signOut(),
          throwsA(isA<FirebaseAuthException>()),
        );
        expect(harness.auth.currentUser?.uid, 'user-1');

        await harness.firestore
            .collection('publicProfiles')
            .doc('friend-1')
            .update({'displayName': 'After failed sign-out'});
        await updated.future.timeout(const Duration(seconds: 5));
      },
    );

    test('a denied presence write still signs the user out', () async {
      final harness = _Harness();
      harness.presence.failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      await harness.service.signOut();

      expect(harness.presence.offlineWrites, <String>['user-1']);
      expect(harness.auth.currentUser, isNull);
    });

    test('a failed token unregistration still signs the user out', () async {
      final harness = _Harness();
      harness.unregister.failure = StateError('messaging unavailable');

      await harness.service.signOut();

      expect(harness.unregister.calls, 1);
      expect(
        harness.presence.offlineWrites,
        <String>['user-1'],
        reason: 'one failing cleanup must not skip the other',
      );
      expect(harness.auth.currentUser, isNull);
    });

    test('never-completing cleanup cannot trap sign-out', () async {
      final harness = _Harness(
        cleanupTimeout: const Duration(milliseconds: 10),
      );
      harness.unregister.neverCompletes = true;
      harness.presence.neverCompletes = true;

      await harness.service.signOut().timeout(const Duration(seconds: 1));

      expect(harness.unregister.calls, 1);
      expect(harness.presence.offlineWrites, <String>['user-1']);
      expect(harness.auth.currentUser, isNull);
    });

    test('different service instances share one in-flight sign-out', () async {
      final harness = _Harness(
        cleanupTimeout: const Duration(milliseconds: 20),
      );
      harness.unregister.neverCompletes = true;
      final secondService = AuthService(
        firebaseAuth: harness.auth,
        firestoreService: FirestoreService(firestore: harness.firestore),
        presenceService: harness.presence,
        unregisterDeviceToken: harness.unregister.call,
        clearLocalSensitiveData: harness.localData.call,
        activeVoiceSessionReader: harness.voice.read,
        disconnectActiveVoice: harness.voice.disconnect,
        leaveActiveRoom: harness.voice.leave,
        endActiveDirectCall: harness.voice.endCall,
        bestEffortCleanupTimeout: const Duration(milliseconds: 20),
      );

      final first = harness.service.signOut();
      final second = secondService.signOut();

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(harness.unregister.calls, 1);
      expect(harness.presence.offlineWrites, <String>['user-1']);
      expect(harness.auth.currentUser, isNull);
    });
  });

  group('AuthService.signOut active voice cleanup', () {
    test('disconnects and leaves a room while auth is still valid', () async {
      final harness = _Harness(activeVoiceSession: true);

      await harness.service.signOut();

      expect(harness.voice.disconnectCalls, 1);
      expect(harness.voice.leftRooms, <String>['room-1']);
      expect(harness.voice.sessionAliveAtDisconnect, <bool>[true]);
      expect(harness.voice.sessionAliveAtLeave, <bool>[true]);
      expect(harness.voice.active, isFalse);
      expect(harness.auth.currentUser, isNull);
    });

    test('a direct call disconnects without using room leave', () async {
      final harness = _Harness(activeVoiceSession: true);
      harness.voice.roomSession = false;
      harness.voice.directCallId = 'call-1';

      await harness.service.signOut();

      expect(harness.voice.disconnectCalls, 1);
      expect(harness.voice.leftRooms, isEmpty);
      expect(harness.voice.endedCalls, <String>['call-1']);
      expect(harness.voice.sessionAliveAtLeave, <bool>[true]);
      expect(harness.voice.active, isFalse);
      expect(harness.auth.currentUser, isNull);
    });

    test('a stalled voice teardown cannot trap sign-out', () async {
      final harness = _Harness(
        activeVoiceSession: true,
        cleanupTimeout: const Duration(milliseconds: 10),
      );
      harness.voice.neverCompletes = true;

      await harness.service.signOut().timeout(const Duration(seconds: 1));

      expect(harness.voice.disconnectCalls, 1);
      expect(harness.voice.leftRooms, <String>['room-1']);
      expect(
        harness.voice.active,
        isFalse,
        reason: 'local audio state must clear before network disposal waits',
      );
      expect(harness.auth.currentUser, isNull);
    });

    test('a failed roster leave cannot trap sign-out', () async {
      final harness = _Harness(activeVoiceSession: true);
      harness.voice.leaveFailure = StateError('room unavailable');

      await harness.service.signOut();

      expect(harness.voice.disconnectCalls, 1);
      expect(harness.voice.leftRooms, <String>['room-1']);
      expect(harness.voice.active, isFalse);
      expect(harness.auth.currentUser, isNull);
    });

    test('already-lost auth still disconnects local room audio', () async {
      final harness = _Harness(activeVoiceSession: true);
      await harness.auth.signOut();

      await harness.service.signOut();

      expect(harness.voice.disconnectCalls, 1);
      expect(harness.voice.leftRooms, isEmpty);
      expect(harness.voice.active, isFalse);
      expect(harness.auth.currentUser, isNull);
    });
  });

  group('AuthController.signOut', () {
    test('runs the full cleanup through the shared AuthService', () async {
      final harness = _Harness(uid: 'user-2');
      final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(harness.service)],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider).signOut();

      expect(harness.presence.offlineWrites, <String>['user-2']);
      expect(harness.presence.sessionAliveAtWrite, <bool>[true]);
      expect(harness.unregister.calls, 1);
      expect(harness.unregister.sessionAliveAtCall, <bool>[true]);
      expect(container.read(authErrorProvider), isNull);
      expect(harness.auth.currentUser, isNull);
    });
  });

  group('sign-out convergence', () {
    /// The original defect was not one bad line, it was five sign-out entry
    /// points doing three different amounts of cleanup. Ownership of that
    /// cleanup now sits in exactly one place, and this keeps a sixth entry
    /// point from quietly reintroducing a partial copy of it.
    test('only AuthService owns the sign-out cleanup', () {
      const owners = <String>{
        'lib/features/auth/data/auth_service.dart',
        'lib/features/notifications/data/services/push_notification_service.dart',
        'lib/core/presence/presence_service.dart',
      };

      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final path = entity.path.replaceAll(r'\', '/');
        if (owners.any(path.endsWith)) continue;

        final source = entity.readAsStringSync();
        if (source.contains('unregisterCurrentDevice(') ||
            source.contains('setOfflineForUser(')) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'sign-out cleanup must go through AuthService.signOut() so every '
            'entry point gets all of it; these files run their own copy',
      );
    });

    test('every UI sign-out entry point delegates to AuthService', () {
      const entryPoints = <String>[
        'lib/features/settings/presentation/screens/settings_screen.dart',
        'lib/features/settings/presentation/screens/device_sessions_screen.dart',
        'lib/features/settings/presentation/screens/two_factor_authentication_screen.dart',
        'lib/features/profile/presentation/screens/profile_screen.dart',
      ];

      for (final path in entryPoints) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('signOut'),
          isTrue,
          reason: '$path is expected to keep a sign-out affordance',
        );
        expect(
          RegExp(
            r'AuthService\(\)?\.signOut|_authService\.signOut',
          ).hasMatch(source),
          isTrue,
          reason: '$path must sign out through AuthService.signOut()',
        );
      }
    });
  });

  group('PresenceLifecycle', () {
    test('no longer issues an offline write it cannot be allowed to make', () {
      final source = File(
        'lib/core/presence/presence_service.dart',
      ).readAsStringSync();

      final listener = source.substring(
        source.indexOf('Future<void> _handleAuthStateChanged'),
        source.indexOf('void didChangeAppLifecycleState'),
      );

      expect(
        listener.contains('_safeSetOffline'),
        isFalse,
        reason:
            'authStateChanges fires after the session is cleared, so an '
            'offline write from that listener is denied every time; the '
            'lifecycle (backgrounding) path keeps its own write',
      );
      expect(
        source.contains('_safeSetOffline'),
        isTrue,
        reason:
            'the backgrounding path is correct and must keep marking the '
            'signed-in user offline',
      );
    });
  });
}
