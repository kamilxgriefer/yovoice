import 'package:intl/intl.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

/// Copy of the composer A "arkusz", the post detail A "karta + wątek", the
/// comment thread, post reports and the Pages upsell (spec premium-pages
/// §4.5, §5; renders R3, R11). English is the catalog key and Polish is
/// authored here; the other locales resolve through
/// `translations_pages.dart`.
class PagePostCopy {
  const PagePostCopy(this.copy);

  final AppLocalizations copy;

  // ---- Composer ------------------------------------------------------------

  String get newPost => copy.text('New post', 'Nowy post');

  /// "jako {page}": the name is drawn bold with its rosette, so the template
  /// is split around the placeholder.
  (String, String) asPage() {
    const marker = '\u0000';
    final text = copy.template(
      'as {page}',
      'jako {page}',
      values: const <String, Object>{'page': marker},
    );
    final at = text.indexOf(marker);
    if (at < 0) return ('$text ', '');
    return (text.substring(0, at), text.substring(at + 1));
  }

  String get modeText => copy.contextualText('pages.modeText', 'Text', 'Tekst');
  String get modePhotos =>
      copy.contextualText('pages.modePhotos', 'Photos', 'Zdjęcia');
  String get modeVoice =>
      copy.contextualText('pages.modeVoice', 'Voice', 'Głos');
  String get postType => copy.text('Post type', 'Rodzaj posta');
  String get writeSomething => copy.text('Write something…', 'Napisz coś…');
  String get addCaption =>
      copy.text('Add a description (optional)', 'Dodaj opis (opcjonalnie)');
  String get commentsOn => copy.text('Comments on', 'Komentarze włączone');
  String get commentsOff => copy.text('Comments off', 'Komentarze wyłączone');
  String get publish =>
      copy.contextualText('pages.publish', 'Publish', 'Opublikuj');
  String get publishing => copy.text('Publishing…', 'Publikowanie…');
  String get sendingPhotos => copy.text('Sending photos…', 'Wysyłanie zdjęć…');
  String get sendingRecording =>
      copy.text('Sending recording…', 'Wysyłanie nagrania…');
  String get published => copy.text('Post published', 'Post opublikowany');
  String get view => copy.contextualText('pages.view', 'View', 'Zobacz');
  String get retry => copy.contextualText('pages.retry', 'Retry', 'Ponów');

  String characters(int used, int max) => copy.template(
    '{used} of {max} characters',
    '{used} z {max} znaków',
    values: <String, Object>{'used': used, 'max': max},
  );

  // Discard.
  String get discardTitle =>
      copy.text('Discard this post?', 'Odrzucić ten post?');
  String get discardBody => copy.text(
    'What you wrote and added will be lost.',
    'To, co napisano i dodano, zostanie utracone.',
  );
  String get discard =>
      copy.contextualText('pages.discard', 'Discard', 'Odrzuć');
  String get keepEditing => copy.text('Keep editing', 'Wróć do edycji');

  // Photos.
  String get choosePhotosTitle =>
      copy.text('Add up to 10 photos', 'Dodaj do 10 zdjęć');
  String get choosePhotos => copy.text('Choose photos', 'Wybierz zdjęcia');
  String get addPhotos => copy.text('Add photos', 'Dodaj zdjęcia');
  String get noLocation => copy.text('No location', 'Bez lokalizacji');
  String get metadataNote => copy.text(
    'Before sending, we remove location and camera details from photos.',
    'Przed wysłaniem usuwamy ze zdjęć lokalizację i dane aparatu.',
  );
  String get preparingPhoto =>
      copy.text('Preparing photo…', 'Przygotowywanie zdjęcia…');
  String get photosLocked => copy.text(
    'The photos are being sent. Publish or close to change them.',
    'Zdjęcia są wysyłane. Opublikuj albo zamknij, aby je zmienić.',
  );

  String removePhoto(int index) => copy.template(
    'Remove photo {index}',
    'Usuń zdjęcie {index}',
    values: <String, Object>{'index': index},
  );

  String showPhoto(int index, int total) => copy.template(
    'Photo {index} of {total}',
    'Zdjęcie {index} z {total}',
    values: <String, Object>{'index': index, 'total': total},
  );

