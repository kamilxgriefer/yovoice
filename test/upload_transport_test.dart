import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
// XFile through image_picker, the package that actually produces it here.
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_upload_transport.dart';
import 'package:yovoice/features/reels/data/services/reel_upload_transport_bytes.dart'
    as bytes_transport;

/// A minimal but real MP4: `ftyp` at offset 4 is what both the client sniffer
/// and the server's header check key on.
Uint8List _videoBytes(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const <int>[
    0, 0, 0, 24, // box size
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x69, 0x73, 0x6f, 0x6d, // 'isom'
  ]);
  return bytes;
}

Uint8List _jpegBytes(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, const <int>[0xff, 0xd8, 0xff]);
  return bytes;
}

Future<XFile> _tempFile(String name, Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('yo_reel_upload');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path);
}

ReelPublishSession _session(ReelUploadPayload media) => ReelPublishSession(
  plan: ReelDraftPlan(
    media: media,
    composition: const ReelComposition(originalAudioVolume: 0),
  ),
  requestId: 'request-00000001',
);

Map<Object?, Object?> _reservation() => <Object?, Object?>{
  'schemaVersion': 2,
  'reelId': 'reel_1',
  'mediaStoragePath': 'reels/creator-1/reel_1/media.mp4',
  'backingAudioStoragePath': null,
  'expiresAtMillis': 1900000900000,
  'availabilityHours': 24,
  'contentExpiresAtMillis': 2000000000000,
};

Map<Object?, Object?> _finalized() => <Object?, Object?>{
  'schemaVersion': 2,
  'reelId': 'reel_1',
  'published': true,
  'availabilityHours': 24,
  'expiresAtMillis': 2000000000000,
};

