/// Resolves [createAudioCapture] to the implementation this build targets.
///
/// Native is the default so the analyzer and the VM test runner both see a
/// real implementation; web builds swap in the `dart:js_interop` one. This
/// is the only place the platform is chosen — everything above it, from
/// `MomentService` to the recording screen, is written once.
library;

export 'audio_capture_io.dart'
    if (dart.library.js_interop) 'audio_capture_web.dart';
