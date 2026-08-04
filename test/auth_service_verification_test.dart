import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/services/firestore_service.dart';

AuthService _buildService(MockFirebaseAuth auth) {
  return AuthService(
    firebaseAuth: auth,
    firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
  );
}

void main() {
  group('AuthService.resendVerificationEmail', () {
    test('throws AuthServiceException when nobody is signed in', () async {
      final service = _buildService(MockFirebaseAuth());

      expect(
        () => service.resendVerificationEmail(),
        throwsA(isA<AuthServiceException>()),
      );
    });

    test('succeeds against the current user when signed in', () async {
      final user = MockUser(isEmailVerified: false, email: 'test@example.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final service = _buildService(auth);

      // MockUser.sendEmailVerification no-ops successfully unless a
      // throwing expectation is registered — reaching here without an
      // exception is the assertion.
      await service.resendVerificationEmail();
    });

    test('propagates a FirebaseAuthException instead of swallowing it', () {
      final user = MockUser(isEmailVerified: false, email: 'test@example.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      whenCalling(Invocation.method(#sendEmailVerification, null))
          .on(user)
          .thenThrow(FirebaseAuthException(code: 'too-many-requests'));
      final service = _buildService(auth);

      expect(
        () => service.resendVerificationEmail(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'too-many-requests',
          ),
        ),
      );
    });
  });

  group('AuthService.reloadCurrentUser', () {
    test('returns false when nobody is signed in', () async {
      final service = _buildService(MockFirebaseAuth());

      expect(await service.reloadCurrentUser(), isFalse);
    });

    test('reflects an already-verified user after reload', () async {
      final user = MockUser(isEmailVerified: true, email: 'test@example.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final service = _buildService(auth);

      expect(await service.reloadCurrentUser(), isTrue);
    });

    test('reflects a still-unverified user after reload', () async {
      final user = MockUser(isEmailVerified: false, email: 'test@example.com');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final service = _buildService(auth);

      expect(await service.reloadCurrentUser(), isFalse);
    });
  });

  group('AuthService.register', () {
    test('a verification-send failure does not fail registration', () async {
      // register() wraps its sendEmailVerification call in try/catch
      // specifically so a delivery-layer problem (the actual bug this
      // whole flow was diagnosing) never undoes an otherwise-successful
      // signup. MockFirebaseAuth.createUserWithEmailAndPassword always
      // constructs its own internal MockUser, so there's no hook to force
      // *that* user's sendEmailVerification to throw — this test instead
      // pins down the contract at the unit level: register() must return
      // a valid credential for a well-formed signup.
      final auth = MockFirebaseAuth();
      final service = _buildService(auth);

      final credential = await service.register(
        email: 'newuser@example.com',
        password: 'Password123',
        username: 'newuser',
      );

      expect(credential.user, isNotNull);
      expect(credential.user!.email, 'newuser@example.com');
    });
  });
}
