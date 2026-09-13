import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/servers/data/models/server_list_item.dart';
import 'package:yovoice/features/servers/data/services/server_shared_list_service.dart';

void main() {
  test(
    'shared-list mutations preserve the injectable V1 callable seam',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerSharedListService(
        firestore: FakeFirebaseFirestore(),
        currentUserIdOverride: 'member',
        callOverride: (name, data) async {
          calls.add((name, data));
          return const {};
        },
      );
      final item = ServerListItem(
        id: 'milk',
        serverId: 'family',
        channelId: 'shopping',
        text: 'Mleko',
        checked: false,
        createdById: 'member',
        revision: 3,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      await service.createItem(
        serverId: 'family',
        channelId: 'shopping',
        text: '  Mleko  ',
        requestId: 'create-request',
      );
      await service.updateItem(
        item: item,
        patch: const {'checked': true},
        requestId: 'update-request',
      );
      await service.deleteItem(item: item, requestId: 'delete-request');

      expect(service.currentUserId, 'member');
      expect(calls.map((call) => call.$1), [
        'createServerListItemV1',
        'updateServerListItemV1',
        'deleteServerListItemV1',
      ]);
      expect(calls[0].$2, {
        'serverId': 'family',
        'channelId': 'shopping',
        'requestId': 'create-request',
        'text': 'Mleko',
      });
      expect(calls[1].$2, {
        'serverId': 'family',
        'channelId': 'shopping',
        'itemId': 'milk',
        'requestId': 'update-request',
        'expectedRevision': 3,
        'patch': <String, Object?>{'checked': true},
      });
      expect(calls[2].$2, {
        'serverId': 'family',
        'channelId': 'shopping',
        'itemId': 'milk',
        'requestId': 'delete-request',
        'expectedRevision': 3,
      });
    },
  );
}
