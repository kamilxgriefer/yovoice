import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _normalRoots = <String>[
  'lib/app/app.dart',
  'lib/features/home/presentation',
  'lib/features/messages/presentation',
  'lib/features/friends/presentation',
  'lib/features/moments/presentation',
  'lib/features/clubs/presentation',
  'lib/features/discover/presentation',
  'lib/features/profile/presentation',
  'lib/features/settings/presentation',
  'lib/features/notifications/presentation',
  'lib/features/premium/presentation',
  'lib/features/onboarding/presentation',
  'lib/features/auth/presentation',
  'lib/features/rooms/presentation',
  'lib/features/moderation/presentation/report_content_flow.dart',
  'lib/features/moderation/presentation/widgets/report_reason_sheet.dart',
  'lib/shared/widgets',
];

/// Routes that deliberately own a complete dark media/voice atom and legacy
/// development-only surfaces that are not part of the shipping shell.
const _excludedFiles = <String>{
  'lib/features/auth/presentation/screens/auth_gate.dart',
  'lib/features/auth/presentation/screens/forgot_password_screen.dart',
  'lib/features/auth/presentation/screens/login_screen.dart',
  'lib/features/auth/presentation/screens/register_screen.dart',
  // Shared only by Login/Register, both complete immersive-auth atoms.
  'lib/features/auth/presentation/screens/responsive_auth_screen.dart',
  'lib/features/auth/presentation/screens/totp_challenge_screen.dart',
  'lib/features/auth/presentation/screens/verify_email_screen.dart',
  // Shared only by Login/Register, both complete immersive-auth atoms.
  'lib/features/auth/presentation/widgets/auth_social_button.dart',
  'lib/features/auth/presentation/widgets/check_inbox_sheet.dart',
  'lib/features/auth/presentation/widgets/startup_loading_screen.dart',
  'lib/features/moments/presentation/screens/record_voice_moment_screen.dart',
  'lib/features/moments/presentation/widgets/moment_story_viewer.dart',
  'lib/features/profile/presentation/screens/image_crop_screen.dart',
  'lib/features/rooms/presentation/screens/broadcast_room_screen.dart',
  'lib/features/rooms/presentation/screens/community_voice_room_screen.dart',
  'lib/features/rooms/presentation/screens/create_room_screen.dart',
  'lib/features/rooms/presentation/screens/room_entry_screen.dart',
  'lib/features/rooms/presentation/screens/room_settings_screen.dart',
  'lib/features/rooms/presentation/screens/room_type_selector_screen.dart',
  'lib/features/rooms/presentation/widgets/mini_player/active_room_controls.dart',
  'lib/features/rooms/presentation/widgets/mini_player/active_room_info.dart',
  'lib/features/rooms/presentation/widgets/mini_player/active_room_mini_player.dart',
  'lib/features/rooms/presentation/widgets/mini_player/live_chat_preview.dart',
  // Shared only by complete immersive room routes and their dev preview.
  'lib/features/rooms/presentation/widgets/room_stage.dart',
  'lib/shared/widgets/backgrounds/animated_waves_background.dart',
  'lib/shared/widgets/profile/profile_banner.dart',
};

/// A normal route may duplicate a semantic token only where pixels belong to
/// uploaded media rather than the app theme. Keep the annotation on the same
/// line or immediately above the literal so an exception cannot mask a whole
/// widget/file.
const _allowedLineException = 'semantic-color-guard: uploaded-media';

/// Dark-only container roles are never valid on a normal Pearl-capable route.
/// Text and media-overlay colours are deliberately excluded because an image
/// scrim can legitimately remain dark in both appearances.
const _forbiddenImmersiveRoles = <String>{
  'background',
  'surface',
  'surfaceRaised',
  'border',
  'divider',
  'authSocialBorder',
  'authSocialDisabledBorder',
};

