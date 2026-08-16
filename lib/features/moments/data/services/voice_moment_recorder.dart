import 'package:flutter/services.dart' show MissingPluginException;
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture_platform.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// The recording contract, re-exported so callers depend on one entry point
/// rather than reaching into the platform-split files.
export 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart'
    show CaptureSupport, VoiceRecorderBackend, kVoiceMomentRecordConfig;

/// Drives one Voice Moment recording from support check to uploadable
/// audio, identically on every platform.
///
/// The platform difference lives entirely in the injected [AudioCapture]:
/// native writes a temporary file, web collects blob bytes. This class owns
/// the ordering and the failure taxonomy, so a browser that cannot record,
/// a microphone the user blocked, and a recorder that broke mid-capture
/// stay three distinguishable outcomes instead of one snackbar.
class VoiceMomentRecorder {
  VoiceMomentRecorder({
    VoiceRecorderBackend? backend,
    AudioCapture? capture,
    Stopwatch? clock,
  }) : _backend = backend ?? RecordPackageBackend(),
       _capture = capture ?? createAudioCapture(),
       _clock = clock ?? Stopwatch();

  final VoiceRecorderBackend _backend;
  final AudioCapture _capture;

  /// Measures capture length off the wall clock rather than by counting UI
  /// ticks, so a dropped frame cannot shorten the duration this recording
  /// is published with. Injectable because a widget test's clock is fake.
  final Stopwatch _clock;

  CaptureSupport? _support;
  bool _recording = false;
  bool _disposed = false;

  bool get isRecording => _recording;

  /// How long the current or just-finished recording ran.
  Duration get elapsed => _clock.elapsed;

  /// The value to publish, inside the 1–60 s window the callables enforce.
  int get durationSeconds => elapsed.inSeconds.clamp(1, 60);

  /// Measured input level while recording. Normalized to 0..1 by the UI;
  /// the raw stream stays in dBFS so the mapping is testable.
  Stream<Amplitude> amplitudes({
    Duration interval = const Duration(milliseconds: 120),
  }) => _backend.onAmplitudeChanged(interval);

  /// Maps a dBFS reading onto the 0..1 range a level meter draws.
  ///
  /// [floorDb] is the quietest level treated as silence; `record` reports
  /// -160 dBFS for a fully silent input, which would flatten every visible
  /// bar to zero if used directly as the floor.
  static double normalizeAmplitude(double dbfs, {double floorDb = -45}) {
    if (dbfs.isNaN || !dbfs.isFinite) return 0;
    if (dbfs <= floorDb) return 0;
    if (dbfs >= 0) return 1;
    return (dbfs - floorDb) / -floorDb;
  }

  /// Whether this platform can record a publishable Voice Moment.
  ///
  /// Deliberately answered before the microphone is requested: asking a
  /// browser that could never publish the result for microphone access
  /// wastes a permission prompt and produces a misleading failure.
  Future<CaptureSupport> checkSupport() async {
    final cached = _support;
    if (cached != null) return cached;

    CaptureSupport resolved;
    try {
      resolved = await _capture.probeSupport(_backend);
    } on MissingPluginException {
      resolved = const CaptureSupport.unsupported(
        reason:
            'Voice recording is not available in this build of YO Voice.',
        action: 'Try the YO Voice web app in Chrome, Edge or Safari.',
      );
    } catch (error) {
      resolved = const CaptureSupport.unsupported(
        reason: 'YO Voice could not reach an audio recorder on this device.',
        action: 'Reload the page and try again.',
      );
    }
    return _support = resolved;
  }

  /// Requests the microphone and begins recording.
  ///
  /// Throws a [VoiceRecordingException] whose `problem` says which of the
  /// three distinct failures happened.
  Future<void> start() async {
    if (_recording) return;

    final support = await checkSupport();
    if (!support.isSupported) {
      throw VoiceRecordingException(
        VoiceRecordingProblem.platformCannotRecord,
        support.reason!,
        action: support.action,
      );
    }

    final bool permitted;
    try {
      permitted = await _backend.hasPermission();
    } on MissingPluginException catch (error) {
      throw VoiceRecordingException(
        VoiceRecordingProblem.platformCannotRecord,
        'Voice recording is not available in this build of YO Voice.',
        cause: error,
      );
    } catch (error) {
      throw VoiceRecordingException(
        VoiceRecordingProblem.microphoneBlocked,
        'YO Voice could not get access to your microphone.',
        action: 'Check your microphone permission and try again.',
        cause: error,
      );
    }

    if (!permitted) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.microphoneBlocked,
        'Your browser blocked microphone access for YO Voice.',
        action:
            'Allow the microphone for this site, then start recording again.',
      );
    }

    final String target;
    try {
      target = await _capture.newRecordingTarget();
    } on MissingPluginException catch (error) {
      // The original bug, now named instead of swallowed: this is exactly
      // where `getTemporaryDirectory()` threw on every web session.
      throw VoiceRecordingException(
        VoiceRecordingProblem.platformCannotRecord,
        'YO Voice could not prepare somewhere to store this recording on '
        'this platform.',
        cause: error,
      );
    }

    try {
      await _backend.start(kVoiceMomentRecordConfig, path: target);
    } catch (error) {
      throw VoiceRecordingException(
        VoiceRecordingProblem.captureFailed,
        'Recording could not be started.',
        action: 'Check that no other app is using your microphone.',
        cause: error,
      );
    }

    _clock
      ..reset()
      ..start();
    _recording = true;
  }

  /// Ends the recording and returns audio that is already known to satisfy
  /// the Storage rules' type and size constraints.
  Future<RecordedAudio> stop() async {
    if (!_recording) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.captureFailed,
        'There is no recording in progress.',
      );
    }

    _clock.stop();
    final String? handle;
    try {
      handle = await _backend.stop();
    } catch (error) {
      _recording = false;
      throw VoiceRecordingException(
        VoiceRecordingProblem.captureFailed,
        'Recording could not be finished.',
        action: 'Record again.',
        cause: error,
      );
    }
    _recording = false;

    final audio = await _capture.materialize(handle);
    final problem = validateRecordedAudio(audio);
    if (problem != null) {
      await audio.discard();
      throw problem;
    }
    return audio;
  }

  /// Abandons an in-progress recording without producing audio.
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    _clock
      ..stop()
      ..reset();
    try {
      await _backend.cancel();
    } catch (_) {
      // Cancelling is best-effort cleanup; surfacing it would replace a
      // user-initiated action with an error they cannot act on.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _recording = false;
    try {
      await _backend.dispose();
    } catch (_) {
      // Same reasoning as `cancel`.
    }
  }
}
