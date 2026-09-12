import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';

bool _dateFormattingInitialized = false;

void _ensureDateFormattingInitialized() {
  if (_dateFormattingInitialized) return;
  // initializeDateFormatting from date_symbol_data_local registers the
  // bundled tables synchronously, then returns Future.value(). This guard
  // also protects widgets that use the English fallback localization without
  // mounting a MaterialApp delegate (common in focused widget tests).
  initializeDateFormatting();
  _dateFormattingInitialized = true;
}

class AppLocalizations {
  const AppLocalizations(this.locale);

  static final RegExp _templatePlaceholderPattern = RegExp(
    r'\{([a-zA-Z][a-zA-Z0-9_]*)\}',
  );

  final Locale locale;

  static final supportedLocales = List<Locale>.unmodifiable(
    selectableAppLanguages.map((language) => language.locale!),
  );

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  bool get isPolish => locale.languageCode == 'pl';

  String get localeKey => localizationKeyForLocale(locale);

  String text(String english, String polish) {
    if (locale.languageCode == 'en') return english;
    if (isPolish) return polish;
    return translatedPhrase(localeKey, english) ?? english;
  }

  /// Resolves copy by a stable, feature-scoped catalog key while keeping the
  /// displayed English phrase independent from that key. Use this when a short
  /// word has different meanings in different product contexts.
  String contextualText(String key, String english, String polish) {
    if (locale.languageCode == 'en') return english;
    if (isPolish) return polish;
    return translatedPhrase(localeKey, key) ?? english;
  }

  /// Resolves a stable catalog template and substitutes runtime values only
  /// after localization.
  ///
  /// The English template is the catalog key, so values must be represented by
  /// named placeholders (`{name}`, `{count}`) instead of Dart interpolation.
  /// English and Polish must expose the same placeholders and callers must
  /// provide exactly one value for each name. Replacement is single-pass:
  /// braces or dollar signs contained in user content are preserved verbatim
  /// and can never become a second template expression.
  String template(
    String englishTemplate,
    String polishTemplate, {
    required Map<String, Object> values,
  }) {
    final englishPlaceholders = _templatePlaceholders(englishTemplate);
    final polishPlaceholders = _templatePlaceholders(polishTemplate);
    if (!listEquals(englishPlaceholders, polishPlaceholders)) {
      throw ArgumentError.value(
        polishTemplate,
        'polishTemplate',
        'English and Polish templates must contain the same placeholders.',
      );
    }

    final requiredNames = englishPlaceholders.toSet();
    final providedNames = values.keys.toSet();
    if (!setEquals(requiredNames, providedNames)) {
      final missing = requiredNames.difference(providedNames).toList()..sort();
      final unexpected = providedNames.difference(requiredNames).toList()
        ..sort();
      throw ArgumentError.value(
        values,
        'values',
        'Template values do not match placeholders. '
            'Missing: $missing; unexpected: $unexpected.',
      );
    }

    var localizedTemplate = text(englishTemplate, polishTemplate);
    // Catalog integrity tests enforce placeholder parity. Falling back here
    // still prevents a malformed remotely merged or future catalog entry from
    // leaking an unresolved token into production UI.
    if (!listEquals(
      _templatePlaceholders(localizedTemplate),
      englishPlaceholders,
    )) {
      localizedTemplate = englishTemplate;
    }

    return localizedTemplate.replaceAllMapped(_templatePlaceholderPattern, (
      match,
    ) {
      final name = match.group(1)!;
      return values[name]!.toString();
    });
  }

