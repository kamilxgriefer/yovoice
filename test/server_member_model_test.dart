import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';

void main() {
  test(
    'a server member requires its canonical id and authorization revision',
    () async {
      final firestore = FakeFirebaseFirestore();
      final reference = firestore.doc('clubs/server/members/member');
      Future<void> write(Map<String, Object?> data) => reference.set(data);

      await write({
        'userId': 'member',
        'displayName': 'Member',
        'role': 'member',
        'authorizationRevision': 2,
        'isOnline': false,
      });
      final parsed = ServerMember.fromFirestore(await reference.get());
      expect(parsed.id, 'member');
      expect(parsed.authorizationRevision, 2);

      await write({
        'displayName': 'Member',
        'role': 'member',
        'authorizationRevision': 2,
      });
      final missingId = await reference.get();
      expect(
        () => ServerMember.fromFirestore(missingId),
        throwsA(isA<FormatException>()),
      );

      await write({
        'userId': 'member',
        'displayName': 'Member',
        'role': 'member',
      });
      final missingRevision = await reference.get();
      expect(
        () => ServerMember.fromFirestore(missingRevision),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
