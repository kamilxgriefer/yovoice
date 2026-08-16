import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude, AudioEncoder, RecordConfig;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/web_mime_negotiation.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';

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
      expect(validateRecordedAudio(_FakeRecordedAudio()), isNull);
    });

    test('refuses a container the backend cannot accept', () {
      final problem = validateRecordedAudio(
        _FakeRecordedAudio(contentType: 'audio/webm'),
      );
      expect(problem?.problem, VoiceRecordingProblem.recordingUnusable);
      expect(problem?.message, contains('audio/webm'));
    });

    test('refuses payloads outside the Storage rules byte bounds', () {
      // storage.rules: size >= 1024 && size <= 12 MiB.
      expect(
        validateRecordedAudio(_FakeRecordedAudio(byteLength: 1023))?.problem,
        VoiceRecordingProblem.recordingUnusable,
      );
      expect(validateRecordedAudio(_FakeRecordedAudio(byteLength: 1024)), isNull);
      expect(
        validateRecordedAudio(
          _FakeRecordedAudio(byteLength: 12 * 1024 * 1024 + 1),
        )?.problem,
        VoiceRecordingProblem.recordingUnusable,
      );
    });
  });

  group('VoiceMomentRecorder failure taxonomy', () {
    test('an unsupported platform never asks for the microphone', () async {
      final backend = _FakeBackend();
      final capture = _FakeCapture()
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
      final capture = _FakeCapture();
      final recorder = VoiceMomentRecorder(
        backend: _FakeBackend(),
        capture: capture,
      );
      await recorder.checkSupport();
      await recorder.checkSupport();
      expect(capture.probeCalls, 1);
    });

    test('a refused microphone is microphoneBlocked, not a generic failure',
        () async {
      final recorder = VoiceMomentRecorder(
        backend: _FakeBackend()..permission = false,
        capture: _FakeCapture(),
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
    });

    test(
      'a MissingPluginException preparing storage is named, not swallowed',
      () async {
        // The original production bug, verbatim: path_provider has no web
        // implementation, `getTemporaryDirectory()` threw this, and a broad
        // catch reported "Could not start recording".
        final recorder = VoiceMomentRecorder(
          backend: _FakeBackend(),
          capture: _FakeCapture()
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
        backend: _FakeBackend()..startError = StateError('device busy'),
        capture: _FakeCapture(),
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

    test('a missing recorder plugin degrades to an honest unsupported state',
        () async {
      final recorder = VoiceMomentRecorder(
        backend: _FakeBackend(),
        capture: _FakeCapture()
          ..probeError = MissingPluginException('no recorder'),
      );

      final support = await recorder.checkSupport();
      expect(support.isSupported, false);
      expect(support.reason, isNot(contains('Coming soon')));
      expect(support.reason, contains('not available'));
    });

    test('a normal capture yields uploadable audio', () async {
      final audio = _FakeRecordedAudio();
      final backend = _FakeBackend();
      final recorder = VoiceMomentRecorder(
        backend: backend,
        capture: _FakeCapture()..result = audio,
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
      final audio = _FakeRecordedAudio(contentType: 'audio/webm');
      final recorder = VoiceMomentRecorder(
        backend: _FakeBackend(),
        capture: _FakeCapture()..result = audio,
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
      final audio = _FakeRecordedAudio();

      final momentId = await service.publishRecordedMoment(
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

    test('refuses an unpublishable recording before uploading anything',
        () async {
      // Uploading it would be rejected by the rules, leaving a reserved
      // draft that can never finalize.
      final audio = _FakeRecordedAudio(contentType: 'audio/webm');

      await expectLater(
        service.publishRecordedMoment(
          audio: audio,
          durationSeconds: 7,
          caption: 'Hello',
        ),
        throwsA(isA<VoiceRecordingException>()),
      );
      expect(audio.uploadCalls, 0);
    });

    test('a voice reply carries the third metadata key its rule requires',
        () async {
      await firestore.collection('voiceMoments').doc('parent-moment').set({
        'authorId': 'someone-else',
        'isPublished': true,
      });
      final audio = _FakeRecordedAudio();

      final commentId = await service.publishRecordedMoment(
        audio: audio,
        durationSeconds: 5,
        caption: 'Replying',
        replyToMomentId: 'parent-moment',
      );

      // storage.rules /voice_replies/{userId}/{momentId}/{fileName}
      expect(
        audio.uploadedPath,
        'voice_replies/$uid/parent-moment/$commentId'
        '.$kVoiceMomentFileExtension',
      );
      expect(audio.uploadedMetadata!.customMetadata, {
        'authorId': uid,
        'momentId': 'parent-moment',
        'commentId': commentId,
      });
      expect(audio.uploadedMetadata!.contentType, 'audio/mp4');
    });
  });
}

// --------------------------------------------------------------- test doubles

class _FakeRecordedAudio extends RecordedAudio {
  _FakeRecordedAudio({
    this.contentType = kVoiceMomentContentType,
    this.byteLength = 4096,
  });

  @override
  final String contentType;

  @override
  final int byteLength;

  int uploadCalls = 0;
  String? uploadedPath;
  SettableMetadata? uploadedMetadata;
  bool discarded = false;

  @override
  Future<String> uploadTo(Reference reference, SettableMetadata metadata) async {
    uploadCalls++;
    uploadedPath = reference.fullPath;
    uploadedMetadata = metadata;
    // Stand in for the platform upload against the real Reference, so the
    // service's follow-up calls (download URL, cleanup) behave as they do
    // in production rather than against a hole in the double.
    await reference.putData(Uint8List(byteLength), metadata);
    return '1700000000000001';
  }

  @override
  Future<void> discard() async {
    discarded = true;
  }
}

class _FakeBackend implements VoiceRecorderBackend {
  bool encoderSupported = true;
  bool permission = true;
  Object? startError;
  Object? stopError;
  String? stopResult = 'handle';

  int permissionCalls = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  RecordConfig? startedConfig;

  @override
  Future<bool> hasPermission() async {
    permissionCalls++;
    return permission;
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async =>
      encoderSupported;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls++;
    startedConfig = config;
    if (startError != null) throw startError!;
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream<Amplitude>.empty();

  @override
  Future<String?> stop() async {
    if (stopError != null) throw stopError!;
    return stopResult;
  }

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

class _FakeCapture implements AudioCapture {
  CaptureSupport support = const CaptureSupport.supported();
  Object? probeError;
  Object? targetError;
  Object? materializeError;
  RecordedAudio? result;
  int probeCalls = 0;

  @override
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend) async {
    probeCalls++;
    if (probeError != null) throw probeError!;
    return support;
  }

  @override
  Future<String> newRecordingTarget() async {
    if (targetError != null) throw targetError!;
    return 'target.m4a';
  }

  @override
  Future<RecordedAudio> materialize(String? stopResult) async {
    if (materializeError != null) throw materializeError!;
    return result ?? _FakeRecordedAudio();
  }
}