  String get settings => text('Settings', 'Ustawienia');
  String get appearance => text('Appearance', 'Wygląd');
  String get theme => text('Theme', 'Motyw');
  String get systemTheme =>
      text('Use device setting', 'Zgodnie z ustawieniami urządzenia');
  String get darkTheme => text('Dark', 'Ciemny');
  String get lightTheme => text('Light', 'Jasny');
  String get language => text('Language', 'Język');
  String get appLanguage => text('App language', 'Język aplikacji');
  String get systemLanguage => text('Use device language', 'Język urządzenia');
  String get english => text('English', 'Angielski');
  String get polish => text('Polish', 'Polski');
  String languageName(AppLanguagePreference language) {
    final polishName = switch (language) {
      AppLanguagePreference.system => 'Język urządzenia',
      AppLanguagePreference.english => 'Angielski',
      AppLanguagePreference.polish => 'Polski',
      AppLanguagePreference.german => 'Niemiecki',
      AppLanguagePreference.spanish => 'Hiszpański',
      AppLanguagePreference.portuguese => 'Portugalski (Portugalia)',
      AppLanguagePreference.portugueseBrazil => 'Portugalski (Brazylia)',
      AppLanguagePreference.french => 'Francuski',
      AppLanguagePreference.italian => 'Włoski',
      AppLanguagePreference.ukrainian => 'Ukraiński',
      AppLanguagePreference.russian => 'Rosyjski',
      AppLanguagePreference.czech => 'Czeski',
      AppLanguagePreference.slovak => 'Słowacki',
      AppLanguagePreference.bulgarian => 'Bułgarski',
      AppLanguagePreference.dutch => 'Niderlandzki',
      AppLanguagePreference.romanian => 'Rumuński',
      AppLanguagePreference.turkish => 'Turecki',
      AppLanguagePreference.greek => 'Grecki',
      AppLanguagePreference.hungarian => 'Węgierski',
      AppLanguagePreference.croatian => 'Chorwacki',
      AppLanguagePreference.serbian => 'Serbski',
      AppLanguagePreference.swedish => 'Szwedzki',
      AppLanguagePreference.danish => 'Duński',
      AppLanguagePreference.norwegian => 'Norweski (bokmål)',
      AppLanguagePreference.finnish => 'Fiński',
      AppLanguagePreference.lithuanian => 'Litewski',
      AppLanguagePreference.latvian => 'Łotewski',
      AppLanguagePreference.estonian => 'Estoński',
      AppLanguagePreference.indonesian => 'Indonezyjski',
      AppLanguagePreference.vietnamese => 'Wietnamski',
      AppLanguagePreference.chineseSimplified => 'Chiński uproszczony',
      AppLanguagePreference.chineseTraditional => 'Chiński tradycyjny',
      AppLanguagePreference.japanese => 'Japoński',
      AppLanguagePreference.korean => 'Koreański',
      AppLanguagePreference.arabic => 'Arabski',
      AppLanguagePreference.hindi => 'Hindi',
      AppLanguagePreference.bengali => 'Bengalski',
      AppLanguagePreference.urdu => 'Urdu',
      AppLanguagePreference.thai => 'Tajski',
      AppLanguagePreference.malay => 'Malajski',
      AppLanguagePreference.filipino => 'Filipiński',
      AppLanguagePreference.hebrew => 'Hebrajski',
      AppLanguagePreference.persian => 'Perski',
      AppLanguagePreference.swahili => 'Suahili',
    };
    return text(language.englishName, polishName);
  }

  String get languagePreviewTitle => text('Language ready', 'Język gotowy');
  String get languagePreviewBody => text(
    'Core navigation, authentication, Settings, onboarding and system controls are available in your selected language. User-created content stays in its original language.',
    'Nawigacja, logowanie, rejestracja, samouczek i najważniejsze ustawienia są dostępne po polsku. Treści użytkowników pozostają w oryginalnym języku.',
  );
  String get chooseLanguage => text(
    'Choose the language used on this device.',
    'Wybierz język aplikacji na tym urządzeniu.',
  );
  String get systemLanguageDescription => text(
    'Matches any supported device language and falls back to English.',
    'Używa języka urządzenia, jeśli YO Voice go obsługuje. W przeciwnym razie wybiera angielski.',
  );
  String get searchLanguages => text('Search languages', 'Szukaj języków');
  String get noLanguagesFound =>
      text('No languages found', 'Nie znaleziono języków');
  String get savedOnDevice => text(
    'This preference is saved on this device.',
    'To ustawienie jest zapisane na tym urządzeniu.',
  );
  String get saveFailed => text(
    'Could not save this preference. Try again.',
    'Nie udało się zapisać ustawienia. Spróbuj ponownie.',
  );

  String get home => text('Home', 'Start');

  String get homeLiveForYou =>
      contextualText('home.liveForYou', 'Live for you', 'Na żywo dla Ciebie');
  String get homeYourCircle =>
      contextualText('home.yourCircle', 'Your circle', 'Twój krąg');
  String get homeCreateRoom =>
      contextualText('home.createRoom', 'Create room', 'Stwórz pokój');
  String get homeStartConversation => contextualText(
    'home.startConversation',
    'Invite and talk',
    'Zaproś i rozmawiaj',
  );
  String get homeGrowYourCircle => contextualText(
    'home.growYourCircle',
    'Grow your circle',
    'Powiększ swój krąg',
  );
  String get homeYou => contextualText('home.you', 'You', 'Ty');

