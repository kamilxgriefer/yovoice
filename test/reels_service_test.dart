import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
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
  testWidgets('feed completion does not wait for auth stream cleanup zone', (
    tester,
  ) async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (_, _) async => <Object?, Object?>{
        'schemaVersion': 2,
        'items': <Object?>[],
        'nextCursor': null,
      },
    );
    ReelFeedPage? completed;
    unawaited(
      service.fetchFeed().then((page) {
        completed = page;
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(completed, isNotNull);
    expect(completed!.items, isEmpty);
  });

  for (final stage in <String>[
    'reserve',
    'media',
    'backingAudio',
    'finalize',
  ]) {
    for (final returnToOwner in <bool>[false, true]) {
      test('publish rejects $stage completion after '
          '${returnToOwner ? 'A-B-A' : 'A-B'} and cannot retry it', () async {
        final auth = _SwitchableReelAuth();
        addTearDown(auth.close);
        final reached = Completer<void>();
        final release = Completer<void>();
        final calls = <String>[];
        final progress = <double>[];
        void Function(double)? delayedProgress;
        Future<void> visit(String value) async {
          calls.add(value);
          if (stage == value) {
            reached.complete();
            await release.future;
          }
        }

        final hasAudio = stage == 'backingAudio';
        final service = ReelService(
          auth: auth,
          callableInvoker: (name, payload) async {
            if (name == 'reserveReelDraftV2') {
              await visit('reserve');
              return _reservation()
                ..['backingAudioStoragePath'] = hasAudio
                    ? 'reels/creator-1/reel_1/backing-audio.mp3'
                    : null;
            }
            expect(name, 'finalizeReelDraftV2');
            await visit('finalize');
            return _finalized();
          },
          uploadInvoker:
              ({
                required storagePath,
                required payload,
                required metadata,
                onProgress,
              }) async {
                expect(metadata['ownerId'], 'creator-1');
                if (stage == metadata['assetKind']) {
                  delayedProgress = onProgress;
                }
                await visit(metadata['assetKind']!);
                return '123';
              },
        );
        final session = _publishSession(hasAudio: hasAudio);
        final publishing = expectLater(
          service.publish(session, onProgress: progress.add),
          throwsStateError,
        );
        await reached.future;
        final callsAtBoundary = List<String>.of(calls);
        auth.setIdentity('viewer-2');
        if (returnToOwner) auth.setIdentity('creator-1');
        delayedProgress?.call(.9);
        release.complete();
        await publishing;
        expect(
          calls,
          callsAtBoundary,
          reason: 'No later pipeline stage may run.',
        );
        expect(
          progress,
          isEmpty,
          reason: 'No stale progress or success callback.',
        );
        if (stage == 'reserve') expect(session.reelId, isNull);
        if (stage == 'media') expect(session.mediaGeneration, isNull);
        if (stage == 'backingAudio') {
          expect(session.backingAudioGeneration, isNull);
        }
        auth.setIdentity('creator-1');
        await expectLater(service.publish(session), throwsStateError);
        expect(calls, callsAtBoundary);
        expect(auth.hasListeners, isFalse);
      });
    }
  }

  test(
    'publish retry is bound to its original owner after a network failure',
    () async {
      final auth = _SwitchableReelAuth();
      addTearDown(auth.close);
      var calls = 0;
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) async {
          calls += 1;
          throw StateError('offline');
        },
      );
      final session = _publishSession();
      await expectLater(service.publish(session), throwsStateError);
      auth.setIdentity('viewer-2');
      await expectLater(service.publish(session), throwsStateError);
      auth.setIdentity('creator-1');
      await expectLater(service.publish(session), throwsStateError);
      expect(calls, 1);
      expect(auth.hasListeners, isFalse);
    },
  );

  test(
    'privacy cache boundary invalidates same-account publish retry',
    () async {
      final auth = _SwitchableReelAuth();
      addTearDown(auth.close);
      var calls = 0;
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) async {
          calls += 1;
          throw StateError('lost acknowledgement');
        },
      );
      final session = _publishSession();
      await expectLater(service.publish(session), throwsStateError);
      ReelService.clearAllMediaAccessCaches();
      await expectLater(service.publish(session), throwsStateError);
      expect(calls, 1);
    },
  );

  for (final boundary in <String>['account', 'A-B-A', 'sign-out', 'epoch']) {
    test('feed discards a response crossing $boundary', () async {
      final auth = _SwitchableReelAuth();
      addTearDown(auth.close);
      final response = Completer<Map<Object?, Object?>>();
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) => response.future,
      );
      final loading = expectLater(service.fetchFeed(), throwsStateError);
      if (boundary == 'epoch') {
        ReelService.clearAllMediaAccessCaches();
      } else {
        auth.setIdentity(boundary == 'sign-out' ? null : 'viewer-2');
        if (boundary == 'A-B-A') auth.setIdentity('creator-1');
      }
      response.complete(_feedResponse());
      await loading;
      expect(auth.hasListeners, isFalse);
    });
  }

  test(
    'same-UID profile refresh preserves reads and distinct identity seam',
    () async {
      final auth = _SwitchableReelAuth();
      addTearDown(auth.close);
      final response = Completer<Map<Object?, Object?>>();
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) => response.future,
      );
      final identities = <String?>[];
      final subscription = service.identityChanges.listen(identities.add);
      final loading = service.fetchFeed();
      auth.setIdentity('creator-1');
      auth.setIdentity('creator-1');
      response.complete(_feedResponse());
      final reel = (await loading).items.single;
      expect(service.isCurrentUserAuthor(reel), isTrue);
      auth.setIdentity('viewer-2');
      expect(service.isCurrentUserAuthor(reel), isFalse);
      auth.setIdentity(null);
      expect(service.isCurrentUserAuthor(reel), isFalse);
      expect(service.currentUserId, isNull);
      expect(identities, <String?>['creator-1', 'viewer-2', null]);
      await subscription.cancel();
      expect(auth.hasListeners, isFalse);
    },
  );

  test(
    'an identity-stream error invalidates pending feed without leaking it',
    () async {
      final auth = _SwitchableReelAuth();
      addTearDown(auth.close);
      final response = Completer<Map<Object?, Object?>>();
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) => response.future,
      );
      final loading = expectLater(service.fetchFeed(), throwsStateError);
      auth.failIdentity();
      response.complete(_feedResponse());
      await loading;
      expect(auth.hasListeners, isFalse);
    },
  );

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

