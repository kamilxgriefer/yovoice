import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

void main() {
  test(
    'creation calls only the exact V1 endpoint with immutable payload',
    () async {
      final calls = <Map<String, Object>>[];
      final service = ServerService(
        call: (name, data) async {
          expect(name, 'createServerV1');
          calls.add(data);
          return {
            'serverId': 's',
            'defaultChannelId': 'c',
            'channelIds': ['c', 'voice'],
            'alreadyExisted': calls.length > 1,
          };
        },
      );
      const request = ServerCreationRequest(
        requestId: 'stable',
        serverType: ServerType.podcast,
        name: 'Podcast',
        description: 'Our show',
        privacy: ServerPrivacy.inviteOnly,
        defaultLanguage: 'Polish',
      );
      expect((await service.createServer(request)).alreadyExisted, isFalse);
      expect((await service.createServer(request)).alreadyExisted, isTrue);
      expect(calls[0], {
        'requestId': 'stable',
        'serverType': 'podcast',
        'templateVersion': 1,
        'name': 'Podcast',
        'description': 'Our show',
        'privacy': 'inviteOnly',
        'defaultLanguage': 'Polish',
      });
      expect(calls[1], calls[0]);
    },
  );

  test('directory reads old ids without migrating roots', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u'));
    await firestore.doc('clubs/old').set({
      'name': 'Old',
      'type': 'family',
      'ownerId': 'u',
    });
    await firestore.doc('users/u/clubs/old').set({
      'clubId': 'old',
      'joinedAt': Timestamp.now(),
    });
    final service = ServerService(firestore: firestore, auth: auth);
    final before = firestore.dump();
    final result = await service.watchMyServers().first;
    expect(result.single.id, 'old');
    expect(result.single.type, ServerType.family);
    expect(firestore.dump(), before);
  });

  test(
    'V1 directory excludes restricted names without private pointers and archived rows',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u'),
      );
      await firestore.doc('clubs/s').set({
        'serverSchemaVersion': 1,
        'serverType': 'company',
        'name': 'Company',
        'ownerId': 'u',
        'privacy': 'inviteOnly',
        'serverActivationState': 'held',
      });
      Map<String, Object> channel(String name, String access, String status) =>
          {
            'serverSchemaVersion': 1,
            'serverId': 's',
            'name': name,
            'kind': 'text',
            'accessMode': access,
            'isPrivate': access == 'restricted',
            'status': status,
            'position': 0,
          };
      await firestore
          .doc('clubs/s/channels/general')
          .set(channel('general', 'members', 'active'));
      await firestore
          .doc('clubs/s/channels/hr')
          .set(channel('HR secret', 'restricted', 'active'));
      await firestore
          .doc('clubs/s/channels/archive')
          .set(channel('archived', 'members', 'archived'));
      final service = ServerService(firestore: firestore, auth: auth);
      expect((await service.watchChannels('s').first).map((c) => c.id), [
        'general',
      ]);
      await firestore.doc('users/u/serverChannelRefs/hr').set({
        'serverId': 's',
        'channelId': 'hr',
      });
      expect((await service.watchChannels('s').first).map((c) => c.id), [
        'general',
        'hr',
      ]);
    },
  );

  test('fresh request identities do not need Firebase and are unique', () {
    final service = ServerService();
    final ids = List.generate(50, (_) => service.newRequestId());
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{48}$').hasMatch(id)), isTrue);
  });
}
