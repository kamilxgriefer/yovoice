import 'package:yovoice/shared/identity/public_identity.dart';

/// The server-owned Page categories (spec premium-pages §1.8,
/// `functions/pages/catalog.js`). The key set is the wire contract; labels
/// live in `PageProfileCopy.categoryLabel`. Deliberately absent: alcohol,
/// tobacco and vapes, gambling, weapons, adult services, dating, crypto and
/// investment.
abstract final class PageCatalog {
  static const List<String> business = <String>[
    'cafe_restaurant',
    'shop',
    'beauty_wellness',
    'sport_fitness',
    'education',
    'music_arts',
    'media_podcast',
    'services',
    'tech',
    'local_travel',
    'other_business',
  ];

  static const List<String> community = <String>[
    'sport',
    'music',
    'gaming',
    'books_learning',
    'hobby_crafts',
    'local_neighbourhood',
    'fan_club',
    'charity_cause',
    'other_community',
  ];

  static List<String> categoriesFor(PageKind kind) => switch (kind) {
    PageKind.business => business,
    PageKind.community => community,
  };

  static bool allowed(PageKind kind, String category) =>
      categoriesFor(kind).contains(category);
}

/// Client-side mirrors of the server's field rules (§2.2.1,
/// `functions/pages/contract.js`), so a mistake is caught at the field
/// instead of as a refusal after "Opublikuj stronę". The server stays the
/// authority and re-validates everything.
abstract final class PageFieldRules {
  static const int description = 300;
  static const int rules = 1000;
  static const int hours = 120;
  static const int address = 160;
  static const int legalNotice = 1000;
  static const int website = 200;
  static const int email = 254;

  static final RegExp _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
  );
  static final RegExp _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');

  /// `https://` with a dotted host, no credentials, no port.
  static bool websiteOk(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    if (text.length > website || RegExp(r'\s').hasMatch(text)) return false;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host;
    if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) {
      return false;
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(host) || host.startsWith('[')) {
      return false;
    }
    return true;
  }

  static bool emailOk(String value) {
    final text = value.trim();
    return text.isEmpty || (text.length <= email && _email.hasMatch(text));
  }

  /// E.164 once spaces and dashes are dropped (the server stores it so).
  static bool phoneOk(String value) {
    final text = value.trim();
    return text.isEmpty || _e164.hasMatch(text.replaceAll(RegExp('[ -]'), ''));
  }

  /// Null for an empty field (the server stores empty text as null).
  static String? optional(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