  /// Heading of the demoted followed-Moments rail on Home.
  String get homeFromPeopleYouFollow => contextualText(
    'home.fromPeopleYouFollow',
    'From people you follow',
    'Od osób, które obserwujesz',
  );

  // Home "Tu i teraz" — pre-registered for the Mobile and Wide slices so the
  // implementers consume keys only. Polish first; "Voice Moment" stays
  // invariant; every key has an explicit entry in the 41 translated catalogs
  // (translations_home.dart).

  /// "Hi, {name}" — the Home greeting. [name] is the first whitespace token of
  /// the display name and is substituted after localization (never the email
  /// local part).
  String homeGreeting(String name) =>
      template('Hi, {name}', 'Cześć, {name}', values: {'name': name});

  /// The greeting when the profile has no display name yet.
  String get homeGreetingNoName => text('Hi!', 'Cześć!');

  String get homeGreetingSubtitle => contextualText(
    'home.greetingSubtitle',
    'Good to see you again!',
    'Dobrze Cię znowu widzieć!',
  );

  /// Section title of the friends rail.
  String get homeYourPeople =>
      contextualText('home.yourPeople', 'Your people', 'Twoi znajomi');

  /// Section title of the featured-room hero.
  String get homeHereNow =>
      contextualText('home.hereNow', 'Here and now', 'Tu i teraz');

  /// Section title of the live rows from the account's own places.
  String get homeInYourServers => contextualText(
    'home.inYourServers',
    'In your servers',
    'W Twoich serwerach',
  );

  /// Section title of the places rail.
  String get homeYourPlaces =>
      contextualText('home.yourPlaces', 'Your places', 'Twoje miejsca');

  /// "See all" addressing people — Polish and several other locales decline
  /// the animate form differently from [homeSeeAll].
  String get homeSeeAllPeople =>
      contextualText('home.seeAllPeople', 'See all', 'Zobacz wszystkich');

  /// "See all" addressing places and servers.
  String get homeSeeAll =>
      contextualText('home.seeAll', 'See all', 'Zobacz wszystkie');

  /// The dashed add tile at the end of the friends rail.
  String get homeAddFriends =>
      contextualText('home.addFriends', 'Add friends', 'Dodaj znajomych');

  /// Hero CTA for a community room.
  String get homeJoinConversation => contextualText(
    'home.joinConversation',
    'Join the conversation',
    'Dołącz do rozmowy',
  );

  /// Hero CTA for a broadcast room — Community and Broadcast stay distinct.
  String get homeJoinBroadcast => contextualText(
    'home.joinBroadcast',
    'Join the broadcast',
    'Dołącz do transmisji',
  );

  /// The server-row pill that opens the pre-join screen of a live lounge.
  String get homeTakeALook =>
      contextualText('home.takeALook', 'Take a look', 'Zajrzyj');

  /// Channel kind on a server row; broadcast rows reuse the existing tag.
  String get homeVoiceConversation => contextualText(
    'home.voiceConversation',
    'Voice conversation',
    'Rozmowa głosowa',
  );

  /// The places rail's last tile and the empty places card's action.
  String get homeCreateServer =>
      contextualText('home.createServer', 'Create server', 'Stwórz serwer');

  /// Title of the "record a Voice Moment" row card.
  String get homeGotAMinute =>
      contextualText('home.gotAMinute', 'Got a minute?', 'Masz chwilę?');

  /// Subtitle of the same card.
  String get homeRecordVoiceMoment => contextualText(
    'home.recordVoiceMoment',
    'Record a Voice Moment',
    'Nagraj Voice Moment',
  );

  /// Empty hero (nothing live): headline, body and the Discover link. The
  /// actions reuse the existing [homeCreateRoom] and [friends] keys.
  String get homeInvitationHeadline => contextualText(
    'home.invitationHeadline',
    'A good conversation starts here.',
    'Tu zaczyna się dobra rozmowa.',
  );
  String get homeInvitationBody => contextualText(
    'home.invitationBody',
    "It's quiet right now. Create a room or check on your friends.",
    'Teraz jest cicho. Utwórz pokój albo zajrzyj do znajomych.',
  );
  String get homeDiscoverRooms =>
      contextualText('home.discoverRooms', 'Discover rooms', 'Odkrywaj pokoje');

