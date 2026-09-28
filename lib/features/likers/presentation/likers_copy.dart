import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';

/// Every string the "See who liked" list and its upsell show (spec §5.7 and
/// the owner's §13 choices). The English phrase is the catalog key; the
/// other 41 locales resolve through `translations_vip_likers.dart`.
class LikersCopy {
  const LikersCopy(this.copy);

  final AppLocalizations copy;

  String title(LikersTarget target) => target.isReactions
      ? copy.contextualText('likers.titleReactions', 'Reactions', 'Reakcje')
      : copy.contextualText('likers.titleLikes', 'Likes', 'Polubienia');

  String get tabAll => copy.contextualText('likers.tabAll', 'All', 'Wszystkie');

  String tabLabel(String emoji, int count) => copy.template(
    '{emoji}: {count}',
    '{emoji}: {count}',
    values: <String, Object>{'emoji': emoji, 'count': count},
  );

  String get you => copy.contextualText('likers.you', 'You', 'Ty');

  String reactedRow(String name, String emoji) => copy.template(
    '{name}, reacted {emoji}',
    '{name}, reakcja {emoji}',
    values: <String, Object>{'name': name, 'emoji': emoji},
  );

  String get partial => copy.text(
    'Some people aren\'t shown.',
    'Niektóre osoby nie są tu widoczne.',
  );

  String get empty =>
      copy.text('No one to show here.', 'Nie ma tu nikogo do pokazania.');

  String get hideHint => copy.text(
    'You can hide your own likes in Settings → Privacy.',
    'Swoje polubienia możesz ukryć w Ustawieniach → Prywatność.',
  );

  /// The polite announcement once the first rows arrive: "Reactions" on a
  /// Server message's list, "Likes" everywhere else.
  String loaded(LikersTarget target, int count) => target.isReactions
      ? copy.template(
          'Reactions loaded: {count}',
          'Wczytano reakcje: {count}',
          values: <String, Object>{'count': count},
        )
      : copy.template(
          'Likes loaded: {count}',
          'Wczytano polubienia: {count}',
          values: <String, Object>{'count': count},
        );

  /// The spoken name of the static skeleton while a page loads.
  String get loading => copy.text('Loading', 'Ładowanie');

  /// The screen reader's hint on a liker row ("double-tap to open profile").
  String get openProfile => copy.text('Open profile', 'Otwórz profil');

  String get loadMore => copy.text('Load more', 'Wczytaj więcej');

  String get tryAgain => copy.text('Try again', 'Spróbuj ponownie');

  String get close => copy.text('Close', 'Zamknij');

  String get comingSoon => copy.text(
    'See who liked is coming soon.',
    'Funkcja „Zobacz, kto polubił” będzie dostępna wkrótce.',
  );

  String get unavailable => copy.text(
    'This content is no longer available.',
    'Ta treść nie jest już dostępna.',
  );

  /// The retryable error text for [failure].
  String error(LikersFailure failure) => switch (failure) {
    LikersFailure.rateLimited => copy.text(
      'Too many requests. Try again in a minute.',
      'Zbyt wiele prób. Spróbuj ponownie za minutę.',
    ),
    _ => copy.text(
      'Couldn\'t load this list. Try again.',
      'Nie udało się wczytać listy. Spróbuj ponownie.',
    ),
  };

  // ---- Entry points (owner variant A, spec §5.1) --------------------------

  String get seeWhoLiked => copy.text('See who liked', 'Zobacz, kto polubił');

  String get seeWhoReacted =>
      copy.text('See who reacted', 'Zobacz, kto zareagował');

  /// The visible "Likes · 24" fallback where no likers row can be drawn.
  String likesCount(int count) => copy.template(
    'Likes · {count}',
    'Polubienia · {count}',
    values: <String, Object>{'count': count},
  );

  /// The spoken label of a separate like-count control.
  String seeWhoLikedCount(int count) => copy.template(
    'See who liked. Likes: {count}',
    'Zobacz, kto polubił. Polubienia: {count}',
    values: <String, Object>{'count': count},
  );

  /// The spoken label of a tappable reaction summary.
  String seeWhoReactedCount(int count) => copy.template(
    'See who reacted. Reactions: {count}',
    'Zobacz, kto zareagował. Reakcje: {count}',
    values: <String, Object>{'count': count},
  );

  /// The Top reactions entry's spoken label: the free names stay in it, so
  /// a screen-reader user loses nothing the avatars show.
  String likedByOpen(String names, int remainder) => remainder > 0
      ? copy.template(
          'Liked by {names} and {count} others. See who liked.',
          'Polubili: {names} i inni ({count}). Zobacz, kto polubił.',
          values: <String, Object>{'names': names, 'count': remainder},
        )
      : copy.template(
          'Liked by {names}. See who liked.',
          'Polubili: {names}. Zobacz, kto polubił.',
          values: <String, Object>{'names': names},
        );

