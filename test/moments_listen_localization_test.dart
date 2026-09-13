import 'dart:io';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_moments_listen.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    (_placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort());

/// The files board 07 introduced. Everything user-facing they say must
/// either be in the catalog or be named below with its reason.
const _slice2Sources = <String>[
  'lib/features/moments/presentation/widgets/moment_progress_ring.dart',
  'lib/features/moments/presentation/widgets/moment_transport_controls.dart',
  'lib/features/moments/presentation/widgets/voice_reply_mini_player.dart',
  'lib/features/moments/presentation/widgets/moments_queue_list.dart',
  'lib/features/moments/presentation/widgets/moment_conversation_thread.dart',
];

/// Product marks and bare numerals do not cross a translation boundary.
///
/// "Voice Moment" is the format's name and is spelled the same way in every
/// locale (the call sites pass it as English AND Polish). "{percent}%" is a
/// number and a sign: in most extended locales the correct rendering is
/// byte-identical to English, which the catalog's own "no English fallback"
/// guard would read as untranslated copy, so it stays a template carrying
/// the English and Polish spellings (Polish keeps the space).
const _localeInvariant = <String>{'Voice Moment', '{percent}%'};

/// Copy the 07 surfaces INHERITED rather than introduced: every one of these
/// strings already existed on `moment_comments_screen.dart`,
/// `moment_comment_preview.dart` or `moments_feed_view.dart` before this
/// slice and still resolves to English outside EN/PL, exactly as it did
/// there. Slice 2 reused the existing keys instead of minting new ones, so
/// no NEW untranslated string reached the product — but the list must only
/// ever shrink. Translating them is a Localization Specialist task that
/// touches the legacy screens too, not a silent edit inside a UI slice.
const _inheritedEnglishFallback = <String>{
  'Voice reply {duration}',
  'Report this comment',
  'Be the first to comment',
  'Be the first to comment.',
  'See the comment',
  'See all {count} comments',
  'This voice reply is unavailable right now.',
};

/// Every new user-facing string of the expanded Voice listen (board 07) has
/// an explicit entry in all 41 translated locales (43 selectable minus
/// English and Polish, which live in the call sites), the catalog knows the
/// keys, and no locale ships English fallback copy.
void main() {
  final translatedLocaleKeys = selectableAppLanguages
      .where(
        (language) =>
            language != AppLanguagePreference.english &&
            language != AppLanguagePreference.polish,
      )
      .map((language) => language.localeKey)
      .toSet();

  test('the listen catalog covers all 43 selectable locale variants', () {
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(translatedLocaleKeys, hasLength(41));
    expect(momentsListenTranslations.keys.toSet(), translatedLocaleKeys);
    expect(momentsListenTranslationKeys.toSet(), hasLength(17));
    expect(appTranslationKeys, containsAll(momentsListenTranslationKeys));
    for (final localeKey in translatedLocaleKeys) {
      final entries = momentsListenTranslations[localeKey]!;
      expect(
        entries.keys.toSet(),
        momentsListenTranslationKeys.toSet(),
        reason: localeKey,
      );
      for (final key in momentsListenTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
        expect(
          _placeholders(value),
          _placeholders(key),
          reason: '$localeKey: $key',
        );
        expect(
          translatedPhrase(localeKey, key),
          value,
          reason: '$localeKey: $key',
        );
        if (!key.startsWith('yoMoments.') && key.length > 10) {
          expect(value, isNot(key), reason: '$localeKey: no English fallback');
        }
      }
    }
  });

  test('the player, the mini-player and the hand-off list speak the catalog, '
      'and the inherited English fallbacks can only shrink', () {
    final localizedCall = RegExp(
      r'''\.(?:text|template)\(\s*((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+),''',
      multiLine: true,
    );
    final literal = RegExp(r'''(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)")''');
    final unknown = <String>[];
    final inheritedSeen = <String>{};

    for (final path in _slice2Sources) {
      final source = File(path).readAsStringSync();
      for (final match in localizedCall.allMatches(source)) {
        final key = literal.allMatches(match.group(1)!).map((m) {
          final encoded = m.group(1) ?? m.group(2)!;
          return encoded
              .replaceAll(r"\'", "'")
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
        }).join();
        if (appTranslationKeys.contains(key)) continue;
        if (_localeInvariant.contains(key)) continue;
        if (_inheritedEnglishFallback.contains(key)) {
          inheritedSeen.add(key);
          continue;
        }
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        unknown.add('$path:$line "$key"');
      }
    }

    expect(
      unknown,
      isEmpty,
      reason:
          'A new string on the expanded Voice listen must have a complete '
          'catalog entry in translations_moments_listen.dart. English '
          'fallback is reserved for the copy these surfaces inherited from '
          'the screens they replaced.\n${unknown.join('\n')}',
    );
    expect(
      inheritedSeen.difference(_inheritedEnglishFallback),
      isEmpty,
      reason: 'The inherited list is a ratchet; it may only shrink.',
    );
  });

  test('contextual keys resolve to the reviewed EN/PL copy and never leak '
      'the unrelated meaning of the same English word', () {
    const english = AppLocalizations(Locale('en'));
    const polish = AppLocalizations(Locale('pl'));
    const german = AppLocalizations(Locale('de'));

    expect(english.contextualText('yoMoments.play', 'Play', 'Odtwórz'), 'Play');
    expect(
      polish.contextualText('yoMoments.play', 'Play', 'Odtwórz'),
      'Odtwórz',
    );
    expect(
      polish.contextualText(
        'yoMoments.conversation',
        'Conversation',
        'Rozmowa',
      ),
      'Rozmowa',
    );
    expect(
      polish.contextualText('yoMoments.replyToComment', 'Reply', 'Odpowiedz'),
      'Odpowiedz',
    );

    // The ring never borrows another surface's word for progress, and the
    // skips print the same 15 the glyph does.
    expect(
      german.text('Listening progress', 'Postęp odsłuchu'),
      isNot('Listening progress'),
    );
    expect(
      german.text('Skip back 15 seconds', 'Cofnij o 15 sekund'),
      contains('15'),
    );
    expect(
      german.text('Skip forward 15 seconds', 'Przewiń o 15 sekund'),
      contains('15'),
    );

    // Position, duration and the hand-off keep their placeholders after
    // localization, so the numbers are substituted into translated copy.
    expect(
      german.template(
        '{position} of {total}',
        '{position} z {total}',
        values: const <String, Object>{'position': '0:18', 'total': '1:02'},
      ),
      allOf(contains('0:18'), contains('1:02')),
    );
    expect(
      german.template(
        'Play voice reply from {name}, {duration}',
        'Odtwórz odpowiedź głosową: {name}, {duration}',
        values: const <String, Object>{'name': 'Ola', 'duration': '0:12'},
      ),
      allOf(contains('Ola'), contains('0:12')),
    );
    expect(
      german.template(
        'Open Voice Moment: {caption}, {author}',
        'Otwórz Voice Moment: {caption}, {author}',
        values: const <String, Object>{'caption': 'Poranek', 'author': 'Maja'},
      ),
      allOf(contains('Poranek'), contains('Maja')),
    );
  });
}
