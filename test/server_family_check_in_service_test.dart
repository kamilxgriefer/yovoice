import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/servers/data/services/server_family_check_in_service.dart';

void main() {
  test('family check-ins use only the callable V1 mutation contract', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerFamilyCheckInService(
      firestore: FakeFirebaseFirestore(),
      callOverride: (name, data) async {
        calls.add((name, data));
        return const {};
      },
    );

    await service.postCheckIn(
      serverId: 'family-owner',
      status: FamilyCheckInStatus.home,
    );
    await service.deleteCheckIn(
      serverId: 'family-owner',
      checkInId: 'check-in',
    );

    expect(calls[0].$1, 'createServerFamilyCheckInV1');
    expect(calls[0].$2['serverId'], 'family-owner');
    expect(calls[0].$2['status'], 'home');
    expect(calls[0].$2['requestId'], matches(RegExp(r'^[0-9a-f]{48}$')));
    expect(calls[0].$2.keys, {'serverId', 'requestId', 'status'});
    expect(calls[1].$1, 'deleteServerFamilyCheckInV1');
    expect(calls[1].$2['serverId'], 'family-owner');
    expect(calls[1].$2['checkInId'], 'check-in');
    expect(calls[1].$2.keys, {'serverId', 'checkInId', 'requestId'});
  });
}
