import 'package:intl/intl.dart';

import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// The copy of the Page profile B, create A, Page settings A and the Premium
/// "Twoja strona" block (spec premium-pages §4.3, §4.4, §5; renders profile
/// B, create A, R2, R6, R8-R10, R12, R13). English is the catalog key and
/// Polish is authored here, as in [PagesCopy].
extension PageProfileCopy on PagesCopy {
  // ---- Categories (§1.8) -----------------------------------------------------

  String categoryLabel(String key) => switch (key) {
    'cafe_restaurant' => copy.text(
      'Café and restaurant',
      'Kawiarnia i restauracja',
    ),
    'shop' => copy.contextualText('pages.category.shop', 'Shop', 'Sklep'),
    'beauty_wellness' => copy.text('Beauty and wellness', 'Uroda i zdrowie'),
    'sport_fitness' => copy.text('Sport and fitness', 'Sport i fitness'),
    'education' => copy.contextualText(
      'pages.category.education',
      'Education',
      'Edukacja',
    ),
    'music_arts' => copy.text('Music and arts', 'Muzyka i sztuka'),
    'media_podcast' => copy.text('Media and podcasts', 'Media i podcasty'),
    'services' => copy.contextualText(
      'pages.category.services',
      'Services',
      'Usługi',
    ),
    'tech' => copy.contextualText('pages.category.tech', 'Tech', 'Technologia'),
    'local_travel' => copy.text('Local and travel', 'Lokalnie i podróże'),
    'other_business' => copy.text('Other business', 'Inna działalność'),
    'sport' => copy.contextualText('pages.category.sport', 'Sport', 'Sport'),
    'music' => copy.contextualText('pages.category.music', 'Music', 'Muzyka'),
    'gaming' => copy.contextualText('pages.category.gaming', 'Gaming', 'Gry'),
    'books_learning' => copy.text('Books and learning', 'Książki i nauka'),
    'hobby_crafts' => copy.text('Hobbies and crafts', 'Hobby i rękodzieło'),
    'local_neighbourhood' => copy.text(
      'Local neighbourhood',
      'Okolica i sąsiedzi',
    ),
    'fan_club' => copy.contextualText(
      'pages.category.fanClub',
      'Fan club',
      'Fanklub',
    ),
    'charity_cause' => copy.text(
      'Charity and causes',
      'Pomoc i sprawy społeczne',
    ),
    'other_community' => copy.text('Other community', 'Inna społeczność'),
    _ => key,
  };

  /// "Kategoria" (Firma) / "Temat" (Społeczność).
  String categoryField(PageKind kind) => kind == PageKind.business
      ? copy.contextualText('pages.categoryField', 'Category', 'Kategoria')
      : copy.contextualText('pages.topicField', 'Topic', 'Temat');

  /// Page settings' exact count (R6): "1 214 obserwujących".
  String exactFollowers(int count) {
    final number = NumberFormat.decimalPattern(copy.localeKey).format(count);
    final line = copy.pluralTemplate(
      count: count,
      stem: '{count} followers',
      englishOne: '{count} follower',
      englishOther: '{count} followers',
      polishOne: '{count} obserwujący',
      polishFew: '{count} obserwujących',
      polishMany: '{count} obserwujących',
    );
    return number == '$count' ? line : line.replaceFirst('$count', number);
  }

  /// "Firma · 1,2 tys. obserwujących".
  String headerMeta(PageKind kind, int followerCount) =>
      '${kindLabel(kind)} · ${followers(followerCount)}';

  /// "od marca 2025" / "since March 2025".
  String onYoVoiceSince(DateTime since) {
    final month = DateFormat('MMMM y', copy.localeKey).format(since.toLocal());
    return copy.template(
      'since {month}',
      'od {month}',
      values: <String, Object>{'month': month},
    );
  }

  // ---- Profile actions (profile B, R8, R10, R15) -----------------------------

