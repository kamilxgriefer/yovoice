import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// The MIME types `record_web` tries, in its own order, for
/// `AudioEncoder.aacLc` — mirrored from `record_web/src/mime_types.dart` at
/// the version this app pins (record 7.1.1 / record_web 2.1.2).
///
/// The browser takes the first of these it supports, and that choice
/// decides whether the recording is publishable at all: the first two
/// normalize to `audio/mp4`, but `audio/aac` is not in
/// [kPublishableAudioContentTypes], so a browser supporting only the last
/// entry could record and still produce nothing YO Voice may upload.
///
/// If `record_web` is upgraded, re-check this list against its
/// `mimeTypes[AudioEncoder.aacLc]`; the support answer this screen gives
/// its users is only as accurate as this mirror.
const List<String> kWebAacMimeCandidates = <String>[
  'audio/mp4;codecs=mp4a',
  'audio/mp4;codecs=mp4a.40.2',
  'audio/aac',
];

/// Resolves the MIME type `record_web` would negotiate, given a predicate
/// standing in for `MediaRecorder.isTypeSupported`.
///
/// Kept free of `dart:js_interop` so the selection rule is unit-testable on
/// the VM; only the predicate is web-only.
String? resolveWebRecordingMimeType(bool Function(String type) isSupported) {
  for (final candidate in kWebAacMimeCandidates) {
    if (isSupported(candidate)) return candidate;
  }
  return null;
}

/// Turns the negotiated type into a support verdict.
///
/// Three genuinely different outcomes, because each needs something
/// different from the user.
CaptureSupport webCaptureSupportFor(String? negotiatedMimeType) {
  if (negotiatedMimeType == null) {
    return const CaptureSupport.unsupported(
      reason:
          'This browser cannot record MP4/AAC audio, which is the only '
          'format YO Voice can publish a Voice Moment in.',
      action: 'Open YO Voice in Chrome, Edge or Safari to record.',
    );
  }
  if (!isPublishableAudioContentType(negotiatedMimeType)) {
    return CaptureSupport.unsupported(
      reason:
          'This browser would record as '
          '${normalizeAudioContentType(negotiatedMimeType)}, which YO Voice '
          'cannot publish yet.',
      action: 'Open YO Voice in Chrome, Edge or Safari to record.',
    );
  }
  return const CaptureSupport.supported();
}
