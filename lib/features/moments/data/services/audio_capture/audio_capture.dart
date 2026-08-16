import 'package:record/record.dart';

import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// The one recorder configuration this product uses, on every platform.
///
/// AAC-LC is not a preference — it is the only family that lands inside
/// [kPublishableAudioContentTypes]. On native this yields an `.m4a` file;
/// on web `record_web` maps it onto an MP4/AAC `MediaRecorder` type.
const RecordConfig kVoiceMomentRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 128000,
  sampleRate: 44100,
  numChannels: 1,
  autoGain: true,
  echoCancel: true,
);

/// The slice of `package:record`'s `AudioRecorder` this feature uses.
///
/// Recording hardware cannot be exercised in a widget test, so the flow is
/// written against this interface and the plugin sits behind
/// [RecordPackageBackend]. Tests drive the seam, not the plugin.
abstract class VoiceRecorderBackend {
  Future<bool> hasPermission();

  Future<bool> isEncoderSupported(AudioEncoder encoder);

  Future<void> start(RecordConfig config, {required String path});

  /// Real input level, in dBFS, sampled at [interval]. The recording UI
  /// draws from this rather than an invented pattern — a meter that moves
  /// when the microphone is silent is fabricated audio state.
  Stream<Amplitude> onAmplitudeChanged(Duration interval);

  /// Returns the platform's handle to the finished recording: a file path
  /// on native, a blob object URL on web, or `null` if nothing was captured.
  Future<String?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// The live implementation, delegating to `package:record`.
class RecordPackageBackend implements VoiceRecorderBackend {
  RecordPackageBackend([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) =>
      _recorder.isEncoderSupported(encoder);

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      _recorder.onAmplitudeChanged(interval);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// Whether this platform can produce a Voice Moment at all.
///
/// When it cannot, [reason] and [action] are specific enough to tell the
/// user what is actually wrong — never a generic "Coming soon".
class CaptureSupport {
  const CaptureSupport.supported() : reason = null, action = null;

  const CaptureSupport.unsupported({required String this.reason, this.action});

  final String? reason;
  final String? action;

  bool get isSupported => reason == null;
}

/// The outcome of asking for the microphone.
///
/// `record`'s `hasPermission()` collapses every one of these into a bare
/// `false`, which is why the old flow blamed the user for a missing or
/// busy microphone. Each value here needs a different action, so each is
/// carried separately all the way to the copy the user reads.
enum MicrophoneOutcome {
  granted,

  /// A standing denial. The page cannot re-prompt; only site/app settings
  /// can change it.
  blocked,

  /// The prompt was dismissed rather than answered — asking again works.
  dismissed,

  /// No input device is connected.
  notFound,

  /// A device exists but could not be opened, usually because another
  /// application holds it.
  unavailable,

  /// Something else went wrong acquiring the device.
  failed,
}

/// A microphone request result, carrying copy that is already specific.
class MicrophoneAccess {
  const MicrophoneAccess.granted()
    : outcome = MicrophoneOutcome.granted,
      message = null,
      action = null;

  const MicrophoneAccess.denied({
    required this.outcome,
    required String this.message,
    this.action,
  });

  final MicrophoneOutcome outcome;
  final String? message;
  final String? action;

  bool get isGranted => outcome == MicrophoneOutcome.granted;
}

/// Everything about recording that genuinely differs between web and
/// native: where the bytes go while recording, how the microphone is
/// requested, and how the bytes are collected afterwards. Nothing else in
/// the feature is platform-aware.
abstract class AudioCapture {
  /// Requests microphone access, preserving *why* it was refused.
  ///
  /// Owned by the platform half because only the platform can tell a
  /// standing denial from a dismissed prompt from absent hardware.
  Future<MicrophoneAccess> requestMicrophone(VoiceRecorderBackend backend);

  /// Whether this platform can capture audio in a publishable container.
  /// Checked before the microphone is ever requested, so an unsupported
  /// browser explains itself instead of failing at the permission prompt.
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend);

  /// The `path` argument for a new recording. Native resolves a real
  /// temporary file; web has no filesystem and ignores it.
  Future<String> newRecordingTarget();

  /// Turns the recorder's `stop()` result into uploadable audio.
  ///
  /// Throws a [VoiceRecordingException] when the platform returned nothing
  /// usable.
  Future<RecordedAudio> materialize(String? stopResult);
}
