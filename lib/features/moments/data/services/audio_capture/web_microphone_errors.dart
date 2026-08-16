import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture.dart';

/// Maps a `getUserMedia` rejection onto something the user can act on.
///
/// `record_web`'s `_requestPermission()` catches every rejection and
/// returns `false`, so a missing microphone, a microphone held by another
/// app, and a genuine denial all reached the UI as "your browser blocked
/// microphone access" — blaming the user for a hardware condition and
/// suggesting an action that would not help. This is the discrimination
/// that restores, kept free of `dart:js_interop` so it is unit-testable.
///
/// [permissionStateAfter] is the value of
/// `navigator.permissions.query({name:'microphone'})` read *after* the
/// failure. It is the only reliable way to separate a standing denial from
/// a dismissed prompt: actively blocking leaves the state `denied`, while
/// dismissing the prompt (Esc, or the close button) leaves it at `prompt`.
/// Browsers that do not implement the microphone permission descriptor
/// report `null`, and are treated as the more likely standing denial —
/// its copy names an action that also works for a dismissal.
MicrophoneAccess microphoneAccessForError(
  String errorName, {
  String? permissionStateAfter,
}) {
  switch (errorName) {
    case 'NotAllowedError':
    case 'PermissionDeniedError':
    case 'SecurityError':
      if (permissionStateAfter == 'prompt') {
        return const MicrophoneAccess.denied(
          outcome: MicrophoneOutcome.dismissed,
          message:
              'The microphone request was dismissed, so recording could not '
              'start.',
          action: 'Start recording again, then choose Allow.',
        );
      }
      return blockedMicrophoneAccess();

    case 'NotFoundError':
    case 'DevicesNotFoundError':
    case 'OverconstrainedError':
      return const MicrophoneAccess.denied(
        outcome: MicrophoneOutcome.notFound,
        message: 'No microphone was found on this device.',
        action: 'Connect a microphone, then start recording again.',
      );

    case 'NotReadableError':
    case 'TrackStartError':
      return const MicrophoneAccess.denied(
        outcome: MicrophoneOutcome.unavailable,
        message:
            'Your microphone could not be opened — another app is probably '
            'using it.',
        action: 'Close the other app, then start recording again.',
      );

    default:
      return const MicrophoneAccess.denied(
        outcome: MicrophoneOutcome.failed,
        message: 'YO Voice could not open your microphone.',
        action: 'Reload the page, then start recording again.',
      );
  }
}

/// The standing-denial case.
///
/// The action deliberately avoids naming the address-bar icon: an
/// installed PWA has no address bar, and once a browser has recorded a
/// denial the page can no longer re-prompt, so "try again" would be a
/// suggestion the user cannot act on.
MicrophoneAccess blockedMicrophoneAccess() {
  return const MicrophoneAccess.denied(
    outcome: MicrophoneOutcome.blocked,
    message: 'Microphone access for YO Voice is blocked in this browser.',
    action:
        "Allow the microphone in your browser's site settings for YO Voice, "
        'then reload this page.',
  );
}
