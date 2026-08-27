import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// The upload contract for Voice Moment audio, shared by every platform.
///
/// Both `storage.rules` (`isAllowedAudioType`) and the deployed Stage B
/// callables (`AUDIO_TYPES` in `functions/moments/integrity.js`) accept
/// exactly these content types, and the server-issued storage path always
/// ends in `.m4a`. A recording that cannot be described by one of these
/// types is not publishable — uploading it anyway would be rejected by the
/// Storage rules, and a draft that never finalizes is worse than an honest
/// refusal, so the client checks agreement before it ever uploads.
const Set<String> kPublishableAudioContentTypes = <String>{
  'audio/mp4',
  'audio/m4a',
  'audio/x-m4a',
};

/// The extension the server bakes into every reserved storage path.
const String kVoiceMomentFileExtension = 'm4a';

/// The content type this client declares for the MP4/AAC it records.
///
/// Browsers report the negotiated type with codec parameters attached
/// (`audio/mp4;codecs=mp4a.40.2`); Storage rules compare the declared
/// content type against a bare set, so the parameters must be dropped
/// before the upload declares it.
const String kVoiceMomentContentType = 'audio/mp4';

/// Storage rules reject anything under 1 KiB (`isValidAudioPayload`), and
/// both the rules and the callables reject anything over 12 MiB.
const int kMinPublishableAudioBytes = 1024;
const int kMaxPublishableAudioBytes = 12 * 1024 * 1024;

/// Strips codec parameters and casing from a MIME type so it can be
/// compared against the sets the backend enforces.
///
/// `'audio/mp4;codecs=mp4a.40.2'` and `'AUDIO/MP4; codecs=mp4a'` both
/// normalize to `'audio/mp4'`.
String normalizeAudioContentType(String rawContentType) {
  final separatorIndex = rawContentType.indexOf(';');
  final base = separatorIndex == -1
      ? rawContentType
      : rawContentType.substring(0, separatorIndex);
  return base.trim().toLowerCase();
}

/// Whether [rawContentType] normalizes to something the Storage rules and
/// the finalize callable will both accept.
bool isPublishableAudioContentType(String rawContentType) {
  return kPublishableAudioContentTypes.contains(
    normalizeAudioContentType(rawContentType),
  );
}

/// Why a finished recording cannot be published, or why recording could not
/// start. Each value maps to a different thing the user has to do, which is
/// the whole reason the taxonomy exists: "your browser blocked the
/// microphone" and "this browser cannot record" need different actions, and
/// collapsing them into one snackbar is what hid this bug in production.
enum VoiceRecordingProblem {
  /// This platform has no encoder that produces a publishable recording.
  /// Nothing the user does in this browser will help; they need another one.
  platformCannotRecord,

  /// The microphone was refused by a standing permission decision — the
  /// site or app permission is denied and the page cannot re-prompt.
  microphoneBlocked,

  /// The permission prompt was dismissed rather than answered. Unlike
  /// [microphoneBlocked] this is recoverable in place: asking again works.
  microphonePromptDismissed,

  /// No microphone is connected. Nothing about permissions will help, so
  /// telling the user to allow access would send them nowhere.
  microphoneNotFound,

  /// A microphone exists but the OS would not hand it over — usually
  /// another application is holding it.
  microphoneUnavailable,

  /// The recorder itself failed while capturing.
  captureFailed,

  /// Capture finished but produced something unusable: no bytes, too few
  /// bytes to be real audio, or a container this backend cannot accept.
  recordingUnusable,

  /// The recording was fine; publishing it failed.
  uploadFailed,
}

/// A failure carrying copy that is already safe to show a user.
///
/// [message] states what happened, [action] states what to do about it.
class VoiceRecordingException implements Exception {
  const VoiceRecordingException(
    this.problem,
    this.message, {
    this.action,
    this.cause,
  });

  final VoiceRecordingProblem problem;

  /// Specific, user-facing description. Never an exception type or code.
  final String message;

  /// What the user can actually do next, when there is something.
  final String? action;

  /// The underlying error, kept for logging — never rendered.
  final Object? cause;

  @override
  String toString() => 'VoiceRecordingException(${problem.name}): $message';
}

/// A finished recording in whatever form this platform produced it, plus
/// the one operation the publish flow needs from it.
///
/// This is the platform seam. Native holds a file on disk and uploads it
/// with `putFile`; web keeps the browser-native Blob and uploads it with
/// `putBlob`. Everything above this — reservation, metadata,
/// finalization, error handling, UI — is identical on both.
abstract class RecordedAudio {
  const RecordedAudio();

  /// The normalized content type to declare on the upload. Always one of
  /// [kPublishableAudioContentTypes].
  String get contentType;

  /// Size of the recording in bytes, known before the upload starts.
  int get byteLength;

  /// A device-local source for pre-publish playback.
  ///
  /// Native recordings resolve to their temporary file and web recordings
  /// resolve to an object URL owned by this object. Reading this property must
  /// not upload the recording.
  Source get playbackSource => throw UnsupportedError(
    '${runtimeType.toString()} does not expose a local playback source.',
  );

  /// Uploads this recording to [reference] with [metadata] and returns the
  /// stored object's generation, which `finalizeMomentDraft` requires.
  Future<String> uploadTo(Reference reference, SettableMetadata metadata);

  /// Releases whatever this recording is holding — a temporary file on
  /// native, an object URL on web. Safe to call more than once.
  Future<void> discard();
}

/// Validates a finished recording against the bounds the backend enforces,
/// before an upload that would be rejected is ever attempted.
///
/// Returns `null` when the recording is publishable.
VoiceRecordingException? validateRecordedAudio(RecordedAudio audio) {
  if (!isPublishableAudioContentType(audio.contentType)) {
    return VoiceRecordingException(
      VoiceRecordingProblem.recordingUnusable,
      'This recording came back as ${normalizeAudioContentType(audio.contentType)}, '
      'which YO Voice cannot publish yet.',
      action: 'Try recording in Chrome, Edge or Safari.',
    );
  }
  if (audio.byteLength < kMinPublishableAudioBytes) {
    return const VoiceRecordingException(
      VoiceRecordingProblem.recordingUnusable,
      'That recording came back almost empty, so there is nothing to publish.',
      action: 'Record again and speak for at least a second.',
    );
  }
  if (audio.byteLength > kMaxPublishableAudioBytes) {
    return const VoiceRecordingException(
      VoiceRecordingProblem.recordingUnusable,
      'That recording is larger than the 12 MB limit for a Voice Moment.',
      action: 'Record a shorter Voice Moment.',
    );
  }
  return null;
}
