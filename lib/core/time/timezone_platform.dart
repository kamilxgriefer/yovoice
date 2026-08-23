/// Resolves [readPlatformIanaTimezone] to the implementation this build
/// targets.
///
/// Native is the default so the analyzer and the VM test runner both see a
/// real implementation; web builds swap in the `dart:js_interop` one. Same
/// shape, and the same reasoning, as
/// `features/moments/data/services/audio_capture/audio_capture_platform.dart`.
library;

export 'timezone_io.dart' if (dart.library.js_interop) 'timezone_web.dart';
