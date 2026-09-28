import 'package:intl/intl.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// Every string the Treści wall, its states, the desktop panel and Find
/// Pages show (spec premium-pages §4.2, §4.7, §5; renders wall A, R4, R5,
/// R15). English is the catalog key and Polish is authored here; the other
/// locales resolve through `translations_pages.dart`.
class PagesCopy {
  const PagesCopy(this.copy);

  final AppLocalizations copy;

  // ---- Header, panel, Find --------------------------------------------------

  String get findPages => copy.text('Find Pages', 'Znajdź strony');
  String get findMorePages =>
      copy.text('Find more Pages', 'Znajdź więcej stron');
  String get followMorePages =>
      copy.text('Follow more Pages', 'Obserwuj więcej stron');
  String get suggestedPages =>
      copy.text('Suggested Pages', 'Proponowane strony');
  String get seeAll => copy.homeSeeAll;
  String get allPosts => copy.text('All posts', 'Wszystkie posty');
  String get followedOverline => copy
      .contextualText('pages.followedOverline', 'Following', 'Obserwowane')
      .toUpperCase();
  String get suggestedOverline => copy
      .contextualText('pages.suggestedOverline', 'Suggested', 'Proponowane')
      .toUpperCase();
  String get pagesOverline => copy
      .contextualText('pages.pagesOverline', 'Pages', 'Strony')
      .toUpperCase();
  String get yourPage => copy.text('Your Page', 'Twoja strona');
  String get searchHint =>
      copy.text('Search Pages by name', 'Szukaj stron po nazwie');
  String get back => copy.text('Back', 'Wstecz');

  String newPostsFrom(String name) => copy.template(
    '{name}, new posts',
    '{name}, nowe posty',
    values: <String, Object>{'name': name},
  );

  // ---- Page identity ---------------------------------------------------------

  String kindLabel(PageKind kind) => switch (kind) {
    PageKind.business => copy.contextualText(
      'pages.kindBusiness',
      'Business',
      'Firma',
    ),
    PageKind.community => copy.contextualText(
      'pages.kindCommunity',
      'Community',
      'Społeczność',
    ),
  };

