import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/services/firestore_service.dart';
import 'package:yovoice/shared/models/app_user.dart';

class _AdditionalUserInfo extends AdditionalUserInfo {
  _AdditionalUserInfo({required super.isNewUser})
    : super(providerId: AppleAuthProvider.PROVIDER_ID);
}

class _UserCredential implements UserCredential {
  _UserCredential({required this.user, required bool isNewUser})
    : additionalUserInfo = _AdditionalUserInfo(isNewUser: isNewUser);

  @override
  final User? user;

  @override
  final AdditionalUserInfo additionalUserInfo;

  @override
  AuthCredential? get credential => null;
}

class _RecordingFirebaseAuth extends MockFirebaseAuth {
  _RecordingFirebaseAuth(this.result);

  final UserCredential result;
  AuthProvider? provider;
  int popupCalls = 0;
  int nativeCalls = 0;
  int signOutCalls = 0;

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    this.provider = provider;
    popupCalls += 1;
    return result;
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    this.provider = provider;
    nativeCalls += 1;
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}

// Test double intentionally records destructive calls.
// ignore: must_be_immutable
class _RecordingMockUser extends MockUser {
  _RecordingMockUser({
    required super.uid,
    required super.email,
    required super.displayName,
  });

  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
  }
}

class _FailingFirestoreService extends FirestoreService {
  _FailingFirestoreService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<void> createUserProfile(AppUser user) async {
    throw StateError('simulated profile race');
  }
}

