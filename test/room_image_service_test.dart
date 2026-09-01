import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/features/rooms/data/services/room_image_service.dart';

void main() {
  test(
    'room cover upload pins JPEG path, MIME and exact cropped bytes',
    () async {
      final storage = MockFirebaseStorage();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'host'),
      );
      final cropped = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 4)),
      );

      final serviceWithLease = RoomImageService(
        storage: storage,
        auth: auth,
        reservationInvoker: _reservationFor,
        generationReader: (reference, snapshot) async => '1',
      );
      final upload = await serviceWithLease.uploadRoomCover(
        roomId: 'room-1',
        bytes: cropped,
      );

      expect(upload.storagePath, isNotEmpty);
      expect(upload.objectGeneration, matches(RegExp(r'^[0-9]+$')));
      final listing = await storage.ref('room_images/room-1').listAll();
      expect(listing.items, hasLength(1));
      final uploaded = listing.items.single;
      expect(uploaded.fullPath, startsWith('room_images/room-1/host_'));
      expect(uploaded.name, endsWith('.jpg'));
      expect((await uploaded.getMetadata()).contentType, 'image/jpeg');
      expect(await uploaded.getData(), cropped);

      await serviceWithLease.deleteManagedRoomCover(
        roomId: 'room-1',
        url: 'https://example.invalid/clubs/club-1/banner.jpg',
      );
      expect(
        (await storage.ref('room_images/room-1').listAll()).items,
        hasLength(1),
        reason: 'a Club/external image must never be deleted as room media',
      );
      await serviceWithLease.deleteManagedRoomCoverPath(
        roomId: 'room-1',
        storagePath: upload.storagePath,
      );
      expect(
        (await storage.ref('room_images/room-1').listAll()).items,
        isEmpty,
      );

      final siblingUpload = await serviceWithLease.uploadRoomCover(
        roomId: 'room-2',
        bytes: cropped,
      );
      await serviceWithLease.deleteManagedRoomCover(
        roomId: 'room-1',
        url:
            'https://example.invalid/${siblingUpload.storagePath}'
            '?note=room_images/room-1/forged.jpg',
      );
      expect(
        (await storage.ref('room_images/room-2').listAll()).items,
        hasLength(1),
        reason: 'query text cannot turn a sibling object into this room media',
      );
    },
  );

  test(
    'room cover upload rejects a signed-out caller before Storage',
    () async {
      final storage = MockFirebaseStorage();
      final service = RoomImageService(
        storage: storage,
        auth: MockFirebaseAuth(signedIn: false),
      );

      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      await expectLater(
        service.uploadRoomCover(roomId: 'room-1', bytes: jpeg),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'You must be signed in to upload a room image.',
          ),
        ),
      );
      expect(
        (await storage.ref('room_images/room-1').listAll()).items,
        isEmpty,
      );
    },
  );

  test(
    'room cover upload rejects bytes that are not an encoded JPEG',
    () async {
      final storage = MockFirebaseStorage();
      final service = RoomImageService(
        storage: storage,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'host')),
      );

      expect(
        () => service.uploadRoomCover(
          roomId: 'room-1',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The processed room cover must be a JPEG image.',
          ),
        ),
      );
      expect(
        (await storage.ref('room_images/room-1').listAll()).items,
        isEmpty,
      );
    },
  );

  test('room cover upload rejects empty and over-budget payloads', () {
    final storage = MockFirebaseStorage();
    final service = RoomImageService(
      storage: storage,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'host')),
    );

    for (final bytes in <Uint8List>[
      Uint8List(0),
      Uint8List(RoomImageService.maxRoomCoverBytes + 1),
    ]) {
      expect(
        () => service.uploadRoomCover(roomId: 'room-1', bytes: bytes),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The processed room cover must be smaller than 8 MB.',
          ),
        ),
      );
    }
  });
}

Future<Map<Object?, Object?>> _reservationFor(
  Map<String, Object> request,
) async {
  final roomId = request['roomId']! as String;
  final contentType = request['contentType']! as String;
  final size = request['size']! as int;
  return <Object?, Object?>{
    'schemaVersion': 1,
    'reservationId': 'b' * 40,
    'storagePath': 'room_images/$roomId/host_${'a' * 32}.jpg',
    'contentType': contentType,
    'size': size,
    'expiresAtMillis': DateTime.now().millisecondsSinceEpoch + 60000,
  };
}
