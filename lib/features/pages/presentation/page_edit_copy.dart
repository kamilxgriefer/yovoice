import 'package:yovoice/features/pages/presentation/pages_copy.dart';

/// The copy of "Edytuj stronę" (pageEdit A, owner decision 2026-10-03): the
/// one form with the live preview, its unsaved-changes and save states, the
/// read-only state with "Wyczyść dane kontaktowe" (ADR-241), and the entry in
/// Page settings. English is the catalog key and Polish is authored here, as
/// in [PagesCopy]; every other locale resolves through
/// `translations_page_edit.dart`. What the form shares with create A and the
/// profile (field labels, "Widoczne publicznie", "Zapisz", "Anuluj") stays in
/// `PageProfileCopy`.
extension PageEditCopy on PagesCopy {
  // ---- Sections and fields ---------------------------------------------------

  String get editAppearance =>
      copy.contextualText('pageEdit.appearance', 'Appearance', 'Wygląd');

  /// Said once, right above the name: the Page has no photo, cover or name
  /// of its own.
  String get editSharedIdentity => copy.text(
    'The cover, photo and name of your Page are also the cover, photo and name of your account in chats and servers.',
    'Okładka, zdjęcie i nazwa strony to także okładka, zdjęcie i nazwa Twojego konta w czatach i serwerach.',
  );
  String get editName => copy.contextualText('pageEdit.name', 'Name', 'Nazwa');
  String get editNameHelper => copy.text(
    'You can change the name once every 30 days. After a change the Page stays out of search for 7 days.',
    'Nazwę zmienisz raz na 30 dni. Po zmianie strona przez 7 dni nie pojawia się w wyszukiwarce.',
  );

  /// The name's helper while the 30-day cooldown runs; [date] is already
  /// formatted for the reader's locale.
  String editNameLockedUntil(String date) => copy.template(
    'You can change the name again on {date}.',
    'Nazwę zmienisz ponownie {date}.',
    values: <String, Object>{'date': date},
  );
  String get editNameLength => copy.text(
    'The name must be 2 to 120 characters long.',
    'Nazwa musi mieć od 2 do 120 znaków.',
  );
  String get editTypeLocked => copy.text(
    "The type can't be changed yet",
    'Typu nie da się jeszcze zmienić',
  );
  String get editRulesHint => copy.text(
    'For example: be kind, no ads, only photos of your own work.',
    'Na przykład: szanujemy się, bez reklam, zdjęcia tylko własnych prac.',
  );
  String get changeCover => copy.text('Change cover', 'Zmień okładkę');
  String get changePhoto => copy.text('Change photo', 'Zmień zdjęcie');

  // ---- Preview ---------------------------------------------------------------

  String get editPreviewNote => copy.text(
    'This is how others will see your Page. The preview changes as you type.',
    'Tak zobaczą stronę inni. Podgląd zmienia się, gdy piszesz.',
  );
  String get hidePreview => copy.text('Hide preview', 'Zwiń podgląd');
  String get showPreview => copy.text('Show preview', 'Rozwiń podgląd');

  // ---- Saving ----------------------------------------------------------------

  String get unsavedChanges =>
      copy.text('You have unsaved changes', 'Masz niezapisane zmiany');
  String get saveChanges => copy.text('Save changes', 'Zapisz zmiany');
  String get discardChangesTitle =>
      copy.text('Discard changes?', 'Odrzucić zmiany?');
  String get discardChangesBody => copy.text(
    "Your changes haven't been saved.",
    'Zmiany nie zostały zapisane.',
  );
  String get saveFailed =>
      copy.text("Couldn't save the changes", 'Nie udało się zapisać zmian');

  /// The name or a picture went through before a later step failed.
  String get savedPartly => copy.text(
    'Some changes were saved, but not all',
    'Część zmian została zapisana, ale nie wszystkie',
  );
  String get nameChangeFailed => copy.text(
    "Couldn't change the name. Try again.",
    'Nie udało się zmienić nazwy. Spróbuj ponownie.',
  );
  String get nameSavedRetry => copy.text(
    'The name is saved. Press Save again to finish.',
    'Nazwa jest zapisana. Naciśnij Zapisz ponownie, aby dokończyć.',
  );
  String get imageRefused => copy.text(
    "Couldn't use this image. Choose a JPG, PNG or WebP file.",
    'Nie udało się użyć tego obrazu. Wybierz plik JPG, PNG lub WebP.',
  );
  String get imageUploadFailed => copy.text(
    "Couldn't upload the image. Check your connection and try again.",
    'Nie udało się przesłać obrazu. Sprawdź połączenie i spróbuj ponownie.',
  );

  // ---- Read-only form and the contact safety action (ADR-241) ----------------

  String get editLockedTitle =>
      copy.text('Editing is off right now', 'Edycja jest teraz wyłączona');
  String get editLockedLapsed => copy.text(
    'Editing comes back when Premium or VIP is active again.',
    'Edycja wróci, gdy Premium lub VIP znów będzie aktywne.',
  );
  String get editLockedSuspended => copy.text(
    "This Page is suspended by moderation, so it can't be edited.",
    'Strona jest zawieszona przez moderację, więc nie można jej edytować.',
  );
  String get clearContact =>
      copy.text('Clear contact details', 'Wyczyść dane kontaktowe');
  String get clearContactTitle =>
      copy.text('Clear contact details?', 'Wyczyścić dane kontaktowe?');
  String get clearContactBody => copy.text(
    "The website, e-mail, phone, address, hours and legal notice will be removed from your Page. This can't be undone.",
    'Strona www, e-mail, telefon, adres, godziny i nota prawna znikną ze strony. Tego nie da się cofnąć.',
  );
  String get clearAction =>
      copy.contextualText('pageEdit.clear', 'Clear', 'Wyczyść');
  String get contactCleared =>
      copy.text('Contact details cleared', 'Dane kontaktowe wyczyszczone');

  // ---- Page settings entry ---------------------------------------------------

  String get editPageSubtitle => copy.text(
    'Cover, photo, name, description and everything visitors see',
    'Okładka, zdjęcie, nazwa, opis i wszystko, co widzą odwiedzający',
  );
}