void main() {
  group('what a picked asset carries', () {
    test('a video is carried as its file, not as its bytes', () async {
      final file = await _tempFile('clip.mp4', _videoBytes(2 * 1024 * 1024));

      final payload = await ReelUploadPayload.fromXFile(file, durationMs: 5000);

      expect(payload.mediaKind, ReelMediaKind.video);
      expect(payload.contentType, 'video/mp4');
      expect(payload.isStreamed, isTrue);
      expect(
        payload.bytes,
        isEmpty,
        reason:
            'A 100 MB cap on resident video bytes was the whole cost this '
            'removes; nothing may quietly put them back.',
      );
      expect(
        payload.size,
        2 * 1024 * 1024,
        reason:
            'The declared size is what the reservation and the server '
            'check the committed object against.',
      );
      expect(payload.sourcePath, file.path);
      expect(await payload.readBytes(), hasLength(2 * 1024 * 1024));
    });

    test('a photo keeps the bytes its preview needs', () async {
      final file = await _tempFile('shot.jpg', _jpegBytes(4096));

      final payload = await ReelUploadPayload.fromXFile(file, durationMs: 0);

      expect(payload.mediaKind, ReelMediaKind.image);
      expect(payload.isStreamed, isFalse);
      expect(payload.bytes, hasLength(4096));
      expect(payload.size, 4096);
    });

    test('two payloads over one file are still two sources', () async {
      final file = await _tempFile('clip.mp4', _videoBytes(1024));
      final first = await ReelUploadPayload.fromXFile(file, durationMs: 5000);
      final second = await ReelUploadPayload.fromXFile(file, durationMs: 5000);

      // The composer preview rebuilds its decoder on
      // `!identical(old.bytes, new.bytes)`; a shared const empty list would
      // make every replacement look like the same source.
      expect(identical(first.bytes, first.bytes), isTrue);
      expect(identical(first.bytes, second.bytes), isFalse);
    });

    test('an unrecognisable header is refused from the header alone', () async {
      final file = await _tempFile('junk.bin', Uint8List(4096));

      await expectLater(
        ReelUploadPayload.fromXFile(file, durationMs: 5000),
        throwsFormatException,
      );
    });

    test('the header probe reads only its window', () async {
      final file = await _tempFile('clip.mp4', _videoBytes(1024 * 1024));

      final header = await readReelHeader(file);

      expect(header, hasLength(reelHeaderProbeBytes));
      expect(sniffReelContentType(header), 'video/mp4');
    });
  });

  group('the io transport', () {
    test('streams a picked file and copies resident bytes', () async {
      final storage = MockFirebaseStorage();
      final file = await _tempFile('clip.mp4', _videoBytes(4096));
      final video = await ReelUploadPayload.fromXFile(file, durationMs: 5000);
      final photo = ReelUploadPayload(
        bytes: _jpegBytes(512),
        contentType: 'image/jpeg',
        durationMs: 0,
      );

      await startReelUpload(
        reference: storage.ref('reels/creator-1/reel_1/media.mp4'),
        payload: video,
        metadata: SettableMetadata(contentType: video.contentType),
      );
      await startReelUpload(
        reference: storage.ref('reels/creator-1/reel_1/cover.jpg'),
        payload: photo,
        metadata: SettableMetadata(contentType: photo.contentType),
      );

      expect(
        storage.storedDataMap.get('reels/creator-1/reel_1/media.mp4'),
        isA<File>(),
        reason: 'putFile streams; putData would need the whole video resident.',
      );
      expect(
        storage.storedDataMap.get('reels/creator-1/reel_1/cover.jpg'),
        isA<Uint8List>(),
      );
    });

    test(
      'refuses a file whose length no longer matches the reservation',
      () async {
        final storage = MockFirebaseStorage();
        final file = await _tempFile('clip.mp4', _videoBytes(4096));
        final payload = await ReelUploadPayload.fromXFile(
          file,
          durationMs: 5000,
        );
        await File(file.path).writeAsBytes(_videoBytes(8192), flush: true);

        await expectLater(
          startReelUpload(
            reference: storage.ref('reels/creator-1/reel_1/media.mp4'),
            payload: payload,
            metadata: SettableMetadata(contentType: payload.contentType),
          ),
          throwsFormatException,
        );
        expect(storage.storedDataMap.keys, isEmpty);
      },
    );

    test(
      'an evicted picker file is a re-pick, not a filesystem error',
      () async {
        final storage = MockFirebaseStorage();
        final file = await _tempFile('clip.mp4', _videoBytes(4096));
        final payload = await ReelUploadPayload.fromXFile(
          file,
          durationMs: 5000,
        );
        await File(file.path).delete();

        await expectLater(
          startReelUpload(
            reference: storage.ref('reels/creator-1/reel_1/media.mp4'),
            payload: payload,
            metadata: SettableMetadata(contentType: payload.contentType),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Choose it again'),
            ),
          ),
        );
      },
    );
  });

  test(
    'the byte transport sends the same content for a streamed asset',
    () async {
      final storage = MockFirebaseStorage();
      final file = await _tempFile('clip.mp4', _videoBytes(4096));
      final payload = await ReelUploadPayload.fromXFile(file, durationMs: 5000);

      await bytes_transport.startReelUploadTask(
        reference: storage.ref('reels/creator-1/reel_1/media.mp4'),
        payload: payload,
        metadata: SettableMetadata(contentType: payload.contentType),
      );

      final stored = storage.storedDataMap.get(
        'reels/creator-1/reel_1/media.mp4',
      );
      expect(stored, isA<Uint8List>());
      expect(stored as Uint8List, hasLength(4096));
    },
  );

  group('the upload contract', () {
    test('no local path reaches reserve or finalize', () async {
      final file = await _tempFile('clip.mp4', _videoBytes(4096));
      final media = await ReelUploadPayload.fromXFile(file, durationMs: 5000);
      final session = ReelPublishSession(
        plan: ReelDraftPlan(
          media: media,
          composition: const ReelComposition(trimEndMs: 5000),
        ),
        requestId: 'request-00000001',
      );
      final payloads = <String, Map<String, Object?>>{};
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
        ),
        callableInvoker: (name, payload) async {
          payloads[name] = Map<String, Object?>.of(payload);
          return name == 'reserveReelDraftV2' ? _reservation() : _finalized();
        },
        uploadInvoker:
            ({
              required storagePath,
              required payload,
              required metadata,
              onProgress,
            }) async => '123',
      );

      expect(await service.publish(session), 'reel_1');

      expect(payloads['reserveReelDraftV2']!.keys.toSet(), <String>{
        'requestId',
        'mediaKind',
        'mediaContentType',
        'mediaSize',
        'durationMs',
        'hasBackingAudio',
        'audioContentType',
        'audioSize',
        'audioDurationMs',
        'availabilityHours',
      });
      expect(payloads['finalizeReelDraftV2']!.keys.toSet(), <String>{
        'requestId',
        'reelId',
        'mediaGeneration',
        'backingAudioGeneration',
        'composition',
      });
      // The path exists on the payload for the local preview and must never
      // leave the device. Nothing on the wire may equal it, at any depth.
      final wire = payloads.values.map((payload) => '$payload').join(' ');
      expect(wire, isNot(contains(file.path)));
      expect(wire, isNot(contains(Directory.systemTemp.path)));
      expect(payloads['reserveReelDraftV2']!['mediaSize'], 4096);
    });

    test(
      'progress is weighted by bytes and finalize is its own stage',
      () async {
        final progress = <double>[];
        final stages = <ReelPublishStage>[];
        final service = ReelService(
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
          ),
          callableInvoker: (name, payload) async => name == 'reserveReelDraftV2'
              ? (_reservation()
                  ..['backingAudioStoragePath'] =
                      'reels/creator-1/reel_1/audio.mp3')
              : _finalized(),
          uploadInvoker:
              ({
                required storagePath,
                required payload,
                required metadata,
                onProgress,
              }) async {
                onProgress?.call(.5);
                onProgress?.call(1);
                return '123';
              },
        );
        final session = ReelPublishSession(
          plan: ReelDraftPlan(
            media: ReelUploadPayload(
              bytes: _jpegBytes(9000),
              contentType: 'image/jpeg',
              durationMs: 0,
            ),
            backingAudio: ReelUploadPayload(
              bytes: Uint8List.fromList(<int>[
                0x49,
                0x44,
                0x33,
                ...List<int>.filled(997, 0),
              ]),
              contentType: 'audio/mpeg',
              durationMs: 5000,
            ),
            composition: const ReelComposition(
              originalAudioVolume: 0,
              backingAudioVolume: 100,
              audioRightsAttested: true,
            ),
          ),
          requestId: 'request-00000002',
        );

        await service.publish(
          session,
          onProgress: progress.add,
          onStage: stages.add,
        );

        // 9000 media bytes + 1000 audio bytes: half the media is 45 % of the
        // upload, not 40 % of an arbitrary stage split, and the audio's whole
        // 1000 bytes moves the bar by a tenth of the upload share.
        expect(progress.first, closeTo(0.45 * .95, 0.001));
        expect(progress[1], closeTo(0.9 * .95, 0.001));
        expect(progress[2], closeTo(0.95 * .95, 0.001));
        expect(progress[3], closeTo(.95, 0.001));
        expect(progress.last, 1);
        expect(progress, everyElement(lessThanOrEqualTo(1)));
        expect(stages, <ReelPublishStage>[
          ReelPublishStage.reserving,
          ReelPublishStage.uploading,
          ReelPublishStage.uploading,
          ReelPublishStage.finalizing,
        ]);
      },
    );

    test('a retry after a lost finalize does not restart the bar', () async {
      final progress = <double>[];
      var finalizeCalls = 0;
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
        ),
        callableInvoker: (name, payload) async {
          if (name == 'reserveReelDraftV2') return _reservation();
          finalizeCalls += 1;
          if (finalizeCalls == 1) throw StateError('lost response');
          return _finalized();
        },
        uploadInvoker:
            ({
              required storagePath,
              required payload,
              required metadata,
              onProgress,
            }) async {
              onProgress?.call(1);
              return '123';
            },
      );
      final session = _session(
        ReelUploadPayload(
          bytes: _jpegBytes(4096),
          contentType: 'image/jpeg',
          durationMs: 0,
        ),
      );

      await expectLater(service.publish(session), throwsStateError);
      await service.publish(session, onProgress: progress.add);

      expect(
        progress,
        <double>[1],
        reason:
            'The bytes are already committed; the retry only has to finalize.',
      );
    });
  });
}
