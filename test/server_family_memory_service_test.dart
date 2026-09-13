import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/servers/data/services/server_family_memory_service.dart';

import 'voice_moment_test_doubles.dart';

Map<String, Object?> familyMemoryData({
  String memoryId = 'fm_memory_001',
  String channelId = 'memories',
  String status = 'published',
  DateTime? createdAt,
}) => <String, Object?>{
  'schemaVersion': 1,
  'memoryKind': 'familyMemory',
  'serverId': 'family_server',
  'clubId': 'family_server',
  'channelId': channelId,
  'memoryId': memoryId,
  'authorId': 'parent_1',
  'authorDisplayName': 'Mama',
  'authorPhotoUrl': null,
  'caption': 'Niedziela razem',
  'status': status,
  'photo': const <String, Object?>{
    'storagePath':
        'family_moments/family_server/parent_1/fm_memory_001_photo.jpg',
    'generation': '1700000000000001',
    'contentType': 'image/jpeg',
    'size': 2048,
  },
  'voice': const <String, Object?>{
    'storagePath':
        'family_moments/family_server/parent_1/fm_memory_001_voice.m4a',
    'generation': '1700000000000002',
    'contentType': 'audio/mp4',
    'size': 4096,
    'durationMs': 4200,
  },
  'revision': 1,
  'createdAt': Timestamp.fromDate(createdAt ?? DateTime.utc(2026, 9, 13)),
  'updatedAt': Timestamp.fromDate(createdAt ?? DateTime.utc(2026, 9, 13)),
};

Map<Object?, Object?> reservation({required int expiresAtMillis}) =>
    <Object?, Object?>{
      'schemaVersion': 1,
      'serverId': 'family_server',
      'channelId': 'memories',
      'memoryId': 'fm_memory_001',
      'expiresAtMillis': expiresAtMillis,
      'photo': <Object?, Object?>{
        'storagePath':
            'family_moments/family_server/parent_1/fm_memory_001_photo.jpg',
        'contentType': 'image/jpeg',
        'size': 2048,
        'uploadMetadata': const <String, String>{
          'yovoiceServerId': 'family_server',
          'yovoiceChannelId': 'memories',
          'yovoiceOwnerUid': 'parent_1',
          'yovoiceMemoryId': 'fm_memory_001',
          'yovoiceAssetKind': 'photo',
        },
      },
      'voice': <Object?, Object?>{
        'storagePath':
            'family_moments/family_server/parent_1/fm_memory_001_voice.m4a',
        'contentType': 'audio/mp4',
        'size': 4096,
        'durationMs': 4200,
        'uploadMetadata': const <String, String>{
          'yovoiceServerId': 'family_server',
          'yovoiceChannelId': 'memories',
          'yovoiceOwnerUid': 'parent_1',
          'yovoiceMemoryId': 'fm_memory_001',
          'yovoiceAssetKind': 'voice',
        },
      },
    };

