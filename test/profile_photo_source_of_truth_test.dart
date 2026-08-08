import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

const String _uid = 'user-1';
const String _avatarUrl =
    'https://firebasestorage.googleapis.com/v0/b/yovoice.appspot.com/o/'
    'users%2Fuser-1%2Fprofile%2Favatar_1754640000000.jpg?alt=media&token=abc';

/// An email/password account: FirebaseAuth's own photoURL is null, which is
/// the case that made the clobber destructive.
MockFirebaseAuth _auth({String? photoURL}) {
  return MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: _uid,
      email: 'user@yovoice.app',
      displayName: 'Ada Lovelace',
      photoURL: photoURL,
    ),
  );
}

Future<Map<String, dynamic>> _readUser(FakeFirebaseFirestore db) async {
  final snapshot = await db.collection('users').doc(_uid).get();
  return snapshot.data() ?? <String, dynamic>{};
}

void main() {
  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  group('profile photo source of truth', () {
    test(
      'ensureUserDocument does not overwrite the saved avatar '
      '(regression: it used to write FirebaseAuth photoURL over it)',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth(); // photoURL == null, like a password account

        // The state right after Edit profile saves an avatar: the profile
        // doc owns a real Storage URL.
        await db.collection('users').doc(_uid).set({
          'uid': _uid,
          'displayName': 'Ada Lovelace',
          'photoUrl': _avatarUrl,
        });

        // Home's friends row starting up (and every page refresh) runs
        // this. Before the fix it merged `photoUrl: user.photoURL` — null —
        // straight over the avatar, and the header fell back to the purple
        // placeholder.
        await FriendService(firestore: db, auth: auth).ensureUserDocument();

        final data = await _readUser(db);
        expect(
          data['photoUrl'],
          _avatarUrl,
          reason: 'the saved avatar must survive a friends-stream start',
        );
        expect(data['isOnline'], isTrue);
      },
    );

    test(
      'ensureUserDocument still creates the doc a friend edge needs',
      () async {
        final db = FakeFirebaseFirestore();
        await FriendService(firestore: db, auth: _auth()).ensureUserDocument();

        final data = await _readUser(db);
        expect(data['uid'], _uid);
        expect(data['isOnline'], isTrue);
        // It must NOT invent profile identity fields — those belong to
        // ProfileService.ensureProfile().
        expect(data.containsKey('photoUrl'), isFalse);
        expect(data.containsKey('displayName'), isFalse);
      },
    );

    test(
      'ensureProfile still seeds a doc that friend_service created first',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth();

        // Ordering hazard: the friends stream can create users/{uid}
        // before AuthGate gets to ensureProfile(). An `exists` check left
        // the account permanently without a displayName.
        await FriendService(firestore: db, auth: auth).ensureUserDocument();
        await ProfileService(firestore: db, auth: auth).ensureProfile();

        final data = await _readUser(db);
        expect(data['displayName'], 'Ada Lovelace');
        expect(data['username'], 'Ada Lovelace');
      },
    );

    test(
      'ensureProfile never overwrites an avatar the profile already owns',
      () async {
        final db = FakeFirebaseFirestore();
        // A Google account whose Auth photoURL differs from the avatar the
        // user later uploaded.
        final auth = _auth(photoURL: 'https://lh3.googleusercontent.com/old');

        await db.collection('users').doc(_uid).set({'photoUrl': _avatarUrl});
        await ProfileService(firestore: db, auth: auth).ensureProfile();

        final data = await _readUser(db);
        expect(data['photoUrl'], _avatarUrl);
      },
    );

    test(
      'ensureProfile seeds the Google avatar only when there is none',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth(photoURL: 'https://lh3.googleusercontent.com/new');

        await ProfileService(firestore: db, auth: auth).ensureProfile();

        final data = await _readUser(db);
        expect(data['photoUrl'], 'https://lh3.googleusercontent.com/new');
        expect(data['followerCount'], 0);
      },
    );

    test(
      'ensureProfile does not reset counters on an existing profile',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth();

        await db.collection('users').doc(_uid).set({
          'uid': _uid,
          'friendCount': 7,
          'followerCount': 12,
        });
        await ProfileService(firestore: db, auth: auth).ensureProfile();

        final data = await _readUser(db);
        expect(data['friendCount'], 7);
        expect(data['followerCount'], 12);
        expect(data['displayName'], 'Ada Lovelace');
      },
    );

    test(
      'watchCurrentProfile emits the avatar and reacts to changes',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth();
        final service = ProfileService(firestore: db, auth: auth);

        await db.collection('users').doc(_uid).set({
          'uid': _uid,
          'displayName': 'Ada Lovelace',
          'photoUrl': _avatarUrl,
        });

        final first = await service.watchCurrentProfile().first;
        expect(first.photoUrl, _avatarUrl);

        const nextUrl = '$_avatarUrl-v2';
        await db.collection('users').doc(_uid).set({
          'photoUrl': nextUrl,
        }, SetOptions(merge: true));

        final updated = await service
            .watchCurrentProfile()
            .firstWhere((profile) => profile.photoUrl == nextUrl)
            .timeout(const Duration(seconds: 5));
        expect(updated.photoUrl, nextUrl);
      },
    );

    test(
      'two ProfileService instances share one reactive profile stream',
      () async {
        final db = FakeFirebaseFirestore();
        final auth = _auth();

        await db.collection('users').doc(_uid).set({
          'uid': _uid,
          'displayName': 'Ada Lovelace',
          'photoUrl': _avatarUrl,
        });

        // Home and Profile each construct their own ProfileService.
        final home = ProfileService(firestore: db, auth: auth);
        final profile = ProfileService(firestore: db, auth: auth);

        expect(
          identical(home.watchCurrentProfile(), profile.watchCurrentProfile()),
          isTrue,
          reason: 'screens must not each get a divergent profile stream',
        );

        // And a late subscriber gets the current value replayed rather
        // than waiting for the next Firestore change.
        expect((await home.watchCurrentProfile().first).photoUrl, _avatarUrl);
        expect(
          (await profile.watchCurrentProfile().first).photoUrl,
          _avatarUrl,
        );
      },
    );
  });
}
