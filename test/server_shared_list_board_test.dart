import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_list_item.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_shared_list_service.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_shared_list_board.dart';

import 'server_test_support.dart';

const _channel = ServerChannel(
  id: 'shopping',
  serverId: 'family',
  name: 'Lista zakupów',
  kind: ServerChannelKind.list,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

class _FakeListRepository implements ServerSharedListRepository {
  List<ServerListItem> items = const [];
  final calls = <(String, Map<String, Object?>)>[];
  var request = 0;

  @override
  String get currentUserId => 'owner';

  @override
  String newRequestId() => 'request-${++request}';

  @override
  Stream<List<ServerListItem>> watchItems(String serverId, String channelId) =>
      Stream.value(items);

  @override
  Future<void> createItem({
    required String serverId,
    required String channelId,
    required String text,
    required String requestId,
  }) async {
    calls.add((
      'createServerListItemV1',
      {
        'serverId': serverId,
        'channelId': channelId,
        'text': text,
        'requestId': requestId,
      },
    ));
  }

  @override
  Future<void> updateItem({
    required ServerListItem item,
    required Map<String, Object?> patch,
    required String requestId,
  }) async {
    calls.add((
      'updateServerListItemV1',
      {
        'serverId': item.serverId,
        'channelId': item.channelId,
        'itemId': item.id,
        'expectedRevision': item.revision,
        'patch': patch,
        'requestId': requestId,
      },
    ));
  }

  @override
  Future<void> deleteItem({
    required ServerListItem item,
    required String requestId,
  }) async {
    calls.add(('deleteServerListItemV1', {'itemId': item.id}));
  }
}

void main() {
  testWidgets('a family member adds an item through the exact V1 action', (
    tester,
  ) async {
    final repository = _FakeListRepository();
    await pumpServers(
      tester,
      Builder(
        builder: (context) => ServerSharedListBoard(
          serverId: 'family',
          channel: _channel,
          repository: repository,
          colors: ServerIdentity.of(
            ServerType.family,
          ).resolve(Theme.of(context).brightness),
          role: ServerMemberRole.member,
          compact: true,
        ),
      ),
      size: const Size(390, 844),
    );

    await tester.enterText(
      find.byKey(const ValueKey('server-list-composer')),
      'Chleb',
    );
    await tester.tap(find.byKey(const ValueKey('server-list-add')));
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'createServerListItemV1');
    expect(repository.calls.single.$2, <String, Object?>{
      'serverId': 'family',
      'channelId': 'shopping',
      'text': 'Chleb',
      'requestId': 'request-1',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('checking an item sends its current revision', (tester) async {
    final repository = _FakeListRepository()
      ..items = [
        ServerListItem(
          id: 'bread',
          serverId: 'family',
          channelId: 'shopping',
          text: 'Chleb',
          checked: false,
          createdById: 'owner',
          revision: 3,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ];
    await pumpServers(
      tester,
      Builder(
        builder: (context) => ServerSharedListBoard(
          serverId: 'family',
          channel: _channel,
          repository: repository,
          colors: ServerIdentity.of(
            ServerType.family,
          ).resolve(Theme.of(context).brightness),
          role: ServerMemberRole.member,
          compact: true,
        ),
      ),
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const ValueKey('server-list-toggle-bread')));
    await tester.pumpAndSettle();

    expect(repository.calls.single.$1, 'updateServerListItemV1');
    expect(repository.calls.single.$2, <String, Object?>{
      'serverId': 'family',
      'channelId': 'shopping',
      'itemId': 'bread',
      'expectedRevision': 3,
      'patch': {'checked': true},
      'requestId': 'request-1',
    });
  });

  testWidgets('a guest sees the synchronized list without write controls', (
    tester,
  ) async {
    final repository = _FakeListRepository();
    await pumpServers(
      tester,
      Builder(
        builder: (context) => ServerSharedListBoard(
          serverId: 'family',
          channel: _channel,
          repository: repository,
          colors: ServerIdentity.of(
            ServerType.family,
          ).resolve(Theme.of(context).brightness),
          role: ServerMemberRole.guest,
          compact: true,
        ),
      ),
      size: const Size(390, 844),
    );

    expect(find.byKey(const ValueKey('server-shared-list-board')), findsOne);
    expect(find.byKey(const ValueKey('server-list-composer')), findsNothing);
    expect(find.byKey(const ValueKey('server-list-add')), findsNothing);
  });
}