class _SwitchableReelAuth extends MockFirebaseAuth {
  User? _user = MockUser(uid: 'creator-1', isEmailVerified: true);
  final _changes = StreamController<User?>.broadcast(sync: true);

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> userChanges() => _changes.stream;

  bool get hasListeners => _changes.hasListener;

  void setIdentity(String? uid) {
    _user = uid == null ? null : MockUser(uid: uid, isEmailVerified: true);
    _changes.add(_user);
  }

  void failIdentity() => _changes.addError(StateError('identity unavailable'));

  Future<void> close() => _changes.close();
}

ReelPublishSession _publishSession({bool hasAudio = false}) =>
    ReelPublishSession(
      plan: ReelDraftPlan(
        media: _photo(),
        backingAudio: hasAudio
            ? ReelUploadPayload(
                bytes: Uint8List(512),
                contentType: 'audio/mpeg',
                durationMs: 1000,
              )
            : null,
        composition: ReelComposition(
          originalAudioVolume: 0,
          audioRightsAttested: hasAudio,
          backingAudioVolume: hasAudio ? 50 : 0,
        ),
      ),
    );

Map<Object?, Object?> _feedResponse() => <Object?, Object?>{
  'schemaVersion': 2,
  'items': <Object?>[
    _feedItem(
      id: 'late_reel',
      availability: <String, Object?>{
        'schemaVersion': 1,
        'availabilityHours': 'permanent',
        'expiresAtMillis': null,
      },
    ),
  ],
  'nextCursor': null,
};

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
