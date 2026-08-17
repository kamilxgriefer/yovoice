import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/web_microphone_errors.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/web_mime_negotiation.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// `navigator.permissions.query()` takes a descriptor object; `package:web`
/// types the argument as an opaque `JSObject`.
extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({String name});
}

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

  /// Asks for the microphone directly rather than through
  /// `record.hasPermission()`.
  ///
  /// The plugin's implementation catches every `getUserMedia` rejection and
  /// returns `false`, which erases the difference between a denial, a
  /// dismissed prompt, absent hardware and a device another app is
  /// holding. Calling it here keeps `DOMException.name`, at the cost of one
  /// extra `getUserMedia` — the same count as before, since the plugin's
  /// own probe is what this replaces. The tracks are stopped immediately;
  /// `record_web.start()` reacquires without prompting again.
  @override
  Future<MicrophoneAccess> requestMicrophone(
    VoiceRecorderBackend backend,
  ) async {
    // A standing denial is worth catching before the call, because
    // `getUserMedia` rejects instantly and indistinguishably in that case.
    if (await _permissionState() == 'denied') {
      return blockedMicrophoneAccess();
    }

    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      for (final track in stream.getAudioTracks().toDart) {
        track.stop();
      }
      return const MicrophoneAccess.granted();
    } catch (error) {
      return microphoneAccessForError(
        _errorName(error),
        permissionStateAfter: await _permissionState(),
      );
    }
  }

  /// `granted` / `denied` / `prompt`, or `null` where the browser does not
  /// implement the microphone permission descriptor (Firefox does not).
  static Future<String?> _permissionState() async {
    try {
      final status = await web.window.navigator.permissions
          .query(_PermissionDescriptor(name: 'microphone'))
          .toDart;
      return status.state;
    } catch (_) {
      return null;
    }
  }

  /// Recovers `DOMException.name` from a rejected promise.
  ///
  /// Layered because how a JS rejection surfaces in Dart depends on the
  /// compiler: usually a `JSObject` carrying `name`, but the string form is
  /// kept as a fallback so an unexpected shape still classifies rather than
  /// collapsing into the generic case.
  static String _errorName(Object error) {
    try {
      final object = error as JSObject;
      if (object.has('name')) {
        final value = object.getProperty<JSAny?>('name'.toJS);
        if (value != null) {
          final name = (value as JSString).toDart;
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {
      // Not a JS object, or no readable `name` — fall through.
    }

    const known = <String>[
      'NotAllowedError',
      'PermissionDeniedError',
      'SecurityError',
      'NotFoundError',
      'DevicesNotFoundError',
      'OverconstrainedError',
      'NotReadableError',
      'TrackStartError',
      'AbortError',
    ];
    final text = error.toString();
    for (final candidate in known) {
      if (text.contains(candidate)) return candidate;
    }
    return '';
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

    // Keep the browser's native Blob all the way to Firebase Storage. The
    // previous Blob -> ArrayBuffer -> Dart Uint8List -> JS Uint8Array round
    // trip was the only untested production seam and real mobile-web uploads
    // stopped before finalizeMomentDraft. `putBlob` avoids that conversion,
    // preserves the exact bytes MediaRecorder produced and is resumable by
    // the Firebase Web SDK.
    web.URL.revokeObjectURL(stopResult);
    return BlobRecordedAudio(blob, normalizeAudioContentType(blobType));
  }
}

/// A recording held as the browser-native Blob MediaRecorder produced.
class BlobRecordedAudio extends RecordedAudio {
  BlobRecordedAudio(this.blob, this.contentType);

  final web.Blob blob;

  @override
  final String contentType;

  @override
  int get byteLength => blob.size;

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final snapshot = await reference.putBlob(blob, metadata);
    final snapshotGeneration = snapshot.metadata?.generation?.trim();
    if (snapshotGeneration != null && snapshotGeneration.isNotEmpty) {
      return snapshotGeneration;
    }
    // TaskSnapshotWeb maps the JS UploadTaskSnapshot metadata (including its
    // generation) into FullMetadata. Keep this defensive read for alternate
    // implementations and old emulators that omit it from the snapshot.
    return (await snapshot.ref.getMetadata()).generation ?? '';
  }

  @override
  Future<void> discard() async {
    // Nothing retained outside the Dart heap: the object URL is revoked in
    // `materialize`, and the bytes go with this object.
  }
}

AudioCapture createAudioCapture() => const WebAudioCapture();