  // ---- Comment hearts (owner variant B, spec §5.1) -----------------------

  /// The heart's spoken label, with the count it sits beside (spec §5.1).
  /// The heart's node also carries the toggled flag, so the on/off state is
  /// reported as state, not only through the verb.
  String commentHeart({required bool liked, required int count}) => liked
      ? copy.template(
          'Unlike comment. Likes: {count}',
          'Cofnij polubienie komentarza. Polubienia: {count}',
          values: <String, Object>{'count': count},
        )
      : copy.template(
          'Like comment. Likes: {count}',
          'Polub komentarz. Polubienia: {count}',
          values: <String, Object>{'count': count},
        );

  /// The VIP viewer's named entry beside a comment's count.
  String get whoLiked => copy.text('Who liked', 'Kto polubił');

  /// The spoken name of that named entry: it starts with the visible words
  /// (WCAG 2.5.3), so a speech-control user can say what they see.
  String whoLikedCount(int count) => copy.template(
    'Who liked. Likes: {count}',
    'Kto polubił. Polubienia: {count}',
    values: <String, Object>{'count': count},
  );

  /// The SnackBar after an optimistic comment like was taken back.
  String get likeFailed => copy.text(
    'Couldn\'t update your like. Try again.',
    'Nie udało się zmienić polubienia. Spróbuj ponownie.',
  );

  // ---- Upsell (owner variant U1) -----------------------------------------

  String get upsellSheetLabel => copy.text('Premium offer', 'Oferta Premium');

  String get upsellTitle => copy.text(
    'See who liked — a Premium feature',
    'Zobacz, kto polubił — funkcja Premium',
  );

  String get upsellBody => copy.text(
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.',
    'Z Premium zobaczysz osoby, które polubiły Moment głosowy, Yeel lub komentarz albo zareagowały na wiadomość na serwerze. Liczniki polubień nadal widzi każdy.',
  );

  /// The buy variant's CTA, shown only when checkout can complete.
  String get explorePremium => copy.text('Explore Premium', 'Poznaj Premium');

  String get notNow => copy.text('Not now', 'Nie teraz');

  String get notForSale => copy.text(
    'Premium isn\'t available to buy yet. It\'s coming soon.',
    'Premium nie jest jeszcze dostępne w sprzedaży. Już wkrótce.',
  );

  /// The public count above the upsell ("24 osoby polubiły ten Moment"):
  /// English one/other, Polish one/few/many, and each other locale's CLDR
  /// plural category from `translations_vip_likers.dart`.
  String countLine(LikersTarget target, int count) => switch (target) {
    VoiceMomentLikersTarget() => copy.pluralTemplate(
      count: count,
      stem: '{count} people liked this Moment',
      englishOne: '{count} person liked this Moment',
      englishOther: '{count} people liked this Moment',
      polishOne: '{count} osoba polubiła ten Moment',
      polishFew: '{count} osoby polubiły ten Moment',
      polishMany: '{count} osób polubiło ten Moment',
    ),
    ReelLikersTarget() => copy.pluralTemplate(
      count: count,
      stem: '{count} people liked this Yeel',
      englishOne: '{count} person liked this Yeel',
      englishOther: '{count} people liked this Yeel',
      polishOne: '{count} osoba polubiła ten Yeel',
      polishFew: '{count} osoby polubiły ten Yeel',
      polishMany: '{count} osób polubiło ten Yeel',
    ),
    VoiceMomentCommentLikersTarget() ||
    ReelCommentLikersTarget() => copy.pluralTemplate(
      count: count,
      stem: '{count} people liked this comment',
      englishOne: '{count} person liked this comment',
      englishOther: '{count} people liked this comment',
      polishOne: '{count} osoba polubiła ten komentarz',
      polishFew: '{count} osoby polubiły ten komentarz',
      polishMany: '{count} osób polubiło ten komentarz',
    ),
    PagePostLikersTarget() => copy.pluralTemplate(
      count: count,
      stem: '{count} people liked this post',
      englishOne: '{count} person liked this post',
      englishOther: '{count} people liked this post',
      polishOne: '{count} osoba polubiła ten post',
      polishFew: '{count} osoby polubiły ten post',
      polishMany: '{count} osób polubiło ten post',
    ),
    ServerMessageReactorsTarget() => copy.pluralTemplate(
      count: count,
      stem: '{count} people reacted to this message',
      englishOne: '{count} person reacted to this message',
      englishOther: '{count} people reacted to this message',
      polishOne: '{count} osoba zareagowała na tę wiadomość',
      polishFew: '{count} osoby zareagowały na tę wiadomość',
      polishMany: '{count} osób zareagowało na tę wiadomość',
    ),
  };
}
