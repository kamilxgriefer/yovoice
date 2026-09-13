import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/services/server_follow_service.dart';

void main() {
  test('watch reads only the signed-in member private projection', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ServerFollowService(
      firestore: firestore,
      currentUserIdOverride: 'member',
      callOverride: (_, _) async => {},
    );
    final states = <bool>[];
    final subscription = service
        .watchCommunityFollow('community')
        .listen(states.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    await firestore.doc('clubs/community/followers/member').set({
      'schemaVersion': 1,
      'serverId': 'community',
      'userId': 'member',
      'following': true,
    });
    await pumpEventQueue();
    expect(states, [false, true]);
  });

  test('set sends the exact callable payload and returns its state', () async {
    String? name;
    Map<String, Object?>? payload;
    final service = ServerFollowService(
      firestore: FakeFirebaseFirestore(),
      currentUserIdOverride: 'member',
      callOverride: (nextName, nextPayload) async {
        name = nextName;
        payload = nextPayload;
        return {'serverId': 'community', 'following': true};
      },
    );
    expect(
      await service.setCommunityFollow(serverId: 'community', following: true),
      isTrue,
    );
    expect(name, 'setCommunityServerFollowV1');
    expect(payload?['serverId'], 'community');
    expect(payload?['following'], true);
    expect(
      payload?['requestId'],
      isA<String>().having((id) => id.length, 'length', 48),
    );
    expect(
      payload?.keys,
      unorderedEquals(['serverId', 'requestId', 'following']),
    );
  });

  test('anonymous use is refused before a callable', () async {
    var called = false;
    final service = ServerFollowService(
      firestore: FakeFirebaseFirestore(),
      currentUserIdOverride: '',
      callOverride: (_, _) async {
        called = true;
        return {};
      },
    );
    await expectLater(
      service.setCommunityFollow(serverId: 'community', following: true),
      throwsStateError,
    );
    expect(called, isFalse);
  });
}
