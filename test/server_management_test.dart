import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_test_support.dart';

void main() {
  testWidgets('owner can open real server settings and save server metadata', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = const [
        Server(
          id: 'server',
          name: 'Ekipa',
          description: 'Po godzinach',
          ownerId: 'owner',
          type: ServerType.friends,
          privacy: ServerPrivacy.private,
          schemaVersion: 1,
          activationState: 'active',
          revision: 7,
        ),
      ]
      ..channels = const [
        ServerChannel(
          id: 'general',
          serverId: 'server',
          name: 'ogólny',
          kind: ServerChannelKind.text,
          schemaVersion: 1,
          revision: 3,
          aclRevision: 2,
        ),
      ]
      ..members = const [
        ServerMember(
          id: 'owner',
          displayName: 'Kamil',
          role: ServerMemberRole.owner,
          authorizationRevision: 1,
        ),
      ];

    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 'server',
        repository: repository,
        channelBuilder: (_, _, _) => const SizedBox(),
      ),
      size: const Size(1200, 900),
    );

    await tester.tap(find.byKey(const ValueKey('server-manage-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('server-management-overview')), findsOne);
    expect(find.text('Ustawienia serwera'), findsOne);

    await tester.enterText(
      find.byKey(const ValueKey('server-management-name')),
      'Ekipa 2.0',
    );
    await tester.tap(find.byKey(const ValueKey('server-management-save')));
    await tester.pumpAndSettle();

    final call = repository.calls.last;
    expect(call.$1, 'updateServerV1');
    expect(call.$2, {
      'serverId': 'server',
      'requestId': 'request-1',
      'expectedRevision': 7,
      'patch': {
        'name': 'Ekipa 2.0',
        'description': 'Po godzinach',
        'privacy': 'private',
        'defaultLanguage': 'English',
      },
    });
    expect(find.text('Zmiany zostały zapisane.'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary member has no server management entry', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..myRole = ServerMemberRole.member
      ..servers = const [
        Server(
          id: 'server',
          name: 'Społeczność',
          description: '',
          ownerId: 'another-owner',
          type: ServerType.community,
          privacy: ServerPrivacy.public,
          schemaVersion: 1,
          activationState: 'active',
          revision: 2,
        ),
      ];

    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 'server',
        repository: repository,
        channelBuilder: (_, _, _) => const SizedBox(),
      ),
      size: const Size(1200, 900),
    );
    expect(find.byKey(const ValueKey('server-manage-action')), findsNothing);
    expect(find.byKey(const ValueKey('server-delete-action')), findsNothing);
    expect(find.byKey(const ValueKey('server-management-save')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'moderator can inspect settings without channel management actions',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..myRole = ServerMemberRole.moderator
        ..servers = const [
          Server(
            id: 'server',
            name: 'Społeczność',
            description: '',
            ownerId: 'another-owner',
            type: ServerType.community,
            privacy: ServerPrivacy.public,
            schemaVersion: 1,
            activationState: 'active',
            revision: 2,
          ),
        ]
        ..channels = const [
          ServerChannel(
            id: 'general',
            serverId: 'server',
            name: 'ogólny',
            kind: ServerChannelKind.text,
            schemaVersion: 1,
            revision: 1,
            aclRevision: 1,
          ),
        ];

      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 'server',
          repository: repository,
          channelBuilder: (_, _, _) => const SizedBox(),
        ),
        size: const Size(1200, 900),
      );
      await tester.tap(find.byKey(const ValueKey('server-manage-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanały'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('server-management-channels')),
        findsOne,
      );
      expect(find.byTooltip('Działania kanału'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('metadata save keeps the revision that populated the form', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final serverUpdates = StreamController<Server?>.broadcast();
    addTearDown(serverUpdates.close);
    const initial = Server(
      id: 'server',
      name: 'Ekipa',
      description: 'Pierwszy opis',
      ownerId: 'owner',
      type: ServerType.friends,
      privacy: ServerPrivacy.private,
      schemaVersion: 1,
      activationState: 'active',
      revision: 7,
    );
    const remote = Server(
      id: 'server',
      name: 'Zdalna nazwa',
      description: 'Zdalny opis',
      ownerId: 'owner',
      type: ServerType.friends,
      privacy: ServerPrivacy.private,
      schemaVersion: 1,
      activationState: 'active',
      revision: 8,
    );
    final serverStream = Stream<Server?>.multi((listener) {
      listener.add(initial);
      final subscription = serverUpdates.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    });
    final repository = TestServerRepository()..serverStream = serverStream;

    await pumpServers(
      tester,
      ServerWorkspaceScreen(serverId: 'server', repository: repository),
      size: const Size(1200, 900),
    );
    await tester.tap(find.byKey(const ValueKey('server-manage-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-management-name')),
      'Moja nazwa',
    );

    serverUpdates.add(remote);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('server-management-save')));
    await tester.pumpAndSettle();

    expect(repository.calls.last.$1, 'updateServerV1');
    expect(repository.calls.last.$2['expectedRevision'], 7);
    expect(
      repository.calls.last.$2['patch'],
      containsPair('name', 'Moja nazwa'),
    );
    expect(tester.takeException(), isNull);
  });
}
