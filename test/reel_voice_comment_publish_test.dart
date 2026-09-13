import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

import 'voice_moment_test_doubles.dart';

/// The Reels voice-comment PUBLISH seam, at the service boundary.
///
/// Slice 4 built the two-phase backend; this is the client half. The
/// invariants under test are the ones a person's recorded voice depends on:
/// the bytes land only under the name the server reserved, one lost
/// acknowledgement never publishes the same recording twice, and nothing is
/// uploaded at all when the recording cannot be published.
typedef _Call = ({String name, Map<String, Object?> payload});

const _viewer = 'viewer_1';
const _reelId = 'reel_1';
const _commentId = 'c0mment0000000000000000000000000000000001';
const _storagePath = 'reel_voice_comments/$_viewer/$_reelId/$_commentId.m4a';

FirebaseFunctionsException _refusal(String code) =>
    FirebaseFunctionsException(code: code, message: 'refused in test');

Map<Object?, Object?> _reservation({
  String reelId = _reelId,
  String commentId = _commentId,
  String storagePath = _storagePath,
}) => <Object?, Object?>{
  'reelId': reelId,
  'commentId': commentId,
  'storagePath': storagePath,
  'created': true,
};

Map<Object?, Object?> _finalized({int commentCount = 1}) => <Object?, Object?>{
  'reelId': _reelId,
  'commentId': _commentId,
  'created': true,
  'commentCount': commentCount,
};

class _Harness {
  _Harness({bool emailVerified = true}) {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer, isEmailVerified: emailVerified),
      ),
      callableInvoker: (name, payload) {
        calls.add((name: name, payload: payload));
        final responder = responders[name];
        if (responder == null) throw StateError('Unexpected callable $name');
        return responder(payload);
      },
      voiceCommentUploadInvoker:
          ({
            required String storagePath,
            required RecordedAudio audio,
            required Map<String, String> metadata,
          }) async {
            uploads.add((path: storagePath, metadata: metadata));
            if (uploadError != null) throw uploadError!;
            return generation;
          },
    );
  }

  final List<_Call> calls = <_Call>[];
  final List<({String path, Map<String, String> metadata})> uploads =
      <({String path, Map<String, String> metadata})>[];
  final Map<
    String,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)
  >
  responders = {};
  Object? uploadError;
  String generation = '1700000000000001';
  late final ReelService service;

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

