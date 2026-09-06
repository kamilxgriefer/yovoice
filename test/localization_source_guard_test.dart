import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';

const _rawCopyPatterns = <String, String>{
  'text': r'''\b(?:Text|SelectableText)\s*\(\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'tooltip': r'''\btooltip\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'semantic label': r'''\bsemanticLabel\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'input hint': r'''\bhintText\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'action label': r'''\bactionLabel\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'sheet label': r'''\bsheetLabel\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
  'message': r'''\bmessage\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
};

const _appShellRawCopyPatterns = <String, String>{
  'snackbar action label':
      r'''\bSnackBarAction\s*\([\s\S]{0,500}?\blabel\s*:\s*(['"])([A-Za-z][^'"\r\n]*)\1''',
};

/// Product marks do not change with locale and therefore do not belong in a
/// translation catalog. Everything else must cross the localization boundary.
const _localeInvariantMarks = <String>{
  'YO Voice',
  'YO VOICE',
  'Moment',
  'Premium',
  'VIBE',
};

/// Temporary ratchet for unstable localization sources that predate the
/// template API. New violating files and per-file count increases fail the
/// suite immediately; reductions are always accepted. Delete entries as call
/// sites migrate to [AppLocalizations.template].
const _legacyUnstableTextSourceLimits = <String, int>{
  'lib/features/creator/presentation/screens/creator_pinned_posts_screen.dart':
      2,
  'lib/features/creator/presentation/screens/find_creators_screen.dart': 1,
  'lib/features/creator/presentation/screens/creator_studio_screen.dart': 3,
  'lib/features/creator/presentation/widgets/creator_pinned_moment_card.dart':
      1,
  'lib/features/settings/presentation/screens/profile_visibility_screen.dart':
      2,
  'lib/features/settings/presentation/screens/downloaded_audio_screen.dart': 4,
  'lib/features/settings/presentation/screens/settings_screen.dart': 15,
  'lib/features/settings/presentation/screens/two_factor_authentication_screen.dart':
      6,
  'lib/features/settings/presentation/screens/message_privacy_screen.dart': 3,
  'lib/features/settings/presentation/screens/device_sessions_screen.dart': 4,
  'lib/features/home/presentation/screens/home_screen.dart': 3,
  'lib/features/home/presentation/widgets/from_your_clubs.dart': 2,
  'lib/features/home/presentation/widgets/desktop/desktop_home.dart': 1,
  'lib/features/home/presentation/widgets/desktop/desktop_moments_strip.dart':
      5,
  'lib/features/home/presentation/widgets/desktop/followed_creators_card.dart':
      4,
  'lib/features/home/presentation/widgets/desktop/voice_trending_card.dart': 1,
  'lib/features/home/presentation/widgets/shared/discover_clubs_rail.dart': 1,
  'lib/features/home/presentation/widgets/shared/home_room_board.dart': 5,
  'lib/features/home/presentation/widgets/live_now_hero.dart': 2,
  'lib/features/home/presentation/widgets/mobile/mobile_home.dart': 1,
  'lib/features/home/presentation/widgets/mobile/mobile_home_sections.dart': 7,
  'lib/features/home/presentation/widgets/more_sheet.dart': 2,
  'lib/features/messages/presentation/screens/messages_screen.dart': 4,
  'lib/features/messages/presentation/widgets/message_bubble.dart': 1,
  'lib/features/discover/presentation/discover_localized_copy.dart': 1,
  'lib/features/discover/presentation/screens/discover_screen.dart': 2,
  'lib/features/moments/presentation/screens/moment_comments_screen.dart': 2,
  'lib/features/moments/presentation/screens/moment_detail_screen.dart': 5,
  'lib/features/moments/presentation/widgets/moment_card.dart': 6,
  'lib/features/moments/presentation/widgets/moments_feed_view.dart': 14,
  'lib/features/moments/presentation/widgets/moment_story_viewer.dart': 3,
  'lib/features/clubs/presentation/screens/club_member_management_screen.dart':
      4,
  'lib/features/clubs/presentation/screens/club_chat_screen.dart': 5,
  'lib/features/clubs/presentation/screens/clubs_screen.dart': 5,
  'lib/features/clubs/presentation/screens/club_overview_screen.dart': 4,
  'lib/features/clubs/presentation/screens/club_invite_response_screen.dart': 1,
  'lib/features/clubs/presentation/widgets/family_check_in_panel.dart': 3,
  'lib/features/achievements/presentation/screens/achievements_screen.dart': 7,
  'lib/features/achievements/presentation/achievement_localized_copy.dart': 2,
  'lib/features/profile/presentation/screens/image_crop_screen.dart': 1,
  'lib/features/profile/presentation/screens/profile_screen.dart': 11,
  'lib/features/profile/presentation/screens/follow_list_screen.dart': 1,
  'lib/features/profile/presentation/screens/edit_profile_screen.dart': 19,
  'lib/features/profile/presentation/widgets/profile_header.dart': 1,
  'lib/features/profile/presentation/widgets/profile_journey_card.dart': 3,
  'lib/features/profile/presentation/widgets/profile_vibe_headline.dart': 3,
  'lib/features/staff/presentation/sections/staff_section_shared.dart': 4,
  'lib/features/staff/presentation/sections/staff_operations_sections.dart': 9,
  'lib/features/staff/presentation/sections/staff_users_section.dart': 15,
  'lib/features/staff/presentation/screens/user_management_screen.dart': 2,
  'lib/features/staff/presentation/staff_localized_copy.dart': 3,
  'lib/features/staff/presentation/widgets/user_actions_menu.dart': 19,
  'lib/features/staff/presentation/widgets/room_staff_menu.dart': 5,
  'lib/features/friends/presentation/screens/add_friend_screen.dart': 6,
  'lib/features/friends/presentation/screens/friends_screen.dart': 5,
  'lib/features/friends/presentation/screens/blocked_users_screen.dart': 1,
  'lib/features/friends/presentation/screens/friend_profile_screen.dart': 4,
  'lib/features/rooms/presentation/screens/community_voice_room_screen.dart': 1,
  'lib/features/rooms/presentation/screens/room_settings_screen.dart': 2,
  'lib/features/rooms/presentation/screens/broadcast_room_screen.dart': 3,
  'lib/features/rooms/presentation/screens/create_room_screen.dart': 3,
  'lib/features/rooms/presentation/screens/broadcast_room/podcast_studio.dart':
      4,
  'lib/features/rooms/presentation/screens/broadcast_room/sheets/participants_sheet.dart':
      1,
  'lib/features/rooms/presentation/screens/broadcast_room/broadcast_roster.dart':
      1,
  'lib/features/rooms/presentation/widgets/mini_player/active_room_info.dart':
      3,
  'lib/features/rooms/presentation/widgets/mini_player/live_chat_preview.dart':
      1,
  'lib/features/rooms/presentation/widgets/mini_player/compact_active_room_bar.dart':
      5,
  'lib/features/rooms/presentation/widgets/room_header.dart': 1,
  'lib/features/rooms/presentation/widgets/room_chat_sheet.dart': 3,
  'lib/features/rooms/presentation/widgets/room_stage.dart': 4,
  'lib/features/rooms/presentation/widgets/room_ended_state.dart': 1,
  'lib/features/premium/presentation/screens/premium_plans_screen.dart': 11,
  'lib/features/premium/presentation/screens/premium_screen.dart': 2,
  'lib/features/premium/presentation/premium_localized_copy.dart': 4,
  'lib/features/premium/presentation/widgets/premium_feature_gate.dart': 1,
  'lib/features/notifications/presentation/screens/notification_preferences_screen.dart':
      1,
  'lib/features/moderation/presentation/screens/moderation_center_screen.dart':
      3,
  'lib/features/moderation/presentation/report_content_flow.dart': 1,
  'lib/features/moderation/presentation/widgets/report_audit_timeline.dart': 2,
  'lib/shared/widgets/profile/profile_preview_sheet.dart': 1,
};

void main() {
  test('every product presentation surface localizes user-facing copy', () {
    final violations = <String>[];

    for (final file in _dartFiles()) {
      final source = file.readAsStringSync();
      final patterns = file.path.startsWith('lib/app/')
          ? {..._rawCopyPatterns, ..._appShellRawCopyPatterns}
          : _rawCopyPatterns;
      for (final pattern in patterns.entries) {
        final matcher = RegExp(pattern.value);
        for (final match in matcher.allMatches(source)) {
          final phrase = match.group(2)!;
          if (_localeInvariantMarks.contains(phrase)) continue;
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          violations.add('${file.path}:$line ${pattern.key}: "$phrase"');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'User-facing copy in the app shell and every feature must go through '
          'AppLocalizations in the same change. This keeps Polish production '
          'ready and gives every other language a deterministic catalog or '
          'English fallback boundary.\n${violations.join('\n')}',
    );
  });

  test('localization calls use literal catalog keys without interpolation', () {
    final violationsByFile = <String, List<_UnstableLocalizationCall>>{};

    for (final file in _dartFiles()) {
      final source = file.readAsStringSync();
      final violations = _unstableLocalizationCalls(source);
      if (violations.isNotEmpty) {
        violationsByFile[file.path] = violations;
      }
    }

    final increases = <String>[];
    for (final entry in violationsByFile.entries) {
      final unstableTemplates = entry.value
          .where((violation) => violation.method == 'template')
          .toList(growable: false);
      if (unstableTemplates.isNotEmpty) {
        final details = unstableTemplates
            .map((violation) => '  line ${violation.line}: ${violation.reason}')
            .join('\n');
        increases.add("'${entry.key}': unstable template() source\n$details");
      }

      final unstableTextCalls = entry.value
          .where((violation) => violation.method == 'text')
          .toList(growable: false);
      final limit = _legacyUnstableTextSourceLimits[entry.key] ?? 0;
      if (unstableTextCalls.length <= limit) continue;
      final details = unstableTextCalls
          .map((violation) => '  line ${violation.line}: ${violation.reason}')
          .join('\n');
      increases.add(
        "'${entry.key}': ${unstableTextCalls.length}, "
        '// allowed: $limit\n$details',
      );
    }

    expect(
      increases,
      isEmpty,
      reason:
          'A localization catalog lookup must start with a stable literal '
          'key such as "Ends {date}". Runtime interpolation and nonliteral '
          'sources make lookups impossible outside English and Polish. Use '
          'copy.template() and substitute named values after localization. '
          'The listed count can only be added to the legacy ratchet after '
          'confirming it predates this guard.\n${increases.join('\n')}',
    );
  });

  test('current-release surfaces cannot rely on English catalog fallback', () {
    const releaseFiles = <String>{
      'lib/features/permissions/presentation/permission_setup_sheet.dart',
      'lib/features/auth/presentation/widgets/email_verification_banner.dart',
      'lib/features/auth/presentation/screens/verify_email_screen.dart',
      'lib/features/auth/presentation/screens/totp_challenge_screen.dart',
      'lib/features/calls/presentation/screens/direct_call_screen.dart',
      'lib/features/rooms/presentation/screens/room_entry_screen.dart',
      'lib/features/rooms/presentation/widgets/room_chat_sheet.dart',
      'lib/features/friends/presentation/screens/add_friend_screen.dart',
      'lib/features/friends/presentation/widgets/friend_suggestion_card.dart',
      'lib/features/friends/presentation/friend_request_error_copy.dart',
      'lib/shared/widgets/profile/profile_photo_viewer.dart',
      'lib/features/reels/presentation/screens/reel_composer_screen.dart',
      'lib/features/reels/presentation/widgets/reel_draft_preview.dart',
      'lib/features/reels/presentation/screens/reels_feed_screen.dart',
      'lib/features/moments/presentation/screens/record_voice_moment_screen.dart',
      'lib/features/moments/presentation/screens/moments_screen.dart',
    };
    final localizedCall = RegExp(
      r'''\.(?:text|template)\(\s*((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+),''',
      multiLine: true,
    );
    final missing = <String>[];

    for (final path in releaseFiles) {
      final source = File(path).readAsStringSync();
      for (final match in localizedCall.allMatches(source)) {
        final key = _joinedCatalogLiteral(match.group(1)!);
        if (!appTranslationKeys.contains(key)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          missing.add('$path:$line "$key"');
        }
      }
    }

    const chatPath =
        'lib/features/messages/presentation/screens/chat_screen.dart';
    final chatSource = File(chatPath).readAsStringSync();
    final terminalStart = chatSource.indexOf('class _QueuedTextMessageBubble');
    final terminalEnd = chatSource.indexOf('class _Composer', terminalStart);
    expect(
      terminalStart,
      greaterThanOrEqualTo(0),
      reason: 'The direct-chat terminal retry surface could not be found.',
    );
    expect(
      terminalEnd,
      greaterThan(terminalStart),
      reason: 'The direct-chat terminal retry boundary could not be found.',
    );
    final terminalSource = chatSource.substring(terminalStart, terminalEnd);
    for (final match in localizedCall.allMatches(terminalSource)) {
      final key = _joinedCatalogLiteral(match.group(1)!);
      if (!appTranslationKeys.contains(key)) {
        final absoluteOffset = terminalStart + match.start;
        final line =
            '\n'.allMatches(chatSource.substring(0, absoluteOffset)).length + 1;
        missing.add('$chatPath:$line "$key"');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Every literal on a current-release surface must have a complete '
          'catalog entry before the coordinated build. English fallback is '
          'reserved for legacy screens outside this release scope.\n'
          '${missing.join('\n')}',
    );
  });

  test('stable-source scanner rejects interpolation and expressions', () {
    expect(
      _unstableLocalizationCalls(
        "final value = copy.text('Stable key', 'Stabilny klucz');",
      ),
      isEmpty,
    );
    expect(
      _unstableLocalizationCalls(
        "final value = copy.template('Hello {name}', 'Cześć, {name}', "
        "values: {'name': name});",
      ),
      isEmpty,
    );
    expect(
      _unstableLocalizationCalls(
        r"final value = copy.text('$name joined', '$name dołącza');",
      ),
      hasLength(1),
    );
    expect(
      _unstableLocalizationCalls(
        "final value = copy.text(runtimeKey, 'Polski');",
      ),
      hasLength(1),
    );
    expect(
      _unstableLocalizationCalls(
        r"final value = copy.template('$name joined', '$name dołącza', "
        r"values: {'name': name});",
      ),
      hasLength(1),
    );
  });

  test('catalog scanner joins adjacent Dart string literals', () {
    expect(
      _joinedCatalogLiteral("'First part ' \n 'and second part.'"),
      'First part and second part.',
    );
    expect(
      _joinedCatalogLiteral(r"'Someone\'s recording'"),
      "Someone's recording",
    );
    expect(
      _joinedCatalogLiteral('"A double-quoted key"'),
      'A double-quoted key',
    );
  });
}

String _joinedCatalogLiteral(String expression) {
  final literal = RegExp(r'''(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)")''');
  return literal.allMatches(expression).map((match) {
    final encoded = match.group(1) ?? match.group(2)!;
    return encoded
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }).join();
}

List<_UnstableLocalizationCall> _unstableLocalizationCalls(String source) {
  final calls = <_UnstableLocalizationCall>[];
  final offsets = <int>{};

  final variableReceiver = RegExp(
    r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(text|template)\s*\(',
  );
  for (final match in variableReceiver.allMatches(source)) {
    final receiver = match.group(1)!;
    final isLocalizationReceiver =
        receiver == 'copy' ||
        receiver == '_copy' ||
        receiver == 'localizations' ||
        receiver.endsWith('Copy');
    if (!isLocalizationReceiver || !offsets.add(match.start)) continue;
    final result = _inspectFirstSourceArgument(source, match.end);
    if (result == null) continue;
    calls.add(
      _UnstableLocalizationCall(
        line: _lineAt(source, match.start),
        method: match.group(2)!,
        reason: result,
      ),
    );
  }

  final directReceiver = RegExp(
    r'AppLocalizations\.of\([^()]*\)\s*\.\s*(text|template)\s*\(',
    multiLine: true,
    dotAll: true,
  );
  for (final match in directReceiver.allMatches(source)) {
    if (!offsets.add(match.start)) continue;
    final result = _inspectFirstSourceArgument(source, match.end);
    if (result == null) continue;
    calls.add(
      _UnstableLocalizationCall(
        line: _lineAt(source, match.start),
        method: match.group(1)!,
        reason: result,
      ),
    );
  }

  calls.sort((left, right) => left.line.compareTo(right.line));
  return calls;
}

String? _inspectFirstSourceArgument(String source, int offset) {
  var cursor = _skipTrivia(source, offset);
  var foundLiteral = false;

  while (cursor < source.length) {
    var raw = false;
    if ((source[cursor] == 'r' || source[cursor] == 'R') &&
        cursor + 1 < source.length &&
        (source[cursor + 1] == "'" || source[cursor + 1] == '"')) {
      raw = true;
      cursor += 1;
    }

    if (source[cursor] != "'" && source[cursor] != '"') {
      return foundLiteral
          ? 'source key is a runtime expression'
          : 'source key is not a string literal';
    }
    foundLiteral = true;

    final quote = source[cursor];
    final triple =
        cursor + 2 < source.length &&
        source[cursor + 1] == quote &&
        source[cursor + 2] == quote;
    cursor += triple ? 3 : 1;

    var closed = false;
    while (cursor < source.length) {
      if (!raw && source[cursor] == r'$') {
        return 'source key contains runtime interpolation';
      }
      if (!raw && source[cursor] == '\\' && cursor + 1 < source.length) {
        cursor += 2;
        continue;
      }
      if (triple) {
        if (cursor + 2 < source.length &&
            source[cursor] == quote &&
            source[cursor + 1] == quote &&
            source[cursor + 2] == quote) {
          cursor += 3;
          closed = true;
          break;
        }
      } else if (source[cursor] == quote) {
        cursor += 1;
        closed = true;
        break;
      }
      cursor += 1;
    }

    if (!closed) return 'source key has an unterminated string literal';
    cursor = _skipTrivia(source, cursor);
    if (cursor >= source.length) return 'source key call is incomplete';
    if (source[cursor] == ',') return null;

    final startsAdjacentLiteral =
        source[cursor] == "'" ||
        source[cursor] == '"' ||
        ((source[cursor] == 'r' || source[cursor] == 'R') &&
            cursor + 1 < source.length &&
            (source[cursor + 1] == "'" || source[cursor + 1] == '"'));
    if (!startsAdjacentLiteral) return 'source key is a runtime expression';
  }

  return 'source key call is incomplete';
}

int _skipTrivia(String source, int offset) {
  var cursor = offset;
  while (cursor < source.length) {
    if (RegExp(r'\s').hasMatch(source[cursor])) {
      cursor += 1;
      continue;
    }
    if (cursor + 1 < source.length &&
        source[cursor] == '/' &&
        source[cursor + 1] == '/') {
      final newline = source.indexOf('\n', cursor + 2);
      cursor = newline == -1 ? source.length : newline + 1;
      continue;
    }
    if (cursor + 1 < source.length &&
        source[cursor] == '/' &&
        source[cursor + 1] == '*') {
      final end = source.indexOf('*/', cursor + 2);
      cursor = end == -1 ? source.length : end + 2;
      continue;
    }
    return cursor;
  }
  return cursor;
}

int _lineAt(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

class _UnstableLocalizationCall {
  const _UnstableLocalizationCall({
    required this.line,
    required this.method,
    required this.reason,
  });

  final int line;
  final String method;
  final String reason;
}

Iterable<File> _dartFiles() sync* {
  for (final root in _localizedPresentationRoots()) {
    yield* root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }
}

Iterable<Directory> _localizedPresentationRoots() sync* {
  final app = Directory('lib/app');
  if (app.existsSync()) yield app;

  final features = Directory('lib/features');
  if (features.existsSync()) {
    for (final feature in features.listSync().whereType<Directory>()) {
      final presentation = Directory('${feature.path}/presentation');
      if (presentation.existsSync()) yield presentation;
    }
  }

  final shared = Directory('lib/shared');
  if (shared.existsSync()) yield shared;
}
