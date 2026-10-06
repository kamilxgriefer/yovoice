import 'package:intl/intl.dart';

import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

/// The copy of Page deletion (ADR-236; owner's choice pageDeleteWhat B +
/// pageDeleteHow B, 2026-10-03): the "Strefa zagrożenia" of Page settings,
/// "Usuń wszystkie posty", the full "Usuń stronę" screen, the 30 days to
/// restore and the 7-day pause before a new Page. English is the catalog key
/// and Polish is authored here, as in [PagesCopy]; every other locale
/// resolves through `translations_page_delete.dart`.
///
/// Counts are never spelled inside a sentence: a sentence takes a ready
/// counted phrase ("14 postów", "128 obserwujących") as `{posts}` or
/// `{followers}`, so each language declines the noun once, in its own
/// plural entries, instead of once per sentence.
extension PageDeleteCopy on PagesCopy {
  // ---- Dates and counts ------------------------------------------------------

  /// "1 listopada 2026" / "November 1, 2026", in the reader's own zone.
  String deletionDate(DateTime at) =>
      DateFormat.yMMMMd(copy.localeKey).format(at.toLocal());

  /// "1 listopada" / "November 1".
  String deletionDay(DateTime at) =>
      DateFormat.MMMMd(copy.localeKey).format(at.toLocal());

  /// "14 postów" / "14 posts".
  String postsCount(int count) {
    final number = NumberFormat.decimalPattern(copy.localeKey).format(count);
    final line = copy.pluralTemplate(
      count: count,
      stem: '{count} posts',
      englishOne: '{count} post',
      englishOther: '{count} posts',
      polishOne: '{count} post',
      polishFew: '{count} posty',
      polishMany: '{count} postów',
    );
    return number == '$count' ? line : line.replaceFirst('$count', number);
  }

  // ---- Page settings: the danger zone ----------------------------------------

  String get dangerZone => copy.text('Danger zone', 'Strefa zagrożenia');
  String get deleteAllPosts =>
      copy.text('Delete all posts', 'Usuń wszystkie posty');
  String get deleteAllPostsSubtitle => copy.text(
    'The Page and its followers stay',
    'Strona i obserwujący zostają',
  );
  String get deletePage => copy.text('Delete Page', 'Usuń stronę');
  String get deletePageSubtitle => copy.text(
    'Posts, followers and contact details. Your account stays.',
    'Posty, obserwujący i kontakt. Konto zostaje.',
  );

  // ---- "Usuń wszystkie posty" -------------------------------------------------

  String clearPostsTitle(int posts) => copy.template(
    'Delete {posts}?',
    'Usunąć {posts}?',
    values: <String, Object>{'posts': postsCount(posts)},
  );
  String clearPostsBody(int followers) => copy.template(
    "Comments and likes under them go too. The Page and {followers} stay. This can't be undone.",
    'Znikną też komentarze i polubienia pod nimi. Strona i {followers} zostają. Tego nie da się cofnąć.',
    values: <String, Object>{'followers': exactFollowers(followers)},
  );
  String get deletePosts => copy.text('Delete posts', 'Usuń posty');
  String get postsDeleted => copy.text('Posts deleted', 'Posty usunięte');
  String get clearingTitle =>
      copy.text('Deleting posts', 'Trwa usuwanie postów');
  String clearingBody(int followers) => copy.template(
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.',
    'Znikają w tle, zwykle w kilkanaście minut. Strona i {followers} zostają.',
    values: <String, Object>{'followers': exactFollowers(followers)},
  );
  String get publishFirstPost =>
      copy.text('Publish your first post', 'Opublikuj pierwszy post');

  // ---- The "Usuń stronę" screen ----------------------------------------------

  String get goesOverline =>
      copy.contextualText('pages.delete.goes', 'Goes away', 'Zniknie');
  String get goesPage => copy.text(
    'The Page in Content and in search.',
    'Strona w Treściach i w wyszukiwarce.',
  );
  String goesPosts(int posts) => copy.template(
    '{posts} with photos and recordings.',
    '{posts} ze zdjęciami i nagraniami.',
    values: <String, Object>{'posts': postsCount(posts)},
  );
  String get goesEngagement => copy.text(
    'Comments and likes under them.',
    'Komentarze i polubienia pod nimi.',
  );
  String goesFollowers(int followers) => copy.template(
    '{followers} of the Page and their notifications about your LIVE.',
    '{followers} strony i ich powiadomienia o Twoich LIVE.',
    values: <String, Object>{'followers': exactFollowers(followers)},
  );
  String get goesContact =>
      copy.text("The Page's contact details.", 'Dane kontaktowe strony.');
  String get staysOverline =>
      copy.contextualText('pages.delete.stays', 'Stays', 'Zostaje');
  String get staysAccount => copy.text(
    'Your account: name, photo and cover.',
    'Twoje konto: nazwa, zdjęcie i okładka.',
  );
  String get staysSocial => copy.text(
    'Friends, chats, servers, Voice Moments and Yeels.',
    'Znajomi, czaty, serwery, Głosy i Yeels.',
  );
  String get reportedExceptionTitle =>
      copy.text('Exception: reported content', 'Wyjątek: zgłoszone treści');
  String get reportedExceptionBody => copy.text(
    'We may keep reported content, not publicly, for up to 90 days.',
    'Zgłoszone treści możemy przechowywać niepublicznie do 90 dni.',
  );
  String get graceTitle =>
      copy.text('You have 30 days to come back', 'Masz 30 dni na powrót');
  String graceBody(DateTime deleteAt) => copy.template(
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.',
    'Stronę ukryjemy od razu. Usuniemy ją {date}. Do tego dnia możesz ją przywrócić. Przywrócenie wymaga aktywnego Premium lub VIP.',
    values: <String, Object>{'date': deletionDate(deleteAt)},
  );
  String get typeNameLabel =>
      copy.text('Type the Page name', 'Wpisz nazwę strony');
  String typeNameHelper(String name) => copy.template(
    'To confirm, type: {name}',
    'Aby potwierdzić, wpisz: {name}',
    values: <String, Object>{'name': name},
  );