void main() {
  setUp(ReelService.clearAllMediaAccessCaches);

  group('publishing one voice comment', () {
    test('reserves, uploads under the reserved name, then finalizes', () async {
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          _reservation();
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async =>
          _finalized();
      final session = ReelVoiceCommentSession(
        reelId: _reelId,
        durationSeconds: 12,
        caption: 'Listen to this',
      );

      final commentId = await harness.service.publishVoiceComment(
        session,
        audio: FakeRecordedAudio(),
      );

      expect(commentId, _commentId);
      expect(harness.calls.map((call) => call.name), <String>[
        'reserveReelVoiceCommentDraft',
        'finalizeReelVoiceCommentDraft',
      ]);
      expect(harness.callsTo('reserveReelVoiceCommentDraft').single.payload, {
        'durationSeconds': 12,
        'reelId': _reelId,
        'requestId': session.requestId,
        'text': 'Listen to this',
      });
      // The upload carries exactly the three custom-metadata keys Storage
      // Rules pin at upload time, and lands at the reserved path.
      expect(harness.uploads.single.path, _storagePath);
      expect(harness.uploads.single.metadata, <String, String>{
        'authorId': _viewer,
        'reelId': _reelId,
        'commentId': _commentId,
      });
      expect(harness.callsTo('finalizeReelVoiceCommentDraft').single.payload, {
        'commentId': _commentId,
        'objectGeneration': '1700000000000001',
        'reelId': _reelId,
        'requestId': session.requestId,
      });
    });

    test('an empty caption publishes; the recording is the content', () async {
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          _reservation();
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async =>
          _finalized();

      await harness.service.publishVoiceComment(
        ReelVoiceCommentSession(
          reelId: _reelId,
          durationSeconds: 1,
          caption: '   ',
        ),
        audio: FakeRecordedAudio(),
      );

      expect(
        harness.callsTo('reserveReelVoiceCommentDraft').single.payload['text'],
        '',
      );
    });

    test('a lost finalize acknowledgement replays; it never reserves or '
        'uploads a second time', () async {
      var finalizeAttempts = 0;
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          _reservation();
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async {
        finalizeAttempts++;
        if (finalizeAttempts == 1) throw _refusal('unavailable');
        return _finalized();
      };
      final session = ReelVoiceCommentSession(
        reelId: _reelId,
        durationSeconds: 9,
        caption: 'Once',
      );
      final audio = FakeRecordedAudio();

      await expectLater(
        harness.service.publishVoiceComment(session, audio: audio),
        throwsA(isA<ReelEngagementException>()),
      );
      final commentId = await harness.service.publishVoiceComment(
        session,
        audio: audio,
      );

      expect(commentId, _commentId);
      expect(harness.callsTo('reserveReelVoiceCommentDraft'), hasLength(1));
      expect(harness.uploads, hasLength(1));
      expect(harness.callsTo('finalizeReelVoiceCommentDraft'), hasLength(2));
      // One request id across every phase and every retry: that is what
      // makes the server's ledger replay instead of creating a second
      // comment out of one recording.
      for (final call in harness.calls) {
        expect(call.payload['requestId'], session.requestId);
      }
    });

    test('a failed upload is retried against the same reservation', () async {
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          _reservation();
      harness.responders['finalizeReelVoiceCommentDraft'] = (_) async =>
          _finalized();
      harness.uploadError = StateError('network dropped');
      final session = ReelVoiceCommentSession(
        reelId: _reelId,
        durationSeconds: 4,
        caption: '',
      );
      final audio = FakeRecordedAudio();

      await expectLater(
        harness.service.publishVoiceComment(session, audio: audio),
        throwsA(isA<StateError>()),
      );
      harness.uploadError = null;
      await harness.service.publishVoiceComment(session, audio: audio);

      expect(harness.callsTo('reserveReelVoiceCommentDraft'), hasLength(1));
      expect(harness.uploads, hasLength(2));
      expect(harness.callsTo('finalizeReelVoiceCommentDraft'), hasLength(1));
    });

    test(
      'a reservation naming somebody else\'s object is refused, unuploaded',
      () async {
        final harness = _Harness();
        harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
            _reservation(
              storagePath:
                  'reel_voice_comments/other_user/$_reelId/$_commentId.m4a',
            );

        await expectLater(
          harness.service.publishVoiceComment(
            ReelVoiceCommentSession(
              reelId: _reelId,
              durationSeconds: 5,
              caption: '',
            ),
            audio: FakeRecordedAudio(),
          ),
          throwsA(isA<FormatException>()),
        );

        expect(harness.uploads, isEmpty);
        expect(harness.callsTo('finalizeReelVoiceCommentDraft'), isEmpty);
      },
    );

    test('a reservation for another Yeel is refused, unuploaded', () async {
      final harness = _Harness();
      harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
          _reservation(reelId: 'reel_2');

      await expectLater(
        harness.service.publishVoiceComment(
          ReelVoiceCommentSession(
            reelId: _reelId,
            durationSeconds: 5,
            caption: '',
          ),
          audio: FakeRecordedAudio(),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(harness.uploads, isEmpty);
    });

    test('the 1-60 second bound is refused before any round trip', () async {
      for (final seconds in <int>[0, -1, 61, 600]) {
        final harness = _Harness();
        await expectLater(
          harness.service.publishVoiceComment(
            ReelVoiceCommentSession(
              reelId: _reelId,
              durationSeconds: seconds,
              caption: '',
            ),
            audio: FakeRecordedAudio(),
          ),
          throwsA(isA<ArgumentError>()),
          reason: '$seconds seconds must never reach the callable',
        );
        expect(harness.calls, isEmpty);
        expect(harness.uploads, isEmpty);
      }
    });

    test('a 141-character caption is refused before any round trip', () async {
      final harness = _Harness();
      await expectLater(
        harness.service.publishVoiceComment(
          ReelVoiceCommentSession(
            reelId: _reelId,
            durationSeconds: 5,
            caption: 'x' * 141,
          ),
          audio: FakeRecordedAudio(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(harness.calls, isEmpty);
      // 140 is the bound, and it is inclusive.
      expect(ReelComment.maxVoiceCaptionLength, 140);
    });

    test('an unpublishable recording never reaches Storage', () async {
      final harness = _Harness();
      await expectLater(
        harness.service.publishVoiceComment(
          ReelVoiceCommentSession(
            reelId: _reelId,
            durationSeconds: 5,
            caption: '',
          ),
          // Under the 1 KiB floor `isValidAudioPayload` enforces.
          audio: FakeRecordedAudio(byteLength: 64),
        ),
        throwsA(isA<VoiceRecordingException>()),
      );
      expect(harness.calls, isEmpty);
      expect(harness.uploads, isEmpty);
    });

    test('a refusal keeps its code so the composer can explain it', () async {
      for (final entry in <String, ReelEngagementFailure>{
        'failed-precondition': ReelEngagementFailure.emailUnverified,
        'resource-exhausted': ReelEngagementFailure.rateLimited,
        'permission-denied': ReelEngagementFailure.unavailable,
        'not-found': ReelEngagementFailure.unavailable,
      }.entries) {
        final harness = _Harness();
        harness.responders['reserveReelVoiceCommentDraft'] = (_) async =>
            throw _refusal(entry.key);
        await expectLater(
          harness.service.publishVoiceComment(
            ReelVoiceCommentSession(
              reelId: _reelId,
              durationSeconds: 5,
              caption: '',
            ),
            audio: FakeRecordedAudio(),
          ),
          throwsA(
            isA<ReelEngagementException>().having(
              (error) => error.reason,
              'reason',
              entry.value,
            ),
          ),
          reason: entry.key,
        );
        expect(harness.uploads, isEmpty);
      }
    });
  });

  group('forward tolerance on the engagement results', () {
    // `deleteReelComment` and `removeReelComment` return EXACTLY the key set
    // every installed strict reader accepts — an earlier backend draft added
    // `audioQueued` and it was taken back out, because installed clients read
    // the committed deletion as malformed (ADR-187). These readers still
    // tolerate that one named key, so a build carrying them would not repeat
    // the failure; an unknown extra key is still refused.
    test(
      'a deletion carrying audioQueued is still a successful deletion',
      () async {
        final harness = _Harness();
        harness.responders['deleteReelComment'] = (_) async =>
            <Object?, Object?>{
              'reelId': _reelId,
              'commentId': _commentId,
              'deleted': true,
              'commentCount': 2,
              'audioQueued': true,
            };

        final result = await harness.service.deleteComment(
          _reelId,
          commentId: _commentId,
        );

        expect(result.commentId, _commentId);
        expect(result.commentCount, 2);
      },
    );

    test('an author removal carrying audioQueued still succeeds', () async {
      final harness = _Harness();
      harness.responders['removeReelComment'] = (_) async => <Object?, Object?>{
        'reelId': _reelId,
        'commentId': _commentId,
        'removed': true,
        'commentCount': 1,
        'removedAuthorId': 'creator_1',
        'audioQueued': false,
      };

      final result = await harness.service.removeComment(
        _reelId,
        commentId: _commentId,
      );

      expect(result.removedAuthorId, 'creator_1');
      expect(result.commentCount, 1);
    });

    test('an UNKNOWN extra key is still refused', () async {
      final harness = _Harness();
      harness.responders['deleteReelComment'] = (_) async => <Object?, Object?>{
        'reelId': _reelId,
        'commentId': _commentId,
        'deleted': true,
        'commentCount': 2,
        'somethingNobodyContracted': true,
      };

      await expectLater(
        harness.service.deleteComment(_reelId, commentId: _commentId),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('listening to one voice comment', () {
    Map<Object?, Object?> grant({
      int expiresInSeconds = 90,
      int durationSeconds = 12,
    }) => <Object?, Object?>{
      'schemaVersion': 2,
      'url': 'https://storage.googleapis.com/bucket/object?sig=1',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresInSeconds))
          .millisecondsSinceEpoch,
      'generation': '1700000000000001',
      'durationSeconds': durationSeconds,
      'availabilityHours': 'permanent',
      'contentExpiresAtMillis': null,
    };

    test('asks for the comment asset, and caches the answer', () async {
      final harness = _Harness();
      harness.responders['getReelMediaAccessV2'] = (_) async => grant();

      final uri = await harness.service.resolveVoiceCommentUri(
        _reelId,
        commentId: _commentId,
      );
      expect(uri.host, 'storage.googleapis.com');
      expect(harness.callsTo('getReelMediaAccessV2').single.payload, {
        'reelId': _reelId,
        'asset': 'voiceComment',
        'commentId': _commentId,
      });

      await harness.service.resolveVoiceCommentUri(
        _reelId,
        commentId: _commentId,
      );
      expect(harness.callsTo('getReelMediaAccessV2'), hasLength(1));
      expect(
        harness.service.cachedVoiceCommentUri(_reelId, commentId: _commentId),
        isNotNull,
      );
    });

    test('two comments on one Yeel never share a grant', () async {
      const other = 'c0mment0000000000000000000000000000000002';
      final harness = _Harness();
      harness.responders['getReelMediaAccessV2'] = (_) async => grant();

      await harness.service.resolveVoiceCommentUri(
        _reelId,
        commentId: _commentId,
      );
      await harness.service.resolveVoiceCommentUri(_reelId, commentId: other);

      expect(harness.callsTo('getReelMediaAccessV2'), hasLength(2));
      expect(
        harness
            .callsTo('getReelMediaAccessV2')
            .map((c) => c.payload['commentId']),
        <String>[_commentId, other],
      );
    });

    test(
      'an account boundary drops the grant and fails a late answer',
      () async {
        final pending = Completer<Map<Object?, Object?>>();
        final harness = _Harness();
        harness.responders['getReelMediaAccessV2'] = (_) => pending.future;

        final inFlight = harness.service.resolveVoiceCommentUri(
          _reelId,
          commentId: _commentId,
        );
        ReelService.clearAllMediaAccessCaches();
        pending.complete(grant());

        await expectLater(inFlight, throwsA(isA<StateError>()));
        expect(
          harness.service.cachedVoiceCommentUri(_reelId, commentId: _commentId),
          isNull,
        );
      },
    );

    test('a malformed or unsafe grant is refused rather than played', () async {
      final cases = <String, Map<Object?, Object?>>{
        'a non-https host': <Object?, Object?>{
          ...grant(),
          'url': 'https://example.com/object',
        },
        'a duration outside the contract': <Object?, Object?>{
          ...grant(),
          'durationSeconds': 61,
        },
        'a missing duration': <Object?, Object?>{...grant()}
          ..remove('durationSeconds'),
        'an already expired signature': <Object?, Object?>{
          ...grant(expiresInSeconds: -5),
        },
      };
      for (final entry in cases.entries) {
        ReelService.clearAllMediaAccessCaches();
        final harness = _Harness();
        harness.responders['getReelMediaAccessV2'] = (_) async => entry.value;
        await expectLater(
          harness.service.resolveVoiceCommentUri(
            _reelId,
            commentId: _commentId,
          ),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });
  });

  group('the deployed-contract probe', () {
    Map<Object?, Object?> view() => <Object?, Object?>{
      'schemaVersion': 2,
      'reel': <String, Object?>{
        'id': _reelId,
        'authorId': 'creator_1',
        'authorName': 'Creator One',
        'media': <String, Object?>{
          'kind': 'video',
          'contentType': 'video/mp4',
          'size': 4096,
          'generation': '7',
          'durationMs': 10000,
        },
        'backingAudio': null,
        'composition': const ReelComposition(
          trimStartMs: 0,
          trimEndMs: 10000,
        ).toWire(),
        'publishedAtMillis': 1725000000000,
        'sortKey': '1725000000000_$_reelId',
        'availability': <String, Object?>{
          'schemaVersion': 1,
          'availabilityHours': 'permanent',
          'expiresAtMillis': null,
        },
        'likeCount': 0,
        'commentCount': 0,
        'callerLiked': false,
      },
      'comments': const <Object?>[],
      'commentsTruncated': false,
      'nextCommentCursor': null,
    };

    test(
      'asks for voice comments and latches a backend that accepts',
      () async {
        final harness = _Harness();
        harness.responders['getReelViewV2'] = (_) async => view();
        expect(
          harness.service.voiceCommentSupport.value,
          ReelVoiceCommentSupport.unknown,
        );

        await harness.service.loadView(_reelId);

        expect(
          harness.callsTo('getReelViewV2').single.payload['commentTypes'],
          <String>['text', 'voice'],
        );
        expect(
          harness.service.voiceCommentSupport.value,
          ReelVoiceCommentSupport.supported,
        );
        expect(harness.service.voiceCommentsSupported, isTrue);
      },
    );

    test('a backend that refuses the flag is VERIFIED before the mic is '
        'withdrawn, and is never asked again', () async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (payload) async {
        if (payload.containsKey('commentTypes')) {
          throw _refusal('invalid-argument');
        }
        return view();
      };

      await harness.service.loadView(_reelId);

      // Two round trips ONCE: the refusal, then the identical request
      // without the flag proving the flag was the only problem.
      expect(harness.callsTo('getReelViewV2'), hasLength(2));
      expect(
        harness
            .callsTo('getReelViewV2')
            .last
            .payload
            .containsKey('commentTypes'),
        isFalse,
      );
      expect(
        harness.service.voiceCommentSupport.value,
        ReelVoiceCommentSupport.unsupported,
      );
      expect(harness.service.voiceCommentsSupported, isFalse);

      await harness.service.loadView(_reelId);
      expect(harness.callsTo('getReelViewV2'), hasLength(3));
      expect(
        harness
            .callsTo('getReelViewV2')
            .last
            .payload
            .containsKey('commentTypes'),
        isFalse,
      );
    });

    test(
      'a request refused for its own reasons teaches the probe nothing',
      () async {
        final harness = _Harness();
        harness.responders['getReelViewV2'] = (_) async =>
            throw _refusal('invalid-argument');

        await expectLater(
          harness.service.loadView(_reelId),
          throwsA(
            isA<ReelEngagementException>().having(
              (error) => error.reason,
              'reason',
              ReelEngagementFailure.invalid,
            ),
          ),
        );

        // A poisoned cursor must not be mistaken for an old deployment.
        expect(
          harness.service.voiceCommentSupport.value,
          ReelVoiceCommentSupport.unknown,
        );
      },
    );

    test('the probe notifies, so a composer can swap the mic live', () async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async => view();
      final seen = <ReelVoiceCommentSupport>[];
      harness.service.voiceCommentSupport.addListener(
        () => seen.add(harness.service.voiceCommentSupport.value),
      );

      await harness.service.loadView(_reelId);

      expect(seen, <ReelVoiceCommentSupport>[
        ReelVoiceCommentSupport.supported,
      ]);
    });
  });
}
