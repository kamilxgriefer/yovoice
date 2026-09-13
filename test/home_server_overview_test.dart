import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_server_overview.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';

const server = Server(
  id: 'community',
  name: 'Głos miasta',
  description: 'Rozmowy społeczności',
  ownerId: 'owner',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  schemaVersion: 1,
  activationState: 'active',
);

AsyncSnapshot<List<Server>> get snapshot =>
    const AsyncSnapshot<List<Server>>.withData(ConnectionState.active, <Server>[
      server,
    ]);

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets(
    'the continue card opens its concrete server workspace callback',
    (tester) async {
      Server? opened;
      var directoryOpens = 0;
      await pump(
        tester,
        HomeServerConversationCard(
          snapshot: snapshot,
          onOpenServers: () => directoryOpens += 1,
          onOpenServer: (value) => opened = value,
          onRetry: () {},
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('home-server-continue-community')),
      );

      expect(opened, same(server));
      expect(directoryOpens, 0);
    },
  );

  testWidgets('a server row keeps the directory callback as its fallback', (
    tester,
  ) async {
    var directoryOpens = 0;
    await pump(
      tester,
      HomeServersOverview(
        snapshot: snapshot,
        onOpenServers: () => directoryOpens += 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-server-row-community')));

    expect(directoryOpens, 1);
  });
}
