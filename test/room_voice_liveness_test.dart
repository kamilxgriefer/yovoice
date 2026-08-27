import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// THE LIVENESS TRANSITION, from the only client API that ever performed it.
///
/// `createLiveKitToken` (functions/livekit/token.js) refuses a voice token
/// unless the room document says `status == 'active' && isLive == true`, and
/// `RoomService.joinRoom` refuses to add a participant to a room whose
/// `isLive` is not true. So the room document has to move BEFORE anything
/// asks for audio — and for every room type, not only the two that happened
/// to be reachable from the Club overview.
///
/// These cases are deliberately written against API that predates the fix, so
/// the same file runs on both sides of it. Three of them fail on the old
/// implementation:
///
/// * a Club Lounge / Family Room member could not start voice at all — the
///   authority test knew only `hostId` and `membersCanStartVoice`, and a
///   lounge member holds neither;
/// * an already-live room was written to anyway, which both
///   `roomVoiceStartAllowed()` and `hostRoomUpdateAllowed()`'s start branch
///   refuse (`resource.data.isLive == false` is a precondition of each);
/// * a room whose deletion had begun could still be restarted.
///
/// The rest are regression guards for behaviour that was already right.
void main() {
  late FakeFirebaseFirestore db;

  RoomService serviceFor(String uid) => RoomService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: '$uid@yovoice.app'),
    ),
  );

  /// The 45-room production reality: 25 documents carry no
  /// `membersCanStartVoice` and 24 carry neither `roomType` nor
  /// `experience`. Nothing below is added unless a case is about it.
  Future<void> seedRoom(String id, Map<String, dynamic> data) {
    return db.collection('rooms').doc(id).set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'A room',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 0,
      'memberCount': 0,
      'isLive': false,
      'status': 'active',
      ...data,
    });
  }

  Future<Map<String, dynamic>> readRoom(String id) async =>
      (await db.collection('rooms').doc(id).get()).data()!;

  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final uid in ['host', 'member', 'relative', 'stranger']) {
      await db.collection('users').doc(uid).set({
        'displayName': uid,
        'photoUrl': null,
      });
    }
  });

  group('starting voice', () {
    test('a Family Room member opens the mics — the reported bug: no '
        'membersCanStartVoice, no roomType and no experience, and the caller '
        'is not the host', () async {
      // Exactly the shape of the reported room, minus the fields that
      // postdate it. `clubId` IS present: all three club_lounge_ rooms in
      // production carry it, and roomVoiceStartAllowed() reads the FIELD.
      await seedRoom('club_lounge_family_host', {
        'category': 'club',
        'visibility': 'private',
        'name': 'The Family Lounge',
        'clubId': 'family_host',
      });
      await db.collection('clubs').doc('family_host').set({
        'ownerId': 'host',
        'name': 'The Family',
        'status': 'active',
      });
      await db
          .collection('clubs')
          .doc('family_host')
          .collection('members')
          .doc('relative')
          .set({'userId': 'relative', 'role': 'member'});

      await serviceFor(
        'relative',
      ).startCommunityVoice('club_lounge_family_host');

      final room = await readRoom('club_lounge_family_host');
      expect(room['isLive'], isTrue, reason: 'voice must actually start');
      expect(room['participantCount'], 1);
      final participant = await db
          .collection('rooms')
          .doc('club_lounge_family_host')
          .collection('participants')
          .doc('relative')
          .get();
      expect(
        participant.exists,
        isTrue,
        reason:
            'the token function refuses a caller with no participant row, '
            'so the roster join is part of starting voice',
      );
      expect(participant.data(), containsPair('role', 'speaker'));
      expect(participant.data(), containsPair('isSpeaker', true));
      expect(participant.data(), containsPair('isMuted', false));
    });

    test('an already-live room is NOT written to again — both rule branches '
        'require isLive to be false before the transition', () async {
      final before = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
      await seedRoom('live-room', {
        'isLive': true,
        'participantCount': 1,
        'updatedAt': before,
      });
      await db
          .collection('rooms')
          .doc('live-room')
          .collection('participants')
          .doc('host')
          .set({
            'userId': 'host',
            'displayName': 'host',
            'role': 'host',
            'isMuted': false,
            'isSpeaker': true,
            'isHandRaised': false,
          });

      await serviceFor('host').startCommunityVoice('live-room');

      final room = await readRoom('live-room');
      expect(room['isLive'], isTrue);
      expect(
        room['updatedAt'],
        before,
        reason:
            'a re-asserted isLive:true is permission-denied on the server; '
            'entering a live room must perform no root write at all',
      );
      expect(room['participantCount'], 1);
    });

    test(
      'a room whose deletion has begun cannot be restarted, even by its host',
      () async {
        await seedRoom('dying-room', {
          'deletionInProgress': true,
          'roomType': 'community',
        });

        await expectLater(
          serviceFor('host').startCommunityVoice('dying-room'),
          throwsA(isA<StateError>()),
        );

        final room = await readRoom('dying-room');
        expect(
          room['isLive'],
          isFalse,
          reason:
              'hostRoomUpdateAllowed()s start branch does not read '
              'deletionInProgress, so the client must be the stricter one',
        );
      },
    );

    test('the write carries exactly the three keys the rules permit', () async {
      await seedRoom('ended-room', {
        'roomType': 'community',
        'endedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'membersCanStartVoice': false,
        'autoMuteNewUsers': true,
      });

      await serviceFor('host').startCommunityVoice('ended-room');

      final room = await readRoom('ended-room');
      expect(room['isLive'], isTrue);
      expect(
        room['endedAt'],
        isNull,
        reason: 'endedAt is cleared as part of the same permitted key set',
      );
      // Nothing else rode along. `affectedKeys().hasOnly([isLive, endedAt,
      // updatedAt])` is what makes an authorized start succeed; a counter or
      // a denormalized name in the same write turns it into a denial.
      expect(room['hostId'], 'host');
      expect(room['visibility'], 'public');
      expect(room['membersCanStartVoice'], isFalse);
      expect(room['autoMuteNewUsers'], isTrue);
      expect(room['status'], 'active');
    });

    test(
      'a legacy document with no type fields still starts for its host',
      () async {
        await seedRoom('legacy-room', {});
        await serviceFor('host').startCommunityVoice('legacy-room');
        expect((await readRoom('legacy-room'))['isLive'], isTrue);
      },
    );

    test('a room member starts voice when the host allowed it', () async {
      await seedRoom('open-room', {
        'roomType': 'community',
        'membersCanStartVoice': true,
      });
      await db
          .collection('rooms')
          .doc('open-room')
          .collection('roomMembers')
          .doc('member')
          .set({'userId': 'member', 'role': 'member'});

      await serviceFor('member').startCommunityVoice('open-room');

      expect((await readRoom('open-room'))['isLive'], isTrue);
    });

    test(
      'someone with no membership cannot start voice, and nothing is written',
      () async {
        await seedRoom('open-room', {
          'roomType': 'community',
          'membersCanStartVoice': true,
        });

        await expectLater(
          serviceFor('stranger').startCommunityVoice('open-room'),
          throwsA(isA<StateError>()),
        );
        expect((await readRoom('open-room'))['isLive'], isFalse);
      },
    );

    test(
      'a lounge member of a Club that is being deleted cannot start voice',
      () async {
        await seedRoom('club_lounge_dying', {
          'visibility': 'private',
          'clubId': 'dying',
        });
        await db.collection('clubs').doc('dying').set({
          'ownerId': 'host',
          'status': 'active',
          'deletionInProgress': true,
        });
        await db
            .collection('clubs')
            .doc('dying')
            .collection('members')
            .doc('relative')
            .set({'userId': 'relative'});

        await expectLater(
          serviceFor('relative').startCommunityVoice('club_lounge_dying'),
          throwsA(isA<StateError>()),
        );
        expect((await readRoom('club_lounge_dying'))['isLive'], isFalse);
      },
    );

    test(
      'a banned lounge member keeps the row and loses the authority',
      () async {
        await seedRoom('club_lounge_family_host', {
          'visibility': 'private',
          'clubId': 'family_host',
        });
        await db.collection('clubs').doc('family_host').set({
          'ownerId': 'host',
          'status': 'active',
        });
        await db
            .collection('clubs')
            .doc('family_host')
            .collection('members')
            .doc('relative')
            .set({'userId': 'relative', 'banned': true});

        await expectLater(
          serviceFor('relative').startCommunityVoice('club_lounge_family_host'),
          throwsA(isA<StateError>()),
        );
        expect((await readRoom('club_lounge_family_host'))['isLive'], isFalse);
      },
    );

    test('a persistent BROADCAST room starts for its host too — the two '
        'experiences share the lifecycle, not the screen', () async {
      await seedRoom('broadcast-room', {
        'roomType': 'community',
        'experience': 'broadcast',
      });

      await serviceFor('host').startCommunityVoice('broadcast-room');

      final room = await readRoom('broadcast-room');
      expect(room['isLive'], isTrue);
      expect(room['experience'], 'broadcast');
    });

    test('a lounge whose clubId FIELD is absent refuses a member, because the '
        'rule reads the field and not the club_lounge_ id prefix', () async {
      // The `clubId` fallback in VoiceRoom.fromFirestore is for identity
      // and routing. roomVoiceStartAllowed() gates on
      // resource.data.get('clubId',''), so a fieldless lounge cannot
      // satisfy the Club branch on the server for anybody. Offering the
      // control anyway would auto-write straight into a denial.
      await seedRoom('club_lounge_fieldless', {'visibility': 'private'});
      await db.collection('clubs').doc('fieldless').set({
        'ownerId': 'host',
        'status': 'active',
      });
      await db
          .collection('clubs')
          .doc('fieldless')
          .collection('members')
          .doc('relative')
          .set({'userId': 'relative', 'role': 'member'});

      expect(
        await serviceFor('relative').resolveVoiceStartAuthority(
          await serviceFor('relative').getRoom('club_lounge_fieldless'),
        ),
        RoomVoiceStartAuthority.none,
      );
      await expectLater(
        serviceFor('relative').startCommunityVoice('club_lounge_fieldless'),
        throwsA(isA<StateError>()),
      );
      expect((await readRoom('club_lounge_fieldless'))['isLive'], isFalse);
    });

    test(
      'the same fieldless lounge still starts for its HOST — the host branch '
      'never reads clubId',
      () async {
        await seedRoom('club_lounge_fieldless', {'visibility': 'private'});
        await serviceFor('host').startCommunityVoice('club_lounge_fieldless');
        expect((await readRoom('club_lounge_fieldless'))['isLive'], isTrue);
      },
    );

    test('a banned account is offered nothing, on every branch', () async {
      await db.collection('users').doc('host').set({
        'displayName': 'host',
        'photoUrl': null,
        'banned': true,
      });
      await seedRoom('room-1', {'roomType': 'community'});

      final service = serviceFor('host');
      expect(
        await service.resolveVoiceStartAuthority(
          await service.getRoom('room-1'),
        ),
        RoomVoiceStartAuthority.none,
        reason:
            'hostRoomUpdateAllowed() opens with isActiveAccount(); offering '
            'a control the server refuses is the defect class this mirrors '
            'against',
      );
      await expectLater(
        service.startCommunityVoice('room-1'),
        throwsA(isA<StateError>()),
      );
      expect((await readRoom('room-1'))['isLive'], isFalse);
    });

    test('a disabled account is refused the same way', () async {
      await db.collection('users').doc('host').set({
        'displayName': 'host',
        'photoUrl': null,
        'disabled': true,
      });
      await seedRoom('room-1', {'roomType': 'community'});

      await expectLater(
        serviceFor('host').startCommunityVoice('room-1'),
        throwsA(isA<StateError>()),
      );
      expect((await readRoom('room-1'))['isLive'], isFalse);
    });

    test('an account with no profile document is refused', () async {
      await seedRoom('room-1', {'hostId': 'ghost', 'roomType': 'community'});
      await expectLater(
        serviceFor('ghost').startCommunityVoice('room-1'),
        throwsA(isA<StateError>()),
      );
      expect((await readRoom('room-1'))['isLive'], isFalse);
    });

    test('a closed room is refused before anything is written', () async {
      await seedRoom('closed-room', {'status': 'closed'});

      await expectLater(
        serviceFor('host').startCommunityVoice('closed-room'),
        throwsA(isA<StateError>()),
      );
      expect((await readRoom('closed-room'))['isLive'], isFalse);
    });
  });
}