  String get message =>
      copy.contextualText('pages.message', 'Message', 'Wiadomość');
  String get unfollow => copy.text('Stop following', 'Przestań obserwować');
  String get newPost => copy.text('New post', 'Nowy post');
  String get editPage => copy.text('Edit Page', 'Edytuj stronę');
  String get pageSettings => copy.text('Page settings', 'Ustawienia strony');
  String get resumePage => copy.text('Resume Page', 'Wznów stronę');
  String get pausePage => copy.text('Pause Page', 'Wstrzymaj stronę');
  String get followingMenu =>
      copy.text('Following, more options', 'Obserwujesz, więcej opcji');
  String get tabWall =>
      copy.contextualText('pages.tabWall', 'Posts', 'Tablica');
  String get tabAbout =>
      copy.contextualText('pages.tabAbout', 'About', 'Informacje');
  String get tabPhotos =>
      copy.contextualText('pages.tabPhotos', 'Photos', 'Zdjęcia');
  String get pageSections => copy.text('Page sections', 'Sekcje strony');
  String get pinned =>
      copy.contextualText('pages.pinned', 'Pinned', 'Przypięty');
  String get goBack => copy.text('Back', 'Wróć');
  String get loadingPage => copy.text('Loading the Page', 'Wczytywanie strony');
  String get loadPageError => copy.text(
    "Couldn't load this Page. Check your connection.",
    'Nie udało się wczytać strony. Sprawdź połączenie.',
  );
  String get noPostsYet => copy.text('No posts yet', 'Jeszcze nie ma postów');
  String get noPostsBody => copy.text(
    'Posts from this Page will appear here.',
    'Tu pojawią się posty tej strony.',
  );
  String get ownerNoPostsBody => copy.text(
    'Your first post will appear here and in your followers’ Content tab.',
    'Twój pierwszy post pojawi się tutaj i w zakładce Treści obserwujących.',
  );
  String get noPhotosYet => copy.text('No photos yet', 'Jeszcze nie ma zdjęć');

  // ---- Held post (R8) --------------------------------------------------------

  String get heldTitle =>
      copy.text('Hidden by moderation', 'Ukryty przez moderację');
  String get heldBody => copy.text(
    'Only you can see it until it has been reviewed',
    'Widzisz go tylko Ty, do czasu weryfikacji',
  );
  String get heldDetails => copy.text(
    'A report on this post is being reviewed. Until then only you can see it. You can delete it; nothing else changes until the review ends.',
    'Zgłoszenie tego posta jest sprawdzane. Do tego czasu widzisz go tylko Ty. Możesz go usunąć; nic innego się nie zmieni do końca weryfikacji.',
  );
  String get details => copy.text('Details', 'Szczegóły');
  String get deletePost => copy.text('Delete post', 'Usuń post');
  String get deletePostTitle => copy.text('Delete post?', 'Usunąć post?');
  String get deletePostBody => copy.text(
    'The post, its likes and its comments will be removed from your Page.',
    'Post, jego polubienia i komentarze znikną ze strony.',
  );
  String get delete => copy.contextualText('pages.delete', 'Delete', 'Usuń');
  String get cancel => copy.contextualText('pages.cancel', 'Cancel', 'Anuluj');
  String get pinPost => copy.text('Pin to top', 'Przypnij na górze');
  String get unpinPost => copy.text('Unpin', 'Odepnij');
  String get postDeleted => copy.text('Post deleted', 'Post usunięty');
  String get postPinned => copy.text('Post pinned', 'Post przypięty');
  String get postUnpinned => copy.text('Post unpinned', 'Post odpięty');

  // ---- Notices (R12) ---------------------------------------------------------

  String get readOnlyTitle =>
      copy.text('Read-only Page', 'Strona tylko do odczytu');

  /// The owner's read-only notice with the Day-30 countdown (§2.8).
  String readOnlyBody({int? daysSince, int? daysLeft}) {
    if (daysSince == null || daysLeft == null) {
      return copy.text(
        "YO Voice VIP has ended. Your posts are still visible, but you can't publish or edit the Page. After 30 days the Page will be hidden. Nothing will be deleted, and it all comes back when you have VIP again.",
        'YO Voice VIP wygasł. Posty są nadal widoczne, ale nie możesz publikować ani edytować strony. Po 30 dniach strona zostanie ukryta. Nic nie zostanie usunięte, a gdy znów będziesz mieć VIP, strona wróci w całości.',
      );
    }
    return copy.template(
      "YO Voice VIP ended {since} days ago. Your posts are still visible, but you can't publish or edit the Page. In {left} days the Page will be hidden. Nothing will be deleted, and it all comes back when you have VIP again.",
      'YO Voice VIP wygasł {since} dni temu. Posty są nadal widoczne, ale nie możesz publikować ani edytować strony. Za {left} dni strona zostanie ukryta. Nic nie zostanie usunięte, a gdy znów będziesz mieć VIP, strona wróci w całości.',
      values: <String, Object>{'since': daysSince, 'left': daysLeft},
    );
  }

