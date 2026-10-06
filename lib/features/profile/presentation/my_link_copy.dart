import 'package:yovoice/core/localization/app_localizations.dart';

/// Every string of "Mój link" (ADR-238): the sheet with the QR code, its
/// entry points, the share texts built around a public link and what a
/// profile or Voice Moment link says when it cannot be opened. The English
/// phrase is the catalog key; the other 41 locales resolve through
/// `translations_my_link.dart`.
class MyLinkCopy {
  const MyLinkCopy(this.copy);

  final AppLocalizations copy;

  /// The sheet's title, the Friends header action and the Profile rows.
  String get title => copy.text('My link', 'Mój link');

  /// What the link does for whoever opens it. An account that runs a Page
  /// opens as that Page, where the action is Follow.
  String body({required bool runsPage}) => runsPage
      ? copy.text(
          'Anyone who opens it or scans the code will see your Page and can '
              'follow you.',
          'Kto go otworzy albo zeskanuje kod, zobaczy Twoją Stronę i będzie '
              'mógł Cię obserwować.',
        )
      : copy.text(
          'Anyone who opens it or scans the code will see your profile and '
              'can add you as a friend.',
          'Kto go otworzy albo zeskanuje kod, zobaczy Twój profil i będzie '
              'mógł dodać Cię do znajomych.',
        );

  /// What the sheet says instead of [body] while the account's profile is
  /// not visible to everyone ("Friends only" or "Only me" under Profile
  /// visibility). The link itself still works, but whoever the setting does
  /// not admit reads [profileUnavailable] and cannot add this person — so
  /// "anyone who opens it will see your profile" would be a promise the app
  /// already knows it cannot keep.
  String get bodyNotPublic => copy.text(
    'Your profile is not public, so this link will not open it for '
        'everyone. To let anyone add you, change Profile visibility in '
        'Settings.',
    'Twój profil nie jest publiczny, więc ten link nie otworzy go każdemu. '
        'Aby każdy mógł Cię dodać, zmień Widoczność profilu w Ustawieniach.',
  );

  String get copyLink => copy.text('Copy link', 'Kopiuj link');

  String get share => copy.text('Share', 'Udostępnij');

  /// The Friends empty state's action.
  String get shareMyLink => copy.text('Share my link', 'Udostępnij mój link');

  String get qrLabel =>
      copy.text('QR code with your link', 'Kod QR z Twoim linkiem');

  String get copied => copy.text('Link copied.', 'Link skopiowany.');

  String get cannotCopy => copy.text(
    'The link could not be copied. Try again.',
    'Nie udało się skopiować linku. Spróbuj ponownie.',
  );

  String get cannotShare => copy.text(
    'Sharing is unavailable here. Copy the link instead.',
    'Udostępnianie jest tutaj niedostępne. Skopiuj link.',
  );

  String get shareUnconfirmed => copy.text(
    'Sharing could not be confirmed. You can copy the link.',
    'Nie można potwierdzić udostępnienia. Możesz skopiować link.',
  );

  /// No signed-in account, or an identifier the link contract cannot carry.
  String get unavailable => copy.text(
    'Your link is not available right now.',
    'Twój link jest teraz niedostępny.',
  );

  /// What "Udostępnij" and every "invite friends" action hand to the system
  /// share sheet.
  String shareText(Uri link) => copy.template(
    'Find me on YO Voice: {link}',
    'Znajdź mnie w YO Voice: {link}',
    values: <String, Object>{'link': link.toString()},
  );

  /// What sharing a Voice Moment hands to the system share sheet.
  String momentShareText({required String authorName, required Uri link}) =>
      copy.template(
        'Listen to {name} on YO Voice: {link}',
        'Posłuchaj {name} w YO Voice: {link}',
        values: <String, Object>{'name': authorName, 'link': link.toString()},
      );

  /// A profile that cannot be shown: missing, private, blocked or suspended.
  /// One sentence for all of them, so the answer reveals nothing.
  String get profileUnavailable => copy.text(
    'This profile is not available.',
    'Ten profil jest niedostępny.',
  );

  /// The Voice Moment detail's own gone-state headline.
  String get momentUnavailable => copy.text(
    'This Moment is no longer available',
    'Ten Moment nie jest już dostępny',
  );

  /// Under the sign-in headline when the app was opened from a profile link.
  String get signInForProfile => copy.text(
    'Sign in to see this profile and add this person as a friend.',
    'Zaloguj się, aby zobaczyć ten profil i dodać tę osobę do znajomych.',
  );

  /// Under the sign-in headline when the app was opened from a Voice link.
  String get signInForMoment => copy.text(
    'Sign in to listen to this Voice Moment.',
    'Zaloguj się, aby posłuchać tego Voice Momentu.',
  );
}
