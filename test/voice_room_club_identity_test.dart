import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// `VoiceRoom.clubId` is the switch that decides whether a room renders
/// as a CLUB room (club banner, "Club Room" subtitle, teal identity,
/// lounge-aware leave) or a plain community room, so its resolution —
/// explicit field first, `club_lounge_` id prefix as the fallback for
/// lounge documents written before the field existed — is load-bearing
/// routing logic, not cosmetics.
void main() {
  late FakeFirebaseFirestore db;

  Future<VoiceRoom> roomFrom(
    String id,
    Map<String, dynamic> data,
  ) async {
    await db.collection('rooms').doc(id).set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'A room',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 0,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      ...data,
    });
    return VoiceRoom.fromFirestore(
      await db.collection('rooms').doc(id).get(),
    );
  }

  setUp(() => db = FakeFirebaseFirestore());

  test('an explicit clubId marks the room as a club room', () async {
    final room = await roomFrom('club_lounge_abc', {'clubId': 'abc'});
    expect(room.clubId, 'abc');
    expect(room.isClubRoom, isTrue);
  });

  test('a legacy lounge document without the field falls back to the '
      'club_lounge_ id prefix', () async {
    final room = await roomFrom('club_lounge_legacy-club', {});
    expect(room.clubId, 'legacy-club');
    expect(room.isClubRoom, isTrue);
  });

  test('an ordinary community room is NOT a club room', () async {
    final room = await roomFrom('plain-room-id', {});
    expect(room.clubId, isNull);
    expect(room.isClubRoom, isFalse);
  });

  test('a room whose name merely mentions a club is not a club room —'
      ' only the id prefix or the field count', () async {
    final room = await roomFrom('some-room', {'name': 'club_lounge_fake'});
    expect(room.isClubRoom, isFalse);
  });
}
