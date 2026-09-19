import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// The server rail inside a workspace hosted IN the Servers tab switches
/// servers in that slot. It must never replace the route that holds the app
/// shell (the tab has no nested Navigator, so a `pushReplacement` there
/// would dispose MainShell and strand the person on a bare workspace).
void main() {
  Server second() => Server(
    id: 't',
    name: 'Rodzina',
    description: '',
    ownerId: 'owner',
    type: ServerType.friends,
    privacy: ServerPrivacy.inviteOnly,
    memberCount: 4,
    defaultChannelId: qaFirstText(ServerType.friends),
    schemaVersion: 1,
    activationState: 'active',
    status: 'active',
  );

  TestServerRepository repository() => TestServerRepository()
    ..servers = [qaServer(ServerType.friends), second()]
    ..channels = qaChannels(ServerType.friends);

  Widget host(TestServerRepository repository) => ServersScreen(
    repository: repository,
    isRootTab: true,
    chatService: qaChat(),
    connector: FakeServerMediaConnector(),
  );

  void expectStillHosted(WidgetTester tester) {
    expect(
      find.byType(ServersScreen),
      findsOneWidget,
      reason: 'the tab host (and the shell around it) was replaced',
    );
    expect(
      find.byKey(const ValueKey('servers-create'), skipOffstage: false),
      findsOneWidget,
      reason: 'the directory must stay mounted under the hosted workspace',
    );
    expect(find.byKey(const ValueKey('servers-inline-t')), findsOneWidget);
    expect(find.byKey(const ValueKey('servers-inline-s')), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets('1440 px: a rail tap swaps the hosted server in place', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(tester, host(repository()), size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('server-directory-s')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('servers-inline-s')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('server-rail-t')));
    await tester.pumpAndSettle();
    expectStillHosted(tester);
  });

  testWidgets('390 px: the Kanały sheet rail swaps the hosted server in '
      'place', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServers(tester, host(repository()), size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('server-directory-s')));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('server-open-channels')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-rail-t')));
    await tester.pumpAndSettle();
    expectStillHosted(tester);
  });
}
