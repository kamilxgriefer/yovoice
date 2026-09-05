import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show AudioEncoder;

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/web_mime_negotiation.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';

import 'voice_moment_test_doubles.dart';

/// Voice Moment recording was broken for every web user: the screen called
/// `getTemporaryDirectory()` before starting the recorder, `path_provider`
/// has no web implementation registered in this app, and the resulting
/// `MissingPluginException` was swallowed by a broad `catch` into the
/// snackbar "Could not start recording".
///
/// These tests cover the seam that fix introduced — the byte-acquisition
/// and byte-upload split, the MIME/extension agreement the deployed
/// Storage rules enforce, and the failure taxonomy that keeps a platform
/// gap distinguishable from a blocked microphone. They deliberately do not
/// test `record`, `record_web` or `firebase_storage` themselves.
void main() {
  group('publishable audio contract', () {
    test('mirrors exactly what storage.rules and the callables accept', () {
      // storage.rules `isAllowedAudioType()` and `AUDIO_TYPES` in
      // functions/moments/integrity.js. If either widens, this set is the
      // client half that has to move with it.
      expect(kPublishableAudioContentTypes, <String>{
        'audio/mp4',
        'audio/m4a',
        'audio/x-m4a',
      });
      // Both `momentStoragePath()` and the rules' `fileName == momentId +
      // '.m4a'` bake this in.
      expect(kVoiceMomentFileExtension, 'm4a');
      expect(kVoiceMomentContentType, isIn(kPublishableAudioContentTypes));
    });

    test('normalization drops the codec parameters browsers attach', () {
      // Chromium reports exactly this for the type record_web negotiates.
      expect(
        normalizeAudioContentType('audio/mp4;codecs=mp4a.40.2'),
        'audio/mp4',
      );
      expect(normalizeAudioContentType('AUDIO/MP4; codecs=mp4a'), 'audio/mp4');
      expect(normalizeAudioContentType('  audio/mp4  '), 'audio/mp4');
      expect(normalizeAudioContentType('audio/webm;codecs=opus'), 'audio/webm');
    });

    test('a parameterised mp4 type is publishable; webm and aac are not', () {
      expect(isPublishableAudioContentType('audio/mp4;codecs=mp4a.40.2'), true);
      expect(isPublishableAudioContentType('audio/x-m4a'), true);
      // The rules compare against a bare set, so an unnormalized declared
      // content type would be rejected at upload time.
      expect(isPublishableAudioContentType('audio/webm;codecs=opus'), false);
      expect(isPublishableAudioContentType('audio/aac'), false);
      expect(isPublishableAudioContentType('audio/wav'), false);
      expect(isPublishableAudioContentType(''), false);
    });
  });

  group('web MIME negotiation', () {
    test('takes the first type record_web would take, in its order', () {
      final probed = <String>[];
      final chosen = resolveWebRecordingMimeType((type) {
        probed.add(type);
        return type == 'audio/mp4;codecs=mp4a.40.2';
      });
      expect(chosen, 'audio/mp4;codecs=mp4a.40.2');
      expect(probed.first, 'audio/mp4;codecs=mp4a');
    });

    test('the type Chromium actually supports resolves to supported', () {
      // Measured on Chromium 148 via MediaRecorder.isTypeSupported:
      // 'audio/mp4;codecs=mp4a' false, 'audio/mp4;codecs=mp4a.40.2' true.
      const chromium = <String, bool>{
        'audio/mp4;codecs=mp4a': false,
        'audio/mp4;codecs=mp4a.40.2': true,
        'audio/aac': false,
      };
      final chosen = resolveWebRecordingMimeType((t) => chromium[t] ?? false);
      expect(chosen, 'audio/mp4;codecs=mp4a.40.2');
      expect(webCaptureSupportFor(chosen).isSupported, true);
    });

    test('a browser with no MP4/AAC encoder is refused, and says why', () {
      final chosen = resolveWebRecordingMimeType((_) => false);
      expect(chosen, isNull);

      final support = webCaptureSupportFor(chosen);
      expect(support.isSupported, false);
      expect(support.reason, contains('MP4/AAC'));
      // Specific, not "Coming soon", and it names a way forward.
      expect(support.reason, isNot(contains('Coming soon')));
      expect(support.action, contains('Chrome'));
    });

    test('an AAC-only browser is refused for a different, stated reason', () {
      // record_web would happily negotiate 'audio/aac' here, and the
      // upload would then be rejected by the Storage rules. Catching it in
      // the probe is what turns a silent failure into an explanation.
      final chosen = resolveWebRecordingMimeType((t) => t == 'audio/aac');
      expect(chosen, 'audio/aac');

      final support = webCaptureSupportFor(chosen);
      expect(support.isSupported, false);
      expect(support.reason, contains('audio/aac'));
    });
  });

  group('validateRecordedAudio', () {
    test('accepts a normal mp4 recording', () {
      expect(validateRecordedAudio(FakeRecordedAudio()), isNull);
    });

    test('refuses a container the backend cannot accept', () {
      final problem = validateRecordedAudio(
        FakeRecordedAudio(contentType: 'audio/webm'),
      );
      expect(problem?.problem, VoiceRecordingProblem.recordingUnusable);
      expect(problem?.message, contains('audio/webm'));
    });

    test('refuses payloads outside the Storage rules byte bounds', () {
      // storage.rules: size >= 1024 && size <= 12 MiB.
      expect(
        validateRecordedAudio(FakeRecordedAudio(byteLength: 1023))?.problem,
        VoiceRecordingProblem.recordingUnusable,
      );
      expect(
        validateRecordedAudio(FakeRecordedAudio(byteLength: 1024)),
        isNull,
      );
      expect(
        validateRecordedAudio(
          FakeRecordedAudio(byteLength: 12 * 1024 * 1024 + 1),
        )?.problem,
        VoiceRecordingProblem.recordingUnusable,
      );
    });
  });

  group('VoiceMomentRecorder failure taxonomy', () {
    test('an unsupported platform never asks for the microphone', () async {
      final backend = FakeRecorderBackend();
      final capture = FakeAudioCapture()
        ..support = const CaptureSupport.unsupported(
          reason: 'This browser cannot record MP4/AAC audio.',
          action: 'Open YO Voice in Chrome, Edge or Safari to record.',
        );
      final recorder = VoiceMomentRecorder(backend: backend, capture: capture);

      expect((await recorder.checkSupport()).isSupported, false);

      await expectLater(
        recorder.start(),
        throwsA(
          isA<VoiceRecordingException>().having(
            (e) => e.problem,
            'problem',
            VoiceRecordingProblem.platformCannotRecord,
          ),
        ),
      );
      // Prompting for a microphone that could never produce a publishable
      // recording would be a misleading permission request.
      expect(backend.permissionCalls, 0);
      expect(backend.startCalls, 0);
    });

    test('support is probed once and cached', () async {
      final capture = FakeAudioCapture();
      final recorder = VoiceMomentRecorder(
        backend: FakeRecorderBackend(),
        capture: capture,
      );
      await recorder.checkSupport();
      await recorder.checkSupport();
      expect(capture.probeCalls, 1);
    });

    test(
      'a refused microphone is microphoneBlocked, not a generic failure',
      () async {
        final recorder = VoiceMomentRecorder(
          backend: FakeRecorderBackend()..permission = false,
          capture: FakeAudioCapture(),
        );

        await expectLater(
          recorder.start(),
          throwsA(
            isA<VoiceRecordingException>()
                .having(
                  (e) => e.problem,
                  'problem',
                  VoiceRecordingProblem.microphoneBlocked,
                )
                .having((e) => e.message, 'message', contains('blocked'))
                .having((e) => e.action, 'action', contains('Allow')),
          ),
        );
      },
    );

    test(
      'a MissingPluginException preparing storage is named, not swallowed',
      () async {
        // The original production bug, verbatim: path_provider has no web
        // implementation, `getTemporaryDirectory()` threw this, and a broad
        // catch reported "Could not start recording".
        final recorder = VoiceMomentRecorder(
          backend: FakeRecorderBackend(),
          capture: FakeAudioCapture()
            ..targetError = MissingPluginException(
              'No implementation found for method getTemporaryDirectory',
            ),
        );

        await expectLater(
          recorder.start(),
          throwsA(
            isA<VoiceRecordingException>()
                .having(
                  (e) => e.problem,
                  'problem',
                  VoiceRecordingProblem.platformCannotRecord,
                )
                // A platform gap, never reported as a capture failure the
                // user could retry their way out of.
                .having((e) => e.message, 'message', isNot(contains('again'))),
          ),
        );
      },
    );

    test('a recorder that will not start is captureFailed', () async {
      final recorder = VoiceMomentRecorder(
        backend: FakeRecorderBackend()..startError = StateError('device busy'),
        capture: FakeAudioCapture(),
      );

      await expectLater(
        recorder.start(),
        throwsA(
          isA<VoiceRecordingException>().having(
            (e) => e.problem,
            'problem',
            VoiceRecordingProblem.captureFailed,
          ),
        ),
      );
      expect(recorder.isRecording, false);
    });

    test(
      'a missing recorder plugin degrades to an honest unsupported state',
      () async {
        final recorder = VoiceMomentRecorder(
          backend: FakeRecorderBackend(),
          capture: FakeAudioCapture()
            ..probeError = MissingPluginException('no recorder'),
        );

        final support = await recorder.checkSupport();
        expect(support.isSupported, false);
        expect(support.reason, isNot(contains('Coming soon')));
        expect(support.reason, contains('not available'));
      },
    );

    test('a normal capture yields uploadable audio', () async {
      final audio = FakeRecordedAudio();
      final backend = FakeRecorderBackend();
      final recorder = VoiceMomentRecorder(
        backend: backend,
        capture: FakeAudioCapture()..result = audio,
      );

      await recorder.start();
      expect(recorder.isRecording, true);
      // The one config the whole product records with — AAC-LC is what
      // keeps the result inside the publishable content types.
      expect(backend.startedConfig?.encoder, AudioEncoder.aacLc);

      expect(await recorder.stop(), same(audio));
      expect(recorder.isRecording, false);
    });

    test('an unpublishable recording is refused and discarded', () async {
      // A browser that negotiated something the pre-flight probe did not
      // predict: the bytes are real, but they cannot be published, and
      // keeping them would leak.
      final audio = FakeRecordedAudio(contentType: 'audio/webm');
      final recorder = VoiceMomentRecorder(
        backend: FakeRecorderBackend(),
        capture: FakeAudioCapture()..result = audio,
      );

      await recorder.start();
      await expectLater(
        recorder.stop(),
        throwsA(
          isA<VoiceRecordingException>().having(
            (e) => e.problem,
            'problem',
            VoiceRecordingProblem.recordingUnusable,
          ),
        ),
      );
      expect(audio.discarded, true);
    });

    test('amplitude normalization maps dBFS onto a drawable range', () {
      // record reports -160 dBFS for silence; using that as the floor would
      // flatten every visible bar.
      expect(VoiceMomentRecorder.normalizeAmplitude(-160), 0);
      expect(VoiceMomentRecorder.normalizeAmplitude(-45), 0);
      expect(VoiceMomentRecorder.normalizeAmplitude(0), 1);
      expect(
        VoiceMomentRecorder.normalizeAmplitude(-22.5),
        closeTo(0.5, 0.001),
      );
      expect(VoiceMomentRecorder.normalizeAmplitude(double.nan), 0);
      expect(VoiceMomentRecorder.normalizeAmplitude(double.infinity), 0);
    });
  });

  group('MomentService upload contract', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockFirebaseStorage storage;
    late MomentService service;

    const uid = 'author-uid-1';

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'author@yovoice.app'),
      );
      storage = MockFirebaseStorage();
      await firestore.collection('users').doc(uid).set({
        'displayName': 'Author',
        'photoUrl': null,
      });
      service = MomentService(
        firestore: firestore,
        auth: auth,
        storage: storage,
      );
    });

    test('uploads through the platform seam with the metadata the Storage '
        'rules require', () async {
      final audio = FakeRecordedAudio();

      // Exercised through the CANONICAL callable path: with no Functions,
      // publishing now REFUSES rather than falling back (the fallback could
      // not stamp `expiresAt`, so its output was invisible forever — closed
      // deliberately; the refusal itself is pinned in the retry group).
      final seamService = MomentService(
        firestore: firestore,
        auth: auth,
        storage: storage,
        functions: _MomentPublishFunctions(
          momentId: 'seam-moment',
          storagePath: 'voice_moments/$uid/seam-moment.m4a',
        ),
      );

      final momentId = await seamService.publishRecordedMoment(
        audio: audio,
        durationSeconds: 7,
        caption: 'Hello',
      );

      // The upload went through RecordedAudio, so the same call works with
      // a file on native and with bytes on web.
      expect(audio.uploadCalls, 1);

      // storage.rules /voice_moments/{userId}/{fileName}:
      //   fileName == momentId + '.m4a'
      expect(
        audio.uploadedPath,
        'voice_moments/$uid/$momentId.$kVoiceMomentFileExtension',
      );

      final metadata = audio.uploadedMetadata!;
      //   isAllowedAudioType() compares a bare content type
      expect(metadata.contentType, 'audio/mp4');
      expect(metadata.contentType, isIn(kPublishableAudioContentTypes));
      //   metadata.keys().hasOnly(['authorId', 'momentId'])
      expect(metadata.customMetadata, {'authorId': uid, 'momentId': momentId});
    });

    test(
      'refuses an unpublishable recording before uploading anything',
      () async {
        // Uploading it would be rejected by the rules, leaving a reserved
        // draft that can never finalize.
        final audio = FakeRecordedAudio(contentType: 'audio/webm');

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 7,
            caption: 'Hello',
          ),
          throwsA(isA<VoiceRecordingException>()),
        );
        expect(audio.uploadCalls, 0);
      },
    );

    test(
      'a voice reply carries the third metadata key its rule requires',
      () async {
        await firestore.collection('voiceMoments').doc('parent-moment').set({
          'authorId': 'someone-else',
          'isPublished': true,
        });
        final audio = FakeRecordedAudio();
        const commentId = 'reply-comment-id-001';
        final replyService = MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: _EngagementFunctions(
            commentId: commentId,
            voiceReplyStoragePath:
                'voice_replies/$uid/parent-moment/$commentId.m4a',
          ),
        );

        final publishedCommentId = await replyService.publishRecordedMoment(
          audio: audio,
          durationSeconds: 5,
          caption: 'Replying',
          replyToMomentId: 'parent-moment',
        );

        // storage.rules /voice_replies/{userId}/{momentId}/{fileName}
        expect(
          audio.uploadedPath,
          'voice_replies/$uid/parent-moment/$publishedCommentId'
          '.$kVoiceMomentFileExtension',
        );
        expect(audio.uploadedMetadata!.customMetadata, {
          'authorId': uid,
          'momentId': 'parent-moment',
          'commentId': publishedCommentId,
        });
        expect(audio.uploadedMetadata!.contentType, 'audio/mp4');
      },
    );
  });

  group('Moment engagement stays server-authoritative', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockFirebaseStorage storage;

    const uid = 'engagement-author';
    const momentId = 'published-moment';

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'engagement@yovoice.app'),
      );
      storage = MockFirebaseStorage();
      await firestore.collection('users').doc(uid).set({
        'displayName': 'Engagement Author',
        'photoUrl': null,
      });
      await firestore.collection('voiceMoments').doc(momentId).set({
        'authorId': 'other-author',
        'isPublished': true,
        'likeCount': 0,
        'commentCount': 0,
      });
    });

    test(
      'setLike refuses loudly and never runs a direct-read/write fallback',
      () async {
        final service = HomeFeedService(
          firestore: firestore,
          auth: auth,
          functions: _EngagementFunctions(errorCode: 'unimplemented'),
        );

        await expectLater(
          service.setLike(momentId, liked: true),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Liking needs the YO Voice server'),
            ),
          ),
        );
        expect(
          (await firestore
                  .collection('voiceMoments')
                  .doc(momentId)
                  .collection('likes')
                  .doc(uid)
                  .get())
              .exists,
          false,
        );
        expect(
          (await firestore.collection('voiceMoments').doc(momentId).get())
              .data()?['likeCount'],
          0,
        );

        // Pin the unlike direction too: an existing server-created like must
        // survive a callable outage instead of being deleted by old clients.
        await firestore
            .collection('voiceMoments')
            .doc(momentId)
            .collection('likes')
            .doc(uid)
            .set({'userId': uid});
        await expectLater(
          service.setLike(momentId, liked: false),
          throwsA(isA<StateError>()),
        );
        expect(
          (await firestore
                  .collection('voiceMoments')
                  .doc(momentId)
                  .collection('likes')
                  .doc(uid)
                  .get())
              .exists,
          true,
        );
      },
    );

    test(
      'setLike sends exact desired state through the callable only',
      () async {
        final functions = _EngagementFunctions();
        final service = HomeFeedService(
          firestore: firestore,
          auth: auth,
          functions: functions,
        );

        await service.setLike(momentId, liked: true);
        await service.setLike(momentId, liked: false);

        expect(functions.calls, const <String>[
          'setMomentLike',
          'setMomentLike',
        ]);
        expect(functions.payloads, hasLength(2));
        final liked = Map<Object?, Object?>.from(
          functions.payloads.first! as Map,
        );
        final unliked = Map<Object?, Object?>.from(
          functions.payloads.last! as Map,
        );
        expect(liked.keys.toSet(), {'momentId', 'liked', 'requestId'});
        expect(unliked.keys.toSet(), {'momentId', 'liked', 'requestId'});
        expect(liked['momentId'], momentId);
        expect(unliked['momentId'], momentId);
        expect(liked['liked'], isTrue);
        expect(unliked['liked'], isFalse);
        expect(
          liked['requestId'],
          isA<String>().having((id) => id, 'id', isNotEmpty),
        );
        expect(
          unliked['requestId'],
          isA<String>().having(
            (id) => id,
            'id',
            isNot(equals(liked['requestId'])),
          ),
        );
        expect(
          (await firestore
                  .collection('voiceMoments')
                  .doc(momentId)
                  .collection('likes')
                  .doc(uid)
                  .get())
              .exists,
          false,
        );
        expect(
          (await firestore.collection('voiceMoments').doc(momentId).get())
              .data()?['likeCount'],
          0,
        );
      },
    );

    test('text comment outage writes neither child nor counter', () async {
      final service = MomentService(
        firestore: firestore,
        auth: auth,
        storage: storage,
        functions: _EngagementFunctions(errorCode: 'unimplemented'),
      );

      await expectLater(
        service.createTextComment(momentId: momentId, text: 'Hello'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('comment was not posted'),
          ),
        ),
      );
      expect(
        (await firestore
                .collection('voiceMoments')
                .doc(momentId)
                .collection('comments')
                .get())
            .docs,
        isEmpty,
      );
      expect(
        (await firestore.collection('voiceMoments').doc(momentId).get())
            .data()?['commentCount'],
        0,
      );
    });

    test('voice reply outage keeps the recording and writes nothing', () async {
      final service = MomentService(
        firestore: firestore,
        auth: auth,
        storage: storage,
        functions: _EngagementFunctions(errorCode: 'unimplemented'),
      );
      final audio = FakeRecordedAudio();

      await expectLater(
        service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 5,
          caption: 'Voice reply',
          replyToMomentId: momentId,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('recording is kept'),
          ),
        ),
      );
      expect(audio.uploadCalls, 0);
      expect(audio.discarded, false);
      expect(
        (await firestore
                .collection('voiceMoments')
                .doc(momentId)
                .collection('comments')
                .get())
            .docs,
        isEmpty,
      );
    });

    test(
      'lost voice-reply finalize response reuses one reservation and media',
      () async {
        final functions = _VoiceReplyRetryFunctions(
          uid: uid,
          momentId: momentId,
          loseFirstFinalizeResponse: true,
        );
        final service = MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: functions,
        );
        final audio = FakeRecordedAudio();

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 5,
            caption: 'Reply exactly once',
            replyToMomentId: momentId,
          ),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (error) => error.code,
              'code',
              'unavailable',
            ),
          ),
        );

        // The fake commits the server-side comment and then loses only the
        // acknowledgement. Its now-published media must survive the error.
        final firstPath = functions.pathFor(
          _VoiceReplyRetryFunctions.firstCommentId,
        );
        expect(
          (await storage.ref(firstPath).getMetadata()).contentType,
          'audio/mp4',
        );
        expect(functions.publishedCommentIds, {
          _VoiceReplyRetryFunctions.firstCommentId,
        });

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 5,
            caption: 'Reply exactly once',
            replyToMomentId: momentId,
          ),
          _VoiceReplyRetryFunctions.firstCommentId,
        );

        expect(audio.uploadCalls, 1);
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(2));
        expect(functions.finalizePayloads[1], functions.finalizePayloads[0]);
        expect(
          functions.finalizePayloads[0]['requestId'],
          functions.reservePayloads.single['requestId'],
        );
        expect(functions.publishedCommentIds, {
          _VoiceReplyRetryFunctions.firstCommentId,
        });
      },
    );

    test(
      'pre-finalize binding failure keeps server-cleaned media and recovers generation',
      () async {
        final functions = _VoiceReplyRetryFunctions(
          uid: uid,
          momentId: momentId,
          failFinalizeBindingOnce: true,
        );
        final service = MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: functions,
        );
        final audio = FakeRecordedAudio();

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 5,
            caption: 'Keep the upload',
            replyToMomentId: momentId,
          ),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (error) => error.code,
              'code',
              'unavailable',
            ),
          ),
        );

        final path = functions.pathFor(
          _VoiceReplyRetryFunctions.firstCommentId,
        );
        expect(
          (await storage.ref(path).getMetadata()).contentType,
          'audio/mp4',
        );

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 5,
            caption: 'Keep the upload',
            replyToMomentId: momentId,
          ),
          _VoiceReplyRetryFunctions.firstCommentId,
        );
        expect(audio.uploadCalls, 1);
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(1));
      },
    );
  });

  group('MomentService server-authoritative publish retry', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockFirebaseStorage storage;

    const uid = 'mobile-web-author';
    const momentId = '0123456789abcdefabcd';
    const storagePath = 'voice_moments/$uid/$momentId.m4a';

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'mobile-web@yovoice.app'),
      );
      storage = MockFirebaseStorage();
      await firestore.collection('users').doc(uid).set({
        'displayName': 'Mobile Web Author',
        'photoUrl': null,
      });
    });

    MomentService serviceWith(_MomentPublishFunctions functions) =>
        MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: functions,
        );

    test(
      'a lost reserve response times out and replays the same request',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          hangReserveOnce: true,
        );
        final service = MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: functions,
          callableTimeout: const Duration(milliseconds: 5),
        );
        final audio = FakeRecordedAudio(byteLength: 1024);

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Bounded reservation',
          ),
          momentId,
        );
        expect(functions.reservePayloads, hasLength(2));
        expect(functions.reservePayloads[1], functions.reservePayloads[0]);
        expect(audio.uploadCalls, 1);
      },
    );

    test(
      'a lost finalize response times out and replays without reuploading',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          hangFinalizeOnce: true,
        );
        final service = MomentService(
          firestore: firestore,
          auth: auth,
          storage: storage,
          functions: functions,
          callableTimeout: const Duration(milliseconds: 5),
        );
        final audio = FakeRecordedAudio(byteLength: 1024);

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Bounded finalize',
          ),
          momentId,
        );
        expect(functions.finalizePayloads, hasLength(2));
        expect(functions.finalizePayloads[1], functions.finalizePayloads[0]);
        expect(audio.uploadCalls, 1);
      },
    );

    test('publishes a one-second mobile-web recording', () async {
      final functions = _MomentPublishFunctions(
        momentId: momentId,
        storagePath: storagePath,
      );
      final audio = FakeRecordedAudio(byteLength: 1024);

      final publishedId = await serviceWith(functions).publishRecordedMoment(
        audio: audio,
        durationSeconds: 1,
        caption: 'One second',
      );

      expect(publishedId, momentId);
      expect(audio.uploadCalls, 1);
      expect(audio.uploadedPath, storagePath);
      expect(audio.uploadedMetadata?.contentType, 'audio/mp4');
      expect(audio.uploadedMetadata?.customMetadata, {
        'authorId': uid,
        'momentId': momentId,
      });
      expect(functions.reservePayloads, hasLength(1));
      expect(functions.reservePayloads.single['durationSeconds'], 1);
      expect(functions.finalizePayloads, hasLength(1));
      expect(
        functions.finalizePayloads.single['objectGeneration'],
        '1700000000000001',
      );
      expect(
        functions.finalizePayloads.single['requestId'],
        functions.reservePayloads.single['requestId'],
      );
    });

    test(
      'retry after a lost finalize response reuses upload and reservation',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          failFinalizeOnce: true,
        );
        final service = serviceWith(functions);
        final audio = FakeRecordedAudio();

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Retry me',
          ),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (error) => error.code,
              'code',
              'unavailable',
            ),
          ),
        );

        // A finalized upload is immutable and may already exist even when the
        // callable response is lost. The previous implementation deleted it
        // here, making an otherwise safe finalize retry impossible.
        final committed = await storage.ref(storagePath).getMetadata();
        expect(committed.contentType, 'audio/mp4');

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Retry me',
          ),
          momentId,
        );

        expect(audio.uploadCalls, 1);
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(2));
        expect(functions.finalizePayloads[1], functions.finalizePayloads[0]);
        expect(
          functions.finalizePayloads[0]['requestId'],
          functions.reservePayloads.single['requestId'],
        );
      },
    );

    test(
      'retry cannot silently publish a draft with changed user-visible input',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          failFinalizeOnce: true,
        );
        final service = serviceWith(functions);
        final audio = FakeRecordedAudio();

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Original caption',
          ),
          throwsA(isA<FirebaseFunctionsException>()),
        );

        for (final changedInput
            in <({String caption, int duration, String? reply})>[
              (caption: 'Changed caption', duration: 1, reply: null),
              (caption: 'Original caption', duration: 2, reply: null),
              (
                caption: 'Original caption',
                duration: 1,
                reply: 'parent-moment',
              ),
            ]) {
          await expectLater(
            service.publishRecordedMoment(
              audio: audio,
              durationSeconds: changedInput.duration,
              caption: changedInput.caption,
              replyToMomentId: changedInput.reply,
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('Restore the original details'),
                  contains('record again'),
                ),
              ),
            ),
          );
        }

        // Refused retries neither reserve nor upload/finalize a second object.
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(1));
        expect(audio.uploadCalls, 1);
        expect(await storage.ref(storagePath).getMetadata(), isNotNull);

        // Returning to the exact pinned input safely resumes finalization.
        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: '  Original caption  ',
            replyToMomentId: '   ',
          ),
          momentId,
        );
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(2));
        expect(audio.uploadCalls, 1);
      },
    );

    test('explicit abandon releases the pinned retry identity', () async {
      final functions = _MomentPublishFunctions(
        momentId: momentId,
        storagePath: storagePath,
        failFinalizeOnce: true,
      );
      final service = serviceWith(functions);
      final audio = FakeRecordedAudio();

      await expectLater(
        service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 1,
          caption: 'Abandoned caption',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      service.abandonPendingPublish(audio);

      expect(
        await service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 1,
          caption: 'Replacement caption',
        ),
        momentId,
      );
      expect(functions.reservePayloads, hasLength(2));
      expect(
        functions.reservePayloads[0]['requestId'],
        isNot(functions.reservePayloads[1]['requestId']),
      );
    });

    test(
      'reserve transport retry keeps request id and does not upload early',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          failReserveOnce: true,
        );
        final service = serviceWith(functions);
        final audio = FakeRecordedAudio();

        await expectLater(
          service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Retry reservation',
          ),
          throwsA(isA<FirebaseFunctionsException>()),
        );
        expect(audio.uploadCalls, 0);

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Retry reservation',
          ),
          momentId,
        );
        expect(functions.reservePayloads, hasLength(2));
        expect(
          functions.reservePayloads[1]['requestId'],
          functions.reservePayloads[0]['requestId'],
        );
        expect(audio.uploadCalls, 1);
        expect(functions.finalizePayloads, hasLength(1));
      },
    );

    test(
      'an upload committed before a lost response is finalized, not redone',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
        );
        final ambiguousStorage = _AmbiguousCommitStorage(
          path: storagePath,
          generation: 'ambiguous-generation-1',
        );
        final service = MomentService(
          firestore: firestore,
          auth: auth,
          storage: ambiguousStorage,
          functions: functions,
        );
        final audio = _AmbiguousCommitAudio();

        expect(
          await service.publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Committed before disconnect',
          ),
          momentId,
        );

        expect(audio.uploadCalls, 1);
        expect(ambiguousStorage.reference.metadataReads, 1);
        expect(functions.reservePayloads, hasLength(1));
        expect(functions.finalizePayloads, hasLength(1));
        expect(
          functions.finalizePayloads.single['objectGeneration'],
          'ambiguous-generation-1',
        );
      },
    );

    test(
      'a deployed callable not-found refusal never writes a legacy moment',
      () async {
        final functions = _MomentPublishFunctions(
          momentId: momentId,
          storagePath: storagePath,
          reserveErrorCode: 'not-found',
        );
        final audio = FakeRecordedAudio();

        await expectLater(
          serviceWith(functions).publishRecordedMoment(
            audio: audio,
            durationSeconds: 1,
            caption: 'Must stay server-authoritative',
          ),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (error) => error.code,
              'code',
              'not-found',
            ),
          ),
        );

        expect(audio.uploadCalls, 0);
        expect(
          (await firestore.collection('voiceMoments').get()).docs,
          isEmpty,
        );
      },
    );

    test('an unimplemented callable REFUSES loudly, keeps the recording and '
        'writes no legacy moment', () async {
      // The direct-write fallback this test used to pin is gone on
      // purpose: only finalizeMomentDraft can stamp `expiresAt` (the
      // create rule bans the field on client writes), so a fallback
      // publish would be treated as expired on every surface — success
      // into permanent invisibility. The pinned behaviour is now the
      // refusal itself.
      final functions = _MomentPublishFunctions(
        momentId: momentId,
        storagePath: storagePath,
        reserveErrorCode: 'unimplemented',
      );

      final audio = FakeRecordedAudio();
      await expectLater(
        serviceWith(functions).publishRecordedMoment(
          audio: audio,
          durationSeconds: 1,
          caption: 'Legacy deployment only',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('recording is kept'),
          ),
        ),
      );
      final docs = await firestore.collection('voiceMoments').get();
      expect(
        docs.docs,
        isEmpty,
        reason: 'a refused publish must write NOTHING',
      );
      expect(
        audio.uploadCalls,
        0,
        reason: 'the reserve failed, so no upload may have happened',
      );
    });
  });
}

