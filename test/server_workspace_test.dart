import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_test_support.dart';

Server fixtureServer(ServerType type, {bool held = true}) => Server(
  id: 's',
  name: 'Długa nazwa naszego wspólnego serwera',
  description: 'Opis',
  ownerId: 'owner',
  type: type,
  privacy: ServerPrivacy.inviteOnly,
  memberCount: 1,
  defaultChannelId: 'voice',
  schemaVersion: 1,
  activationState: held ? 'held' : 'active',
);

List<ServerChannel> fixtureChannels(ServerType type) => [
  ServerChannel(
    id: 'voice',
    serverId: 's',
    name: 'Salon naszej społeczności',
    kind: type == ServerType.podcast || type == ServerType.community
        ? ServerChannelKind.stage
        : type == ServerType.company
        ? ServerChannelKind.meeting
        : ServerChannelKind.voice,
    roomId: 'room',
    experience: type == ServerType.podcast || type == ServerType.community
        ? RoomExperience.broadcast
        : RoomExperience.community,
    mediaMode: type == ServerType.community
        ? ServerMediaMode.video
        : ServerMediaMode.audio,
  ),
  const ServerChannel(
    id: 'chat',
    serverId: 's',
    name: 'ogólny',
    kind: ServerChannelKind.text,
  ),
];

ClubChatService fakeChatService() => ClubChatService(
  firestore: FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'owner')),
  messageSendInvoker: (_) async => <Object?, Object?>{},
);

