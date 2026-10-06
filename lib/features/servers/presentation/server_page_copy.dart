import 'package:yovoice/core/localization/app_localizations.dart';

/// Copy the server page (`Strona serwera`, ADR-240) adds to the Servers
/// vocabulary. English is the catalog key and Polish is authored here; every
/// other selectable locale is in
/// `core/localization/translations/translations_server_page.dart`, together
/// with the existing Servers phrases the page shows, so nothing on the page
/// falls back to English.
///
/// `serverPage.*` keys are context keys: a short word whose form depends on
/// where it stands ("public" inside the meta line is a lower-case adjective,
/// "Voice" is a section heading and not the channel kind `Głosowy`).
extension ServerPageCopy on AppLocalizations {
  /// The page itself: the way back from a channel on a phone, and the channel
  /// column's header on a tablet and a desktop.
  String get serverPageTitle => text('Server page', 'Strona serwera');

  /// The one entry to the full channel list, with the number of channels this
  /// person can see.
  String serverPageAllChannels(int count) => template(
    'All channels ({count})',
    'Wszystkie kanały ({count})',
    values: {'count': count},
  );

  String get serverPageConversations => text('Conversations', 'Rozmowy');

  String get serverPageVoice =>
      contextualText('serverPage.voice', 'Voice', 'Głos');

  /// The eyebrow of the next planned broadcast (a real community event).
  String get serverPageNextLive => text('Next LIVE', 'Następny LIVE');

  /// Opens the stage for a role that may start it. The stage's own
  /// `Rozpocznij nadawanie` still starts the broadcast.
  String get serverPageGoLive => text('Go LIVE', 'Nadaj LIVE');

  /// "Społeczność · publiczny · 128 osób": the middle word.
  String get serverPagePublic =>
      contextualText('serverPage.public', 'public', 'publiczny');

  /// "jutro · Scena LIVE": the day of the next event, relative to now.
  String get serverPageToday =>
      contextualText('serverPage.today', 'today', 'dziś');
  String get serverPageTomorrow =>
      contextualText('serverPage.tomorrow', 'tomorrow', 'jutro');

  /// The short join on a voice row; the hero keeps the full sentence.
  String get serverPageJoin =>
      contextualText('serverPage.join', 'Join', 'Dołącz');

  /// Under the next event's action: the answer this person has on record,
  /// whenever the button does not show it itself. A first `Przypomnij mi` is
  /// saved with the answer `Może` (the callable keeps no reminder without an
  /// answer), and this line is where the page says so.
  String serverPageYourAnswer(String answer) => template(
    'Your answer: {answer}',
    'Twoja odpowiedź: {answer}',
    values: {'answer': answer},
  );
}
