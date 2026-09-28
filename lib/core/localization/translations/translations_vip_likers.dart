/// Copy for "See who liked" (ADR-230): the likers list and its reaction tabs,
/// the Premium upsell (owner variant U1), the entry points on Voice Moments,
/// Yeels and Server messages, the comment hearts, the Premium benefit lines
/// and Settings → Privacy → "Hide my likes".
///
/// English and Polish are authored at the call sites (`LikersCopy`,
/// `premium_localized_copy.dart`, `premium_feature_gate.dart`,
/// `settings_screen.dart`); this module gives every other selectable locale
/// an explicit translation, so none of these strings falls back to English.
///
/// Three kinds of key live here:
///
/// * The final English phrase or template (`Likes · {count}`), resolved by
///   `AppLocalizations.text` / `.template`.
/// * `likers.*` context keys for short words whose meaning depends on the
///   sheet ("Likes" the title, "All" the tab, "You" the viewer's own row),
///   resolved by `AppLocalizations.contextualText`.
/// * Count lines above the upsell, keyed by a stable stem plus a CLDR plural
///   category (`{count} people liked this Moment.few`) and resolved by
///   `AppLocalizations.pluralTemplate`. Every locale carries all six
///   entries. `Intl.pluralLogic` returns the `zero` and `two` entries for the
///   exact counts 0 and 2 before it applies the CLDR rule, so in every
///   language those two hold the forms for 0 and 2 (Russian `two` is its
///   `few` form); any other category a language lacks repeats `other`.
///
/// "Premium", "YO Voice", "Voice Moment(s)", "Moment", "Yeel(s)" and emoji
/// stay as written. `Privacy` is included because the list's hint names the
/// Settings section by that label; the word was not catalogued before, so the
/// existing `copy.text('Privacy', …)` labels (the Settings section, the
/// Server privacy field) now resolve the same, deliberately general, word.
///
/// Every value keeps exactly the placeholders of its key
/// (`test/vip_likers_localization_test.dart`).
const vipLikersTranslationKeys = <String>[
  'likers.titleLikes',
  'likers.titleReactions',
  'likers.tabAll',
  '{emoji}: {count}',
  'likers.you',
  '{name}, reacted {emoji}',
  "Some people aren't shown.",
  'No one to show here.',
  'You can hide your own likes in Settings → Privacy.',
  'Likes loaded: {count}',
  'Reactions loaded: {count}',
  'Open profile',
  'See who liked is coming soon.',
  'This content is no longer available.',
  'Too many requests. Try again in a minute.',
  "Couldn't load this list. Try again.",
  'See who liked',
  'See who reacted',
  'Likes · {count}',
  'See who liked. Likes: {count}',
  'See who reacted. Reactions: {count}',
  'Liked by {names} and {count} others. See who liked.',
  'Liked by {names}. See who liked.',
  'Like comment. Likes: {count}',
  'Unlike comment. Likes: {count}',
  'Who liked',
  'Who liked. Likes: {count}',
  "Couldn't update your like. Try again.",
  'Premium offer',
  'See who liked — a Premium feature',
  'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.',
  'Explore Premium',
  "Premium isn't available to buy yet. It's coming soon.",
  'See who liked is included with Premium',
  'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost',
  'See who liked Voice Moments, Yeels, comments and Server messages',
  'Hide my likes',
  "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.",
  "Couldn't update this setting. Try again.",
  'Privacy',
  '{count} people liked this Moment.zero',
  '{count} people liked this Moment.one',
  '{count} people liked this Moment.two',
  '{count} people liked this Moment.few',
  '{count} people liked this Moment.many',
  '{count} people liked this Moment.other',
  '{count} people liked this Yeel.zero',
  '{count} people liked this Yeel.one',
  '{count} people liked this Yeel.two',
  '{count} people liked this Yeel.few',
  '{count} people liked this Yeel.many',
  '{count} people liked this Yeel.other',
  '{count} people liked this comment.zero',
  '{count} people liked this comment.one',
  '{count} people liked this comment.two',
  '{count} people liked this comment.few',
  '{count} people liked this comment.many',
  '{count} people liked this comment.other',
  '{count} people reacted to this message.zero',
  '{count} people reacted to this message.one',
  '{count} people reacted to this message.two',
  '{count} people reacted to this message.few',
  '{count} people reacted to this message.many',
  '{count} people reacted to this message.other',
  // Premium Pages (ADR-233): the likers count line of a Page post.
  '{count} people liked this post.zero',
  '{count} people liked this post.one',
  '{count} people liked this post.two',
  '{count} people liked this post.few',
  '{count} people liked this post.many',
  '{count} people liked this post.other',
];

const vipLikersTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'likers.titleLikes': 'Likes',
    'likers.titleReactions': 'Reaktionen',
    'likers.tabAll': 'Alle',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Du',
    '{name}, reacted {emoji}': '{name}, hat mit {emoji} reagiert',
    "Some people aren't shown.": 'Einige Personen werden nicht angezeigt.',
    'No one to show here.': 'Hier gibt es niemanden anzuzeigen.',
    'You can hide your own likes in Settings → Privacy.':
        'Du kannst deine eigenen Likes unter Einstellungen → Privatsphäre verbergen.',
    'Likes loaded: {count}': 'Geladene Likes: {count}',
    'Reactions loaded: {count}': 'Geladene Reaktionen: {count}',
    'Open profile': 'Profil öffnen',
    'See who liked is coming soon.': '„Likes ansehen“ ist bald verfügbar.',
    'This content is no longer available.':
        'Dieser Inhalt ist nicht mehr verfügbar.',
    'Too many requests. Try again in a minute.':
        'Zu viele Anfragen. Versuche es in einer Minute erneut.',
    "Couldn't load this list. Try again.":
        'Diese Liste konnte nicht geladen werden. Versuche es erneut.',
    'See who liked': 'Likes ansehen',
    'See who reacted': 'Reaktionen ansehen',
    'Likes · {count}': 'Likes · {count}',
    'See who liked. Likes: {count}': 'Likes ansehen. Likes: {count}',
    'See who reacted. Reactions: {count}':
        'Reaktionen ansehen. Reaktionen: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Gefällt {names} und {count} weiteren Personen. Likes ansehen.',
    'Liked by {names}. See who liked.': 'Gefällt {names}. Likes ansehen.',
    'Like comment. Likes: {count}': 'Kommentar liken. Likes: {count}',
    'Unlike comment. Likes: {count}':
        'Like für Kommentar entfernen. Likes: {count}',
    'Who liked': 'Wer hat geliked',
    'Who liked. Likes: {count}': 'Wer hat geliked. Likes: {count}',
    "Couldn't update your like. Try again.":
        'Dein Like konnte nicht aktualisiert werden. Versuche es erneut.',
    'Premium offer': 'Premium-Angebot',
    'See who liked — a Premium feature':
        'Likes ansehen — eine Premium-Funktion',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Mit Premium siehst du, wem ein Voice Moment, ein Yeel oder ein Kommentar gefällt und wer auf eine Servernachricht reagiert hat. Die Anzahl der Likes bleibt für alle sichtbar.',
    'Explore Premium': 'Premium entdecken',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium kann noch nicht gekauft werden. Es kommt bald.',
    'See who liked is included with Premium':
        '„Likes ansehen“ ist in Premium enthalten',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Abzeichen, Schimmer, Datenschutzoptionen, Likes ansehen und ein moderater Yeels-Boost',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Sieh, wem Voice Moments, Yeels, Kommentare und Servernachrichten gefallen',
    'Hide my likes': 'Meine Likes verbergen',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Du erscheinst nicht in den Listen von YO Voice, die zeigen, wer etwas geliked oder darauf reagiert hat. Die Zahlen ändern sich nicht. Servermitglieder erhalten deine Reaktionen in gemeinsamen Kanälen weiterhin.',
    "Couldn't update this setting. Try again.":
        'Diese Einstellung konnte nicht geändert werden. Versuche es erneut.',
    'Privacy': 'Privatsphäre',
    '{count} people liked this Moment.zero':
        'Dieser Moment gefällt {count} Personen',
    '{count} people liked this Moment.one':
        'Dieser Moment gefällt {count} Person',
    '{count} people liked this Moment.two':
        'Dieser Moment gefällt {count} Personen',
    '{count} people liked this Moment.few':
        'Dieser Moment gefällt {count} Personen',
    '{count} people liked this Moment.many':
        'Dieser Moment gefällt {count} Personen',
    '{count} people liked this Moment.other':
        'Dieser Moment gefällt {count} Personen',
    '{count} people liked this Yeel.zero':
        'Dieser Yeel gefällt {count} Personen',
    '{count} people liked this Yeel.one': 'Dieser Yeel gefällt {count} Person',
    '{count} people liked this Yeel.two':
        'Dieser Yeel gefällt {count} Personen',
    '{count} people liked this Yeel.few':
        'Dieser Yeel gefällt {count} Personen',
    '{count} people liked this Yeel.many':
        'Dieser Yeel gefällt {count} Personen',
    '{count} people liked this Yeel.other':
        'Dieser Yeel gefällt {count} Personen',
    '{count} people liked this comment.zero':
        'Dieser Kommentar gefällt {count} Personen',
    '{count} people liked this comment.one':
        'Dieser Kommentar gefällt {count} Person',
    '{count} people liked this comment.two':
        'Dieser Kommentar gefällt {count} Personen',
    '{count} people liked this comment.few':
        'Dieser Kommentar gefällt {count} Personen',
    '{count} people liked this comment.many':
        'Dieser Kommentar gefällt {count} Personen',
    '{count} people liked this comment.other':
        'Dieser Kommentar gefällt {count} Personen',
    '{count} people reacted to this message.zero':
        '{count} Personen haben auf diese Nachricht reagiert',
    '{count} people reacted to this message.one':
        '{count} Person hat auf diese Nachricht reagiert',
    '{count} people reacted to this message.two':
        '{count} Personen haben auf diese Nachricht reagiert',
    '{count} people reacted to this message.few':
        '{count} Personen haben auf diese Nachricht reagiert',
    '{count} people reacted to this message.many':
        '{count} Personen haben auf diese Nachricht reagiert',
    '{count} people reacted to this message.other':
        '{count} Personen haben auf diese Nachricht reagiert',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} Personen gefällt dieser Beitrag',
    '{count} people liked this post.one':
        '{count} Person gefällt dieser Beitrag',
    '{count} people liked this post.two':
        '{count} Personen gefällt dieser Beitrag',
    '{count} people liked this post.few':
        '{count} Personen gefällt dieser Beitrag',
    '{count} people liked this post.many':
        '{count} Personen gefällt dieser Beitrag',
    '{count} people liked this post.other':
        '{count} Personen gefällt dieser Beitrag',
  },
  'es': <String, String>{
    'likers.titleLikes': 'Me gusta',
    'likers.titleReactions': 'Reacciones',
    'likers.tabAll': 'Todas',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tú',
    '{name}, reacted {emoji}': '{name}, reaccionó con {emoji}',
    "Some people aren't shown.": 'Algunas personas no se muestran.',
    'No one to show here.': 'No hay nadie que mostrar aquí.',
    'You can hide your own likes in Settings → Privacy.':
        'Puedes ocultar tus propios me gusta en Ajustes → Privacidad.',
    'Likes loaded: {count}': 'Me gusta cargados: {count}',
    'Reactions loaded: {count}': 'Reacciones cargadas: {count}',
    'Open profile': 'Abrir perfil',
    'See who liked is coming soon.': '«Ver a quién le gustó» llegará pronto.',
    'This content is no longer available.':
        'Este contenido ya no está disponible.',
    'Too many requests. Try again in a minute.':
        'Demasiadas solicitudes. Vuelve a intentarlo en un minuto.',
    "Couldn't load this list. Try again.":
        'No se pudo cargar esta lista. Vuelve a intentarlo.',
    'See who liked': 'Ver a quién le gustó',
    'See who reacted': 'Ver quién reaccionó',
    'Likes · {count}': 'Me gusta · {count}',
    'See who liked. Likes: {count}': 'Ver a quién le gustó. Me gusta: {count}',
    'See who reacted. Reactions: {count}':
        'Ver quién reaccionó. Reacciones: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Me gusta de {names} y {count} personas más. Ver a quién le gustó.',
    'Liked by {names}. See who liked.':
        'Me gusta de {names}. Ver a quién le gustó.',
    'Like comment. Likes: {count}':
        'Dar me gusta al comentario. Me gusta: {count}',
    'Unlike comment. Likes: {count}':
        'Quitar me gusta del comentario. Me gusta: {count}',
    'Who liked': 'A quién le gustó',
    'Who liked. Likes: {count}': 'A quién le gustó. Me gusta: {count}',
    "Couldn't update your like. Try again.":
        'No se pudo actualizar tu me gusta. Vuelve a intentarlo.',
    'Premium offer': 'Oferta Premium',
    'See who liked — a Premium feature':
        'Ver a quién le gustó — una función Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Con Premium puedes ver a las personas a las que les gustó un Voice Moment, un Yeel o un comentario, o que reaccionaron a un mensaje de un servidor. El número de me gusta sigue siendo visible para todos.',
    'Explore Premium': 'Descubrir Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium aún no se puede comprar. Llegará pronto.',
    'See who liked is included with Premium':
        '«Ver a quién le gustó» está incluido en Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Insignia, brillo, controles de privacidad, ver a quién le gustó y un impulso moderado en Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Ver a quién le gustaron Voice Moments, Yeels, comentarios y mensajes de servidores',
    'Hide my likes': 'Ocultar mis me gusta',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'No aparecerás en las listas de YO Voice de quién dio me gusta o reaccionó. Los contadores no cambian. Los miembros del servidor siguen recibiendo tus reacciones en los canales que compartes con ellos.',
    "Couldn't update this setting. Try again.":
        'No se pudo cambiar este ajuste. Vuelve a intentarlo.',
    'Privacy': 'Privacidad',
    '{count} people liked this Moment.zero':
        'A {count} personas les gustó este Moment',
    '{count} people liked this Moment.one':
        'A {count} persona le gustó este Moment',
    '{count} people liked this Moment.two':
        'A {count} personas les gustó este Moment',
    '{count} people liked this Moment.few':
        'A {count} personas les gustó este Moment',
    '{count} people liked this Moment.many':
        'A {count} personas les gustó este Moment',
    '{count} people liked this Moment.other':
        'A {count} personas les gustó este Moment',
    '{count} people liked this Yeel.zero':
        'A {count} personas les gustó este Yeel',
    '{count} people liked this Yeel.one':
        'A {count} persona le gustó este Yeel',
    '{count} people liked this Yeel.two':
        'A {count} personas les gustó este Yeel',
    '{count} people liked this Yeel.few':
        'A {count} personas les gustó este Yeel',
    '{count} people liked this Yeel.many':
        'A {count} personas les gustó este Yeel',
    '{count} people liked this Yeel.other':
        'A {count} personas les gustó este Yeel',
    '{count} people liked this comment.zero':
        'A {count} personas les gustó este comentario',
    '{count} people liked this comment.one':
        'A {count} persona le gustó este comentario',
    '{count} people liked this comment.two':
        'A {count} personas les gustó este comentario',
    '{count} people liked this comment.few':
        'A {count} personas les gustó este comentario',
    '{count} people liked this comment.many':
        'A {count} personas les gustó este comentario',
    '{count} people liked this comment.other':
        'A {count} personas les gustó este comentario',
    '{count} people reacted to this message.zero':
        '{count} personas reaccionaron a este mensaje',
    '{count} people reacted to this message.one':
        '{count} persona reaccionó a este mensaje',
    '{count} people reacted to this message.two':
        '{count} personas reaccionaron a este mensaje',
    '{count} people reacted to this message.few':
        '{count} personas reaccionaron a este mensaje',
    '{count} people reacted to this message.many':
        '{count} personas reaccionaron a este mensaje',
    '{count} people reacted to this message.other':
        '{count} personas reaccionaron a este mensaje',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        'A {count} personas les gustó esta publicación',
    '{count} people liked this post.one':
        'A {count} persona le gustó esta publicación',
    '{count} people liked this post.two':
        'A {count} personas les gustó esta publicación',
    '{count} people liked this post.few':
        'A {count} personas les gustó esta publicación',
    '{count} people liked this post.many':
        'A {count} personas les gustó esta publicación',
    '{count} people liked this post.other':
        'A {count} personas les gustó esta publicación',
  },
  'pt': <String, String>{
    'likers.titleLikes': 'Gostos',
    'likers.titleReactions': 'Reações',
    'likers.tabAll': 'Todas',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tu',
    '{name}, reacted {emoji}': '{name}, reagiu com {emoji}',
    "Some people aren't shown.": 'Algumas pessoas não são mostradas.',
    'No one to show here.': 'Não há ninguém para mostrar aqui.',
    'You can hide your own likes in Settings → Privacy.':
        'Podes ocultar os teus gostos em Definições → Privacidade.',
    'Likes loaded: {count}': 'Gostos carregados: {count}',
    'Reactions loaded: {count}': 'Reações carregadas: {count}',
    'Open profile': 'Abrir perfil',
    'See who liked is coming soon.': '«Ver quem gostou» chega em breve.',
    'This content is no longer available.':
        'Este conteúdo já não está disponível.',
    'Too many requests. Try again in a minute.':
        'Demasiados pedidos. Tenta novamente dentro de um minuto.',
    "Couldn't load this list. Try again.":
        'Não foi possível carregar esta lista. Tenta novamente.',
    'See who liked': 'Ver quem gostou',
    'See who reacted': 'Ver quem reagiu',
    'Likes · {count}': 'Gostos · {count}',
    'See who liked. Likes: {count}': 'Ver quem gostou. Gostos: {count}',
    'See who reacted. Reactions: {count}': 'Ver quem reagiu. Reações: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Gostos de {names} e de mais {count} pessoas. Ver quem gostou.',
    'Liked by {names}. See who liked.': 'Gostos de {names}. Ver quem gostou.',
    'Like comment. Likes: {count}': 'Gostar do comentário. Gostos: {count}',
    'Unlike comment. Likes: {count}':
        'Deixar de gostar do comentário. Gostos: {count}',
    'Who liked': 'Quem gostou',
    'Who liked. Likes: {count}': 'Quem gostou. Gostos: {count}',
    "Couldn't update your like. Try again.":
        'Não foi possível atualizar o teu gosto. Tenta novamente.',
    'Premium offer': 'Oferta Premium',
    'See who liked — a Premium feature':
        'Ver quem gostou — uma funcionalidade Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Com o Premium podes ver as pessoas que gostaram de um Voice Moment, de um Yeel ou de um comentário, ou que reagiram a uma mensagem de um servidor. O número de gostos continua visível para todos.',
    'Explore Premium': 'Explorar o Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'O Premium ainda não está disponível para compra. Chega em breve.',
    'See who liked is included with Premium':
        '«Ver quem gostou» está incluído no Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Emblema, brilho, controlos de privacidade, ver quem gostou e um impulso moderado nos Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Ver quem gostou de Voice Moments, Yeels, comentários e mensagens de servidores',
    'Hide my likes': 'Ocultar os meus gostos',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Não vais aparecer nas listas do YO Voice de quem gostou ou reagiu. Os contadores não mudam. Os membros do servidor continuam a receber as tuas reações nos canais que partilham contigo.',
    "Couldn't update this setting. Try again.":
        'Não foi possível alterar esta definição. Tenta novamente.',
    'Privacy': 'Privacidade',
    '{count} people liked this Moment.zero':
        '{count} pessoas gostaram deste Moment',
    '{count} people liked this Moment.one':
        '{count} pessoa gostou deste Moment',
    '{count} people liked this Moment.two':
        '{count} pessoas gostaram deste Moment',
    '{count} people liked this Moment.few':
        '{count} pessoas gostaram deste Moment',
    '{count} people liked this Moment.many':
        '{count} pessoas gostaram deste Moment',
    '{count} people liked this Moment.other':
        '{count} pessoas gostaram deste Moment',
    '{count} people liked this Yeel.zero':
        '{count} pessoas gostaram deste Yeel',
    '{count} people liked this Yeel.one': '{count} pessoa gostou deste Yeel',
    '{count} people liked this Yeel.two': '{count} pessoas gostaram deste Yeel',
    '{count} people liked this Yeel.few': '{count} pessoas gostaram deste Yeel',
    '{count} people liked this Yeel.many':
        '{count} pessoas gostaram deste Yeel',
    '{count} people liked this Yeel.other':
        '{count} pessoas gostaram deste Yeel',
    '{count} people liked this comment.zero':
        '{count} pessoas gostaram deste comentário',
    '{count} people liked this comment.one':
        '{count} pessoa gostou deste comentário',
    '{count} people liked this comment.two':
        '{count} pessoas gostaram deste comentário',
    '{count} people liked this comment.few':
        '{count} pessoas gostaram deste comentário',
    '{count} people liked this comment.many':
        '{count} pessoas gostaram deste comentário',
    '{count} people liked this comment.other':
        '{count} pessoas gostaram deste comentário',
    '{count} people reacted to this message.zero':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.one':
        '{count} pessoa reagiu a esta mensagem',
    '{count} people reacted to this message.two':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.few':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.many':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.other':
        '{count} pessoas reagiram a esta mensagem',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} pessoas gostaram desta publicação',
    '{count} people liked this post.one':
        '{count} pessoa gostou desta publicação',
    '{count} people liked this post.two':
        '{count} pessoas gostaram desta publicação',
    '{count} people liked this post.few':
        '{count} pessoas gostaram desta publicação',
    '{count} people liked this post.many':
        '{count} pessoas gostaram desta publicação',
    '{count} people liked this post.other':
        '{count} pessoas gostaram desta publicação',
  },
  'pt_BR': <String, String>{
    'likers.titleLikes': 'Curtidas',
    'likers.titleReactions': 'Reações',
    'likers.tabAll': 'Todas',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Você',
    '{name}, reacted {emoji}': '{name}, reagiu com {emoji}',
    "Some people aren't shown.": 'Algumas pessoas não são exibidas.',
    'No one to show here.': 'Não há ninguém para mostrar aqui.',
    'You can hide your own likes in Settings → Privacy.':
        'Você pode ocultar suas curtidas em Configurações → Privacidade.',
    'Likes loaded: {count}': 'Curtidas carregadas: {count}',
    'Reactions loaded: {count}': 'Reações carregadas: {count}',
    'Open profile': 'Abrir perfil',
    'See who liked is coming soon.': '“Ver quem curtiu” chega em breve.',
    'This content is no longer available.':
        'Este conteúdo não está mais disponível.',
    'Too many requests. Try again in a minute.':
        'Muitas solicitações. Tente novamente em um minuto.',
    "Couldn't load this list. Try again.":
        'Não foi possível carregar esta lista. Tente novamente.',
    'See who liked': 'Ver quem curtiu',
    'See who reacted': 'Ver quem reagiu',
    'Likes · {count}': 'Curtidas · {count}',
    'See who liked. Likes: {count}': 'Ver quem curtiu. Curtidas: {count}',
    'See who reacted. Reactions: {count}': 'Ver quem reagiu. Reações: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Curtido por {names} e mais {count} pessoas. Ver quem curtiu.',
    'Liked by {names}. See who liked.': 'Curtido por {names}. Ver quem curtiu.',
    'Like comment. Likes: {count}': 'Curtir comentário. Curtidas: {count}',
    'Unlike comment. Likes: {count}': 'Descurtir comentário. Curtidas: {count}',
    'Who liked': 'Quem curtiu',
    'Who liked. Likes: {count}': 'Quem curtiu. Curtidas: {count}',
    "Couldn't update your like. Try again.":
        'Não foi possível atualizar sua curtida. Tente novamente.',
    'Premium offer': 'Oferta Premium',
    'See who liked — a Premium feature': 'Ver quem curtiu — um recurso Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Com o Premium você vê as pessoas que curtiram um Voice Moment, um Yeel ou um comentário, ou que reagiram a uma mensagem de um servidor. O número de curtidas continua visível para todos.',
    'Explore Premium': 'Conhecer o Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'O Premium ainda não está disponível para compra. Em breve.',
    'See who liked is included with Premium':
        '“Ver quem curtiu” está incluído no Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Selo, brilho, controles de privacidade, ver quem curtiu e um impulso moderado nos Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Ver quem curtiu Voice Moments, Yeels, comentários e mensagens de servidores',
    'Hide my likes': 'Ocultar minhas curtidas',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Você não vai aparecer nas listas do YO Voice de quem curtiu ou reagiu. Os contadores não mudam. Os membros do servidor continuam recebendo suas reações nos canais em comum.',
    "Couldn't update this setting. Try again.":
        'Não foi possível alterar esta configuração. Tente novamente.',
    'Privacy': 'Privacidade',
    '{count} people liked this Moment.zero':
        '{count} pessoas curtiram este Moment',
    '{count} people liked this Moment.one': '{count} pessoa curtiu este Moment',
    '{count} people liked this Moment.two':
        '{count} pessoas curtiram este Moment',
    '{count} people liked this Moment.few':
        '{count} pessoas curtiram este Moment',
    '{count} people liked this Moment.many':
        '{count} pessoas curtiram este Moment',
    '{count} people liked this Moment.other':
        '{count} pessoas curtiram este Moment',
    '{count} people liked this Yeel.zero': '{count} pessoas curtiram este Yeel',
    '{count} people liked this Yeel.one': '{count} pessoa curtiu este Yeel',
    '{count} people liked this Yeel.two': '{count} pessoas curtiram este Yeel',
    '{count} people liked this Yeel.few': '{count} pessoas curtiram este Yeel',
    '{count} people liked this Yeel.many': '{count} pessoas curtiram este Yeel',
    '{count} people liked this Yeel.other':
        '{count} pessoas curtiram este Yeel',
    '{count} people liked this comment.zero':
        '{count} pessoas curtiram este comentário',
    '{count} people liked this comment.one':
        '{count} pessoa curtiu este comentário',
    '{count} people liked this comment.two':
        '{count} pessoas curtiram este comentário',
    '{count} people liked this comment.few':
        '{count} pessoas curtiram este comentário',
    '{count} people liked this comment.many':
        '{count} pessoas curtiram este comentário',
    '{count} people liked this comment.other':
        '{count} pessoas curtiram este comentário',
    '{count} people reacted to this message.zero':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.one':
        '{count} pessoa reagiu a esta mensagem',
    '{count} people reacted to this message.two':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.few':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.many':
        '{count} pessoas reagiram a esta mensagem',
    '{count} people reacted to this message.other':
        '{count} pessoas reagiram a esta mensagem',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} pessoa curtiu esta publicação',
    '{count} people liked this post.one':
        '{count} pessoa curtiu esta publicação',
    '{count} people liked this post.two':
        '{count} pessoas curtiram esta publicação',
    '{count} people liked this post.few':
        '{count} pessoas curtiram esta publicação',
    '{count} people liked this post.many':
        '{count} pessoas curtiram esta publicação',
    '{count} people liked this post.other':
        '{count} pessoas curtiram esta publicação',
  },
  'fr': <String, String>{
    'likers.titleLikes': 'J’aime',
    'likers.titleReactions': 'Réactions',
    'likers.tabAll': 'Toutes',
    '{emoji}: {count}': '{emoji} : {count}',
    'likers.you': 'Vous',
    '{name}, reacted {emoji}': '{name}, a réagi avec {emoji}',
    "Some people aren't shown.": 'Certaines personnes ne sont pas affichées.',
    'No one to show here.': 'Personne à afficher ici.',
    'You can hide your own likes in Settings → Privacy.':
        'Vous pouvez masquer vos propres J’aime dans Paramètres → Confidentialité.',
    'Likes loaded: {count}': 'J’aime chargés : {count}',
    'Reactions loaded: {count}': 'Réactions chargées : {count}',
    'Open profile': 'Ouvrir le profil',
    'See who liked is coming soon.': '« Voir qui a aimé » arrive bientôt.',
    'This content is no longer available.': 'Ce contenu n’est plus disponible.',
    'Too many requests. Try again in a minute.':
        'Trop de demandes. Réessayez dans une minute.',
    "Couldn't load this list. Try again.":
        'Impossible de charger cette liste. Réessayez.',
    'See who liked': 'Voir qui a aimé',
    'See who reacted': 'Voir qui a réagi',
    'Likes · {count}': 'J’aime · {count}',
    'See who liked. Likes: {count}': 'Voir qui a aimé. J’aime : {count}',
    'See who reacted. Reactions: {count}':
        'Voir qui a réagi. Réactions : {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Aimé par {names} et {count} autres personnes. Voir qui a aimé.',
    'Liked by {names}. See who liked.': 'Aimé par {names}. Voir qui a aimé.',
    'Like comment. Likes: {count}': 'Aimer le commentaire. J’aime : {count}',
    'Unlike comment. Likes: {count}':
        'Ne plus aimer le commentaire. J’aime : {count}',
    'Who liked': 'Qui a aimé',
    'Who liked. Likes: {count}': 'Qui a aimé. J’aime : {count}',
    "Couldn't update your like. Try again.":
        'Impossible de mettre à jour votre J’aime. Réessayez.',
    'Premium offer': 'Offre Premium',
    'See who liked — a Premium feature':
        'Voir qui a aimé — une fonctionnalité Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Avec Premium, vous voyez les personnes qui ont aimé un Voice Moment, un Yeel ou un commentaire, ou qui ont réagi à un message de serveur. Le nombre de J’aime reste visible par tous.',
    'Explore Premium': 'Découvrir Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium n’est pas encore disponible à l’achat. Il arrive bientôt.',
    'See who liked is included with Premium':
        '« Voir qui a aimé » est inclus dans Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Badge, scintillement, contrôles de confidentialité, voir qui a aimé et un léger coup de pouce sur Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Voir qui a aimé les Voice Moments, Yeels, commentaires et messages de serveur',
    'Hide my likes': 'Masquer mes J’aime',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Vous n’apparaîtrez pas dans les listes YO Voice des personnes qui ont aimé ou réagi. Les compteurs ne changent pas. Les membres du serveur reçoivent toujours vos réactions dans les salons que vous partagez.',
    "Couldn't update this setting. Try again.":
        'Impossible de modifier ce paramètre. Réessayez.',
    'Privacy': 'Confidentialité',
    '{count} people liked this Moment.zero':
        '{count} personne a aimé ce Moment',
    '{count} people liked this Moment.one': '{count} personne a aimé ce Moment',
    '{count} people liked this Moment.two':
        '{count} personnes ont aimé ce Moment',
    '{count} people liked this Moment.few':
        '{count} personnes ont aimé ce Moment',
    '{count} people liked this Moment.many':
        '{count} personnes ont aimé ce Moment',
    '{count} people liked this Moment.other':
        '{count} personnes ont aimé ce Moment',
    '{count} people liked this Yeel.zero': '{count} personne a aimé ce Yeel',
    '{count} people liked this Yeel.one': '{count} personne a aimé ce Yeel',
    '{count} people liked this Yeel.two': '{count} personnes ont aimé ce Yeel',
    '{count} people liked this Yeel.few': '{count} personnes ont aimé ce Yeel',
    '{count} people liked this Yeel.many': '{count} personnes ont aimé ce Yeel',
    '{count} people liked this Yeel.other':
        '{count} personnes ont aimé ce Yeel',
    '{count} people liked this comment.zero':
        '{count} personne a aimé ce commentaire',
    '{count} people liked this comment.one':
        '{count} personne a aimé ce commentaire',
    '{count} people liked this comment.two':
        '{count} personnes ont aimé ce commentaire',
    '{count} people liked this comment.few':
        '{count} personnes ont aimé ce commentaire',
    '{count} people liked this comment.many':
        '{count} personnes ont aimé ce commentaire',
    '{count} people liked this comment.other':
        '{count} personnes ont aimé ce commentaire',
    '{count} people reacted to this message.zero':
        '{count} personne a réagi à ce message',
    '{count} people reacted to this message.one':
        '{count} personne a réagi à ce message',
    '{count} people reacted to this message.two':
        '{count} personnes ont réagi à ce message',
    '{count} people reacted to this message.few':
        '{count} personnes ont réagi à ce message',
    '{count} people reacted to this message.many':
        '{count} personnes ont réagi à ce message',
    '{count} people reacted to this message.other':
        '{count} personnes ont réagi à ce message',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} personne a aimé cette publication',
    '{count} people liked this post.one':
        '{count} personne a aimé cette publication',
    '{count} people liked this post.two':
        '{count} personnes ont aimé cette publication',
    '{count} people liked this post.few':
        '{count} personnes ont aimé cette publication',
    '{count} people liked this post.many':
        '{count} personnes ont aimé cette publication',
    '{count} people liked this post.other':
        '{count} personnes ont aimé cette publication',
  },
  'it': <String, String>{
    'likers.titleLikes': 'Mi piace',
    'likers.titleReactions': 'Reazioni',
    'likers.tabAll': 'Tutte',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tu',
    '{name}, reacted {emoji}': '{name}, ha reagito con {emoji}',
    "Some people aren't shown.": 'Alcune persone non sono mostrate.',
    'No one to show here.': 'Nessuno da mostrare qui.',
    'You can hide your own likes in Settings → Privacy.':
        'Puoi nascondere i tuoi Mi piace in Impostazioni → Privacy.',
    'Likes loaded: {count}': 'Mi piace caricati: {count}',
    'Reactions loaded: {count}': 'Reazioni caricate: {count}',
    'Open profile': 'Apri profilo',
    'See who liked is coming soon.': '«Vedi a chi piace» arriverà presto.',
    'This content is no longer available.':
        'Questo contenuto non è più disponibile.',
    'Too many requests. Try again in a minute.':
        'Troppe richieste. Riprova tra un minuto.',
    "Couldn't load this list. Try again.":
        'Impossibile caricare questo elenco. Riprova.',
    'See who liked': 'Vedi a chi piace',
    'See who reacted': 'Vedi chi ha reagito',
    'Likes · {count}': 'Mi piace · {count}',
    'See who liked. Likes: {count}': 'Vedi a chi piace. Mi piace: {count}',
    'See who reacted. Reactions: {count}':
        'Vedi chi ha reagito. Reazioni: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Piace a {names} e ad altre {count} persone. Vedi a chi piace.',
    'Liked by {names}. See who liked.': 'Piace a {names}. Vedi a chi piace.',
    'Like comment. Likes: {count}':
        'Metti Mi piace al commento. Mi piace: {count}',
    'Unlike comment. Likes: {count}':
        'Togli Mi piace al commento. Mi piace: {count}',
    'Who liked': 'A chi piace',
    'Who liked. Likes: {count}': 'A chi piace. Mi piace: {count}',
    "Couldn't update your like. Try again.":
        'Impossibile aggiornare il tuo Mi piace. Riprova.',
    'Premium offer': 'Offerta Premium',
    'See who liked — a Premium feature':
        'Vedi a chi piace — una funzione Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Con Premium puoi vedere le persone a cui è piaciuto un Voice Moment, uno Yeel o un commento, o che hanno reagito a un messaggio di un server. Il numero di Mi piace resta visibile a tutti.',
    'Explore Premium': 'Scopri Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium non è ancora disponibile per l’acquisto. Arriverà presto.',
    'See who liked is included with Premium':
        '«Vedi a chi piace» è incluso in Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Badge, bagliore, controlli della privacy, vedi a chi piace e una spinta moderata su Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Vedi a chi piacciono Voice Moments, Yeels, commenti e messaggi dei server',
    'Hide my likes': 'Nascondi i miei Mi piace',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Non comparirai negli elenchi di YO Voice di chi ha messo Mi piace o ha reagito. I conteggi non cambiano. I membri del server continuano a ricevere le tue reazioni nei canali che condividete.',
    "Couldn't update this setting. Try again.":
        'Impossibile modificare questa impostazione. Riprova.',
    'Privacy': 'Privacy',
    '{count} people liked this Moment.zero':
        '{count} persone hanno messo Mi piace a questo Moment',
    '{count} people liked this Moment.one':
        '{count} persona ha messo Mi piace a questo Moment',
    '{count} people liked this Moment.two':
        '{count} persone hanno messo Mi piace a questo Moment',
    '{count} people liked this Moment.few':
        '{count} persone hanno messo Mi piace a questo Moment',
    '{count} people liked this Moment.many':
        '{count} persone hanno messo Mi piace a questo Moment',
    '{count} people liked this Moment.other':
        '{count} persone hanno messo Mi piace a questo Moment',
    '{count} people liked this Yeel.zero':
        '{count} persone hanno messo Mi piace a questo Yeel',
    '{count} people liked this Yeel.one':
        '{count} persona ha messo Mi piace a questo Yeel',
    '{count} people liked this Yeel.two':
        '{count} persone hanno messo Mi piace a questo Yeel',
    '{count} people liked this Yeel.few':
        '{count} persone hanno messo Mi piace a questo Yeel',
    '{count} people liked this Yeel.many':
        '{count} persone hanno messo Mi piace a questo Yeel',
    '{count} people liked this Yeel.other':
        '{count} persone hanno messo Mi piace a questo Yeel',
    '{count} people liked this comment.zero':
        '{count} persone hanno messo Mi piace a questo commento',
    '{count} people liked this comment.one':
        '{count} persona ha messo Mi piace a questo commento',
    '{count} people liked this comment.two':
        '{count} persone hanno messo Mi piace a questo commento',
    '{count} people liked this comment.few':
        '{count} persone hanno messo Mi piace a questo commento',
    '{count} people liked this comment.many':
        '{count} persone hanno messo Mi piace a questo commento',
    '{count} people liked this comment.other':
        '{count} persone hanno messo Mi piace a questo commento',
    '{count} people reacted to this message.zero':
        '{count} persone hanno reagito a questo messaggio',
    '{count} people reacted to this message.one':
        '{count} persona ha reagito a questo messaggio',
    '{count} people reacted to this message.two':
        '{count} persone hanno reagito a questo messaggio',
    '{count} people reacted to this message.few':
        '{count} persone hanno reagito a questo messaggio',
    '{count} people reacted to this message.many':
        '{count} persone hanno reagito a questo messaggio',
    '{count} people reacted to this message.other':
        '{count} persone hanno reagito a questo messaggio',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        'A {count} persone è piaciuto questo post',
    '{count} people liked this post.one':
        'A {count} persona è piaciuto questo post',
    '{count} people liked this post.two':
        'A {count} persone è piaciuto questo post',
    '{count} people liked this post.few':
        'A {count} persone è piaciuto questo post',
    '{count} people liked this post.many':
        'A {count} persone è piaciuto questo post',
    '{count} people liked this post.other':
        'A {count} persone è piaciuto questo post',
  },
  'nl': <String, String>{
    'likers.titleLikes': 'Vind-ik-leuks',
    'likers.titleReactions': 'Reacties',
    'likers.tabAll': 'Alle',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Jij',
    '{name}, reacted {emoji}': '{name}, reageerde met {emoji}',
    "Some people aren't shown.": 'Sommige mensen worden niet getoond.',
    'No one to show here.': 'Er is hier niemand om te tonen.',
    'You can hide your own likes in Settings → Privacy.':
        'Je kunt je eigen vind-ik-leuks verbergen via Instellingen → Privacy.',
    'Likes loaded: {count}': 'Vind-ik-leuks geladen: {count}',
    'Reactions loaded: {count}': 'Reacties geladen: {count}',
    'Open profile': 'Profiel openen',
    'See who liked is coming soon.':
        '‘Bekijk wie het leuk vond’ komt binnenkort.',
    'This content is no longer available.':
        'Deze content is niet meer beschikbaar.',
    'Too many requests. Try again in a minute.':
        'Te veel verzoeken. Probeer het over een minuut opnieuw.',
    "Couldn't load this list. Try again.":
        'Kan deze lijst niet laden. Probeer het opnieuw.',
    'See who liked': 'Bekijk wie het leuk vond',
    'See who reacted': 'Bekijk wie reageerde',
    'Likes · {count}': 'Vind-ik-leuks · {count}',
    'See who liked. Likes: {count}':
        'Bekijk wie het leuk vond. Vind-ik-leuks: {count}',
    'See who reacted. Reactions: {count}':
        'Bekijk wie reageerde. Reacties: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Leuk gevonden door {names} en {count} anderen. Bekijk wie het leuk vond.',
    'Liked by {names}. See who liked.':
        'Leuk gevonden door {names}. Bekijk wie het leuk vond.',
    'Like comment. Likes: {count}':
        'Reactie leuk vinden. Vind-ik-leuks: {count}',
    'Unlike comment. Likes: {count}':
        'Reactie niet meer leuk vinden. Vind-ik-leuks: {count}',
    'Who liked': 'Wie vond het leuk',
    'Who liked. Likes: {count}': 'Wie vond het leuk. Vind-ik-leuks: {count}',
    "Couldn't update your like. Try again.":
        'Kan je vind-ik-leuk niet bijwerken. Probeer het opnieuw.',
    'Premium offer': 'Premium-aanbod',
    'See who liked — a Premium feature':
        'Bekijk wie het leuk vond — een Premium-functie',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Met Premium zie je wie een Voice Moment, een Yeel of een reactie leuk vond, of op een serverbericht reageerde. Het aantal vind-ik-leuks blijft voor iedereen zichtbaar.',
    'Explore Premium': 'Ontdek Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium is nog niet te koop. Het komt binnenkort.',
    'See who liked is included with Premium':
        '‘Bekijk wie het leuk vond’ zit in Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Badge, glans, privacyinstellingen, zien wie het leuk vond en een bescheiden boost in Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Zie wie Voice Moments, Yeels, reacties en serverberichten leuk vond',
    'Hide my likes': 'Mijn vind-ik-leuks verbergen',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Je verschijnt niet in de lijsten van YO Voice van wie iets leuk vond of reageerde. Aantallen veranderen niet. Serverleden ontvangen je reacties nog steeds in kanalen die jullie delen.',
    "Couldn't update this setting. Try again.":
        'Kan deze instelling niet wijzigen. Probeer het opnieuw.',
    'Privacy': 'Privacy',
    '{count} people liked this Moment.zero':
        '{count} mensen vonden dit Moment leuk',
    '{count} people liked this Moment.one':
        '{count} persoon vond dit Moment leuk',
    '{count} people liked this Moment.two':
        '{count} mensen vonden dit Moment leuk',
    '{count} people liked this Moment.few':
        '{count} mensen vonden dit Moment leuk',
    '{count} people liked this Moment.many':
        '{count} mensen vonden dit Moment leuk',
    '{count} people liked this Moment.other':
        '{count} mensen vonden dit Moment leuk',
    '{count} people liked this Yeel.zero':
        '{count} mensen vonden deze Yeel leuk',
    '{count} people liked this Yeel.one': '{count} persoon vond deze Yeel leuk',
    '{count} people liked this Yeel.two':
        '{count} mensen vonden deze Yeel leuk',
    '{count} people liked this Yeel.few':
        '{count} mensen vonden deze Yeel leuk',
    '{count} people liked this Yeel.many':
        '{count} mensen vonden deze Yeel leuk',
    '{count} people liked this Yeel.other':
        '{count} mensen vonden deze Yeel leuk',
    '{count} people liked this comment.zero':
        '{count} mensen vonden deze reactie leuk',
    '{count} people liked this comment.one':
        '{count} persoon vond deze reactie leuk',
    '{count} people liked this comment.two':
        '{count} mensen vonden deze reactie leuk',
    '{count} people liked this comment.few':
        '{count} mensen vonden deze reactie leuk',
    '{count} people liked this comment.many':
        '{count} mensen vonden deze reactie leuk',
    '{count} people liked this comment.other':
        '{count} mensen vonden deze reactie leuk',
    '{count} people reacted to this message.zero':
        '{count} mensen reageerden op dit bericht',
    '{count} people reacted to this message.one':
        '{count} persoon reageerde op dit bericht',
    '{count} people reacted to this message.two':
        '{count} mensen reageerden op dit bericht',
    '{count} people reacted to this message.few':
        '{count} mensen reageerden op dit bericht',
    '{count} people reacted to this message.many':
        '{count} mensen reageerden op dit bericht',
    '{count} people reacted to this message.other':
        '{count} mensen reageerden op dit bericht',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} mensen vinden dit bericht leuk',
    '{count} people liked this post.one':
        '{count} persoon vindt dit bericht leuk',
    '{count} people liked this post.two':
        '{count} mensen vinden dit bericht leuk',
    '{count} people liked this post.few':
        '{count} mensen vinden dit bericht leuk',
    '{count} people liked this post.many':
        '{count} mensen vinden dit bericht leuk',
    '{count} people liked this post.other':
        '{count} mensen vinden dit bericht leuk',
  },
  'ro': <String, String>{
    'likers.titleLikes': 'Aprecieri',
    'likers.titleReactions': 'Reacții',
    'likers.tabAll': 'Toate',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tu',
    '{name}, reacted {emoji}': '{name}, a reacționat cu {emoji}',
    "Some people aren't shown.": 'Unele persoane nu sunt afișate.',
    'No one to show here.': 'Nu este nimeni de afișat aici.',
    'You can hide your own likes in Settings → Privacy.':
        'Îți poți ascunde propriile aprecieri din Setări → Confidențialitate.',
    'Likes loaded: {count}': 'Aprecieri încărcate: {count}',
    'Reactions loaded: {count}': 'Reacții încărcate: {count}',
    'Open profile': 'Deschide profilul',
    'See who liked is coming soon.':
        '„Vezi cine a apreciat” va fi disponibil în curând.',
    'This content is no longer available.':
        'Acest conținut nu mai este disponibil.',
    'Too many requests. Try again in a minute.':
        'Prea multe solicitări. Încearcă din nou peste un minut.',
    "Couldn't load this list. Try again.":
        'Lista nu a putut fi încărcată. Încearcă din nou.',
    'See who liked': 'Vezi cine a apreciat',
    'See who reacted': 'Vezi cine a reacționat',
    'Likes · {count}': 'Aprecieri · {count}',
    'See who liked. Likes: {count}': 'Vezi cine a apreciat. Aprecieri: {count}',
    'See who reacted. Reactions: {count}':
        'Vezi cine a reacționat. Reacții: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Apreciat de {names} și încă {count}. Vezi cine a apreciat.',
    'Liked by {names}. See who liked.':
        'Apreciat de {names}. Vezi cine a apreciat.',
    'Like comment. Likes: {count}': 'Apreciază comentariul. Aprecieri: {count}',
    'Unlike comment. Likes: {count}':
        'Retrage aprecierea comentariului. Aprecieri: {count}',
    'Who liked': 'Cine a apreciat',
    'Who liked. Likes: {count}': 'Cine a apreciat. Aprecieri: {count}',
    "Couldn't update your like. Try again.":
        'Aprecierea nu a putut fi actualizată. Încearcă din nou.',
    'Premium offer': 'Ofertă Premium',
    'See who liked — a Premium feature':
        'Vezi cine a apreciat — o funcție Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Cu Premium poți vedea persoanele care au apreciat un Voice Moment, un Yeel sau un comentariu ori au reacționat la un mesaj de pe un server. Numărul de aprecieri rămâne vizibil pentru toată lumea.',
    'Explore Premium': 'Descoperă Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium nu poate fi cumpărat încă. Va fi disponibil în curând.',
    'See who liked is included with Premium':
        '„Vezi cine a apreciat” este inclus în Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Insignă, strălucire, controale de confidențialitate, vezi cine a apreciat și un impuls moderat în Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Vezi cine a apreciat Voice Moments, Yeels, comentarii și mesaje de pe servere',
    'Hide my likes': 'Ascunde aprecierile mele',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Nu vei apărea în listele YO Voice cu cei care au apreciat sau au reacționat. Numerele nu se schimbă. Membrii serverului primesc în continuare reacțiile tale în canalele comune.',
    "Couldn't update this setting. Try again.":
        'Setarea nu a putut fi modificată. Încearcă din nou.',
    'Privacy': 'Confidențialitate',
    '{count} people liked this Moment.zero':
        '{count} persoane au apreciat acest Moment',
    '{count} people liked this Moment.one':
        '{count} persoană a apreciat acest Moment',
    '{count} people liked this Moment.two':
        '{count} persoane au apreciat acest Moment',
    '{count} people liked this Moment.few':
        '{count} persoane au apreciat acest Moment',
    '{count} people liked this Moment.many':
        '{count} de persoane au apreciat acest Moment',
    '{count} people liked this Moment.other':
        '{count} de persoane au apreciat acest Moment',
    '{count} people liked this Yeel.zero':
        '{count} persoane au apreciat acest Yeel',
    '{count} people liked this Yeel.one':
        '{count} persoană a apreciat acest Yeel',
    '{count} people liked this Yeel.two':
        '{count} persoane au apreciat acest Yeel',
    '{count} people liked this Yeel.few':
        '{count} persoane au apreciat acest Yeel',
    '{count} people liked this Yeel.many':
        '{count} de persoane au apreciat acest Yeel',
    '{count} people liked this Yeel.other':
        '{count} de persoane au apreciat acest Yeel',
    '{count} people liked this comment.zero':
        '{count} persoane au apreciat acest comentariu',
    '{count} people liked this comment.one':
        '{count} persoană a apreciat acest comentariu',
    '{count} people liked this comment.two':
        '{count} persoane au apreciat acest comentariu',
    '{count} people liked this comment.few':
        '{count} persoane au apreciat acest comentariu',
    '{count} people liked this comment.many':
        '{count} de persoane au apreciat acest comentariu',
    '{count} people liked this comment.other':
        '{count} de persoane au apreciat acest comentariu',
    '{count} people reacted to this message.zero':
        '{count} persoane au reacționat la acest mesaj',
    '{count} people reacted to this message.one':
        '{count} persoană a reacționat la acest mesaj',
    '{count} people reacted to this message.two':
        '{count} persoane au reacționat la acest mesaj',
    '{count} people reacted to this message.few':
        '{count} persoane au reacționat la acest mesaj',
    '{count} people reacted to this message.many':
        '{count} de persoane au reacționat la acest mesaj',
    '{count} people reacted to this message.other':
        '{count} de persoane au reacționat la acest mesaj',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} persoane au apreciat această postare',
    '{count} people liked this post.one':
        '{count} persoană a apreciat această postare',
    '{count} people liked this post.two':
        '{count} persoane au apreciat această postare',
    '{count} people liked this post.few':
        '{count} persoane au apreciat această postare',
    '{count} people liked this post.many':
        '{count} persoane au apreciat această postare',
    '{count} people liked this post.other':
        '{count} de persoane au apreciat această postare',
  },
  'tr': <String, String>{
    'likers.titleLikes': 'Beğeniler',
    'likers.titleReactions': 'Tepkiler',
    'likers.tabAll': 'Tümü',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Sen',
    '{name}, reacted {emoji}': '{name}, {emoji} ile tepki verdi',
    "Some people aren't shown.": 'Bazı kişiler gösterilmiyor.',
    'No one to show here.': 'Burada gösterilecek kimse yok.',
    'You can hide your own likes in Settings → Privacy.':
        'Kendi beğenilerini Ayarlar → Gizlilik bölümünden gizleyebilirsin.',
    'Likes loaded: {count}': 'Yüklenen beğeniler: {count}',
    'Reactions loaded: {count}': 'Yüklenen tepkiler: {count}',
    'Open profile': 'Profili aç',
    'See who liked is coming soon.':
        '“Kimlerin beğendiğini gör” yakında geliyor.',
    'This content is no longer available.': 'Bu içerik artık kullanılamıyor.',
    'Too many requests. Try again in a minute.':
        'Çok fazla istek. Bir dakika sonra tekrar dene.',
    "Couldn't load this list. Try again.": 'Bu liste yüklenemedi. Tekrar dene.',
    'See who liked': 'Kimlerin beğendiğini gör',
    'See who reacted': 'Kimlerin tepki verdiğini gör',
    'Likes · {count}': 'Beğeniler · {count}',
    'See who liked. Likes: {count}':
        'Kimlerin beğendiğini gör. Beğeniler: {count}',
    'See who reacted. Reactions: {count}':
        'Kimlerin tepki verdiğini gör. Tepkiler: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} ve {count} kişi daha beğendi. Kimlerin beğendiğini gör.',
    'Liked by {names}. See who liked.':
        '{names} beğendi. Kimlerin beğendiğini gör.',
    'Like comment. Likes: {count}': 'Yorumu beğen. Beğeniler: {count}',
    'Unlike comment. Likes: {count}':
        'Yorumun beğenisini kaldır. Beğeniler: {count}',
    'Who liked': 'Kimler beğendi',
    'Who liked. Likes: {count}': 'Kimler beğendi. Beğeniler: {count}',
    "Couldn't update your like. Try again.":
        'Beğenin güncellenemedi. Tekrar dene.',
    'Premium offer': 'Premium teklifi',
    'See who liked — a Premium feature':
        'Kimlerin beğendiğini gör — bir Premium özelliği',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium ile bir Voice Moment’ı, Yeel’i ya da yorumu beğenen veya bir sunucu mesajına tepki veren kişileri görebilirsin. Beğeni sayıları herkese görünür kalır.',
    'Explore Premium': 'Premium’u keşfet',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium henüz satın alınamıyor. Yakında geliyor.',
    'See who liked is included with Premium':
        '“Kimlerin beğendiğini gör” Premium’a dahildir',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Rozet, parıltı, gizlilik kontrolleri, kimlerin beğendiğini görme ve Yeels’te ölçülü bir öne çıkarma',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Voice Moments, Yeels, yorumlar ve sunucu mesajlarını kimlerin beğendiğini gör',
    'Hide my likes': 'Beğenilerimi gizle',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'YO Voice’ta kimlerin beğendiğini veya tepki verdiğini gösteren listelerde görünmezsin. Sayılar değişmez. Sunucu üyeleri, paylaştığınız kanallarda tepkilerini almaya devam eder.',
    "Couldn't update this setting. Try again.":
        'Bu ayar güncellenemedi. Tekrar dene.',
    'Privacy': 'Gizlilik',
    '{count} people liked this Moment.zero': '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Moment.one': '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Moment.two': '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Moment.few': '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Moment.many': '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Moment.other':
        '{count} kişi bu Moment’ı beğendi',
    '{count} people liked this Yeel.zero': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this Yeel.one': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this Yeel.two': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this Yeel.few': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this Yeel.many': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this Yeel.other': '{count} kişi bu Yeel’i beğendi',
    '{count} people liked this comment.zero': '{count} kişi bu yorumu beğendi',
    '{count} people liked this comment.one': '{count} kişi bu yorumu beğendi',
    '{count} people liked this comment.two': '{count} kişi bu yorumu beğendi',
    '{count} people liked this comment.few': '{count} kişi bu yorumu beğendi',
    '{count} people liked this comment.many': '{count} kişi bu yorumu beğendi',
    '{count} people liked this comment.other': '{count} kişi bu yorumu beğendi',
    '{count} people reacted to this message.zero':
        '{count} kişi bu mesaja tepki verdi',
    '{count} people reacted to this message.one':
        '{count} kişi bu mesaja tepki verdi',
    '{count} people reacted to this message.two':
        '{count} kişi bu mesaja tepki verdi',
    '{count} people reacted to this message.few':
        '{count} kişi bu mesaja tepki verdi',
    '{count} people reacted to this message.many':
        '{count} kişi bu mesaja tepki verdi',
    '{count} people reacted to this message.other':
        '{count} kişi bu mesaja tepki verdi',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': 'Bu gönderiyi {count} kişi beğendi',
    '{count} people liked this post.one': 'Bu gönderiyi {count} kişi beğendi',
    '{count} people liked this post.two': 'Bu gönderiyi {count} kişi beğendi',
    '{count} people liked this post.few': 'Bu gönderiyi {count} kişi beğendi',
    '{count} people liked this post.many': 'Bu gönderiyi {count} kişi beğendi',
    '{count} people liked this post.other': 'Bu gönderiyi {count} kişi beğendi',
  },
  'el': <String, String>{
    'likers.titleLikes': 'Μου αρέσει',
    'likers.titleReactions': 'Αντιδράσεις',
    'likers.tabAll': 'Όλες',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Εσύ',
    '{name}, reacted {emoji}': '{name}, αντέδρασε με {emoji}',
    "Some people aren't shown.": 'Ορισμένα άτομα δεν εμφανίζονται.',
    'No one to show here.': 'Δεν υπάρχει κανείς για εμφάνιση εδώ.',
    'You can hide your own likes in Settings → Privacy.':
        'Μπορείς να κρύψεις τα δικά σου «Μου αρέσει» από Ρυθμίσεις → Απόρρητο.',
    'Likes loaded: {count}': '«Μου αρέσει» που φορτώθηκαν: {count}',
    'Reactions loaded: {count}': 'Αντιδράσεις που φορτώθηκαν: {count}',
    'Open profile': 'Άνοιγμα προφίλ',
    'See who liked is coming soon.':
        'Το «Δες σε ποιους αρέσει» έρχεται σύντομα.',
    'This content is no longer available.':
        'Αυτό το περιεχόμενο δεν είναι πλέον διαθέσιμο.',
    'Too many requests. Try again in a minute.':
        'Πάρα πολλά αιτήματα. Δοκίμασε ξανά σε ένα λεπτό.',
    "Couldn't load this list. Try again.":
        'Δεν ήταν δυνατή η φόρτωση της λίστας. Δοκίμασε ξανά.',
    'See who liked': 'Δες σε ποιους αρέσει',
    'See who reacted': 'Δες ποιοι αντέδρασαν',
    'Likes · {count}': 'Μου αρέσει · {count}',
    'See who liked. Likes: {count}':
        'Δες σε ποιους αρέσει. «Μου αρέσει»: {count}',
    'See who reacted. Reactions: {count}':
        'Δες ποιοι αντέδρασαν. Αντιδράσεις: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Αρέσει σε {names} και σε άλλα {count} άτομα. Δες σε ποιους αρέσει.',
    'Liked by {names}. See who liked.':
        'Αρέσει σε {names}. Δες σε ποιους αρέσει.',
    'Like comment. Likes: {count}':
        '«Μου αρέσει» στο σχόλιο. «Μου αρέσει»: {count}',
    'Unlike comment. Likes: {count}':
        'Αναίρεση «Μου αρέσει» στο σχόλιο. «Μου αρέσει»: {count}',
    'Who liked': 'Σε ποιους αρέσει',
    'Who liked. Likes: {count}': 'Σε ποιους αρέσει. «Μου αρέσει»: {count}',
    "Couldn't update your like. Try again.":
        'Δεν ήταν δυνατή η ενημέρωση του «Μου αρέσει». Δοκίμασε ξανά.',
    'Premium offer': 'Προσφορά Premium',
    'See who liked — a Premium feature':
        'Δες σε ποιους αρέσει — λειτουργία Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Με το Premium βλέπεις τα άτομα στα οποία άρεσε ένα Voice Moment, ένα Yeel ή ένα σχόλιο ή που αντέδρασαν σε ένα μήνυμα διακομιστή. Ο αριθμός των «Μου αρέσει» παραμένει ορατός σε όλους.',
    'Explore Premium': 'Εξερεύνησε το Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Το Premium δεν διατίθεται ακόμη για αγορά. Έρχεται σύντομα.',
    'See who liked is included with Premium':
        'Το «Δες σε ποιους αρέσει» περιλαμβάνεται στο Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Σήμα, λάμψη, ρυθμίσεις απορρήτου, προβολή του σε ποιους αρέσει και μια μέτρια ώθηση στα Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Δες σε ποιους αρέσουν Voice Moments, Yeels, σχόλια και μηνύματα διακομιστών',
    'Hide my likes': 'Απόκρυψη των «Μου αρέσει» μου',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Δεν θα εμφανίζεσαι στις λίστες του YO Voice με όσους πάτησαν «Μου αρέσει» ή αντέδρασαν. Οι αριθμοί δεν αλλάζουν. Τα μέλη του διακομιστή εξακολουθούν να λαμβάνουν τις αντιδράσεις σου στα κανάλια που μοιράζεστε.',
    "Couldn't update this setting. Try again.":
        'Δεν ήταν δυνατή η αλλαγή αυτής της ρύθμισης. Δοκίμασε ξανά.',
    'Privacy': 'Απόρρητο',
    '{count} people liked this Moment.zero':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Moment.one':
        '{count} άτομο πάτησε «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Moment.two':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Moment.few':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Moment.many':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Moment.other':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Moment',
    '{count} people liked this Yeel.zero':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this Yeel.one':
        '{count} άτομο πάτησε «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this Yeel.two':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this Yeel.few':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this Yeel.many':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this Yeel.other':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το Yeel',
    '{count} people liked this comment.zero':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people liked this comment.one':
        '{count} άτομο πάτησε «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people liked this comment.two':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people liked this comment.few':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people liked this comment.many':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people liked this comment.other':
        '{count} άτομα πάτησαν «Μου αρέσει» σε αυτό το σχόλιο',
    '{count} people reacted to this message.zero':
        '{count} άτομα αντέδρασαν σε αυτό το μήνυμα',
    '{count} people reacted to this message.one':
        '{count} άτομο αντέδρασε σε αυτό το μήνυμα',
    '{count} people reacted to this message.two':
        '{count} άτομα αντέδρασαν σε αυτό το μήνυμα',
    '{count} people reacted to this message.few':
        '{count} άτομα αντέδρασαν σε αυτό το μήνυμα',
    '{count} people reacted to this message.many':
        '{count} άτομα αντέδρασαν σε αυτό το μήνυμα',
    '{count} people reacted to this message.other':
        '{count} άτομα αντέδρασαν σε αυτό το μήνυμα',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        'Σε {count} άτομα άρεσε αυτή η ανάρτηση',
    '{count} people liked this post.one':
        'Σε {count} άτομο άρεσε αυτή η ανάρτηση',
    '{count} people liked this post.two':
        'Σε {count} άτομα άρεσε αυτή η ανάρτηση',
    '{count} people liked this post.few':
        'Σε {count} άτομα άρεσε αυτή η ανάρτηση',
    '{count} people liked this post.many':
        'Σε {count} άτομα άρεσε αυτή η ανάρτηση',
    '{count} people liked this post.other':
        'Σε {count} άτομα άρεσε αυτή η ανάρτηση',
  },
  'hu': <String, String>{
    'likers.titleLikes': 'Kedvelések',
    'likers.titleReactions': 'Reakciók',
    'likers.tabAll': 'Összes',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Te',
    '{name}, reacted {emoji}': '{name}, reakció: {emoji}',
    "Some people aren't shown.": 'Néhány személy nem látható.',
    'No one to show here.': 'Itt nincs kit megjeleníteni.',
    'You can hide your own likes in Settings → Privacy.':
        'A saját kedveléseidet a Beállítások → Adatvédelem menüben rejtheted el.',
    'Likes loaded: {count}': 'Betöltött kedvelések: {count}',
    'Reactions loaded: {count}': 'Betöltött reakciók: {count}',
    'Open profile': 'Profil megnyitása',
    'See who liked is coming soon.':
        'A „Nézd meg, kik kedvelték” funkció hamarosan érkezik.',
    'This content is no longer available.': 'Ez a tartalom már nem érhető el.',
    'Too many requests. Try again in a minute.':
        'Túl sok kérés. Próbáld újra egy perc múlva.',
    "Couldn't load this list. Try again.":
        'Nem sikerült betölteni a listát. Próbáld újra.',
    'See who liked': 'Nézd meg, kik kedvelték',
    'See who reacted': 'Nézd meg, kik reagáltak',
    'Likes · {count}': 'Kedvelések · {count}',
    'See who liked. Likes: {count}':
        'Nézd meg, kik kedvelték. Kedvelések: {count}',
    'See who reacted. Reactions: {count}':
        'Nézd meg, kik reagáltak. Reakciók: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} és további {count} személy kedvelte. Nézd meg, kik kedvelték.',
    'Liked by {names}. See who liked.':
        '{names} kedvelte. Nézd meg, kik kedvelték.',
    'Like comment. Likes: {count}':
        'Hozzászólás kedvelése. Kedvelések: {count}',
    'Unlike comment. Likes: {count}':
        'Hozzászólás kedvelésének visszavonása. Kedvelések: {count}',
    'Who liked': 'Kik kedvelték',
    'Who liked. Likes: {count}': 'Kik kedvelték. Kedvelések: {count}',
    "Couldn't update your like. Try again.":
        'Nem sikerült frissíteni a kedvelésedet. Próbáld újra.',
    'Premium offer': 'Premium-ajánlat',
    'See who liked — a Premium feature':
        'Nézd meg, kik kedvelték — Premium-funkció',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'A Premiummal láthatod, kik kedveltek egy Voice Momentet, egy Yeelt vagy egy hozzászólást, illetve kik reagáltak egy szerverüzenetre. A kedvelések száma továbbra is mindenki számára látható.',
    'Explore Premium': 'Fedezd fel a Premiumot',
    "Premium isn't available to buy yet. It's coming soon.":
        'A Premium még nem vásárolható meg. Hamarosan érkezik.',
    'See who liked is included with Premium':
        'A „Nézd meg, kik kedvelték” funkció a Premium része',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Jelvény, csillogás, adatvédelmi beállítások, a kedvelők megtekintése és mérsékelt kiemelés a Yeelsben',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Kedvelők megtekintése: Voice Moments, Yeels, hozzászólások és szerverüzenetek',
    'Hide my likes': 'Kedveléseim elrejtése',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Nem jelensz meg a YO Voice azon listáin, amelyek megmutatják, ki kedvelt vagy reagált. A számok nem változnak. A szerver tagjai továbbra is megkapják a reakcióidat a közös csatornákon.',
    "Couldn't update this setting. Try again.":
        'Nem sikerült módosítani ezt a beállítást. Próbáld újra.',
    'Privacy': 'Adatvédelem',
    '{count} people liked this Moment.zero':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Moment.one':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Moment.two':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Moment.few':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Moment.many':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Moment.other':
        '{count} személy kedvelte ezt a Momentet',
    '{count} people liked this Yeel.zero':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this Yeel.one':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this Yeel.two':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this Yeel.few':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this Yeel.many':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this Yeel.other':
        '{count} személy kedvelte ezt a Yeelt',
    '{count} people liked this comment.zero':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people liked this comment.one':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people liked this comment.two':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people liked this comment.few':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people liked this comment.many':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people liked this comment.other':
        '{count} személy kedvelte ezt a hozzászólást',
    '{count} people reacted to this message.zero':
        '{count} személy reagált erre az üzenetre',
    '{count} people reacted to this message.one':
        '{count} személy reagált erre az üzenetre',
    '{count} people reacted to this message.two':
        '{count} személy reagált erre az üzenetre',
    '{count} people reacted to this message.few':
        '{count} személy reagált erre az üzenetre',
    '{count} people reacted to this message.many':
        '{count} személy reagált erre az üzenetre',
    '{count} people reacted to this message.other':
        '{count} személy reagált erre az üzenetre',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} embernek tetszik ez a bejegyzés',
    '{count} people liked this post.one':
        '{count} embernek tetszik ez a bejegyzés',
    '{count} people liked this post.two':
        '{count} embernek tetszik ez a bejegyzés',
    '{count} people liked this post.few':
        '{count} embernek tetszik ez a bejegyzés',
    '{count} people liked this post.many':
        '{count} embernek tetszik ez a bejegyzés',
    '{count} people liked this post.other':
        '{count} embernek tetszik ez a bejegyzés',
  },
  'uk': <String, String>{
    'likers.titleLikes': 'Вподобання',
    'likers.titleReactions': 'Реакції',
    'likers.tabAll': 'Усі',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Ти',
    '{name}, reacted {emoji}': '{name}, реакція {emoji}',
    "Some people aren't shown.": 'Деяких людей не показано.',
    'No one to show here.': 'Тут немає кого показати.',
    'You can hide your own likes in Settings → Privacy.':
        'Свої вподобання можна приховати в Налаштуваннях → Конфіденційність.',
    'Likes loaded: {count}': 'Завантажено вподобань: {count}',
    'Reactions loaded: {count}': 'Завантажено реакцій: {count}',
    'Open profile': 'Відкрити профіль',
    'See who liked is coming soon.':
        'Функція «Переглянути, хто вподобав» скоро з’явиться.',
    'This content is no longer available.': 'Цей вміст більше не доступний.',
    'Too many requests. Try again in a minute.':
        'Забагато запитів. Спробуй ще раз за хвилину.',
    "Couldn't load this list. Try again.":
        'Не вдалося завантажити список. Спробуй ще раз.',
    'See who liked': 'Переглянути, хто вподобав',
    'See who reacted': 'Переглянути, хто відреагував',
    'Likes · {count}': 'Вподобання · {count}',
    'See who liked. Likes: {count}':
        'Переглянути, хто вподобав. Вподобань: {count}',
    'See who reacted. Reactions: {count}':
        'Переглянути, хто відреагував. Реакцій: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Вподобали: {names} та ще {count}. Переглянути, хто вподобав.',
    'Liked by {names}. See who liked.':
        'Вподобали: {names}. Переглянути, хто вподобав.',
    'Like comment. Likes: {count}': 'Вподобати коментар. Вподобань: {count}',
    'Unlike comment. Likes: {count}':
        'Скасувати вподобання коментаря. Вподобань: {count}',
    'Who liked': 'Хто вподобав',
    'Who liked. Likes: {count}': 'Хто вподобав. Вподобань: {count}',
    "Couldn't update your like. Try again.":
        'Не вдалося оновити вподобання. Спробуй ще раз.',
    'Premium offer': 'Пропозиція Premium',
    'See who liked — a Premium feature':
        'Переглянути, хто вподобав — функція Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'З Premium ти бачиш людей, які вподобали Voice Moment, Yeel чи коментар або відреагували на повідомлення на сервері. Кількість вподобань і далі бачать усі.',
    'Explore Premium': 'Дізнатися про Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium поки не можна придбати. Незабаром.',
    'See who liked is included with Premium':
        'Функцію «Переглянути, хто вподобав» включено в Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Значок, сяйво, налаштування конфіденційності, перегляд вподобань і помірне просування в Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Переглядай, хто вподобав Voice Moments, Yeels, коментарі та повідомлення на серверах',
    'Hide my likes': 'Приховати мої вподобання',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Тебе не буде в списках YO Voice, які показують, хто вподобав або відреагував. Лічильники не змінюються. Учасники сервера й далі отримують твої реакції в спільних каналах.',
    "Couldn't update this setting. Try again.":
        'Не вдалося змінити це налаштування. Спробуй ще раз.',
    'Privacy': 'Конфіденційність',
    '{count} people liked this Moment.zero':
        '{count} людей вподобали цей Moment',
    '{count} people liked this Moment.one':
        '{count} людина вподобала цей Moment',
    '{count} people liked this Moment.two':
        '{count} людини вподобали цей Moment',
    '{count} people liked this Moment.few':
        '{count} людини вподобали цей Moment',
    '{count} people liked this Moment.many':
        '{count} людей вподобали цей Moment',
    '{count} people liked this Moment.other':
        '{count} людей вподобали цей Moment',
    '{count} people liked this Yeel.zero': '{count} людей вподобали цей Yeel',
    '{count} people liked this Yeel.one': '{count} людина вподобала цей Yeel',
    '{count} people liked this Yeel.two': '{count} людини вподобали цей Yeel',
    '{count} people liked this Yeel.few': '{count} людини вподобали цей Yeel',
    '{count} people liked this Yeel.many': '{count} людей вподобали цей Yeel',
    '{count} people liked this Yeel.other': '{count} людей вподобали цей Yeel',
    '{count} people liked this comment.zero':
        '{count} людей вподобали цей коментар',
    '{count} people liked this comment.one':
        '{count} людина вподобала цей коментар',
    '{count} people liked this comment.two':
        '{count} людини вподобали цей коментар',
    '{count} people liked this comment.few':
        '{count} людини вподобали цей коментар',
    '{count} people liked this comment.many':
        '{count} людей вподобали цей коментар',
    '{count} people liked this comment.other':
        '{count} людей вподобали цей коментар',
    '{count} people reacted to this message.zero':
        '{count} людей відреагували на це повідомлення',
    '{count} people reacted to this message.one':
        '{count} людина відреагувала на це повідомлення',
    '{count} people reacted to this message.two':
        '{count} людини відреагували на це повідомлення',
    '{count} people reacted to this message.few':
        '{count} людини відреагували на це повідомлення',
    '{count} people reacted to this message.many':
        '{count} людей відреагували на це повідомлення',
    '{count} people reacted to this message.other':
        '{count} людей відреагували на це повідомлення',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} людей вподобали цей допис',
    '{count} people liked this post.one': '{count} людина вподобала цей допис',
    '{count} people liked this post.two': '{count} людини вподобали цей допис',
    '{count} people liked this post.few': '{count} людини вподобали цей допис',
    '{count} people liked this post.many': '{count} людей вподобали цей допис',
    '{count} people liked this post.other': '{count} людей вподобали цей допис',
  },
  'ru': <String, String>{
    'likers.titleLikes': 'Лайки',
    'likers.titleReactions': 'Реакции',
    'likers.tabAll': 'Все',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Вы',
    '{name}, reacted {emoji}': '{name}, реакция {emoji}',
    "Some people aren't shown.": 'Некоторые люди не показаны.',
    'No one to show here.': 'Здесь некого показать.',
    'You can hide your own likes in Settings → Privacy.':
        'Свои лайки можно скрыть в разделе «Настройки» → «Конфиденциальность».',
    'Likes loaded: {count}': 'Загружено лайков: {count}',
    'Reactions loaded: {count}': 'Загружено реакций: {count}',
    'Open profile': 'Открыть профиль',
    'See who liked is coming soon.':
        'Функция «Посмотреть, кому понравилось» скоро появится.',
    'This content is no longer available.': 'Этот контент больше недоступен.',
    'Too many requests. Try again in a minute.':
        'Слишком много запросов. Повторите попытку через минуту.',
    "Couldn't load this list. Try again.":
        'Не удалось загрузить список. Повторите попытку.',
    'See who liked': 'Посмотреть, кому понравилось',
    'See who reacted': 'Посмотреть, кто отреагировал',
    'Likes · {count}': 'Лайки · {count}',
    'See who liked. Likes: {count}':
        'Посмотреть, кому понравилось. Лайков: {count}',
    'See who reacted. Reactions: {count}':
        'Посмотреть, кто отреагировал. Реакций: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Понравилось: {names} и ещё {count}. Посмотреть, кому понравилось.',
    'Liked by {names}. See who liked.':
        'Понравилось: {names}. Посмотреть, кому понравилось.',
    'Like comment. Likes: {count}':
        'Поставить лайк комментарию. Лайков: {count}',
    'Unlike comment. Likes: {count}':
        'Убрать лайк с комментария. Лайков: {count}',
    'Who liked': 'Кому понравилось',
    'Who liked. Likes: {count}': 'Кому понравилось. Лайков: {count}',
    "Couldn't update your like. Try again.":
        'Не удалось обновить лайк. Повторите попытку.',
    'Premium offer': 'Предложение Premium',
    'See who liked — a Premium feature':
        'Посмотреть, кому понравилось — функция Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'С Premium вы видите людей, которым понравился Voice Moment, Yeel или комментарий, а также тех, кто отреагировал на сообщение на сервере. Число лайков по-прежнему видно всем.',
    'Explore Premium': 'Узнать о Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium пока нельзя купить. Скоро появится.',
    'See who liked is included with Premium':
        'Функция «Посмотреть, кому понравилось» входит в Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Значок, сияние, настройки конфиденциальности, просмотр лайков и умеренное продвижение в Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Смотрите, кому понравились Voice Moments, Yeels, комментарии и сообщения на серверах',
    'Hide my likes': 'Скрывать мои лайки',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Вас не будет в списках YO Voice, где видно, кто поставил лайк или отреагировал. Счётчики не меняются. Участники сервера по-прежнему получают ваши реакции в общих каналах.',
    "Couldn't update this setting. Try again.":
        'Не удалось изменить эту настройку. Повторите попытку.',
    'Privacy': 'Конфиденциальность',
    '{count} people liked this Moment.zero':
        '{count} человек оценили этот Moment',
    '{count} people liked this Moment.one':
        '{count} человек оценил этот Moment',
    '{count} people liked this Moment.two':
        '{count} человека оценили этот Moment',
    '{count} people liked this Moment.few':
        '{count} человека оценили этот Moment',
    '{count} people liked this Moment.many':
        '{count} человек оценили этот Moment',
    '{count} people liked this Moment.other':
        '{count} человека оценили этот Moment',
    '{count} people liked this Yeel.zero': '{count} человек оценили этот Yeel',
    '{count} people liked this Yeel.one': '{count} человек оценил этот Yeel',
    '{count} people liked this Yeel.two': '{count} человека оценили этот Yeel',
    '{count} people liked this Yeel.few': '{count} человека оценили этот Yeel',
    '{count} people liked this Yeel.many': '{count} человек оценили этот Yeel',
    '{count} people liked this Yeel.other':
        '{count} человека оценили этот Yeel',
    '{count} people liked this comment.zero':
        '{count} человек оценили этот комментарий',
    '{count} people liked this comment.one':
        '{count} человек оценил этот комментарий',
    '{count} people liked this comment.two':
        '{count} человека оценили этот комментарий',
    '{count} people liked this comment.few':
        '{count} человека оценили этот комментарий',
    '{count} people liked this comment.many':
        '{count} человек оценили этот комментарий',
    '{count} people liked this comment.other':
        '{count} человека оценили этот комментарий',
    '{count} people reacted to this message.zero':
        '{count} человек отреагировали на это сообщение',
    '{count} people reacted to this message.one':
        '{count} человек отреагировал на это сообщение',
    '{count} people reacted to this message.two':
        '{count} человека отреагировали на это сообщение',
    '{count} people reacted to this message.few':
        '{count} человека отреагировали на это сообщение',
    '{count} people reacted to this message.many':
        '{count} человек отреагировали на это сообщение',
    '{count} people reacted to this message.other':
        '{count} человека отреагировали на это сообщение',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} человек оценили этот пост',
    '{count} people liked this post.one': '{count} человек оценил этот пост',
    '{count} people liked this post.two': '{count} человека оценили этот пост',
    '{count} people liked this post.few': '{count} человека оценили этот пост',
    '{count} people liked this post.many': '{count} человек оценили этот пост',
    '{count} people liked this post.other':
        '{count} человека оценили этот пост',
  },
  'cs': <String, String>{
    'likers.titleLikes': 'Líbí se',
    'likers.titleReactions': 'Reakce',
    'likers.tabAll': 'Vše',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Vy',
    '{name}, reacted {emoji}': '{name}, reakce {emoji}',
    "Some people aren't shown.": 'Některé osoby nejsou zobrazeny.',
    'No one to show here.': 'Není tu nikdo k zobrazení.',
    'You can hide your own likes in Settings → Privacy.':
        'Svá označení Líbí se můžete skrýt v Nastavení → Soukromí.',
    'Likes loaded: {count}': 'Načteno označení Líbí se: {count}',
    'Reactions loaded: {count}': 'Načteno reakcí: {count}',
    'Open profile': 'Otevřít profil',
    'See who liked is coming soon.':
        'Funkce „Zobrazit, komu se líbí“ bude brzy k dispozici.',
    'This content is no longer available.': 'Tento obsah už není k dispozici.',
    'Too many requests. Try again in a minute.':
        'Příliš mnoho požadavků. Zkuste to znovu za minutu.',
    "Couldn't load this list. Try again.":
        'Seznam se nepodařilo načíst. Zkuste to znovu.',
    'See who liked': 'Zobrazit, komu se líbí',
    'See who reacted': 'Zobrazit, kdo reagoval',
    'Likes · {count}': 'Líbí se · {count}',
    'See who liked. Likes: {count}':
        'Zobrazit, komu se líbí. Označení Líbí se: {count}',
    'See who reacted. Reactions: {count}':
        'Zobrazit, kdo reagoval. Reakce: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Líbí se: {names} a dalším {count}. Zobrazit, komu se líbí.',
    'Liked by {names}. See who liked.':
        'Líbí se: {names}. Zobrazit, komu se líbí.',
    'Like comment. Likes: {count}':
        'Označit komentář jako Líbí se. Označení Líbí se: {count}',
    'Unlike comment. Likes: {count}':
        'Zrušit Líbí se u komentáře. Označení Líbí se: {count}',
    'Who liked': 'Komu se líbí',
    'Who liked. Likes: {count}': 'Komu se líbí. Označení Líbí se: {count}',
    "Couldn't update your like. Try again.":
        'Označení Líbí se se nepodařilo aktualizovat. Zkuste to znovu.',
    'Premium offer': 'Nabídka Premium',
    'See who liked — a Premium feature':
        'Zobrazit, komu se líbí — funkce Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'S Premium uvidíte lidi, kterým se líbil Voice Moment, Yeel nebo komentář, nebo kteří reagovali na zprávu na serveru. Počty označení Líbí se zůstávají viditelné pro všechny.',
    'Explore Premium': 'Prozkoumat Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium zatím nelze koupit. Už brzy.',
    'See who liked is included with Premium':
        'Funkce „Zobrazit, komu se líbí“ je součástí Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Odznak, třpyt, nastavení soukromí, zobrazení, komu se co líbí, a mírná podpora v Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Zobrazit, komu se líbí Voice Moments, Yeels, komentáře a zprávy na serverech',
    'Hide my likes': 'Skrýt moje označení Líbí se',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Neobjevíte se v seznamech YO Voice, které ukazují, kdo dal Líbí se nebo reagoval. Počty se nemění. Členové serveru dál dostávají vaše reakce ve společných kanálech.',
    "Couldn't update this setting. Try again.":
        'Toto nastavení se nepodařilo změnit. Zkuste to znovu.',
    'Privacy': 'Soukromí',
    '{count} people liked this Moment.zero':
        '{count} osob dalo Líbí se tomuto Momentu',
    '{count} people liked this Moment.one':
        '{count} osoba dala Líbí se tomuto Momentu',
    '{count} people liked this Moment.two':
        '{count} osoby daly Líbí se tomuto Momentu',
    '{count} people liked this Moment.few':
        '{count} osoby daly Líbí se tomuto Momentu',
    '{count} people liked this Moment.many':
        '{count} osoby dalo Líbí se tomuto Momentu',
    '{count} people liked this Moment.other':
        '{count} osob dalo Líbí se tomuto Momentu',
    '{count} people liked this Yeel.zero':
        '{count} osob dalo Líbí se tomuto Yeelu',
    '{count} people liked this Yeel.one':
        '{count} osoba dala Líbí se tomuto Yeelu',
    '{count} people liked this Yeel.two':
        '{count} osoby daly Líbí se tomuto Yeelu',
    '{count} people liked this Yeel.few':
        '{count} osoby daly Líbí se tomuto Yeelu',
    '{count} people liked this Yeel.many':
        '{count} osoby dalo Líbí se tomuto Yeelu',
    '{count} people liked this Yeel.other':
        '{count} osob dalo Líbí se tomuto Yeelu',
    '{count} people liked this comment.zero':
        '{count} osob dalo Líbí se tomuto komentáři',
    '{count} people liked this comment.one':
        '{count} osoba dala Líbí se tomuto komentáři',
    '{count} people liked this comment.two':
        '{count} osoby daly Líbí se tomuto komentáři',
    '{count} people liked this comment.few':
        '{count} osoby daly Líbí se tomuto komentáři',
    '{count} people liked this comment.many':
        '{count} osoby dalo Líbí se tomuto komentáři',
    '{count} people liked this comment.other':
        '{count} osob dalo Líbí se tomuto komentáři',
    '{count} people reacted to this message.zero':
        '{count} osob reagovalo na tuto zprávu',
    '{count} people reacted to this message.one':
        '{count} osoba reagovala na tuto zprávu',
    '{count} people reacted to this message.two':
        '{count} osoby reagovaly na tuto zprávu',
    '{count} people reacted to this message.few':
        '{count} osoby reagovaly na tuto zprávu',
    '{count} people reacted to this message.many':
        '{count} osoby reagovalo na tuto zprávu',
    '{count} people reacted to this message.other':
        '{count} osob reagovalo na tuto zprávu',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} osob dalo Líbí se tomuto příspěvku',
    '{count} people liked this post.one':
        '{count} osoba dala Líbí se tomuto příspěvku',
    '{count} people liked this post.two':
        '{count} osoby daly Líbí se tomuto příspěvku',
    '{count} people liked this post.few':
        '{count} osoby daly Líbí se tomuto příspěvku',
    '{count} people liked this post.many':
        '{count} osoby dalo Líbí se tomuto příspěvku',
    '{count} people liked this post.other':
        '{count} osob dalo Líbí se tomuto příspěvku',
  },
  'sk': <String, String>{
    'likers.titleLikes': 'Páči sa mi',
    'likers.titleReactions': 'Reakcie',
    'likers.tabAll': 'Všetky',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Vy',
    '{name}, reacted {emoji}': '{name}, reakcia {emoji}',
    "Some people aren't shown.": 'Niektoré osoby sa nezobrazujú.',
    'No one to show here.': 'Nie je tu nikto na zobrazenie.',
    'You can hide your own likes in Settings → Privacy.':
        'Svoje označenia Páči sa mi môžete skryť v Nastaveniach → Súkromie.',
    'Likes loaded: {count}': 'Načítané označenia Páči sa mi: {count}',
    'Reactions loaded: {count}': 'Načítané reakcie: {count}',
    'Open profile': 'Otvoriť profil',
    'See who liked is coming soon.':
        'Funkcia „Zobraziť, komu sa páči“ bude čoskoro k dispozícii.',
    'This content is no longer available.':
        'Tento obsah už nie je k dispozícii.',
    'Too many requests. Try again in a minute.':
        'Príliš veľa požiadaviek. Skúste to znova o minútu.',
    "Couldn't load this list. Try again.":
        'Zoznam sa nepodarilo načítať. Skúste to znova.',
    'See who liked': 'Zobraziť, komu sa páči',
    'See who reacted': 'Zobraziť, kto reagoval',
    'Likes · {count}': 'Páči sa mi · {count}',
    'See who liked. Likes: {count}':
        'Zobraziť, komu sa páči. Označenia Páči sa mi: {count}',
    'See who reacted. Reactions: {count}':
        'Zobraziť, kto reagoval. Reakcie: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Páči sa: {names} a ďalším {count}. Zobraziť, komu sa páči.',
    'Liked by {names}. See who liked.':
        'Páči sa: {names}. Zobraziť, komu sa páči.',
    'Like comment. Likes: {count}':
        'Označiť komentár ako Páči sa mi. Označenia Páči sa mi: {count}',
    'Unlike comment. Likes: {count}':
        'Zrušiť Páči sa mi pri komentári. Označenia Páči sa mi: {count}',
    'Who liked': 'Komu sa páči',
    'Who liked. Likes: {count}': 'Komu sa páči. Označenia Páči sa mi: {count}',
    "Couldn't update your like. Try again.":
        'Označenie Páči sa mi sa nepodarilo aktualizovať. Skúste to znova.',
    'Premium offer': 'Ponuka Premium',
    'See who liked — a Premium feature':
        'Zobraziť, komu sa páči — funkcia Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'S Premium uvidíte ľudí, ktorým sa páčil Voice Moment, Yeel alebo komentár, alebo ktorí reagovali na správu na serveri. Počty označení Páči sa mi zostávajú viditeľné pre všetkých.',
    'Explore Premium': 'Preskúmať Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium sa zatiaľ nedá kúpiť. Už čoskoro.',
    'See who liked is included with Premium':
        'Funkcia „Zobraziť, komu sa páči“ je súčasťou Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Odznak, trblietanie, nastavenia súkromia, zobrazenie, komu sa čo páči, a mierna podpora v Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Zobraziť, komu sa páčia Voice Moments, Yeels, komentáre a správy na serveroch',
    'Hide my likes': 'Skryť moje označenia Páči sa mi',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Nezobrazíte sa v zoznamoch YO Voice, ktoré ukazujú, kto dal Páči sa mi alebo reagoval. Počty sa nemenia. Členovia servera naďalej dostávajú vaše reakcie v spoločných kanáloch.',
    "Couldn't update this setting. Try again.":
        'Toto nastavenie sa nepodarilo zmeniť. Skúste to znova.',
    'Privacy': 'Súkromie',
    '{count} people liked this Moment.zero':
        '{count} osôb dalo Páči sa mi tomuto Momentu',
    '{count} people liked this Moment.one':
        '{count} osoba dala Páči sa mi tomuto Momentu',
    '{count} people liked this Moment.two':
        '{count} osoby dali Páči sa mi tomuto Momentu',
    '{count} people liked this Moment.few':
        '{count} osoby dali Páči sa mi tomuto Momentu',
    '{count} people liked this Moment.many':
        '{count} osoby dalo Páči sa mi tomuto Momentu',
    '{count} people liked this Moment.other':
        '{count} osôb dalo Páči sa mi tomuto Momentu',
    '{count} people liked this Yeel.zero':
        '{count} osôb dalo Páči sa mi tomuto Yeelu',
    '{count} people liked this Yeel.one':
        '{count} osoba dala Páči sa mi tomuto Yeelu',
    '{count} people liked this Yeel.two':
        '{count} osoby dali Páči sa mi tomuto Yeelu',
    '{count} people liked this Yeel.few':
        '{count} osoby dali Páči sa mi tomuto Yeelu',
    '{count} people liked this Yeel.many':
        '{count} osoby dalo Páči sa mi tomuto Yeelu',
    '{count} people liked this Yeel.other':
        '{count} osôb dalo Páči sa mi tomuto Yeelu',
    '{count} people liked this comment.zero':
        '{count} osôb dalo Páči sa mi tomuto komentáru',
    '{count} people liked this comment.one':
        '{count} osoba dala Páči sa mi tomuto komentáru',
    '{count} people liked this comment.two':
        '{count} osoby dali Páči sa mi tomuto komentáru',
    '{count} people liked this comment.few':
        '{count} osoby dali Páči sa mi tomuto komentáru',
    '{count} people liked this comment.many':
        '{count} osoby dalo Páči sa mi tomuto komentáru',
    '{count} people liked this comment.other':
        '{count} osôb dalo Páči sa mi tomuto komentáru',
    '{count} people reacted to this message.zero':
        '{count} osôb reagovalo na túto správu',
    '{count} people reacted to this message.one':
        '{count} osoba reagovala na túto správu',
    '{count} people reacted to this message.two':
        '{count} osoby reagovali na túto správu',
    '{count} people reacted to this message.few':
        '{count} osoby reagovali na túto správu',
    '{count} people reacted to this message.many':
        '{count} osoby reagovalo na túto správu',
    '{count} people reacted to this message.other':
        '{count} osôb reagovalo na túto správu',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} osôb dalo Páči sa mi tomuto príspevku',
    '{count} people liked this post.one':
        '{count} osoba dala Páči sa mi tomuto príspevku',
    '{count} people liked this post.two':
        '{count} osoby dali Páči sa mi tomuto príspevku',
    '{count} people liked this post.few':
        '{count} osoby dali Páči sa mi tomuto príspevku',
    '{count} people liked this post.many':
        '{count} osoby dalo Páči sa mi tomuto príspevku',
    '{count} people liked this post.other':
        '{count} osôb dalo Páči sa mi tomuto príspevku',
  },
  'bg': <String, String>{
    'likers.titleLikes': 'Харесвания',
    'likers.titleReactions': 'Реакции',
    'likers.tabAll': 'Всички',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Ти',
    '{name}, reacted {emoji}': '{name}, реагира с {emoji}',
    "Some people aren't shown.": 'Някои хора не са показани.',
    'No one to show here.': 'Тук няма кого да покажем.',
    'You can hide your own likes in Settings → Privacy.':
        'Можеш да скриеш своите харесвания от Настройки → Поверителност.',
    'Likes loaded: {count}': 'Заредени харесвания: {count}',
    'Reactions loaded: {count}': 'Заредени реакции: {count}',
    'Open profile': 'Отвори профила',
    'See who liked is coming soon.': '„Виж кой харесва“ идва скоро.',
    'This content is no longer available.':
        'Това съдържание вече не е налично.',
    'Too many requests. Try again in a minute.':
        'Твърде много заявки. Опитай отново след минута.',
    "Couldn't load this list. Try again.":
        'Списъкът не можа да се зареди. Опитай отново.',
    'See who liked': 'Виж кой харесва',
    'See who reacted': 'Виж кой реагира',
    'Likes · {count}': 'Харесвания · {count}',
    'See who liked. Likes: {count}': 'Виж кой харесва. Харесвания: {count}',
    'See who reacted. Reactions: {count}': 'Виж кой реагира. Реакции: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Харесано от {names} и още {count}. Виж кой харесва.',
    'Liked by {names}. See who liked.': 'Харесано от {names}. Виж кой харесва.',
    'Like comment. Likes: {count}': 'Харесай коментара. Харесвания: {count}',
    'Unlike comment. Likes: {count}':
        'Премахни харесването на коментара. Харесвания: {count}',
    'Who liked': 'Кой харесва',
    'Who liked. Likes: {count}': 'Кой харесва. Харесвания: {count}',
    "Couldn't update your like. Try again.":
        'Харесването не можа да се обнови. Опитай отново.',
    'Premium offer': 'Оферта Premium',
    'See who liked — a Premium feature': 'Виж кой харесва — функция на Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'С Premium виждаш хората, които са харесали Voice Moment, Yeel или коментар, или са реагирали на съобщение в сървър. Броят на харесванията остава видим за всички.',
    'Explore Premium': 'Разгледай Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium все още не може да се купи. Очаквай скоро.',
    'See who liked is included with Premium':
        '„Виж кой харесва“ е включено в Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Значка, блясък, настройки за поверителност, преглед на харесванията и умерен тласък в Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Виж кой харесва Voice Moments, Yeels, коментари и съобщения в сървъри',
    'Hide my likes': 'Скрий моите харесвания',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Няма да се появяваш в списъците на YO Voice с хората, които са харесали или реагирали. Броячите не се променят. Членовете на сървъра продължават да получават реакциите ти в общите канали.',
    "Couldn't update this setting. Try again.":
        'Настройката не можа да се промени. Опитай отново.',
    'Privacy': 'Поверителност',
    '{count} people liked this Moment.zero':
        '{count} души харесаха този Moment',
    '{count} people liked this Moment.one': '{count} човек хареса този Moment',
    '{count} people liked this Moment.two': '{count} души харесаха този Moment',
    '{count} people liked this Moment.few': '{count} души харесаха този Moment',
    '{count} people liked this Moment.many':
        '{count} души харесаха този Moment',
    '{count} people liked this Moment.other':
        '{count} души харесаха този Moment',
    '{count} people liked this Yeel.zero': '{count} души харесаха този Yeel',
    '{count} people liked this Yeel.one': '{count} човек хареса този Yeel',
    '{count} people liked this Yeel.two': '{count} души харесаха този Yeel',
    '{count} people liked this Yeel.few': '{count} души харесаха този Yeel',
    '{count} people liked this Yeel.many': '{count} души харесаха този Yeel',
    '{count} people liked this Yeel.other': '{count} души харесаха този Yeel',
    '{count} people liked this comment.zero':
        '{count} души харесаха този коментар',
    '{count} people liked this comment.one':
        '{count} човек хареса този коментар',
    '{count} people liked this comment.two':
        '{count} души харесаха този коментар',
    '{count} people liked this comment.few':
        '{count} души харесаха този коментар',
    '{count} people liked this comment.many':
        '{count} души харесаха този коментар',
    '{count} people liked this comment.other':
        '{count} души харесаха този коментар',
    '{count} people reacted to this message.zero':
        '{count} души реагираха на това съобщение',
    '{count} people reacted to this message.one':
        '{count} човек реагира на това съобщение',
    '{count} people reacted to this message.two':
        '{count} души реагираха на това съобщение',
    '{count} people reacted to this message.few':
        '{count} души реагираха на това съобщение',
    '{count} people reacted to this message.many':
        '{count} души реагираха на това съобщение',
    '{count} people reacted to this message.other':
        '{count} души реагираха на това съобщение',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} души харесаха тази публикация',
    '{count} people liked this post.one':
        '{count} човек хареса тази публикация',
    '{count} people liked this post.two':
        '{count} души харесаха тази публикация',
    '{count} people liked this post.few':
        '{count} души харесаха тази публикация',
    '{count} people liked this post.many':
        '{count} души харесаха тази публикация',
    '{count} people liked this post.other':
        '{count} души харесаха тази публикация',
  },
  'hr': <String, String>{
    'likers.titleLikes': 'Sviđanja',
    'likers.titleReactions': 'Reakcije',
    'likers.tabAll': 'Sve',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Ti',
    '{name}, reacted {emoji}': '{name}, reakcija {emoji}',
    "Some people aren't shown.": 'Neke osobe nisu prikazane.',
    'No one to show here.': 'Ovdje nema nikoga za prikaz.',
    'You can hide your own likes in Settings → Privacy.':
        'Svoja sviđanja možeš sakriti u Postavkama → Privatnost.',
    'Likes loaded: {count}': 'Učitana sviđanja: {count}',
    'Reactions loaded: {count}': 'Učitane reakcije: {count}',
    'Open profile': 'Otvori profil',
    'See who liked is coming soon.': '„Pogledaj kome se sviđa” uskoro stiže.',
    'This content is no longer available.': 'Ovaj sadržaj više nije dostupan.',
    'Too many requests. Try again in a minute.':
        'Previše zahtjeva. Pokušaj ponovno za minutu.',
    "Couldn't load this list. Try again.":
        'Popis nije moguće učitati. Pokušaj ponovno.',
    'See who liked': 'Pogledaj kome se sviđa',
    'See who reacted': 'Pogledaj tko je reagirao',
    'Likes · {count}': 'Sviđanja · {count}',
    'See who liked. Likes: {count}':
        'Pogledaj kome se sviđa. Sviđanja: {count}',
    'See who reacted. Reactions: {count}':
        'Pogledaj tko je reagirao. Reakcije: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Sviđa se: {names} i još {count}. Pogledaj kome se sviđa.',
    'Liked by {names}. See who liked.':
        'Sviđa se: {names}. Pogledaj kome se sviđa.',
    'Like comment. Likes: {count}':
        'Označi da ti se komentar sviđa. Sviđanja: {count}',
    'Unlike comment. Likes: {count}':
        'Poništi sviđanje komentara. Sviđanja: {count}',
    'Who liked': 'Kome se sviđa',
    'Who liked. Likes: {count}': 'Kome se sviđa. Sviđanja: {count}',
    "Couldn't update your like. Try again.":
        'Sviđanje nije moguće ažurirati. Pokušaj ponovno.',
    'Premium offer': 'Premium ponuda',
    'See who liked — a Premium feature':
        'Pogledaj kome se sviđa — Premium značajka',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Uz Premium vidiš osobe kojima se svidio Voice Moment, Yeel ili komentar ili koje su reagirale na poruku na serveru. Broj sviđanja i dalje je svima vidljiv.',
    'Explore Premium': 'Istraži Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium još nije moguće kupiti. Uskoro stiže.',
    'See who liked is included with Premium':
        '„Pogledaj kome se sviđa” uključeno je u Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Značka, sjaj, postavke privatnosti, pregled sviđanja i umjereni poticaj na Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Pogledaj kome se sviđaju Voice Moments, Yeels, komentari i poruke na serverima',
    'Hide my likes': 'Sakrij moja sviđanja',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Nećeš se pojavljivati na YO Voice popisima koji prikazuju tko je označio sviđanje ili reagirao. Brojevi se ne mijenjaju. Članovi servera i dalje primaju tvoje reakcije u zajedničkim kanalima.',
    "Couldn't update this setting. Try again.":
        'Postavku nije moguće promijeniti. Pokušaj ponovno.',
    'Privacy': 'Privatnost',
    '{count} people liked this Moment.zero':
        '{count} osoba označilo je sviđanje za ovaj Moment',
    '{count} people liked this Moment.one':
        '{count} osoba označila je sviđanje za ovaj Moment',
    '{count} people liked this Moment.two':
        '{count} osobe označile su sviđanje za ovaj Moment',
    '{count} people liked this Moment.few':
        '{count} osobe označile su sviđanje za ovaj Moment',
    '{count} people liked this Moment.many':
        '{count} osoba označilo je sviđanje za ovaj Moment',
    '{count} people liked this Moment.other':
        '{count} osoba označilo je sviđanje za ovaj Moment',
    '{count} people liked this Yeel.zero':
        '{count} osoba označilo je sviđanje za ovaj Yeel',
    '{count} people liked this Yeel.one':
        '{count} osoba označila je sviđanje za ovaj Yeel',
    '{count} people liked this Yeel.two':
        '{count} osobe označile su sviđanje za ovaj Yeel',
    '{count} people liked this Yeel.few':
        '{count} osobe označile su sviđanje za ovaj Yeel',
    '{count} people liked this Yeel.many':
        '{count} osoba označilo je sviđanje za ovaj Yeel',
    '{count} people liked this Yeel.other':
        '{count} osoba označilo je sviđanje za ovaj Yeel',
    '{count} people liked this comment.zero':
        '{count} osoba označilo je sviđanje za ovaj komentar',
    '{count} people liked this comment.one':
        '{count} osoba označila je sviđanje za ovaj komentar',
    '{count} people liked this comment.two':
        '{count} osobe označile su sviđanje za ovaj komentar',
    '{count} people liked this comment.few':
        '{count} osobe označile su sviđanje za ovaj komentar',
    '{count} people liked this comment.many':
        '{count} osoba označilo je sviđanje za ovaj komentar',
    '{count} people liked this comment.other':
        '{count} osoba označilo je sviđanje za ovaj komentar',
    '{count} people reacted to this message.zero':
        '{count} osoba reagiralo je na ovu poruku',
    '{count} people reacted to this message.one':
        '{count} osoba reagirala je na ovu poruku',
    '{count} people reacted to this message.two':
        '{count} osobe reagirale su na ovu poruku',
    '{count} people reacted to this message.few':
        '{count} osobe reagirale su na ovu poruku',
    '{count} people reacted to this message.many':
        '{count} osoba reagiralo je na ovu poruku',
    '{count} people reacted to this message.other':
        '{count} osoba reagiralo je na ovu poruku',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': 'Ova objava sviđa se {count} osoba',
    '{count} people liked this post.one': 'Ova objava sviđa se {count} osobi',
    '{count} people liked this post.two': 'Ova objava sviđa se {count} osobe',
    '{count} people liked this post.few': 'Ova objava sviđa se {count} osobe',
    '{count} people liked this post.many': 'Ova objava sviđa se {count} osoba',
    '{count} people liked this post.other': 'Ova objava sviđa se {count} osoba',
  },
  'sr': <String, String>{
    'likers.titleLikes': 'Свиђања',
    'likers.titleReactions': 'Реакције',
    'likers.tabAll': 'Све',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Ти',
    '{name}, reacted {emoji}': '{name}, реакција {emoji}',
    "Some people aren't shown.": 'Неке особе нису приказане.',
    'No one to show here.': 'Овде нема никога за приказ.',
    'You can hide your own likes in Settings → Privacy.':
        'Своја свиђања можеш да сакријеш у Подешавањима → Приватност.',
    'Likes loaded: {count}': 'Учитана свиђања: {count}',
    'Reactions loaded: {count}': 'Учитане реакције: {count}',
    'Open profile': 'Отвори профил',
    'See who liked is coming soon.': '„Погледај коме се свиђа” стиже ускоро.',
    'This content is no longer available.': 'Овај садржај више није доступан.',
    'Too many requests. Try again in a minute.':
        'Превише захтева. Покушај поново за минут.',
    "Couldn't load this list. Try again.":
        'Листу није могуће учитати. Покушај поново.',
    'See who liked': 'Погледај коме се свиђа',
    'See who reacted': 'Погледај ко је реаговао',
    'Likes · {count}': 'Свиђања · {count}',
    'See who liked. Likes: {count}': 'Погледај коме се свиђа. Свиђања: {count}',
    'See who reacted. Reactions: {count}':
        'Погледај ко је реаговао. Реакције: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Свиђа се: {names} и још {count}. Погледај коме се свиђа.',
    'Liked by {names}. See who liked.':
        'Свиђа се: {names}. Погледај коме се свиђа.',
    'Like comment. Likes: {count}':
        'Означи да ти се коментар свиђа. Свиђања: {count}',
    'Unlike comment. Likes: {count}':
        'Поништи свиђање коментара. Свиђања: {count}',
    'Who liked': 'Коме се свиђа',
    'Who liked. Likes: {count}': 'Коме се свиђа. Свиђања: {count}',
    "Couldn't update your like. Try again.":
        'Свиђање није могуће ажурирати. Покушај поново.',
    'Premium offer': 'Premium понуда',
    'See who liked — a Premium feature':
        'Погледај коме се свиђа — Premium функција',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Уз Premium видиш особе којима се свидео Voice Moment, Yeel или коментар или које су реаговале на поруку на серверу. Број свиђања и даље је свима видљив.',
    'Explore Premium': 'Истражи Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium још није могуће купити. Стиже ускоро.',
    'See who liked is included with Premium':
        '„Погледај коме се свиђа” је укључено у Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Значка, сјај, подешавања приватности, преглед свиђања и умерено истицање на Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Погледај коме се свиђају Voice Moments, Yeels, коментари и поруке на серверима',
    'Hide my likes': 'Сакриј моја свиђања',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Нећеш се појављивати на YO Voice листама које приказују ко је означио свиђање или реаговао. Бројеви се не мењају. Чланови сервера и даље примају твоје реакције у заједничким каналима.',
    "Couldn't update this setting. Try again.":
        'Подешавање није могуће променити. Покушај поново.',
    'Privacy': 'Приватност',
    '{count} people liked this Moment.zero':
        '{count} особа је означило свиђање за овај Moment',
    '{count} people liked this Moment.one':
        '{count} особа је означила свиђање за овај Moment',
    '{count} people liked this Moment.two':
        '{count} особе су означиле свиђање за овај Moment',
    '{count} people liked this Moment.few':
        '{count} особе су означиле свиђање за овај Moment',
    '{count} people liked this Moment.many':
        '{count} особа је означило свиђање за овај Moment',
    '{count} people liked this Moment.other':
        '{count} особа је означило свиђање за овај Moment',
    '{count} people liked this Yeel.zero':
        '{count} особа је означило свиђање за овај Yeel',
    '{count} people liked this Yeel.one':
        '{count} особа је означила свиђање за овај Yeel',
    '{count} people liked this Yeel.two':
        '{count} особе су означиле свиђање за овај Yeel',
    '{count} people liked this Yeel.few':
        '{count} особе су означиле свиђање за овај Yeel',
    '{count} people liked this Yeel.many':
        '{count} особа је означило свиђање за овај Yeel',
    '{count} people liked this Yeel.other':
        '{count} особа је означило свиђање за овај Yeel',
    '{count} people liked this comment.zero':
        '{count} особа је означило свиђање за овај коментар',
    '{count} people liked this comment.one':
        '{count} особа је означила свиђање за овај коментар',
    '{count} people liked this comment.two':
        '{count} особе су означиле свиђање за овај коментар',
    '{count} people liked this comment.few':
        '{count} особе су означиле свиђање за овај коментар',
    '{count} people liked this comment.many':
        '{count} особа је означило свиђање за овај коментар',
    '{count} people liked this comment.other':
        '{count} особа је означило свиђање за овај коментар',
    '{count} people reacted to this message.zero':
        '{count} особа је реаговало на ову поруку',
    '{count} people reacted to this message.one':
        '{count} особа је реаговала на ову поруку',
    '{count} people reacted to this message.two':
        '{count} особе су реаговале на ову поруку',
    '{count} people reacted to this message.few':
        '{count} особе су реаговале на ову поруку',
    '{count} people reacted to this message.many':
        '{count} особа је реаговало на ову поруку',
    '{count} people reacted to this message.other':
        '{count} особа је реаговало на ову поруку',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': 'Ова објава се свиђа {count} особа',
    '{count} people liked this post.one': 'Ова објава се свиђа {count} особи',
    '{count} people liked this post.two': 'Ова објава се свиђа {count} особе',
    '{count} people liked this post.few': 'Ова објава се свиђа {count} особе',
    '{count} people liked this post.many': 'Ова објава се свиђа {count} особа',
    '{count} people liked this post.other': 'Ова објава се свиђа {count} особа',
  },
  'sv': <String, String>{
    'likers.titleLikes': 'Gilla-markeringar',
    'likers.titleReactions': 'Reaktioner',
    'likers.tabAll': 'Alla',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Du',
    '{name}, reacted {emoji}': '{name}, reagerade med {emoji}',
    "Some people aren't shown.": 'Vissa personer visas inte.',
    'No one to show here.': 'Det finns ingen att visa här.',
    'You can hide your own likes in Settings → Privacy.':
        'Du kan dölja dina egna gilla-markeringar i Inställningar → Integritet.',
    'Likes loaded: {count}': 'Inlästa gilla-markeringar: {count}',
    'Reactions loaded: {count}': 'Inlästa reaktioner: {count}',
    'Open profile': 'Öppna profil',
    'See who liked is coming soon.': '”Se vem som gillade” kommer snart.',
    'This content is no longer available.':
        'Det här innehållet är inte längre tillgängligt.',
    'Too many requests. Try again in a minute.':
        'För många förfrågningar. Försök igen om en minut.',
    "Couldn't load this list. Try again.":
        'Det gick inte att läsa in listan. Försök igen.',
    'See who liked': 'Se vem som gillade',
    'See who reacted': 'Se vem som reagerade',
    'Likes · {count}': 'Gilla-markeringar · {count}',
    'See who liked. Likes: {count}':
        'Se vem som gillade. Gilla-markeringar: {count}',
    'See who reacted. Reactions: {count}':
        'Se vem som reagerade. Reaktioner: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Gillas av {names} och {count} till. Se vem som gillade.',
    'Liked by {names}. See who liked.':
        'Gillas av {names}. Se vem som gillade.',
    'Like comment. Likes: {count}':
        'Gilla kommentaren. Gilla-markeringar: {count}',
    'Unlike comment. Likes: {count}':
        'Sluta gilla kommentaren. Gilla-markeringar: {count}',
    'Who liked': 'Vem gillade',
    'Who liked. Likes: {count}': 'Vem gillade. Gilla-markeringar: {count}',
    "Couldn't update your like. Try again.":
        'Det gick inte att uppdatera din gilla-markering. Försök igen.',
    'Premium offer': 'Premium-erbjudande',
    'See who liked — a Premium feature':
        'Se vem som gillade — en Premium-funktion',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Med Premium ser du vilka som gillade ett Voice Moment, en Yeel eller en kommentar, eller som reagerade på ett servermeddelande. Antalet gilla-markeringar syns fortfarande för alla.',
    'Explore Premium': 'Utforska Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium går inte att köpa än. Det kommer snart.',
    'See who liked is included with Premium':
        '”Se vem som gillade” ingår i Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Märke, skimmer, integritetsinställningar, se vem som gillade och en måttlig skjuts i Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Se vem som gillade Voice Moments, Yeels, kommentarer och servermeddelanden',
    'Hide my likes': 'Dölj mina gilla-markeringar',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Du visas inte i YO Voices listor över vilka som gillat eller reagerat. Antalen ändras inte. Servermedlemmar får fortfarande dina reaktioner i kanaler ni delar.',
    "Couldn't update this setting. Try again.":
        'Det gick inte att ändra inställningen. Försök igen.',
    'Privacy': 'Integritet',
    '{count} people liked this Moment.zero':
        '{count} personer gillade detta Moment',
    '{count} people liked this Moment.one':
        '{count} person gillade detta Moment',
    '{count} people liked this Moment.two':
        '{count} personer gillade detta Moment',
    '{count} people liked this Moment.few':
        '{count} personer gillade detta Moment',
    '{count} people liked this Moment.many':
        '{count} personer gillade detta Moment',
    '{count} people liked this Moment.other':
        '{count} personer gillade detta Moment',
    '{count} people liked this Yeel.zero':
        '{count} personer gillade denna Yeel',
    '{count} people liked this Yeel.one': '{count} person gillade denna Yeel',
    '{count} people liked this Yeel.two': '{count} personer gillade denna Yeel',
    '{count} people liked this Yeel.few': '{count} personer gillade denna Yeel',
    '{count} people liked this Yeel.many':
        '{count} personer gillade denna Yeel',
    '{count} people liked this Yeel.other':
        '{count} personer gillade denna Yeel',
    '{count} people liked this comment.zero':
        '{count} personer gillade denna kommentar',
    '{count} people liked this comment.one':
        '{count} person gillade denna kommentar',
    '{count} people liked this comment.two':
        '{count} personer gillade denna kommentar',
    '{count} people liked this comment.few':
        '{count} personer gillade denna kommentar',
    '{count} people liked this comment.many':
        '{count} personer gillade denna kommentar',
    '{count} people liked this comment.other':
        '{count} personer gillade denna kommentar',
    '{count} people reacted to this message.zero':
        '{count} personer reagerade på detta meddelande',
    '{count} people reacted to this message.one':
        '{count} person reagerade på detta meddelande',
    '{count} people reacted to this message.two':
        '{count} personer reagerade på detta meddelande',
    '{count} people reacted to this message.few':
        '{count} personer reagerade på detta meddelande',
    '{count} people reacted to this message.many':
        '{count} personer reagerade på detta meddelande',
    '{count} people reacted to this message.other':
        '{count} personer reagerade på detta meddelande',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} personer gillade det här inlägget',
    '{count} people liked this post.one':
        '{count} person gillade det här inlägget',
    '{count} people liked this post.two':
        '{count} personer gillade det här inlägget',
    '{count} people liked this post.few':
        '{count} personer gillade det här inlägget',
    '{count} people liked this post.many':
        '{count} personer gillade det här inlägget',
    '{count} people liked this post.other':
        '{count} personer gillade det här inlägget',
  },
  'da': <String, String>{
    'likers.titleLikes': 'Synes godt om',
    'likers.titleReactions': 'Reaktioner',
    'likers.tabAll': 'Alle',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Dig',
    '{name}, reacted {emoji}': '{name}, reagerede med {emoji}',
    "Some people aren't shown.": 'Nogle personer vises ikke.',
    'No one to show here.': 'Der er ingen at vise her.',
    'You can hide your own likes in Settings → Privacy.':
        'Du kan skjule dine egne synes godt om-markeringer under Indstillinger → Privatliv.',
    'Likes loaded: {count}': 'Indlæste synes godt om: {count}',
    'Reactions loaded: {count}': 'Indlæste reaktioner: {count}',
    'Open profile': 'Åbn profil',
    'See who liked is coming soon.':
        '»Se, hvem der synes godt om« kommer snart.',
    'This content is no longer available.':
        'Dette indhold er ikke længere tilgængeligt.',
    'Too many requests. Try again in a minute.':
        'For mange forespørgsler. Prøv igen om et minut.',
    "Couldn't load this list. Try again.":
        'Listen kunne ikke indlæses. Prøv igen.',
    'See who liked': 'Se, hvem der synes godt om',
    'See who reacted': 'Se, hvem der reagerede',
    'Likes · {count}': 'Synes godt om · {count}',
    'See who liked. Likes: {count}':
        'Se, hvem der synes godt om. Synes godt om: {count}',
    'See who reacted. Reactions: {count}':
        'Se, hvem der reagerede. Reaktioner: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} og {count} andre synes godt om. Se, hvem der synes godt om.',
    'Liked by {names}. See who liked.':
        '{names} synes godt om. Se, hvem der synes godt om.',
    'Like comment. Likes: {count}':
        'Synes godt om kommentaren. Synes godt om: {count}',
    'Unlike comment. Likes: {count}':
        'Fjern synes godt om fra kommentaren. Synes godt om: {count}',
    'Who liked': 'Hvem synes godt om',
    'Who liked. Likes: {count}': 'Hvem synes godt om. Synes godt om: {count}',
    "Couldn't update your like. Try again.":
        'Din synes godt om kunne ikke opdateres. Prøv igen.',
    'Premium offer': 'Premium-tilbud',
    'See who liked — a Premium feature':
        'Se, hvem der synes godt om — en Premium-funktion',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Med Premium kan du se, hvem der synes godt om et Voice Moment, en Yeel eller en kommentar, eller hvem der reagerede på en serverbesked. Antallet af synes godt om er stadig synligt for alle.',
    'Explore Premium': 'Udforsk Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium kan ikke købes endnu. Det kommer snart.',
    'See who liked is included with Premium':
        '»Se, hvem der synes godt om« er inkluderet i Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Mærke, glimmer, privatlivsindstillinger, se, hvem der synes godt om, og et moderat løft i Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Se, hvem der synes godt om Voice Moments, Yeels, kommentarer og serverbeskeder',
    'Hide my likes': 'Skjul mine synes godt om-markeringer',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Du vises ikke på YO Voices lister over, hvem der synes godt om eller reagerede. Tallene ændrer sig ikke. Servermedlemmer modtager stadig dine reaktioner i kanaler, I deler.',
    "Couldn't update this setting. Try again.":
        'Indstillingen kunne ikke ændres. Prøv igen.',
    'Privacy': 'Privatliv',
    '{count} people liked this Moment.zero':
        '{count} personer synes godt om dette Moment',
    '{count} people liked this Moment.one':
        '{count} person synes godt om dette Moment',
    '{count} people liked this Moment.two':
        '{count} personer synes godt om dette Moment',
    '{count} people liked this Moment.few':
        '{count} personer synes godt om dette Moment',
    '{count} people liked this Moment.many':
        '{count} personer synes godt om dette Moment',
    '{count} people liked this Moment.other':
        '{count} personer synes godt om dette Moment',
    '{count} people liked this Yeel.zero':
        '{count} personer synes godt om denne Yeel',
    '{count} people liked this Yeel.one':
        '{count} person synes godt om denne Yeel',
    '{count} people liked this Yeel.two':
        '{count} personer synes godt om denne Yeel',
    '{count} people liked this Yeel.few':
        '{count} personer synes godt om denne Yeel',
    '{count} people liked this Yeel.many':
        '{count} personer synes godt om denne Yeel',
    '{count} people liked this Yeel.other':
        '{count} personer synes godt om denne Yeel',
    '{count} people liked this comment.zero':
        '{count} personer synes godt om denne kommentar',
    '{count} people liked this comment.one':
        '{count} person synes godt om denne kommentar',
    '{count} people liked this comment.two':
        '{count} personer synes godt om denne kommentar',
    '{count} people liked this comment.few':
        '{count} personer synes godt om denne kommentar',
    '{count} people liked this comment.many':
        '{count} personer synes godt om denne kommentar',
    '{count} people liked this comment.other':
        '{count} personer synes godt om denne kommentar',
    '{count} people reacted to this message.zero':
        '{count} personer reagerede på denne besked',
    '{count} people reacted to this message.one':
        '{count} person reagerede på denne besked',
    '{count} people reacted to this message.two':
        '{count} personer reagerede på denne besked',
    '{count} people reacted to this message.few':
        '{count} personer reagerede på denne besked',
    '{count} people reacted to this message.many':
        '{count} personer reagerede på denne besked',
    '{count} people reacted to this message.other':
        '{count} personer reagerede på denne besked',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} personer synes godt om dette opslag',
    '{count} people liked this post.one':
        '{count} person synes godt om dette opslag',
    '{count} people liked this post.two':
        '{count} personer synes godt om dette opslag',
    '{count} people liked this post.few':
        '{count} personer synes godt om dette opslag',
    '{count} people liked this post.many':
        '{count} personer synes godt om dette opslag',
    '{count} people liked this post.other':
        '{count} personer synes godt om dette opslag',
  },
  'nb': <String, String>{
    'likers.titleLikes': 'Likerklikk',
    'likers.titleReactions': 'Reaksjoner',
    'likers.tabAll': 'Alle',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Deg',
    '{name}, reacted {emoji}': '{name}, reagerte med {emoji}',
    "Some people aren't shown.": 'Noen personer vises ikke.',
    'No one to show here.': 'Det er ingen å vise her.',
    'You can hide your own likes in Settings → Privacy.':
        'Du kan skjule dine egne likerklikk under Innstillinger → Personvern.',
    'Likes loaded: {count}': 'Likerklikk lastet inn: {count}',
    'Reactions loaded: {count}': 'Reaksjoner lastet inn: {count}',
    'Open profile': 'Åpne profil',
    'See who liked is coming soon.': '«Se hvem som likte» kommer snart.',
    'This content is no longer available.':
        'Dette innholdet er ikke lenger tilgjengelig.',
    'Too many requests. Try again in a minute.':
        'For mange forespørsler. Prøv igjen om et minutt.',
    "Couldn't load this list. Try again.":
        'Kunne ikke laste inn listen. Prøv igjen.',
    'See who liked': 'Se hvem som likte',
    'See who reacted': 'Se hvem som reagerte',
    'Likes · {count}': 'Likerklikk · {count}',
    'See who liked. Likes: {count}': 'Se hvem som likte. Likerklikk: {count}',
    'See who reacted. Reactions: {count}':
        'Se hvem som reagerte. Reaksjoner: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Likt av {names} og {count} andre. Se hvem som likte.',
    'Liked by {names}. See who liked.': 'Likt av {names}. Se hvem som likte.',
    'Like comment. Likes: {count}': 'Lik kommentaren. Likerklikk: {count}',
    'Unlike comment. Likes: {count}':
        'Fjern likerklikket fra kommentaren. Likerklikk: {count}',
    'Who liked': 'Hvem likte',
    'Who liked. Likes: {count}': 'Hvem likte. Likerklikk: {count}',
    "Couldn't update your like. Try again.":
        'Kunne ikke oppdatere likerklikket ditt. Prøv igjen.',
    'Premium offer': 'Premium-tilbud',
    'See who liked — a Premium feature':
        'Se hvem som likte — en Premium-funksjon',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Med Premium ser du hvem som likte et Voice Moment, en Yeel eller en kommentar, eller som reagerte på en servermelding. Antall likerklikk er fortsatt synlig for alle.',
    'Explore Premium': 'Utforsk Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium kan ikke kjøpes ennå. Det kommer snart.',
    'See who liked is included with Premium':
        '«Se hvem som likte» er inkludert i Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Merke, glimt, personverninnstillinger, se hvem som likte og et moderat løft i Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Se hvem som likte Voice Moments, Yeels, kommentarer og servermeldinger',
    'Hide my likes': 'Skjul likerklikkene mine',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Du vises ikke i YO Voice-listene over hvem som likte eller reagerte. Tallene endres ikke. Servermedlemmer mottar fortsatt reaksjonene dine i kanaler dere deler.',
    "Couldn't update this setting. Try again.":
        'Kunne ikke endre denne innstillingen. Prøv igjen.',
    'Privacy': 'Personvern',
    '{count} people liked this Moment.zero':
        '{count} personer likte dette Momentet',
    '{count} people liked this Moment.one':
        '{count} person likte dette Momentet',
    '{count} people liked this Moment.two':
        '{count} personer likte dette Momentet',
    '{count} people liked this Moment.few':
        '{count} personer likte dette Momentet',
    '{count} people liked this Moment.many':
        '{count} personer likte dette Momentet',
    '{count} people liked this Moment.other':
        '{count} personer likte dette Momentet',
    '{count} people liked this Yeel.zero':
        '{count} personer likte denne Yeelen',
    '{count} people liked this Yeel.one': '{count} person likte denne Yeelen',
    '{count} people liked this Yeel.two': '{count} personer likte denne Yeelen',
    '{count} people liked this Yeel.few': '{count} personer likte denne Yeelen',
    '{count} people liked this Yeel.many':
        '{count} personer likte denne Yeelen',
    '{count} people liked this Yeel.other':
        '{count} personer likte denne Yeelen',
    '{count} people liked this comment.zero':
        '{count} personer likte denne kommentaren',
    '{count} people liked this comment.one':
        '{count} person likte denne kommentaren',
    '{count} people liked this comment.two':
        '{count} personer likte denne kommentaren',
    '{count} people liked this comment.few':
        '{count} personer likte denne kommentaren',
    '{count} people liked this comment.many':
        '{count} personer likte denne kommentaren',
    '{count} people liked this comment.other':
        '{count} personer likte denne kommentaren',
    '{count} people reacted to this message.zero':
        '{count} personer reagerte på denne meldingen',
    '{count} people reacted to this message.one':
        '{count} person reagerte på denne meldingen',
    '{count} people reacted to this message.two':
        '{count} personer reagerte på denne meldingen',
    '{count} people reacted to this message.few':
        '{count} personer reagerte på denne meldingen',
    '{count} people reacted to this message.many':
        '{count} personer reagerte på denne meldingen',
    '{count} people reacted to this message.other':
        '{count} personer reagerte på denne meldingen',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} personer likte dette innlegget',
    '{count} people liked this post.one':
        '{count} person likte dette innlegget',
    '{count} people liked this post.two':
        '{count} personer likte dette innlegget',
    '{count} people liked this post.few':
        '{count} personer likte dette innlegget',
    '{count} people liked this post.many':
        '{count} personer likte dette innlegget',
    '{count} people liked this post.other':
        '{count} personer likte dette innlegget',
  },
  'fi': <String, String>{
    'likers.titleLikes': 'Tykkäykset',
    'likers.titleReactions': 'Reaktiot',
    'likers.tabAll': 'Kaikki',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Sinä',
    '{name}, reacted {emoji}': '{name}, reagoi {emoji}',
    "Some people aren't shown.": 'Kaikkia henkilöitä ei näytetä.',
    'No one to show here.': 'Täällä ei ole ketään näytettävää.',
    'You can hide your own likes in Settings → Privacy.':
        'Voit piilottaa omat tykkäyksesi kohdassa Asetukset → Yksityisyys.',
    'Likes loaded: {count}': 'Tykkäyksiä ladattu: {count}',
    'Reactions loaded: {count}': 'Reaktioita ladattu: {count}',
    'Open profile': 'Avaa profiili',
    'See who liked is coming soon.': '”Katso, kuka tykkäsi” on tulossa pian.',
    'This content is no longer available.':
        'Tämä sisältö ei ole enää saatavilla.',
    'Too many requests. Try again in a minute.':
        'Liikaa pyyntöjä. Yritä uudelleen minuutin kuluttua.',
    "Couldn't load this list. Try again.":
        'Luettelon lataaminen epäonnistui. Yritä uudelleen.',
    'See who liked': 'Katso, kuka tykkäsi',
    'See who reacted': 'Katso, kuka reagoi',
    'Likes · {count}': 'Tykkäykset · {count}',
    'See who liked. Likes: {count}': 'Katso, kuka tykkäsi. Tykkäyksiä: {count}',
    'See who reacted. Reactions: {count}':
        'Katso, kuka reagoi. Reaktioita: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Tykkääjät: {names} ja {count} muuta. Katso, kuka tykkäsi.',
    'Liked by {names}. See who liked.':
        'Tykkääjät: {names}. Katso, kuka tykkäsi.',
    'Like comment. Likes: {count}': 'Tykkää kommentista. Tykkäyksiä: {count}',
    'Unlike comment. Likes: {count}':
        'Peru kommentin tykkäys. Tykkäyksiä: {count}',
    'Who liked': 'Kuka tykkäsi',
    'Who liked. Likes: {count}': 'Kuka tykkäsi. Tykkäyksiä: {count}',
    "Couldn't update your like. Try again.":
        'Tykkäyksen päivittäminen epäonnistui. Yritä uudelleen.',
    'Premium offer': 'Premium-tarjous',
    'See who liked — a Premium feature':
        'Katso, kuka tykkäsi — Premium-ominaisuus',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premiumilla näet, ketkä tykkäsivät Voice Momentista, Yeelistä tai kommentista tai reagoivat palvelimen viestiin. Tykkäysten määrä näkyy edelleen kaikille.',
    'Explore Premium': 'Tutustu Premiumiin',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premiumia ei voi vielä ostaa. Se on tulossa pian.',
    'See who liked is included with Premium':
        '”Katso, kuka tykkäsi” sisältyy Premiumiin',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Merkki, hohto, yksityisyysasetukset, tykkääjien näkeminen ja maltillinen näkyvyysetu Yeelsissä',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Katso tykkääjät: Voice Moments, Yeels, kommentit ja palvelinviestit',
    'Hide my likes': 'Piilota tykkäykseni',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Et näy YO Voicen luetteloissa, joissa näkyy, kuka tykkäsi tai reagoi. Määrät eivät muutu. Palvelimen jäsenet saavat edelleen reaktiosi yhteisillä kanavilla.',
    "Couldn't update this setting. Try again.":
        'Asetuksen muuttaminen epäonnistui. Yritä uudelleen.',
    'Privacy': 'Yksityisyys',
    '{count} people liked this Moment.zero':
        '{count} henkilöä tykkäsi tästä Momentista',
    '{count} people liked this Moment.one':
        '{count} henkilö tykkäsi tästä Momentista',
    '{count} people liked this Moment.two':
        '{count} henkilöä tykkäsi tästä Momentista',
    '{count} people liked this Moment.few':
        '{count} henkilöä tykkäsi tästä Momentista',
    '{count} people liked this Moment.many':
        '{count} henkilöä tykkäsi tästä Momentista',
    '{count} people liked this Moment.other':
        '{count} henkilöä tykkäsi tästä Momentista',
    '{count} people liked this Yeel.zero':
        '{count} henkilöä tykkäsi tästä Yeelistä',
    '{count} people liked this Yeel.one':
        '{count} henkilö tykkäsi tästä Yeelistä',
    '{count} people liked this Yeel.two':
        '{count} henkilöä tykkäsi tästä Yeelistä',
    '{count} people liked this Yeel.few':
        '{count} henkilöä tykkäsi tästä Yeelistä',
    '{count} people liked this Yeel.many':
        '{count} henkilöä tykkäsi tästä Yeelistä',
    '{count} people liked this Yeel.other':
        '{count} henkilöä tykkäsi tästä Yeelistä',
    '{count} people liked this comment.zero':
        '{count} henkilöä tykkäsi tästä kommentista',
    '{count} people liked this comment.one':
        '{count} henkilö tykkäsi tästä kommentista',
    '{count} people liked this comment.two':
        '{count} henkilöä tykkäsi tästä kommentista',
    '{count} people liked this comment.few':
        '{count} henkilöä tykkäsi tästä kommentista',
    '{count} people liked this comment.many':
        '{count} henkilöä tykkäsi tästä kommentista',
    '{count} people liked this comment.other':
        '{count} henkilöä tykkäsi tästä kommentista',
    '{count} people reacted to this message.zero':
        '{count} henkilöä reagoi tähän viestiin',
    '{count} people reacted to this message.one':
        '{count} henkilö reagoi tähän viestiin',
    '{count} people reacted to this message.two':
        '{count} henkilöä reagoi tähän viestiin',
    '{count} people reacted to this message.few':
        '{count} henkilöä reagoi tähän viestiin',
    '{count} people reacted to this message.many':
        '{count} henkilöä reagoi tähän viestiin',
    '{count} people reacted to this message.other':
        '{count} henkilöä reagoi tähän viestiin',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} ihmistä tykkäsi tästä julkaisusta',
    '{count} people liked this post.one':
        '{count} ihminen tykkäsi tästä julkaisusta',
    '{count} people liked this post.two':
        '{count} ihmistä tykkäsi tästä julkaisusta',
    '{count} people liked this post.few':
        '{count} ihmistä tykkäsi tästä julkaisusta',
    '{count} people liked this post.many':
        '{count} ihmistä tykkäsi tästä julkaisusta',
    '{count} people liked this post.other':
        '{count} ihmistä tykkäsi tästä julkaisusta',
  },
  'lt': <String, String>{
    'likers.titleLikes': 'Patiktukai',
    'likers.titleReactions': 'Reakcijos',
    'likers.tabAll': 'Visos',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tu',
    '{name}, reacted {emoji}': '{name}, sureagavo {emoji}',
    "Some people aren't shown.": 'Kai kurie žmonės nerodomi.',
    'No one to show here.': 'Čia nėra ko rodyti.',
    'You can hide your own likes in Settings → Privacy.':
        'Savo patiktukus gali paslėpti skiltyje Nustatymai → Privatumas.',
    'Likes loaded: {count}': 'Įkelta patiktukų: {count}',
    'Reactions loaded: {count}': 'Įkelta reakcijų: {count}',
    'Open profile': 'Atidaryti profilį',
    'See who liked is coming soon.':
        'Funkcija „Žiūrėti, kam patiko“ jau netrukus.',
    'This content is no longer available.': 'Šis turinys nebepasiekiamas.',
    'Too many requests. Try again in a minute.':
        'Per daug užklausų. Bandyk dar kartą po minutės.',
    "Couldn't load this list. Try again.":
        'Nepavyko įkelti sąrašo. Bandyk dar kartą.',
    'See who liked': 'Žiūrėti, kam patiko',
    'See who reacted': 'Žiūrėti, kas sureagavo',
    'Likes · {count}': 'Patiktukai · {count}',
    'See who liked. Likes: {count}': 'Žiūrėti, kam patiko. Patiktukų: {count}',
    'See who reacted. Reactions: {count}':
        'Žiūrėti, kas sureagavo. Reakcijų: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Patiko: {names} ir dar {count}. Žiūrėti, kam patiko.',
    'Liked by {names}. See who liked.': 'Patiko: {names}. Žiūrėti, kam patiko.',
    'Like comment. Likes: {count}':
        'Pažymėti, kad komentaras patinka. Patiktukų: {count}',
    'Unlike comment. Likes: {count}':
        'Atšaukti komentaro patiktuką. Patiktukų: {count}',
    'Who liked': 'Kam patiko',
    'Who liked. Likes: {count}': 'Kam patiko. Patiktukų: {count}',
    "Couldn't update your like. Try again.":
        'Nepavyko atnaujinti patiktuko. Bandyk dar kartą.',
    'Premium offer': 'Premium pasiūlymas',
    'See who liked — a Premium feature':
        'Žiūrėti, kam patiko — Premium funkcija',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Su Premium matai žmones, kuriems patiko Voice Moment, Yeel ar komentaras arba kurie sureagavo į serverio žinutę. Patiktukų skaičius ir toliau matomas visiems.',
    'Explore Premium': 'Sužinok apie Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium dar negalima įsigyti. Jau netrukus.',
    'See who liked is included with Premium':
        'Funkcija „Žiūrėti, kam patiko“ įtraukta į Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Ženklelis, žvilgesys, privatumo nustatymai, galimybė matyti, kam patiko, ir saikingas iškėlimas Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Matyk, kam patiko Voice Moments, Yeels, komentarai ir serverių žinutės',
    'Hide my likes': 'Slėpti mano patiktukus',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Nebūsi rodomas YO Voice sąrašuose, kuriuose matyti, kas paspaudė „patinka“ ar sureagavo. Skaičiai nesikeičia. Serverio nariai ir toliau gauna tavo reakcijas bendruose kanaluose.',
    "Couldn't update this setting. Try again.":
        'Nepavyko pakeisti šio nustatymo. Bandyk dar kartą.',
    'Privacy': 'Privatumas',
    '{count} people liked this Moment.zero':
        '{count} žmonių pažymėjo, kad šis Moment patinka',
    '{count} people liked this Moment.one':
        '{count} žmogus pažymėjo, kad šis Moment patinka',
    '{count} people liked this Moment.two':
        '{count} žmonės pažymėjo, kad šis Moment patinka',
    '{count} people liked this Moment.few':
        '{count} žmonės pažymėjo, kad šis Moment patinka',
    '{count} people liked this Moment.many':
        '{count} žmogaus pažymėjo, kad šis Moment patinka',
    '{count} people liked this Moment.other':
        '{count} žmonių pažymėjo, kad šis Moment patinka',
    '{count} people liked this Yeel.zero':
        '{count} žmonių pažymėjo, kad šis Yeel patinka',
    '{count} people liked this Yeel.one':
        '{count} žmogus pažymėjo, kad šis Yeel patinka',
    '{count} people liked this Yeel.two':
        '{count} žmonės pažymėjo, kad šis Yeel patinka',
    '{count} people liked this Yeel.few':
        '{count} žmonės pažymėjo, kad šis Yeel patinka',
    '{count} people liked this Yeel.many':
        '{count} žmogaus pažymėjo, kad šis Yeel patinka',
    '{count} people liked this Yeel.other':
        '{count} žmonių pažymėjo, kad šis Yeel patinka',
    '{count} people liked this comment.zero':
        '{count} žmonių pažymėjo, kad šis komentaras patinka',
    '{count} people liked this comment.one':
        '{count} žmogus pažymėjo, kad šis komentaras patinka',
    '{count} people liked this comment.two':
        '{count} žmonės pažymėjo, kad šis komentaras patinka',
    '{count} people liked this comment.few':
        '{count} žmonės pažymėjo, kad šis komentaras patinka',
    '{count} people liked this comment.many':
        '{count} žmogaus pažymėjo, kad šis komentaras patinka',
    '{count} people liked this comment.other':
        '{count} žmonių pažymėjo, kad šis komentaras patinka',
    '{count} people reacted to this message.zero':
        '{count} žmonių sureagavo į šią žinutę',
    '{count} people reacted to this message.one':
        '{count} žmogus sureagavo į šią žinutę',
    '{count} people reacted to this message.two':
        '{count} žmonės sureagavo į šią žinutę',
    '{count} people reacted to this message.few':
        '{count} žmonės sureagavo į šią žinutę',
    '{count} people reacted to this message.many':
        '{count} žmogaus sureagavo į šią žinutę',
    '{count} people reacted to this message.other':
        '{count} žmonių sureagavo į šią žinutę',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': 'Šis įrašas patiko {count} žmonių',
    '{count} people liked this post.one': 'Šis įrašas patiko {count} žmogui',
    '{count} people liked this post.two': 'Šis įrašas patiko {count} žmonėms',
    '{count} people liked this post.few': 'Šis įrašas patiko {count} žmonėms',
    '{count} people liked this post.many': 'Šis įrašas patiko {count} žmogaus',
    '{count} people liked this post.other': 'Šis įrašas patiko {count} žmonių',
  },
  'lv': <String, String>{
    'likers.titleLikes': 'Patīk atzīmes',
    'likers.titleReactions': 'Reakcijas',
    'likers.tabAll': 'Visas',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Tu',
    '{name}, reacted {emoji}': '{name}, reaģēja ar {emoji}',
    "Some people aren't shown.": 'Dažas personas netiek rādītas.',
    'No one to show here.': 'Šeit nav neviena, ko parādīt.',
    'You can hide your own likes in Settings → Privacy.':
        'Savas “patīk” atzīmes vari paslēpt sadaļā Iestatījumi → Privātums.',
    'Likes loaded: {count}': 'Ielādētas “patīk” atzīmes: {count}',
    'Reactions loaded: {count}': 'Ielādētas reakcijas: {count}',
    'Open profile': 'Atvērt profilu',
    'See who liked is coming soon.':
        'Funkcija “Skatīt, kam patika” drīzumā būs pieejama.',
    'This content is no longer available.': 'Šis saturs vairs nav pieejams.',
    'Too many requests. Try again in a minute.':
        'Pārāk daudz pieprasījumu. Mēģini vēlreiz pēc minūtes.',
    "Couldn't load this list. Try again.":
        'Neizdevās ielādēt sarakstu. Mēģini vēlreiz.',
    'See who liked': 'Skatīt, kam patika',
    'See who reacted': 'Skatīt, kas reaģēja',
    'Likes · {count}': 'Patīk atzīmes · {count}',
    'See who liked. Likes: {count}':
        'Skatīt, kam patika. Patīk atzīmes: {count}',
    'See who reacted. Reactions: {count}':
        'Skatīt, kas reaģēja. Reakcijas: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Patika: {names} un vēl {count}. Skatīt, kam patika.',
    'Liked by {names}. See who liked.': 'Patika: {names}. Skatīt, kam patika.',
    'Like comment. Likes: {count}':
        'Atzīmēt, ka komentārs patīk. Patīk atzīmes: {count}',
    'Unlike comment. Likes: {count}':
        'Noņemt komentāra “patīk” atzīmi. Patīk atzīmes: {count}',
    'Who liked': 'Kam patika',
    'Who liked. Likes: {count}': 'Kam patika. Patīk atzīmes: {count}',
    "Couldn't update your like. Try again.":
        'Neizdevās atjaunināt tavu “patīk” atzīmi. Mēģini vēlreiz.',
    'Premium offer': 'Premium piedāvājums',
    'See who liked — a Premium feature':
        'Skatīt, kam patika — Premium funkcija',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Ar Premium vari redzēt cilvēkus, kuriem patika Voice Moment, Yeel vai komentārs vai kuri reaģēja uz servera ziņu. “Patīk” atzīmju skaits joprojām ir redzams visiem.',
    'Explore Premium': 'Iepazīsti Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium vēl nevar iegādāties. Drīzumā.',
    'See who liked is included with Premium':
        'Funkcija “Skatīt, kam patika” ir iekļauta Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Nozīmīte, mirdzums, privātuma iestatījumi, iespēja redzēt, kam patika, un mērens izcēlums Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Skati, kam patika Voice Moments, Yeels, komentāri un serveru ziņas',
    'Hide my likes': 'Paslēpt manas “patīk” atzīmes',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Tu netiksi rādīts YO Voice sarakstos, kuros redzams, kam patika vai kas reaģēja. Skaitļi nemainās. Servera dalībnieki joprojām saņem tavas reakcijas kopīgajos kanālos.',
    "Couldn't update this setting. Try again.":
        'Neizdevās mainīt šo iestatījumu. Mēģini vēlreiz.',
    'Privacy': 'Privātums',
    '{count} people liked this Moment.zero':
        '{count} cilvēku atzīmēja, ka šis Moment patīk',
    '{count} people liked this Moment.one':
        '{count} cilvēks atzīmēja, ka šis Moment patīk',
    '{count} people liked this Moment.two':
        '{count} cilvēki atzīmēja, ka šis Moment patīk',
    '{count} people liked this Moment.few':
        '{count} cilvēki atzīmēja, ka šis Moment patīk',
    '{count} people liked this Moment.many':
        '{count} cilvēki atzīmēja, ka šis Moment patīk',
    '{count} people liked this Moment.other':
        '{count} cilvēki atzīmēja, ka šis Moment patīk',
    '{count} people liked this Yeel.zero':
        '{count} cilvēku atzīmēja, ka šis Yeel patīk',
    '{count} people liked this Yeel.one':
        '{count} cilvēks atzīmēja, ka šis Yeel patīk',
    '{count} people liked this Yeel.two':
        '{count} cilvēki atzīmēja, ka šis Yeel patīk',
    '{count} people liked this Yeel.few':
        '{count} cilvēki atzīmēja, ka šis Yeel patīk',
    '{count} people liked this Yeel.many':
        '{count} cilvēki atzīmēja, ka šis Yeel patīk',
    '{count} people liked this Yeel.other':
        '{count} cilvēki atzīmēja, ka šis Yeel patīk',
    '{count} people liked this comment.zero':
        '{count} cilvēku atzīmēja, ka šis komentārs patīk',
    '{count} people liked this comment.one':
        '{count} cilvēks atzīmēja, ka šis komentārs patīk',
    '{count} people liked this comment.two':
        '{count} cilvēki atzīmēja, ka šis komentārs patīk',
    '{count} people liked this comment.few':
        '{count} cilvēki atzīmēja, ka šis komentārs patīk',
    '{count} people liked this comment.many':
        '{count} cilvēki atzīmēja, ka šis komentārs patīk',
    '{count} people liked this comment.other':
        '{count} cilvēki atzīmēja, ka šis komentārs patīk',
    '{count} people reacted to this message.zero':
        '{count} cilvēku reaģēja uz šo ziņu',
    '{count} people reacted to this message.one':
        '{count} cilvēks reaģēja uz šo ziņu',
    '{count} people reacted to this message.two':
        '{count} cilvēki reaģēja uz šo ziņu',
    '{count} people reacted to this message.few':
        '{count} cilvēki reaģēja uz šo ziņu',
    '{count} people reacted to this message.many':
        '{count} cilvēki reaģēja uz šo ziņu',
    '{count} people reacted to this message.other':
        '{count} cilvēki reaģēja uz šo ziņu',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} cilvēku atzīmēja, ka šī ziņa patīk',
    '{count} people liked this post.one':
        '{count} cilvēks atzīmēja, ka šī ziņa patīk',
    '{count} people liked this post.two':
        '{count} cilvēki atzīmēja, ka šī ziņa patīk',
    '{count} people liked this post.few':
        '{count} cilvēki atzīmēja, ka šī ziņa patīk',
    '{count} people liked this post.many':
        '{count} cilvēki atzīmēja, ka šī ziņa patīk',
    '{count} people liked this post.other':
        '{count} cilvēki atzīmēja, ka šī ziņa patīk',
  },
  'et': <String, String>{
    'likers.titleLikes': 'Meeldimised',
    'likers.titleReactions': 'Reaktsioonid',
    'likers.tabAll': 'Kõik',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Sina',
    '{name}, reacted {emoji}': '{name}, reageeris: {emoji}',
    "Some people aren't shown.": 'Kõiki inimesi ei kuvata.',
    'No one to show here.': 'Siin pole kedagi näidata.',
    'You can hide your own likes in Settings → Privacy.':
        'Oma meeldimisi saad peita jaotises Seaded → Privaatsus.',
    'Likes loaded: {count}': 'Laaditud meeldimisi: {count}',
    'Reactions loaded: {count}': 'Laaditud reaktsioone: {count}',
    'Open profile': 'Ava profiil',
    'See who liked is coming soon.': '„Vaata, kellele meeldis“ tuleb peagi.',
    'This content is no longer available.': 'See sisu pole enam saadaval.',
    'Too many requests. Try again in a minute.':
        'Liiga palju päringuid. Proovi minuti pärast uuesti.',
    "Couldn't load this list. Try again.":
        'Loendit ei saanud laadida. Proovi uuesti.',
    'See who liked': 'Vaata, kellele meeldis',
    'See who reacted': 'Vaata, kes reageeris',
    'Likes · {count}': 'Meeldimised · {count}',
    'See who liked. Likes: {count}':
        'Vaata, kellele meeldis. Meeldimisi: {count}',
    'See who reacted. Reactions: {count}':
        'Vaata, kes reageeris. Reaktsioone: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Meeldis: {names} ja veel {count}. Vaata, kellele meeldis.',
    'Liked by {names}. See who liked.':
        'Meeldis: {names}. Vaata, kellele meeldis.',
    'Like comment. Likes: {count}':
        'Märgi kommentaar meeldivaks. Meeldimisi: {count}',
    'Unlike comment. Likes: {count}':
        'Eemalda kommentaari meeldimine. Meeldimisi: {count}',
    'Who liked': 'Kellele meeldis',
    'Who liked. Likes: {count}': 'Kellele meeldis. Meeldimisi: {count}',
    "Couldn't update your like. Try again.":
        'Meeldimist ei saanud uuendada. Proovi uuesti.',
    'Premium offer': 'Premium-pakkumine',
    'See who liked — a Premium feature':
        'Vaata, kellele meeldis — Premium-funktsioon',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premiumiga näed inimesi, kellele meeldis Voice Moment, Yeel või kommentaar või kes reageerisid serveri sõnumile. Meeldimiste arv jääb kõigile nähtavaks.',
    'Explore Premium': 'Avasta Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premiumi ei saa veel osta. See tuleb peagi.',
    'See who liked is included with Premium':
        '„Vaata, kellele meeldis“ kuulub Premiumi',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Märk, sära, privaatsusseaded, meeldijate vaatamine ja mõõdukas esiletõste Yeelsis',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Vaata, kellele meeldisid Voice Moments, Yeels, kommentaarid ja serverisõnumid',
    'Hide my likes': 'Peida minu meeldimised',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Sind ei kuvata YO Voice’i loendites, mis näitavad, kellele midagi meeldis või kes reageeris. Arvud ei muutu. Serveri liikmed saavad sinu reaktsioonid ühistes kanalites endiselt kätte.',
    "Couldn't update this setting. Try again.":
        'Seda seadet ei saanud muuta. Proovi uuesti.',
    'Privacy': 'Privaatsus',
    '{count} people liked this Moment.zero':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Moment.one':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Moment.two':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Moment.few':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Moment.many':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Moment.other':
        '{count} inimesele meeldis see Moment',
    '{count} people liked this Yeel.zero': '{count} inimesele meeldis see Yeel',
    '{count} people liked this Yeel.one': '{count} inimesele meeldis see Yeel',
    '{count} people liked this Yeel.two': '{count} inimesele meeldis see Yeel',
    '{count} people liked this Yeel.few': '{count} inimesele meeldis see Yeel',
    '{count} people liked this Yeel.many': '{count} inimesele meeldis see Yeel',
    '{count} people liked this Yeel.other':
        '{count} inimesele meeldis see Yeel',
    '{count} people liked this comment.zero':
        '{count} inimesele meeldis see kommentaar',
    '{count} people liked this comment.one':
        '{count} inimesele meeldis see kommentaar',
    '{count} people liked this comment.two':
        '{count} inimesele meeldis see kommentaar',
    '{count} people liked this comment.few':
        '{count} inimesele meeldis see kommentaar',
    '{count} people liked this comment.many':
        '{count} inimesele meeldis see kommentaar',
    '{count} people liked this comment.other':
        '{count} inimesele meeldis see kommentaar',
    '{count} people reacted to this message.zero':
        '{count} inimest reageerisid sellele sõnumile',
    '{count} people reacted to this message.one':
        '{count} inimene reageeris sellele sõnumile',
    '{count} people reacted to this message.two':
        '{count} inimest reageerisid sellele sõnumile',
    '{count} people reacted to this message.few':
        '{count} inimest reageerisid sellele sõnumile',
    '{count} people reacted to this message.many':
        '{count} inimest reageerisid sellele sõnumile',
    '{count} people reacted to this message.other':
        '{count} inimest reageerisid sellele sõnumile',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        'See postitus meeldis {count} inimesele',
    '{count} people liked this post.one':
        'See postitus meeldis {count} inimesele',
    '{count} people liked this post.two':
        'See postitus meeldis {count} inimesele',
    '{count} people liked this post.few':
        'See postitus meeldis {count} inimesele',
    '{count} people liked this post.many':
        'See postitus meeldis {count} inimesele',
    '{count} people liked this post.other':
        'See postitus meeldis {count} inimesele',
  },
  'id': <String, String>{
    'likers.titleLikes': 'Suka',
    'likers.titleReactions': 'Reaksi',
    'likers.tabAll': 'Semua',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Kamu',
    '{name}, reacted {emoji}': '{name}, bereaksi {emoji}',
    "Some people aren't shown.": 'Beberapa orang tidak ditampilkan.',
    'No one to show here.': 'Tidak ada yang bisa ditampilkan di sini.',
    'You can hide your own likes in Settings → Privacy.':
        'Kamu bisa menyembunyikan suka milikmu di Pengaturan → Privasi.',
    'Likes loaded: {count}': 'Suka dimuat: {count}',
    'Reactions loaded: {count}': 'Reaksi dimuat: {count}',
    'Open profile': 'Buka profil',
    'See who liked is coming soon.':
        '“Lihat siapa yang menyukai” segera hadir.',
    'This content is no longer available.': 'Konten ini sudah tidak tersedia.',
    'Too many requests. Try again in a minute.':
        'Terlalu banyak permintaan. Coba lagi dalam satu menit.',
    "Couldn't load this list. Try again.":
        'Tidak dapat memuat daftar ini. Coba lagi.',
    'See who liked': 'Lihat siapa yang menyukai',
    'See who reacted': 'Lihat siapa yang bereaksi',
    'Likes · {count}': 'Suka · {count}',
    'See who liked. Likes: {count}': 'Lihat siapa yang menyukai. Suka: {count}',
    'See who reacted. Reactions: {count}':
        'Lihat siapa yang bereaksi. Reaksi: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Disukai oleh {names} dan {count} lainnya. Lihat siapa yang menyukai.',
    'Liked by {names}. See who liked.':
        'Disukai oleh {names}. Lihat siapa yang menyukai.',
    'Like comment. Likes: {count}': 'Sukai komentar. Suka: {count}',
    'Unlike comment. Likes: {count}': 'Batal menyukai komentar. Suka: {count}',
    'Who liked': 'Siapa yang menyukai',
    'Who liked. Likes: {count}': 'Siapa yang menyukai. Suka: {count}',
    "Couldn't update your like. Try again.":
        'Tidak dapat memperbarui suka kamu. Coba lagi.',
    'Premium offer': 'Penawaran Premium',
    'See who liked — a Premium feature':
        'Lihat siapa yang menyukai — fitur Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Dengan Premium, kamu bisa melihat orang yang menyukai Voice Moment, Yeel, atau komentar, atau yang bereaksi pada pesan server. Jumlah suka tetap terlihat oleh semua orang.',
    'Explore Premium': 'Jelajahi Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium belum bisa dibeli. Segera hadir.',
    'See who liked is included with Premium':
        '“Lihat siapa yang menyukai” termasuk dalam Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Lencana, kilau, kontrol privasi, lihat siapa yang menyukai, dan dorongan moderat di Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Lihat siapa yang menyukai Voice Moments, Yeels, komentar, dan pesan server',
    'Hide my likes': 'Sembunyikan suka saya',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Kamu tidak akan muncul di daftar YO Voice tentang siapa yang menyukai atau bereaksi. Jumlahnya tidak berubah. Anggota server tetap menerima reaksimu di saluran yang kalian ikuti bersama.',
    "Couldn't update this setting. Try again.":
        'Tidak dapat mengubah pengaturan ini. Coba lagi.',
    'Privacy': 'Privasi',
    '{count} people liked this Moment.zero':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.one': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.two': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.few': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.many':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.other':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Yeel.zero': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.one': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.two': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.few': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.many': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.other': '{count} orang menyukai Yeel ini',
    '{count} people liked this comment.zero':
        '{count} orang menyukai komentar ini',
    '{count} people liked this comment.one':
        '{count} orang menyukai komentar ini',
    '{count} people liked this comment.two':
        '{count} orang menyukai komentar ini',
    '{count} people liked this comment.few':
        '{count} orang menyukai komentar ini',
    '{count} people liked this comment.many':
        '{count} orang menyukai komentar ini',
    '{count} people liked this comment.other':
        '{count} orang menyukai komentar ini',
    '{count} people reacted to this message.zero':
        '{count} orang bereaksi pada pesan ini',
    '{count} people reacted to this message.one':
        '{count} orang bereaksi pada pesan ini',
    '{count} people reacted to this message.two':
        '{count} orang bereaksi pada pesan ini',
    '{count} people reacted to this message.few':
        '{count} orang bereaksi pada pesan ini',
    '{count} people reacted to this message.many':
        '{count} orang bereaksi pada pesan ini',
    '{count} people reacted to this message.other':
        '{count} orang bereaksi pada pesan ini',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} orang menyukai postingan ini',
    '{count} people liked this post.one':
        '{count} orang menyukai postingan ini',
    '{count} people liked this post.two':
        '{count} orang menyukai postingan ini',
    '{count} people liked this post.few':
        '{count} orang menyukai postingan ini',
    '{count} people liked this post.many':
        '{count} orang menyukai postingan ini',
    '{count} people liked this post.other':
        '{count} orang menyukai postingan ini',
  },
  'vi': <String, String>{
    'likers.titleLikes': 'Lượt thích',
    'likers.titleReactions': 'Cảm xúc',
    'likers.tabAll': 'Tất cả',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Bạn',
    '{name}, reacted {emoji}': '{name}, đã bày tỏ cảm xúc {emoji}',
    "Some people aren't shown.": 'Một số người không được hiển thị.',
    'No one to show here.': 'Không có ai để hiển thị ở đây.',
    'You can hide your own likes in Settings → Privacy.':
        'Bạn có thể ẩn lượt thích của mình trong Cài đặt → Quyền riêng tư.',
    'Likes loaded: {count}': 'Đã tải lượt thích: {count}',
    'Reactions loaded: {count}': 'Đã tải cảm xúc: {count}',
    'Open profile': 'Mở hồ sơ',
    'See who liked is coming soon.': 'Tính năng “Xem ai đã thích” sắp ra mắt.',
    'This content is no longer available.': 'Nội dung này không còn khả dụng.',
    'Too many requests. Try again in a minute.':
        'Quá nhiều yêu cầu. Hãy thử lại sau một phút.',
    "Couldn't load this list. Try again.":
        'Không thể tải danh sách này. Hãy thử lại.',
    'See who liked': 'Xem ai đã thích',
    'See who reacted': 'Xem ai đã bày tỏ cảm xúc',
    'Likes · {count}': 'Lượt thích · {count}',
    'See who liked. Likes: {count}': 'Xem ai đã thích. Lượt thích: {count}',
    'See who reacted. Reactions: {count}':
        'Xem ai đã bày tỏ cảm xúc. Cảm xúc: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} và {count} người khác đã thích. Xem ai đã thích.',
    'Liked by {names}. See who liked.': '{names} đã thích. Xem ai đã thích.',
    'Like comment. Likes: {count}': 'Thích bình luận. Lượt thích: {count}',
    'Unlike comment. Likes: {count}': 'Bỏ thích bình luận. Lượt thích: {count}',
    'Who liked': 'Ai đã thích',
    'Who liked. Likes: {count}': 'Ai đã thích. Lượt thích: {count}',
    "Couldn't update your like. Try again.":
        'Không thể cập nhật lượt thích của bạn. Hãy thử lại.',
    'Premium offer': 'Ưu đãi Premium',
    'See who liked — a Premium feature': 'Xem ai đã thích — tính năng Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Với Premium, bạn có thể xem những người đã thích một Voice Moment, một Yeel hoặc một bình luận, hoặc đã bày tỏ cảm xúc với một tin nhắn trên máy chủ. Số lượt thích vẫn hiển thị với mọi người.',
    'Explore Premium': 'Khám phá Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium chưa thể mua. Sắp ra mắt.',
    'See who liked is included with Premium':
        '“Xem ai đã thích” có trong Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Huy hiệu, hiệu ứng lấp lánh, quyền riêng tư, xem ai đã thích và mức tăng hiển thị vừa phải trên Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Xem ai đã thích Voice Moments, Yeels, bình luận và tin nhắn máy chủ',
    'Hide my likes': 'Ẩn lượt thích của tôi',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Bạn sẽ không xuất hiện trong danh sách của YO Voice về những người đã thích hoặc bày tỏ cảm xúc. Số lượng không thay đổi. Thành viên máy chủ vẫn nhận được cảm xúc của bạn trong các kênh chung.',
    "Couldn't update this setting. Try again.":
        'Không thể thay đổi cài đặt này. Hãy thử lại.',
    'Privacy': 'Quyền riêng tư',
    '{count} people liked this Moment.zero':
        '{count} người đã thích Moment này',
    '{count} people liked this Moment.one': '{count} người đã thích Moment này',
    '{count} people liked this Moment.two': '{count} người đã thích Moment này',
    '{count} people liked this Moment.few': '{count} người đã thích Moment này',
    '{count} people liked this Moment.many':
        '{count} người đã thích Moment này',
    '{count} people liked this Moment.other':
        '{count} người đã thích Moment này',
    '{count} people liked this Yeel.zero': '{count} người đã thích Yeel này',
    '{count} people liked this Yeel.one': '{count} người đã thích Yeel này',
    '{count} people liked this Yeel.two': '{count} người đã thích Yeel này',
    '{count} people liked this Yeel.few': '{count} người đã thích Yeel này',
    '{count} people liked this Yeel.many': '{count} người đã thích Yeel này',
    '{count} people liked this Yeel.other': '{count} người đã thích Yeel này',
    '{count} people liked this comment.zero':
        '{count} người đã thích bình luận này',
    '{count} people liked this comment.one':
        '{count} người đã thích bình luận này',
    '{count} people liked this comment.two':
        '{count} người đã thích bình luận này',
    '{count} people liked this comment.few':
        '{count} người đã thích bình luận này',
    '{count} people liked this comment.many':
        '{count} người đã thích bình luận này',
    '{count} people liked this comment.other':
        '{count} người đã thích bình luận này',
    '{count} people reacted to this message.zero':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    '{count} people reacted to this message.one':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    '{count} people reacted to this message.two':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    '{count} people reacted to this message.few':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    '{count} people reacted to this message.many':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    '{count} people reacted to this message.other':
        '{count} người đã bày tỏ cảm xúc với tin nhắn này',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} người đã thích bài đăng này',
    '{count} people liked this post.one': '{count} người đã thích bài đăng này',
    '{count} people liked this post.two': '{count} người đã thích bài đăng này',
    '{count} people liked this post.few': '{count} người đã thích bài đăng này',
    '{count} people liked this post.many':
        '{count} người đã thích bài đăng này',
    '{count} people liked this post.other':
        '{count} người đã thích bài đăng này',
  },
  'zh_CN': <String, String>{
    'likers.titleLikes': '赞',
    'likers.titleReactions': '表情回应',
    'likers.tabAll': '全部',
    '{emoji}: {count}': '{emoji}：{count}',
    'likers.you': '你',
    '{name}, reacted {emoji}': '{name}，回应了 {emoji}',
    "Some people aren't shown.": '部分用户未显示。',
    'No one to show here.': '这里没有可显示的人。',
    'You can hide your own likes in Settings → Privacy.':
        '你可以在“设置 → 隐私”中隐藏自己的赞。',
    'Likes loaded: {count}': '已加载的赞：{count}',
    'Reactions loaded: {count}': '已加载的表情回应：{count}',
    'Open profile': '打开个人资料',
    'See who liked is coming soon.': '“查看谁赞了”即将推出。',
    'This content is no longer available.': '此内容已不可用。',
    'Too many requests. Try again in a minute.': '请求过多。请一分钟后重试。',
    "Couldn't load this list. Try again.": '无法加载此列表。请重试。',
    'See who liked': '查看谁赞了',
    'See who reacted': '查看谁回应了',
    'Likes · {count}': '赞 · {count}',
    'See who liked. Likes: {count}': '查看谁赞了。赞：{count}',
    'See who reacted. Reactions: {count}': '查看谁回应了。表情回应：{count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} 和另外 {count} 人赞了。查看谁赞了。',
    'Liked by {names}. See who liked.': '{names} 赞了。查看谁赞了。',
    'Like comment. Likes: {count}': '赞这条评论。赞：{count}',
    'Unlike comment. Likes: {count}': '取消赞这条评论。赞：{count}',
    'Who liked': '谁赞了',
    'Who liked. Likes: {count}': '谁赞了。赞：{count}',
    "Couldn't update your like. Try again.": '无法更新你的赞。请重试。',
    'Premium offer': 'Premium 优惠',
    'See who liked — a Premium feature': '查看谁赞了 — Premium 功能',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        '开通 Premium 后，你可以看到赞了某个 Voice Moment、Yeel 或评论的人，以及回应了服务器消息的人。赞的数量仍对所有人可见。',
    'Explore Premium': '了解 Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium 暂不可购买，即将推出。',
    'See who liked is included with Premium': '“查看谁赞了”包含在 Premium 中',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        '徽章、闪光效果、隐私设置、查看谁赞了，以及 Yeels 中的适度推荐加成',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        '查看谁赞了 Voice Moments、Yeels、评论和服务器消息',
    'Hide my likes': '隐藏我的赞',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        '你不会出现在 YO Voice 显示谁点赞或回应的列表中。数量不会改变。服务器成员仍会在你们共同所在的频道中收到你的回应。',
    "Couldn't update this setting. Try again.": '无法更改此设置。请重试。',
    'Privacy': '隐私',
    '{count} people liked this Moment.zero': '{count} 人赞了这个 Moment',
    '{count} people liked this Moment.one': '{count} 人赞了这个 Moment',
    '{count} people liked this Moment.two': '{count} 人赞了这个 Moment',
    '{count} people liked this Moment.few': '{count} 人赞了这个 Moment',
    '{count} people liked this Moment.many': '{count} 人赞了这个 Moment',
    '{count} people liked this Moment.other': '{count} 人赞了这个 Moment',
    '{count} people liked this Yeel.zero': '{count} 人赞了这个 Yeel',
    '{count} people liked this Yeel.one': '{count} 人赞了这个 Yeel',
    '{count} people liked this Yeel.two': '{count} 人赞了这个 Yeel',
    '{count} people liked this Yeel.few': '{count} 人赞了这个 Yeel',
    '{count} people liked this Yeel.many': '{count} 人赞了这个 Yeel',
    '{count} people liked this Yeel.other': '{count} 人赞了这个 Yeel',
    '{count} people liked this comment.zero': '{count} 人赞了这条评论',
    '{count} people liked this comment.one': '{count} 人赞了这条评论',
    '{count} people liked this comment.two': '{count} 人赞了这条评论',
    '{count} people liked this comment.few': '{count} 人赞了这条评论',
    '{count} people liked this comment.many': '{count} 人赞了这条评论',
    '{count} people liked this comment.other': '{count} 人赞了这条评论',
    '{count} people reacted to this message.zero': '{count} 人回应了这条消息',
    '{count} people reacted to this message.one': '{count} 人回应了这条消息',
    '{count} people reacted to this message.two': '{count} 人回应了这条消息',
    '{count} people reacted to this message.few': '{count} 人回应了这条消息',
    '{count} people reacted to this message.many': '{count} 人回应了这条消息',
    '{count} people reacted to this message.other': '{count} 人回应了这条消息',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} 人赞了这个帖子',
    '{count} people liked this post.one': '{count} 人赞了这个帖子',
    '{count} people liked this post.two': '{count} 人赞了这个帖子',
    '{count} people liked this post.few': '{count} 人赞了这个帖子',
    '{count} people liked this post.many': '{count} 人赞了这个帖子',
    '{count} people liked this post.other': '{count} 人赞了这个帖子',
  },
  'zh_TW': <String, String>{
    'likers.titleLikes': '讚',
    'likers.titleReactions': '表情回應',
    'likers.tabAll': '全部',
    '{emoji}: {count}': '{emoji}：{count}',
    'likers.you': '你',
    '{name}, reacted {emoji}': '{name}，回應了 {emoji}',
    "Some people aren't shown.": '部分使用者未顯示。',
    'No one to show here.': '這裡沒有可顯示的人。',
    'You can hide your own likes in Settings → Privacy.':
        '你可以在「設定 → 隱私」中隱藏自己的讚。',
    'Likes loaded: {count}': '已載入的讚：{count}',
    'Reactions loaded: {count}': '已載入的表情回應：{count}',
    'Open profile': '開啟個人檔案',
    'See who liked is coming soon.': '「查看誰按讚」即將推出。',
    'This content is no longer available.': '此內容已無法使用。',
    'Too many requests. Try again in a minute.': '要求次數過多。請一分鐘後再試。',
    "Couldn't load this list. Try again.": '無法載入此清單。請再試一次。',
    'See who liked': '查看誰按讚',
    'See who reacted': '查看誰回應',
    'Likes · {count}': '讚 · {count}',
    'See who liked. Likes: {count}': '查看誰按讚。讚：{count}',
    'See who reacted. Reactions: {count}': '查看誰回應。表情回應：{count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} 和其他 {count} 人都說讚。查看誰按讚。',
    'Liked by {names}. See who liked.': '{names} 說讚。查看誰按讚。',
    'Like comment. Likes: {count}': '對留言按讚。讚：{count}',
    'Unlike comment. Likes: {count}': '收回留言的讚。讚：{count}',
    'Who liked': '誰按讚',
    'Who liked. Likes: {count}': '誰按讚。讚：{count}',
    "Couldn't update your like. Try again.": '無法更新你的讚。請再試一次。',
    'Premium offer': 'Premium 優惠',
    'See who liked — a Premium feature': '查看誰按讚 — Premium 功能',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        '使用 Premium 後，你可以看到對 Voice Moment、Yeel 或留言按讚的人，以及回應伺服器訊息的人。讚數仍對所有人顯示。',
    'Explore Premium': '探索 Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium 目前尚無法購買，即將推出。',
    'See who liked is included with Premium': '「查看誰按讚」已包含在 Premium 中',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        '徽章、閃光效果、隱私設定、查看誰按讚，以及 Yeels 中的適度推薦加成',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        '查看誰對 Voice Moments、Yeels、留言和伺服器訊息按讚',
    'Hide my likes': '隱藏我的讚',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        '你不會出現在 YO Voice 顯示誰按讚或回應的清單中。數量不會改變。伺服器成員仍會在你們共同的頻道中收到你的回應。',
    "Couldn't update this setting. Try again.": '無法變更此設定。請再試一次。',
    'Privacy': '隱私',
    '{count} people liked this Moment.zero': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Moment.one': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Moment.two': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Moment.few': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Moment.many': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Moment.other': '{count} 人對這個 Moment 按讚',
    '{count} people liked this Yeel.zero': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this Yeel.one': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this Yeel.two': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this Yeel.few': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this Yeel.many': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this Yeel.other': '{count} 人對這個 Yeel 按讚',
    '{count} people liked this comment.zero': '{count} 人對這則留言按讚',
    '{count} people liked this comment.one': '{count} 人對這則留言按讚',
    '{count} people liked this comment.two': '{count} 人對這則留言按讚',
    '{count} people liked this comment.few': '{count} 人對這則留言按讚',
    '{count} people liked this comment.many': '{count} 人對這則留言按讚',
    '{count} people liked this comment.other': '{count} 人對這則留言按讚',
    '{count} people reacted to this message.zero': '{count} 人回應了這則訊息',
    '{count} people reacted to this message.one': '{count} 人回應了這則訊息',
    '{count} people reacted to this message.two': '{count} 人回應了這則訊息',
    '{count} people reacted to this message.few': '{count} 人回應了這則訊息',
    '{count} people reacted to this message.many': '{count} 人回應了這則訊息',
    '{count} people reacted to this message.other': '{count} 人回應了這則訊息',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} 人對這則貼文按讚',
    '{count} people liked this post.one': '{count} 人對這則貼文按讚',
    '{count} people liked this post.two': '{count} 人對這則貼文按讚',
    '{count} people liked this post.few': '{count} 人對這則貼文按讚',
    '{count} people liked this post.many': '{count} 人對這則貼文按讚',
    '{count} people liked this post.other': '{count} 人對這則貼文按讚',
  },
  'ja': <String, String>{
    'likers.titleLikes': 'いいね',
    'likers.titleReactions': 'リアクション',
    'likers.tabAll': 'すべて',
    '{emoji}: {count}': '{emoji}：{count}',
    'likers.you': 'あなた',
    '{name}, reacted {emoji}': '{name}、{emoji} でリアクション',
    "Some people aren't shown.": '一部のユーザーは表示されていません。',
    'No one to show here.': '表示できるユーザーはいません。',
    'You can hide your own likes in Settings → Privacy.':
        '自分のいいねは「設定」→「プライバシー」で非表示にできます。',
    'Likes loaded: {count}': '読み込んだいいね：{count}',
    'Reactions loaded: {count}': '読み込んだリアクション：{count}',
    'Open profile': 'プロフィールを開く',
    'See who liked is coming soon.': '「いいねした人を見る」は近日公開予定です。',
    'This content is no longer available.': 'このコンテンツは利用できなくなりました。',
    'Too many requests. Try again in a minute.': 'リクエストが多すぎます。1分後にもう一度お試しください。',
    "Couldn't load this list. Try again.": 'リストを読み込めませんでした。もう一度お試しください。',
    'See who liked': 'いいねした人を見る',
    'See who reacted': 'リアクションした人を見る',
    'Likes · {count}': 'いいね · {count}',
    'See who liked. Likes: {count}': 'いいねした人を見る。いいね：{count}',
    'See who reacted. Reactions: {count}': 'リアクションした人を見る。リアクション：{count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} さんほか {count} 人がいいねしました。いいねした人を見る。',
    'Liked by {names}. See who liked.': '{names} さんがいいねしました。いいねした人を見る。',
    'Like comment. Likes: {count}': 'コメントにいいねする。いいね：{count}',
    'Unlike comment. Likes: {count}': 'コメントのいいねを取り消す。いいね：{count}',
    'Who liked': 'いいねした人',
    'Who liked. Likes: {count}': 'いいねした人。いいね：{count}',
    "Couldn't update your like. Try again.": 'いいねを更新できませんでした。もう一度お試しください。',
    'Premium offer': 'Premium のご案内',
    'See who liked — a Premium feature': 'いいねした人を見る — Premium 機能',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium では、Voice Moment、Yeel、コメントにいいねした人や、サーバーのメッセージにリアクションした人を確認できます。いいねの数は引き続き全員に表示されます。',
    'Explore Premium': 'Premium を見る',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium はまだ購入できません。近日提供予定です。',
    'See who liked is included with Premium': '「いいねした人を見る」は Premium に含まれています',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'バッジ、きらめき、プライバシー設定、いいねした人の確認、Yeels での控えめな露出アップ',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Voice Moments、Yeels、コメント、サーバーメッセージにいいねした人を確認',
    'Hide my likes': '自分のいいねを非表示にする',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'いいねやリアクションをした人を表示する YO Voice のリストに、あなたは表示されなくなります。数は変わりません。サーバーのメンバーには、共通のチャンネルで引き続きあなたのリアクションが届きます。',
    "Couldn't update this setting. Try again.": 'この設定を変更できませんでした。もう一度お試しください。',
    'Privacy': 'プライバシー',
    '{count} people liked this Moment.zero': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Moment.one': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Moment.two': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Moment.few': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Moment.many': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Moment.other': '{count} 人がこの Moment にいいねしました',
    '{count} people liked this Yeel.zero': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this Yeel.one': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this Yeel.two': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this Yeel.few': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this Yeel.many': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this Yeel.other': '{count} 人がこの Yeel にいいねしました',
    '{count} people liked this comment.zero': '{count} 人がこのコメントにいいねしました',
    '{count} people liked this comment.one': '{count} 人がこのコメントにいいねしました',
    '{count} people liked this comment.two': '{count} 人がこのコメントにいいねしました',
    '{count} people liked this comment.few': '{count} 人がこのコメントにいいねしました',
    '{count} people liked this comment.many': '{count} 人がこのコメントにいいねしました',
    '{count} people liked this comment.other': '{count} 人がこのコメントにいいねしました',
    '{count} people reacted to this message.zero':
        '{count} 人がこのメッセージにリアクションしました',
    '{count} people reacted to this message.one':
        '{count} 人がこのメッセージにリアクションしました',
    '{count} people reacted to this message.two':
        '{count} 人がこのメッセージにリアクションしました',
    '{count} people reacted to this message.few':
        '{count} 人がこのメッセージにリアクションしました',
    '{count} people reacted to this message.many':
        '{count} 人がこのメッセージにリアクションしました',
    '{count} people reacted to this message.other':
        '{count} 人がこのメッセージにリアクションしました',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} 人がこの投稿にいいねしました',
    '{count} people liked this post.one': '{count} 人がこの投稿にいいねしました',
    '{count} people liked this post.two': '{count} 人がこの投稿にいいねしました',
    '{count} people liked this post.few': '{count} 人がこの投稿にいいねしました',
    '{count} people liked this post.many': '{count} 人がこの投稿にいいねしました',
    '{count} people liked this post.other': '{count} 人がこの投稿にいいねしました',
  },
  'ko': <String, String>{
    'likers.titleLikes': '좋아요',
    'likers.titleReactions': '반응',
    'likers.tabAll': '전체',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': '나',
    '{name}, reacted {emoji}': '{name}, {emoji} 반응',
    "Some people aren't shown.": '일부 사용자는 표시되지 않습니다.',
    'No one to show here.': '표시할 사람이 없습니다.',
    'You can hide your own likes in Settings → Privacy.':
        '설정 → 개인정보 보호에서 내 좋아요를 숨길 수 있습니다.',
    'Likes loaded: {count}': '불러온 좋아요: {count}',
    'Reactions loaded: {count}': '불러온 반응: {count}',
    'Open profile': '프로필 열기',
    'See who liked is coming soon.': "'좋아요 누른 사람 보기' 기능이 곧 제공됩니다.",
    'This content is no longer available.': '이 콘텐츠는 더 이상 사용할 수 없습니다.',
    'Too many requests. Try again in a minute.': '요청이 너무 많습니다. 1분 후에 다시 시도하세요.',
    "Couldn't load this list. Try again.": '목록을 불러올 수 없습니다. 다시 시도하세요.',
    'See who liked': '좋아요 누른 사람 보기',
    'See who reacted': '반응한 사람 보기',
    'Likes · {count}': '좋아요 · {count}',
    'See who liked. Likes: {count}': '좋아요 누른 사람 보기. 좋아요: {count}',
    'See who reacted. Reactions: {count}': '반응한 사람 보기. 반응: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names}님 외 {count}명이 좋아합니다. 좋아요 누른 사람 보기.',
    'Liked by {names}. See who liked.': '{names}님이 좋아합니다. 좋아요 누른 사람 보기.',
    'Like comment. Likes: {count}': '댓글 좋아요. 좋아요: {count}',
    'Unlike comment. Likes: {count}': '댓글 좋아요 취소. 좋아요: {count}',
    'Who liked': '좋아요 누른 사람',
    'Who liked. Likes: {count}': '좋아요 누른 사람. 좋아요: {count}',
    "Couldn't update your like. Try again.": '좋아요를 업데이트할 수 없습니다. 다시 시도하세요.',
    'Premium offer': 'Premium 혜택 안내',
    'See who liked — a Premium feature': '좋아요 누른 사람 보기 — Premium 기능',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium을 이용하면 Voice Moment, Yeel, 댓글에 좋아요를 누른 사람과 서버 메시지에 반응한 사람을 볼 수 있습니다. 좋아요 수는 계속 모든 사람에게 표시됩니다.',
    'Explore Premium': 'Premium 살펴보기',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium은 아직 구매할 수 없습니다. 곧 제공됩니다.',
    'See who liked is included with Premium': "'좋아요 누른 사람 보기'는 Premium에 포함됩니다",
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        '배지, 반짝임 효과, 개인정보 설정, 좋아요 누른 사람 보기, Yeels 노출 소폭 향상',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Voice Moments, Yeels, 댓글, 서버 메시지에 좋아요를 누른 사람 보기',
    'Hide my likes': '내 좋아요 숨기기',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        '좋아요를 누르거나 반응한 사람을 보여 주는 YO Voice 목록에 내가 표시되지 않습니다. 숫자는 바뀌지 않습니다. 서버 멤버는 함께 있는 채널에서 계속 내 반응을 받습니다.',
    "Couldn't update this setting. Try again.": '이 설정을 변경할 수 없습니다. 다시 시도하세요.',
    'Privacy': '개인정보 보호',
    '{count} people liked this Moment.zero': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Moment.one': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Moment.two': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Moment.few': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Moment.many': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Moment.other': '{count}명이 이 Moment를 좋아합니다',
    '{count} people liked this Yeel.zero': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this Yeel.one': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this Yeel.two': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this Yeel.few': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this Yeel.many': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this Yeel.other': '{count}명이 이 Yeel을 좋아합니다',
    '{count} people liked this comment.zero': '{count}명이 이 댓글을 좋아합니다',
    '{count} people liked this comment.one': '{count}명이 이 댓글을 좋아합니다',
    '{count} people liked this comment.two': '{count}명이 이 댓글을 좋아합니다',
    '{count} people liked this comment.few': '{count}명이 이 댓글을 좋아합니다',
    '{count} people liked this comment.many': '{count}명이 이 댓글을 좋아합니다',
    '{count} people liked this comment.other': '{count}명이 이 댓글을 좋아합니다',
    '{count} people reacted to this message.zero': '{count}명이 이 메시지에 반응했습니다',
    '{count} people reacted to this message.one': '{count}명이 이 메시지에 반응했습니다',
    '{count} people reacted to this message.two': '{count}명이 이 메시지에 반응했습니다',
    '{count} people reacted to this message.few': '{count}명이 이 메시지에 반응했습니다',
    '{count} people reacted to this message.many': '{count}명이 이 메시지에 반응했습니다',
    '{count} people reacted to this message.other': '{count}명이 이 메시지에 반응했습니다',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count}명이 이 게시물을 좋아합니다',
    '{count} people liked this post.one': '{count}명이 이 게시물을 좋아합니다',
    '{count} people liked this post.two': '{count}명이 이 게시물을 좋아합니다',
    '{count} people liked this post.few': '{count}명이 이 게시물을 좋아합니다',
    '{count} people liked this post.many': '{count}명이 이 게시물을 좋아합니다',
    '{count} people liked this post.other': '{count}명이 이 게시물을 좋아합니다',
  },
  'ar': <String, String>{
    'likers.titleLikes': 'الإعجابات',
    'likers.titleReactions': 'التفاعلات',
    'likers.tabAll': 'الكل',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'أنت',
    '{name}, reacted {emoji}': '{name}، تفاعل بـ {emoji}',
    "Some people aren't shown.": 'بعض الأشخاص غير معروضين.',
    'No one to show here.': 'لا يوجد أحد لعرضه هنا.',
    'You can hide your own likes in Settings → Privacy.':
        'يمكنك إخفاء إعجاباتك من الإعدادات ← الخصوصية.',
    'Likes loaded: {count}': 'الإعجابات المحمّلة: {count}',
    'Reactions loaded: {count}': 'التفاعلات المحمّلة: {count}',
    'Open profile': 'فتح الملف الشخصي',
    'See who liked is coming soon.': 'ميزة «عرض من أعجبهم» قادمة قريبًا.',
    'This content is no longer available.': 'هذا المحتوى لم يعد متاحًا.',
    'Too many requests. Try again in a minute.':
        'طلبات كثيرة جدًا. حاول مرة أخرى بعد دقيقة.',
    "Couldn't load this list. Try again.":
        'تعذّر تحميل هذه القائمة. حاول مرة أخرى.',
    'See who liked': 'عرض من أعجبهم',
    'See who reacted': 'عرض من تفاعلوا',
    'Likes · {count}': 'الإعجابات · {count}',
    'See who liked. Likes: {count}': 'عرض من أعجبهم. الإعجابات: {count}',
    'See who reacted. Reactions: {count}': 'عرض من تفاعلوا. التفاعلات: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'أعجب ذلك {names} و{count} آخرين. عرض من أعجبهم.',
    'Liked by {names}. See who liked.': 'أعجب ذلك {names}. عرض من أعجبهم.',
    'Like comment. Likes: {count}': 'الإعجاب بالتعليق. الإعجابات: {count}',
    'Unlike comment. Likes: {count}':
        'إلغاء الإعجاب بالتعليق. الإعجابات: {count}',
    'Who liked': 'من أعجبهم',
    'Who liked. Likes: {count}': 'من أعجبهم. الإعجابات: {count}',
    "Couldn't update your like. Try again.":
        'تعذّر تحديث إعجابك. حاول مرة أخرى.',
    'Premium offer': 'عرض Premium',
    'See who liked — a Premium feature': 'عرض من أعجبهم — ميزة Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'مع Premium يمكنك رؤية الأشخاص الذين أعجبهم Voice Moment أو Yeel أو تعليق، أو الذين تفاعلوا مع رسالة في خادم. يظل عدد الإعجابات مرئيًا للجميع.',
    'Explore Premium': 'استكشف Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'لا يمكن شراء Premium بعد. سيتوفر قريبًا.',
    'See who liked is included with Premium':
        'ميزة «عرض من أعجبهم» مضمّنة في Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'شارة ولمعان وعناصر تحكم في الخصوصية وعرض من أعجبهم المحتوى ودفعة معتدلة في Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'اعرف من أعجبتهم Voice Moments وYeels والتعليقات ورسائل الخوادم',
    'Hide my likes': 'إخفاء إعجاباتي',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'لن تظهر في قوائم YO Voice التي تعرض من أعجبهم المحتوى أو تفاعلوا معه. لا تتغير الأعداد. يظل أعضاء الخادم يتلقون تفاعلاتك في القنوات المشتركة بينكم.',
    "Couldn't update this setting. Try again.":
        'تعذّر تغيير هذا الإعداد. حاول مرة أخرى.',
    'Privacy': 'الخصوصية',
    '{count} people liked this Moment.zero':
        'أُعجب {count} شخص بهذا الـ Moment',
    '{count} people liked this Moment.one': 'أُعجب {count} شخص بهذا الـ Moment',
    '{count} people liked this Moment.two':
        'أُعجب {count} شخصان بهذا الـ Moment',
    '{count} people liked this Moment.few':
        'أُعجب {count} أشخاص بهذا الـ Moment',
    '{count} people liked this Moment.many':
        'أُعجب {count} شخصًا بهذا الـ Moment',
    '{count} people liked this Moment.other':
        'أُعجب {count} شخص بهذا الـ Moment',
    '{count} people liked this Yeel.zero': 'أُعجب {count} شخص بهذا الـ Yeel',
    '{count} people liked this Yeel.one': 'أُعجب {count} شخص بهذا الـ Yeel',
    '{count} people liked this Yeel.two': 'أُعجب {count} شخصان بهذا الـ Yeel',
    '{count} people liked this Yeel.few': 'أُعجب {count} أشخاص بهذا الـ Yeel',
    '{count} people liked this Yeel.many': 'أُعجب {count} شخصًا بهذا الـ Yeel',
    '{count} people liked this Yeel.other': 'أُعجب {count} شخص بهذا الـ Yeel',
    '{count} people liked this comment.zero': 'أُعجب {count} شخص بهذا التعليق',
    '{count} people liked this comment.one': 'أُعجب {count} شخص بهذا التعليق',
    '{count} people liked this comment.two': 'أُعجب {count} شخصان بهذا التعليق',
    '{count} people liked this comment.few': 'أُعجب {count} أشخاص بهذا التعليق',
    '{count} people liked this comment.many':
        'أُعجب {count} شخصًا بهذا التعليق',
    '{count} people liked this comment.other': 'أُعجب {count} شخص بهذا التعليق',
    '{count} people reacted to this message.zero':
        'تفاعل {count} شخص مع هذه الرسالة',
    '{count} people reacted to this message.one':
        'تفاعل {count} شخص مع هذه الرسالة',
    '{count} people reacted to this message.two':
        'تفاعل {count} شخصان مع هذه الرسالة',
    '{count} people reacted to this message.few':
        'تفاعل {count} أشخاص مع هذه الرسالة',
    '{count} people reacted to this message.many':
        'تفاعل {count} شخصًا مع هذه الرسالة',
    '{count} people reacted to this message.other':
        'تفاعل {count} شخص مع هذه الرسالة',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': 'أعجب هذا المنشور {count} شخص',
    '{count} people liked this post.one': 'أعجب هذا المنشور {count} شخص',
    '{count} people liked this post.two': 'أعجب هذا المنشور {count} شخصين',
    '{count} people liked this post.few': 'أعجب هذا المنشور {count} أشخاص',
    '{count} people liked this post.many': 'أعجب هذا المنشور {count} شخصًا',
    '{count} people liked this post.other': 'أعجب هذا المنشور {count} شخص',
  },
  'th': <String, String>{
    'likers.titleLikes': 'ถูกใจ',
    'likers.titleReactions': 'รีแอคชัน',
    'likers.tabAll': 'ทั้งหมด',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'คุณ',
    '{name}, reacted {emoji}': '{name}, รีแอคชัน {emoji}',
    "Some people aren't shown.": 'บางคนไม่ได้แสดงอยู่ที่นี่',
    'No one to show here.': 'ไม่มีใครให้แสดงที่นี่',
    'You can hide your own likes in Settings → Privacy.':
        'คุณซ่อนการถูกใจของตัวเองได้ใน การตั้งค่า → ความเป็นส่วนตัว',
    'Likes loaded: {count}': 'โหลดการถูกใจแล้ว: {count}',
    'Reactions loaded: {count}': 'โหลดรีแอคชันแล้ว: {count}',
    'Open profile': 'เปิดโปรไฟล์',
    'See who liked is coming soon.': '“ดูว่าใครถูกใจ” จะมาเร็วๆ นี้',
    'This content is no longer available.': 'เนื้อหานี้ไม่พร้อมใช้งานแล้ว',
    'Too many requests. Try again in a minute.':
        'มีคำขอมากเกินไป โปรดลองอีกครั้งในอีกหนึ่งนาที',
    "Couldn't load this list. Try again.":
        'โหลดรายการนี้ไม่ได้ โปรดลองอีกครั้ง',
    'See who liked': 'ดูว่าใครถูกใจ',
    'See who reacted': 'ดูว่าใครแสดงรีแอคชัน',
    'Likes · {count}': 'ถูกใจ · {count}',
    'See who liked. Likes: {count}': 'ดูว่าใครถูกใจ ถูกใจ: {count}',
    'See who reacted. Reactions: {count}':
        'ดูว่าใครแสดงรีแอคชัน รีแอคชัน: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} และอีก {count} คนถูกใจสิ่งนี้ ดูว่าใครถูกใจ',
    'Liked by {names}. See who liked.': '{names} ถูกใจสิ่งนี้ ดูว่าใครถูกใจ',
    'Like comment. Likes: {count}': 'ถูกใจความคิดเห็น ถูกใจ: {count}',
    'Unlike comment. Likes: {count}': 'เลิกถูกใจความคิดเห็น ถูกใจ: {count}',
    'Who liked': 'ใครถูกใจ',
    'Who liked. Likes: {count}': 'ใครถูกใจ ถูกใจ: {count}',
    "Couldn't update your like. Try again.":
        'อัปเดตการถูกใจของคุณไม่ได้ โปรดลองอีกครั้ง',
    'Premium offer': 'ข้อเสนอ Premium',
    'See who liked — a Premium feature': 'ดูว่าใครถูกใจ — ฟีเจอร์ Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'เมื่อใช้ Premium คุณจะเห็นคนที่ถูกใจ Voice Moment, Yeel หรือความคิดเห็น หรือแสดงรีแอคชันต่อข้อความในเซิร์ฟเวอร์ จำนวนการถูกใจยังคงแสดงให้ทุกคนเห็น',
    'Explore Premium': 'สำรวจ Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'ยังซื้อ Premium ไม่ได้ในขณะนี้ เร็วๆ นี้',
    'See who liked is included with Premium':
        '“ดูว่าใครถูกใจ” รวมอยู่ใน Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'ตราสัญลักษณ์ เอฟเฟกต์ประกาย การควบคุมความเป็นส่วนตัว ดูว่าใครถูกใจ และการโปรโมตใน Yeels ในระดับพอดี',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'ดูว่าใครถูกใจ Voice Moments, Yeels, ความคิดเห็น และข้อความในเซิร์ฟเวอร์',
    'Hide my likes': 'ซ่อนการถูกใจของฉัน',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'คุณจะไม่ปรากฏในรายการของ YO Voice ที่แสดงว่าใครถูกใจหรือแสดงรีแอคชัน จำนวนจะไม่เปลี่ยนแปลง สมาชิกเซิร์ฟเวอร์ยังคงได้รับรีแอคชันของคุณในช่องที่คุณอยู่ร่วมกัน',
    "Couldn't update this setting. Try again.":
        'เปลี่ยนการตั้งค่านี้ไม่ได้ โปรดลองอีกครั้ง',
    'Privacy': 'ความเป็นส่วนตัว',
    '{count} people liked this Moment.zero': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Moment.one': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Moment.two': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Moment.few': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Moment.many': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Moment.other': '{count} คนถูกใจ Moment นี้',
    '{count} people liked this Yeel.zero': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this Yeel.one': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this Yeel.two': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this Yeel.few': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this Yeel.many': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this Yeel.other': '{count} คนถูกใจ Yeel นี้',
    '{count} people liked this comment.zero': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people liked this comment.one': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people liked this comment.two': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people liked this comment.few': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people liked this comment.many': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people liked this comment.other': '{count} คนถูกใจความคิดเห็นนี้',
    '{count} people reacted to this message.zero':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    '{count} people reacted to this message.one':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    '{count} people reacted to this message.two':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    '{count} people reacted to this message.few':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    '{count} people reacted to this message.many':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    '{count} people reacted to this message.other':
        '{count} คนแสดงรีแอคชันต่อข้อความนี้',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} คนถูกใจโพสต์นี้',
    '{count} people liked this post.one': '{count} คนถูกใจโพสต์นี้',
    '{count} people liked this post.two': '{count} คนถูกใจโพสต์นี้',
    '{count} people liked this post.few': '{count} คนถูกใจโพสต์นี้',
    '{count} people liked this post.many': '{count} คนถูกใจโพสต์นี้',
    '{count} people liked this post.other': '{count} คนถูกใจโพสต์นี้',
  },
  'ms': <String, String>{
    'likers.titleLikes': 'Suka',
    'likers.titleReactions': 'Reaksi',
    'likers.tabAll': 'Semua',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Anda',
    '{name}, reacted {emoji}': '{name}, bereaksi {emoji}',
    "Some people aren't shown.": 'Sesetengah orang tidak ditunjukkan.',
    'No one to show here.': 'Tiada sesiapa untuk ditunjukkan di sini.',
    'You can hide your own likes in Settings → Privacy.':
        'Anda boleh menyembunyikan suka anda sendiri dalam Tetapan → Privasi.',
    'Likes loaded: {count}': 'Suka dimuatkan: {count}',
    'Reactions loaded: {count}': 'Reaksi dimuatkan: {count}',
    'Open profile': 'Buka profil',
    'See who liked is coming soon.':
        '“Lihat siapa yang suka” akan datang tidak lama lagi.',
    'This content is no longer available.':
        'Kandungan ini tidak lagi tersedia.',
    'Too many requests. Try again in a minute.':
        'Terlalu banyak permintaan. Cuba lagi dalam seminit.',
    "Couldn't load this list. Try again.":
        'Tidak dapat memuatkan senarai ini. Cuba lagi.',
    'See who liked': 'Lihat siapa yang suka',
    'See who reacted': 'Lihat siapa yang bereaksi',
    'Likes · {count}': 'Suka · {count}',
    'See who liked. Likes: {count}': 'Lihat siapa yang suka. Suka: {count}',
    'See who reacted. Reactions: {count}':
        'Lihat siapa yang bereaksi. Reaksi: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Disukai oleh {names} dan {count} yang lain. Lihat siapa yang suka.',
    'Liked by {names}. See who liked.':
        'Disukai oleh {names}. Lihat siapa yang suka.',
    'Like comment. Likes: {count}': 'Suka komen. Suka: {count}',
    'Unlike comment. Likes: {count}': 'Nyahsuka komen. Suka: {count}',
    'Who liked': 'Siapa yang suka',
    'Who liked. Likes: {count}': 'Siapa yang suka. Suka: {count}',
    "Couldn't update your like. Try again.":
        'Tidak dapat mengemas kini suka anda. Cuba lagi.',
    'Premium offer': 'Tawaran Premium',
    'See who liked — a Premium feature': 'Lihat siapa yang suka — ciri Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Dengan Premium, anda boleh melihat orang yang menyukai Voice Moment, Yeel atau komen, atau yang bereaksi pada mesej pelayan. Bilangan suka kekal kelihatan kepada semua orang.',
    'Explore Premium': 'Terokai Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium belum boleh dibeli. Akan datang tidak lama lagi.',
    'See who liked is included with Premium':
        '“Lihat siapa yang suka” disertakan dalam Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Lencana, kilauan, kawalan privasi, lihat siapa yang suka dan rangsangan sederhana dalam Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Lihat siapa yang menyukai Voice Moments, Yeels, komen dan mesej pelayan',
    'Hide my likes': 'Sembunyikan suka saya',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Anda tidak akan muncul dalam senarai YO Voice tentang siapa yang suka atau bereaksi. Bilangan tidak berubah. Ahli pelayan masih menerima reaksi anda dalam saluran yang anda kongsi.',
    "Couldn't update this setting. Try again.":
        'Tidak dapat menukar tetapan ini. Cuba lagi.',
    'Privacy': 'Privasi',
    '{count} people liked this Moment.zero':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.one': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.two': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.few': '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.many':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Moment.other':
        '{count} orang menyukai Moment ini',
    '{count} people liked this Yeel.zero': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.one': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.two': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.few': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.many': '{count} orang menyukai Yeel ini',
    '{count} people liked this Yeel.other': '{count} orang menyukai Yeel ini',
    '{count} people liked this comment.zero':
        '{count} orang menyukai komen ini',
    '{count} people liked this comment.one': '{count} orang menyukai komen ini',
    '{count} people liked this comment.two': '{count} orang menyukai komen ini',
    '{count} people liked this comment.few': '{count} orang menyukai komen ini',
    '{count} people liked this comment.many':
        '{count} orang menyukai komen ini',
    '{count} people liked this comment.other':
        '{count} orang menyukai komen ini',
    '{count} people reacted to this message.zero':
        '{count} orang bereaksi pada mesej ini',
    '{count} people reacted to this message.one':
        '{count} orang bereaksi pada mesej ini',
    '{count} people reacted to this message.two':
        '{count} orang bereaksi pada mesej ini',
    '{count} people reacted to this message.few':
        '{count} orang bereaksi pada mesej ini',
    '{count} people reacted to this message.many':
        '{count} orang bereaksi pada mesej ini',
    '{count} people reacted to this message.other':
        '{count} orang bereaksi pada mesej ini',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} orang menyukai hantaran ini',
    '{count} people liked this post.one': '{count} orang menyukai hantaran ini',
    '{count} people liked this post.two': '{count} orang menyukai hantaran ini',
    '{count} people liked this post.few': '{count} orang menyukai hantaran ini',
    '{count} people liked this post.many':
        '{count} orang menyukai hantaran ini',
    '{count} people liked this post.other':
        '{count} orang menyukai hantaran ini',
  },
  'fil': <String, String>{
    'likers.titleLikes': 'Mga like',
    'likers.titleReactions': 'Mga reaksyon',
    'likers.tabAll': 'Lahat',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Ikaw',
    '{name}, reacted {emoji}': '{name}, nag-react ng {emoji}',
    "Some people aren't shown.": 'Hindi ipinapakita ang ilang tao.',
    'No one to show here.': 'Walang maipapakita rito.',
    'You can hide your own likes in Settings → Privacy.':
        'Maitatago mo ang sarili mong mga like sa Mga setting → Pagkapribado.',
    'Likes loaded: {count}': 'Mga na-load na like: {count}',
    'Reactions loaded: {count}': 'Mga na-load na reaksyon: {count}',
    'Open profile': 'Buksan ang profile',
    'See who liked is coming soon.':
        'Malapit nang dumating ang “Tingnan kung sino ang nag-like.”',
    'This content is no longer available.':
        'Hindi na available ang content na ito.',
    'Too many requests. Try again in a minute.':
        'Masyadong maraming request. Subukan ulit pagkalipas ng isang minuto.',
    "Couldn't load this list. Try again.":
        'Hindi ma-load ang listahang ito. Subukan ulit.',
    'See who liked': 'Tingnan kung sino ang nag-like',
    'See who reacted': 'Tingnan kung sino ang nag-react',
    'Likes · {count}': 'Mga like · {count}',
    'See who liked. Likes: {count}':
        'Tingnan kung sino ang nag-like. Mga like: {count}',
    'See who reacted. Reactions: {count}':
        'Tingnan kung sino ang nag-react. Mga reaksyon: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Ni-like nina {names} at ng {count} iba pa. Tingnan kung sino ang nag-like.',
    'Liked by {names}. See who liked.':
        'Ni-like ni {names}. Tingnan kung sino ang nag-like.',
    'Like comment. Likes: {count}': 'I-like ang komento. Mga like: {count}',
    'Unlike comment. Likes: {count}': 'I-unlike ang komento. Mga like: {count}',
    'Who liked': 'Sino ang nag-like',
    'Who liked. Likes: {count}': 'Sino ang nag-like. Mga like: {count}',
    "Couldn't update your like. Try again.":
        'Hindi ma-update ang like mo. Subukan ulit.',
    'Premium offer': 'Alok ng Premium',
    'See who liked — a Premium feature':
        'Tingnan kung sino ang nag-like — feature ng Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Sa Premium, makikita mo ang mga taong nag-like ng Voice Moment, Yeel o komento, o nag-react sa mensahe sa server. Nananatiling nakikita ng lahat ang bilang ng mga like.',
    'Explore Premium': 'Tuklasin ang Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Hindi pa mabibili ang Premium. Malapit na.',
    'See who liked is included with Premium':
        'Kasama sa Premium ang “Tingnan kung sino ang nag-like”',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Badge, kislap, mga kontrol sa pagkapribado, pagtingin kung sino ang nag-like at katamtamang boost sa Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Tingnan kung sino ang nag-like ng Voice Moments, Yeels, mga komento at mensahe sa server',
    'Hide my likes': 'Itago ang mga like ko',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Hindi ka lalabas sa mga listahan ng YO Voice kung sino ang nag-like o nag-react. Hindi nagbabago ang bilang. Natatanggap pa rin ng mga miyembro ng server ang mga reaksyon mo sa mga channel na magkasama kayo.',
    "Couldn't update this setting. Try again.":
        'Hindi mabago ang setting na ito. Subukan ulit.',
    'Privacy': 'Pagkapribado',
    '{count} people liked this Moment.zero':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Moment.one':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Moment.two':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Moment.few':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Moment.many':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Moment.other':
        '{count} tao ang nag-like sa Moment na ito',
    '{count} people liked this Yeel.zero':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this Yeel.one':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this Yeel.two':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this Yeel.few':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this Yeel.many':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this Yeel.other':
        '{count} tao ang nag-like sa Yeel na ito',
    '{count} people liked this comment.zero':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people liked this comment.one':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people liked this comment.two':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people liked this comment.few':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people liked this comment.many':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people liked this comment.other':
        '{count} tao ang nag-like sa komentong ito',
    '{count} people reacted to this message.zero':
        '{count} tao ang nag-react sa mensaheng ito',
    '{count} people reacted to this message.one':
        '{count} tao ang nag-react sa mensaheng ito',
    '{count} people reacted to this message.two':
        '{count} tao ang nag-react sa mensaheng ito',
    '{count} people reacted to this message.few':
        '{count} tao ang nag-react sa mensaheng ito',
    '{count} people reacted to this message.many':
        '{count} tao ang nag-react sa mensaheng ito',
    '{count} people reacted to this message.other':
        '{count} tao ang nag-react sa mensaheng ito',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        '{count} tao ang nag-like sa post na ito',
    '{count} people liked this post.one':
        '{count} tao ang nag-like sa post na ito',
    '{count} people liked this post.two':
        '{count} tao ang nag-like sa post na ito',
    '{count} people liked this post.few':
        '{count} tao ang nag-like sa post na ito',
    '{count} people liked this post.many':
        '{count} tao ang nag-like sa post na ito',
    '{count} people liked this post.other':
        '{count} tao ang nag-like sa post na ito',
  },
  'he': <String, String>{
    'likers.titleLikes': 'לייקים',
    'likers.titleReactions': 'תגובות אמוג׳י',
    'likers.tabAll': 'הכול',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'את/ה',
    '{name}, reacted {emoji}': '{name}, הגיב/ה עם {emoji}',
    "Some people aren't shown.": 'חלק מהאנשים לא מוצגים.',
    'No one to show here.': 'אין כאן אף אחד להצגה.',
    'You can hide your own likes in Settings → Privacy.':
        'אפשר להסתיר את הלייקים שלך בהגדרות ← פרטיות.',
    'Likes loaded: {count}': 'לייקים שנטענו: {count}',
    'Reactions loaded: {count}': 'תגובות אמוג׳י שנטענו: {count}',
    'Open profile': 'פתיחת הפרופיל',
    'See who liked is coming soon.': 'האפשרות „הצגת מי שעשו לייק” תגיע בקרוב.',
    'This content is no longer available.': 'התוכן הזה כבר לא זמין.',
    'Too many requests. Try again in a minute.':
        'יותר מדי בקשות. אפשר לנסות שוב בעוד דקה.',
    "Couldn't load this list. Try again.":
        'לא ניתן לטעון את הרשימה. אפשר לנסות שוב.',
    'See who liked': 'הצגת מי שעשו לייק',
    'See who reacted': 'הצגת מי שהגיבו',
    'Likes · {count}': 'לייקים · {count}',
    'See who liked. Likes: {count}': 'הצגת מי שעשו לייק. לייקים: {count}',
    'See who reacted. Reactions: {count}':
        'הצגת מי שהגיבו. תגובות אמוג׳י: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} ועוד {count} עשו לייק. הצגת מי שעשו לייק.',
    'Liked by {names}. See who liked.': '{names} עשו לייק. הצגת מי שעשו לייק.',
    'Like comment. Likes: {count}': 'לייק לתגובה. לייקים: {count}',
    'Unlike comment. Likes: {count}': 'ביטול הלייק לתגובה. לייקים: {count}',
    'Who liked': 'מי עשו לייק',
    'Who liked. Likes: {count}': 'מי עשו לייק. לייקים: {count}',
    "Couldn't update your like. Try again.":
        'לא ניתן לעדכן את הלייק שלך. אפשר לנסות שוב.',
    'Premium offer': 'הצעת Premium',
    'See who liked — a Premium feature': 'הצגת מי שעשו לייק — תכונת Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'עם Premium אפשר לראות מי עשו לייק ל־Voice Moment, ל־Yeel או לתגובה, או הגיבו להודעה בשרת. מספר הלייקים ממשיך להיות גלוי לכולם.',
    'Explore Premium': 'גילוי Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'עדיין אי אפשר לרכוש את Premium. בקרוב.',
    'See who liked is included with Premium':
        '„הצגת מי שעשו לייק” כלולה ב־Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'תג, ניצוץ, הגדרות פרטיות, הצגת מי שעשו לייק ודחיפה מתונה ב־Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'הצגת מי שעשו לייק ל־Voice Moments, ל־Yeels, לתגובות ולהודעות בשרתים',
    'Hide my likes': 'הסתרת הלייקים שלי',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'לא תופיע/י ברשימות של YO Voice שמראות מי עשו לייק או הגיבו. המספרים לא משתנים. חברי השרת עדיין מקבלים את התגובות שלך בערוצים המשותפים לכם.',
    "Couldn't update this setting. Try again.":
        'לא ניתן לשנות את ההגדרה הזו. אפשר לנסות שוב.',
    'Privacy': 'פרטיות',
    '{count} people liked this Moment.zero':
        '{count} אנשים עשו לייק ל־Moment הזה',
    '{count} people liked this Moment.one': '{count} אדם עשה לייק ל־Moment הזה',
    '{count} people liked this Moment.two':
        '{count} אנשים עשו לייק ל־Moment הזה',
    '{count} people liked this Moment.few':
        '{count} אנשים עשו לייק ל־Moment הזה',
    '{count} people liked this Moment.many':
        '{count} אנשים עשו לייק ל־Moment הזה',
    '{count} people liked this Moment.other':
        '{count} אנשים עשו לייק ל־Moment הזה',
    '{count} people liked this Yeel.zero': '{count} אנשים עשו לייק ל־Yeel הזה',
    '{count} people liked this Yeel.one': '{count} אדם עשה לייק ל־Yeel הזה',
    '{count} people liked this Yeel.two': '{count} אנשים עשו לייק ל־Yeel הזה',
    '{count} people liked this Yeel.few': '{count} אנשים עשו לייק ל־Yeel הזה',
    '{count} people liked this Yeel.many': '{count} אנשים עשו לייק ל־Yeel הזה',
    '{count} people liked this Yeel.other': '{count} אנשים עשו לייק ל־Yeel הזה',
    '{count} people liked this comment.zero':
        '{count} אנשים עשו לייק לתגובה הזו',
    '{count} people liked this comment.one': '{count} אדם עשה לייק לתגובה הזו',
    '{count} people liked this comment.two':
        '{count} אנשים עשו לייק לתגובה הזו',
    '{count} people liked this comment.few':
        '{count} אנשים עשו לייק לתגובה הזו',
    '{count} people liked this comment.many':
        '{count} אנשים עשו לייק לתגובה הזו',
    '{count} people liked this comment.other':
        '{count} אנשים עשו לייק לתגובה הזו',
    '{count} people reacted to this message.zero':
        '{count} אנשים הגיבו להודעה הזו',
    '{count} people reacted to this message.one': '{count} אדם הגיב להודעה הזו',
    '{count} people reacted to this message.two':
        '{count} אנשים הגיבו להודעה הזו',
    '{count} people reacted to this message.few':
        '{count} אנשים הגיבו להודעה הזו',
    '{count} people reacted to this message.many':
        '{count} אנשים הגיבו להודעה הזו',
    '{count} people reacted to this message.other':
        '{count} אנשים הגיבו להודעה הזו',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} אנשים אהבו את הפוסט הזה',
    '{count} people liked this post.one': '{count} אדם אהב את הפוסט הזה',
    '{count} people liked this post.two': '{count} אנשים אהבו את הפוסט הזה',
    '{count} people liked this post.few': '{count} אנשים אהבו את הפוסט הזה',
    '{count} people liked this post.many': '{count} אנשים אהבו את הפוסט הזה',
    '{count} people liked this post.other': '{count} אנשים אהבו את הפוסט הזה',
  },
  'fa': <String, String>{
    'likers.titleLikes': 'پسندها',
    'likers.titleReactions': 'واکنش‌ها',
    'likers.tabAll': 'همه',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'شما',
    '{name}, reacted {emoji}': '{name}، با {emoji} واکنش نشان داد',
    "Some people aren't shown.": 'برخی افراد نمایش داده نمی‌شوند.',
    'No one to show here.': 'کسی برای نمایش در اینجا نیست.',
    'You can hide your own likes in Settings → Privacy.':
        'می‌توانید پسندهای خودتان را در تنظیمات ← حریم خصوصی پنهان کنید.',
    'Likes loaded: {count}': 'پسندهای بارگیری‌شده: {count}',
    'Reactions loaded: {count}': 'واکنش‌های بارگیری‌شده: {count}',
    'Open profile': 'باز کردن نمایه',
    'See who liked is coming soon.':
        'قابلیت «ببینید چه کسانی پسندیدند» به‌زودی می‌آید.',
    'This content is no longer available.': 'این محتوا دیگر در دسترس نیست.',
    'Too many requests. Try again in a minute.':
        'درخواست‌ها بیش از حد است. یک دقیقه دیگر دوباره امتحان کنید.',
    "Couldn't load this list. Try again.":
        'این فهرست بارگیری نشد. دوباره امتحان کنید.',
    'See who liked': 'ببینید چه کسانی پسندیدند',
    'See who reacted': 'ببینید چه کسانی واکنش نشان دادند',
    'Likes · {count}': 'پسندها · {count}',
    'See who liked. Likes: {count}':
        'ببینید چه کسانی پسندیدند. پسندها: {count}',
    'See who reacted. Reactions: {count}':
        'ببینید چه کسانی واکنش نشان دادند. واکنش‌ها: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} و {count} نفر دیگر پسندیدند. ببینید چه کسانی پسندیدند.',
    'Liked by {names}. See who liked.':
        '{names} پسندیدند. ببینید چه کسانی پسندیدند.',
    'Like comment. Likes: {count}': 'پسندیدن نظر. پسندها: {count}',
    'Unlike comment. Likes: {count}': 'لغو پسند نظر. پسندها: {count}',
    'Who liked': 'چه کسانی پسندیدند',
    'Who liked. Likes: {count}': 'چه کسانی پسندیدند. پسندها: {count}',
    "Couldn't update your like. Try again.":
        'پسند شما به‌روز نشد. دوباره امتحان کنید.',
    'Premium offer': 'پیشنهاد Premium',
    'See who liked — a Premium feature':
        'ببینید چه کسانی پسندیدند — قابلیت Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'با Premium می‌توانید افرادی را ببینید که یک Voice Moment، یک Yeel یا یک نظر را پسندیده‌اند یا به پیامی در سرور واکنش نشان داده‌اند. تعداد پسندها همچنان برای همه قابل مشاهده است.',
    'Explore Premium': 'آشنایی با Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium هنوز قابل خرید نیست. به‌زودی.',
    'See who liked is included with Premium':
        'قابلیت «ببینید چه کسانی پسندیدند» در Premium گنجانده شده است',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'نشان، درخشش، کنترل‌های حریم خصوصی، دیدن پسندکنندگان و تقویت متعادل در Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'ببینید چه کسانی Voice Moments، Yeels، نظرها و پیام‌های سرور را پسندیده‌اند',
    'Hide my likes': 'پنهان کردن پسندهای من',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'در فهرست‌های YO Voice که نشان می‌دهند چه کسی پسندیده یا واکنش نشان داده است، نمایش داده نمی‌شوید. تعدادها تغییر نمی‌کنند. اعضای سرور همچنان واکنش‌های شما را در کانال‌های مشترک دریافت می‌کنند.',
    "Couldn't update this setting. Try again.":
        'این تنظیم تغییر نکرد. دوباره امتحان کنید.',
    'Privacy': 'حریم خصوصی',
    '{count} people liked this Moment.zero':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Moment.one':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Moment.two':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Moment.few':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Moment.many':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Moment.other':
        '{count} نفر این Moment را پسندیدند',
    '{count} people liked this Yeel.zero': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this Yeel.one': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this Yeel.two': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this Yeel.few': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this Yeel.many': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this Yeel.other': '{count} نفر این Yeel را پسندیدند',
    '{count} people liked this comment.zero': '{count} نفر این نظر را پسندیدند',
    '{count} people liked this comment.one': '{count} نفر این نظر را پسندیدند',
    '{count} people liked this comment.two': '{count} نفر این نظر را پسندیدند',
    '{count} people liked this comment.few': '{count} نفر این نظر را پسندیدند',
    '{count} people liked this comment.many': '{count} نفر این نظر را پسندیدند',
    '{count} people liked this comment.other':
        '{count} نفر این نظر را پسندیدند',
    '{count} people reacted to this message.zero':
        '{count} نفر به این پیام واکنش نشان دادند',
    '{count} people reacted to this message.one':
        '{count} نفر به این پیام واکنش نشان دادند',
    '{count} people reacted to this message.two':
        '{count} نفر به این پیام واکنش نشان دادند',
    '{count} people reacted to this message.few':
        '{count} نفر به این پیام واکنش نشان دادند',
    '{count} people reacted to this message.many':
        '{count} نفر به این پیام واکنش نشان دادند',
    '{count} people reacted to this message.other':
        '{count} نفر به این پیام واکنش نشان دادند',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} نفر این پست را پسندیدند',
    '{count} people liked this post.one': '{count} نفر این پست را پسندیدند',
    '{count} people liked this post.two': '{count} نفر این پست را پسندیدند',
    '{count} people liked this post.few': '{count} نفر این پست را پسندیدند',
    '{count} people liked this post.many': '{count} نفر این پست را پسندیدند',
    '{count} people liked this post.other': '{count} نفر این پست را پسندیدند',
  },
  'sw': <String, String>{
    'likers.titleLikes': 'Vipendwa',
    'likers.titleReactions': 'Hisia',
    'likers.tabAll': 'Zote',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'Wewe',
    '{name}, reacted {emoji}': '{name}, alijibu kwa {emoji}',
    "Some people aren't shown.": 'Baadhi ya watu hawaonyeshwi.',
    'No one to show here.': 'Hakuna mtu wa kuonyesha hapa.',
    'You can hide your own likes in Settings → Privacy.':
        'Unaweza kuficha vipendwa vyako katika Mipangilio → Faragha.',
    'Likes loaded: {count}': 'Vipendwa vilivyopakiwa: {count}',
    'Reactions loaded: {count}': 'Hisia zilizopakiwa: {count}',
    'Open profile': 'Fungua wasifu',
    'See who liked is coming soon.': '“Ona waliopenda” inakuja hivi karibuni.',
    'This content is no longer available.': 'Maudhui haya hayapatikani tena.',
    'Too many requests. Try again in a minute.':
        'Maombi mengi mno. Jaribu tena baada ya dakika moja.',
    "Couldn't load this list. Try again.":
        'Imeshindwa kupakia orodha hii. Jaribu tena.',
    'See who liked': 'Ona waliopenda',
    'See who reacted': 'Ona waliojibu kwa hisia',
    'Likes · {count}': 'Vipendwa · {count}',
    'See who liked. Likes: {count}': 'Ona waliopenda. Vipendwa: {count}',
    'See who reacted. Reactions: {count}':
        'Ona waliojibu kwa hisia. Hisia: {count}',
    'Liked by {names} and {count} others. See who liked.':
        'Imependwa na {names} na wengine {count}. Ona waliopenda.',
    'Liked by {names}. See who liked.': 'Imependwa na {names}. Ona waliopenda.',
    'Like comment. Likes: {count}': 'Penda maoni. Vipendwa: {count}',
    'Unlike comment. Likes: {count}': 'Acha kupenda maoni. Vipendwa: {count}',
    'Who liked': 'Waliopenda',
    'Who liked. Likes: {count}': 'Waliopenda. Vipendwa: {count}',
    "Couldn't update your like. Try again.":
        'Imeshindwa kusasisha kipendwa chako. Jaribu tena.',
    'Premium offer': 'Ofa ya Premium',
    'See who liked — a Premium feature':
        'Ona waliopenda — kipengele cha Premium',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Ukiwa na Premium unaweza kuona watu waliopenda Voice Moment, Yeel au maoni, au waliojibu kwa hisia ujumbe wa seva. Idadi ya vipendwa inaendelea kuonekana kwa kila mtu.',
    'Explore Premium': 'Gundua Premium',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium bado haiwezi kununuliwa. Inakuja hivi karibuni.',
    'See who liked is included with Premium':
        '“Ona waliopenda” imejumuishwa katika Premium',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'Beji, mng’ao, vidhibiti vya faragha, kuona waliopenda na msukumo wa wastani kwenye Yeels',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'Ona waliopenda Voice Moments, Yeels, maoni na ujumbe wa seva',
    'Hide my likes': 'Ficha vipendwa vyangu',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'Hutaonekana kwenye orodha za YO Voice za waliopenda au waliojibu kwa hisia. Idadi haibadiliki. Wanachama wa seva bado hupokea hisia zako katika vituo mnavyoshiriki.',
    "Couldn't update this setting. Try again.":
        'Imeshindwa kubadilisha mpangilio huu. Jaribu tena.',
    'Privacy': 'Faragha',
    '{count} people liked this Moment.zero':
        'Watu {count} wamependa Moment hii',
    '{count} people liked this Moment.one': 'Mtu {count} amependa Moment hii',
    '{count} people liked this Moment.two': 'Watu {count} wamependa Moment hii',
    '{count} people liked this Moment.few': 'Watu {count} wamependa Moment hii',
    '{count} people liked this Moment.many':
        'Watu {count} wamependa Moment hii',
    '{count} people liked this Moment.other':
        'Watu {count} wamependa Moment hii',
    '{count} people liked this Yeel.zero': 'Watu {count} wamependa Yeel hii',
    '{count} people liked this Yeel.one': 'Mtu {count} amependa Yeel hii',
    '{count} people liked this Yeel.two': 'Watu {count} wamependa Yeel hii',
    '{count} people liked this Yeel.few': 'Watu {count} wamependa Yeel hii',
    '{count} people liked this Yeel.many': 'Watu {count} wamependa Yeel hii',
    '{count} people liked this Yeel.other': 'Watu {count} wamependa Yeel hii',
    '{count} people liked this comment.zero':
        'Watu {count} wamependa maoni haya',
    '{count} people liked this comment.one': 'Mtu {count} amependa maoni haya',
    '{count} people liked this comment.two':
        'Watu {count} wamependa maoni haya',
    '{count} people liked this comment.few':
        'Watu {count} wamependa maoni haya',
    '{count} people liked this comment.many':
        'Watu {count} wamependa maoni haya',
    '{count} people liked this comment.other':
        'Watu {count} wamependa maoni haya',
    '{count} people reacted to this message.zero':
        'Watu {count} wamejibu ujumbe huu kwa hisia',
    '{count} people reacted to this message.one':
        'Mtu {count} amejibu ujumbe huu kwa hisia',
    '{count} people reacted to this message.two':
        'Watu {count} wamejibu ujumbe huu kwa hisia',
    '{count} people reacted to this message.few':
        'Watu {count} wamejibu ujumbe huu kwa hisia',
    '{count} people reacted to this message.many':
        'Watu {count} wamejibu ujumbe huu kwa hisia',
    '{count} people reacted to this message.other':
        'Watu {count} wamejibu ujumbe huu kwa hisia',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero':
        'Watu {count} wamependa chapisho hili',
    '{count} people liked this post.one': 'Mtu {count} amependa chapisho hili',
    '{count} people liked this post.two':
        'Watu {count} wamependa chapisho hili',
    '{count} people liked this post.few':
        'Watu {count} wamependa chapisho hili',
    '{count} people liked this post.many':
        'Watu {count} wamependa chapisho hili',
    '{count} people liked this post.other':
        'Watu {count} wamependa chapisho hili',
  },
  'hi': <String, String>{
    'likers.titleLikes': 'लाइक',
    'likers.titleReactions': 'प्रतिक्रियाएँ',
    'likers.tabAll': 'सभी',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'आप',
    '{name}, reacted {emoji}': '{name}, {emoji} से प्रतिक्रिया दी',
    "Some people aren't shown.": 'कुछ लोग नहीं दिखाए गए हैं।',
    'No one to show here.': 'यहाँ दिखाने के लिए कोई नहीं है।',
    'You can hide your own likes in Settings → Privacy.':
        'आप सेटिंग्स → निजता में अपने लाइक छिपा सकते हैं।',
    'Likes loaded: {count}': 'लोड हुए लाइक: {count}',
    'Reactions loaded: {count}': 'लोड हुई प्रतिक्रियाएँ: {count}',
    'Open profile': 'प्रोफ़ाइल खोलें',
    'See who liked is coming soon.': '“देखें किसने लाइक किया” जल्द आ रहा है।',
    'This content is no longer available.': 'यह सामग्री अब उपलब्ध नहीं है।',
    'Too many requests. Try again in a minute.':
        'बहुत ज़्यादा अनुरोध। एक मिनट बाद फिर से कोशिश करें।',
    "Couldn't load this list. Try again.":
        'यह सूची लोड नहीं हो सकी। फिर से कोशिश करें।',
    'See who liked': 'देखें किसने लाइक किया',
    'See who reacted': 'देखें किसने प्रतिक्रिया दी',
    'Likes · {count}': 'लाइक · {count}',
    'See who liked. Likes: {count}': 'देखें किसने लाइक किया। लाइक: {count}',
    'See who reacted. Reactions: {count}':
        'देखें किसने प्रतिक्रिया दी। प्रतिक्रियाएँ: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} और {count} अन्य लोगों ने लाइक किया। देखें किसने लाइक किया।',
    'Liked by {names}. See who liked.':
        '{names} ने लाइक किया। देखें किसने लाइक किया।',
    'Like comment. Likes: {count}': 'टिप्पणी को लाइक करें। लाइक: {count}',
    'Unlike comment. Likes: {count}': 'टिप्पणी से लाइक हटाएँ। लाइक: {count}',
    'Who liked': 'किसने लाइक किया',
    'Who liked. Likes: {count}': 'किसने लाइक किया। लाइक: {count}',
    "Couldn't update your like. Try again.":
        'आपका लाइक अपडेट नहीं हो सका। फिर से कोशिश करें।',
    'Premium offer': 'Premium ऑफ़र',
    'See who liked — a Premium feature':
        'देखें किसने लाइक किया — Premium सुविधा',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium के साथ आप उन लोगों को देख सकते हैं जिन्होंने किसी Voice Moment, Yeel या टिप्पणी को लाइक किया, या किसी सर्वर संदेश पर प्रतिक्रिया दी। लाइक की संख्या सभी को दिखती रहती है।',
    'Explore Premium': 'Premium देखें',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium अभी खरीदा नहीं जा सकता। जल्द आ रहा है।',
    'See who liked is included with Premium':
        '“देखें किसने लाइक किया” Premium में शामिल है',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'बैज, चमक, निजता नियंत्रण, किसने लाइक किया यह देखना और Yeels में संतुलित बढ़ावा',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'देखें किसने Voice Moments, Yeels, टिप्पणियाँ और सर्वर संदेश लाइक किए',
    'Hide my likes': 'मेरे लाइक छिपाएँ',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'आप YO Voice की उन सूचियों में नहीं दिखेंगे जो बताती हैं कि किसने लाइक किया या प्रतिक्रिया दी। संख्याएँ नहीं बदलतीं। सर्वर के सदस्यों को साझा चैनलों में आपकी प्रतिक्रियाएँ मिलती रहती हैं।',
    "Couldn't update this setting. Try again.":
        'यह सेटिंग बदली नहीं जा सकी। फिर से कोशिश करें।',
    'Privacy': 'निजता',
    '{count} people liked this Moment.zero':
        '{count} लोगों ने यह Moment लाइक किया',
    '{count} people liked this Moment.one':
        '{count} व्यक्ति ने यह Moment लाइक किया',
    '{count} people liked this Moment.two':
        '{count} लोगों ने यह Moment लाइक किया',
    '{count} people liked this Moment.few':
        '{count} लोगों ने यह Moment लाइक किया',
    '{count} people liked this Moment.many':
        '{count} लोगों ने यह Moment लाइक किया',
    '{count} people liked this Moment.other':
        '{count} लोगों ने यह Moment लाइक किया',
    '{count} people liked this Yeel.zero': '{count} लोगों ने यह Yeel लाइक किया',
    '{count} people liked this Yeel.one':
        '{count} व्यक्ति ने यह Yeel लाइक किया',
    '{count} people liked this Yeel.two': '{count} लोगों ने यह Yeel लाइक किया',
    '{count} people liked this Yeel.few': '{count} लोगों ने यह Yeel लाइक किया',
    '{count} people liked this Yeel.many': '{count} लोगों ने यह Yeel लाइक किया',
    '{count} people liked this Yeel.other':
        '{count} लोगों ने यह Yeel लाइक किया',
    '{count} people liked this comment.zero':
        '{count} लोगों ने यह टिप्पणी लाइक की',
    '{count} people liked this comment.one':
        '{count} व्यक्ति ने यह टिप्पणी लाइक की',
    '{count} people liked this comment.two':
        '{count} लोगों ने यह टिप्पणी लाइक की',
    '{count} people liked this comment.few':
        '{count} लोगों ने यह टिप्पणी लाइक की',
    '{count} people liked this comment.many':
        '{count} लोगों ने यह टिप्पणी लाइक की',
    '{count} people liked this comment.other':
        '{count} लोगों ने यह टिप्पणी लाइक की',
    '{count} people reacted to this message.zero':
        '{count} लोगों ने इस संदेश पर प्रतिक्रिया दी',
    '{count} people reacted to this message.one':
        '{count} व्यक्ति ने इस संदेश पर प्रतिक्रिया दी',
    '{count} people reacted to this message.two':
        '{count} लोगों ने इस संदेश पर प्रतिक्रिया दी',
    '{count} people reacted to this message.few':
        '{count} लोगों ने इस संदेश पर प्रतिक्रिया दी',
    '{count} people reacted to this message.many':
        '{count} लोगों ने इस संदेश पर प्रतिक्रिया दी',
    '{count} people reacted to this message.other':
        '{count} लोगों ने इस संदेश पर प्रतिक्रिया दी',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} लोगों ने यह पोस्ट लाइक की',
    '{count} people liked this post.one': '{count} व्यक्ति ने यह पोस्ट लाइक की',
    '{count} people liked this post.two': '{count} लोगों ने यह पोस्ट लाइक की',
    '{count} people liked this post.few': '{count} लोगों ने यह पोस्ट लाइक की',
    '{count} people liked this post.many': '{count} लोगों ने यह पोस्ट लाइक की',
    '{count} people liked this post.other': '{count} लोगों ने यह पोस्ट लाइक की',
  },
  'bn': <String, String>{
    'likers.titleLikes': 'লাইক',
    'likers.titleReactions': 'প্রতিক্রিয়া',
    'likers.tabAll': 'সব',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'আপনি',
    '{name}, reacted {emoji}': '{name}, {emoji} দিয়ে প্রতিক্রিয়া জানিয়েছেন',
    "Some people aren't shown.": 'কিছু মানুষকে দেখানো হচ্ছে না।',
    'No one to show here.': 'এখানে দেখানোর মতো কেউ নেই।',
    'You can hide your own likes in Settings → Privacy.':
        'সেটিংস → গোপনীয়তা থেকে আপনি নিজের লাইক লুকাতে পারেন।',
    'Likes loaded: {count}': 'লোড হওয়া লাইক: {count}',
    'Reactions loaded: {count}': 'লোড হওয়া প্রতিক্রিয়া: {count}',
    'Open profile': 'প্রোফাইল খুলুন',
    'See who liked is coming soon.': '“দেখুন কে লাইক করেছেন” শিগগির আসছে।',
    'This content is no longer available.': 'এই কনটেন্ট আর উপলব্ধ নেই।',
    'Too many requests. Try again in a minute.':
        'অনেক বেশি অনুরোধ। এক মিনিট পরে আবার চেষ্টা করুন।',
    "Couldn't load this list. Try again.":
        'এই তালিকা লোড করা যায়নি। আবার চেষ্টা করুন।',
    'See who liked': 'দেখুন কে লাইক করেছেন',
    'See who reacted': 'দেখুন কে প্রতিক্রিয়া জানিয়েছেন',
    'Likes · {count}': 'লাইক · {count}',
    'See who liked. Likes: {count}': 'দেখুন কে লাইক করেছেন। লাইক: {count}',
    'See who reacted. Reactions: {count}':
        'দেখুন কে প্রতিক্রিয়া জানিয়েছেন। প্রতিক্রিয়া: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} এবং আরও {count} জন লাইক করেছেন। দেখুন কে লাইক করেছেন।',
    'Liked by {names}. See who liked.':
        '{names} লাইক করেছেন। দেখুন কে লাইক করেছেন।',
    'Like comment. Likes: {count}': 'মন্তব্যে লাইক দিন। লাইক: {count}',
    'Unlike comment. Likes: {count}': 'মন্তব্য থেকে লাইক সরান। লাইক: {count}',
    'Who liked': 'কে লাইক করেছেন',
    'Who liked. Likes: {count}': 'কে লাইক করেছেন। লাইক: {count}',
    "Couldn't update your like. Try again.":
        'আপনার লাইক আপডেট করা যায়নি। আবার চেষ্টা করুন।',
    'Premium offer': 'Premium অফার',
    'See who liked — a Premium feature': 'দেখুন কে লাইক করেছেন — Premium ফিচার',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium দিয়ে আপনি দেখতে পারবেন কারা কোনো Voice Moment, Yeel বা মন্তব্যে লাইক করেছেন, বা সার্ভারের কোনো মেসেজে প্রতিক্রিয়া জানিয়েছেন। লাইকের সংখ্যা সবাই দেখতে পাবেন।',
    'Explore Premium': 'Premium ঘুরে দেখুন',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium এখনও কেনা যাচ্ছে না। শিগগির আসছে।',
    'See who liked is included with Premium':
        '“দেখুন কে লাইক করেছেন” Premium-এ অন্তর্ভুক্ত',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'ব্যাজ, ঝলক, গোপনীয়তা নিয়ন্ত্রণ, কে লাইক করেছেন তা দেখা এবং Yeels-এ পরিমিত প্রচার',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'দেখুন কারা Voice Moments, Yeels, মন্তব্য ও সার্ভারের মেসেজে লাইক করেছেন',
    'Hide my likes': 'আমার লাইক লুকান',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'কে লাইক বা প্রতিক্রিয়া দিয়েছেন তা দেখানো YO Voice-এর তালিকায় আপনি থাকবেন না। সংখ্যা বদলায় না। সার্ভারের সদস্যরা শেয়ার করা চ্যানেলে এখনও আপনার প্রতিক্রিয়া পান।',
    "Couldn't update this setting. Try again.":
        'এই সেটিং পরিবর্তন করা যায়নি। আবার চেষ্টা করুন।',
    'Privacy': 'গোপনীয়তা',
    '{count} people liked this Moment.zero':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Moment.one':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Moment.two':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Moment.few':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Moment.many':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Moment.other':
        '{count} জন এই Moment-এ লাইক করেছেন',
    '{count} people liked this Yeel.zero': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this Yeel.one': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this Yeel.two': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this Yeel.few': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this Yeel.many': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this Yeel.other': '{count} জন এই Yeel-এ লাইক করেছেন',
    '{count} people liked this comment.zero':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people liked this comment.one':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people liked this comment.two':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people liked this comment.few':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people liked this comment.many':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people liked this comment.other':
        '{count} জন এই মন্তব্যে লাইক করেছেন',
    '{count} people reacted to this message.zero':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    '{count} people reacted to this message.one':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    '{count} people reacted to this message.two':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    '{count} people reacted to this message.few':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    '{count} people reacted to this message.many':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    '{count} people reacted to this message.other':
        '{count} জন এই মেসেজে প্রতিক্রিয়া জানিয়েছেন',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} জন এই পোস্টটি লাইক করেছেন',
    '{count} people liked this post.one': '{count} জন এই পোস্টটি লাইক করেছেন',
    '{count} people liked this post.two': '{count} জন এই পোস্টটি লাইক করেছেন',
    '{count} people liked this post.few': '{count} জন এই পোস্টটি লাইক করেছেন',
    '{count} people liked this post.many': '{count} জন এই পোস্টটি লাইক করেছেন',
    '{count} people liked this post.other': '{count} জন এই পোস্টটি লাইক করেছেন',
  },
  'ur': <String, String>{
    'likers.titleLikes': 'لائکس',
    'likers.titleReactions': 'ردعمل',
    'likers.tabAll': 'سب',
    '{emoji}: {count}': '{emoji}: {count}',
    'likers.you': 'آپ',
    '{name}, reacted {emoji}': '{name}، {emoji} کے ساتھ ردعمل دیا',
    "Some people aren't shown.": 'کچھ لوگ نہیں دکھائے گئے۔',
    'No one to show here.': 'یہاں دکھانے کے لیے کوئی نہیں ہے۔',
    'You can hide your own likes in Settings → Privacy.':
        'آپ ترتیبات ← رازداری میں اپنی لائکس چھپا سکتے ہیں۔',
    'Likes loaded: {count}': 'لوڈ شدہ لائکس: {count}',
    'Reactions loaded: {count}': 'لوڈ شدہ ردعمل: {count}',
    'Open profile': 'پروفائل کھولیں',
    'See who liked is coming soon.': '”دیکھیں کس نے لائک کیا“ جلد آ رہا ہے۔',
    'This content is no longer available.': 'یہ مواد اب دستیاب نہیں ہے۔',
    'Too many requests. Try again in a minute.':
        'بہت زیادہ درخواستیں۔ ایک منٹ بعد دوبارہ کوشش کریں۔',
    "Couldn't load this list. Try again.":
        'یہ فہرست لوڈ نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
    'See who liked': 'دیکھیں کس نے لائک کیا',
    'See who reacted': 'دیکھیں کس نے ردعمل دیا',
    'Likes · {count}': 'لائکس · {count}',
    'See who liked. Likes: {count}': 'دیکھیں کس نے لائک کیا۔ لائکس: {count}',
    'See who reacted. Reactions: {count}':
        'دیکھیں کس نے ردعمل دیا۔ ردعمل: {count}',
    'Liked by {names} and {count} others. See who liked.':
        '{names} اور {count} دیگر نے لائک کیا۔ دیکھیں کس نے لائک کیا۔',
    'Liked by {names}. See who liked.':
        '{names} نے لائک کیا۔ دیکھیں کس نے لائک کیا۔',
    'Like comment. Likes: {count}': 'تبصرہ لائک کریں۔ لائکس: {count}',
    'Unlike comment. Likes: {count}': 'تبصرے سے لائک ہٹائیں۔ لائکس: {count}',
    'Who liked': 'کس نے لائک کیا',
    'Who liked. Likes: {count}': 'کس نے لائک کیا۔ لائکس: {count}',
    "Couldn't update your like. Try again.":
        'آپ کا لائک اپ ڈیٹ نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    'Premium offer': 'Premium پیشکش',
    'See who liked — a Premium feature': 'دیکھیں کس نے لائک کیا — Premium فیچر',
    'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.':
        'Premium کے ساتھ آپ ان لوگوں کو دیکھ سکتے ہیں جنہوں نے کسی Voice Moment، Yeel یا تبصرے کو لائک کیا، یا سرور کے کسی پیغام پر ردعمل دیا۔ لائکس کی تعداد سب کو نظر آتی رہے گی۔',
    'Explore Premium': 'Premium دریافت کریں',
    "Premium isn't available to buy yet. It's coming soon.":
        'Premium ابھی خریدا نہیں جا سکتا۔ جلد آ رہا ہے۔',
    'See who liked is included with Premium':
        '”دیکھیں کس نے لائک کیا“ Premium میں شامل ہے',
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost':
        'بیج، چمک، رازداری کے کنٹرول، یہ دیکھنا کہ کس نے لائک کیا اور Yeels میں معتدل فروغ',
    'See who liked Voice Moments, Yeels, comments and Server messages':
        'دیکھیں کس نے Voice Moments، Yeels، تبصرے اور سرور کے پیغامات لائک کیے',
    'Hide my likes': 'میری لائکس چھپائیں',
    "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.":
        'آپ YO Voice کی ان فہرستوں میں نظر نہیں آئیں گے جو دکھاتی ہیں کہ کس نے لائک کیا یا ردعمل دیا۔ تعداد نہیں بدلتی۔ سرور کے اراکین مشترکہ چینلز میں آپ کے ردعمل بدستور وصول کرتے ہیں۔',
    "Couldn't update this setting. Try again.":
        'یہ ترتیب تبدیل نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
    'Privacy': 'رازداری',
    '{count} people liked this Moment.zero':
        '{count} لوگوں نے یہ Moment لائک کیا',
    '{count} people liked this Moment.one': '{count} شخص نے یہ Moment لائک کیا',
    '{count} people liked this Moment.two':
        '{count} لوگوں نے یہ Moment لائک کیا',
    '{count} people liked this Moment.few':
        '{count} لوگوں نے یہ Moment لائک کیا',
    '{count} people liked this Moment.many':
        '{count} لوگوں نے یہ Moment لائک کیا',
    '{count} people liked this Moment.other':
        '{count} لوگوں نے یہ Moment لائک کیا',
    '{count} people liked this Yeel.zero': '{count} لوگوں نے یہ Yeel لائک کیا',
    '{count} people liked this Yeel.one': '{count} شخص نے یہ Yeel لائک کیا',
    '{count} people liked this Yeel.two': '{count} لوگوں نے یہ Yeel لائک کیا',
    '{count} people liked this Yeel.few': '{count} لوگوں نے یہ Yeel لائک کیا',
    '{count} people liked this Yeel.many': '{count} لوگوں نے یہ Yeel لائک کیا',
    '{count} people liked this Yeel.other': '{count} لوگوں نے یہ Yeel لائک کیا',
    '{count} people liked this comment.zero':
        '{count} لوگوں نے یہ تبصرہ لائک کیا',
    '{count} people liked this comment.one': '{count} شخص نے یہ تبصرہ لائک کیا',
    '{count} people liked this comment.two':
        '{count} لوگوں نے یہ تبصرہ لائک کیا',
    '{count} people liked this comment.few':
        '{count} لوگوں نے یہ تبصرہ لائک کیا',
    '{count} people liked this comment.many':
        '{count} لوگوں نے یہ تبصرہ لائک کیا',
    '{count} people liked this comment.other':
        '{count} لوگوں نے یہ تبصرہ لائک کیا',
    '{count} people reacted to this message.zero':
        '{count} لوگوں نے اس پیغام پر ردعمل دیا',
    '{count} people reacted to this message.one':
        '{count} شخص نے اس پیغام پر ردعمل دیا',
    '{count} people reacted to this message.two':
        '{count} لوگوں نے اس پیغام پر ردعمل دیا',
    '{count} people reacted to this message.few':
        '{count} لوگوں نے اس پیغام پر ردعمل دیا',
    '{count} people reacted to this message.many':
        '{count} لوگوں نے اس پیغام پر ردعمل دیا',
    '{count} people reacted to this message.other':
        '{count} لوگوں نے اس پیغام پر ردعمل دیا',
    // Premium Pages (ADR-233): the likers count line of a Page post.
    '{count} people liked this post.zero': '{count} لوگوں نے یہ پوسٹ لائک کی',
    '{count} people liked this post.one': '{count} شخص نے یہ پوسٹ لائک کی',
    '{count} people liked this post.two': '{count} لوگوں نے یہ پوسٹ لائک کی',
    '{count} people liked this post.few': '{count} لوگوں نے یہ پوسٹ لائک کی',
    '{count} people liked this post.many': '{count} لوگوں نے یہ پوسٹ لائک کی',
    '{count} people liked this post.other': '{count} لوگوں نے یہ پوسٹ لائک کی',
  },
};
