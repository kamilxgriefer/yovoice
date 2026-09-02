import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/firebase_auth_language_sync.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/services/firestore_service.dart';

void main() {
  test(
    'locale requests are serialized and readiness waits for the latest',
    () async {
      final started = <String>[];
      final completions = <String, Completer<void>>{};
      final sync = FirebaseAuthLanguageSync(
        setLanguageCode: (languageCode) {
          started.add(languageCode);
          final completion = Completer<void>();
          completions[languageCode] = completion;
          return completion.future;
        },
      );

      final english = sync.synchronize(const Locale('en'));
      final polish = sync.synchronize(const Locale('pl'));
      expect(started, ['en']);

      var ready = false;
      sync.ready.then((_) => ready = true);
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);

      completions['en']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, ['en', 'pl']);
      expect(ready, isFalse);

      completions['pl']!.complete();
      await Future.wait([english, polish, sync.ready]);
      expect(ready, isTrue);
    },
  );

  test(
    'AuthService waits for language readiness before starting sign-in',
    () async {
      final readiness = Completer<void>();
      final auth = _RecordingFirebaseAuth(
        mockUser: MockUser(email: 'person@example.com'),
      );
      final service = AuthService(
        firebaseAuth: auth,
        firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
        waitForAuthLanguage: () => readiness.future,
      );

      final signIn = service.signIn(
        email: 'person@example.com',
        password: 'Password123',
      );
      await Future<void>.delayed(Duration.zero);
      expect(auth.signInStarted, isFalse);

      readiness.complete();
      await signIn;
      expect(auth.signInStarted, isTrue);
    },
  );

  test(
    'a platform failure is best-effort and the locale can be retried',
    () async {
      var attempts = 0;
      final messages = <String>[];
      final sync = FirebaseAuthLanguageSync(
        setLanguageCode: (_) async {
          attempts += 1;
          if (attempts == 1) throw StateError('platform unavailable');
        },
        log: messages.add,
      );

      await sync.synchronize(const Locale('pl'));
      await sync.ready;
      expect(attempts, 1);
      expect(messages, hasLength(1));

      await sync.synchronize(const Locale('pl'));
      expect(attempts, 2);
    },
  );
}

class _RecordingFirebaseAuth extends MockFirebaseAuth {
  _RecordingFirebaseAuth({required super.mockUser});

  bool signInStarted = false;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    signInStarted = true;
    return super.signInWithEmailAndPassword(email: email, password: password);
  }
}
