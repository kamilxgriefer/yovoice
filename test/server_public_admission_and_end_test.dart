import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';

import 'server_test_support.dart';

Server _server(ServerType type, {ServerPrivacy? privacy}) => Server(
  id: 'server',
  name: type == ServerType.podcast ? 'Podcast publiczny' : 'Społeczność',
  description: 'Opis widoczny przed dołączeniem',
  ownerId: 'owner',
  type: type,
  privacy: privacy ?? ServerPrivacy.inviteOnly,
  defaultChannelId: 'general',
  schemaVersion: 1,
  templateVersion: 1,
  revision: 1,
  activationState: 'active',
  status: 'active',
);

const _textChannel = ServerChannel(
  id: 'general',
  serverId: 'server',
  name: 'ogólny',
  kind: ServerChannelKind.text,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

const _voiceChannel = ServerChannel(
  id: 'voice',
  serverId: 'server',
  name: 'Salon',
  kind: ServerChannelKind.voice,
  roomId: 'room',
  experience: RoomExperience.community,
  mediaMode: ServerMediaMode.audio,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

void main() {
  group('public server admission', () {
    for (final type in [ServerType.community, ServerType.podcast]) {
      testWidgets(
        '${type.name} defers channel reads and retries join with one request id',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repository = TestServerRepository()
            ..servers = [_server(type, privacy: ServerPrivacy.public)]
            ..channels = const [_textChannel]
            ..myRole = null
            ..failNextCall['joinServerV1'] = FirebaseFunctionsException(
              code: 'unavailable',
              message: 'offline after commit is possible',
            );

          await pumpServers(
            tester,
            ServerWorkspaceScreen(
              serverId: 'server',
              repository: repository,
              isRootTab: true,
              channelBuilder: (_, _, channel) => Text('opened-${channel.id}'),
            ),
          );

          expect(
            find.byKey(const ValueKey('server-public-admission')),
            findsOneWidget,
          );
          expect(repository.watchChannelsCalls, 0);
          expect(find.text('ogólny'), findsNothing);

          await tester.tap(find.byKey(const ValueKey('server-public-join')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('server-public-join-error')),
            findsOneWidget,
          );
          expect(repository.watchChannelsCalls, 0);
          expect(repository.calls.single.$1, 'joinServerV1');
          final requestId = repository.calls.single.$2['requestId'];

          await tester.tap(find.byKey(const ValueKey('server-public-join')));
          await tester.pumpAndSettle();

          final joins = repository.calls
              .where((call) => call.$1 == 'joinServerV1')
              .toList();
          expect(joins, hasLength(2));
          expect(joins[0].$2, {'serverId': 'server', 'requestId': requestId});
          expect(joins[1].$2, joins[0].$2);
          expect(repository.watchChannelsCalls, 1);
          expect(
            find.byKey(const ValueKey('server-public-admission')),
            findsNothing,
          );
          expect(find.text('opened-general'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('non-public non-member never receives a join or channel path', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [_server(ServerType.friends)]
        ..channels = const [_textChannel]
        ..myRole = null;

      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 'server',
          repository: repository,
          isRootTab: true,
        ),
      );

      expect(find.byKey(const ValueKey('server-public-join')), findsNothing);
      expect(find.text('Nie należysz do tego serwera.'), findsOneWidget);
      expect(repository.watchChannelsCalls, 0);
      expect(repository.calls, isEmpty);
    });
  });

  testWidgets(
    'host ends the durable generation and an ambiguous retry keeps its id',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [_server(ServerType.friends)]
        ..channels = const [_voiceChannel]
        ..failNextCall['endServerChannelSessionV1'] =
            FirebaseFunctionsException(
              code: 'unavailable',
              message: 'response lost',
            );
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 'server',
          repository: repository,
          isRootTab: true,
          initialChannelId: 'voice',
          connector: connector,
          anotherVoiceSessionActive: () => false,
        ),
        size: const Size(1100, 800),
      );

      await tester.tap(find.byKey(const ValueKey('server-join')));
      await tester.pumpAndSettle();
      final link = connector.links.single;
      link.report(ServerMediaLinkState.connected);
      await tester.pumpAndSettle();

      Future<void> confirmEnd() async {
        await tester.tap(find.byKey(const ValueKey('server-dock-end-session')));
        await tester.pumpAndSettle();
        expect(
          find.text('Zakończyć tę rozmowę dla wszystkich?'),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('server-end-session-confirm')),
        );
        await tester.pumpAndSettle();
      }

      await confirmEnd();
      expect(link.disconnects, 0, reason: 'failed end keeps the live link');
      expect(
        find.text('To trwa dłużej, niż oczekiwano. Spróbuj ponownie.'),
        findsOneWidget,
      );

      final firstEnd = repository.calls.last;
      expect(firstEnd.$1, 'endServerChannelSessionV1');
      expect(firstEnd.$2, {
        'serverId': 'server',
        'channelId': 'voice',
        'sessionId': 'session-1',
        'requestId': 'request-3',
      });

      await confirmEnd();
      final ends = repository.calls
          .where((call) => call.$1 == 'endServerChannelSessionV1')
          .toList();
      expect(ends, hasLength(2));
      expect(ends[1].$2, ends[0].$2);
      expect(link.disconnects, 1);
      expect(
        find.byKey(const ValueKey('server-conversation-dock')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