  String get hiddenTitle => copy.text('Page hidden', 'Strona ukryta');
  String get hiddenBody => copy.text(
    "It's been 30 days without YO Voice VIP. Only you can see the Page; others see your personal profile. Your posts and followers are kept and come back when you have VIP again.",
    'Minęło 30 dni bez YO Voice VIP. Stronę widzisz tylko Ty, a inni widzą Twój profil osobisty. Posty i obserwujący są zachowani i wrócą, gdy znów będziesz mieć VIP.',
  );
  String get pausedTitle => copy.text('Page paused', 'Strona wstrzymana');
  String get pausedBody => copy.text(
    "It doesn't appear in Content or search. Posts, followers and contact details are kept.",
    'Nie widać jej w Treściach ani w wyszukiwaniu. Posty, obserwujący i dane kontaktowe są zachowane.',
  );
  String get pausedPrivateBody => copy.text(
    'Your Page was paused because your profile is no longer public. To resume it, make your profile public.',
    'Strona została wstrzymana, bo profil nie jest już publiczny. Aby ją wznowić, ustaw profil jako publiczny.',
  );
  String get profileVisibility =>
      copy.text('Profile visibility', 'Widoczność profilu');
  String get suspendedTitle => copy.text(
    'Page suspended by moderation',
    'Strona zawieszona przez moderację',
  );
  String suspendedBody(String? reason) {
    final tail = copy.text(
      "The Page isn't visible to others and you can't publish. Posts have not been deleted.",
      'Strona nie jest widoczna dla innych i nie możesz publikować. Posty nie zostały usunięte.',
    );
    if (reason == null) return tail;
    return copy.template(
      'Reason: {reason}. {rest}',
      'Powód: {reason}. {rest}',
      values: <String, Object>{
        'reason': suspensionReason(reason),
        'rest': tail,
      },
    );
  }

  /// A moderator's reason key in words; an unknown key is shown as sent.
  String suspensionReason(String key) => switch (key) {
    'spam' => copy.contextualText('pages.reason.spam', 'spam', 'spam'),
    'restrictedCategory' => copy.text(
      'restricted category',
      'niedozwolona kategoria',
    ),
    'impersonation' => copy.text('impersonation', 'podszywanie się'),
    'harassment' => copy.text('harassment', 'nękanie'),
    'scam' || 'fraud' => copy.text('fraud', 'oszustwo'),
    _ => key,
  };
  String get seeStatement =>
      copy.text('See the statement of reasons', 'Zobacz uzasadnienie');
  String get statementBody => copy.text(
    'The full statement of reasons is in your notifications. You can appeal by replying to the moderation team from there.',
    'Pełne uzasadnienie jest w Twoich powiadomieniach. Stamtąd możesz odwołać się do zespołu moderacji.',
  );
  String get visitorReadOnlyTitle => copy.text(
    "This Page isn't publishing right now.",
    'Ta strona obecnie nie publikuje.',
  );
  String get visitorReadOnlyBody => copy.text(
    'Comments are closed while this Page is paused. You can still read and like earlier posts.',
    'Komentarze są wyłączone, dopóki strona jest wstrzymana. Wcześniejsze posty możesz czytać i polubić.',
  );
  String get gotIt => copy.contextualText('pages.gotIt', 'Got it', 'Rozumiem');

  // ---- About (R9) ------------------------------------------------------------

