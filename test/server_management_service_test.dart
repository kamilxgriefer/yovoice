import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

void main() {
  test('management calls exact versioned endpoints and payloads', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerService(
      call: (name, data) async {
        calls.add((name, data));
        return const {};
      },
    );

    await service.updateChannel(
      serverId: 'server',
      channelId: 'channel',
      expectedRevision: 4,
      patch: const {'name': 'Nowa nazwa'},
      requestId: 'rename-request',
    );
    await service.setChannelAccess(
      serverId: 'server',
      channelId: 'channel',
      expectedAclRevision: 8,
      access: ServerChannelAccess.restricted,
      roleIds: const ['owner', 'admin'],
      userIds: const ['person'],
      requestId: 'access-request',
    );
    await service.setMemberRole(
      serverId: 'server',
      memberId: 'person',
      role: ServerMemberRole.moderator,
      requestId: 'role-request',
    );

    expect(calls.map((call) => call.$1), [
      'updateServerChannelV1',
      'setServerChannelAccessV1',
      'setServerMemberRoleV1',
    ]);
    expect(calls[0].$2, {
      'serverId': 'server',
      'channelId': 'channel',
      'requestId': 'rename-request',
      'expectedRevision': 4,
      'patch': {'name': 'Nowa nazwa'},
    });
    expect(calls[1].$2, {
      'serverId': 'server',
      'channelId': 'channel',
      'requestId': 'access-request',
      'expectedAclRevision': 8,
      'policy': {
        'accessMode': 'restricted',
        'roleIds': ['owner', 'admin'],
        'userIds': ['person'],
      },
    });
    expect(calls[2].$2, {
      'serverId': 'server',
      'memberId': 'person',
      'requestId': 'role-request',
      'role': 'moderator',
    });
  });
}
