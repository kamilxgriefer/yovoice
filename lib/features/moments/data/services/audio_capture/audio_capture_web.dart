import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/web_mime_negotiation.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// Web capture: `record_web` drives a `MediaRecorder` and hands back a blob
/// object URL. There is no filesystem, so the bytes are read out of the
/// blob and uploaded with `putData`.
class WebAudioCapture implements AudioCapture {
  const WebAudioCapture();

  @override
  Future<CaptureSupport> probeSupport(VoiceRecorderBackend backend) async {
    // A page served over plain HTTP has no `navigator.mediaDevices` at all,
    // so the microphone can never be granted. That is not a denied
    // permission and telling the user to allow the mic would send them
    // hunting through browser settings for a control that cannot help.
    if (!web.window.isSecureContext) {
      return const CaptureSupport.unsupported(
        reason:
            'Browsers only allow microphone access over a secure (https) '
            'connection, and this page was not loaded over one.',
        action: 'Open YO Voice over https and try again.',
      );
    }

    return webCaptureSupportFor(
      resolveWebRecordingMimeType(_isMediaRecorderTypeSupported),
    );
  }

  static bool _isMediaRecorderTypeSupported(String type) {
    try {
      return web.MediaRecorder.isTypeSupported(type);
    } catch (_) {
      // No MediaRecorder on this browser at all.
      return false;
    }
  }

  /// `record_web` ignores the path, but the plugin API requires one and the
  /// extension keeps the intent readable in logs.
  @override
  Future<String> newRecordingTarget() async =>
      'voice_moment.$kVoiceMomentFileExtension';

  @override
  Future<RecordedAudio> materialize(String? stopResult) async {
    if (stopResult == null || stopResult.isEmpty) {
      throw const VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The browser finished recording without producing any audio.',
        action: 'Record again.',
      );
    }

    final web.Blob blob;
    try {
      final response = await web.window.fetch(stopResult.toJS).toDart;
      blob = await response.blob().toDart;
    } catch (error) {
      web.URL.revokeObjectURL(stopResult);
      throw VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The finished recording could not be read back from the browser.',
        action: 'Record again.',
        cause: error,
      );
    }

    // The blob carries the type `MediaRecorder` actually negotiated, which
    // is the ground truth for what was captured — the pre-flight probe is
    // only a prediction of it.
    final blobType = blob.type;
    if (!isPublishableAudioContentType(blobType)) {
      web.URL.revokeObjectURL(stopResult);
      throw VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'This browser recorded as '
        '${blobType.isEmpty ? 'an unknown format' : normalizeAudioContentType(blobType)}, '
        'which YO Voice cannot publish.',
        action: 'Open YO Voice in Chrome, Edge or Safari to record.',
      );
    }

    final Uint8List bytes;
    try {
      final buffer = await blob.arrayBuffer().toDart;
      bytes = buffer.toDart.asUint8List();
    } catch (error) {
      throw VoiceRecordingException(
        VoiceRecordingProblem.recordingUnusable,
        'The finished recording could not be read back from the browser.',
        action: 'Record again.',
        cause: error,
      );
    } finally {
      // The bytes are in Dart's heap now; holding the object URL would leak
      // the blob for the lifetime of the document.
      web.URL.revokeObjectURL(stopResult);
    }

    return BytesRecordedAudio(bytes, normalizeAudioContentType(blobType));
  }
}

/// A recording held in memory, uploaded with `putData`.
class BytesRecordedAudio extends RecordedAudio {
  BytesRecordedAudio(this.bytes, this.contentType);

  final Uint8List bytes;

  @override
  final String contentType;

  @override
  int get byteLength => bytes.lengthInBytes;

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final snapshot = await reference.putData(bytes, metadata);
    final stored = await snapshot.ref.getMetadata();
    return stored.generation ?? '';
  }

  @override
  Future<void> discard() async {
    // Nothing retained outside the Dart heap: the object URL is revoked in
    // `materialize`, and the bytes go with this object.
  }
}

AudioCapture createAudioCapture() => const WebAudioCapture();
