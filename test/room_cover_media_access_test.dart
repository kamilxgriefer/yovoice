import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

const _path = 'room_images/room-1/viewer_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';

const _room = VoiceRoom(
  id: 'room-1',
  hostId: 'viewer',
  hostName: 'Viewer',
  hostPhotoUrl: null,
  name: 'Room',
  description: '',
  category: 'talk',
  visibility: 'private',
  language: 'English',
  maxParticipants: 8,
  participantCount: 1,
  memberCount: 1,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  coverStoragePath: _path,
  coverGeneration: '42',
  coverContentType: 'image/jpeg',
  coverSize: 4096,
);

Map<Object?, Object?> _grant({String? url}) => <Object?, Object?>{
  'schemaVersion': 1,
  'url':
      url ??
      'https://storage.googleapis.com/test-bucket/$_path?generation=42&sig=x',
  'expiresAtMillis': DateTime.now().millisecondsSinceEpoch + 90000,
  'coverGeneration': '42',
  'coverContentType': 'image/jpeg',
  'coverSize': 4096,
};

RoomService _service(RoomCoverAccessInvoker invoker) => RoomService(
  firestore: FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'viewer')),
  coverAccessInvoker: invoker,
);

void main() {
  setUp(RoomService.clearAllCoverAccessCaches);
  tearDown(RoomService.clearAllCoverAccessCaches);

  test('accepts and globally caches an exact generation-bound grant', () async {
    var calls = 0;
    final service = _service((request) async {
      calls++;
      expect(request, <String, Object?>{'roomId': 'room-1'});
      return _grant();
    });

    final first = await service.resolveCoverUri(_room);
    final second = await service.resolveCoverUri(_room);
    expect(first, second);
    expect(calls, 1);

    RoomService.clearAllCoverAccessCaches();
    await service.resolveCoverUri(_room);
    expect(calls, 2);
  });

  test('rejects a signed grant on a non-default HTTPS port', () async {
    final service = _service(
      (_) async => _grant(
        url:
            'https://storage.googleapis.com:444/test-bucket/$_path'
            '?generation=42&sig=x',
      ),
    );

    await expectLater(
      service.resolveCoverUri(_room),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects the wrong object path or generation', () async {
    for (final url in <String>[
      'https://storage.googleapis.com/test-bucket/room_images/other/x.jpg'
          '?generation=42&sig=x',
      'https://storage.googleapis.com/test-bucket/$_path'
          '?generation=999&sig=x',
      'https://tracker.example/$_path?generation=42',
    ]) {
      final service = _service((_) async => _grant(url: url));
      await expectLater(
        service.resolveCoverUri(_room),
        throwsA(isA<FormatException>()),
      );
      RoomService.clearAllCoverAccessCaches();
    }
  });
}
