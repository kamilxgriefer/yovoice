import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// Native capture: the recorder writes an `.m4a` into the temporary
/// directory and the upload streams that file.
///
/// `path_provider` has no web implementation registered in this app, which
/// is exactly why this half is isolated behind a conditional import — the
/// old code called `getTemporaryDirectory()` unconditionally and every web
/// user hit a `MissingPluginException` that a broad `catch` turned into
/// "Could not start recording".
class NativeAudioCapture implements AudioCapture {
  const NativeAudioCapture();

  @override
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend) async {
    final supported = await backend.isEncoderSupported(AudioEncoder.aacLc);
    if (supported) return const CaptureSupport.supported();
    return const CaptureSupport.unsupported(
      reason:
          'This device has no AAC encoder, so it cannot record a Voice '
          'Moment in the format YO Voice publishes.',
    );
  }

  /// Native platforms answer through the OS permission dialog, which
  /// `record` already funnels into a single boolean. There is no
  /// device-level detail to recover here, so a refusal is reported as the
  /// standing denial it is on iOS and Android.
  @override
  Future<MicrophoneAccess> requestMicrophone(
    VoiceRecorderBackend backend,
  ) async {
    if (await backend.hasPermission()) {
      return const MicrophoneAccess.granted();
    }
    return const MicrophoneAccess.denied(
      outcome: MicrophoneOutcome.blocked,
      message: 'YO Voice does not have permission to use your microphone.',
      action: 'Allow the microphone for YO Voice in your device settings.',
    );
  }

  @override
  Future<String> newRecordingTarget() async {
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${directory.path}/voice_moment_$stamp.$kVoiceMomentFileExtension';
  }

  @override
  Future<RecordedAudio> materialize(String? stopResult) async {
    if (stopResult == null || stopResult.isEmpty) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The recording finished without producing any audio.',
        action: 'Record again.',
      );
    }

    final file = File(stopResult);
    if (!await file.exists()) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The recorded audio file could not be found.',
        action: 'Record again.',
      );
    }

    return FileRecordedAudio(file, await file.length());
  }
}

/// A recording held as a file on disk, uploaded with `putFile`.
class FileRecordedAudio extends RecordedAudio {
  FileRecordedAudio(this.file, this.byteLength);

  final File file;

  @override
  final int byteLength;

  @override
  String get contentType => kVoiceMomentContentType;

  @override
  Source get playbackSource =>
      DeviceFileSource(file.path, mimeType: contentType);

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final snapshot = await reference.putFile(file, metadata);
    final snapshotGeneration = snapshot.metadata?.generation?.trim();
    if (snapshotGeneration != null && snapshotGeneration.isNotEmpty) {
      return snapshotGeneration;
    }
    return (await snapshot.ref.getMetadata()).generation ?? '';
  }

  @override
  Future<void> discard() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover file in the OS temporary directory is harmless; failing
      // the flow over it would not be.
    }
  }
}

AudioCapture createAudioCapture() => const NativeAudioCapture();
