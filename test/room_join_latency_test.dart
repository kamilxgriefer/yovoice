import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_token_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';

/// The shape a canonical room cover must have for `VoiceRoom.fromFirestore`
/// to treat it as one; anything else parses as "no cover" and the grant
/// callable is never reached at all.
const _coverPath =
    'room_images/room-1/host_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';

Map<String, Object?> _roomData({
  bool isLive = true,
  int participantCount = 3,
  String hostId = 'host',
  bool withCover = true,
}) => <String, Object?>{
  'hostId': hostId,
  'hostName': 'Host',
  'name': 'Room',
  'description': '',
  'category': 'talk',
  'visibility': 'public',
  'language': 'English',
  'participantCount': participantCount,
  'memberCount': 0,
  'isLive': isLive,
  'roomType': 'community',
  'status': 'active',
  'experience': 'community',
  'approvalRequired': false,
  'slowModeSeconds': 0,
  'autoMuteNewUsers': false,
  'membersCanStartVoice': true,
  if (withCover) ...<String, Object?>{
    'coverStoragePath': _coverPath,
    'coverGeneration': '42',
    'coverContentType': 'image/jpeg',
    'coverSize': 4096,
  },
};

Map<Object?, Object?> _grant() => <Object?, Object?>{
  'schemaVersion': 1,
  'url': 'https://storage.googleapis.com/bucket/$_coverPath?generation=42',
  'expiresAtMillis': DateTime.now().millisecondsSinceEpoch + 300000,
  'coverGeneration': '42',
  'coverContentType': 'image/jpeg',
  'coverSize': 4096,
};

VoiceRoom _entryRoom({String? imageUrl}) => VoiceRoom(
  id: 'room-1',
  hostId: 'host',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: 'Room',
  description: '',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: null,
  participantCount: 3,
  memberCount: 0,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: imageUrl,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  coverStoragePath: _coverPath,
  coverGeneration: '42',
  coverContentType: 'image/jpeg',
  coverSize: 4096,
);

