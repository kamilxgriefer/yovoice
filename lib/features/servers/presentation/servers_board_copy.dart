import 'package:yovoice/core/localization/app_localizations.dart';

/// Copy of the Servers tab's board (ADR-239): "Twoje serwery", "Serwery
/// publiczne", the "+" sheet, the name filter and "Dołącz z linku".
///
/// English is the catalog key and Polish is authored here; every other
/// selectable locale has an explicit entry in
/// `lib/core/localization/translations/translations_servers_board.dart`
/// (pinned by `test/servers_board_localization_test.dart`), so none of these
/// falls back to English. `serversBoard.*` context keys carry the short words
/// whose meaning depends on this board ("View" the card's action, "live" the
/// row's lamp, "Paste" the clipboard action).
extension ServersBoardCopy on AppLocalizations {
  String get serversBoardYours => text('Your servers', 'Twoje serwery');
  String get serversBoardPublic => text('Public servers', 'Serwery publiczne');

  /// The public card's action.
  String get serversBoardView =>
      contextualText('serversBoard.view', 'View', 'Zobacz');

  /// The lamp beside a server with a live conversation — lower case, a
  /// status, not the `NA ŻYWO` badge.
  String get serversBoardLive =>
      contextualText('serversBoard.live', 'live', 'na żywo');

  String get serversBoardShowAll =>
      contextualText('serversBoard.showAll', 'Show all', 'Pokaż wszystkie');
  String get serversBoardShowFewer =>
      contextualText('serversBoard.showFewer', 'Show fewer', 'Pokaż mniej');

  /// The "+" disc's spoken name and tooltip.
  String get serversBoardAdd =>
      text('Create or join a server', 'Stwórz serwer lub dołącz');
  String get serversBoardCreate => text('Create server', 'Stwórz serwer');
  String get serversBoardJoinLink => text('Join with a link', 'Dołącz z linku');

  String get serversBoardSearch => text('Search servers', 'Szukaj serwera');
  String get serversBoardCloseSearch =>
      text('Close search', 'Zamknij wyszukiwanie');
  String get serversBoardNoMatches => text(
    'No server matches your search.',
    'Żaden serwer nie pasuje do wyszukiwania.',
  );

  /// The first-run invitation that stands in for "Twoje serwery".
  String get serversBoardNewcomerTitle => text(
    'Your place for shared conversations',
    'Twoje miejsce na wspólne rozmowy',
  );

  String get serversBoardPublicFailed => text(
    "Public servers couldn't be loaded.",
    'Nie udało się wczytać serwerów publicznych.',
  );
  String get serversBoardRetry => text('Try again', 'Spróbuj ponownie');
  String get serversBoardLoading =>
      text('Loading servers', 'Wczytywanie serwerów');

  // "Dołącz z linku" -------------------------------------------------------

  String get serversJoinLinkBody => text(
    'Paste a link to a YO Voice server.',
    'Wklej link do serwera YO Voice.',
  );
  String get serversJoinLinkLabel => text('Server link', 'Link do serwera');
  String get serversJoinLinkPaste =>
      contextualText('serversBoard.paste', 'Paste', 'Wklej');
  String get serversJoinLinkOpen => text('Open server', 'Otwórz serwer');
  String get serversJoinLinkInvalid => text(
    "This isn't a YO Voice server link.",
    'To nie jest link do serwera YO Voice.',
  );
}
