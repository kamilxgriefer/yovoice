import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

import 'helpers/room_creation_test_double.dart';

void main() {
  const uid = 'room-creator';
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'creator@example.test'),
    );
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Canonical Creator',
    });
  });

  test(
    'createRoom sends the exact callable contract and reads server result',
    () async {
      Map<String, Object?>? captured;
      final service = RoomService(
        firestore: firestore,
        auth: auth,
        requestIdFactory: () => 'room-create-0001',
        roomCreateInvoker: (request) async {
          captured = Map<String, Object?>.of(request);
          return createRoomForTest(
            firestore: firestore,
            userId: uid,
            request: request,
          );
        },
      );

      final room = await service.createRoom(
        name: '  Secure room  ',
        description: '  Exact contract  ',
        category: 'talk',
        visibility: 'private',
        language: 'English',
        maxParticipants: 25,
        roomType: RoomType.community,
        targetAudience: TargetAudience.professionals,
        topicTags: const ['security'],
        roomGuidelines: 'Be kind',
        conversationStyle: ConversationStyle.focused,
        newcomerFriendly: true,
      );

      expect(room.hostId, uid);
      expect(room.hostName, 'Canonical Creator');
      expect(room.hostPhotoUrl, isNull);
      expect(captured?.keys.toSet(), {
        'requestId',
        'name',
        'description',
        'category',
        'visibility',
        'language',
        'maxParticipants',
        'roomType',
        'targetAudience',
        'topicTags',
        'roomGuidelines',
        'conversationStyle',
        'newcomerFriendly',
        'showFormat',
        'experience',
        'topic',
        'audienceCanSpeak',
        'handRaisingEnabled',
      });
      expect(captured?['requestId'], 'room-create-0001');
      expect(captured?['name'], 'Secure room');
      expect(captured?['description'], 'Exact contract');
      expect(captured?['showFormat'], isNull);
      final owner = await firestore
          .collection('rooms')
          .doc(room.id)
          .collection('roomMembers')
          .doc(uid)
          .get();
      expect(owner.data(), containsPair('role', 'owner'));
      expect(owner.data(), containsPair('photoUrl', null));
    },
  );

  test('caller can retain one request id across an ambiguous retry', () async {
    var calls = 0;
    final requestIds = <Object?>[];
    final service = RoomService(
      firestore: firestore,
      auth: auth,
      requestIdFactory: () => 'room-create-retry',
      roomCreateInvoker: (request) async {
        calls += 1;
        requestIds.add(request['requestId']);
        final result = await createRoomForTest(
          firestore: firestore,
          userId: uid,
          request: request,
        );
        if (calls == 1) throw StateError('acknowledgement lost');
        return result;
      },
    );
    final requestId = service.newRoomCreationRequestId();

    Future<VoiceRoom> create() => service.createRoom(
      name: 'Retry room',
      description: '',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 25,
      roomType: RoomType.temporary,
      requestId: requestId,
    );

    await expectLater(create(), throwsStateError);
    final recovered = await create();
    expect(recovered.name, 'Retry room');
    expect(requestIds, ['room-create-retry', 'room-create-retry']);
    expect((await firestore.collection('rooms').get()).docs, hasLength(1));
  });

  test('generated request ids are URL/document safe and distinct', () {
    final service = RoomService(firestore: firestore, auth: auth);
    final first = service.newRoomCreationRequestId();
    final second = service.newRoomCreationRequestId();
    expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{8,128}$')));
    expect(second, matches(RegExp(r'^[A-Za-z0-9_-]{8,128}$')));
    expect(second, isNot(first));
  });

  test('malformed callable response fails closed', () async {
    final service = RoomService(
      firestore: firestore,
      auth: auth,
      roomCreateInvoker: (_) async => <Object?, Object?>{
        'schemaVersion': 1,
        'roomId': '../foreign-room',
      },
    );
    await expectLater(
      service.createRoom(
        name: 'Closed boundary',
        description: '',
        category: 'talk',
        visibility: 'public',
        language: 'English',
        maxParticipants: 25,
        roomType: RoomType.community,
      ),
      throwsFormatException,
    );
  });

  test('invalid local input never invokes the callable', () async {
    var calls = 0;
    final service = RoomService(
      firestore: firestore,
      auth: auth,
      roomCreateInvoker: (_) async {
        calls += 1;
        return <Object?, Object?>{};
      },
    );
    await expectLater(
      service.createRoom(
        name: 'ab',
        description: '',
        category: 'talk',
        visibility: 'public',
        language: 'English',
        maxParticipants: 25,
        roomType: RoomType.community,
        experience: RoomExperience.community,
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test(
    'voice start retains request and session ids after a lost ack',
    () async {
      var calls = 0;
      var factoryCalls = 0;
      final payloads = <Map<String, Object?>>[];
      final service = RoomService(
        firestore: firestore,
        auth: auth,
        requestIdFactory: () =>
            factoryCalls++ == 0 ? 'voice-request-0001' : 'voice-session-0001',
        roomVoiceStartInvoker: (request) async {
          calls += 1;
          payloads.add(Map<String, Object?>.of(request));
          final response = <Object?, Object?>{
            'schemaVersion': 1,
            'started': true,
            'roomId': request['roomId'],
            'sessionId': request['sessionId'],
          };
          if (calls == 1) throw StateError('acknowledgement lost');
          return response;
        },
      );

      await expectLater(service.startRoomVoice('voice-room'), throwsStateError);
      await service.startRoomVoice('voice-room');
      expect(calls, 2);
      expect(payloads[1], payloads[0]);
      expect(payloads[0].keys.toSet(), {'requestId', 'roomId', 'sessionId'});
    },
  );
}