void main() {
  setUp(RoomService.clearAllCoverAccessCaches);
  tearDown(RoomService.clearAllCoverAccessCaches);

  group('cover grants leave the join await chain', () {
    test('a state-only room read never waits for the cover callable', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('rooms').doc('room-1').set(_roomData());
      final released = Completer<void>();
      var calls = 0;
      final rooms = RoomService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'member'),
        ),
        coverAccessInvoker: (_) async {
          calls += 1;
          await released.future;
          return _grant();
        },
      );

      // The grant is stalled — a cold `getRoomCoverMediaAccess` instance is
      // exactly this. The state read must still answer.
      final room = await rooms
          .getRoom('room-1', resolveCover: false)
          .timeout(const Duration(seconds: 5));

      expect(room.isLive, isTrue);
      expect(
        room.imageUrl,
        isNull,
        reason: 'An unresolved cover is the existing gradient state.',
      );
      expect(calls, 1, reason: 'The grant was started, just not waited on.');

      // And the warm-up is what the room screen then finds in the cache: one
      // callable serves both reads.
      released.complete();
      final painted = await rooms.getRoom('room-1');
      expect(painted.imageUrl, contains('storage.googleapis.com'));
      expect(calls, 1);
    });

    test(
      'a resolved cover is still resolved for callers that paint it',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('rooms').doc('room-1').set(_roomData());
        final rooms = RoomService(
          firestore: firestore,
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'member'),
          ),
          coverAccessInvoker: (_) async => _grant(),
        );

        final room = await rooms.getRoom('room-1');
        expect(room.imageUrl, contains('generation=42'));
      },
    );

    test(
      'entry carries the cover it already had rather than blanking it',
      () async {
        final coordinator = RoomVoiceEntryCoordinator(
          readRoom: (_) async => _entryRoom(),
          resolveAuthority: (_) async => RoomVoiceStartAuthority.host,
          startVoice: (_) async {},
          joinRoom: (_, {startMuted = false}) async => _entryRoom(),
        );

        final entry = await coordinator.enter(
          _entryRoom(
            imageUrl: 'https://storage.googleapis.com/bucket/cover.jpg',
          ),
        );

        expect(entry.outcome, RoomVoiceEntryOutcome.live);
        expect(
          entry.room.imageUrl,
          'https://storage.googleapis.com/bucket/cover.jpg',
          reason:
              'Skipping the grant on the entry path must not blank an image the '
              'screen was already painting.',
        );
      },
    );

    test(
      'a cover replaced between reads is never painted from the old URL',
      () async {
        final replaced = _entryRoom().withResolvedImageUrl(null);
        final coordinator = RoomVoiceEntryCoordinator(
          // Same room, new cover generation: the carried URL no longer
          // describes this object.
          readRoom: (_) async => VoiceRoom(
            id: replaced.id,
            hostId: replaced.hostId,
            hostName: replaced.hostName,
            hostPhotoUrl: null,
            name: replaced.name,
            description: replaced.description,
            category: replaced.category,
            visibility: replaced.visibility,
            language: replaced.language,
            maxParticipants: null,
            participantCount: replaced.participantCount,
            memberCount: replaced.memberCount,
            isLive: true,
            roomType: replaced.roomType,
            status: replaced.status,
            imageUrl: null,
            approvalRequired: false,
            slowModeSeconds: 0,
            autoMuteNewUsers: false,
            membersCanStartVoice: true,
            createdAt: null,
            updatedAt: null,
            coverStoragePath: _coverPath,
            coverGeneration: '99',
            coverContentType: 'image/jpeg',
            coverSize: 4096,
          ),
          resolveAuthority: (_) async => RoomVoiceStartAuthority.host,
          startVoice: (_) async {},
          joinRoom: (_, {startMuted = false}) async => replaced,
        );

        final entry = await coordinator.enter(
          _entryRoom(imageUrl: 'https://storage.googleapis.com/bucket/old.jpg'),
        );

        expect(entry.room.imageUrl, isNull);
      },
    );
  });

  group('the join itself', () {
    late FakeFirebaseFirestore firestore;
    late RoomService rooms;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      rooms = RoomService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'member'),
        ),
        coverAccessInvoker: (_) async => _grant(),
      );
      await firestore.collection('users').doc('member').set(<String, Object?>{
        'displayName': 'Member',
      });
      await firestore
          .collection('rooms')
          .doc('room-1')
          .set(_roomData(withCover: false));
    });

    test('answers from the document the transaction read', () async {
      final joined = await rooms.joinRoom('room-1');

      expect(
        joined.participantCount,
        4,
        reason:
            'The room comes back from the transaction with the roster write '
            'applied, not from a second read of what we just wrote.',
      );
      final stored = await firestore.collection('rooms').doc('room-1').get();
      expect(stored.data()?['participantCount'], 4);
    });

    test('re-entry reports the roster it did not change', () async {
      await rooms.joinRoom('room-1');
      final again = await rooms.joinRoom('room-1');

      expect(again.participantCount, 4);
      final stored = await firestore.collection('rooms').doc('room-1').get();
      expect(stored.data()?['participantCount'], 4);
    });

    test('a profile without a display name still refuses the join', () async {
      await firestore.collection('users').doc('member').set(<String, Object?>{
        'displayName': '  ',
      });

      await expectLater(rooms.joinRoom('room-1'), throwsStateError);
      final participant = await firestore
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('member')
          .get();
      expect(
        participant.exists,
        isFalse,
        reason:
            'Overlapping the profile read with the transaction must not let a '
            'nameless roster row through.',
      );
    });

    test('a dormant room reads the caller profile once, not twice', () async {
      await firestore.collection('rooms').doc('room-1').update(
        <String, Object?>{'hostId': 'member'},
      );
      final room = await rooms.getRoom('room-1');

      final authority = await rooms.resolveVoiceStartAuthority(room);
      expect(authority, RoomVoiceStartAuthority.host);

      // Between the authority check and the join, the stored name changes.
      // The join reuses the memo, so it writes the name it read — the same
      // failure class as the millisecond gap this replaced, just wider, and
      // the rules' byte-for-byte binding turns it into the existing
      // "the room changed while you were joining" retry rather than a
      // silently wrong row.
      await firestore.collection('users').doc('member').set(<String, Object?>{
        'displayName': 'Renamed',
      });

      await rooms.joinRoom('room-1');
      final participant = await firestore
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('member')
          .get();
      expect(participant.data()?['displayName'], 'Member');
    });

    test('a fresh service reads the profile again', () async {
      await firestore.collection('users').doc('member').set(<String, Object?>{
        'displayName': 'Renamed',
      });
      final fresh = RoomService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'member'),
        ),
        coverAccessInvoker: (_) async => _grant(),
      );

      await fresh.joinRoom('room-1');
      final participant = await firestore
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('member')
          .get();
      expect(participant.data()?['displayName'], 'Renamed');
    });

    test('an account boundary drops the remembered profile', () async {
      final room = await rooms.getRoom('room-1');
      await rooms.resolveVoiceStartAuthority(room);
      await firestore.collection('users').doc('member').set(<String, Object?>{
        'displayName': 'Renamed',
      });

      // Sign-out clears every ephemeral media grant; the profile memo rides
      // the same signal so it can never outlive its session.
      RoomService.clearAllCoverAccessCaches();

      await rooms.joinRoom('room-1');
      final participant = await firestore
          .collection('rooms')
          .doc('room-1')
          .collection('participants')
          .doc('member')
          .get();
      expect(participant.data()?['displayName'], 'Renamed');
    });
  });

  group('bounded waits', () {
    test('every interactive callable answers well before the plugin default', () {
      // The cloud_functions default is 60 s. Anything on a path where a person
      // is watching a control must be shorter than that, or the app has no way
      // to tell them anything for a full minute.
      const pluginDefault = Duration(seconds: 60);
      final deadlines = <String, Duration>{
        'startRoomVoice': RoomService.startRoomVoiceTimeout,
        'getRoomCoverMediaAccess': RoomService.coverAccessTimeout,
        'setOwnRoomParticipantMute': RoomService.setMutedDefaultTimeout,
        'createLiveKitToken': VoiceTokenService.createTokenTimeout,
        'openDirectConversation': MessageService.openConversationTimeout,
        'reserveReelDraftV2': ReelService.reserveTimeout,
      };
      for (final entry in deadlines.entries) {
        expect(
          entry.value,
          lessThan(pluginDefault),
          reason: '${entry.key} must fail before the plugin default.',
        );
        expect(entry.value.inSeconds, greaterThanOrEqualTo(10));
      }
      // finalizeReelDraftV2 range-reads and probes the committed object, so it
      // is deliberately the one long deadline — still under the server's 120 s.
      expect(ReelService.finalizeTimeout, const Duration(seconds: 60));
    });

    test(
      'a deadline reads as a slow server, never as a missing network',
      () async {
        Future<RoomVoiceEntry> enterWith(Object error) {
          final coordinator = RoomVoiceEntryCoordinator(
            readRoom: (_) async => _entryRoom().withLiveness(false),
            resolveAuthority: (_) async => RoomVoiceStartAuthority.host,
            startVoice: (_) async => throw error,
            joinRoom: (_, {startMuted = false}) async => _entryRoom(),
          );
          return coordinator.enter(_entryRoom().withLiveness(false));
        }

        final timedOut = await enterWith(
          FirebaseFunctionsException(
            code: 'deadline-exceeded',
            message: 'deadline exceeded',
          ),
        );
        expect(timedOut.outcome, RoomVoiceEntryOutcome.failed);
        // The operation's own retry copy, which is catalogued and localized in
        // every shipping locale — NOT the offline message, which would blame a
        // connection that is working.
        expect(timedOut.message, 'Could not start voice. Try again.');
        expect(
          timedOut.canStartVoice,
          isTrue,
          reason: 'A deadline is retryable; the affordance must survive it.',
        );
        final timedOutLocally = await enterWith(
          TimeoutException('startRoomVoice', const Duration(seconds: 15)),
        );
        expect(timedOutLocally.message, 'Could not start voice. Try again.');

        final offline = await enterWith(
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'unavailable',
          ),
        );
        expect(
          offline.message,
          'You appear to be offline. Check your connection and try again.',
        );
      },
    );
  });
}