  String get aboutBusiness => copy.text('About the business', 'O firmie');
  String get aboutCommunity =>
      copy.text('About the community', 'O społeczności');
  String get aboutTitle =>
      copy.contextualText('pages.aboutTitle', 'About', 'Informacje');
  String get contactAndHours =>
      copy.text('Contact and hours', 'Kontakt i godziny');
  String get addressLabel =>
      copy.contextualText('pages.address', 'Address', 'Adres');
  String get hoursLabel =>
      copy.contextualText('pages.hours', 'Hours', 'Godziny');
  String get phoneLabel =>
      copy.contextualText('pages.phone', 'Phone', 'Telefon');
  String get emailLabel =>
      copy.contextualText('pages.email', 'E-mail', 'E-mail');
  String get websiteLabel =>
      copy.contextualText('pages.website', 'Website', 'Strona www');
  String get onYoVoice => copy.text('On YO Voice', 'Na YO Voice');
  String get legalNotice =>
      copy.contextualText('pages.legalNotice', 'Legal notice', 'Nota prawna');
  String get rulesTitle =>
      copy.contextualText('pages.rules', 'Rules', 'Zasady');
  String get communityServer =>
      copy.text('Community server', 'Serwer społeczności');
  String get publicServer => copy.text('Public server', 'Serwer publiczny');
  String get open => copy.contextualText('pages.open', 'Open', 'Otwórz');
  String get serverNote => copy.text(
    'Voice channels, chat and events are on the server. The Page owner runs the server.',
    'Kanały głosowe, czat i wydarzenia są na serwerze. Serwer prowadzi właściciel strony.',
  );
  String get notVerifiedLine => copy.text(
    "YO Voice doesn't verify identities or business details.",
    'YO Voice nie weryfikuje tożsamości ani danych firm.',
  );
  String get ownerOnlyPosts => copy.text(
    'Only the Page owner publishes posts on the Page.',
    'Posty na stronie publikuje tylko jej właściciel.',
  );
  String get reportPage => copy.text('Report Page', 'Zgłoś stronę');
  String get photosTitle =>
      copy.contextualText('pages.photosTitle', 'Photos', 'Zdjęcia');
  String get seeAllPhotos =>
      copy.text('See all photos', 'Zobacz wszystkie zdjęcia');
  String get couldNotOpenLink =>
      copy.text("Couldn't open the link.", 'Nie udało się otworzyć linku.');

  // ---- ⋯ menus (R10) ---------------------------------------------------------

  String get yourFriend =>
      copy.contextualText('pages.yourFriend', 'Your friend', 'Twój znajomy');
  String get call => copy.contextualText('pages.call', 'Call', 'Zadzwoń');
  String get sendVoiceMessage =>
      copy.text('Send a voice message', 'Wyślij wiadomość głosową');
  String get inviteToServer =>
      copy.text('Invite to a server', 'Zaproś na serwer');
  String get sharePage => copy.text('Share Page', 'Udostępnij stronę');
  String get removeFriend => copy.text('Remove friend', 'Usuń ze znajomych');
  String get block => copy.contextualText('pages.block', 'Block', 'Zablokuj');
  String get removeFriendTitle =>
      copy.text('Remove friend?', 'Usunąć ze znajomych?');
  String removeFriendBody(String name) => copy.template(
    '{name} will be removed from your friends list.',
    '{name} zniknie z Twojej listy znajomych.',
    values: <String, Object>{'name': name},
  );
  String get blockTitle =>
      copy.text('Block this account?', 'Zablokować to konto?');
  String blockBody(String name) => copy.template(
    "{name} will be removed as a friend and won't be able to message you, follow you or send you requests. You'll stop seeing this Page. You can unblock it any time.",
    '{name} zostanie usunięty ze znajomych i nie będzie mógł wysyłać Ci wiadomości, obserwować Cię ani zapraszać. Przestaniesz widzieć tę stronę. Możesz odblokować w dowolnej chwili.',
    values: <String, Object>{'name': name},
  );
  String reportTitle(String name) => copy.template(
    'Report {name}',
    'Zgłoś stronę {name}',
    values: <String, Object>{'name': name},
  );
  String get reportSubtitle => copy.text(
    "Your report goes to the YO Voice moderation team. The Page isn't told who reported it.",
    'Zgłoszenie trafi do zespołu moderacji YO Voice. Strona nie dowie się, kto ją zgłosił.',
  );
  String get reported => copy.text(
    'Reported. Our team will review it.',
    'Zgłoszono. Nasz zespół to sprawdzi.',
  );
  String get reportFailed => copy.text(
    "Your report couldn't be sent. Try again.",
    'Nie udało się wysłać zgłoszenia. Spróbuj ponownie.',
  );

  /// A refused report in words (`pageReportTargetMissing`,
  /// `pageReportOwnContent`, a rate limit); anything else is [reportFailed].
  String reportError(PagesFailure failure) => switch (failure) {
    PagesFailure.unavailable => copy.text(
      'That content is no longer available.',
      'Ta treść nie jest już dostępna.',
    ),
    PagesFailure.ownContent => copy.text(
      "You can't report your own content.",
      'Nie możesz zgłosić własnej treści.',
    ),
    _ => reportFailed,
  };
  String get actionFailed => copy.text(
    "That didn't work. Try again.",
    'Nie udało się. Spróbuj ponownie.',
  );
  String get chatFailed =>
      copy.text("Couldn't open the chat.", 'Nie udało się otworzyć rozmowy.');

