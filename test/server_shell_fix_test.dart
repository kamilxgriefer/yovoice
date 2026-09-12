import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// The lifecycle, schema-tolerance and device defects the shell gate blocked
/// on. Each test here names the failure it locks out, not the code path.
void main() {
  group('a layout change never ends a conversation', () {
    testWidgets('narrowing a hosted workspace below the tablet breakpoint '
        'keeps the person in the conversation', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: qaChat(),
          connector: connector,
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-channel-lounge')));
      await tester.pumpAndSettle();
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(qaDock, findsOneWidget);

      // A desktop window dragged narrow, browser zoom at 200 % on a 1440 px
      // window, or a small tablet turned to portrait — all the same event.
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpAndSettle();
      expect(
        link.disconnects,
        0,
        reason: 'the resize dropped the person from the call',
      );
      expect(
        qaDock,
        findsOneWidget,
        reason: 'the conversation lost its dock on the phone tier',
      );
      expect(
        find.byKey(const ValueKey('servers-create')),
        findsNothing,
        reason: 'the surface fell back to the directory',
      );
      // The panel is not drawn at this width, so the way back must be here.
      expect(find.byKey(const ValueKey('server-phone-back')), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpAndSettle();
      expect(link.disconnects, 0);
      expect(qaDock, findsOneWidget);
    });

    testWidgets('the hosted workspace leaves when its shell slot goes '
        'invisible', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: qaChat(),
          connector: connector,
          isVisible: visible,
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-channel-lounge')));
      await tester.pumpAndSettle();
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(qaDock, findsOneWidget);

      // The desktop shell keeps hidden slots mounted; the microphone must not
      // stay open behind a dock nobody can see.
      visible.value = false;
      await tester.pumpAndSettle();
      expect(link.disconnects, 1);
      expect(qaDock, findsNothing);
      expect(pumpedVoiceDevice.keepAliveStops, 1);
    });
  });

  group('a reconnect never removes a privacy control', () {
    testWidgets('the dock keeps the microphone and the headphones, and both '
        'still act', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(link.microphoneCalls, [true]);

      link.report(ServerMediaLinkState.reconnecting);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('server-dock-microphone')),
        findsOneWidget,
        reason: 'the mute disappeared while the capture stayed open',
      );
      expect(
        find.byKey(const ValueKey('server-dock-headphones')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(
        link.microphoneCalls,
        [true, false],
        reason: 'the control was mounted, enabled and inert',
      );
      await tester.tap(find.byKey(const ValueKey('server-dock-headphones')));
      await tester.pumpAndSettle();
      expect(link.deafenCalls, [true]);
    });

    testWidgets('the Salon round controls act during a reconnect too', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      link.report(ServerMediaLinkState.reconnecting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-session-microphone')));
      await tester.pumpAndSettle();
      expect(link.microphoneCalls, [true]);
    });
  });

  group('the device a conversation actually plays on', () {
    testWidgets('a join asks for the speaker and starts the keep-alive; '
        'leaving stops it', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final device = pumpedVoiceDevice;
      expect(device.speakerRequests, 0, reason: 'asked before any join');
      expect(device.keepAliveStarts, 0);

      await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(
        device.speakerRequests,
        1,
        reason: 'a social conversation left on whatever route the last call '
            'happened to leave behind',
      );
      expect(device.keepAliveStarts, 1);
      expect(device.lastCanPublish, isTrue);
      expect(device.lastTitle, 'Po godzinach');

      await tester.tap(find.byKey(const ValueKey('server-dock-leave')));
      await tester.pumpAndSettle();
      expect(device.keepAliveStops, 1);
    });

    testWidgets('a listener keeps the service, but not as a microphone', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.podcast)]
        ..channels = qaChannels(ServerType.podcast, activeSessionId: 'gen-1')
        ..sessionRole = 'listener'
        ..permittedTrackSources = const [];
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'studio', connector: connector),
        size: const Size(1440, 900),
      );
      await qaJoinAndSettle(tester, connector);
      expect(pumpedVoiceDevice.keepAliveStarts, 1);
      expect(pumpedVoiceDevice.lastCanPublish, isFalse);
    });
  });

  group('one document a newer backend wrote never breaks a whole list', () {
    Future<ServerService> seeded(FakeFirebaseFirestore firestore) async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u'),
      );
      return ServerService(firestore: firestore, auth: auth);
    }

    test('a server on an unknown schema version drops out of the directory',
        () async {
      final firestore = FakeFirebaseFirestore();
      for (final (id, version) in const [('good', 1), ('future', 2)]) {
        await firestore.doc('clubs/$id').set({
          'serverSchemaVersion': version,
          'serverType': 'friends',
          'name': id,
          'ownerId': 'u',
          'privacy': 'private',
        });
        await firestore.doc('users/u/clubs/$id').set({
          'clubId': id,
          'joinedAt': Timestamp.now(),
        });
      }
      final service = await seeded(firestore);
      final servers = await service.watchMyServers().first;
      expect(
        servers.map((s) => s.id),
        ['good'],
        reason: 'one future document took the whole directory down',
      );
    });

    test('a channel of an unknown kind drops out of the channel list',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('clubs/s').set({
        'serverSchemaVersion': 1,
        'serverType': 'community',
        'name': 'Klub',
        'ownerId': 'u',
        'privacy': 'public',
      });
      Map<String, Object> channel(String kind) => {
        'serverSchemaVersion': 1,
        'serverId': 's',
        'name': kind,
        'kind': kind,
        'accessMode': 'members',
        'isPrivate': false,
        'status': 'active',
        'position': 0,
      };
      await firestore.doc('clubs/s/channels/general').set(channel('text'));
      await firestore.doc('clubs/s/channels/spatial').set(channel('spatial'));
      final service = await seeded(firestore);
      expect(
        (await service.watchChannels('s').first).map((c) => c.id),
        ['general'],
        reason: 'one future channel kind took the whole list down',
      );
    });
  });

  group('the configuration screen follows the app it is running in', () {
    for (final (locale, expected) in const [
      (Locale('pl'), 'Polish'),
      (Locale('en'), 'English'),
    ]) {
      testWidgets('$locale seeds the channels in $expected', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpServers(
          tester,
          CreateServerScreen(
            repository: TestServerRepository(),
            initialType: ServerType.friends,
          ),
          size: const Size(1440, 900),
          locale: locale,
        );
        final field = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('server-language')),
        );
        expect(field.initialValue, expected);
      });
    }
  });
}
