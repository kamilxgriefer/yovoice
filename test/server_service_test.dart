import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

void main() {
  test(
    'creation recovers a committed request whose first acknowledgement stalls',
    () async {
      var calls = 0;
      final payloads = <Map<String, Object?>>[];
      final firstAcknowledgement = Completer<Map<Object?, Object?>>();
      final service = ServerService(
        creationAttemptTimeout: const Duration(milliseconds: 10),
        call: (name, data) async {
          expect(name, 'createServerV1');
          calls++;
          payloads.add(data);
          if (calls == 1) return firstAcknowledgement.future;
          return {
            'serverId': 'saved',
            'defaultChannelId': 'general',
            'channelIds': ['general', 'voice'],
            'alreadyExisted': true,
          };
        },
      );

      const request = ServerCreationRequest(
        requestId: 'stable',
        serverType: ServerType.friends,
        name: 'Friends',
        description: '',
        privacy: ServerPrivacy.inviteOnly,
        defaultLanguage: 'Polish',
      );
      final result = await service.createServer(request);

      expect(calls, 2);
      expect(identical(payloads[0], payloads[1]), isTrue);
      expect(payloads[1]['requestId'], 'stable');
      expect(result.serverId, 'saved');
      expect(result.alreadyExisted, isTrue);
    },
  );

  test('creation stops waiting after two stalled acknowledgements', () async {
    var calls = 0;
    final service = ServerService(
      creationAttemptTimeout: const Duration(milliseconds: 10),
      call: (_, _) {
        calls++;
        return Completer<Map<Object?, Object?>>().future;
      },
    );

    await expectLater(
      service.createServer(
        const ServerCreationRequest(
          requestId: 'stable',
          serverType: ServerType.friends,
          name: 'Friends',
          description: '',
          privacy: ServerPrivacy.inviteOnly,
          defaultLanguage: 'Polish',
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 2);
  });

  test('creation never replays under a different authenticated user', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'owner-a'),
    );
    var calls = 0;
    final service = ServerService(
      auth: auth,
      creationAttemptTimeout: const Duration(milliseconds: 10),
      call: (_, _) {
        calls++;
        if (calls > 1) fail('the request crossed an account boundary');
        auth.mockUser = MockUser(uid: 'owner-b');
        return Completer<Map<Object?, Object?>>().future;
      },
    );

    await expectLater(
      service.createServer(
        const ServerCreationRequest(
          requestId: 'owner-a-request',
          serverType: ServerType.friends,
          name: 'Friends',
          description: '',
          privacy: ServerPrivacy.inviteOnly,
          defaultLanguage: 'Polish',
        ),
      ),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(calls, 1);
  });

  test('creation never returns a late success to another user', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'owner-a'),
    );
    final response = Completer<Map<Object?, Object?>>();
    final service = ServerService(auth: auth, call: (_, _) => response.future);

    final result = service.createServer(
      const ServerCreationRequest(
        requestId: 'owner-a-success',
        serverType: ServerType.friends,
        name: 'Friends',
        description: '',
        privacy: ServerPrivacy.inviteOnly,
        defaultLanguage: 'Polish',
      ),
    );
    auth.mockUser = MockUser(uid: 'owner-b');
    response.complete({
      'serverId': 'owner-a-server',
      'defaultChannelId': 'general',
      'channelIds': ['general', 'voice'],
      'alreadyExisted': false,
    });

    await expectLater(
      result,
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });

  test('creation never returns a late refusal to another user', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'owner-a'),
    );
    final response = Completer<Map<Object?, Object?>>();
    final service = ServerService(auth: auth, call: (_, _) => response.future);

    final result = service.createServer(
      const ServerCreationRequest(
        requestId: 'owner-a-refusal',
        serverType: ServerType.friends,
        name: 'Friends',
        description: '',
        privacy: ServerPrivacy.inviteOnly,
        defaultLanguage: 'Polish',
      ),
    );
    auth.mockUser = MockUser(uid: 'owner-b');
    response.completeError(
      FirebaseFunctionsException(code: 'invalid-argument', message: 'refused'),
    );

    await expectLater(
      result,
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });

  test('creation does not call the backend after sign-out', () async {
    final auth = MockFirebaseAuth(signedIn: false);
    var calls = 0;
    final service = ServerService(
      auth: auth,
      call: (_, _) async {
        calls++;
        return const <Object?, Object?>{};
      },
    );

    await expectLater(
      service.createServer(
        const ServerCreationRequest(
          requestId: 'signed-out-request',
          serverType: ServerType.friends,
          name: 'Friends',
          description: '',
          privacy: ServerPrivacy.inviteOnly,
          defaultLanguage: 'Polish',
        ),
      ),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(calls, 0);
  });

  test(
    'creation calls only the exact V1 endpoint with immutable payload',
    () async {
      final calls = <Map<String, Object?>>[];
      final service = ServerService(
        call: (name, data) async {
          expect(name, 'createServerV1');
          calls.add(data);
          return {
            'serverId': 's',
            'defaultChannelId': 'c',
            'channelIds': ['c', 'voice'],
            'alreadyExisted': calls.length > 1,
          };
        },
      );
      const request = ServerCreationRequest(
        requestId: 'stable',
        serverType: ServerType.podcast,
        name: 'Podcast',
        description: 'Our show',
        privacy: ServerPrivacy.inviteOnly,
        defaultLanguage: 'Polish',
      );
      expect((await service.createServer(request)).alreadyExisted, isFalse);
      expect((await service.createServer(request)).alreadyExisted, isTrue);
      expect(calls[0], {
        'requestId': 'stable',
        'serverType': 'podcast',
        'templateVersion': 1,
        'name': 'Podcast',
        'description': 'Our show',
        'privacy': 'inviteOnly',
        'defaultLanguage': 'Polish',
      });
      expect(calls[1], calls[0]);
    },
  );

  test(
    'public admission calls only joinServerV1 with the supplied retry id',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerService(
        call: (name, data) async {
          calls.add((name, data));
          return const <Object?, Object?>{};
        },
      );

      await service.joinServer(
        serverId: 'public-server',
        requestId: 'stable-join',
      );
      await service.joinServer(
        serverId: 'public-server',
        requestId: 'stable-join',
      );

      expect(calls.map((call) => call.$1), ['joinServerV1', 'joinServerV1']);
      expect(calls[0].$2, {
        'serverId': 'public-server',
        'requestId': 'stable-join',
      });
      expect(calls[1].$2, calls[0].$2);
    },
  );

  test('generation end calls only endServerChannelSessionV1', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerService(
      call: (name, data) async {
        calls.add((name, data));
        return const <Object?, Object?>{};
      },
    );

    await service.endChannelSession(
      serverId: 'server',
      channelId: 'stage',
      sessionId: 'generation-7',
      requestId: 'stable-end',
    );

    expect(calls.single.$1, 'endServerChannelSessionV1');
    expect(calls.single.$2, {
      'serverId': 'server',
      'channelId': 'stage',
      'sessionId': 'generation-7',
      'requestId': 'stable-end',
    });
  });

  test('the leave signal calls only releaseServerChannelSessionIfEmptyV1 and '
      'reads its receipt strictly', () async {
    final calls = <(String, Map<String, Object?>)>[];
    var answer = <Object?, Object?>{
      'sessionId': 'generation-7',
      'outcome': 'pending',
      'recheckAfterMillis': 60000,
    };
    final service = ServerService(
      call: (name, data) async {
        calls.add((name, data));
        return answer;
      },
    );

    final pending = await service.releaseChannelSessionIfEmpty(
      serverId: 'server',
      channelId: 'lounge',
      sessionId: 'generation-7',
      requestId: 'leave-1',
    );
    expect(calls.single.$1, 'releaseServerChannelSessionIfEmptyV1');
    expect(calls.single.$2, {
      'serverId': 'server',
      'channelId': 'lounge',
      'sessionId': 'generation-7',
      'requestId': 'leave-1',
    });
    expect(pending.isPending, isTrue);
    expect(pending.recheckAfter, const Duration(seconds: 60));

    // A receipt can never keep the client waiting longer than the cap.
    answer = {
      'sessionId': 'generation-7',
      'outcome': 'pending',
      'recheckAfterMillis': 86400000,
    };
    final capped = await service.releaseChannelSessionIfEmpty(
      serverId: 'server',
      channelId: 'lounge',
      sessionId: 'generation-7',
      requestId: 'leave-2',
    );
    expect(capped.recheckAfter, ServerSessionReleaseResult.maxRecheckAfter);

    answer = {'sessionId': 'generation-7', 'outcome': 'occupied'};
    final occupied = await service.releaseChannelSessionIfEmpty(
      serverId: 'server',
      channelId: 'lounge',
      sessionId: 'generation-7',
      requestId: 'leave-3',
    );
    expect(occupied.isPending, isFalse);
    expect(occupied.recheckAfter, Duration.zero);

    answer = {'outcome': 'ended'};
    await expectLater(
      service.releaseChannelSessionIfEmpty(
        serverId: 'server',
        channelId: 'lounge',
        sessionId: 'generation-7',
        requestId: 'leave-4',
      ),
      throwsFormatException,
    );
  });

  test('directory reads old ids without migrating roots', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u'));
    await firestore.doc('clubs/old').set({
      'name': 'Old',
      'type': 'family',
      'ownerId': 'u',
    });
    await firestore.doc('users/u/clubs/old').set({
      'clubId': 'old',
      'joinedAt': Timestamp.now(),
    });
    final service = ServerService(firestore: firestore, auth: auth);
    final before = firestore.dump();
    final result = await service.watchMyServers().first;
    expect(result.single.id, 'old');
    expect(result.single.type, ServerType.family);
    expect(firestore.dump(), before);
  });

  test(
    'V1 directory excludes restricted names without private pointers and archived rows',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u'),
      );
      await firestore.doc('clubs/s').set({
        'serverSchemaVersion': 1,
        'serverType': 'company',
        'name': 'Company',
        'ownerId': 'u',
        'privacy': 'inviteOnly',
        'serverActivationState': 'held',
      });
      Map<String, Object> channel(String name, String access, String status) =>
          {
            'serverSchemaVersion': 1,
            'serverId': 's',
            'name': name,
            'kind': 'text',
            'accessMode': access,
            'isPrivate': access == 'restricted',
            'status': status,
            'position': 0,
          };
      await firestore
          .doc('clubs/s/channels/general')
          .set(channel('general', 'members', 'active'));
      await firestore
          .doc('clubs/s/channels/hr')
          .set(channel('HR secret', 'restricted', 'active'));
      await firestore
          .doc('clubs/s/channels/archive')
          .set(channel('archived', 'members', 'archived'));
      final service = ServerService(firestore: firestore, auth: auth);
      expect((await service.watchChannels('s').first).map((c) => c.id), [
        'general',
      ]);
      await firestore.doc('users/u/serverChannelRefs/hr').set({
        'serverId': 's',
        'channelId': 'hr',
      });
      expect((await service.watchChannels('s').first).map((c) => c.id), [
        'general',
        'hr',
      ]);
    },
  );

  test('fresh request identities do not need Firebase and are unique', () {
    final service = ServerService();
    final ids = List.generate(50, (_) => service.newRequestId());
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => RegExp(r'^[0-9a-f]{48}$').hasMatch(id)), isTrue);
  });

  test(
    'account-scoped reads fail closed when no Firebase app exists',
    () async {
      final service = ServerService(firestore: FakeFirebaseFirestore());

      expect(await service.watchMyRole('server').first, isNull);
      expect(await service.watchInviteCandidates().first, isEmpty);
    },
  );

  test(
    'stage moderation uses the exact generation-bound callable contracts',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerService(
        call: (name, data) async {
          calls.add((name, data));
          final role = name == 'setServerSessionParticipantRoleV1'
              ? data['role']
              : 'guest';
          return {
            'serverId': 's',
            'channelId': 'stage',
            'sessionId': 'gen-7',
            'participantId': 'guest-1',
            'role': role,
            'hostMuted': name == 'setServerSessionMuteV1',
            'serverMuted': false,
            'participantRevision': 2,
            'changed': true,
            'cleanupPending': true,
            if (name == 'setServerSessionMuteV1') 'muted': data['muted'],
          };
        },
      );

      final role = await service.setSessionParticipantRole(
        serverId: 's',
        channelId: 'stage',
        sessionId: 'gen-7',
        participantId: 'guest-1',
        role: 'listener',
        requestId: 'role-request',
      );
      final mute = await service.setSessionParticipantMute(
        serverId: 's',
        channelId: 'stage',
        sessionId: 'gen-7',
        participantId: 'guest-1',
        muted: true,
        requestId: 'mute-request',
      );

      expect(calls.map((call) => call.$1), [
        'setServerSessionParticipantRoleV1',
        'setServerSessionMuteV1',
      ]);
      expect(calls[0].$2, {
        'serverId': 's',
        'channelId': 'stage',
        'sessionId': 'gen-7',
        'participantId': 'guest-1',
        'role': 'listener',
        'requestId': 'role-request',
      });
      expect(calls[1].$2, {
        'serverId': 's',
        'channelId': 'stage',
        'sessionId': 'gen-7',
        'participantId': 'guest-1',
        'muted': true,
        'requestId': 'mute-request',
      });
      expect(role.role, 'listener');
      expect(role.requestedMuted, isNull);
      expect(mute.requestedMuted, isTrue);
      expect(mute.isMuted, isTrue);
    },
  );

  test('stage moderation refuses a receipt for another participant', () async {
    final service = ServerService(
      call: (_, _) async => {
        'serverId': 's',
        'channelId': 'stage',
        'sessionId': 'gen-7',
        'participantId': 'somebody-else',
        'role': 'guest',
        'hostMuted': false,
        'serverMuted': false,
        'participantRevision': 2,
        'changed': true,
        'cleanupPending': true,
      },
    );

    await expectLater(
      service.setSessionParticipantRole(
        serverId: 's',
        channelId: 'stage',
        sessionId: 'gen-7',
        participantId: 'guest-1',
        role: 'guest',
        requestId: 'role-request',
      ),
      throwsFormatException,
    );
  });
}