  // ---- 30 days to restore ----------------------------------------------------

  String get statusPendingDeletion => copy.contextualText(
    'pages.statusPendingDeletion',
    'To be deleted',
    'Do usunięcia',
  );
  String pendingTitle(DateTime deleteAt) => copy.template(
    'The Page will be deleted on {date}',
    'Strona zostanie usunięta {date}',
    values: <String, Object>{'date': deletionDate(deleteAt)},
  );
  String get pendingProfileBody => copy.text(
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.',
    'Inni już jej nie widzą, posty widzisz tylko Ty. Do tego dnia możesz ją przywrócić razem z postami i obserwującymi.',
  );
  String get pendingSettingsBody => copy.text(
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.',
    'Inni już jej nie widzą. Do tego dnia możesz ją przywrócić razem z postami i obserwującymi. Przywrócenie wymaga aktywnego Premium lub VIP.',
  );
  String get restorePage => copy.text('Restore Page', 'Przywróć stronę');
  String get restoreSubtitle => copy.text(
    'Comes back to Content with its posts and followers',
    'Wraca do Treści razem z postami i obserwującymi',
  );
  String get pageRestored => copy.text('Page restored', 'Strona przywrócona');

  /// "Przywróć stronę" always cancels the deletion; the Page goes back on
  /// air only when it was running before and today's rules allow it (live
  /// Premium or VIP, a public profile). Otherwise this is the answer, and
  /// the Page shows its ordinary paused state with "Wznów stronę".
  String get deletionCancelledPaused => copy.text(
    'Deletion cancelled. The Page stays paused.',
    'Usuwanie anulowane. Strona pozostaje wstrzymana.',
  );
  String get deleteNow =>
      copy.text("Delete now, don't wait", 'Usuń teraz, nie czekaj');
  String deleteNowSubtitle(DateTime deleteAt) => copy.template(
    "Without waiting until {date}. This can't be undone.",
    'Bez czekania do {date}. Tego nie da się cofnąć.',
    values: <String, Object>{'date': deletionDay(deleteAt)},
  );
  String get deleteNowTitle =>
      copy.text('Delete the Page now?', 'Usunąć stronę teraz?');
  String get deleteNowBody => copy.text(
    "Posts, followers and contact details are deleted right away and can't be restored. You can create a new Page after 7 days.",
    'Posty, obserwujących i dane kontaktowe usuniemy od razu i nie da się ich przywrócić. Nową stronę założysz po 7 dniach.',
  );

  // ---- The fresh sign-in before "Usuń teraz, nie czekaj" -----------------------

  /// "Delete now" is the one step that cannot be undone, so the server asks
  /// for a sign-in no older than five minutes (the account-deletion rule).
  String get confirmIdentityTitle => copy.contextualText(
    'pages.delete.confirmIdentity',
    'Confirm it is you',
    'Potwierdź, że to Ty',
  );
  String get confirmIdentityBody => copy.text(
    'Deleting the Page now needs a fresh sign-in. Enter your password.',
    'Usunięcie strony od razu wymaga świeżego logowania. Wpisz hasło.',
  );

  /// The field label; the word is in the base catalog of every locale.
  String get passwordLabel => copy.text('Password', 'Hasło');
  String get confirmIdentityFailed => copy.text(
    "We couldn't confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.",
    'Nie udało się potwierdzić, że to Ty, więc nic nie zostało usunięte. Spróbuj ponownie albo wyloguj się i zaloguj od nowa.',
  );

  // ---- The purge and the pause before a new Page -------------------------------

  String get purgingTitle =>
      copy.text('Deleting the Page', 'Trwa usuwanie strony');
  String get purgingBody => copy.text(
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.',
    'Usuwamy posty i obserwujących w tle. Nową stronę założysz 7 dni po zakończeniu.',
  );

  /// The purge finished: the Page is gone for good.
  String get pageDeleted => copy.text('Page deleted', 'Strona usunięta');
  String recreateAfter(DateTime at) => copy.template(
    'You can create a new Page after {date}.',
    'Nową stronę założysz po {date}.',
    values: <String, Object>{'date': deletionDate(at)},
  );

  /// The bell row 3 days before the purge (`pageLapse`, phase
  /// `deletionSoon`).
  String get deletionSoonNotice => copy.text(
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.',
    'Twoja strona zostanie usunięta za 3 dni. Przywróć ją w ustawieniach strony, jeśli chcesz ją zachować.',
  );
}