  /// Mobile room-directory destination, distinct from desktop Discover.
  String get navigationRooms =>
      contextualText('navigation.rooms', 'Rooms', 'Pokoje');

  /// The Servers destination (dock slot 1, desktop rail row 2): the account's
  /// own places. Lives in core localization because Home may not import the
  /// servers feature's copy.
  String get navigationServers =>
      contextualText('navigation.servers', 'Servers', 'Serwery');

  /// Primary navigation label; the shared destination heading keeps its
  /// separate, invariant YO Moments product name.
  String get navigationYourMoments =>
      contextualText('navigation.yourMoments', 'Moments', 'Momenty');

  /// Product destination name. Brand names stay invariant in every locale;
  /// "Voice Moment" and "Reel" remain the localized format names inside it.
  String get moments => 'YO Moments';
  String get yoMomentsFromYourCircle => contextualText(
    'yoMoments.fromCircle',
    'YO Moments from your circle',
    'YO Moments z Twojego kręgu',
  );
  String get discover => text('Discover', 'Odkrywaj');
  String get findCreators => text('Find creators', 'Znajdź twórców');
  String get chats => text('Chats', 'Czaty');
  String get notifications => text('Notifications', 'Powiadomienia');
  String get friends => text('Friends', 'Znajomi');
  String get more => text('More', 'Więcej');
  String get profile => text('Profile', 'Profil');

