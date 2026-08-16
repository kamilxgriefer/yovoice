// Shared test doubles for the Voice Moment recording seam.
//
// Not a test file (no `_test.dart` suffix), so `flutter test` imports it
// without trying to run it.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:record/record.dart' show Amplitude, AudioEncoder, RecordConfig;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// A finished recording that records what it was asked to upload.
class FakeRecordedAudio extends RecordedAudio {
  FakeRecordedAudio({
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
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
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

/// Stands in for `package:record`'s `AudioRecorder`.
class FakeRecorderBackend implements VoiceRecorderBackend {
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

  final StreamController<Amplitude> amplitudes =
      StreamController<Amplitude>.broadcast();

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
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => amplitudes.stream;

  @override
  Future<String?> stop() async {
    if (stopError != null) throw stopError!;
    return stopResult;
  }

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await amplitudes.close();
  }
}

/// A stopwatch the test drives directly.
///
/// `flutter_test`'s fake clock advances timers but not `Stopwatch`, which
/// reads real elapsed time, so recording length has to be injected for the
/// reviewing and publishing states to be reachable deterministically.
class FakeStopwatch implements Stopwatch {
  Duration value = Duration.zero;
  bool _running = false;

  @override
  Duration get elapsed => value;

  @override
  bool get isRunning => _running;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset() => value = Duration.zero;

  @override
  int get frequency => 1000000;

  @override
  int get elapsedTicks => value.inMicroseconds;

  @override
  int get elapsedMicroseconds => value.inMicroseconds;

  @override
  int get elapsedMilliseconds => value.inMilliseconds;
}

/// Stands in for the platform byte-acquisition half.
class FakeAudioCapture implements AudioCapture {
  CaptureSupport support = const CaptureSupport.supported();
  Object? probeError;
  Object? targetError;
  Object? materializeError;
  Object? microphoneError;
  RecordedAudio? result;
  int probeCalls = 0;
  int microphoneCalls = 0;

  /// Defaults to granted; set an outcome to exercise a specific refusal.
  MicrophoneAccess microphone = const MicrophoneAccess.granted();

  /// When set, the request hangs on it — a browser that never answers the
  /// permission prompt.
  Completer<MicrophoneAccess>? microphoneGate;

  @override
  Future<MicrophoneAccess> requestMicrophone(
    VoiceRecorderBackend backend,
  ) async {
    microphoneCalls++;
    if (microphoneError != null) throw microphoneError!;
    if (microphoneGate != null) return microphoneGate!.future;
    // Mirrors the real implementations, which all consult the backend's
    // permission state before deciding.
    if (microphone.isGranted && !await backend.hasPermission()) {
      return const MicrophoneAccess.denied(
        outcome: MicrophoneOutcome.blocked,
        message: 'Microphone access for YO Voice is blocked in this browser.',
        action: "Allow the microphone in your browser's site settings for "
            'YO Voice, then reload this page.',
      );
    }
    return microphone;
  }

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
    return result ?? FakeRecordedAudio();
  }
}

/// A `MomentService` whose publish call can be held open or failed on
/// demand, so the uploading and failed states are reachable in a widget
/// test without a Firebase project.
class StubMomentService extends MomentService {
  StubMomentService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'stub-uid'),
        ),
        storage: MockFirebaseStorage(),
      );

  /// When set, `publishRecordedMoment` waits on it — the uploading state.
  Completer<void>? gate;

  /// When set, `publishRecordedMoment` throws it.
  Object? failure;

  int publishCalls = 0;
  RecordedAudio? publishedAudio;
  int? publishedDuration;
  String? publishedCaption;

  @override
  Future<String> publishRecordedMoment({
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
  }) async {
    publishCalls++;
    publishedAudio = audio;
    publishedDuration = durationSeconds;
    publishedCaption = caption;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return 'published-moment-id';
  }
}