void main() {
  testWidgets('large directory names have full card width on a narrow screen', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      final server = fixtureServer(ServerType.friends);
      final repository = TestServerRepository()..servers = [server];
      Server? opened;
      await pumpServers(
        tester,
        ServersScreen(
          key: UniqueKey(),
          repository: repository,
          onOpenServer: (value) => opened = value,
          isRootTab: true,
        ),
        size: const Size(320, 844),
        textScale: 2,
        light: light,
      );
      final card = find.byKey(const ValueKey('server-directory-s'));
      final title = find.text(server.name);
      final avatar = find.descendant(
        of: card,
        matching: find.text(server.initial),
      );
      final cardRect = tester.getRect(card);
      final titleRect = tester.getRect(title);
      expect(titleRect.width, greaterThanOrEqualTo(cardRect.width - 32));
      expect(titleRect.top, greaterThan(tester.getRect(avatar).bottom));
      await tester.ensureVisible(title);
      await tester.tap(title);
      expect(opened, same(server));
      expect(repository.requests, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'selected channel text contrasts with its actual composite wash',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final light in [false, true]) {
        for (final type in ServerType.values) {
          final repository = TestServerRepository()
            ..servers = [fixtureServer(type)]
            ..channels = fixtureChannels(type);
          await pumpServers(
            tester,
            ServerWorkspaceScreen(
              key: UniqueKey(),
              serverId: 's',
              repository: repository,
            ),
            size: const Size(1440, 900),
            light: light,
          );
          final selected = find.byKey(const ValueKey('server-channel-voice'));
          final tile = tester.widget<ListTile>(selected);
          final material = tester.widget<Material>(
            find.ancestor(of: selected, matching: find.byType(Material)).first,
          );
          expect(tile.selected, isTrue);
          expect(
            material.color,
            light
                ? AppPalette.light.surfaceMuted
                : AppPalette.dark.surfaceMuted,
          );
          final surface = Color.alphaBlend(
            tile.selectedTileColor!,
            material.color!,
          );
          final textLuminance = tile.selectedColor!.computeLuminance();
          final surfaceLuminance = surface.computeLuminance();
          final ratio = textLuminance > surfaceLuminance
              ? (textLuminance + .05) / (surfaceLuminance + .05)
              : (surfaceLuminance + .05) / (textLuminance + .05);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$type / light=$light',
          );
        }
      }
    },
  );

  testWidgets(
    'all five held workspaces fit phone, tablet and desktop including 200 percent',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final type in ServerType.values) {
        for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0, 1920.0]) {
          for (final scale in [1.0, 2.0]) {
            final repository = TestServerRepository()
              ..servers = [fixtureServer(type)]
              ..channels = fixtureChannels(type);
            await pumpServers(
              tester,
              ServerWorkspaceScreen(
                key: UniqueKey(),
                serverId: 's',
                repository: repository,
                isRootTab: true,
                chatService: fakeChatService(),
              ),
              size: Size(width, 720),
              textScale: scale,
              light: scale == 2,
            );
            // A held root: the join surface is drawn but inert, and nothing
            // pretends to be live or populated.
            final join = find.byKey(const ValueKey('server-join'));
            expect(join, findsOneWidget, reason: '$type $width $scale');
            expect(tester.widget<FilledButton>(join).onPressed, isNull);
            // Nothing claims liveness. The marker itself is what is
            // asserted, not the words: "NA ŻYWO" is also the community
            // template's channel-group heading (contract §4.2), which names
            // a group of channels and says nothing about a session.
            expect(
              find.byKey(const ValueKey('server-live-pill')),
              findsNothing,
              reason: '$type $width $scale',
            );
            expect(find.text('Maja'), findsNothing);
            expect(repository.calls, isEmpty);
            expect(
              tester.takeException(),
              isNull,
              reason: '$type $width $scale',
            );
          }
        }
      }
    },
  );

  testWidgets('held root never mounts runtime content or enables invites', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..servers = [fixtureServer(ServerType.friends)]
      ..channels = fixtureChannels(ServerType.friends);
    var builds = 0;
    var invites = 0;
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        onInvite: (_) => invites++,
        chatService: fakeChatService(),
        channelBuilder: (_, _, _) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    expect(builds, 0);
    // The panel lives in the phone's sheet at this width.
    await tester.tap(find.byKey(const ValueKey('server-open-channels')));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('server-invite-action'));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      find.text('Zaproszenia będą możliwe, gdy serwer będzie gotowy.'),
      findsOneWidget,
    );
    expect(invites, 0);
  });

  testWidgets(
    'channel changes render the selected id without mutating server data',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [fixtureServer(ServerType.friends, held: false)]
        ..channels = fixtureChannels(ServerType.friends);
      final shown = <String>[];
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          channelBuilder: (_, _, channel) {
            shown.add(channel.id);
            return Text(channel.id);
          },
          // Desktop width puts the default text channel in the context
          // panel beside the media scene, so the thread needs its seam.
          chatService: fakeChatService(),
        ),
        size: const Size(1100, 720),
      );
      await tester.tap(find.byKey(const ValueKey('server-channel-chat')));
      await tester.pumpAndSettle();
      expect(shown.last, 'chat');
      expect(repository.requests, isEmpty);
    },
  );

  testWidgets('revoked channel read removes previously rendered content', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = StreamController<List<ServerChannel>>.broadcast();
    addTearDown(controller.close);
    final repository = TestServerRepository()
      ..servers = [fixtureServer(ServerType.company, held: false)]
      ..channelStream = controller.stream;
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        channelBuilder: (_, _, channel) => Text('private-${channel.id}'),
      ),
      settle: false,
    );
    controller.add(fixtureChannels(ServerType.company));
    await tester.pumpAndSettle();
    expect(find.text('private-voice'), findsOneWidget);
    controller.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await tester.pumpAndSettle();
    expect(find.text('private-voice'), findsNothing);
    expect(find.text('Nie masz uprawnień, aby to zrobić.'), findsOneWidget);
  });

  testWidgets(
    'configuration and directory tolerate short screens and large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 768.0, 1440.0]) {
        await pumpServers(
          tester,
          CreateServerScreen(
            key: UniqueKey(),
            repository: TestServerRepository(),
            initialType: ServerType.family,
          ),
          size: Size(width, 400),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        final submit = tester.getRect(
          find.byKey(const ValueKey('server-create-submit')),
        );
        expect(submit.bottom, lessThanOrEqualTo(400));
        final repository = TestServerRepository()
          ..servers = [fixtureServer(ServerType.family)];
        await pumpServers(
          tester,
          ServersScreen(repository: repository, isRootTab: true),
          size: Size(width, 400),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
