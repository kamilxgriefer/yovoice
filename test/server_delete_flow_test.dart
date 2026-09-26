import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_test_support.dart';

const _owned = Server(
  id: 'ekipa',
  name: 'Ekipa',
  description: 'Po godzinach',
  ownerId: 'owner',
  type: ServerType.friends,
  privacy: ServerPrivacy.private,
  schemaVersion: 1,
  activationState: 'active',
  revision: 3,
  directoryRole: ServerMemberRole.owner,
);

const _joined = Server(
  id: 'klub',
  name: 'Klub',
  description: '',
  ownerId: 'someone-else',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  schemaVersion: 1,
  activationState: 'active',
  revision: 1,
  directoryRole: ServerMemberRole.member,
);

const _legacy = Server(
  id: 'stary',
  name: 'Stary klub',
  description: '',
  ownerId: 'owner',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
);

final _liveVoice = ServerChannel(
  id: 'voice',
  serverId: 'ekipa',
  name: 'Pokój',
  kind: ServerChannelKind.voice,
  schemaVersion: 1,
  activeSessionId: 'gen-4',
  liveness: ServerChannelLiveness(
    isLive: true,
    startedAt: DateTime.utc(2026, 9, 19, 12),
  ),
);

Future<void> _pumpDirectory(
  WidgetTester tester,
  TestServerRepository repository, {
  Size size = const Size(390, 844),
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpServers(
    tester,
    ServersScreen(repository: repository, onOpenServer: (_) {}),
    size: size,
  );
}

Future<void> _openActions(WidgetTester tester, String serverId) async {
  await tester.tap(find.byKey(ValueKey('server-directory-actions-$serverId')));
  await tester.pumpAndSettle();
}

Iterable<String> _callNames(TestServerRepository repository) =>
    repository.calls.map((call) => call.$1);

void main() {
  group('servers directory actions', () {
    testWidgets('the owner gets "Usuń serwer", a member gets "Opuść serwer"', (
      tester,
    ) async {
      final repository = TestServerRepository()..servers = [_owned, _joined];
      await _pumpDirectory(tester, repository);

      await _openActions(tester, 'ekipa');
      expect(find.byKey(const ValueKey('server-directory-delete')), findsOne);
      expect(
        find.byKey(const ValueKey('server-directory-leave')),
        findsNothing,
      );
      expect(find.text('Usuń serwer'), findsOne);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _openActions(tester, 'klub');
      expect(find.byKey(const ValueKey('server-directory-leave')), findsOne);
      expect(
        find.byKey(const ValueKey('server-directory-delete')),
        findsNothing,
      );
      expect(find.text('Opuść serwer'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long press on the row opens the same action sheet', (
      tester,
    ) async {
      final repository = TestServerRepository()..servers = [_owned];
      await _pumpDirectory(tester, repository, size: const Size(1280, 800));

      await tester.longPress(
        find.byKey(const ValueKey('server-directory-ekipa')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('server-directory-actions-sheet')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('server-directory-delete')), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a mirror role the root owner id decides', (
      tester,
    ) async {
      final repository = TestServerRepository()
        ..servers = [
          _owned.withDirectoryRole(null),
          _joined.withDirectoryRole(null),
        ];
      await _pumpDirectory(tester, repository);

      await _openActions(tester, 'ekipa');
      expect(find.byKey(const ValueKey('server-directory-delete')), findsOne);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await _openActions(tester, 'klub');
      expect(find.byKey(const ValueKey('server-directory-leave')), findsOne);
    });

    testWidgets(
      'delete needs the typed server name, then calls deleteServerV1 and '
      'drops the row',
      (tester) async {
        final repository = TestServerRepository()..servers = [_owned, _joined];
        await _pumpDirectory(tester, repository);

        await _openActions(tester, 'ekipa');
        await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('server-delete-dialog')), findsOne);
        expect(
          find.text(
            'Kanały, wiadomości i pliki zostaną usunięte, a członkowie '
            'stracą dostęp.',
          ),
          findsOne,
        );
        expect(
          find.byKey(const ValueKey('server-delete-live-notice')),
          findsNothing,
        );
        FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const ValueKey('server-delete-confirm')),
        );
        expect(confirm().onPressed, isNull);

        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'ekipa',
        );
        await tester.pump();
        expect(confirm().onPressed, isNull, reason: 'Case must match.');

        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'Ekipa',
        );
        await tester.pump();
        expect(confirm().onPressed, isNotNull);
        expect(_callNames(repository), isNot(contains('deleteServerV1')));

        await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
        await tester.pumpAndSettle();

        final delete = repository.calls.singleWhere(
          (call) => call.$1 == 'deleteServerV1',
        );
        expect(delete.$2['serverId'], 'ekipa');
        expect(delete.$2['requestId'], isA<String>());
        expect(
          find.byKey(const ValueKey('server-directory-ekipa')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('server-directory-klub')), findsOne);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final repository = TestServerRepository()..servers = [_owned];
      await _pumpDirectory(tester, repository);

      await _openActions(tester, 'ekipa');
      await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-delete-cancel')));
      await tester.pumpAndSettle();

      expect(_callNames(repository), isNot(contains('deleteServerV1')));
      expect(find.byKey(const ValueKey('server-directory-ekipa')), findsOne);
    });

    testWidgets('a legacy root routes to deleteClubSelf, never V1', (
      tester,
    ) async {
      final repository = TestServerRepository()..servers = [_legacy];
      await _pumpDirectory(tester, repository);

      await _openActions(tester, 'stary');
      await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('server-delete-confirm-field')),
        'Stary klub',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
      await tester.pumpAndSettle();

      expect(_callNames(repository), contains('deleteClubSelf'));
      expect(_callNames(repository), isNot(contains('deleteServerV1')));
      expect(
        repository.calls.singleWhere((call) => call.$1 == 'deleteClubSelf').$2,
        {'clubId': 'stary'},
      );
      expect(
        find.byKey(const ValueKey('server-directory-stary')),
        findsNothing,
      );
    });

    testWidgets(
      'a live channel offers "Zakończ rozmowy i usuń", ending each live '
      'session before deleteServerV1',
      (tester) async {
        final repository = TestServerRepository()
          ..servers = [_owned]
          ..channels = [_liveVoice];
        await _pumpDirectory(tester, repository);

        await _openActions(tester, 'ekipa');
        await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('server-delete-live-notice')),
          findsOne,
        );
        expect(find.text('Zakończ rozmowy i usuń'), findsOne);
        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'Ekipa',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
        await tester.pumpAndSettle();

        final names = _callNames(repository).toList();
        final end = names.indexOf('endServerChannelSessionV1');
        final delete = names.indexOf('deleteServerV1');
        expect(end, greaterThanOrEqualTo(0));
        expect(delete, greaterThan(end));
        final endCall = repository.calls[end].$2;
        expect(endCall['serverId'], 'ekipa');
        expect(endCall['channelId'], 'voice');
        expect(endCall['sessionId'], 'gen-4');
        expect(
          find.byKey(const ValueKey('server-directory-ekipa')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a live-session refusal says to end the conversation, not "denied"',
      (tester) async {
        final repository = TestServerRepository()..servers = [_owned];
        repository.failNextCall['deleteServerV1'] = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'End the live session in this server before deleting it.',
        );
        await _pumpDirectory(tester, repository);

        await _openActions(tester, 'ekipa');
        await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'Ekipa',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('server-directory-action-error')),
          findsOne,
        );
        expect(
          find.text(
            'Na serwerze trwa rozmowa. Zakończ ją przed usunięciem serwera.',
          ),
          findsOne,
        );
        expect(find.byKey(const ValueKey('server-directory-ekipa')), findsOne);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a member leaves through leaveServerV1 after confirming', (
      tester,
    ) async {
      final repository = TestServerRepository()..servers = [_joined];
      await _pumpDirectory(tester, repository);

      await _openActions(tester, 'klub');
      await tester.tap(find.byKey(const ValueKey('server-directory-leave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-leave-dialog')), findsOne);
      await tester.tap(find.byKey(const ValueKey('server-leave-confirm')));
      await tester.pumpAndSettle();

      final leave = repository.calls.singleWhere(
        (call) => call.$1 == 'leaveServerV1',
      );
      expect(leave.$2['serverId'], 'klub');
      expect(find.byKey(const ValueKey('server-directory-klub')), findsNothing);
    });

    testWidgets('long names and 200 % text keep the row and dialog intact', (
      tester,
    ) async {
      final long = _owned.withDirectoryRole(ServerMemberRole.owner);
      final repository = TestServerRepository()
        ..servers = [
          Server(
            id: long.id,
            name: 'Bardzo długa nazwa serwera dla całej rodziny i znajomych',
            description: long.description * 6,
            ownerId: long.ownerId,
            type: long.type,
            privacy: long.privacy,
            schemaVersion: 1,
            activationState: 'active',
            directoryRole: ServerMemberRole.owner,
          ),
        ];
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServersScreen(repository: repository, onOpenServer: (_) {}),
        size: const Size(320, 700),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await _openActions(tester, 'ekipa');
      await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-delete-dialog')), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('management sheet danger zone', () {
    TestServerRepository ownerRepository() => TestServerRepository()
      ..servers = const [
        Server(
          id: 'server',
          name: 'Ekipa',
          description: '',
          ownerId: 'owner',
          type: ServerType.friends,
          privacy: ServerPrivacy.private,
          schemaVersion: 1,
          activationState: 'active',
          revision: 2,
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

    testWidgets(
      'wide panel draws a labelled settings entry; the sheet keeps delete '
      'in its own danger zone behind the typed name',
      (tester) async {
        final repository = ownerRepository();
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpServers(
          tester,
          ServerWorkspaceScreen(
            serverId: 'server',
            repository: repository,
            channelBuilder: (_, _, _) => const SizedBox(),
          ),
          size: const Size(1200, 900),
        );

        final manage = find.byKey(const ValueKey('server-manage-action'));
        expect(manage, findsOne);
        expect(
          find.descendant(of: manage, matching: find.text('Ustawienia')),
          findsOne,
        );
        await tester.tap(manage);
        await tester.pumpAndSettle();

        final zone = find.byKey(const ValueKey('server-danger-zone'));
        await tester.scrollUntilVisible(
          zone,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('server-management-overview')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.descendant(of: zone, matching: find.text('Strefa zagrożenia')),
          findsOne,
        );
        final delete = find.descendant(
          of: zone,
          matching: find.byKey(const ValueKey('server-delete-action')),
        );
        expect(delete, findsOne);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'Ekipa',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
        await tester.pumpAndSettle();

        expect(_callNames(repository), contains('deleteServerV1'));
        expect(
          find.byKey(const ValueKey('server-management-overview')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the sheet shows the live-session refusal copy', (
      tester,
    ) async {
      final repository = ownerRepository();
      repository.failNextCall['deleteServerV1'] = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'End the live session in this server before deleting it.',
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      final delete = find.byKey(const ValueKey('server-delete-action'));
      await tester.scrollUntilVisible(
        delete,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('server-management-overview')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('server-delete-confirm-field')),
        'Ekipa',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
      await tester.pumpAndSettle();

      final message = find.byKey(const ValueKey('server-management-message'));
      expect(message, findsOne);
      expect(
        find.descendant(
          of: message,
          matching: find.text(
            'Na serwerze trwa rozmowa. Zakończ ją przed usunięciem serwera.',
          ),
        ),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('server-management-overview')),
        findsOne,
      );
    });

    testWidgets('the phone channel sheet keeps a compact settings gear', (
      tester,
    ) async {
      final repository = ownerRepository();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 'server',
          repository: repository,
          channelBuilder: (_, _, _) => const SizedBox(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('server-open-channels')));
      await tester.pumpAndSettle();

      final manage = find.byKey(const ValueKey('server-manage-action'));
      expect(manage, findsOne);
      expect(tester.widget(manage), isA<IconButton>());
      expect(
        find.descendant(
          of: manage,
          matching: find.byIcon(Icons.settings_outlined),
        ),
        findsOne,
      );
    });
  });

  group('service routing', () {
    test('a legacy delete calls deleteClubSelf with the club id', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerService(
        call: (name, data) async {
          calls.add((name, data));
          return const {};
        },
      );
      await service.deleteLegacyServer(serverId: 'stary');
      await service.deleteServer(serverId: 'ekipa', requestId: 'req');

      expect(calls.map((call) => call.$1), [
        'deleteClubSelf',
        'deleteServerV1',
      ]);
      expect(calls.first.$2, {'clubId': 'stary'});
      expect(calls.last.$2, {'serverId': 'ekipa', 'requestId': 'req'});
    });

    test('the directory carries the mirror role as a display hint', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u'),
      );
      for (final (id, owner) in [('mine', 'u'), ('theirs', 'x')]) {
        await firestore.doc('clubs/$id').set({
          'serverSchemaVersion': 1,
          'serverType': 'friends',
          'name': id,
          'ownerId': owner,
          'privacy': 'private',
          'serverActivationState': 'active',
        });
      }
      await firestore.doc('users/u/clubs/mine').set({
        'clubId': 'mine',
        'role': 'owner',
        'joinedAt': Timestamp.now(),
      });
      await firestore.doc('users/u/clubs/theirs').set({
        'clubId': 'theirs',
        'role': 'member',
        'joinedAt': Timestamp.now(),
      });
      final service = ServerService(firestore: firestore, auth: auth);
      final before = firestore.dump();

      final servers = await service.watchMyServers().first;
      final roles = {
        for (final server in servers) server.id: server.directoryRole,
      };
      expect(roles, {
        'mine': ServerMemberRole.owner,
        'theirs': ServerMemberRole.member,
      });
      expect(firestore.dump(), before);
    });
  });
}