class _EngagementFunctions implements FirebaseFunctions {
  _EngagementFunctions({
    this.errorCode,
    this.commentId = 'comment-id-000000001',
    this.voiceReplyStoragePath =
        'voice_replies/author/parent/comment-id-000000001.m4a',
  });

  final String? errorCode;
  final String commentId;
  final String voiceReplyStoragePath;
  final List<String> calls = <String>[];
  final List<Object?> payloads = <Object?>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _MomentCallable((parameters) => _call(name, parameters));

  Future<Object?> _call(String name, Object? parameters) async {
    calls.add(name);
    payloads.add(parameters);
    if (errorCode != null) {
      throw FirebaseFunctionsException(
        code: errorCode!,
        message: 'Configured engagement refusal.',
      );
    }
    switch (name) {
      case 'setMomentLike':
        final payload = Map<Object?, Object?>.from(parameters! as Map);
        return <String, Object?>{'liked': payload['liked']};
      case 'createMomentComment':
        return <String, Object?>{'commentId': commentId};
      case 'reserveVoiceCommentDraft':
        return <String, Object?>{
          'commentId': commentId,
          'storagePath': voiceReplyStoragePath,
        };
      case 'finalizeVoiceCommentDraft':
        return <String, Object?>{'published': true};
      default:
        throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'Unexpected callable $name.',
        );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VoiceReplyRetryFunctions implements FirebaseFunctions {
  _VoiceReplyRetryFunctions({
    required this.uid,
    required this.momentId,
    this.loseFirstFinalizeResponse = false,
    this.failFinalizeBindingOnce = false,
  });

  static const firstCommentId = '11111111111111111111';
  static const _secondCommentId = '22222222222222222222';

  final String uid;
  final String momentId;
  final bool loseFirstFinalizeResponse;
  final bool failFinalizeBindingOnce;
  final List<Map<String, dynamic>> reservePayloads = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> finalizePayloads = <Map<String, dynamic>>[];
  final Set<String> publishedCommentIds = <String>{};
  final Map<String, String> _commentIdsByRequest = <String, String>{};
  bool _finalizeResponseLost = false;
  bool _finalizeBindingFailed = false;

  String pathFor(String commentId) =>
      'voice_replies/$uid/$momentId/$commentId.m4a';

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    if (name == 'finalizeVoiceCommentDraft' &&
        failFinalizeBindingOnce &&
        !_finalizeBindingFailed) {
      _finalizeBindingFailed = true;
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'The callable binding failed before finalize started.',
      );
    }
    return _MomentCallable((parameters) => _call(name, parameters));
  }

