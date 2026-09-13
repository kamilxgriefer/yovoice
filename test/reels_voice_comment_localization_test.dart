import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_reels_voice_comments.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    (_placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort());

/// The files slice 5 introduced or extended with voice-comment copy.
const _slice5Sources = <String>[
  'lib/features/reels/presentation/widgets/reel_comments_view.dart',
  'lib/features/reels/presentation/widgets/reel_comment_report_sheet.dart',
];

/// Copy these surfaces INHERITED rather than introduced.
///
/// Every one of these strings already existed on `reel_comments_view.dart`
/// or `reel_comment_report_sheet.dart` before this slice and still resolves
/// to English outside EN/PL, exactly as it did there. This slice added no
/// NEW untranslated string — but the list must only ever shrink. Translating
/// them touches the whole Reels thread and belongs to a Localization
/// Specialist pass, not to a feature slice.
const _inheritedEnglishFallback = <String>{
  'Add a comment',
  'Anything else? (optional)',
  'Be the first to comment.',
  'Cancel',
  'Comment by {author}',
  'Comment by {author}, reported by you',
  'Comment deleted.',
  'Comment options',
  'Comment posted.',
  'Comment removed.',
  'Comments: {count}',
  'Context helps our team decide faster.',
  'Delete',
  'Delete comment',
  'Delete comment?',
  'Load more comments',
  'Loading comments',
  'No comments yet',
  'Post comment',
  'Remove',
  'Remove from my Reel',
  'Remove this comment?',
  'Report again',
  'Report comment',
  'Report this comment',
  'Reported — with our team',
  'Send report',
  'Thanks. This comment was sent for review.',
  'Try again',
  'You already reported this comment. It is still with our team.',
  'Your comment will be removed for everyone. This cannot be undone.',
  'Your report is confidential. Our team reviews it — the comment stays up until they decide.',
  "{author}'s comment will be removed from your Reel for everyone. This cannot be undone. To have it reviewed instead, report it.",
  // Reused, not minted: 'Reply with voice' already lives in the Moments
  // overview catalog and the mic points at that entry.
  'Reply with voice',
};

void main() {
  final translatedLocaleKeys = selectableAppLanguages
      .where(
        (language) =>
            language != AppLanguagePreference.english &&
            language != AppLanguagePreference.polish,
      )
      .map((language) => language.localeKey)
      .toSet();

  test('43 selectable locales, 41 of them catalogued explicitly', () {
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(translatedLocaleKeys, hasLength(41));
    expect(reelsVoiceCommentTranslations.keys.toSet(), translatedLocaleKeys);
  });

  test('every voice-comment string is complete in all 41 locales', () {
    expect(reelsVoiceCommentTranslationKeys, hasLength(6));
    expect(
      appTranslationKeys,
      containsAll(reelsVoiceCommentTranslationKeys),
      reason: 'the app catalog must know every new key',
    );
    for (final localeKey in translatedLocaleKeys) {
      final entries = reelsVoiceCommentTranslations[localeKey]!;
      expect(
        entries.keys.toSet(),
        reelsVoiceCommentTranslationKeys.toSet(),
        reason: localeKey,
      );
      for (final key in reelsVoiceCommentTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
        // A placeholder that disappears in one locale is a crash in that
        // locale, not a wording choice.
        expect(
          _placeholders(value),
          _placeholders(key),
          reason: '$localeKey: $key',
        );
        expect(translatedPhrase(localeKey, key), value);
        // No locale ships the English source as its "translation".
        expect(value, isNot(key), reason: '$localeKey: no English fallback');
      }
    }
  });

  test('the new keys do not overwrite existing release terminology', () {
    // `Reply with voice` already exists (Moments overview) and the mic reuses
    // it rather than minting a second spelling, so it must NOT be redefined
    // here — a duplicate would silently win the merge for the whole app.
    expect(
      reelsVoiceCommentTranslationKeys,
      isNot(contains('Reply with voice')),
    );
    expect(
      reelsVoiceCommentTranslationKeys,
      isNot(contains('Coming soon')),
      reason:
          'the mic states an ACTION plus a state; the bare chip is a '
          'different string with a different meaning',
    );
    for (final localeKey in translatedLocaleKeys) {
      expect(translatedPhrase(localeKey, 'Reply with voice'), isNotNull);
      expect(translatedPhrase(localeKey, 'Coming soon'), isNotNull);
    }
  });

  test('slice 5 introduced no new uncatalogued user-facing string', () {
    // Matches `copy.text('EN', 'PL')` and `copy.template('EN', 'PL', …)`,
    // including adjacent-literal continuations.
    final localizedCall = RegExp(
      r'''\.(?:text|template)\(\s*((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+),''',
      multiLine: true,
    );
    final missing = <String>[];
    for (final path in _slice5Sources) {
      final source = File(path).readAsStringSync();
      for (final match in localizedCall.allMatches(source)) {
        final key = _joinedLiteral(match.group(1)!);
        if (appTranslationKeys.contains(key)) continue;
        if (_inheritedEnglishFallback.contains(key)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        missing.add('$path:$line "$key"');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Every string this slice introduced must have a complete catalog '
          'entry. Inherited copy is listed explicitly and that list may only '
          'shrink.\n${missing.join('\n')}',
    );
  });

  test('every contextual key the slice uses exists in the catalog', () {
    final contextual = RegExp(
      r"""\.contextualText\(\s*'([^']+)'""",
      multiLine: true,
    );
    final used = <String>{};
    for (final path in _slice5Sources) {
      final source = File(path).readAsStringSync();
      for (final match in contextual.allMatches(source)) {
        used.add(match.group(1)!);
      }
    }
    expect(
      used,
      containsAll(<String>{
        'reels.voiceCommentComingSoon',
        'reels.voiceCommentPosted',
        'reels.voiceCommentKept',
      }),
    );
    for (final key in used) {
      expect(
        appTranslationKeys.contains(key),
        isTrue,
        reason: 'contextual key "$key" is not in the catalog',
      );
    }
  });
}

/// Joins adjacent Dart string literals the way the compiler does, so a key
/// wrapped across lines is compared as the single value it really is.
String _joinedLiteral(String expression) {
  final literal = RegExp(r'''(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)")''');
  return literal.allMatches(expression).map((match) {
    final encoded = match.group(1) ?? match.group(2)!;
    return encoded
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }).join();
}
