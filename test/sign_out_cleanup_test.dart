import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/providers/auth_provider.dart';
import 'package:yovoice/services/firestore_service.dart';

/// Signing out has two pieces of cleanup that the SERVER only permits while
/// the session is still live:
///
///  * `users/{uid}` presence — `firestore.rules` gates the update on
///    `isSignedIn() && isOwner(uid)`.
///  * `fcmTokens/{token}` — deleting it needs `isOwner(uid)`.
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

  @override
  Future<void> setOfflineForUser(String userId) async {
    offlineWrites.add(userId);
    sessionAliveAtWrite.add(_auth.currentUser != null);

    final thrown = failure;
    if (thrown != null) throw thrown;

    await super.setOfflineForUser(userId);
  }
}

class _RecordingDeviceUnregister {
  _RecordingDeviceUnregister(this._auth);

  final FirebaseAuth _auth;

  int calls = 0;
  final List<bool> sessionAliveAtCall = <bool>[];
  Object? failure;

  Future<void> call() async {
    calls += 1;
    sessionAliveAtCall.add(_auth.currentUser != null);

    final thrown = failure;
    if (thrown != null) throw thrown;
  }
}

class _Harness {
  _Harness({String uid = 'user-1'})
    : auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'signed-in@example.com'),
      ),
      firestore = FakeFirebaseFirestore() {
    presence = _RecordingPresenceService(auth, firestore);
    unregister = _RecordingDeviceUnregister(auth);
    service = AuthService(
      firebaseAuth: auth,
      firestoreService: FirestoreService(firestore: firestore),
      presenceService: presence,
      unregisterDeviceToken: unregister.call,
    );
  }

  final MockFirebaseAuth auth;
  final FakeFirebaseFirestore firestore;
  late final _RecordingPresenceService presence;
  late final _RecordingDeviceUnregister unregister;
  late final AuthService service;
}

void main() {
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

    test('unregisters this device for push while the session is still live', () async {
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
    });

    test('does no cleanup when nobody is signed in', () async {
      final harness = _Harness();
      await harness.auth.signOut();

      await harness.service.signOut();

      expect(harness.presence.offlineWrites, isEmpty);
      expect(harness.unregister.calls, 0);
    });
  });

  group('AuthService.signOut resilience', () {
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
          RegExp(r'AuthService\(\)?\.signOut|_authService\.signOut').hasMatch(source),
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
