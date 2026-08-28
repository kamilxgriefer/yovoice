import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';

const _roomId = 'room-cover-reference';
const _managedUrl =
    'https://firebasestorage.googleapis.com/v0/b/'
    'yovoice-ec54a.firebasestorage.app/o/'
    'room_images%2Froom-cover-reference%2Fhost-uid_123.jpg'
    '?alt=media&token=test';
const _clubId = 'creator-club';
const _clubRoomId = 'club_lounge_creator-club';
const _managedClubAvatar =
    'https://firebasestorage.googleapis.com/v0/b/'
    'yovoice-ec54a.firebasestorage.app/o/'
    'clubs%2Fowner-uid%2Fcreator-club%2Favatar'
    '?alt=media&generation=123&token=test';

Future<VoiceRoom> _roomWith(
  Object? imageUrl, {
  String roomId = _roomId,
  Map<String, Object?> extra = const <String, Object?>{},
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('rooms').doc(roomId).set({
    'hostId': 'host-uid',
    'hostName': 'Host',
    'name': 'Safe room',
    'description': '',
    'category': 'talk',
    'visibility': 'public',
    'language': 'English',
    'maxParticipants': 25,
    'participantCount': 0,
    'memberCount': 1,
    'isLive': false,
    'roomType': 'community',
    'status': 'active',
    'imageUrl': imageUrl,
    'approvalRequired': false,
    'slowModeSeconds': 0,
    'autoMuteNewUsers': false,
    'membersCanStartVoice': true,
    ...extra,
  });
  return VoiceRoom.fromFirestore(
    await firestore.collection('rooms').doc(roomId).get(),
  );
}

void main() {
  test('accepts this room exact managed Firebase Storage cover', () async {
    expect((await _roomWith(_managedUrl)).imageUrl, _managedUrl);
  });

  test('malformed imageUrl type cannot poison a shared room stream', () async {
    expect((await _roomWith(<String, Object?>{})).imageUrl, isNull);
  });

  test('accepts the canonical managed avatar for its Club Lounge', () async {
    final room = await _roomWith(
      _managedClubAvatar,
      roomId: _clubRoomId,
      extra: const {'clubId': _clubId, 'roomKind': 'clubLounge'},
    );
    expect(room.imageUrl, _managedClubAvatar);
  });

  test('Club Lounge cannot render another Club managed avatar', () async {
    final room = await _roomWith(
      _managedClubAvatar.replaceFirst(
        'creator-club%2Favatar',
        'different-club%2Favatar',
      ),
      roomId: _clubRoomId,
      extra: const {'clubId': _clubId, 'roomKind': 'clubLounge'},
    );
    expect(room.imageUrl, isNull);
  });

  test(
    'external and sibling-room cover URLs never trigger image fetches',
    () async {
      expect(
        (await _roomWith('https://tracker.example/cover.jpg')).imageUrl,
        isNull,
      );
      expect(
        (await _roomWith(
          _managedUrl.replaceFirst(_roomId, 'different-room'),
        )).imageUrl,
        isNull,
      );
    },
  );

  test('encoded path confusion and oversized pointers fail closed', () async {
    expect(
      (await _roomWith(
        _managedUrl.replaceFirst('room_images%2F', 'room_images%2F..%2F'),
      )).imageUrl,
      isNull,
    );
    expect(
      (await _roomWith('https://${List.filled(2050, 'a').join()}')).imageUrl,
      isNull,
    );
  });
}