void main() {
  test(
    'published Family Memories are parsed from the scoped ordered feed',
    () async {
      final firestore = FakeFirebaseFirestore();
      final feed = firestore
          .collection('clubs')
          .doc('family_server')
          .collection('moments');
      await feed
          .doc('fm_memory_001')
          .set(familyMemoryData(createdAt: DateTime.utc(2026, 9, 13)));
      await feed.doc('fm_memory_002').set({
        ...familyMemoryData(
          memoryId: 'fm_memory_002',
          createdAt: DateTime.utc(2026, 9, 14),
        ),
        'photo': const <String, Object?>{
          'storagePath':
              'family_moments/family_server/parent_1/fm_memory_002_photo.jpg',
          'generation': '1700000000000003',
          'contentType': 'image/jpeg',
          'size': 2048,
        },
        'voice': const <String, Object?>{
          'storagePath':
              'family_moments/family_server/parent_1/fm_memory_002_voice.m4a',
          'generation': '1700000000000004',
          'contentType': 'audio/mp4',
          'size': 4096,
          'durationMs': 4200,
        },
      });
      await feed
          .doc('draft')
          .set(familyMemoryData(memoryId: 'draft', status: 'deleting'));
      await feed
          .doc('other')
          .set(familyMemoryData(memoryId: 'other', channelId: 'other-channel'));

      final memories = await ServerFamilyMemoryService(
        firestore: firestore,
      ).watchFamilyMemories('family_server', 'memories').first;

      expect(memories.map((memory) => memory.id), [
        'fm_memory_002',
        'fm_memory_001',
      ]);
      expect(memories.first.voice.durationMs, 4200);
    },
  );

  test(
    'publish sends exact payloads and reuses reservation and uploads on retry',
    () async {
      final now = DateTime.utc(2026, 9, 13, 12);
      final calls = <(String, Map<String, Object?>)>[];
      final requestIds = ['family_reserve_001', 'family_finalize_001'];
      var finalizeAttempts = 0;
      var photoUploads = 0;
      var voiceUploads = 0;
      final service = ServerFamilyMemoryService(
        clock: () => now,
        requestIdFactory: () => requestIds.removeAt(0),
        photoUploader: (bytes, target) async {
          photoUploads += 1;
          expect(bytes.lengthInBytes, 2048);
          expect(target.uploadMetadata['yovoiceAssetKind'], 'photo');
          return '1700000000000001';
        },
        voiceUploader: (audio, target) async {
          voiceUploads += 1;
          expect(audio.byteLength, 4096);
          expect(target.uploadMetadata['yovoiceAssetKind'], 'voice');
          return '1700000000000002';
        },
        callOverride: (callable, payload) async {
          calls.add((callable, Map<String, Object?>.from(payload)));
          if (callable == 'reserveServerFamilyMemoryV1') {
            return reservation(
              expiresAtMillis: now
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
            );
          }
          finalizeAttempts += 1;
          if (finalizeAttempts == 1) {
            throw StateError('connection closed after the server received it');
          }
          return const <Object?, Object?>{
            'schemaVersion': 1,
            'serverId': 'family_server',
            'channelId': 'memories',
            'memoryId': 'fm_memory_001',
            'revision': 1,
            'status': 'published',
          };
        },
      );
      final audio = FakeRecordedAudio(byteLength: 4096);
      final attempt = service.newFamilyMemoryPublishAttempt(
        serverId: 'family_server',
        channelId: 'memories',
        caption: ' Niedziela razem ',
        photoBytes: Uint8List(2048),
        photoContentType: 'image/jpeg',
        voice: audio,
        voiceDurationMs: 4200,
      );

      await expectLater(
        service.publishFamilyMemory(attempt),
        throwsA(
          isA<ServerFamilyMemoryException>().having(
            (error) => error.failure,
            'failure',
            ServerFamilyMemoryFailure.unavailable,
          ),
        ),
      );
      expect(await service.publishFamilyMemory(attempt), 'fm_memory_001');

      expect(photoUploads, 1);
      expect(voiceUploads, 1);
      expect(calls.map((call) => call.$1), [
        'reserveServerFamilyMemoryV1',
        'finalizeServerFamilyMemoryV1',
        'finalizeServerFamilyMemoryV1',
      ]);
      expect(calls.first.$2, {
        'serverId': 'family_server',
        'channelId': 'memories',
        'requestId': 'family_reserve_001',
        'caption': 'Niedziela razem',
        'photoContentType': 'image/jpeg',
        'photoSize': 2048,
        'voiceContentType': 'audio/mp4',
        'voiceSize': 4096,
        'voiceDurationMs': 4200,
      });
      expect(calls[1].$2, calls[2].$2);
      expect(calls[1].$2, {
        'serverId': 'family_server',
        'channelId': 'memories',
        'memoryId': 'fm_memory_001',
        'requestId': 'family_finalize_001',
        'photoGeneration': '1700000000000001',
        'voiceGeneration': '1700000000000002',
      });
    },
  );

  test(
    'playback uses the short lived callable grant and caches only while safe',
    () async {
      final now = DateTime.utc(2026, 9, 13, 12);
      final calls = <(String, Map<String, Object?>)>[];
      final service = ServerFamilyMemoryService(
        clock: () => now,
        callOverride: (callable, payload) async {
          calls.add((callable, Map<String, Object?>.from(payload)));
          return <Object?, Object?>{
            'schemaVersion': 1,
            'serverId': 'family_server',
            'channelId': 'memories',
            'memoryId': 'fm_memory_001',
            'expiresAtMillis': now
                .add(const Duration(seconds: 90))
                .millisecondsSinceEpoch,
            'photo': const <Object?, Object?>{
              'url': 'https://media.example/photo?signature=one',
              'generation': '1700000000000001',
              'contentType': 'image/jpeg',
              'size': 2048,
            },
            'voice': const <Object?, Object?>{
              'url': 'https://media.example/voice?signature=two',
              'generation': '1700000000000002',
              'contentType': 'audio/mp4',
              'size': 4096,
              'durationMs': 4200,
            },
          };
        },
      );

      final first = await service.getFamilyMemoryMediaAccess(
        serverId: 'family_server',
        channelId: 'memories',
        memoryId: 'fm_memory_001',
      );
      final second = await service.getFamilyMemoryMediaAccess(
        serverId: 'family_server',
        channelId: 'memories',
        memoryId: 'fm_memory_001',
      );

      expect(first, same(second));
      expect(first.voice.url.queryParameters['signature'], 'two');
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'getServerFamilyMemoryMediaAccessV1');
      expect(calls.single.$2, {
        'serverId': 'family_server',
        'channelId': 'memories',
        'memoryId': 'fm_memory_001',
      });
    },
  );

  test('delete sends the exact revision-fenced request', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerFamilyMemoryService(
      callOverride: (callable, payload) async {
        calls.add((callable, Map<String, Object?>.from(payload)));
        return const <Object?, Object?>{
          'serverId': 'family_server',
          'channelId': 'memories',
          'memoryId': 'fm_memory_001',
          'deletionRevision': 2,
          'deleted': true,
          'cleanupPending': false,
          'deletionOperationId': 'delete_operation_001',
        };
      },
    );

    await service.deleteFamilyMemory(
      serverId: 'family_server',
      channelId: 'memories',
      memoryId: 'fm_memory_001',
      expectedRevision: 1,
      requestId: 'family_delete_001',
    );

    expect(calls.single.$1, 'deleteServerFamilyMemoryV1');
    expect(calls.single.$2, {
      'serverId': 'family_server',
      'channelId': 'memories',
      'memoryId': 'fm_memory_001',
      'expectedRevision': 1,
      'requestId': 'family_delete_001',
    });
  });
}
