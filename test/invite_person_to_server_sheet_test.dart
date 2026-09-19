import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/invite_person_to_server_sheet.dart';

Server _server(
  String id,
  String name, {
  ServerType type = ServerType.friends,
  ServerPrivacy privacy = ServerPrivacy.private,
  String activationState = 'active',
}) => Server(
  id: id,
  name: name,
  description: '',
  ownerId: 'someone',
  type: type,
  privacy: privacy,
  schemaVersion: 1,
  activationState: activationState,
);

class _Repo implements ServerRepository {
  _Repo({required this.servers, required this.roles, this.inviteError});

  final Stream<List<Server>> servers;
  final Map<String, ServerMemberRole?> roles;
  Object? inviteError;
  final invites = <String>[];
  final roleRequests = <String>[];
  Completer<void>? inviteGate;
  var _requests = 0;

  @override
  Stream<List<Server>> watchMyServers() => servers;

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) {
    roleRequests.add(serverId);
    return Stream.value(roles[serverId]);
  }

  @override
  String newRequestId() => 'request-${++_requests}';

  @override
  Future<ServerInviteResult> createInvite({
    required String serverId,
    required String inviteeId,
    required String requestId,
  }) async {
    invites.add('$serverId:$inviteeId');
    await inviteGate?.future;
    if (inviteError case final error?) throw error;
    return ServerInviteResult(
      serverId: serverId,
      inviteeId: inviteeId,
      generation: 1,
      status: 'pending',
      alreadyExisted: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pump(WidgetTester tester, ServerRepository repository) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: InvitePersonToServerSheet(
            inviteeId: 'friend-1',
            inviteeName: 'Ola',
            repository: repository,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  testWidgets('offers only servers where the viewer may invite, never a '
      'held one', (tester) async {
    final repo = _Repo(
      servers: Stream.value([
        _server('mod', 'Moderated'),
        _server('member-private', 'Private member'),
        _server(
          'member-public',
          'Public community',
          type: ServerType.community,
          privacy: ServerPrivacy.public,
        ),
        _server('held', 'Held', activationState: 'pendingPayment'),
      ]),
      roles: const {
        'mod': ServerMemberRole.moderator,
        'member-private': ServerMemberRole.member,
        'member-public': ServerMemberRole.member,
        'held': ServerMemberRole.owner,
      },
    );
    await pump(tester, repo);
    expect(find.text('Moderated'), findsOneWidget);
    expect(find.text('Public community'), findsOneWidget);
    expect(find.text('Private member'), findsNothing);
    expect(find.text('Held'), findsNothing);
    expect(repo.roleRequests, isNot(contains('held')));
  });

  testWidgets('loading shows skeleton rows, an empty list says so', (
    tester,
  ) async {
    final servers = StreamController<List<Server>>();
    addTearDown(servers.close);
    await pump(tester, _Repo(servers: servers.stream, roles: const {}));
    expect(key('invite-person-to-server-loading'), findsOneWidget);
    servers.add([_server('member-private', 'Private member')]);
    await tester.pump();
    await tester.pump();
    expect(key('invite-person-to-server-empty'), findsOneWidget);
    expect(
      find.text('You have no servers you can invite people to.'),
      findsOneWidget,
    );
  });

  testWidgets('an error offers a retry that resubscribes', (tester) async {
    await pump(
      tester,
      _Repo(
        servers: Stream<List<Server>>.error(StateError('offline')),
        roles: const {},
      ),
    );
    expect(key('invite-person-to-server-error'), findsOneWidget);
  });

  testWidgets('one invite per tap, then Invited', (tester) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.admin},
    )..inviteGate = Completer<void>();
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    expect(key('invite-person-to-server-mod'), findsNothing);
    repo.inviteGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(repo.invites, ['mod:friend-1']);
    expect(find.text('Invited'), findsOneWidget);
  });

  testWidgets('failed-precondition reads as already on the server', (
    tester,
  ) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.owner},
      inviteError: FirebaseFunctionsException(
        message: 'This person already belongs to this server.',
        code: 'failed-precondition',
      ),
    );
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Already on this server'), findsOneWidget);
  });

  testWidgets('permission-denied names the failure and allows a retry', (
    tester,
  ) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.owner},
      inviteError: FirebaseFunctionsException(
        message: 'denied',
        code: 'permission-denied',
      ),
    );
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not send the invite.'), findsOneWidget);
    expect(key('invite-person-to-server-mod'), findsOneWidget);
  });

  testWidgets('an unverified inviter is asked to verify, not told the person '
      'is already on the server, and can retry', (tester) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.owner},
      inviteError: FirebaseFunctionsException(
        message: 'Verify your email before continuing.',
        code: 'failed-precondition',
      ),
    );
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Already on this server'), findsNothing);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(key('invite-person-to-server-mod'), findsOneWidget);
  });

  testWidgets('a server activation refusal uses the shared availability copy '
      'and stays retryable', (tester) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.owner},
      inviteError: FirebaseFunctionsException(
        message: 'This person already belongs to this server.',
        code: 'failed-precondition',
        details: const {'reason': serverActivationUnavailableReason},
      ),
    );
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Already on this server'), findsNothing);
    expect(
      find.text('This part of YO Voice is still being prepared.'),
      findsOneWidget,
    );
    expect(key('invite-person-to-server-mod'), findsOneWidget);
  });

  testWidgets('any other failed-precondition is a retryable failure', (
    tester,
  ) async {
    final repo = _Repo(
      servers: Stream.value([_server('mod', 'Moderated')]),
      roles: const {'mod': ServerMemberRole.owner},
      inviteError: FirebaseFunctionsException(
        message: 'Something else.',
        code: 'failed-precondition',
      ),
    );
    await pump(tester, repo);
    await tester.tap(key('invite-person-to-server-mod'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Already on this server'), findsNothing);
    expect(key('invite-person-to-server-mod'), findsOneWidget);
  });
}