  /// "1,4 tys. obserwujących" / "1.4K followers": the plural form follows
  /// the exact count, the figure is the compact one.
  String followers(int count) {
    // One decimal at most, as on the approved renders ("1,2 tys.").
    final step = count >= 1000000 ? 100000 : 100;
    final number = count >= 1000
        ? NumberFormat.compact(
            locale: copy.localeKey,
          ).format((count / step).round() * step)
        : '$count';
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

  // ---- Actions ---------------------------------------------------------------

  String get follow =>
      copy.contextualText('pages.follow', 'Follow', 'Obserwuj');
  String get following =>
      copy.contextualText('pages.following', 'Following', 'Obserwujesz');
  String get like => copy.contextualText('pages.like', 'Like', 'Lubię to');
  String get comment =>
      copy.contextualText('pages.comment', 'Comment', 'Komentuj');
  String get share => copy.contextualText('pages.share', 'Share', 'Udostępnij');
  String get sharePost => copy.text('Share post', 'Udostępnij post');
  String get goToPage => copy.text('Go to Page', 'Przejdź do strony');
  String get moreOptions => copy.text('More options', 'Więcej opcji');
  String get showMore => copy.text('Show more', 'Pokaż więcej');
  String get loadMore => copy.text('Load more', 'Wczytaj więcej');
  String get loadingEllipsis => copy.text('Loading…', 'Wczytywanie…');
  String get loadMoreFailed => copy.text(
    "Couldn't load more. Try again.",
    'Nie udało się wczytać więcej. Spróbuj ponownie.',
  );
  String loadedMore(int count) => copy.template(
    'Loaded {count} more',
    'Wczytano kolejne: {count}',
    values: <String, Object>{'count': count},
  );
  String searchResults(int count) => copy.template(
    'Search results: {count}',
    'Wyniki wyszukiwania: {count}',
    values: <String, Object>{'count': count},
  );
  String get tryAgain => copy.text('Try again', 'Spróbuj ponownie');
  String get comingSoon => copy.text('Coming soon', 'Wkrótce');

  String followPage(String name) => copy.template(
    'Follow {name}',
    'Obserwuj: {name}',
    values: <String, Object>{'name': name},
  );

  String unfollowPage(String name) => copy.template(
    'Following {name}. Double-tap to unfollow.',
    'Obserwujesz: {name}. Stuknij dwukrotnie, aby przestać.',
    values: <String, Object>{'name': name},
  );

  // ---- Counts ----------------------------------------------------------------

  /// "48 polubień" / "48 likes".
  String likes(int count) => copy.pluralTemplate(
    count: count,
    stem: '{count} likes',
    englishOne: '{count} like',
    englishOther: '{count} likes',
    polishOne: '{count} polubienie',
    polishFew: '{count} polubienia',
    polishMany: '{count} polubień',
  );

  /// "12 komentarzy" / "12 comments".
  String comments(int count) => copy.pluralTemplate(
    count: count,
    stem: '{count} comments',
    englishOne: '{count} comment',
    englishOther: '{count} comments',
    polishOne: '{count} komentarz',
    polishFew: '{count} komentarze',
    polishMany: '{count} komentarzy',
  );

  /// The likers entry's spoken label (§4.5): "48 polubień, pokaż kto
  /// polubił".
  String likersEntry(int count) => copy.template(
    '{likes}, see who liked',
    '{likes}, pokaż kto polubił',
    values: <String, Object>{'likes': likes(count)},
  );

  /// The like toggle's spoken label (§4.5): "Lubię to, 48 polubień".
  String likeToggle(int count) => copy.template(
    'Like, {likes}',
    'Lubię to, {likes}',
    values: <String, Object>{'likes': likes(count)},
  );

  /// The merged card header (§4.5): "{Page}, Firma, {age}".
  String cardHeader(String name, PageKind kind, String age) => copy.template(
    '{name}, {kind}, {age}',
    '{name}, {kind}, {age}',
    values: <String, Object>{'name': name, 'kind': kindLabel(kind), 'age': age},
  );

  String photoLabel(int index, int total, String page) => copy.template(
    'Photo {index} of {total}, {page}',
    'Zdjęcie {index} z {total}, {page}',
    values: <String, Object>{'index': index, 'total': total, 'page': page},
  );

  String morePhotos(int count) => copy.pluralTemplate(
    count: count,
    stem: '{count} more photos',
    englishOne: '{count} more photo',
    englishOther: '{count} more photos',
    polishOne: 'Jeszcze {count} zdjęcie',
    polishFew: 'Jeszcze {count} zdjęcia',
    polishMany: 'Jeszcze {count} zdjęć',
  );

  String voiceLabel(String duration) => copy.template(
    'Voice post, {duration}',
    'Wiadomość głosowa, {duration}',
    values: <String, Object>{'duration': duration},
  );

  String get playAction =>
      copy.contextualText('pages.voicePlay', 'play', 'odtwórz');
  String get pauseAction =>
      copy.contextualText('pages.voicePause', 'pause', 'wstrzymaj');
  String get voicePlaybackFailed => copy.text(
    "Couldn't play the recording. Tap to try again.",
    'Nie udało się odtworzyć nagrania. Stuknij, aby spróbować ponownie.',
  );

  /// A voice post with no text: nothing in words stands in for the audio.
  String get noTranscript => copy.text('No transcript', 'Bez transkrypcji');

  String get voicePlaybackSoon => copy.text(
    'Playback is coming soon',
    'Odtwarzanie będzie dostępne wkrótce',
  );

  // ---- Ages ------------------------------------------------------------------

  /// The card's age: "18 min", "2 godz.", "wczoraj", "3 dni", then a date.
  String age(DateTime createdAt, DateTime now) {
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return copy.text('now', 'teraz');
    if (diff.inMinutes < 60) {
      return copy.template(
        '{count} min',
        '{count} min',
        values: <String, Object>{'count': diff.inMinutes},
      );
    }
    if (diff.inHours < 24) {
      return copy.template(
        '{count} h',
        '{count} godz.',
        values: <String, Object>{'count': diff.inHours},
      );
    }
    final days = _calendarDays(createdAt, now);
    if (days <= 1) return copy.text('yesterday', 'wczoraj');
    if (days < 7) {
      return copy.template(
        '{count} d',
        '{count} dni',
        values: <String, Object>{'count': days},
      );
    }
    final format = createdAt.year == now.year ? 'd MMM' : 'd MMM y';
    return DateFormat(format, copy.localeKey).format(createdAt.toLocal());
  }

  /// Find rows: "post 2 godz. temu", "post wczoraj", "post 3 dni temu".
  String lastPost(DateTime at, DateTime now) {
    final diff = now.difference(at);
    if (diff.inMinutes < 60) {
      return copy.template(
        'posted {count} min ago',
        'post {count} min temu',
        values: <String, Object>{
          'count': diff.inMinutes < 1 ? 1 : diff.inMinutes,
        },
      );
    }
    if (diff.inHours < 24) {
      return copy.template(
        'posted {count} h ago',
        'post {count} godz. temu',
        values: <String, Object>{'count': diff.inHours},
      );
    }
    final days = _calendarDays(at, now);
    if (days <= 1) return copy.text('posted yesterday', 'post wczoraj');
    return copy.template(
      'posted {count} d ago',
      'post {count} dni temu',
      values: <String, Object>{'count': days},
    );
  }

  static int _calendarDays(DateTime from, DateTime to) {
    final a = from.toLocal();
    final b = to.toLocal();
    return DateTime(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime(a.year, a.month, a.day)).inDays;
  }

  // ---- States (R4, R5) -------------------------------------------------------

  String get e1Title =>
      copy.text('Posts from Pages show up here', 'Tu pojawią się posty stron');
  String get e1Body => copy.text(
    'Pages are run by businesses and communities on YO Voice. Follow them to see their posts here.',
    'Strony prowadzą firmy i społeczności z YO Voice. Obserwuj je, by widzieć ich posty tutaj.',
  );
  String get createYourPage =>
      copy.text('Create your Page', 'Utwórz swoją stronę');
  String get e3Title =>
      copy.text('There are no Pages yet', 'Nie ma jeszcze żadnych stron');
  String get e3Body => copy.text(
    'The first Pages will appear when VIP accounts create them.',
    'Pierwsze strony pojawią się, gdy konta VIP je utworzą.',
  );
  String get e4Title => copy.text('No new posts', 'Brak nowych postów');
  String get e4Body => copy.text(
    "The Pages you follow haven't posted anything yet. Check back later.",
    'Obserwowane strony jeszcze nic nie opublikowały. Zajrzyj później.',
  );
  String get e9Title => copy.text(
    'Content is temporarily unavailable',
    'Treści są chwilowo niedostępne',
  );
  String get e9Body => copy.text(
    'Nothing has been deleted. The Pages you follow and their posts will come back when we turn Content on again.',
    'Nic nie zostało usunięte. Obserwowane strony i ich posty wrócą, gdy włączymy Treści ponownie.',
  );
  String get e9Pill => copy.text('Temporarily off', 'Chwilowo wyłączone');
  String get loadError => copy.text(
    "Couldn't load posts. Check your connection.",
    'Nie udało się wczytać postów. Sprawdź połączenie.',
  );
  String get loadingPosts => copy.text('Loading posts', 'Wczytywanie postów');
  String get nothingFound => copy.text('Nothing found', 'Nic nie znaleziono');
  String get nothingFoundBody => copy.text(
    'Check the spelling or try another name.',
    'Sprawdź pisownię lub spróbuj innej nazwy.',
  );
  String get searchError => copy.text(
    "Couldn't load Pages. Check your connection.",
    'Nie udało się wczytać stron. Sprawdź połączenie.',
  );

  // ---- Create entry (R5) -----------------------------------------------------

  String get createCardBody => copy.text(
    'As a VIP you can run a business or community Page. Only you publish posts.',
    'Jako VIP możesz prowadzić stronę firmy lub społeczności. Posty publikujesz tylko Ty.',
  );
  String get getStarted => copy.text('Get started', 'Zacznij');
  String get hide => copy.text('Hide', 'Ukryj');

  // ---- Owner composer entry (R5) ---------------------------------------------

  String get writeSomething => copy.text('Write something…', 'Napisz coś…');
  String writeAs(String page) => copy.template(
    'Write something as {page}…',
    'Napisz coś jako {page}…',
    values: <String, Object>{'page': page},
  );
  String get recordVoicePost =>
      copy.text('Record a voice post', 'Nagraj post głosowy');
  String get addPhotos => copy.text('Add photos', 'Dodaj zdjęcia');

  // ---- Failures --------------------------------------------------------------

  String followError(PagesFailure failure) => switch (failure) {
    PagesFailure.rateLimited => copy.text(
      'Too many tries. Try again later.',
      'Zbyt wiele prób. Spróbuj ponownie później.',
    ),
    PagesFailure.unavailable || PagesFailure.readOnly => copy.text(
      "This Page isn't accepting followers right now.",
      'Ta strona nie przyjmuje teraz obserwujących.',
    ),
    _ => copy.text(
      "Couldn't update following. Try again.",
      'Nie udało się zmienić obserwowania. Spróbuj ponownie.',
    ),
  };

  String likeError(PagesFailure failure) => switch (failure) {
    PagesFailure.rateLimited => copy.text(
      'Too many tries. Try again later.',
      'Zbyt wiele prób. Spróbuj ponownie później.',
    ),
    _ => copy.text(
      "Couldn't update the like. Try again.",
      'Nie udało się zmienić polubienia. Spróbuj ponownie.',
    ),
  };
}
