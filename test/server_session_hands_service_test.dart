import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session_hand.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

/// The repository half of request to speak.
///
/// The fake Firestore does not enforce `firestore.rules`; the emulator suite
/// (`firestore-tests/server_rules.test.js`) proves who may run these reads.
/// What this proves is the client's own contract: the queue carries exactly
/// the rule's four equalities, keeps only raised hands of the named
/// generation, sorts oldest first on the client, and the decline sends the
/// exact `answerServerSessionHandV1` payload and refuses a mismatched receipt.
Map<String, Object?> _participant(
  String uid, {
  String sessionId = 'gen-7',
  String channelId = 'studio',
  bool raised = true,
  DateTime? raisedAt,
  String role = 'listener',
  Map<String, Object?> extra = const {},
}) => {
  'serverSchemaVersion': 1,
  'serverId': 's',
  'channelId': channelId,
  'roomId': 'room',
  'sessionId': sessionId,
  'userId': uid,
  'role': role,
  'authorizationRevision': 1,
  'hostMuted': false,
  'serverMuted': false,
  'isMuted': true,
  'isHandRaised': raised,
  'handRaisedAt': raisedAt == null ? null : Timestamp.fromDate(raisedAt),
  'displayName': 'Name $uid',
  'photoUrl': null,
  'tokenAuthorityFingerprint': 'f' * 64,
  ...extra,
};

void main() {
  test(
    'the queue is the live generation\'s raised hands, oldest first',
    () async {
      final firestore = FakeFirebaseFirestore();
      final participants = firestore.collection('rooms/room/participants');
      await participants
          .doc('late')
          .set(_participant('late', raisedAt: DateTime(2026, 9, 25, 18, 5)));
      await participants
          .doc('early')
          .set(_participant('early', raisedAt: DateTime(2026, 9, 25, 18)));
      await participants
          .doc('lowered')
          .set(_participant('lowered', raised: false));
      await participants
          .doc('old')
          .set(
            _participant('old', sessionId: 'gen-6', raisedAt: DateTime(2026)),
          );
      await participants
          .doc('host')
          .set(_participant('host', role: 'host', raisedAt: DateTime(2026)));
      // A document that names somebody else under this id is refused.
      await participants
          .doc('forged')
          .set(_participant('someone-else', raisedAt: DateTime(2026)));
      // A guest is already on the stage: a hand left up (an older client let
      // a guest ask) is nothing an Approve could answer, so it never queues.
      await participants
          .doc('guest')
          .set(_participant('guest', role: 'guest', raisedAt: DateTime(2026)));
      final service = ServerService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'owner'),
        ),
      );
      final hands = await service
          .watchSessionHands(
            roomId: 'room',
            serverId: 's',
            channelId: 'studio',
            sessionId: 'gen-7',
          )
          .first;
      expect(hands.map((hand) => hand.userId), ['early', 'late']);
      expect(hands.first.displayName, 'Name early');
      expect(hands.first.raisedAt, DateTime(2026, 9, 25, 18));
      expect(hands.first.role, 'listener');
    },
  );

  test(
    'the staff roster maps each moderate-capable member to their role',
    () async {
      final firestore = FakeFirebaseFirestore();
      final members = firestore.collection('clubs/s/members');
      await members.doc('owner').set({'userId': 'owner', 'role': 'owner'});
      await members.doc('admin').set({'userId': 'admin', 'role': 'admin'});
      await members.doc('mod').set({'userId': 'mod', 'role': 'moderator'});
      await members.doc('plain').set({'userId': 'plain', 'role': 'member'});
      await members.doc('odd').set({'userId': 'odd', 'role': 'emperor'});
      final service = ServerService(
        firestore: firestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'mod')),
      );
      final roles = await service.watchSessionStaffRoles('s').first;
      expect(roles, {
        'owner': ServerMemberRole.owner,
        'admin': ServerMemberRole.admin,
        'mod': ServerMemberRole.moderator,
      });
    },
  );

  test(
    'the own document is read by uid and parsed without the decider',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .doc('rooms/room/participants/owner')
          .set(
            _participant(
              'owner',
              raised: false,
              extra: {
                'handDecision': 'declined',
                'handDecidedAt': Timestamp.fromDate(DateTime(2026, 9, 25, 19)),
                'handDecidedById': 'moderator-uid',
              },
            ),
          );
      final service = ServerService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'owner'),
        ),
      );
      final own = await service
          .watchOwnSessionParticipant(roomId: 'room', sessionId: 'gen-7')
          .first;
      expect(own, isNotNull);
      expect(own!.handDecision, ServerHandDecision.declined);
      expect(own.handDecidedAt, DateTime(2026, 9, 25, 19));
      expect(own.isHandRaised, isFalse);
      expect(own.tokenFingerprint, 'f' * 64);
      // Another generation's copy of the document is not this generation's.
      final stale = await service
          .watchOwnSessionParticipant(roomId: 'room', sessionId: 'gen-8')
          .first;
      expect(stale, isNull);
    },
  );

  test(
    'a decline sends the exact callable payload and checks its receipt',
    () async {
      final payloads = <(String, Map<String, Object?>)>[];
      var answer = <Object?, Object?>{
        'serverId': 's',
        'channelId': 'studio',
        'sessionId': 'gen-7',
        'participantId': 'kamil',
        'role': 'listener',
        'hostMuted': false,
        'serverMuted': false,
        'participantRevision': 1,
        'decision': 'declined',
        'changed': true,
      };
      final service = ServerService(
        call: (name, data) async {
          payloads.add((name, data));
          return answer;
        },
      );
      final result = await service.declineSessionHand(
        serverId: 's',
        channelId: 'studio',
        sessionId: 'gen-7',
        participantId: 'kamil',
        requestId: 'request-1',
      );
      expect(result.changed, isTrue);
      expect(result.decision, ServerHandDecision.declined);
      expect(payloads.single.$1, 'answerServerSessionHandV1');
      expect(payloads.single.$2, {
        'serverId': 's',
        'channelId': 'studio',
        'sessionId': 'gen-7',
        'participantId': 'kamil',
        'decision': 'declined',
        'requestId': 'request-1',
      });
      answer = {...answer, 'participantId': 'somebody-else'};
      await expectLater(
        service.declineSessionHand(
          serverId: 's',
          channelId: 'studio',
          sessionId: 'gen-7',
          participantId: 'kamil',
          requestId: 'request-2',
        ),
        throwsFormatException,
      );
    },
  );
}