  Future<Object?> _call(String name, Object? parameters) async {
    final payload = Map<String, dynamic>.from(parameters as Map);
    if (name == 'reserveVoiceCommentDraft') {
      reservePayloads.add(payload);
      final requestId = payload['requestId'] as String;
      final commentId = _commentIdsByRequest.putIfAbsent(
        requestId,
        () => _commentIdsByRequest.isEmpty ? firstCommentId : _secondCommentId,
      );
      return <String, Object?>{
        'commentId': commentId,
        'storagePath': pathFor(commentId),
      };
    }
    if (name == 'finalizeVoiceCommentDraft') {
      finalizePayloads.add(payload);
      publishedCommentIds.add(payload['commentId'] as String);
      if (loseFirstFinalizeResponse && !_finalizeResponseLost) {
        _finalizeResponseLost = true;
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'The server committed but its response was lost.',
        );
      }
      return <String, Object?>{'published': true};
    }
    throw FirebaseFunctionsException(
      code: 'not-found',
      message: 'Unexpected callable $name.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MomentPublishFunctions implements FirebaseFunctions {
  _MomentPublishFunctions({
    required this.momentId,
    required this.storagePath,
    this.failReserveOnce = false,
    this.failFinalizeOnce = false,
    this.hangReserveOnce = false,
    this.hangFinalizeOnce = false,
    this.reserveErrorCode,
  });

  final String momentId;
  final String storagePath;
  final bool failReserveOnce;
  final bool failFinalizeOnce;
  final bool hangReserveOnce;
  final bool hangFinalizeOnce;
  final String? reserveErrorCode;

  final List<Map<String, dynamic>> reservePayloads = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> finalizePayloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _MomentCallable((parameters) => _call(name, parameters));

  Future<Object?> _call(String name, Object? parameters) async {
    final payload = Map<String, dynamic>.from(parameters as Map);
    if (name == 'reserveMomentDraft') {
      reservePayloads.add(payload);
      if (hangReserveOnce && reservePayloads.length == 1) {
        return Completer<Object?>().future;
      }
      if (reserveErrorCode != null) {
        throw FirebaseFunctionsException(
          code: reserveErrorCode!,
          message: 'Configured reserve refusal.',
        );
      }
      if (failReserveOnce && reservePayloads.length == 1) {
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'The response was lost.',
        );
      }
      return <String, Object?>{
        'momentId': momentId,
        'storagePath': storagePath,
      };
    }
    if (name == 'finalizeMomentDraft') {
      finalizePayloads.add(payload);
      if (hangFinalizeOnce && finalizePayloads.length == 1) {
        return Completer<Object?>().future;
      }
      if (failFinalizeOnce && finalizePayloads.length == 1) {
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'The response was lost.',
        );
      }
      return <String, Object?>{'published': true};
    }
    throw FirebaseFunctionsException(
      code: 'not-found',
      message: 'Unexpected callable $name.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MomentCallable implements HttpsCallable {
  _MomentCallable(this.handler);

  final Future<Object?> Function(Object? parameters) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    final result = await handler(parameters);
    return _MomentCallableResult<T>(result as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MomentCallableResult<T> implements HttpsCallableResult<T> {
  _MomentCallableResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AmbiguousCommitStorage implements FirebaseStorage {
  _AmbiguousCommitStorage({required String path, required String generation})
    : reference = _AmbiguousCommitReference(path, generation);

  final _AmbiguousCommitReference reference;

  @override
  Reference ref([String? path]) {
    if (path != reference.fullPath) {
      throw StateError('Unexpected Storage path: $path');
    }
    return reference;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AmbiguousCommitReference implements Reference {
  _AmbiguousCommitReference(this.fullPath, this.generation);

  @override
  final String fullPath;
  final String generation;
  bool committed = false;
  int metadataReads = 0;

  void commit() => committed = true;

  @override
  Future<FullMetadata> getMetadata() async {
    metadataReads += 1;
    if (!committed) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
    }
    return FullMetadata({
      'bucket': 'test-bucket',
      'fullPath': fullPath,
      'name': fullPath.split('/').last,
      'generation': generation,
      'size': 4096,
      'contentType': 'audio/mp4',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AmbiguousCommitAudio extends RecordedAudio {
  int uploadCalls = 0;

  @override
  int get byteLength => 4096;

  @override
  String get contentType => 'audio/mp4';

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    uploadCalls += 1;
    (reference as _AmbiguousCommitReference).commit();
    throw FirebaseException(
      plugin: 'firebase_storage',
      code: 'retry-limit-exceeded',
      message: 'The object committed but the response was lost.',
    );
  }

  @override
  Future<void> discard() async {}
}
