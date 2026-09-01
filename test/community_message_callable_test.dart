import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

void main() {
  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: 'member',
      email: 'member@yovoice.app',
      isEmailVerified: true,
    ),
  );

  test(
    'room chat uses the callable payload and never writes directly',
    () async {
      final firestore = FakeFirebaseFirestore();
      Map<String, Object?>? captured;
      final service = RoomService(
        firestore: firestore,
        auth: signedInAuth(),
        requestIdFactory: () => 'room-request-0001',
        roomMessageSendInvoker: (request) async {
          captured = request;
          return <Object?, Object?>{'messageId': 'rm_1', 'roomId': 'room-1'};
        },
      );

      await service.sendRoomMessage(roomId: 'room-1', text: '  hello  ');

      expect(captured, <String, Object?>{
        'requestId': 'room-request-0001',
        'roomId': 'room-1',
        'text': 'hello',
      });
      expect(
        (await firestore.collection('rooms/room-1/messages').get()).size,
        0,
      );
    },
  );

  test(
    'club chat uses the callable payload and never writes directly',
    () async {
      final firestore = FakeFirebaseFirestore();
      Map<String, Object?>? captured;
      final service = ClubChatService(
        firestore: firestore,
        auth: signedInAuth(),
        requestIdFactory: () => 'club-request-0001',
        messageSendInvoker: (request) async {
          captured = request;
          return <Object?, Object?>{
            'clubId': 'club-1',
            'channelId': 'general',
            'messageId': 'cm_1',
          };
        },
      );

      await service.sendTextMessage(
        clubId: 'club-1',
        channelId: 'general',
        text: '  hello club  ',
      );

      expect(captured, <String, Object?>{
        'clubId': 'club-1',
        'channelId': 'general',
        'requestId': 'club-request-0001',
        'text': 'hello club',
      });
      expect(
        (await firestore
                .collection('clubs/club-1/channels/general/messages')
                .get())
            .size,
        0,
      );
    },
  );

  test('local validation rejects blank and oversized chat payloads', () async {
    var calls = 0;
    final rooms = RoomService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      requestIdFactory: () => 'room-request-0002',
      roomMessageSendInvoker: (request) async {
        calls += 1;
        return <Object?, Object?>{};
      },
    );
    final clubs = ClubChatService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      requestIdFactory: () => 'club-request-0002',
      messageSendInvoker: (request) async {
        calls += 1;
        return <Object?, Object?>{};
      },
    );

    await rooms.sendRoomMessage(roomId: 'room', text: '   ');
    await clubs.sendTextMessage(clubId: 'club', channelId: 'general', text: '');
    expect(calls, 0);
    await expectLater(
      rooms.sendRoomMessage(
        roomId: 'room',
        text: List<String>.filled(501, 'x').join(),
      ),
      throwsArgumentError,
    );
    await expectLater(
      clubs.sendTextMessage(
        clubId: 'club',
        channelId: 'general',
        text: List<String>.filled(2001, 'x').join(),
      ),
      throwsArgumentError,
    );
  });
}
