import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Material icons glyphs for tests that measure or capture
/// rendered UI.
///
/// The font ships inside the Flutter SDK, not with the app, so its path
/// depends on where Flutter is installed. Hardcoding one machine's path
/// (`/opt/homebrew/...`) made three suites fail in CI on 2026-09-11: the file
/// does not exist on the Linux runner, `readAsBytesSync` threw inside
/// `setUpAll`, and every case in those files was reported as failed.
///
/// Resolution order: `FLUTTER_ROOT` (exported by `flutter test`), the SDK that
/// owns the running Dart binary, then the historical Homebrew path. When none
/// of them exists the loader returns quietly — icons then draw as the default
/// test glyph, which only matters to tests that assert on icon pixels.
Future<void> loadMaterialIconsFont() async {
  final file = _resolveMaterialIconsFont();
  if (file == null) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

/// The resolved font file, or null when this machine has none.
File? _resolveMaterialIconsFont() {
  const relative =
      'bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf';
  final roots = <String?>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?
        when root.isNotEmpty)
      root,
    _sdkRootOfRunningDart(),
    '/opt/homebrew/share/flutter',
  ].whereType<String>();
  for (final root in roots) {
    final candidate = File('$root/$relative');
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

/// `<sdk>/bin/cache/dart-sdk/bin/dart` -> `<sdk>`.
String? _sdkRootOfRunningDart() {
  final parts = Platform.resolvedExecutable.split('/');
  final index = parts.lastIndexOf('bin');
  if (index < 4) return null;
  return parts.sublist(0, index - 3).join('/');
}