  // ---- E7 (deep link to a Page that cannot be opened) ------------------------

  String get e7Title =>
      copy.text("This Page isn't available", 'Ta strona jest niedostępna');
  String get e7Body => copy.text(
    "You can't open it right now.",
    'Nie możesz jej teraz otworzyć.',
  );
  String get backToContent => copy.text('Back to Content', 'Wróć do Treści');

  // ---- Create A (steps 1-3, R2) ----------------------------------------------

  String get newPage => copy.text('New Page', 'Nowa strona');
  String stepOf(int step) => copy.template(
    'Step {step} of 3',
    'Krok {step} z 3',
    values: <String, Object>{'step': step},
  );
  String get stepKind =>
      copy.contextualText('pages.stepKind', 'Type', 'Rodzaj');
  String get stepDetails =>
      copy.contextualText('pages.stepDetails', 'Details', 'Szczegóły');
  String get stepPreview =>
      copy.contextualText('pages.stepPreview', 'Preview', 'Podgląd');
  String get next => copy.contextualText('pages.next', 'Next', 'Dalej');
  String get step1Title => copy.text(
    'What kind of Page do you want to run?',
    'Jaką stronę chcesz prowadzić?',
  );
  String get step1Lead => copy.text(
    'A Page is your account as a channel: you publish posts, and anyone can follow them.',
    'Strona to Twoje konto w formie kanału: publikujesz posty, a każdy może je obserwować.',
  );
  String get step1LeadWide => copy.text(
    'A Page is your account as a channel: you publish posts, and anyone can follow them in the Content tab.',
    'Strona to Twoje konto w formie kanału: publikujesz posty, a każdy może je obserwować w zakładce Treści.',
  );
  String get businessTitle => copy.text('Business Page', 'Strona firmowa');
  String get businessExample =>
      copy.text('Café, studio, shop, brand', 'Kawiarnia, studio, sklep, marka');
  List<String> get businessBullets => [
    copy.text('Category, hours and contact', 'Kategoria, godziny i kontakt'),
    // V1 (§9.3, approved): "Wiadomość", not "Kontakt".
    copy.text(
      'A "Message" button on your Page',
      'Przycisk „Wiadomość” na stronie',
    ),
    copy.text('Only you publish posts', 'Posty publikujesz tylko Ty'),
  ];
  String get communityTitle =>
      copy.text('Community Page', 'Strona społeczności');
  String get communityExample => copy.text(
    'Running club, fan club, hobby group',
    'Klub biegowy, fanklub, grupa hobbystyczna',
  );
  List<String> get communityBullets => [
    copy.text('Topic and rules', 'Temat i zasady'),
    copy.text('A link to your server', 'Połączenie z Twoim serwerem'),
    copy.text('Only you publish posts', 'Posty publikujesz tylko Ty'),
  ];

