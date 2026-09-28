import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);
  bool canonical(Object? grant) =>
      LikersAccessService.canonicalLikersVipGrant(grant, now);

  group(
    'canonicalLikersVipGrant (Dart port of the fail-closed server rule)',
    () {
      test('accepts the production tester and legacy-migration shapes', () {
        expect(
          canonical(<String, Object?>{
            'source': 'testerProgram',
            'expiresAt': null,
            'revoked': false,
            'grantedBy': 'kamil',
          }),
          isTrue,
        );
        expect(
          canonical(<String, Object?>{
            'source': 'legacyRoleMigration',
            'grantedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
            'expiresAt': null,
            'revoked': false,
          }),
          isTrue,
        );
        expect(
          canonical(<String, Object?>{
            'source': 'admin',
            'expiresAt': Timestamp.fromDate(DateTime.utc(2027, 1, 1)),
            'revoked': false,
            'active': true,
          }),
          isTrue,
        );
      });

      test('refuses every malformed, revoked or expired grant', () {
        final base = <String, Object?>{
          'source': 'testerProgram',
          'expiresAt': null,
          'revoked': false,
        };
        final refused = <Object?>[
          null,
          'vip',
          <String, Object?>{},
          {...base, 'revoked': 'true'},
          {...base, 'revoked': true},
          {...base, 'revokedAt': Timestamp.fromDate(now)},
          {...base}..remove('revoked'),
          {...base}..remove('source'),
          {...base}..remove('expiresAt'),
          {...base, 'active': false},
          {...base, 'source': 'purchase'},
          {...base, 'expiresAt': '2099-01-01'},
          {...base, 'expiresAt': 4102444800000},
          {...base, 'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1))},
          {...base, 'grantedBy': ''},
          {...base, 'grantedBy': 'x' * 201},
          {...base, 'grantedAt': '2026-01-01'},
        ];
        for (final grant in refused) {
          expect(canonical(grant), isFalse, reason: '$grant must be refused');
        }
      });
    },
  );

  group('LikersAccessService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    });

    tearDown(EntitlementService.resetCache);

    LikersAccessService service({MockFirebaseAuth? withAuth}) =>
        LikersAccessService(
          firestore: firestore,
          auth: withAuth ?? auth,
          clock: () => now,
        );

    test('a free account without a grant cannot see likers', () async {
      expect(await service().canSeeLikers(), isFalse);
      expect(await service().watchCanSeeLikers().first, isFalse);
    });

    test('a canonical VIP grant unlocks it', () async {
      await firestore.doc('vipGrants/me').set(<String, Object?>{
        'source': 'testerProgram',
        'expiresAt': null,
        'revoked': false,
        'grantedBy': 'kamil',
      });
      expect(await service().canSeeLikers(), isTrue);
      expect(await service().watchCanSeeLikers().first, isTrue);
    });

    test('the real tester grant shape with a note unlocks it', () async {
      await firestore.doc('vipGrants/me').set(<String, Object?>{
        'source': 'testerProgram',
        'expiresAt': null,
        'revoked': false,
        'grantedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 19)),
        'grantedBy': 'owner-decision-2026-09-19',
        'note': 'Tester VIP',
      });
      expect(await service().canSeeLikers(), isTrue);
    });

    test('a note that is not a non-empty string is refused', () async {
      for (final note in <Object?>['', 7, 'x' * 501]) {
        expect(
          LikersAccessService.canonicalLikersVipGrant(<String, Object?>{
            'source': 'testerProgram',
            'expiresAt': null,
            'revoked': false,
            'note': note,
          }, DateTime.utc(2026, 9, 28)),
          isFalse,
          reason: 'note: $note',
        );
      }
    });

    test('a non-canonical grant does not', () async {
      await firestore.doc('vipGrants/me').set(<String, Object?>{
        'source': 'testerProgram',
        'expiresAt': null,
        'revoked': 'false',
      });
      expect(await service().canSeeLikers(), isFalse);
      expect(await service().watchCanSeeLikers().first, isFalse);
    });

    test('paid Premium identity unlocks it', () async {
      await firestore.doc('entitlements/me').set(<String, Object?>{
        'isPremium': true,
        'status': 'active',
        'currentPeriodEnd': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 20)),
        ),
        'premiumIdentityEnabled': true,
      });
      expect(await service().canSeeLikers(), isTrue);
      expect(await service().watchCanSeeLikers().first, isTrue);
    });

    test('the moderator preview unlocks it', () async {
      await firestore.doc('users/me').set(<String, Object?>{
        'role': 'moderator',
      });
      expect(await service().canSeeLikers(), isTrue);
      expect(await service().watchCanSeeLikers().first, isTrue);
    });

    test('the live answer follows a grant being revoked', () async {
      await firestore.doc('vipGrants/me').set(<String, Object?>{
        'source': 'testerProgram',
        'expiresAt': null,
        'revoked': false,
      });
      final values = <bool>[];
      final subscription = service().watchCanSeeLikers().listen(values.add);
      await pumpEventQueue();
      await firestore.doc('vipGrants/me').update(<String, Object?>{
        'revoked': true,
      });
      await pumpEventQueue();
      await subscription.cancel();
      expect(values, [true, false]);
    });

    test('signed out is always false', () async {
      final signedOut = MockFirebaseAuth();
      expect(await service(withAuth: signedOut).canSeeLikers(), isFalse);
      expect(
        await service(withAuth: signedOut).watchCanSeeLikers().first,
        isFalse,
      );
    });
  });
}