  String photoPrepareFailed(int index) => copy.template(
    "Photo {index} couldn't be prepared. Try again.",
    'Nie udało się przygotować zdjęcia {index}. Spróbuj ponownie.',
    values: <String, Object>{'index': index},
  );

  String photoUploadFailed(int index) => copy.template(
    "Photo {index} couldn't be sent. Try again.",
    'Nie udało się wysłać zdjęcia {index}. Spróbuj ponownie.',
    values: <String, Object>{'index': index},
  );

  String get recordingUploadFailed => copy.text(
    "The recording couldn't be sent. Try again.",
    'Nie udało się wysłać nagrania. Spróbuj ponownie.',
  );

  /// "1,8 MB".
  String megabytes(int bytes) {
    final value = bytes / (1024 * 1024);
    final number = NumberFormat('0.0', copy.localeKey).format(value);
    return copy.template(
      '{size} MB',
      '{size} MB',
      values: <String, Object>{'size': number},
    );
  }

  // Voice.
  String get recordTitle =>
      copy.text('Record a voice post', 'Nagraj post głosowy');

  /// Modality-neutral: the record control is pressed, clicked, tapped or
  /// activated with a keyboard or switch.
  String get recordHint => copy.text('Up to 1:00', 'Do 1:00');
  String get tenSecondsLeft =>
      copy.text('Ten seconds left.', 'Zostało 10 sekund.');

  /// Voice mode's text field: the words stand in for the audio for anyone
  /// who cannot listen (WCAG 1.2.1).
  String get voiceTranscript => copy.text(
    'Description or transcript (recommended)',
    'Opis lub transkrypcja (zalecane)',
  );
  String get voiceTranscriptHelper => copy.text(
    "A text version lets people who can't listen follow your post.",
    'Wersja tekstowa pozwala śledzić post osobom, które nie mogą słuchać.',
  );
  String get startRecording => copy.text('Start recording', 'Zacznij nagrywać');
  String get stopRecording =>
      copy.text('Stop recording', 'Zatrzymaj nagrywanie');
  String get recording => copy.text('Recording…', 'Nagrywanie…');
  String get recordAgain => copy.text('Record again', 'Nagraj ponownie');
  String get deleteRecording => copy.text('Delete recording', 'Usuń nagranie');
  String get playRecording => copy.text('Play recording', 'Odtwórz nagranie');
  String get pauseRecording =>
      copy.text('Pause recording', 'Wstrzymaj nagranie');
  String get autoStopped => copy.text(
    "The recording stopped by itself at 1:00. That's the longest voice post.",
    'Nagranie zatrzymało się samo na 1:00. To najdłuższy możliwy post głosowy.',
  );
  String get recordingLocked => copy.text(
    'The recording is being sent. Publish or close to change it.',
    'Nagranie jest wysyłane. Opublikuj albo zamknij, aby je zmienić.',
  );

  String recordingProblem(VoiceRecordingProblem problem) => switch (problem) {
    VoiceRecordingProblem.microphoneBlocked => copy.text(
      'Microphone access is blocked. Allow it in your device or browser settings.',
      'Dostęp do mikrofonu jest zablokowany. Zezwól na niego w ustawieniach urządzenia lub przeglądarki.',
    ),
    VoiceRecordingProblem.microphoneNotFound => copy.text(
      'No microphone was found.',
      'Nie znaleziono mikrofonu.',
    ),
    VoiceRecordingProblem.platformCannotRecord => copy.text(
      "This device can't record voice posts.",
      'To urządzenie nie może nagrywać postów głosowych.',
    ),
    VoiceRecordingProblem.recordingUnusable => copy.text(
      'That recording came back empty. Record again.',
      'Nagranie jest puste. Nagraj ponownie.',
    ),
    _ => copy.text(
      "Recording couldn't start. Try again.",
      'Nie udało się rozpocząć nagrywania. Spróbuj ponownie.',
    ),
  };

  // Budget (§1.1: 10 posts per Page per UTC day).
  String postsLeftToday(int count) => copy.pluralTemplate(
    count: count,
    stem: 'You can publish {count} more posts today.',
    englishOne: 'You can publish {count} more post today.',
    englishOther: 'You can publish {count} more posts today.',
    polishOne: 'Dziś możesz opublikować jeszcze {count} post.',
    polishFew: 'Dziś możesz opublikować jeszcze {count} posty.',
    polishMany: 'Dziś możesz opublikować jeszcze {count} postów.',
  );