void main() {
  group('Apple provider configuration probe', () {
    test('accepts only an Apple authorization response', () {
      const response = '''
        {
          "authUri": "https://appleid.apple.com/auth/authorize?client_id=test",
          "providerId": "apple.com"
        }
      ''';

      expect(
        parseAppleProviderProbeResponse(200, response),
        AppleSignInAvailability.available,
      );
    });

    test('recognizes a Firebase provider that is not configured', () {
      const response = '''
        {
          "error": {
            "code": 400,
            "message": "OPERATION_NOT_ALLOWED : The identity provider configuration is not found."
          }
        }
      ''';

      expect(
        parseAppleProviderProbeResponse(400, response),
        AppleSignInAvailability.notConfigured,
      );
    });

    test('fails closed for malformed or non-Apple authorization URLs', () {
      expect(
        parseAppleProviderProbeResponse(
          200,
          '{"authUri":"https://example.com/phish","providerId":"apple.com"}',
        ),
        AppleSignInAvailability.temporarilyUnavailable,
      );
      expect(
        parseAppleProviderProbeResponse(200, 'not-json'),
        AppleSignInAvailability.temporarilyUnavailable,
      );
    });
  });

  group('AuthService Apple Sign-In', () {
    test(
      'build flag defaults to fail-closed and does not run the probe',
      () async {
        var probeCalls = 0;
        final service = AuthService(
          firebaseAuth: MockFirebaseAuth(),
          firestoreService: FirestoreService(
            firestore: FakeFirebaseFirestore(),
          ),
          appleSignInFeatureEnabled: false,
          appleProviderProbe: () async {
            probeCalls += 1;
            return AppleSignInAvailability.available;
          },
        );

        expect(
          await service.getAppleSignInAvailability(),
          AppleSignInAvailability.notConfigured,
        );
        expect(probeCalls, 0);
      },
    );

    test('caches a successful provider configuration probe', () async {
      var probeCalls = 0;
      final service = AuthService(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        appleSignInFeatureEnabled: true,
        appleProviderProbe: () async {
          probeCalls += 1;
          return AppleSignInAvailability.available;
        },
      );

      expect(
        await service.getAppleSignInAvailability(),
        AppleSignInAvailability.available,
      );
      expect(
        await service.getAppleSignInAvailability(),
        AppleSignInAvailability.available,
      );
      expect(probeCalls, 1);
    });

    test('uses the native provider flow with the required scopes', () async {
      final auth = _RecordingFirebaseAuth(
        _UserCredential(user: MockUser(uid: 'existing-user'), isNewUser: false),
      );
      final service = AuthService(
        firebaseAuth: auth,
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        appleSignInFeatureEnabled: true,
        appleUseWebPopup: false,
        appleProviderProbe: () async => AppleSignInAvailability.available,
      );

      await service.signInWithApple();

      expect(auth.nativeCalls, 1);
      expect(auth.popupCalls, 0);
      expect(auth.provider, isA<AppleAuthProvider>());
      expect(
        (auth.provider! as AppleAuthProvider).scopes,
        containsAll(<String>['email', 'name']),
      );
    });

    test('uses the popup provider flow on web', () async {
      final auth = _RecordingFirebaseAuth(
        _UserCredential(user: MockUser(uid: 'existing-user'), isNewUser: false),
      );
      final service = AuthService(
        firebaseAuth: auth,
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        appleSignInFeatureEnabled: true,
        appleUseWebPopup: true,
        appleProviderProbe: () async => AppleSignInAvailability.available,
      );

      await service.signInWithApple();

      expect(auth.popupCalls, 1);
      expect(auth.nativeCalls, 0);
      expect(auth.provider, isA<AppleAuthProvider>());
    });

    test('provisions the Firestore profile for a new Apple account', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _RecordingFirebaseAuth(
        _UserCredential(
          user: MockUser(
            uid: 'new-apple-user',
            email: '  apple.user@example.com  ',
            displayName: 'Apple User',
          ),
          isNewUser: true,
        ),
      );
      final service = AuthService(
        firebaseAuth: auth,
        firestoreService: FirestoreService(firestore: firestore),
        appleSignInFeatureEnabled: true,
        appleUseWebPopup: false,
        appleProviderProbe: () async => AppleSignInAvailability.available,
      );

      await service.signInWithApple();

      final profile = await firestore
          .collection('users')
          .doc('new-apple-user')
          .get();
      expect(profile.exists, isTrue);
      expect(profile.data()?['email'], 'apple.user@example.com');
      expect(profile.data()?['displayName'], 'Apple User');
      expect(profile.data()?['username'], 'Apple User');
    });

    test('does not start Firebase Auth while Apple is unavailable', () async {
      final auth = _RecordingFirebaseAuth(
        _UserCredential(user: MockUser(uid: 'unused'), isNewUser: false),
      );
      final service = AuthService(
        firebaseAuth: auth,
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        appleSignInFeatureEnabled: true,
        appleProviderProbe: () async => AppleSignInAvailability.notConfigured,
      );

      await expectLater(
        service.signInWithApple(),
        throwsA(
          isA<AuthServiceException>().having(
            (error) => error.message,
            'message',
            'Apple Sign-In is not available right now.',
          ),
        ),
      );
      expect(auth.nativeCalls, 0);
      expect(auth.popupCalls, 0);
    });

    test(
      'profile provisioning failure signs out but never deletes the social identity',
      () async {
        final user = _RecordingMockUser(
          uid: 'new-social-user',
          email: 'social@example.com',
          displayName: 'Social User',
        );
        final auth = _RecordingFirebaseAuth(
          _UserCredential(user: user, isNewUser: true),
        );
        final service = AuthService(
          firebaseAuth: auth,
          firestoreService: _FailingFirestoreService(),
          appleSignInFeatureEnabled: true,
          appleUseWebPopup: false,
          appleProviderProbe: () async => AppleSignInAvailability.available,
        );

        await expectLater(
          service.signInWithApple(),
          throwsA(isA<AuthServiceException>()),
        );
        expect(auth.signOutCalls, 1);
        expect(user.deleteCalls, 0);
      },
    );

    test('maps native Apple cancellation to neutral UX copy', () {
      final service = AuthService(
        firebaseAuth: MockFirebaseAuth(),
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
      );

      expect(
        service.getErrorMessage(FirebaseAuthException(code: 'canceled')),
        'Sign-in was cancelled.',
      );
    });
  });
}