void main() {
  test('AppColors contains only stable brand and status roles', () {
    final source = File('lib/core/theme/app_colors.dart').readAsStringSync();
    for (final legacyRole in const [
      'background',
      'surface',
      'surfaceLight',
      'textPrimary',
      'textSecondary',
      'textHint',
      'navigationInactive',
      'border',
      'divider',
    ]) {
      expect(
        source,
        isNot(contains('static const Color $legacyRole')),
        reason: '$legacyRole belongs to AppPalette/AppImmersiveColors.',
      );
    }
  });

  test('normal Pearl-capable routes do not import the immersive palette', () {
    final violations = <String>[];
    for (final file in _normalFiles()) {
      final source = file.readAsStringSync();
      if (source.contains('core/theme/app_immersive_colors.dart')) {
        violations.add(file.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Immersive-dark imports leaked into normal routes.',
    );
  });

  test('auth social control declares its immersive-only colour contract', () {
    const path =
        'lib/features/auth/presentation/widgets/auth_social_button.dart';
    final source = File(path).readAsStringSync();
    expect(_excludedFiles, contains(path));
    expect(
      source,
      contains('core/theme/app_immersive_colors.dart'),
      reason: 'Login/Register are documented complete immersive-auth atoms.',
    );
    expect(
      source,
      isNot(matches(RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)'))),
      reason: 'The immersive auth control must still use named atom roles.',
    );
  });

  test('source guard inventories every Dark and Pearl semantic token', () {
    final tokens = _semanticTokensByScheme();
    expect(tokens.keys, unorderedEquals(const ['dark', 'light']));
    expect(tokens['dark']!.keys, unorderedEquals(tokens['light']!.keys));
    expect(
      tokens['dark'],
      hasLength(26),
      reason:
          'Every AppPalette role must be declared in both schemes and covered '
          'by the raw-literal source guard.',
    );
  });

  test('normal routes reject copied semantic and immersive surface values', () {
    final violations = <String>[];
    final forbiddenLiterals = <String, Set<String>>{
      ..._semanticTokenLiterals(),
    };
    for (final entry in _immersiveSurfaceLiterals().entries) {
      forbiddenLiterals
          .putIfAbsent(entry.key, () => <String>{})
          .addAll(entry.value);
    }
    for (final file in _normalFiles()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final lineNumber = index + 1;
        final previousLine = index == 0 ? '' : lines[index - 1];
        final line = lines[index];
        final hasGuardAnnotation =
            line.contains('semantic-color-guard:') ||
            previousLine.contains('semantic-color-guard:');
        final hasAllowedException =
            line.contains(_allowedLineException) ||
            previousLine.contains(_allowedLineException);
        if (hasGuardAnnotation && !hasAllowedException) {
          violations.add(
            '${file.path}:$lineNumber uses an unsupported guard exception',
          );
          continue;
        }
        if (hasAllowedException) {
          continue;
        }
        final upperLine = line.toUpperCase();
        for (final entry in forbiddenLiterals.entries) {
          if (upperLine.contains(entry.key)) {
            violations.add(
              '${file.path}:$lineNumber uses ${entry.key} '
              '(${entry.value.join(', ')})',
            );
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Use AppPalette/ColorScheme. Only a line-specific uploaded-media '
          'exception may duplicate a semantic token. Dark-only immersive '
          'container values must stay inside documented immersive atoms.',
    );
  });
}

Map<String, Map<String, String>> _semanticTokensByScheme() {
  final source = File('lib/core/theme/app_palette.dart').readAsStringSync();
  final result = <String, Map<String, String>>{};
  final schemePattern = RegExp(
    r'static const (dark|light) = AppPalette\((.*?)\n  \);',
    dotAll: true,
  );
  final rolePattern = RegExp(r'(\w+):\s+Color\((0x[0-9A-Fa-f]{8})\)');

  for (final schemeMatch in schemePattern.allMatches(source)) {
    final scheme = schemeMatch.group(1)!;
    final body = schemeMatch.group(2)!;
    result[scheme] = {
      for (final roleMatch in rolePattern.allMatches(body))
        roleMatch.group(1)!: roleMatch.group(2)!.toUpperCase(),
    };
  }
  return result;
}

Map<String, Set<String>> _semanticTokenLiterals() {
  final result = <String, Set<String>>{};
  for (final schemeEntry in _semanticTokensByScheme().entries) {
    for (final roleEntry in schemeEntry.value.entries) {
      result
          .putIfAbsent(roleEntry.value, () => <String>{})
          .add('${schemeEntry.key}.${roleEntry.key}');
    }
  }
  return result;
}

Map<String, Set<String>> _immersiveSurfaceLiterals() {
  final source = File(
    'lib/core/theme/app_immersive_colors.dart',
  ).readAsStringSync();
  final rolePattern = RegExp(
    r'static const Color (\w+) = Color\((0x[0-9A-Fa-f]{8})\)',
  );
  final result = <String, Set<String>>{};
  for (final match in rolePattern.allMatches(source)) {
    final role = match.group(1)!;
    if (!_forbiddenImmersiveRoles.contains(role)) continue;
    result
        .putIfAbsent(match.group(2)!.toUpperCase(), () => <String>{})
        .add('immersive.$role');
  }
  expect(
    result.values.expand((roles) => roles).toSet(),
    hasLength(_forbiddenImmersiveRoles.length),
    reason: 'Every dark-only container role must remain covered by the guard.',
  );
  return result;
}

Iterable<File> _normalFiles() sync* {
  final emitted = <String>{};
  for (final rootPath in _normalRoots) {
    final type = FileSystemEntity.typeSync(rootPath);
    if (type == FileSystemEntityType.file) {
      if (!_excludedFiles.contains(rootPath) && emitted.add(rootPath)) {
        yield File(rootPath);
      }
      continue;
    }
    if (type != FileSystemEntityType.directory) continue;
    for (final entity in Directory(rootPath).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_excludedFiles.contains(entity.path) || !emitted.add(entity.path)) {
        continue;
      }
      yield entity;
    }
  }
}