  /// V2 (§9.3, approved): "w ustawieniach strony", not "w Studio twórcy".
  String get step1Info => copy.text(
    'Your profile will look like a Page. You can pause it any time in Page settings.',
    'Twój profil będzie wyglądał jak strona. Wstrzymasz ją w każdej chwili w ustawieniach strony.',
  );
  String get step2Title => copy.text('Page details', 'Szczegóły strony');
  String get step2Lead => copy.text(
    'Everyone who opens your Page will see this.',
    'Te informacje zobaczy każdy, kto otworzy Twoją stronę.',
  );
  String get changeNameAndPhoto => copy.text(
    'Change your name and photo in your profile',
    'Zmień nazwę i zdjęcie w profilu',
  );
  String get chooseCategory =>
      copy.text('Choose a category', 'Wybierz kategorię');
  String get chooseTopic => copy.text('Choose a topic', 'Wybierz temat');
  String get descriptionLabel =>
      copy.contextualText('pages.description', 'Description', 'Opis');
  String get contactOverline =>
      copy.contextualText('pages.contactOverline', 'Contact', 'Kontakt');
  String get allOptional => copy.text('all optional', 'wszystko opcjonalne');
  String get contactEmailLabel =>
      copy.text('Contact e-mail', 'E-mail kontaktowy');
  String get addressOrAreaLabel =>
      copy.text('Address or area', 'Adres lub obszar');
  String get legalNoticeFieldLabel =>
      copy.text('Business details (legal notice)', 'Dane firmy (nota prawna)');
  String get legalNoticeHint => copy.text(
    'E.g. company name, tax ID, registered address',
    'Np. nazwa firmy, NIP, adres rejestrowy',
  );
  String get linkedServerLabel =>
      copy.text('Linked server', 'Połączony serwer');
  String get linkedServerHelper => copy.text(
    'Your public community and podcast servers',
    'Twoje publiczne serwery społeczności i podcastów',
  );
  String get noLinkedServer => copy.text('No server', 'Bez serwera');
  String get noEligibleServers => copy.text(
    'You have no public community or podcast server to link.',
    'Nie masz publicznego serwera społeczności ani podcastu do połączenia.',
  );
  String get confirmationOverline => copy.contextualText(
    'pages.confirmation',
    'Confirmation',
    'Potwierdzenie',
  );
  String get birthDateLabel => copy.text('Date of birth', 'Data urodzenia');
  String get birthDateHelper => copy.text(
    "Only to confirm you're 18 or older. We don't store it.",
    'Tylko do potwierdzenia, że masz 18 lat. Nie zapisujemy jej.',
  );
  String get birthDatePicker => copy.text(
    'Confirm that you are 18+',
    'Potwierdź, że masz co najmniej 18 lat',
  );
  String get chooseBirthDate =>
      copy.text('Choose your date of birth', 'Wybierz datę urodzenia');
  String get consentBusiness => copy.text(
    'I understand that the contact details will be public. They stay saved while the Page is paused. I can clear them any time.',
    'Rozumiem, że dane kontaktowe będą widoczne publicznie. Zostają zapisane, gdy strona jest wstrzymana. Możesz je usunąć w każdej chwili.',
  );
  String get consentCommunity => copy.text(
    "I understand that the Page's name, photo, description and rules will be public.",
    'Rozumiem, że nazwa, zdjęcie, opis i zasady strony będą widoczne publicznie.',
  );
  String get consentRequired =>
      copy.text('Tick the box to continue.', 'Zaznacz, aby kontynuować.');
  String get publicHelper =>
      copy.text('Visible to everyone', 'Widoczne publicznie');
  String get httpsOnly => copy.text('https:// only', 'tylko https://');
  String get websiteError => copy.text(
    'Use a full address starting with https://',
    'Podaj pełny adres zaczynający się od https://',
  );
  String get emailError =>
      copy.text('Enter a valid e-mail address', 'Podaj poprawny adres e-mail');
  String get phoneError => copy.text(
    'Use the international format, e.g. +48 58 555 01 27',
    'Użyj formatu międzynarodowego, np. +48 58 555 01 27',
  );
  String get phoneHelper =>
      copy.text('E.g. +48 58 555 01 27', 'Np. +48 58 555 01 27');
  String tooLong(int max) => copy.template(
    'At most {max} characters',
    'Najwyżej {max} znaków',
    values: <String, Object>{'max': max},
  );
  String get step3Title =>
      copy.text("This is how others will see it", 'Tak zobaczą ją inni');
  String get step3Lead => copy.text(
    'Check your Page before publishing. You can change everything later.',
    'Sprawdź stronę przed publikacją. Wszystko zmienisz później.',
  );
  String get previewOverline =>
      copy.contextualText('pages.previewOverline', 'Preview', 'Podgląd');
  String get previewOnWall =>
      copy.text('On the Content wall', 'Na ścianie Treści');
  String get previewProfile => copy.text('Page profile', 'Profil strony');
  String get whatHappens => copy.text('What happens', 'Co się stanie');
  String get whatFollow => copy.text(
    'Anyone can follow the Page and see its posts. Only you publish posts.',
    'Każdy może obserwować stronę i widzieć jej posty. Posty publikujesz tylko Ty.',
  );
  String get whatProfile => copy.text(
    'Your profile will show as a Page. You can pause it any time in Page settings.',
    'Twój profil wyświetli się jako strona. Wstrzymasz ją w każdej chwili w ustawieniach strony.',
  );
  String get whatLapse => copy.text(
    'If VIP ends, the Page is read-only for 30 days and then hidden. Nothing is deleted.',
    'Gdy VIP wygaśnie, strona przez 30 dni będzie tylko do odczytu, a potem ukryta. Nic nie zostanie usunięte.',
  );
  String get publishPage => copy.text('Publish Page', 'Opublikuj stronę');
  String get publishFailed => copy.text(
    "Couldn't publish the Page",
    'Nie udało się opublikować strony',
  );
  String get close => copy.contextualText('pages.close', 'Close', 'Zamknij');
  String get pagePublished =>
      copy.text('Your Page is live', 'Twoja strona jest już widoczna');
  String zeroFollowersMeta(PageKind kind) =>
      '${kindLabel(kind)} · ${followers(0)}';

