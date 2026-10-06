import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/home/data/first_steps.dart';

/// Every string of "Zacznij tutaj" (firstSteps A, 2026-10-03): Start's
/// checklist card and the one action each of the three dead ends gained (the
/// server invite sheet with no friends, empty Notifications, the empty
/// friends list).
///
/// English is the catalog key and Polish is authored here; the other locales
/// resolve through `translations_first_steps.dart`, so nothing falls back to
/// English. "YO Voice" is the product name and stays as written.
class FirstStepsCopy {
  const FirstStepsCopy(this.copy);

  final AppLocalizations copy;

  // ---- The card -------------------------------------------------------------

  String get title => copy.text('Start here', 'Zacznij tutaj');

  /// "1 z 5": completed steps of the listed ones.
  String progress(int done, int total) => copy.template(
    '{done} of {total}',
    '{done} z {total}',
    values: <String, Object>{'done': '$done', 'total': '$total'},
  );

  /// The X of the card (tooltip and spoken name).
  String get close =>
      copy.contextualText('firstSteps.close', 'Close', 'Zamknij');

  /// Spoken after a ticked step's label; sighted readers get the check.
  String get stepDone =>
      copy.contextualText('firstSteps.stepDone', 'Done', 'Zrobione');

  /// The one line the card collapses to once every step is done.
  String get allDone =>
      copy.text('Done. You know YO Voice now.', 'Gotowe. Znasz już YO Voice.');

  String label(FirstStep step) => switch (step) {
    FirstStep.photo => copy.text(
      'Add a profile photo',
      'Dodaj zdjęcie profilowe',
    ),
    FirstStep.friend => copy.text(
      'Add your first friend',
      'Dodaj pierwszego znajomego',
    ),
    FirstStep.server => copy.text(
      'Join a server or create your own',
      'Dołącz do serwera albo stwórz własny',
    ),
    FirstStep.voice => copy.text(
      'Record your first Voice',
      'Nagraj pierwszy Głos',
    ),
    FirstStep.follow => copy.text(
      'Follow a Page or creator',
      'Zaobserwuj stronę lub twórcę',
    ),
  };

  /// The line under the highlighted (next) step.
  String hint(FirstStep step) => switch (step) {
    FirstStep.photo => copy.text(
      'Friends will recognise you faster',
      'Znajomi szybciej Cię rozpoznają',
    ),
    FirstStep.friend => copy.text(
      'Search by name or send your link',
      'Wyszukaj po nazwie albo wyślij swój link',
    ),
    FirstStep.server => copy.text(
      'See public servers or start your own',
      'Zobacz publiczne serwery albo załóż swój',
    ),
    FirstStep.voice => copy.text(
      'A short voice recording, up to 60 seconds',
      'Krótkie nagranie głosowe, do 60 sekund',
    ),
    FirstStep.follow => copy.text(
      'You will see their news in Content',
      'Ich nowości zobaczysz w Treściach',
    ),
  };

  // ---- The three dead ends --------------------------------------------------

  /// Server invite sheet, nobody to invite, on a server anyone may join.
  String get shareServerLink =>
      copy.text('Share the server link', 'Udostępnij link do serwera');

  String get shareServerLinkFailed => copy.text(
    "Couldn't share the link. Try again.",
    'Nie udało się udostępnić linku. Spróbuj ponownie.',
  );

  /// Server invite sheet and empty Notifications (while Pages are off).
  String get addFriends => copy.homeAddFriends;

  /// Empty Notifications, while Treści exists for the account.
  String get findPagesToFollow =>
      copy.text('Find Pages to follow', 'Znajdź strony do obserwowania');

  /// The Friends screen's "Add friend": the header action and, under the
  /// message of the empty list, the same words again.
  String get addFriend => copy.contextualText(
    'firstSteps.addFriend',
    'Add friend',
    'Dodaj znajomego',
  );
}