  /// Every refusal of reserve / upload / publish in words.
  String publishError(PagesFailure failure) => switch (failure) {
    PagesFailure.budget => copy.text(
      "Your Page reached today's posting limit. Try again tomorrow.",
      'Strona osiągnęła dzisiejszy limit postów. Spróbuj jutro.',
    ),
    PagesFailure.mediaMetadata => copy.text(
      "This photo couldn't be prepared. Try again.",
      'Nie udało się przygotować zdjęcia. Spróbuj ponownie.',
    ),
    PagesFailure.mediaInvalid => copy.text(
      "A file couldn't be verified. Try again.",
      'Nie udało się sprawdzić pliku. Spróbuj ponownie.',
    ),
    PagesFailure.uploadInProgress => copy.text(
      'An earlier upload is still open. Try again in a few minutes.',
      'Poprzednie wysyłanie jest jeszcze otwarte. Spróbuj ponownie za kilka minut.',
    ),
    PagesFailure.uploadExpired => copy.text(
      'The upload took too long. Publish again.',
      'Wysyłanie trwało zbyt długo. Opublikuj ponownie.',
    ),
    PagesFailure.paused => copy.text(
      'Your Page is paused. Resume it to publish.',
      'Strona jest wstrzymana. Wznów ją, aby publikować.',
    ),
    PagesFailure.readOnly => copy.text(
      "This Page isn't publishing right now.",
      'Ta strona obecnie nie publikuje.',
    ),
    PagesFailure.accessRequired => copy.text(
      'YO Voice VIP is required to run a Page.',
      'Do prowadzenia strony potrzebny jest YO Voice VIP.',
    ),
    PagesFailure.notEnabled => copy.text(
      "Pages aren't available right now.",
      'Strony są chwilowo niedostępne.',
    ),
    PagesFailure.invalidInput => copy.text(
      'Check the post and try again.',
      'Sprawdź post i spróbuj ponownie.',
    ),
    PagesFailure.rateLimited => copy.text(
      'Too many tries. Try again later.',
      'Zbyt wiele prób. Spróbuj ponownie później.',
    ),
    PagesFailure.network => copy.text(
      "Couldn't connect. Check your connection and try again.",
      'Brak połączenia. Sprawdź internet i spróbuj ponownie.',
    ),
    _ => copy.text(
      'Something went wrong. Try again.',
      'Coś poszło nie tak. Spróbuj ponownie.',
    ),
  };

  // ---- Post detail -----------------------------------------------------------

  String get postTitle =>
      copy.contextualText('pages.postTitle', 'Post', 'Post');
  String get commentsTitle =>
      copy.contextualText('pages.commentsTitle', 'Comments', 'Komentarze');
  String get earlierComments =>
      copy.text('Earlier comments', 'Wcześniejsze komentarze');
  String get authorBadge =>
      copy.contextualText('pages.authorBadge', 'Author', 'Autor');
  String get writeComment => copy.text('Write a comment…', 'Napisz komentarz…');
  String get sendComment => copy.text('Publish comment', 'Opublikuj komentarz');
  String get closedReadOnly => copy.text(
    'Comments are closed while this Page is paused.',
    'Komentarze są wyłączone, dopóki strona jest wstrzymana.',
  );
  String get closedByPage => copy.text(
    'The Page turned comments off for this post.',
    'Strona wyłączyła komentarze pod tym postem.',
  );
  String get noComments =>
      copy.text('No comments yet', 'Nie ma jeszcze komentarzy');
  String get noCommentsBody =>
      copy.text('Write the first comment.', 'Napisz pierwszy komentarz.');
  String get loadingPost => copy.text('Loading post', 'Wczytywanie posta');
  String get loadPostError => copy.text(
    "Couldn't load the post. Check your connection.",
    'Nie udało się wczytać posta. Sprawdź połączenie.',
  );
  String get postUnavailable =>
      copy.text('This post is unavailable', 'Ten post jest niedostępny');
  String get postUnavailableBody => copy.text(
    'It may have been deleted, or the Page is no longer visible.',
    'Mógł zostać usunięty albo strona nie jest już widoczna.',
  );
  String get loadCommentsError => copy.text(
    "Couldn't load the comments.",
    'Nie udało się wczytać komentarzy.',
  );
  String get loadingComments =>
      copy.text('Loading comments', 'Wczytywanie komentarzy');