  /// §5: every refusal of create / update / resume in words.
  String manageError(PagesFailure failure) => switch (failure) {
    PagesFailure.accessRequired => copy.text(
      'YO Voice VIP is required to run a Page.',
      'Do prowadzenia strony potrzebny jest YO Voice VIP.',
    ),
    PagesFailure.adultRequired => copy.text(
      'You must be 18 or older to run a Page.',
      'Aby prowadzić stronę, musisz mieć ukończone 18 lat.',
    ),
    PagesFailure.hasAudience => copy.text(
      "Pages can't be created on an account that already has followers yet.",
      'Na koncie, które ma już obserwujących, nie można jeszcze utworzyć strony.',
    ),
    PagesFailure.nameReserved => copy.text(
      "This name can't be used for a Page.",
      'Tej nazwy nie można użyć dla strony.',
    ),
    PagesFailure.profileNotPublic => copy.text(
      'A Page needs a public profile. Make your profile public and try again.',
      'Strona wymaga publicznego profilu. Ustaw profil jako publiczny i spróbuj ponownie.',
    ),
    PagesFailure.pageExists => copy.text(
      'This account already has a Page.',
      'To konto ma już stronę.',
    ),
    PagesFailure.notEnabled => copy.text(
      "Pages aren't available right now.",
      'Strony są chwilowo niedostępne.',
    ),
    PagesFailure.linkedServerInvalid => copy.text(
      "The linked server isn't available any more. Choose another one.",
      'Połączony serwer nie jest już dostępny. Wybierz inny.',
    ),
    PagesFailure.invalidInput => copy.text(
      'Check the fields and try again.',
      'Sprawdź pola i spróbuj ponownie.',
    ),
    PagesFailure.rateLimited => copy.text(
      'Too many tries. Try again later.',
      'Zbyt wiele prób. Spróbuj ponownie później.',
    ),
    PagesFailure.unavailable => copy.text(
      "This Page can't be changed right now.",
      'Tej strony nie można teraz zmienić.',
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

  // ---- Page settings A (R6) --------------------------------------------------

  String get pageGroup =>
      copy.contextualText('pages.pageGroup', 'Page', 'Strona');
  String get contactGroup => copy.text(
    'Contact · visible to everyone',
    'Kontakt · widoczne publicznie',
  );
  String get communityGroup => copy.text(
    'Community · visible to everyone',
    'Społeczność · widoczne publicznie',
  );
  String get followersGroup =>
      copy.contextualText('pages.followersGroup', 'Followers', 'Obserwujący');
  String get visibilityGroup =>
      copy.text('Page visibility', 'Widoczność strony');
  String get pageType => copy.text('Page type', 'Typ strony');
  String get pageTypeLocked => copy.text(
    "The Page type can't be changed",
    'Typu strony nie można zmienić',
  );
  String get nameAndPhotos =>
      copy.text('Name, photo and cover', 'Nazwa, zdjęcie i okładka');
  String get nameAndPhotosBody => copy.text(
    'You change them in your profile',
    'Zmieniasz je w edycji profilu',
  );
  String get notAdded => copy.text('Not added', 'Nie dodano');
  String get add => copy.contextualText('pages.add', 'Add', 'Dodaj');
  String get retention => copy.text(
    'Contact details stay saved while your Page is paused. You can clear them any time.',
    'Dane kontaktowe zostają zapisane, gdy strona jest wstrzymana. Możesz je usunąć w każdej chwili.',
  );
  String get followersOnlyCount => copy.text(
    "You see the count only. The list of followers isn't available.",
    'Widzisz tylko liczbę. Lista obserwujących nie jest dostępna.',
  );
  String get pauseSubtitle => copy.text(
    'The Page disappears from Content and search. Posts and followers are kept.',
    'Strona zniknie z Treści i wyszukiwania. Posty i obserwujący zostaną zachowani.',
  );
  String get resumeSubtitle => copy.text(
    'The Page comes back to Content and search',
    'Strona wróci do Treści i wyszukiwania',
  );
  String get resumeNeedsPublic => copy.text(
    'First make your profile public',
    'Najpierw ustaw profil jako publiczny',
  );
  String get resumeNeedsVip =>
      copy.text('Needs YO Voice VIP', 'Wymaga YO Voice VIP');
  String get accountFootnote => copy.text(
    "The Page is part of your account. It's only deleted together with the account.",
    'Strona jest częścią Twojego konta. Usuniesz ją tylko razem z kontem.',
  );
  String get statusActive =>
      copy.contextualText('pages.statusActive', 'Active', 'Aktywna');
  String get statusPaused =>
      copy.contextualText('pages.statusPaused', 'Paused', 'Wstrzymana');
  String get statusReadOnly => copy.contextualText(
    'pages.statusReadOnly',
    'Read-only',
    'Tylko do odczytu',
  );
  String get statusHidden =>
      copy.contextualText('pages.statusHidden', 'Hidden', 'Ukryta');
  String get statusSuspended =>
      copy.contextualText('pages.statusSuspended', 'Suspended', 'Zawieszona');
  String get pauseTitle => copy.text('Pause your Page?', 'Wstrzymać stronę?');
  String get pauseBody => copy.text(
    'The Page disappears from Content and search until you resume it. Posts, followers and contact details are kept.',
    'Strona zniknie z Treści i wyszukiwania, dopóki jej nie wznowisz. Posty, obserwujący i dane kontaktowe zostaną zachowane.',
  );
  String get pause => copy.contextualText('pages.pause', 'Pause', 'Wstrzymaj');
  String get pagePausedSnack => copy.text('Page paused', 'Strona wstrzymana');
  String get pageResumedSnack => copy.text('Page resumed', 'Strona wznowiona');
  String get saved => copy.contextualText('pages.saved', 'Saved', 'Zapisano');
  String get save => copy.contextualText('pages.save', 'Save', 'Zapisz');
  String get removeNumberFromPage =>
      copy.text('Remove the number from the Page', 'Usuń numer ze strony');
  String get removeFromPage =>
      copy.text('Remove from the Page', 'Usuń ze strony');
  String get publicOnPage => copy.text(
    'Visible to everyone on the Page.',
    'Widoczne publicznie na stronie.',
  );
  String get phoneSheetBody => copy.text(
    'Visible to everyone on the Page. International format.',
    'Widoczny publicznie na stronie. Numer w formacie międzynarodowym.',
  );
  String get phoneNumberLabel => copy.text('Phone number', 'Numer telefonu');
  String get loadSettingsError => copy.text(
    "Couldn't load your Page settings.",
    'Nie udało się wczytać ustawień strony.',
  );
  String get noPageYet =>
      copy.text("This account doesn't have a Page.", 'To konto nie ma strony.');

  // ---- Premium "Twoja strona" block (R2, R13) --------------------------------

  String get yourPageBlockTitle => yourPage;
  String get availableWithVip =>
      copy.text('Available with your VIP', 'Dostępna z Twoim VIP');
  String get businessOrCommunity =>
      copy.text('Business or community', 'Firmowa lub społeczności');
  String get yourPageBlockBody => copy.text(
    'Your account becomes a channel like a server. You publish posts, photos and voice notes, and your followers see them in the Content tab.',
    'Twoje konto staje się kanałem jak serwer. Publikujesz posty, zdjęcia i głosówki, a obserwujący widzą je w zakładce Treści.',
  );
  String get ownPageBlockBody => copy.text(
    'Your account is a Page. Followers see your posts in the Content tab.',
    'Twoje konto jest stroną. Obserwujący widzą Twoje posty w zakładce Treści.',
  );
  String get createPage => copy.text('Create Page', 'Utwórz stronę');
  String get openPage => copy.text('Open Page', 'Otwórz stronę');
  String get ownPageBenefitTitle => copy.text('Your own Page', 'Własna strona');
  String get ownPageBenefitBody => copy.text(
    'Business or community, with posts and followers. At first only for VIP testers',
    'Firmowa lub społeczności, z postami i obserwującymi. Na start tylko dla testerów VIP',
  );
}
