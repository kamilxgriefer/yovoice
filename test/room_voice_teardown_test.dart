import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// A room must not be left live with nobody in it.
///
/// The server only cleans that up for Club lounges: `executeLeaveRoom`
/// (functions/rooms/participants.js) drops `isLive` at zero participants when
/// `roomKind == 'clubLounge'` and for no other room. Now that an ordinary
/// persistent room can be started from the client, the matching close has to
/// exist too — and `endRoomVoiceSelf` is host-only, so the host leaving last
/// is the only case the client can close by itself. Everything else must fall
/// through to the ordinary `leaveRoomSelf` path unchanged.
void main() {
  late FakeFirebaseFirestore db;

  RoomService serviceFor(String uid) => RoomService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: '$uid@yovoice.app'),
    ),
  );

  Future<void> seedRoom(String id, Map<String, dynamic> data) {
    return db.collection('rooms').doc(id).set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'A room',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'memberCount': 0,
      'isLive': true,
      'status': 'active',
      'roomType': 'community',
      ...data,
    });
  }

  setUp(() => db = FakeFirebaseFirestore());

  test('the host leaving last closes the session behind them', () async {
    await seedRoom('room-1', {'participantCount': 1});
    expect(await serviceFor('host').shouldEndVoiceOnLeaving('room-1'), isTrue);
  });

  test(
    'a room whose counter never existed is closed too — that IS the stuck '
    'empty-live room',
    () async {
      await seedRoom('legacy-room', {});
      expect(
        await serviceFor('host').shouldEndVoiceOnLeaving('legacy-room'),
        isTrue,
      );
    },
  );

  test('the host stepping out of a busy room closes nothing', () async {
    await seedRoom('room-1', {'participantCount': 4});
    expect(await serviceFor('host').shouldEndVoiceOnLeaving('room-1'), isFalse);
  });

  test('a participant who is not the host closes nothing', () async {
    await seedRoom('room-1', {'participantCount': 1});
    expect(
      await serviceFor('someone-else').shouldEndVoiceOnLeaving('room-1'),
      isFalse,
    );
  });

  test(
    'a Club lounge is left to the server, which tears it down atomically with '
    'the participant delete',
    () async {
      await seedRoom('club_lounge_family_host', {
        'participantCount': 1,
        'roomKind': 'clubLounge',
        'clubId': 'family_host',
      });
      expect(
        await serviceFor(
          'host',
        ).shouldEndVoiceOnLeaving('club_lounge_family_host'),
        isFalse,
      );
    },
  );

  test(
    'a legacy lounge with neither roomKind nor clubId is still recognised by '
    'its document id',
    () async {
      await seedRoom('club_lounge_legacy', {'participantCount': 1});
      expect(
        await serviceFor('host').shouldEndVoiceOnLeaving('club_lounge_legacy'),
        isFalse,
      );
    },
  );

  test(
    'a temporary room keeps its existing host-ends-for-everyone path',
    () async {
      await seedRoom('temp-room', {
        'participantCount': 1,
        'roomType': 'temporary',
      });
      expect(
        await serviceFor('host').shouldEndVoiceOnLeaving('temp-room'),
        isFalse,
      );
    },
  );

  test('a room that is not live has no session to close', () async {
    await seedRoom('room-1', {'participantCount': 1, 'isLive': false});
    expect(await serviceFor('host').shouldEndVoiceOnLeaving('room-1'), isFalse);
  });

  test('a room being deleted is left entirely to the server', () async {
    await seedRoom('room-1', {
      'participantCount': 1,
      'deletionInProgress': true,
    });
    expect(await serviceFor('host').shouldEndVoiceOnLeaving('room-1'), isFalse);
  });

  test('a suspended room is not touched', () async {
    await seedRoom('room-1', {'participantCount': 1, 'status': 'suspended'});
    expect(await serviceFor('host').shouldEndVoiceOnLeaving('room-1'), isFalse);
  });

  test(
    'a missing room answers false rather than throwing on the way out',
    () async {
      expect(await serviceFor('host').shouldEndVoiceOnLeaving('nope'), isFalse);
    },
  );
}