  String unreadConversations(int count) {
    if (isPolish) {
      if (count == 1) return '1 nieprzeczytana rozmowa';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count nieprzeczytane rozmowy';
      }
      return '$count nieprzeczytanych rozmów';
    }
    return _pluralized(
      count: count,
      stem: '{count} unread conversation',
      englishOne: '{count} unread conversation',
      englishOther: '{count} unread conversations',
    );
  }

  String unreadMessages(int count) {
    if (isPolish) {
      if (count == 1) return '1 nieprzeczytana wiadomość';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count nieprzeczytane wiadomości';
      }
      return '$count nieprzeczytanych wiadomości';
    }
    return _pluralized(
      count: count,
      stem: '{count} unread message',
      englishOne: '{count} unread message',
      englishOther: '{count} unread messages',
    );
  }

  /// "N people" for a place's member count, with Polish declension:
  /// 1 osoba, 2–4 osoby (but 12–14 osób), otherwise osób.
  String peopleCount(int count) {
    if (isPolish) {
      if (count == 1) return '1 osoba';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count osoby';
      }
      return '$count osób';
    }
    return _pluralized(
      count: count,
      stem: '{count} member',
      englishOne: '{count} member',
      englishOther: '{count} members',
    );
  }

  /// A spoken duration for screen readers ("45 sekund"), never "0:45":
  /// 1 sekunda, 2–4 sekundy (but 12–14 sekund), otherwise sekund.
  String secondsCount(int count) {
    if (isPolish) {
      if (count == 1) return '1 sekunda';
      final lastTwo = count % 100;
      final last = count % 10;
      if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
        return '$count sekundy';
      }
      return '$count sekund';
    }
    return _pluralized(
      count: count,
      stem: '{count} second',
      englishOne: '{count} second',
      englishOther: '{count} seconds',
    );
  }

  String navigationUnreadLabel(String destination, int count) => _template(
    text('{destination}, {unread}', '{destination}, {unread}'),
    {'destination': destination, 'unread': unreadConversations(count)},
  );

  String openChatWith(String displayName) => _template(
    text('Open chat with {name}', 'Otwórz czat: {name}'),
    {'name': displayName},
  );

  String lastMessage(String preview) => _template(
    text('Last message: {preview}', 'Ostatnia wiadomość: {preview}'),
    {'preview': preview},
  );

  String tourProgress(int current, int total) => _template(
    text('Step {current} of {total}', 'Krok {current} z {total}'),
    {'current': '$current', 'total': '$total'},
  );

  String tourStepSemantics(int current, int total, String title, String body) =>
      _template(
        text(
          'Step {current} of {total}. {title}. {body}',
          'Krok {current} z {total}. {title}. {body}',
        ),
        {
          'current': '$current',
          'total': '$total',
          'title': title,
          'body': body,
        },
      );

  String get openVoiceActions =>
      text('Open voice actions', 'Otwórz opcje głosowe');
  String get voiceActionsPrivateCallActive => text(
    'Voice actions — private call active',
    'Opcje głosowe — trwa rozmowa prywatna',
  );
  String get voiceActionsRoomActive =>
      text('Voice actions — live in a room', 'Opcje głosowe — aktywny pokój');

  String get email => text('Email', 'E-mail');
  String get password => text('Password', 'Hasło');
  String get logIn => text('LOG IN', 'ZALOGUJ SIĘ');
  String get continueWithGoogle =>
      text('Continue with Google', 'Kontynuuj z Google');
  String get continueWithApple =>
      text('Continue with Apple', 'Kontynuuj z Apple');
  String get noAccount => text("Don't have an account?", 'Nie masz konta?');
  String get signUp => text('Sign up', 'Zarejestruj się');
  String get forgotPassword => text('Forgot password?', 'Nie pamiętasz hasła?');
  String get resetPassword => text('Reset password', 'Zresetuj hasło');
  String get resetPasswordIntro => text(
    'Enter the email address for your YO Voice account. We will send a secure reset link if an account exists.',
    'Wpisz adres e-mail przypisany do konta YO Voice. Jeśli konto istnieje, wyślemy bezpieczny link do resetowania hasła.',
  );
  String get emailAddress => text('Email address', 'Adres e-mail');
  String get sendResetLink => text('SEND RESET LINK', 'WYŚLIJ LINK RESETUJĄCY');
  String get backToLogin => text('Back to log in', 'Wróć do logowania');
  String get createAccount => text('CREATE ACCOUNT', 'UTWÓRZ KONTO');
  String get username => text('Username', 'Nazwa użytkownika');
  String get confirmPassword => text('Confirm password', 'Powtórz hasło');
  String get alreadyHaveAccount =>
      text('Already have an account?', 'Masz już konto?');

  String get today => text('Today', 'Dzisiaj');
  String get yesterday => text('Yesterday', 'Wczoraj');
  String get earlier => text('Earlier', 'Wcześniej');

  String calendarDate(DateTime date) {
    _ensureDateFormattingInitialized();
    return DateFormat.yMd(localeKey).format(date);
  }

  String relativeCompactTime(DateTime date, {DateTime? now}) {
    final difference = (now ?? DateTime.now()).difference(date);
    if (difference.inMinutes < 1) return text('now', 'teraz');
    if (difference.inMinutes < 60) {
      return _template(text('{count}m ago', '{count} min temu'), {
        'count': '${difference.inMinutes}',
      });
    }
    if (difference.inHours < 24) {
      return _template(text('{count}h ago', '{count} godz. temu'), {
        'count': '${difference.inHours}',
      });
    }
    if (difference.inDays < 7) {
      return _template(text('{count}d ago', '{count} dni temu'), {
        'count': '${difference.inDays}',
      });
    }
    return calendarDate(date);
  }

  String activeTime(DateTime date, {DateTime? now}) {
    final difference = (now ?? DateTime.now()).difference(date);
    if (difference.inMinutes < 1) return text('Active now', 'Aktywny teraz');
    if (difference.inMinutes < 60) {
      return _template(
        text('Active {count}m ago', 'Aktywny {count} min temu'),
        {'count': '${difference.inMinutes}'},
      );
    }
    if (difference.inHours < 24) {
      return _template(
        text('Active {count}h ago', 'Aktywny {count} godz. temu'),
        {'count': '${difference.inHours}'},
      );
    }
    return _template(text('Active {count}d ago', 'Aktywny {count} dni temu'), {
      'count': '${difference.inDays}',
    });
  }

  String _pluralized({
    required int count,
    required String stem,
    required String englishOne,
    required String englishOther,
  }) {
    String form(String category, String fallback) =>
        translatedPhrase(localeKey, '$stem.$category') ?? fallback;
    final value = Intl.pluralLogic(
      count,
      locale: localeKey,
      zero: form('zero', englishOther),
      one: form('one', englishOne),
      two: form('two', englishOther),
      few: form('few', englishOther),
      many: form('many', englishOther),
      other: form('other', englishOther),
    );
    return _template(value, {'count': '$count'});
  }

  String _template(String value, Map<String, String> replacements) {
    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  static List<String> _templatePlaceholders(String value) {
    final placeholders = _templatePlaceholderPattern
        .allMatches(value)
        .map((match) => match.group(1)!)
        .toList(growable: false);
    return [...placeholders]..sort();
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) {
    // date_symbol_data_local registers its bundled lookup tables before it
    // returns Future.value(). Keeping the delegate synchronous avoids a blank
    // localization frame while still making DateFormat safe for every locale.
    _ensureDateFormattingInitialized();
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
