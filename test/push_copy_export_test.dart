import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/notifications/presentation/notification_copy.dart';

/// The server's push copy is an EXPORT of the app's own notification copy
/// (ADR-237): `functions/notifications/push_copy.json` holds every push
/// template in the 42 non-English languages, rendered by the same
/// `NotificationCopy` / `NotificationPushCopy` the bell and the banner use.
/// A push therefore says what the bell row says, and nothing is translated
/// twice.
///
/// This test is both the generator and the guard:
///
///   flutter test test/push_copy_export_test.dart \
///       --dart-define=UPDATE_PUSH_COPY=true
///
/// rewrites the file; without the define it fails when the file and the
/// catalog disagree, so a changed translation cannot ship without its push.
const bool _update = bool.fromEnvironment('UPDATE_PUSH_COPY');
const String _path = 'functions/notifications/push_copy.json';

final RegExp _placeholder = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholder.allMatches(value).map((match) => match.group(0)!).toList()
      ..sort();

/// The 42 languages a push can be written in besides English, in the order
/// the language picker lists them.
List<AppLanguagePreference> get _translated => selectableAppLanguages
    .where((language) => language != AppLanguagePreference.english)
    .toList(growable: false);

Map<String, Object> _export() {
  final templates = <String, Map<String, String>>{};
  for (final id in NotificationPushCopy.templateIds) {
    templates[id] = <String, String>{
      for (final language in _translated)
        language.localeKey: NotificationPushCopy(
          AppLocalizations(language.locale!),
        ).template(id),
    };
  }
  return <String, Object>{
    'schemaVersion': 1,
    'generatedBy': 'test/push_copy_export_test.dart',
    'locales': [for (final language in _translated) language.localeKey],
    'templates': templates,
  };
}

String _encode(Map<String, Object> export) =>
    '${const JsonEncoder.withIndent('  ').convert(export)}\n';

void main() {
  test('every push template exists in all 42 translated languages', () {
    final export = _export();
    final locales = export['locales']! as List<String>;
    expect(locales, hasLength(42));
    expect(locales.toSet(), hasLength(42));
    expect(locales, isNot(contains('en')));
    expect(locales, containsAll(<String>['pl', 'pt_BR', 'zh_CN', 'zh_TW']));

    final english = NotificationPushCopy(const AppLocalizations(Locale('en')));
    final templates = export['templates']! as Map<String, Map<String, String>>;
    expect(templates.keys.toList(), NotificationPushCopy.templateIds);
    for (final entry in templates.entries) {
      final source = english.template(entry.key);
      for (final locale in locales) {
        final value = entry.value[locale];
        final reason = '${entry.key} in $locale';
        expect(value, isNotNull, reason: reason);
        expect(value!.trim(), isNotEmpty, reason: reason);
        // The server fills {actor} and {label}; a template must keep exactly
        // the placeholders of its English source.
        expect(_placeholders(value), _placeholders(source), reason: reason);
        // No silent English: a language that has no translation would render
        // the English sentence here.
        expect(value, isNot(source), reason: '$reason fell back to English');
      }
    }
  });

  test('template ids follow the server contract', () {
    // push_locale.js builds the id from (type, label): `type`, `type.label`,
    // the two `.video` call forms, and the non-title sentences.
    final ids = NotificationPushCopy.templateIds;
    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll(<String>[
        'friendRequest',
        'clubInvite',
        'clubInvite.label',
        'liveStarted.label',
        'directCall.video',
        'missedCall.video',
        'pagePostPublished',
        'achievementUnlocked.label',
        'moderation',
        'actor.unknown',
        'body.default',
        'call.incoming.title',
        'call.incoming.body',
        'call.missed.title',
        'call.missed.body',
      ]),
    );
    expect(
      () => NotificationPushCopy(
        const AppLocalizations(Locale('en')),
      ).template('nope'),
      throwsArgumentError,
    );
  });

  test(
    'a followed Page post is announced without a gendered verb in Polish',
    () {
      final polish = NotificationPushCopy(const AppLocalizations(Locale('pl')));
      expect(polish.template('pagePostPublished'), '{actor} dodaje post');
      expect(polish.template('body.default'), 'Dotknij, aby otworzyć YO Voice');
      expect(
        polish.template('clubInvite.label'),
        '{actor} zaprasza Cię do serwera {label}',
      );
      expect(
        polish.template('roomInvite.label'),
        '{actor} zaprasza Cię do kanału głosowego {label}',
      );
    },
  );

  test('functions/notifications/push_copy.json matches the catalog', () {
    final expected = _encode(_export());
    final file = File(_path);
    if (_update) {
      file.writeAsStringSync(expected);
    }
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run this test with --dart-define=UPDATE_PUSH_COPY=true.',
    );
    expect(
      file.readAsStringSync(),
      expected,
      reason:
          '$_path is out of date. Regenerate it with '
          'flutter test test/push_copy_export_test.dart '
          '--dart-define=UPDATE_PUSH_COPY=true',
    );
  });
}