  String commentLabel(String name, String age, {required bool author}) => author
      ? copy.template(
          '{name}, author, {age}',
          '{name}, autor, {age}',
          values: <String, Object>{'name': name, 'age': age},
        )
      : copy.template(
          '{name}, {age}',
          '{name}, {age}',
          values: <String, Object>{'name': name, 'age': age},
        );

  String commentOptions(String name) => copy.template(
    'Comment options, {name}',
    'Opcje komentarza, {name}',
    values: <String, Object>{'name': name},
  );

  // Comment and post menus.
  String get deleteComment => copy.text('Delete comment', 'Usuń komentarz');
  String get reportComment => copy.text('Report comment', 'Zgłoś komentarz');
  String get reportPost => copy.text('Report post', 'Zgłoś post');
  String get deleteCommentTitle =>
      copy.text('Delete this comment?', 'Usunąć ten komentarz?');
  String get deleteCommentBody =>
      copy.text('It will disappear for everyone.', 'Zniknie dla wszystkich.');
  String get commentDeleted =>
      copy.text('Comment deleted', 'Komentarz usunięty');
  String get turnCommentsOff =>
      copy.text('Turn off comments', 'Wyłącz komentarze');
  String get turnCommentsOn =>
      copy.text('Turn on comments', 'Włącz komentarze');
  String get commentsNowOff => copy.text(
    'Comments are off for this post',
    'Komentarze pod tym postem są wyłączone',
  );
  String get commentsNowOn => copy.text(
    'Comments are on for this post',
    'Komentarze pod tym postem są włączone',
  );
  String get reportPostTitle => copy.text('Report this post', 'Zgłoś ten post');
  String get reportCommentTitle =>
      copy.text('Report this comment', 'Zgłoś ten komentarz');

  String commentError(PagesFailure failure) => switch (failure) {
    PagesFailure.commentLinks => copy.text(
      "Links can't be posted in comments.",
      'W komentarzach nie można umieszczać linków.',
    ),
    PagesFailure.commentsOff => closedByPage,
    PagesFailure.readOnly => closedReadOnly,
    PagesFailure.rateLimited => copy.text(
      'Too many tries. Try again later.',
      'Zbyt wiele prób. Spróbuj ponownie później.',
    ),
    PagesFailure.unavailable => postUnavailable,
    PagesFailure.invalidInput => copy.text(
      "This comment can't be sent. Check the text.",
      'Nie można wysłać tego komentarza. Sprawdź treść.',
    ),
    _ => copy.text(
      "Couldn't send the comment. Try again.",
      'Nie udało się wysłać komentarza. Spróbuj ponownie.',
    ),
  };

  String get deleteCommentError => copy.text(
    "Couldn't delete the comment. Try again.",
    'Nie udało się usunąć komentarza. Spróbuj ponownie.',
  );

  // ---- Upsell (R11) -----------------------------------------------------------

  String get upsellTitle => copy.text(
    'Your own Page is a VIP feature',
    'Własna strona to funkcja VIP',
  );
  String get upsellBody => copy.text(
    'A business or community Page is run by an account with YO Voice VIP. For now, VIP is given to testers.',
    'Stronę firmową lub społeczności prowadzi konto z YO Voice VIP. Na razie VIP otrzymują testerzy.',
  );
  String get upsellNotForSale => copy.text(
    "Premium isn't available to buy yet.",
    'Premium nie jest jeszcze dostępne do kupienia.',
  );
  String get upsellFree => copy.text(
    'Following Pages and reading posts is free for everyone.',
    'Obserwowanie stron i czytanie postów jest bezpłatne dla wszystkich.',
  );
  String get gotIt => copy.text('Got it', 'Rozumiem');
  String get seePremium =>
      copy.text('See what Premium offers', 'Zobacz, co daje Premium');
  String get premiumOffer => copy.text('Premium offer', 'Oferta Premium');
}
