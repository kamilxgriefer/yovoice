import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';

ReelUploadPayload _photo() {
  return ReelUploadPayload(
    bytes: Uint8List.fromList(<int>[
      0xff,
      0xd8,
      0xff,
      ...List<int>.filled(125, 0),
    ]),
    contentType: 'image/jpeg',
    durationMs: 0,
  );
}

MockFirebaseAuth _auth() => MockFirebaseAuth(
  mockUser: MockUser(uid: 'creator-1', isEmailVerified: true),
  signedIn: true,
);

void main() {
  test(
    'publish executes reserve, canonical upload and finalize in order',
    () async {
      final calls = <String>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          calls.add(name);
          if (name == 'reserveReelDraft') {
            return <Object?, Object?>{
              'reelId': 'reel_1',
              'mediaStoragePath': 'reels/creator-1/reel_1/media.jpg',
              'backingAudioStoragePath': null,
            };
          }
          expect(name, 'finalizeReelDraft');
          expect(payload['mediaGeneration'], '123');
          return <Object?, Object?>{'reelId': 'reel_1', 'published': true};
        },
        uploadInvoker:
            ({
              required storagePath,
              required payload,
              required metadata,
              onProgress,
            }) async {
              calls.add('upload');
              expect(storagePath, 'reels/creator-1/reel_1/media.jpg');
              expect(metadata, <String, String>{
                'ownerId': 'creator-1',
                'reelId': 'reel_1',
                'assetKind': 'media',
              });
              onProgress?.call(1);
              return '123';
            },
      );
      final session = ReelPublishSession(
        plan: ReelDraftPlan(
          media: _photo(),
          composition: const ReelComposition(originalAudioVolume: 0),
        ),
        requestId: 'request-00000001',
      );

      expect(await service.publish(session), 'reel_1');
      expect(calls, <String>[
        'reserveReelDraft',
        'upload',
        'finalizeReelDraft',
      ]);
    },
  );

  test(
    'ambiguous finalize retry reuses reservation and uploaded generation',
    () async {
      var reserveCount = 0;
      var uploadCount = 0;
      var finalizeCount = 0;
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          if (name == 'reserveReelDraft') {
            reserveCount += 1;
            return <Object?, Object?>{
              'reelId': 'reel_retry',
              'mediaStoragePath': 'reels/creator-1/reel_retry/media.jpg',
              'backingAudioStoragePath': null,
            };
          }
          finalizeCount += 1;
          if (finalizeCount == 1) throw StateError('lost response');
          return <Object?, Object?>{'reelId': 'reel_retry', 'published': true};
        },
        uploadInvoker:
            ({
              required storagePath,
              required payload,
              required metadata,
              onProgress,
            }) async {
              uploadCount += 1;
              return '456';
            },
      );
      final session = ReelPublishSession(
        plan: ReelDraftPlan(
          media: _photo(),
          composition: const ReelComposition(originalAudioVolume: 0),
        ),
        requestId: 'request-00000002',
      );

      await expectLater(service.publish(session), throwsStateError);
      expect(await service.publish(session), 'reel_retry');
      expect(reserveCount, 1);
      expect(uploadCount, 1);
      expect(finalizeCount, 2);
    },
  );

  test(
    'feed parser rejects server payloads carrying undeclared identity data',
    () async {
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async => <Object?, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'reel_1',
              'authorId': 'creator-1',
              'authorName': 'Creator',
              'email': 'must-not-cross-boundary@example.com',
              'media': <String, Object>{
                'kind': 'image',
                'contentType': 'image/jpeg',
                'size': 1024,
                'generation': '123',
                'durationMs': 0,
              },
              'backingAudio': null,
              'composition': const ReelComposition(
                originalAudioVolume: 0,
              ).toWire(),
              'publishedAtMillis': 1900000000000,
              'sortKey': '1900000000000_reel_1',
            },
          ],
          'nextCursor': null,
        },
      );
      await expectLater(service.fetchFeed(), throwsFormatException);
    },
  );

  test('report uses the safety callable and validates its response', () async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        expect(name, 'createReelReport');
        expect(payload, <String, Object?>{
          'reelId': 'reel_1',
          'requestId': 'report-request-0001',
          'reason': 'spam',
          'note': '',
        });
        return <Object?, Object?>{'reportId': 'report_1', 'created': true};
      },
    );

    expect(
      await service.reportReel(
        'reel_1',
        reason: ' spam ',
        requestId: 'report-request-0001',
      ),
      'report_1',
    );
  });

  test('an already-filed report remains a successful safety outcome', () async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async => <Object?, Object?>{
        'reportId': 'report_1',
        'created': false,
      },
    );

    expect(
      await service.reportReel(
        'reel_1',
        reason: 'other',
        requestId: 'report-request-0002',
      ),
      'report_1',
    );
  });
}
