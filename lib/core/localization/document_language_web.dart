import 'dart:ui' show Locale;

import 'package:web/web.dart' as web;

const _rightToLeftLanguageCodes = <String>{'ar', 'he', 'fa', 'ur'};

void updateDocumentLanguage(Locale locale) {
  final documentElement = web.document.documentElement;
  documentElement?.setAttribute('lang', locale.toLanguageTag());
  documentElement?.setAttribute(
    'dir',
    _rightToLeftLanguageCodes.contains(locale.languageCode.toLowerCase())
        ? 'rtl'
        : 'ltr',
  );
}
