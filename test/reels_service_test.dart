import 'dart:typed_data';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
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

const _contentExpiry = 2000000000000;

Map<Object?, Object?> _reservation({
  String reelId = 'reel_1',
  Object availabilityHours = 24,
  int? contentExpiresAtMillis = _contentExpiry,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reelId': reelId,
  'mediaStoragePath': 'reels/creator-1/$reelId/media.jpg',
  'backingAudioStoragePath': null,
  'expiresAtMillis': 1900000900000,
  'availabilityHours': availabilityHours,
  'contentExpiresAtMillis': contentExpiresAtMillis,
};

Map<Object?, Object?> _finalized({
  String reelId = 'reel_1',
  Object availabilityHours = 24,
  int? expiresAtMillis = _contentExpiry,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reelId': reelId,
  'published': true,
  'availabilityHours': availabilityHours,
  'expiresAtMillis': expiresAtMillis,
};

void main() {
  test(
    'publish executes reserve, canonical upload and finalize in order',
    () async {
      final calls = <String>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          calls.add(name);
          if (name == 'reserveReelDraftV2') {
            expect(payload['availabilityHours'], 24);
            return _reservation();
          }
          expect(name, 'finalizeReelDraftV2');
          expect(payload['mediaGeneration'], '123');
          return _finalized();
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
        'reserveReelDraftV2',
        'upload',
        'finalizeReelDraftV2',
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
          if (name == 'reserveReelDraftV2') {
            reserveCount += 1;
            return _reservation(reelId: 'reel_retry');
          }
          finalizeCount += 1;
          if (finalizeCount == 1) throw StateError('lost response');
          return _finalized(reelId: 'reel_retry');
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
          'schemaVersion': 2,
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
              'availability': <String, Object?>{
                'schemaVersion': 2,
                'availabilityHours': 24,
                'expiresAtMillis': _contentExpiry,
              },
            },
          ],
          'nextCursor': null,
        },
      );
      await expectLater(service.fetchFeed(), throwsFormatException);
    },
  );

  test('availability accepts exact boundary hours and permanent only', () {
    expect(ReelAvailabilityChoice.timedHours(24).wireValue, 24);
    expect(ReelAvailabilityChoice.timedHours(720).wireValue, 720);
    expect(
      ReelAvailabilityChoice.fromWire('permanent'),
      ReelAvailabilityChoice.permanent,
    );
    expect(() => ReelAvailabilityChoice.timedHours(23), throwsRangeError);
    expect(() => ReelAvailabilityChoice.timedHours(721), throwsRangeError);
    expect(() => ReelAvailabilityChoice.fromWire(24.0), throwsFormatException);
  });

  test('permanent v2 publish stays locked to its retry session', () async {
    final payloads = <Map<String, Object?>>[];
    var finalizeCount = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        payloads.add(Map<String, Object?>.of(payload));
        if (name == 'reserveReelDraftV2') {
          return _reservation(
            reelId: 'reel_permanent',
            availabilityHours: 'permanent',
            contentExpiresAtMillis: null,
          );
        }
        expect(name, 'finalizeReelDraftV2');
        finalizeCount += 1;
        if (finalizeCount == 1) throw StateError('lost response');
        return _finalized(
          reelId: 'reel_permanent',
          availabilityHours: 'permanent',
          expiresAtMillis: null,
        );
      },
      uploadInvoker:
          ({
            required storagePath,
            required payload,
            required metadata,
            onProgress,
          }) async => '789',
    );
    final session = ReelPublishSession(
      plan: ReelDraftPlan(
        media: _photo(),
        composition: const ReelComposition(originalAudioVolume: 0),
        availability: ReelAvailabilityChoice.permanent,
      ),
      requestId: 'request-permanent-1',
    );

    await expectLater(service.publish(session), throwsStateError);
    expect(session.plan.availability, ReelAvailabilityChoice.permanent);
    expect(await service.publish(session), 'reel_permanent');
    expect(
      payloads
          .where((item) => item.containsKey('availabilityHours'))
          .single['availabilityHours'],
      'permanent',
    );
  });

  test('reserve response is exact and cannot change selected availability', () {
    final extra = _reservation()..['unexpected'] = true;
    final mismatched = _reservation(availabilityHours: 168);
    Future<void> run(Map<Object?, Object?> response) async {
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async => response,
      );
      await service.publish(
        ReelPublishSession(
          plan: ReelDraftPlan(
            media: _photo(),
            composition: const ReelComposition(originalAudioVolume: 0),
          ),
        ),
      );
    }

    expect(run(extra), throwsFormatException);
    expect(run(mismatched), throwsFormatException);
  });

  test(
    'v2 feed parses timed and legacy-permanent availability safely',
    () async {
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          expect(name, 'listReelsV2');
          return <Object?, Object?>{
            'schemaVersion': 2,
            'items': <Object?>[
              _feedItem(
                id: 'timed',
                availability: <String, Object?>{
                  'schemaVersion': 2,
                  'availabilityHours': 168,
                  'expiresAtMillis': _contentExpiry,
                },
              ),
              _feedItem(
                id: 'legacy',
                availability: <String, Object?>{
                  'schemaVersion': 1,
                  'availabilityHours': 'permanent',
                  'expiresAtMillis': null,
                },
              ),
            ],
            'nextCursor': null,
          };
        },
      );

      final page = await service.fetchFeed();
      expect(page.items.first.availability.choice.hours, 168);
      expect(
        page.items.first.availability.contentExpiresAt?.millisecondsSinceEpoch,
        _contentExpiry,
      );
      expect(page.items.last.availability, ReelAvailability.legacyPermanent);
    },
  );

  test('v2 media access rejects grants beyond content expiry', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        expect(name, 'getReelMediaAccessV2');
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': 'https://storage.googleapis.com/bucket/reel.jpg?token=x',
          'expiresAtMillis': now + 120000,
          'generation': '123',
          'availabilityHours': 24,
          'contentExpiresAtMillis': now + 60000,
        };
      },
    );

    await expectLater(
      service.resolveMediaUri('grant_after_expiry'),
      throwsFormatException,
    );
  });

  test(
    'delete retry reuses its request id after a lost acknowledgement',
    () async {
      final requestIds = <String>[];
      var calls = 0;
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          expect(name, 'deleteReel');
          calls += 1;
          requestIds.add(payload['requestId']! as String);
          if (calls == 1) throw StateError('lost acknowledgement');
          return <Object?, Object?>{'reelId': 'reel_1', 'deleted': true};
        },
      );

      await expectLater(service.deleteReel('reel_1'), throwsStateError);
      await service.deleteReel('reel_1');

      expect(requestIds, hasLength(2));
      expect(requestIds.first, requestIds.last);
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

Map<String, Object?> _feedItem({
  required String id,
  required Map<String, Object?> availability,
}) => <String, Object?>{
  'id': id,
  'authorId': 'creator-1',
  'authorName': 'Creator',
  'media': <String, Object>{
    'kind': 'image',
    'contentType': 'image/jpeg',
    'size': 1024,
    'generation': '123',
    'durationMs': 0,
  },
  'backingAudio': null,
  'composition': const ReelComposition(originalAudioVolume: 0).toWire(),
  'publishedAtMillis': 1900000000000,
  'sortKey': '1900000000000_$id',
  'availability': availability,
};
