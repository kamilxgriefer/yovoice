/// Copy for Page deletion (ADR-236; owner's choice pageDeleteWhat B "Dwa
/// działania" + pageDeleteHow B "30 dni na powrót", 2026-10-03): the
/// "Strefa zagrożenia" of Page settings, "Usuń wszystkie posty", the "Usuń
/// stronę" screen, the pending banner with "Przywróć stronę", "Usuń teraz,
/// nie czekaj", "Strona usunięta", the 7-day pause before a new Page, the
/// "deleted in 3 days" bell row, and the two create-flow lines that
/// deletion made untrue.
///
/// English and Polish are authored at the call sites
/// (`page_delete_copy.dart`, `page_profile_copy.dart`); this module gives
/// every other selectable locale an explicit translation, so none of these
/// strings falls back to English.
///
/// Three kinds of key live here, as in `translations_vip_likers.dart`:
///
/// * the final English phrase or template (`Delete {posts}?`), resolved by
///   `AppLocalizations.text` / `.template`;
/// * `pages.*` context keys for short words whose meaning depends on the
///   place ("Goes away" / "Stays" above the two lists, the "To be deleted"
///   pill), resolved by `AppLocalizations.contextualText`;
/// * the counted phrase `{count} posts`, keyed by the stem plus a CLDR
///   plural category and resolved by `AppLocalizations.pluralTemplate`.
///   Every locale carries all six entries; `zero` and `two` hold the forms
///   for exactly 0 and 2.
///
/// A sentence never spells a count itself: it takes the ready counted
/// phrase as `{posts}` or `{followers}` (the existing `{count} followers`
/// entries of `translations_pages.dart`), so each language declines the noun
/// once. "Premium", "VIP", "LIVE", "Voice Moments" and "Yeels" stay as
/// written. Every value keeps exactly the placeholders of its key
/// (`test/page_delete_localization_test.dart`).
///
/// GENERATED from the reviewed per-locale lists kept with the evidence of
/// this change (yovoice-evidence/2026-10-03/w42/page-delete/i18n); edit a
/// translation here directly when a native reader corrects it.
const pageDeleteTranslationKeys = <String>[
  'Delete all posts',
  'The Page and its followers stay',
  'Delete Page',
  'Posts, followers and contact details. Your account stays.',
  'Delete {posts}?',
  'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.',
  'Delete posts',
  'Posts deleted',
  'Deleting posts',
  'They disappear in the background, usually within several minutes. The Page and {followers} stay.',
  'Publish your first post',
  'pages.delete.goes',
  'The Page in Content and in search.',
  '{posts} with photos and recordings.',
  'Comments and likes under them.',
  '{followers} of the Page and their notifications about your LIVE.',
  'The Page\'s contact details.',
  'pages.delete.stays',
  'Your account: name, photo and cover.',
  'Friends, chats, servers, Voice Moments and Yeels.',
  'Exception: reported content',
  'We may keep reported content, not publicly, for up to 90 days.',
  'You have 30 days to come back',
  'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.',
  'Type the Page name',
  'To confirm, type: {name}',
  'pages.statusPendingDeletion',
  'The Page will be deleted on {date}',
  'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.',
  'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.',
  'Restore Page',
  'Comes back to Content with its posts and followers',
  'Page restored',
  'Delete now, don\'t wait',
  'Without waiting until {date}. This can\'t be undone.',
  'Delete the Page now?',
  'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.',
  'Deleting the Page',
  'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.',
  'You can create a new Page after {date}.',
  'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.',
  'A new Page can be created 7 days after the previous one was deleted.',
  'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.',
  'Your profile will show as a Page. You can pause or delete it any time in Page settings.',
  'Page deleted',
  'pages.delete.confirmIdentity',
  'Deleting the Page now needs a fresh sign-in. Enter your password.',
  'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.',
  'Deletion cancelled. The Page stays paused.',
  '{count} posts.zero',
  '{count} posts.one',
  '{count} posts.two',
  '{count} posts.few',
  '{count} posts.many',
  '{count} posts.other',
];

const pageDeleteTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'Delete all posts': 'Alle Beiträge löschen',
    'The Page and its followers stay': 'Seite und Follower bleiben erhalten',
    'Delete Page': 'Seite löschen',
    'Posts, followers and contact details. Your account stays.':
        'Beiträge, Follower und Kontaktdaten. Dein Konto bleibt.',
    'Delete {posts}?': '{posts} löschen?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Auch die Kommentare und Likes darunter verschwinden. Die Seite und {followers} bleiben. Das lässt sich nicht rückgängig machen.',
    'Delete posts': 'Beiträge löschen',
    'Posts deleted': 'Beiträge gelöscht',
    'Deleting posts': 'Beiträge werden gelöscht',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Sie verschwinden im Hintergrund, meist innerhalb weniger Minuten. Die Seite und {followers} bleiben.',
    'Publish your first post': 'Ersten Beitrag veröffentlichen',
    'pages.delete.goes': 'Verschwindet',
    'The Page in Content and in search.':
        'Die Seite in Inhalten und in der Suche.',
    '{posts} with photos and recordings.': '{posts} mit Fotos und Aufnahmen.',
    'Comments and likes under them.': 'Kommentare und Likes darunter.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} der Seite und ihre Benachrichtigungen zu deinen LIVE-Übertragungen.',
    'The Page\'s contact details.': 'Die Kontaktdaten der Seite.',
    'pages.delete.stays': 'Bleibt',
    'Your account: name, photo and cover.':
        'Dein Konto: Name, Foto und Titelbild.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Freunde, Chats, Server, Voice Moments und Yeels.',
    'Exception: reported content': 'Ausnahme: gemeldete Inhalte',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Gemeldete Inhalte können wir bis zu 90 Tage nicht öffentlich aufbewahren.',
    'You have 30 days to come back': 'Du hast 30 Tage, um zurückzukommen',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Wir blenden die Seite sofort aus und löschen sie am {date}. Bis dahin kannst du sie wiederherstellen. Dafür brauchst du aktives Premium oder VIP.',
    'Type the Page name': 'Namen der Seite eingeben',
    'To confirm, type: {name}': 'Zur Bestätigung eingeben: {name}',
    'pages.statusPendingDeletion': 'Wird gelöscht',
    'The Page will be deleted on {date}': 'Die Seite wird am {date} gelöscht',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Andere sehen sie nicht mehr, die Beiträge siehst nur du. Bis dahin kannst du sie mit Beiträgen und Followern wiederherstellen.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Andere sehen sie nicht mehr. Bis dahin kannst du sie mit Beiträgen und Followern wiederherstellen. Dafür brauchst du aktives Premium oder VIP.',
    'Restore Page': 'Seite wiederherstellen',
    'Comes back to Content with its posts and followers':
        'Kehrt mit Beiträgen und Followern in Inhalte zurück',
    'Page restored': 'Seite wiederhergestellt',
    'Delete now, don\'t wait': 'Jetzt löschen, nicht warten',
    'Without waiting until {date}. This can\'t be undone.':
        'Ohne bis zum {date} zu warten. Das lässt sich nicht rückgängig machen.',
    'Delete the Page now?': 'Seite jetzt löschen?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Beiträge, Follower und Kontaktdaten werden sofort gelöscht und lassen sich nicht wiederherstellen. Eine neue Seite kannst du nach 7 Tagen erstellen.',
    'Deleting the Page': 'Seite wird gelöscht',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Beiträge und Follower werden im Hintergrund entfernt. Eine neue Seite kannst du 7 Tage danach erstellen.',
    'You can create a new Page after {date}.':
        'Eine neue Seite kannst du nach dem {date} erstellen.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Deine Seite wird in 3 Tagen gelöscht. Stelle sie in den Seiteneinstellungen wieder her, wenn du sie behalten möchtest.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Eine neue Seite kann 7 Tage nach dem Löschen der vorherigen erstellt werden.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Mir ist klar, dass die Kontaktdaten öffentlich sichtbar sind. Sie bleiben gespeichert, solange die Seite pausiert ist, und werden zusammen mit der Seite gelöscht. Ich kann sie jederzeit entfernen.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Dein Profil wird als Seite angezeigt. Du kannst sie jederzeit in den Seiteneinstellungen pausieren oder löschen.',
    'Page deleted': 'Seite gelöscht',
    'pages.delete.confirmIdentity': 'Bestätige, dass du es bist',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Um die Seite sofort zu löschen, ist eine frische Anmeldung nötig. Gib dein Passwort ein.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Wir konnten nicht bestätigen, dass du es bist, deshalb wurde nichts gelöscht. Versuch es noch einmal oder melde dich ab und wieder an.',
    'Deletion cancelled. The Page stays paused.':
        'Löschung abgebrochen. Die Seite bleibt pausiert.',
    '{count} posts.zero': '{count} Beiträge',
    '{count} posts.one': '{count} Beitrag',
    '{count} posts.two': '{count} Beiträge',
    '{count} posts.few': '{count} Beiträge',
    '{count} posts.many': '{count} Beiträge',
    '{count} posts.other': '{count} Beiträge',
  },
  'es': <String, String>{
    'Delete all posts': 'Eliminar todas las publicaciones',
    'The Page and its followers stay': 'La página y los seguidores se quedan',
    'Delete Page': 'Eliminar página',
    'Posts, followers and contact details. Your account stays.':
        'Publicaciones, seguidores y datos de contacto. Tu cuenta se queda.',
    'Delete {posts}?': '¿Eliminar {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'También desaparecerán los comentarios y los me gusta que tienen. La página y {followers} se quedan. Esto no se puede deshacer.',
    'Delete posts': 'Eliminar publicaciones',
    'Posts deleted': 'Publicaciones eliminadas',
    'Deleting posts': 'Eliminando publicaciones',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Desaparecen en segundo plano, normalmente en unos minutos. La página y {followers} se quedan.',
    'Publish your first post': 'Publica tu primera publicación',
    'pages.delete.goes': 'Desaparece',
    'The Page in Content and in search.':
        'La página en Contenido y en la búsqueda.',
    '{posts} with photos and recordings.': '{posts} con fotos y grabaciones.',
    'Comments and likes under them.':
        'Los comentarios y los me gusta que tienen.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} de la página y sus notificaciones sobre tus LIVE.',
    'The Page\'s contact details.': 'Los datos de contacto de la página.',
    'pages.delete.stays': 'Se queda',
    'Your account: name, photo and cover.':
        'Tu cuenta: nombre, foto y portada.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Amigos, chats, servidores, Voice Moments y Yeels.',
    'Exception: reported content': 'Excepción: contenido denunciado',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Podemos conservar el contenido denunciado, de forma no pública, hasta 90 días.',
    'You have 30 days to come back': 'Tienes 30 días para volver',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Ocultaremos la página de inmediato y la eliminaremos el {date}. Hasta ese día puedes restaurarla. Restaurarla requiere Premium o VIP activo.',
    'Type the Page name': 'Escribe el nombre de la página',
    'To confirm, type: {name}': 'Para confirmar, escribe: {name}',
    'pages.statusPendingDeletion': 'Se eliminará',
    'The Page will be deleted on {date}': 'La página se eliminará el {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Los demás ya no la ven; las publicaciones solo las ves tú. Hasta ese día puedes restaurarla con sus publicaciones y seguidores.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Los demás ya no la ven. Hasta ese día puedes restaurarla con sus publicaciones y seguidores. Restaurarla requiere Premium o VIP activo.',
    'Restore Page': 'Restaurar página',
    'Comes back to Content with its posts and followers':
        'Vuelve a Contenido con sus publicaciones y seguidores',
    'Page restored': 'Página restaurada',
    'Delete now, don\'t wait': 'Eliminar ahora, sin esperar',
    'Without waiting until {date}. This can\'t be undone.':
        'Sin esperar hasta el {date}. Esto no se puede deshacer.',
    'Delete the Page now?': '¿Eliminar la página ahora?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Las publicaciones, los seguidores y los datos de contacto se eliminan de inmediato y no se pueden restaurar. Podrás crear una página nueva pasados 7 días.',
    'Deleting the Page': 'Eliminando la página',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Estamos quitando las publicaciones y los seguidores en segundo plano. Podrás crear una página nueva 7 días después de que termine.',
    'You can create a new Page after {date}.':
        'Podrás crear una página nueva después del {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Tu página se eliminará en 3 días. Restáurala en los ajustes de la página si quieres conservarla.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Se puede crear una página nueva 7 días después de eliminar la anterior.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Entiendo que los datos de contacto serán públicos. Se guardan mientras la página está en pausa y se eliminan junto con la página. Puedo borrarlos en cualquier momento.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Tu perfil se mostrará como página. Puedes pausarla o eliminarla cuando quieras en los ajustes de la página.',
    'Page deleted': 'Página eliminada',
    'pages.delete.confirmIdentity': 'Confirma que eres tú',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Para eliminar la página ahora hace falta un inicio de sesión reciente. Introduce tu contraseña.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'No pudimos confirmar que eres tú, así que no se eliminó nada. Inténtalo de nuevo o cierra sesión y vuelve a iniciarla.',
    'Deletion cancelled. The Page stays paused.':
        'Eliminación cancelada. La página sigue en pausa.',
    '{count} posts.zero': '{count} publicaciones',
    '{count} posts.one': '{count} publicación',
    '{count} posts.two': '{count} publicaciones',
    '{count} posts.few': '{count} publicaciones',
    '{count} posts.many': '{count} publicaciones',
    '{count} posts.other': '{count} publicaciones',
  },
  'pt': <String, String>{
    'Delete all posts': 'Eliminar todas as publicações',
    'The Page and its followers stay': 'A página e os seguidores ficam',
    'Delete Page': 'Eliminar página',
    'Posts, followers and contact details. Your account stays.':
        'Publicações, seguidores e contactos. A tua conta fica.',
    'Delete {posts}?': 'Eliminar {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Os comentários e os gostos que têm também desaparecem. A página e {followers} ficam. Isto não pode ser anulado.',
    'Delete posts': 'Eliminar publicações',
    'Posts deleted': 'Publicações eliminadas',
    'Deleting posts': 'A eliminar publicações',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Desaparecem em segundo plano, normalmente em poucos minutos. A página e {followers} ficam.',
    'Publish your first post': 'Publica a tua primeira publicação',
    'pages.delete.goes': 'Desaparece',
    'The Page in Content and in search.':
        'A página em Conteúdos e na pesquisa.',
    '{posts} with photos and recordings.': '{posts} com fotos e gravações.',
    'Comments and likes under them.': 'Os comentários e os gostos que têm.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} da página e as notificações deles sobre os teus LIVE.',
    'The Page\'s contact details.': 'Os contactos da página.',
    'pages.delete.stays': 'Fica',
    'Your account: name, photo and cover.': 'A tua conta: nome, foto e capa.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Amigos, conversas, servidores, Voice Moments e Yeels.',
    'Exception: reported content': 'Exceção: conteúdo denunciado',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Podemos guardar conteúdo denunciado, de forma não pública, até 90 dias.',
    'You have 30 days to come back': 'Tens 30 dias para voltar',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Ocultamos a página de imediato e eliminamo-la a {date}. Até lá podes restaurá-la. Restaurar requer Premium ou VIP ativo.',
    'Type the Page name': 'Escreve o nome da página',
    'To confirm, type: {name}': 'Para confirmar, escreve: {name}',
    'pages.statusPendingDeletion': 'A eliminar',
    'The Page will be deleted on {date}': 'A página será eliminada a {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Os outros já não a veem; só tu vês as publicações. Até lá podes restaurá-la com as publicações e os seguidores.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Os outros já não a veem. Até lá podes restaurá-la com as publicações e os seguidores. Restaurar requer Premium ou VIP ativo.',
    'Restore Page': 'Restaurar página',
    'Comes back to Content with its posts and followers':
        'Volta a Conteúdos com as publicações e os seguidores',
    'Page restored': 'Página restaurada',
    'Delete now, don\'t wait': 'Eliminar agora, sem esperar',
    'Without waiting until {date}. This can\'t be undone.':
        'Sem esperar até {date}. Isto não pode ser anulado.',
    'Delete the Page now?': 'Eliminar a página agora?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'As publicações, os seguidores e os contactos são eliminados de imediato e não podem ser restaurados. Podes criar uma página nova ao fim de 7 dias.',
    'Deleting the Page': 'A eliminar a página',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Estamos a remover as publicações e os seguidores em segundo plano. Podes criar uma página nova 7 dias depois de terminar.',
    'You can create a new Page after {date}.':
        'Podes criar uma página nova depois de {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'A tua página será eliminada dentro de 3 dias. Restaura-a nas definições da página se a quiseres manter.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Pode criar-se uma página nova 7 dias depois de a anterior ser eliminada.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Compreendo que os contactos serão públicos. Ficam guardados enquanto a página está em pausa e são eliminados juntamente com a página. Posso apagá-los a qualquer momento.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'O teu perfil vai aparecer como página. Podes pausá-la ou eliminá-la a qualquer momento nas definições da página.',
    'Page deleted': 'Página eliminada',
    'pages.delete.confirmIdentity': 'Confirma que és tu',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Para eliminar a página agora é preciso um início de sessão recente. Introduz a tua palavra-passe.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Não conseguimos confirmar que és tu, por isso nada foi eliminado. Tenta novamente ou termina a sessão e inicia-a de novo.',
    'Deletion cancelled. The Page stays paused.':
        'Eliminação cancelada. A página continua em pausa.',
    '{count} posts.zero': '{count} publicações',
    '{count} posts.one': '{count} publicação',
    '{count} posts.two': '{count} publicações',
    '{count} posts.few': '{count} publicações',
    '{count} posts.many': '{count} publicações',
    '{count} posts.other': '{count} publicações',
  },
  'pt_BR': <String, String>{
    'Delete all posts': 'Excluir todas as publicações',
    'The Page and its followers stay': 'A página e os seguidores ficam',
    'Delete Page': 'Excluir página',
    'Posts, followers and contact details. Your account stays.':
        'Publicações, seguidores e contato. Sua conta fica.',
    'Delete {posts}?': 'Excluir {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Os comentários e as curtidas delas também somem. A página e {followers} ficam. Isso não pode ser desfeito.',
    'Delete posts': 'Excluir publicações',
    'Posts deleted': 'Publicações excluídas',
    'Deleting posts': 'Excluindo publicações',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Elas somem em segundo plano, normalmente em poucos minutos. A página e {followers} ficam.',
    'Publish your first post': 'Publique sua primeira publicação',
    'pages.delete.goes': 'Some',
    'The Page in Content and in search.': 'A página em Conteúdo e na busca.',
    '{posts} with photos and recordings.': '{posts} com fotos e gravações.',
    'Comments and likes under them.': 'Os comentários e as curtidas delas.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} da página e as notificações deles sobre seus LIVE.',
    'The Page\'s contact details.': 'Os dados de contato da página.',
    'pages.delete.stays': 'Fica',
    'Your account: name, photo and cover.': 'Sua conta: nome, foto e capa.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Amigos, conversas, servidores, Voice Moments e Yeels.',
    'Exception: reported content': 'Exceção: conteúdo denunciado',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Podemos guardar conteúdo denunciado, de forma não pública, por até 90 dias.',
    'You have 30 days to come back': 'Você tem 30 dias para voltar',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Ocultamos a página na hora e a excluímos em {date}. Até lá você pode restaurá-la. Restaurar exige Premium ou VIP ativo.',
    'Type the Page name': 'Digite o nome da página',
    'To confirm, type: {name}': 'Para confirmar, digite: {name}',
    'pages.statusPendingDeletion': 'Será excluída',
    'The Page will be deleted on {date}': 'A página será excluída em {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'As outras pessoas já não a veem; só você vê as publicações. Até lá você pode restaurá-la com as publicações e os seguidores.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'As outras pessoas já não a veem. Até lá você pode restaurá-la com as publicações e os seguidores. Restaurar exige Premium ou VIP ativo.',
    'Restore Page': 'Restaurar página',
    'Comes back to Content with its posts and followers':
        'Volta para Conteúdo com as publicações e os seguidores',
    'Page restored': 'Página restaurada',
    'Delete now, don\'t wait': 'Excluir agora, sem esperar',
    'Without waiting until {date}. This can\'t be undone.':
        'Sem esperar até {date}. Isso não pode ser desfeito.',
    'Delete the Page now?': 'Excluir a página agora?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'As publicações, os seguidores e os dados de contato são excluídos na hora e não podem ser restaurados. Você pode criar uma página nova depois de 7 dias.',
    'Deleting the Page': 'Excluindo a página',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Estamos removendo as publicações e os seguidores em segundo plano. Você pode criar uma página nova 7 dias depois que terminar.',
    'You can create a new Page after {date}.':
        'Você pode criar uma página nova depois de {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Sua página será excluída em 3 dias. Restaure-a nas configurações da página se quiser mantê-la.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Uma página nova pode ser criada 7 dias depois da exclusão da anterior.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Entendo que os dados de contato serão públicos. Eles ficam salvos enquanto a página está pausada e são excluídos junto com a página. Posso apagá-los quando quiser.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Seu perfil vai aparecer como página. Você pode pausá-la ou excluí-la quando quiser nas configurações da página.',
    'Page deleted': 'Página excluída',
    'pages.delete.confirmIdentity': 'Confirme que é você',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Para excluir a página agora é preciso um login recente. Digite sua senha.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Não conseguimos confirmar que é você, então nada foi excluído. Tente de novo ou saia e entre novamente.',
    'Deletion cancelled. The Page stays paused.':
        'Exclusão cancelada. A página continua pausada.',
    '{count} posts.zero': '{count} publicações',
    '{count} posts.one': '{count} publicação',
    '{count} posts.two': '{count} publicações',
    '{count} posts.few': '{count} publicações',
    '{count} posts.many': '{count} publicações',
    '{count} posts.other': '{count} publicações',
  },
  'fr': <String, String>{
    'Delete all posts': 'Supprimer toutes les publications',
    'The Page and its followers stay': 'La page et les abonnés restent',
    'Delete Page': 'Supprimer la page',
    'Posts, followers and contact details. Your account stays.':
        'Publications, abonnés et coordonnées. Ton compte reste.',
    'Delete {posts}?': 'Supprimer {posts} ?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Les commentaires et les j’aime associés disparaissent aussi. La page et {followers} restent. Cette action est irréversible.',
    'Delete posts': 'Supprimer les publications',
    'Posts deleted': 'Publications supprimées',
    'Deleting posts': 'Suppression des publications',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Elles disparaissent en arrière-plan, en général en quelques minutes. La page et {followers} restent.',
    'Publish your first post': 'Publie ta première publication',
    'pages.delete.goes': 'Disparaît',
    'The Page in Content and in search.':
        'La page dans Contenus et dans la recherche.',
    '{posts} with photos and recordings.':
        '{posts} avec photos et enregistrements.',
    'Comments and likes under them.':
        'Les commentaires et les j’aime associés.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} de la page et leurs notifications sur tes LIVE.',
    'The Page\'s contact details.': 'Les coordonnées de la page.',
    'pages.delete.stays': 'Reste',
    'Your account: name, photo and cover.':
        'Ton compte : nom, photo et couverture.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Amis, discussions, serveurs, Voice Moments et Yeels.',
    'Exception: reported content': 'Exception : contenu signalé',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Nous pouvons conserver un contenu signalé, de façon non publique, jusqu’à 90 jours.',
    'You have 30 days to come back': 'Tu as 30 jours pour revenir',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Nous masquons la page tout de suite et la supprimons le {date}. D’ici là, tu peux la restaurer. La restauration nécessite un Premium ou un VIP actif.',
    'Type the Page name': 'Saisis le nom de la page',
    'To confirm, type: {name}': 'Pour confirmer, saisis : {name}',
    'pages.statusPendingDeletion': 'Suppression prévue',
    'The Page will be deleted on {date}': 'La page sera supprimée le {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Les autres ne la voient plus ; toi seul vois les publications. D’ici là, tu peux la restaurer avec ses publications et ses abonnés.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Les autres ne la voient plus. D’ici là, tu peux la restaurer avec ses publications et ses abonnés. La restauration nécessite un Premium ou un VIP actif.',
    'Restore Page': 'Restaurer la page',
    'Comes back to Content with its posts and followers':
        'Revient dans Contenus avec ses publications et ses abonnés',
    'Page restored': 'Page restaurée',
    'Delete now, don\'t wait': 'Supprimer maintenant, sans attendre',
    'Without waiting until {date}. This can\'t be undone.':
        'Sans attendre le {date}. Cette action est irréversible.',
    'Delete the Page now?': 'Supprimer la page maintenant ?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Les publications, les abonnés et les coordonnées sont supprimés tout de suite et ne peuvent pas être restaurés. Tu pourras créer une nouvelle page au bout de 7 jours.',
    'Deleting the Page': 'Suppression de la page',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Nous retirons les publications et les abonnés en arrière-plan. Tu pourras créer une nouvelle page 7 jours après la fin.',
    'You can create a new Page after {date}.':
        'Tu pourras créer une nouvelle page après le {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Ta page sera supprimée dans 3 jours. Restaure-la dans les paramètres de la page si tu veux la garder.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Une nouvelle page peut être créée 7 jours après la suppression de la précédente.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Je comprends que les coordonnées seront publiques. Elles restent enregistrées tant que la page est en pause et sont supprimées avec la page. Je peux les effacer à tout moment.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Ton profil s’affichera comme une page. Tu peux la mettre en pause ou la supprimer à tout moment dans les paramètres de la page.',
    'Page deleted': 'Page supprimée',
    'pages.delete.confirmIdentity': 'Confirme que c’est bien toi',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Supprimer la page tout de suite demande une connexion récente. Saisis ton mot de passe.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nous n’avons pas pu confirmer que c’est bien toi, donc rien n’a été supprimé. Réessaie, ou déconnecte-toi puis reconnecte-toi.',
    'Deletion cancelled. The Page stays paused.':
        'Suppression annulée. La page reste en pause.',
    '{count} posts.zero': '{count} publication',
    '{count} posts.one': '{count} publication',
    '{count} posts.two': '{count} publications',
    '{count} posts.few': '{count} publications',
    '{count} posts.many': '{count} publications',
    '{count} posts.other': '{count} publications',
  },
  'it': <String, String>{
    'Delete all posts': 'Elimina tutti i post',
    'The Page and its followers stay': 'La pagina e i follower restano',
    'Delete Page': 'Elimina pagina',
    'Posts, followers and contact details. Your account stays.':
        'Post, follower e contatti. Il tuo account resta.',
    'Delete {posts}?': 'Eliminare {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Spariranno anche i commenti e i Mi piace sotto. La pagina e {followers} restano. L’operazione non si può annullare.',
    'Delete posts': 'Elimina i post',
    'Posts deleted': 'Post eliminati',
    'Deleting posts': 'Eliminazione dei post',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Spariscono in background, di solito in pochi minuti. La pagina e {followers} restano.',
    'Publish your first post': 'Pubblica il tuo primo post',
    'pages.delete.goes': 'Sparisce',
    'The Page in Content and in search.':
        'La pagina in Contenuti e nella ricerca.',
    '{posts} with photos and recordings.': '{posts} con foto e registrazioni.',
    'Comments and likes under them.': 'I commenti e i Mi piace sotto.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} della pagina e le loro notifiche sui tuoi LIVE.',
    'The Page\'s contact details.': 'I contatti della pagina.',
    'pages.delete.stays': 'Resta',
    'Your account: name, photo and cover.':
        'Il tuo account: nome, foto e copertina.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Amici, chat, server, Voice Moments e Yeels.',
    'Exception: reported content': 'Eccezione: contenuti segnalati',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Possiamo conservare i contenuti segnalati, in modo non pubblico, fino a 90 giorni.',
    'You have 30 days to come back': 'Hai 30 giorni per tornare',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Nascondiamo subito la pagina e la eliminiamo il {date}. Fino ad allora puoi ripristinarla. Il ripristino richiede Premium o VIP attivo.',
    'Type the Page name': 'Scrivi il nome della pagina',
    'To confirm, type: {name}': 'Per confermare, scrivi: {name}',
    'pages.statusPendingDeletion': 'In eliminazione',
    'The Page will be deleted on {date}': 'La pagina sarà eliminata il {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Gli altri non la vedono più; i post li vedi solo tu. Fino ad allora puoi ripristinarla con i post e i follower.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Gli altri non la vedono più. Fino ad allora puoi ripristinarla con i post e i follower. Il ripristino richiede Premium o VIP attivo.',
    'Restore Page': 'Ripristina pagina',
    'Comes back to Content with its posts and followers':
        'Torna in Contenuti con i post e i follower',
    'Page restored': 'Pagina ripristinata',
    'Delete now, don\'t wait': 'Elimina ora, senza aspettare',
    'Without waiting until {date}. This can\'t be undone.':
        'Senza aspettare il {date}. L’operazione non si può annullare.',
    'Delete the Page now?': 'Eliminare la pagina ora?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Post, follower e contatti vengono eliminati subito e non si possono ripristinare. Potrai creare una nuova pagina dopo 7 giorni.',
    'Deleting the Page': 'Eliminazione della pagina',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Stiamo rimuovendo post e follower in background. Potrai creare una nuova pagina 7 giorni dopo la fine.',
    'You can create a new Page after {date}.':
        'Potrai creare una nuova pagina dopo il {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'La tua pagina sarà eliminata tra 3 giorni. Ripristinala nelle impostazioni della pagina se vuoi tenerla.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Una nuova pagina può essere creata 7 giorni dopo l’eliminazione della precedente.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Ho capito che i contatti saranno pubblici. Restano salvati mentre la pagina è in pausa e vengono eliminati insieme alla pagina. Posso cancellarli in qualsiasi momento.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Il tuo profilo apparirà come pagina. Puoi metterla in pausa o eliminarla in qualsiasi momento nelle impostazioni della pagina.',
    'Page deleted': 'Pagina eliminata',
    'pages.delete.confirmIdentity': 'Conferma che sei tu',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Per eliminare subito la pagina serve un accesso recente. Inserisci la tua password.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Non siamo riusciti a confermare che sei tu, quindi non è stato eliminato nulla. Riprova oppure esci e accedi di nuovo.',
    'Deletion cancelled. The Page stays paused.':
        'Eliminazione annullata. La pagina resta in pausa.',
    '{count} posts.zero': '{count} post',
    '{count} posts.one': '{count} post',
    '{count} posts.two': '{count} post',
    '{count} posts.few': '{count} post',
    '{count} posts.many': '{count} post',
    '{count} posts.other': '{count} post',
  },
  'nl': <String, String>{
    'Delete all posts': 'Alle berichten verwijderen',
    'The Page and its followers stay': 'De pagina en de volgers blijven',
    'Delete Page': 'Pagina verwijderen',
    'Posts, followers and contact details. Your account stays.':
        'Berichten, volgers en contactgegevens. Je account blijft.',
    'Delete {posts}?': '{posts} verwijderen?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Ook de reacties en likes eronder verdwijnen. De pagina en {followers} blijven. Dit kan niet ongedaan worden gemaakt.',
    'Delete posts': 'Berichten verwijderen',
    'Posts deleted': 'Berichten verwijderd',
    'Deleting posts': 'Berichten worden verwijderd',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Ze verdwijnen op de achtergrond, meestal binnen enkele minuten. De pagina en {followers} blijven.',
    'Publish your first post': 'Plaats je eerste bericht',
    'pages.delete.goes': 'Verdwijnt',
    'The Page in Content and in search.':
        'De pagina in Inhoud en in de zoekresultaten.',
    '{posts} with photos and recordings.': '{posts} met foto’s en opnames.',
    'Comments and likes under them.': 'De reacties en likes eronder.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} van de pagina en hun meldingen over jouw LIVE-uitzendingen.',
    'The Page\'s contact details.': 'De contactgegevens van de pagina.',
    'pages.delete.stays': 'Blijft',
    'Your account: name, photo and cover.': 'Je account: naam, foto en omslag.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Vrienden, chats, servers, Voice Moments en Yeels.',
    'Exception: reported content': 'Uitzondering: gemelde inhoud',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Gemelde inhoud kunnen we maximaal 90 dagen niet-openbaar bewaren.',
    'You have 30 days to come back': 'Je hebt 30 dagen om terug te komen',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'We verbergen de pagina meteen en verwijderen haar op {date}. Tot dan kun je haar herstellen. Herstellen vereist actief Premium of VIP.',
    'Type the Page name': 'Typ de naam van de pagina',
    'To confirm, type: {name}': 'Typ ter bevestiging: {name}',
    'pages.statusPendingDeletion': 'Wordt verwijderd',
    'The Page will be deleted on {date}':
        'De pagina wordt verwijderd op {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Anderen zien haar niet meer; alleen jij ziet de berichten. Tot dan kun je haar herstellen met berichten en volgers.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Anderen zien haar niet meer. Tot dan kun je haar herstellen met berichten en volgers. Herstellen vereist actief Premium of VIP.',
    'Restore Page': 'Pagina herstellen',
    'Comes back to Content with its posts and followers':
        'Komt terug in Inhoud met berichten en volgers',
    'Page restored': 'Pagina hersteld',
    'Delete now, don\'t wait': 'Nu verwijderen, niet wachten',
    'Without waiting until {date}. This can\'t be undone.':
        'Zonder te wachten tot {date}. Dit kan niet ongedaan worden gemaakt.',
    'Delete the Page now?': 'Pagina nu verwijderen?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Berichten, volgers en contactgegevens worden meteen verwijderd en kunnen niet worden hersteld. Na 7 dagen kun je een nieuwe pagina maken.',
    'Deleting the Page': 'Pagina wordt verwijderd',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Berichten en volgers worden op de achtergrond verwijderd. Je kunt 7 dagen daarna een nieuwe pagina maken.',
    'You can create a new Page after {date}.':
        'Je kunt een nieuwe pagina maken na {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Je pagina wordt over 3 dagen verwijderd. Herstel haar in de pagina-instellingen als je haar wilt houden.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Een nieuwe pagina kan 7 dagen na het verwijderen van de vorige worden gemaakt.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Ik begrijp dat de contactgegevens openbaar zijn. Ze blijven bewaard zolang de pagina gepauzeerd is en worden samen met de pagina verwijderd. Ik kan ze op elk moment wissen.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Je profiel wordt als pagina getoond. Je kunt haar op elk moment pauzeren of verwijderen in de pagina-instellingen.',
    'Page deleted': 'Pagina verwijderd',
    'pages.delete.confirmIdentity': 'Bevestig dat jij het bent',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Om de pagina nu te verwijderen is een recente aanmelding nodig. Voer je wachtwoord in.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'We konden niet bevestigen dat jij het bent, dus er is niets verwijderd. Probeer het opnieuw of meld je af en weer aan.',
    'Deletion cancelled. The Page stays paused.':
        'Verwijdering geannuleerd. De pagina blijft gepauzeerd.',
    '{count} posts.zero': '{count} berichten',
    '{count} posts.one': '{count} bericht',
    '{count} posts.two': '{count} berichten',
    '{count} posts.few': '{count} berichten',
    '{count} posts.many': '{count} berichten',
    '{count} posts.other': '{count} berichten',
  },
  'ro': <String, String>{
    'Delete all posts': 'Șterge toate postările',
    'The Page and its followers stay': 'Pagina și urmăritorii rămân',
    'Delete Page': 'Șterge pagina',
    'Posts, followers and contact details. Your account stays.':
        'Postări, urmăritori și date de contact. Contul tău rămâne.',
    'Delete {posts}?': 'Ștergi {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Dispar și comentariile și aprecierile de sub ele. Pagina și {followers} rămân. Acțiunea nu poate fi anulată.',
    'Delete posts': 'Șterge postările',
    'Posts deleted': 'Postări șterse',
    'Deleting posts': 'Se șterg postările',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Dispar în fundal, de obicei în câteva minute. Pagina și {followers} rămân.',
    'Publish your first post': 'Publică prima ta postare',
    'pages.delete.goes': 'Dispare',
    'The Page in Content and in search.': 'Pagina din Conținut și din căutare.',
    '{posts} with photos and recordings.':
        '{posts} cu fotografii și înregistrări.',
    'Comments and likes under them.': 'Comentariile și aprecierile de sub ele.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ai paginii și notificările lor despre LIVE-urile tale.',
    'The Page\'s contact details.': 'Datele de contact ale paginii.',
    'pages.delete.stays': 'Rămâne',
    'Your account: name, photo and cover.':
        'Contul tău: nume, fotografie și copertă.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Prieteni, conversații, servere, Voice Moments și Yeels.',
    'Exception: reported content': 'Excepție: conținut raportat',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Putem păstra conținutul raportat, nepublic, până la 90 de zile.',
    'You have 30 days to come back': 'Ai 30 de zile să te întorci',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Ascundem pagina imediat și o ștergem pe {date}. Până atunci o poți restaura. Restaurarea necesită Premium sau VIP activ.',
    'Type the Page name': 'Scrie numele paginii',
    'To confirm, type: {name}': 'Pentru confirmare, scrie: {name}',
    'pages.statusPendingDeletion': 'De șters',
    'The Page will be deleted on {date}': 'Pagina va fi ștearsă pe {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Ceilalți nu o mai văd; postările le vezi doar tu. Până atunci o poți restaura împreună cu postările și urmăritorii.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Ceilalți nu o mai văd. Până atunci o poți restaura împreună cu postările și urmăritorii. Restaurarea necesită Premium sau VIP activ.',
    'Restore Page': 'Restaurează pagina',
    'Comes back to Content with its posts and followers':
        'Revine în Conținut cu postările și urmăritorii',
    'Page restored': 'Pagină restaurată',
    'Delete now, don\'t wait': 'Șterge acum, nu aștepta',
    'Without waiting until {date}. This can\'t be undone.':
        'Fără să aștepți până pe {date}. Acțiunea nu poate fi anulată.',
    'Delete the Page now?': 'Ștergi pagina acum?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Postările, urmăritorii și datele de contact sunt șterse imediat și nu pot fi restaurate. Poți crea o pagină nouă după 7 zile.',
    'Deleting the Page': 'Se șterge pagina',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Eliminăm postările și urmăritorii în fundal. Poți crea o pagină nouă la 7 zile după ce se termină.',
    'You can create a new Page after {date}.':
        'Poți crea o pagină nouă după {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Pagina ta va fi ștearsă în 3 zile. Restaureaz-o din setările paginii dacă vrei să o păstrezi.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'O pagină nouă poate fi creată la 7 zile după ștergerea celei anterioare.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Înțeleg că datele de contact vor fi publice. Rămân salvate cât timp pagina este pe pauză și sunt șterse odată cu pagina. Le pot șterge oricând.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profilul tău va apărea ca pagină. O poți pune pe pauză sau șterge oricând din setările paginii.',
    'Page deleted': 'Pagină ștearsă',
    'pages.delete.confirmIdentity': 'Confirmă că ești tu',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Pentru a șterge pagina acum este nevoie de o autentificare recentă. Introdu parola.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nu am putut confirma că ești tu, așa că nu s-a șters nimic. Încearcă din nou sau deconectează-te și conectează-te iar.',
    'Deletion cancelled. The Page stays paused.':
        'Ștergere anulată. Pagina rămâne pe pauză.',
    '{count} posts.zero': '{count} postări',
    '{count} posts.one': '{count} postare',
    '{count} posts.two': '{count} postări',
    '{count} posts.few': '{count} postări',
    '{count} posts.many': '{count} de postări',
    '{count} posts.other': '{count} de postări',
  },
  'tr': <String, String>{
    'Delete all posts': 'Tüm gönderileri sil',
    'The Page and its followers stay': 'Sayfa ve takipçiler kalır',
    'Delete Page': 'Sayfayı sil',
    'Posts, followers and contact details. Your account stays.':
        'Gönderiler, takipçiler ve iletişim bilgileri. Hesabın kalır.',
    'Delete {posts}?': '{posts} silinsin mi?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Altlarındaki yorumlar ve beğeniler de kaybolur. Sayfa ve {followers} kalır. Bu işlem geri alınamaz.',
    'Delete posts': 'Gönderileri sil',
    'Posts deleted': 'Gönderiler silindi',
    'Deleting posts': 'Gönderiler siliniyor',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Arka planda, genellikle birkaç dakika içinde kaybolurlar. Sayfa ve {followers} kalır.',
    'Publish your first post': 'İlk gönderini yayınla',
    'pages.delete.goes': 'Kaybolacak',
    'The Page in Content and in search.': 'İçerik’teki ve aramadaki sayfa.',
    '{posts} with photos and recordings.': 'Fotoğraf ve kayıtlarıyla {posts}.',
    'Comments and likes under them.': 'Altlarındaki yorumlar ve beğeniler.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ve LIVE yayınlarınla ilgili bildirimleri.',
    'The Page\'s contact details.': 'Sayfanın iletişim bilgileri.',
    'pages.delete.stays': 'Kalacak',
    'Your account: name, photo and cover.': 'Hesabın: ad, fotoğraf ve kapak.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Arkadaşlar, sohbetler, sunucular, Voice Moments ve Yeels.',
    'Exception: reported content': 'İstisna: şikâyet edilen içerik',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Şikâyet edilen içeriği herkese açık olmadan 90 güne kadar saklayabiliriz.',
    'You have 30 days to come back': 'Geri dönmek için 30 günün var',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Sayfayı hemen gizleriz ve {date} tarihinde sileriz. O güne kadar geri yükleyebilirsin. Geri yükleme için etkin Premium veya VIP gerekir.',
    'Type the Page name': 'Sayfanın adını yaz',
    'To confirm, type: {name}': 'Onaylamak için şunu yaz: {name}',
    'pages.statusPendingDeletion': 'Silinecek',
    'The Page will be deleted on {date}': 'Sayfa {date} tarihinde silinecek',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Başkaları artık göremiyor; gönderileri yalnızca sen görüyorsun. O güne kadar gönderileri ve takipçileriyle geri yükleyebilirsin.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Başkaları artık göremiyor. O güne kadar gönderileri ve takipçileriyle geri yükleyebilirsin. Geri yükleme için etkin Premium veya VIP gerekir.',
    'Restore Page': 'Sayfayı geri yükle',
    'Comes back to Content with its posts and followers':
        'Gönderileri ve takipçileriyle İçerik’e geri döner',
    'Page restored': 'Sayfa geri yüklendi',
    'Delete now, don\'t wait': 'Şimdi sil, bekleme',
    'Without waiting until {date}. This can\'t be undone.':
        '{date} tarihini beklemeden. Bu işlem geri alınamaz.',
    'Delete the Page now?': 'Sayfa şimdi silinsin mi?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Gönderiler, takipçiler ve iletişim bilgileri hemen silinir ve geri yüklenemez. 7 gün sonra yeni bir sayfa oluşturabilirsin.',
    'Deleting the Page': 'Sayfa siliniyor',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Gönderiler ve takipçiler arka planda kaldırılıyor. İşlem bittikten 7 gün sonra yeni bir sayfa oluşturabilirsin.',
    'You can create a new Page after {date}.':
        '{date} tarihinden sonra yeni bir sayfa oluşturabilirsin.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Sayfan 3 gün içinde silinecek. Kalsın istiyorsan sayfa ayarlarından geri yükle.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Yeni bir sayfa, önceki silindikten 7 gün sonra oluşturulabilir.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'İletişim bilgilerinin herkese açık olacağını anlıyorum. Sayfa duraklatılmışken kayıtlı kalır ve sayfayla birlikte silinir. İstediğim zaman temizleyebilirim.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profilin sayfa olarak görünecek. İstediğin zaman sayfa ayarlarından duraklatabilir veya silebilirsin.',
    'Page deleted': 'Sayfa silindi',
    'pages.delete.confirmIdentity': 'Sen olduğunu doğrula',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Sayfayı şimdi silmek için yeni bir oturum açma gerekir. Şifreni gir.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Sen olduğunu doğrulayamadık, bu yüzden hiçbir şey silinmedi. Tekrar dene ya da çıkış yapıp yeniden giriş yap.',
    'Deletion cancelled. The Page stays paused.':
        'Silme iptal edildi. Sayfa duraklatılmış olarak kalıyor.',
    '{count} posts.zero': '{count} gönderi',
    '{count} posts.one': '{count} gönderi',
    '{count} posts.two': '{count} gönderi',
    '{count} posts.few': '{count} gönderi',
    '{count} posts.many': '{count} gönderi',
    '{count} posts.other': '{count} gönderi',
  },
  'el': <String, String>{
    'Delete all posts': 'Διαγραφή όλων των αναρτήσεων',
    'The Page and its followers stay': 'Η σελίδα και οι ακόλουθοι μένουν',
    'Delete Page': 'Διαγραφή σελίδας',
    'Posts, followers and contact details. Your account stays.':
        'Αναρτήσεις, ακόλουθοι και στοιχεία επικοινωνίας. Ο λογαριασμός σου μένει.',
    'Delete {posts}?': 'Διαγραφή: {posts};',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Θα χαθούν και τα σχόλια και τα «μου αρέσει» κάτω από αυτές. Η σελίδα και {followers} μένουν. Η ενέργεια δεν αναιρείται.',
    'Delete posts': 'Διαγραφή αναρτήσεων',
    'Posts deleted': 'Οι αναρτήσεις διαγράφηκαν',
    'Deleting posts': 'Διαγραφή αναρτήσεων σε εξέλιξη',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Χάνονται στο παρασκήνιο, συνήθως μέσα σε λίγα λεπτά. Η σελίδα και {followers} μένουν.',
    'Publish your first post': 'Δημοσίευσε την πρώτη σου ανάρτηση',
    'pages.delete.goes': 'Θα χαθεί',
    'The Page in Content and in search.':
        'Η σελίδα στο Περιεχόμενο και στην αναζήτηση.',
    '{posts} with photos and recordings.':
        '{posts} με φωτογραφίες και ηχογραφήσεις.',
    'Comments and likes under them.':
        'Τα σχόλια και τα «μου αρέσει» κάτω από αυτές.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} της σελίδας και οι ειδοποιήσεις τους για τα LIVE σου.',
    'The Page\'s contact details.': 'Τα στοιχεία επικοινωνίας της σελίδας.',
    'pages.delete.stays': 'Μένει',
    'Your account: name, photo and cover.':
        'Ο λογαριασμός σου: όνομα, φωτογραφία και εξώφυλλο.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Φίλοι, συνομιλίες, διακομιστές, Voice Moments και Yeels.',
    'Exception: reported content': 'Εξαίρεση: περιεχόμενο που αναφέρθηκε',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Το περιεχόμενο που αναφέρθηκε μπορεί να διατηρηθεί, μη δημόσια, έως 90 ημέρες.',
    'You have 30 days to come back': 'Έχεις 30 ημέρες για να επιστρέψεις',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Κρύβουμε τη σελίδα αμέσως και τη διαγράφουμε στις {date}. Μέχρι τότε μπορείς να την επαναφέρεις. Η επαναφορά απαιτεί ενεργό Premium ή VIP.',
    'Type the Page name': 'Γράψε το όνομα της σελίδας',
    'To confirm, type: {name}': 'Για επιβεβαίωση, γράψε: {name}',
    'pages.statusPendingDeletion': 'Προς διαγραφή',
    'The Page will be deleted on {date}': 'Η σελίδα θα διαγραφεί στις {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Οι άλλοι δεν τη βλέπουν πια· τις αναρτήσεις τις βλέπεις μόνο εσύ. Μέχρι τότε μπορείς να την επαναφέρεις με τις αναρτήσεις και τους ακολούθους της.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Οι άλλοι δεν τη βλέπουν πια. Μέχρι τότε μπορείς να την επαναφέρεις με τις αναρτήσεις και τους ακολούθους της. Η επαναφορά απαιτεί ενεργό Premium ή VIP.',
    'Restore Page': 'Επαναφορά σελίδας',
    'Comes back to Content with its posts and followers':
        'Επιστρέφει στο Περιεχόμενο με τις αναρτήσεις και τους ακολούθους της',
    'Page restored': 'Η σελίδα επαναφέρθηκε',
    'Delete now, don\'t wait': 'Διαγραφή τώρα, χωρίς αναμονή',
    'Without waiting until {date}. This can\'t be undone.':
        'Χωρίς αναμονή έως τις {date}. Η ενέργεια δεν αναιρείται.',
    'Delete the Page now?': 'Διαγραφή της σελίδας τώρα;',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Οι αναρτήσεις, οι ακόλουθοι και τα στοιχεία επικοινωνίας διαγράφονται αμέσως και δεν επαναφέρονται. Μπορείς να δημιουργήσεις νέα σελίδα μετά από 7 ημέρες.',
    'Deleting the Page': 'Διαγραφή σελίδας σε εξέλιξη',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Οι αναρτήσεις και οι ακόλουθοι αφαιρούνται στο παρασκήνιο. Μπορείς να δημιουργήσεις νέα σελίδα 7 ημέρες μετά την ολοκλήρωση.',
    'You can create a new Page after {date}.':
        'Μπορείς να δημιουργήσεις νέα σελίδα μετά τις {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Η σελίδα σου θα διαγραφεί σε 3 ημέρες. Επανάφερέ την από τις ρυθμίσεις σελίδας αν θέλεις να την κρατήσεις.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Νέα σελίδα μπορεί να δημιουργηθεί 7 ημέρες μετά τη διαγραφή της προηγούμενης.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Κατανοώ ότι τα στοιχεία επικοινωνίας θα είναι δημόσια. Παραμένουν αποθηκευμένα όσο η σελίδα είναι σε παύση και διαγράφονται μαζί με τη σελίδα. Μπορώ να τα σβήσω όποτε θέλω.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Το προφίλ σου θα εμφανίζεται ως σελίδα. Μπορείς να τη θέσεις σε παύση ή να τη διαγράψεις όποτε θέλεις από τις ρυθμίσεις σελίδας.',
    'Page deleted': 'Η σελίδα διαγράφηκε',
    'pages.delete.confirmIdentity': 'Επιβεβαίωσε ότι είσαι εσύ',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Για να διαγραφεί η σελίδα τώρα χρειάζεται πρόσφατη σύνδεση. Γράψε τον κωδικό σου.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Δεν μπορέσαμε να επιβεβαιώσουμε ότι είσαι εσύ, οπότε δεν διαγράφηκε τίποτα. Δοκίμασε ξανά ή αποσυνδέσου και συνδέσου πάλι.',
    'Deletion cancelled. The Page stays paused.':
        'Η διαγραφή ακυρώθηκε. Η σελίδα παραμένει σε παύση.',
    '{count} posts.zero': '{count} αναρτήσεις',
    '{count} posts.one': '{count} ανάρτηση',
    '{count} posts.two': '{count} αναρτήσεις',
    '{count} posts.few': '{count} αναρτήσεις',
    '{count} posts.many': '{count} αναρτήσεις',
    '{count} posts.other': '{count} αναρτήσεις',
  },
  'hu': <String, String>{
    'Delete all posts': 'Összes bejegyzés törlése',
    'The Page and its followers stay': 'Az oldal és a követők megmaradnak',
    'Delete Page': 'Oldal törlése',
    'Posts, followers and contact details. Your account stays.':
        'Bejegyzések, követők és elérhetőségek. A fiókod megmarad.',
    'Delete {posts}?': '{posts} törlése?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Az alattuk lévő hozzászólások és kedvelések is eltűnnek. Az oldal és {followers} megmarad. Ez nem vonható vissza.',
    'Delete posts': 'Bejegyzések törlése',
    'Posts deleted': 'Bejegyzések törölve',
    'Deleting posts': 'Bejegyzések törlése folyamatban',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'A háttérben tűnnek el, általában néhány percen belül. Az oldal és {followers} megmarad.',
    'Publish your first post': 'Tedd közzé az első bejegyzésed',
    'pages.delete.goes': 'Eltűnik',
    'The Page in Content and in search.':
        'Az oldal a Tartalomban és a keresésben.',
    '{posts} with photos and recordings.': '{posts} fotókkal és felvételekkel.',
    'Comments and likes under them.':
        'Az alattuk lévő hozzászólások és kedvelések.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} az oldalon, és az értesítéseik a LIVE adásaidról.',
    'The Page\'s contact details.': 'Az oldal elérhetőségei.',
    'pages.delete.stays': 'Megmarad',
    'Your account: name, photo and cover.': 'A fiókod: név, fotó és borító.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Barátok, csevegések, szerverek, Voice Moments és Yeels.',
    'Exception: reported content': 'Kivétel: bejelentett tartalom',
    'We may keep reported content, not publicly, for up to 90 days.':
        'A bejelentett tartalmat nem nyilvánosan legfeljebb 90 napig megőrizhetjük.',
    'You have 30 days to come back': '30 napod van visszatérni',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Az oldalt azonnal elrejtjük, és ekkor töröljük: {date}. Addig visszaállíthatod. A visszaállításhoz aktív Premium vagy VIP kell.',
    'Type the Page name': 'Írd be az oldal nevét',
    'To confirm, type: {name}': 'A megerősítéshez írd be: {name}',
    'pages.statusPendingDeletion': 'Törlésre vár',
    'The Page will be deleted on {date}': 'Az oldal törlésének napja: {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Mások már nem látják; a bejegyzéseket csak te látod. Addig visszaállíthatod a bejegyzésekkel és a követőkkel együtt.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Mások már nem látják. Addig visszaállíthatod a bejegyzésekkel és a követőkkel együtt. A visszaállításhoz aktív Premium vagy VIP kell.',
    'Restore Page': 'Oldal visszaállítása',
    'Comes back to Content with its posts and followers':
        'Visszakerül a Tartalomba a bejegyzésekkel és a követőkkel',
    'Page restored': 'Oldal visszaállítva',
    'Delete now, don\'t wait': 'Törlés most, várakozás nélkül',
    'Without waiting until {date}. This can\'t be undone.':
        'Nem várunk eddig: {date}. Ez nem vonható vissza.',
    'Delete the Page now?': 'Törlöd most az oldalt?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'A bejegyzések, a követők és az elérhetőségek azonnal törlődnek, és nem állíthatók vissza. Új oldalt 7 nap múlva hozhatsz létre.',
    'Deleting the Page': 'Az oldal törlése folyamatban',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'A bejegyzéseket és a követőket a háttérben távolítjuk el. Új oldalt a befejezés után 7 nappal hozhatsz létre.',
    'You can create a new Page after {date}.':
        'Új oldalt ezután hozhatsz létre: {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Az oldalad 3 nap múlva törlődik. Állítsd vissza az oldal beállításaiban, ha meg szeretnéd tartani.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Új oldal az előző törlése után 7 nappal hozható létre.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Tudomásul veszem, hogy az elérhetőségek nyilvánosak lesznek. Mentve maradnak, amíg az oldal szünetel, és az oldallal együtt törlődnek. Bármikor törölhetem őket.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'A profilod oldalként jelenik meg. Az oldal beállításaiban bármikor szüneteltetheted vagy törölheted.',
    'Page deleted': 'Oldal törölve',
    'pages.delete.confirmIdentity': 'Erősítsd meg, hogy te vagy az',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Az oldal azonnali törléséhez friss bejelentkezés kell. Add meg a jelszavad.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nem tudtuk megerősíteni, hogy te vagy az, ezért semmi sem törlődött. Próbáld újra, vagy jelentkezz ki, majd be újra.',
    'Deletion cancelled. The Page stays paused.':
        'Törlés visszavonva. Az oldal szüneteltetve marad.',
    '{count} posts.zero': '{count} bejegyzés',
    '{count} posts.one': '{count} bejegyzés',
    '{count} posts.two': '{count} bejegyzés',
    '{count} posts.few': '{count} bejegyzés',
    '{count} posts.many': '{count} bejegyzés',
    '{count} posts.other': '{count} bejegyzés',
  },
  'uk': <String, String>{
    'Delete all posts': 'Видалити всі дописи',
    'The Page and its followers stay': 'Сторінка й читачі залишаться',
    'Delete Page': 'Видалити сторінку',
    'Posts, followers and contact details. Your account stays.':
        'Дописи, читачі та контактні дані. Обліковий запис залишиться.',
    'Delete {posts}?': 'Видалити {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Зникнуть також коментарі й уподобання під ними. Сторінка та {followers} залишаться. Цю дію не можна скасувати.',
    'Delete posts': 'Видалити дописи',
    'Posts deleted': 'Дописи видалено',
    'Deleting posts': 'Дописи видаляються',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Вони зникають у фоні, зазвичай за кілька хвилин. Сторінка та {followers} залишаться.',
    'Publish your first post': 'Опублікуйте перший допис',
    'pages.delete.goes': 'Зникне',
    'The Page in Content and in search.': 'Сторінка в «Контенті» та в пошуку.',
    '{posts} with photos and recordings.': '{posts} із фото та записами.',
    'Comments and likes under them.': 'Коментарі й уподобання під ними.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} сторінки та їхні сповіщення про ваші LIVE.',
    'The Page\'s contact details.': 'Контактні дані сторінки.',
    'pages.delete.stays': 'Залишиться',
    'Your account: name, photo and cover.':
        'Ваш обліковий запис: ім’я, фото й обкладинка.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Друзі, чати, сервери, Voice Moments і Yeels.',
    'Exception: reported content': 'Виняток: контент, на який поскаржилися',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Контент, на який поскаржилися, ми можемо зберігати непублічно до 90 днів.',
    'You have 30 days to come back': 'У вас є 30 днів, щоб повернутися',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Ми одразу приховаємо сторінку й видалимо її {date}. До цього дня її можна відновити. Для відновлення потрібен активний Premium або VIP.',
    'Type the Page name': 'Введіть назву сторінки',
    'To confirm, type: {name}': 'Щоб підтвердити, введіть: {name}',
    'pages.statusPendingDeletion': 'До видалення',
    'The Page will be deleted on {date}': 'Сторінку буде видалено {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Інші її вже не бачать, дописи бачите лише ви. До цього дня її можна відновити разом із дописами й читачами.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Інші її вже не бачать. До цього дня її можна відновити разом із дописами й читачами. Для відновлення потрібен активний Premium або VIP.',
    'Restore Page': 'Відновити сторінку',
    'Comes back to Content with its posts and followers':
        'Повернеться в «Контент» разом із дописами й читачами',
    'Page restored': 'Сторінку відновлено',
    'Delete now, don\'t wait': 'Видалити зараз, не чекати',
    'Without waiting until {date}. This can\'t be undone.':
        'Не чекаючи до {date}. Цю дію не можна скасувати.',
    'Delete the Page now?': 'Видалити сторінку зараз?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Дописи, читачів і контактні дані буде видалено одразу, відновити їх не вдасться. Нову сторінку можна створити через 7 днів.',
    'Deleting the Page': 'Сторінка видаляється',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Дописи й читачі видаляються у фоні. Нову сторінку можна створити через 7 днів після завершення.',
    'You can create a new Page after {date}.':
        'Нову сторінку можна створити після {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Вашу сторінку буде видалено через 3 дні. Відновіть її в налаштуваннях сторінки, якщо хочете її зберегти.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Нову сторінку можна створити через 7 днів після видалення попередньої.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Я розумію, що контактні дані будуть публічними. Вони зберігаються, поки сторінку призупинено, і видаляються разом зі сторінкою. Я можу стерти їх будь-коли.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Ваш профіль відображатиметься як сторінка. Її можна будь-коли призупинити або видалити в налаштуваннях сторінки.',
    'Page deleted': 'Сторінку видалено',
    'pages.delete.confirmIdentity': 'Підтвердьте, що це ви',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Щоб видалити сторінку зараз, потрібен нещодавній вхід. Введіть пароль.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Не вдалося підтвердити, що це ви, тому нічого не видалено. Спробуйте ще раз або вийдіть і ввійдіть знову.',
    'Deletion cancelled. The Page stays paused.':
        'Видалення скасовано. Сторінка залишається призупиненою.',
    '{count} posts.zero': '{count} дописів',
    '{count} posts.one': '{count} допис',
    '{count} posts.two': '{count} дописи',
    '{count} posts.few': '{count} дописи',
    '{count} posts.many': '{count} дописів',
    '{count} posts.other': '{count} дописа',
  },
  'ru': <String, String>{
    'Delete all posts': 'Удалить все посты',
    'The Page and its followers stay': 'Страница и подписчики останутся',
    'Delete Page': 'Удалить страницу',
    'Posts, followers and contact details. Your account stays.':
        'Посты, подписчики и контактные данные. Аккаунт останется.',
    'Delete {posts}?': 'Удалить {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Исчезнут также комментарии и лайки под ними. Страница и {followers} останутся. Это действие нельзя отменить.',
    'Delete posts': 'Удалить посты',
    'Posts deleted': 'Посты удалены',
    'Deleting posts': 'Посты удаляются',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Они исчезают в фоне, обычно за несколько минут. Страница и {followers} останутся.',
    'Publish your first post': 'Опубликуйте первый пост',
    'pages.delete.goes': 'Исчезнет',
    'The Page in Content and in search.': 'Страница в «Контенте» и в поиске.',
    '{posts} with photos and recordings.': '{posts} с фото и записями.',
    'Comments and likes under them.': 'Комментарии и лайки под ними.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} страницы и их уведомления о ваших LIVE.',
    'The Page\'s contact details.': 'Контактные данные страницы.',
    'pages.delete.stays': 'Останется',
    'Your account: name, photo and cover.': 'Ваш аккаунт: имя, фото и обложка.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Друзья, чаты, серверы, Voice Moments и Yeels.',
    'Exception: reported content':
        'Исключение: контент, на который пожаловались',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Контент, на который пожаловались, мы можем хранить непублично до 90 дней.',
    'You have 30 days to come back': 'У вас есть 30 дней, чтобы вернуться',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Мы сразу скроем страницу и удалим её {date}. До этого дня её можно восстановить. Для восстановления нужен активный Premium или VIP.',
    'Type the Page name': 'Введите название страницы',
    'To confirm, type: {name}': 'Чтобы подтвердить, введите: {name}',
    'pages.statusPendingDeletion': 'К удалению',
    'The Page will be deleted on {date}': 'Страница будет удалена {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Другие её уже не видят, посты видите только вы. До этого дня её можно восстановить вместе с постами и подписчиками.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Другие её уже не видят. До этого дня её можно восстановить вместе с постами и подписчиками. Для восстановления нужен активный Premium или VIP.',
    'Restore Page': 'Восстановить страницу',
    'Comes back to Content with its posts and followers':
        'Вернётся в «Контент» вместе с постами и подписчиками',
    'Page restored': 'Страница восстановлена',
    'Delete now, don\'t wait': 'Удалить сейчас, не ждать',
    'Without waiting until {date}. This can\'t be undone.':
        'Не дожидаясь {date}. Это действие нельзя отменить.',
    'Delete the Page now?': 'Удалить страницу сейчас?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Посты, подписчики и контактные данные будут удалены сразу, восстановить их не получится. Новую страницу можно создать через 7 дней.',
    'Deleting the Page': 'Страница удаляется',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Посты и подписчики удаляются в фоне. Новую страницу можно создать через 7 дней после завершения.',
    'You can create a new Page after {date}.':
        'Новую страницу можно создать после {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Ваша страница будет удалена через 3 дня. Восстановите её в настройках страницы, если хотите её сохранить.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Новую страницу можно создать через 7 дней после удаления предыдущей.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Я понимаю, что контактные данные будут публичными. Они хранятся, пока страница приостановлена, и удаляются вместе со страницей. Я могу стереть их в любой момент.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Ваш профиль будет отображаться как страница. Её можно в любой момент приостановить или удалить в настройках страницы.',
    'Page deleted': 'Страница удалена',
    'pages.delete.confirmIdentity': 'Подтвердите, что это вы',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Чтобы удалить страницу сейчас, нужен недавний вход. Введите пароль.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Не удалось подтвердить, что это вы, поэтому ничего не удалено. Попробуйте ещё раз или выйдите и войдите снова.',
    'Deletion cancelled. The Page stays paused.':
        'Удаление отменено. Страница остаётся приостановленной.',
    '{count} posts.zero': '{count} постов',
    '{count} posts.one': '{count} пост',
    '{count} posts.two': '{count} поста',
    '{count} posts.few': '{count} поста',
    '{count} posts.many': '{count} постов',
    '{count} posts.other': '{count} поста',
  },
  'cs': <String, String>{
    'Delete all posts': 'Smazat všechny příspěvky',
    'The Page and its followers stay': 'Stránka a sledující zůstanou',
    'Delete Page': 'Smazat stránku',
    'Posts, followers and contact details. Your account stays.':
        'Příspěvky, sledující a kontakt. Účet ti zůstane.',
    'Delete {posts}?': 'Smazat {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Zmizí i komentáře a lajky pod nimi. Stránka a {followers} zůstanou. Tohle nejde vrátit zpět.',
    'Delete posts': 'Smazat příspěvky',
    'Posts deleted': 'Příspěvky smazány',
    'Deleting posts': 'Příspěvky se mažou',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Mizí na pozadí, obvykle během několika minut. Stránka a {followers} zůstanou.',
    'Publish your first post': 'Zveřejni první příspěvek',
    'pages.delete.goes': 'Zmizí',
    'The Page in Content and in search.': 'Stránka v Obsahu a ve vyhledávání.',
    '{posts} with photos and recordings.': '{posts} s fotkami a nahrávkami.',
    'Comments and likes under them.': 'Komentáře a lajky pod nimi.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} stránky a jejich oznámení o tvých LIVE.',
    'The Page\'s contact details.': 'Kontaktní údaje stránky.',
    'pages.delete.stays': 'Zůstane',
    'Your account: name, photo and cover.':
        'Tvůj účet: jméno, fotka a titulní obrázek.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Přátelé, chaty, servery, Voice Moments a Yeels.',
    'Exception: reported content': 'Výjimka: nahlášený obsah',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Nahlášený obsah můžeme neveřejně uchovávat až 90 dní.',
    'You have 30 days to come back': 'Máš 30 dní na návrat',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Stránku hned skryjeme a smažeme ji {date}. Do té doby ji můžeš obnovit. Obnovení vyžaduje aktivní Premium nebo VIP.',
    'Type the Page name': 'Napiš název stránky',
    'To confirm, type: {name}': 'Pro potvrzení napiš: {name}',
    'pages.statusPendingDeletion': 'Ke smazání',
    'The Page will be deleted on {date}': 'Stránka bude smazána {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Ostatní ji už nevidí, příspěvky vidíš jen ty. Do té doby ji můžeš obnovit i s příspěvky a sledujícími.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Ostatní ji už nevidí. Do té doby ji můžeš obnovit i s příspěvky a sledujícími. Obnovení vyžaduje aktivní Premium nebo VIP.',
    'Restore Page': 'Obnovit stránku',
    'Comes back to Content with its posts and followers':
        'Vrátí se do Obsahu i s příspěvky a sledujícími',
    'Page restored': 'Stránka obnovena',
    'Delete now, don\'t wait': 'Smazat hned, nečekat',
    'Without waiting until {date}. This can\'t be undone.':
        'Bez čekání na {date}. Tohle nejde vrátit zpět.',
    'Delete the Page now?': 'Smazat stránku hned?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Příspěvky, sledující a kontaktní údaje smažeme hned a nepůjdou obnovit. Novou stránku můžeš založit po 7 dnech.',
    'Deleting the Page': 'Stránka se maže',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Příspěvky a sledující odstraňujeme na pozadí. Novou stránku můžeš založit 7 dní po dokončení.',
    'You can create a new Page after {date}.':
        'Novou stránku můžeš založit po {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Tvoje stránka bude za 3 dny smazána. Pokud si ji chceš nechat, obnov ji v nastavení stránky.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Novou stránku lze založit 7 dní po smazání té předchozí.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Rozumím, že kontaktní údaje budou veřejné. Zůstávají uložené, dokud je stránka pozastavená, a smažou se spolu se stránkou. Můžu je kdykoli vymazat.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Tvůj profil se zobrazí jako stránka. V nastavení stránky ji můžeš kdykoli pozastavit nebo smazat.',
    'Page deleted': 'Stránka smazána',
    'pages.delete.confirmIdentity': 'Potvrď, že jsi to ty',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'K okamžitému smazání stránky je potřeba čerstvé přihlášení. Zadej heslo.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nepodařilo se potvrdit, že jsi to ty, takže se nic nesmazalo. Zkus to znovu, nebo se odhlas a přihlas znovu.',
    'Deletion cancelled. The Page stays paused.':
        'Smazání zrušeno. Stránka zůstává pozastavená.',
    '{count} posts.zero': '{count} příspěvků',
    '{count} posts.one': '{count} příspěvek',
    '{count} posts.two': '{count} příspěvky',
    '{count} posts.few': '{count} příspěvky',
    '{count} posts.many': '{count} příspěvku',
    '{count} posts.other': '{count} příspěvků',
  },
  'sk': <String, String>{
    'Delete all posts': 'Odstrániť všetky príspevky',
    'The Page and its followers stay': 'Stránka a sledovatelia zostanú',
    'Delete Page': 'Odstrániť stránku',
    'Posts, followers and contact details. Your account stays.':
        'Príspevky, sledovatelia a kontakt. Účet ti zostane.',
    'Delete {posts}?': 'Odstrániť {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Zmiznú aj komentáre a lajky pod nimi. Stránka a {followers} zostanú. Toto sa nedá vrátiť späť.',
    'Delete posts': 'Odstrániť príspevky',
    'Posts deleted': 'Príspevky odstránené',
    'Deleting posts': 'Príspevky sa odstraňujú',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Miznú na pozadí, zvyčajne do niekoľkých minút. Stránka a {followers} zostanú.',
    'Publish your first post': 'Zverejni prvý príspevok',
    'pages.delete.goes': 'Zmizne',
    'The Page in Content and in search.': 'Stránka v Obsahu a vo vyhľadávaní.',
    '{posts} with photos and recordings.': '{posts} s fotkami a nahrávkami.',
    'Comments and likes under them.': 'Komentáre a lajky pod nimi.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} stránky a ich oznámenia o tvojich LIVE.',
    'The Page\'s contact details.': 'Kontaktné údaje stránky.',
    'pages.delete.stays': 'Zostane',
    'Your account: name, photo and cover.':
        'Tvoj účet: meno, fotka a titulný obrázok.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Priatelia, čety, servery, Voice Moments a Yeels.',
    'Exception: reported content': 'Výnimka: nahlásený obsah',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Nahlásený obsah môžeme neverejne uchovávať až 90 dní.',
    'You have 30 days to come back': 'Máš 30 dní na návrat',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Stránku hneď skryjeme a odstránime ju {date}. Dovtedy ju môžeš obnoviť. Obnovenie vyžaduje aktívne Premium alebo VIP.',
    'Type the Page name': 'Napíš názov stránky',
    'To confirm, type: {name}': 'Na potvrdenie napíš: {name}',
    'pages.statusPendingDeletion': 'Na odstránenie',
    'The Page will be deleted on {date}': 'Stránka bude odstránená {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Ostatní ju už nevidia, príspevky vidíš len ty. Dovtedy ju môžeš obnoviť aj s príspevkami a sledovateľmi.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Ostatní ju už nevidia. Dovtedy ju môžeš obnoviť aj s príspevkami a sledovateľmi. Obnovenie vyžaduje aktívne Premium alebo VIP.',
    'Restore Page': 'Obnoviť stránku',
    'Comes back to Content with its posts and followers':
        'Vráti sa do Obsahu aj s príspevkami a sledovateľmi',
    'Page restored': 'Stránka obnovená',
    'Delete now, don\'t wait': 'Odstrániť hneď, nečakať',
    'Without waiting until {date}. This can\'t be undone.':
        'Bez čakania na {date}. Toto sa nedá vrátiť späť.',
    'Delete the Page now?': 'Odstrániť stránku hneď?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Príspevky, sledovateľov a kontaktné údaje odstránime hneď a nebude ich možné obnoviť. Novú stránku môžeš založiť po 7 dňoch.',
    'Deleting the Page': 'Stránka sa odstraňuje',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Príspevky a sledovateľov odstraňujeme na pozadí. Novú stránku môžeš založiť 7 dní po dokončení.',
    'You can create a new Page after {date}.':
        'Novú stránku môžeš založiť po {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Tvoja stránka bude o 3 dni odstránená. Ak si ju chceš nechať, obnov ju v nastaveniach stránky.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Novú stránku možno založiť 7 dní po odstránení predchádzajúcej.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Rozumiem, že kontaktné údaje budú verejné. Zostávajú uložené, kým je stránka pozastavená, a odstránia sa spolu so stránkou. Môžem ich kedykoľvek vymazať.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Tvoj profil sa zobrazí ako stránka. V nastaveniach stránky ju môžeš kedykoľvek pozastaviť alebo odstrániť.',
    'Page deleted': 'Stránka odstránená',
    'pages.delete.confirmIdentity': 'Potvrď, že si to ty',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Na okamžité odstránenie stránky je potrebné čerstvé prihlásenie. Zadaj heslo.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nepodarilo sa potvrdiť, že si to ty, takže sa nič neodstránilo. Skús to znova alebo sa odhlás a znova prihlás.',
    'Deletion cancelled. The Page stays paused.':
        'Odstránenie zrušené. Stránka zostáva pozastavená.',
    '{count} posts.zero': '{count} príspevkov',
    '{count} posts.one': '{count} príspevok',
    '{count} posts.two': '{count} príspevky',
    '{count} posts.few': '{count} príspevky',
    '{count} posts.many': '{count} príspevku',
    '{count} posts.other': '{count} príspevkov',
  },
  'bg': <String, String>{
    'Delete all posts': 'Изтрий всички публикации',
    'The Page and its followers stay': 'Страницата и последователите остават',
    'Delete Page': 'Изтрий страницата',
    'Posts, followers and contact details. Your account stays.':
        'Публикации, последователи и данни за контакт. Акаунтът ти остава.',
    'Delete {posts}?': 'Да се изтрият ли {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Ще изчезнат и коментарите и харесванията под тях. Страницата и {followers} остават. Това не може да се отмени.',
    'Delete posts': 'Изтрий публикациите',
    'Posts deleted': 'Публикациите са изтрити',
    'Deleting posts': 'Публикациите се изтриват',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Изчезват на заден план, обикновено за няколко минути. Страницата и {followers} остават.',
    'Publish your first post': 'Публикувай първата си публикация',
    'pages.delete.goes': 'Изчезва',
    'The Page in Content and in search.':
        'Страницата в „Съдържание“ и в търсенето.',
    '{posts} with photos and recordings.': '{posts} със снимки и записи.',
    'Comments and likes under them.': 'Коментарите и харесванията под тях.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} на страницата и известията им за твоите LIVE.',
    'The Page\'s contact details.': 'Данните за контакт на страницата.',
    'pages.delete.stays': 'Остава',
    'Your account: name, photo and cover.':
        'Акаунтът ти: име, снимка и корица.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Приятели, чатове, сървъри, Voice Moments и Yeels.',
    'Exception: reported content': 'Изключение: докладвано съдържание',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Докладваното съдържание може да се пази непублично до 90 дни.',
    'You have 30 days to come back': 'Имаш 30 дни да се върнеш',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Скриваме страницата веднага и я изтриваме на {date}. Дотогава можеш да я възстановиш. Възстановяването изисква активен Premium или VIP.',
    'Type the Page name': 'Въведи името на страницата',
    'To confirm, type: {name}': 'За потвърждение въведи: {name}',
    'pages.statusPendingDeletion': 'За изтриване',
    'The Page will be deleted on {date}':
        'Страницата ще бъде изтрита на {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Другите вече не я виждат, публикациите виждаш само ти. Дотогава можеш да я възстановиш заедно с публикациите и последователите.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Другите вече не я виждат. Дотогава можеш да я възстановиш заедно с публикациите и последователите. Възстановяването изисква активен Premium или VIP.',
    'Restore Page': 'Възстанови страницата',
    'Comes back to Content with its posts and followers':
        'Връща се в „Съдържание“ заедно с публикациите и последователите',
    'Page restored': 'Страницата е възстановена',
    'Delete now, don\'t wait': 'Изтрий сега, без чакане',
    'Without waiting until {date}. This can\'t be undone.':
        'Без да чакаш до {date}. Това не може да се отмени.',
    'Delete the Page now?': 'Да се изтрие ли страницата сега?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Публикациите, последователите и данните за контакт се изтриват веднага и не могат да се възстановят. Нова страница можеш да създадеш след 7 дни.',
    'Deleting the Page': 'Страницата се изтрива',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Публикациите и последователите се премахват на заден план. Нова страница можеш да създадеш 7 дни след приключването.',
    'You can create a new Page after {date}.':
        'Нова страница можеш да създадеш след {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Страницата ти ще бъде изтрита след 3 дни. Възстанови я от настройките на страницата, ако искаш да я запазиш.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Нова страница може да се създаде 7 дни след изтриването на предишната.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Разбирам, че данните за контакт ще бъдат публични. Остават запазени, докато страницата е на пауза, и се изтриват заедно със страницата. Мога да ги изчистя по всяко време.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Профилът ти ще се показва като страница. Можеш да я поставиш на пауза или да я изтриеш по всяко време от настройките на страницата.',
    'Page deleted': 'Страницата е изтрита',
    'pages.delete.confirmIdentity': 'Потвърди, че си ти',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'За да изтриеш страницата сега, е нужно скорошно влизане. Въведи паролата си.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Не успяхме да потвърдим, че си ти, затова нищо не е изтрито. Опитай отново или излез и влез пак.',
    'Deletion cancelled. The Page stays paused.':
        'Изтриването е отменено. Страницата остава на пауза.',
    '{count} posts.zero': '{count} публикации',
    '{count} posts.one': '{count} публикация',
    '{count} posts.two': '{count} публикации',
    '{count} posts.few': '{count} публикации',
    '{count} posts.many': '{count} публикации',
    '{count} posts.other': '{count} публикации',
  },
  'hr': <String, String>{
    'Delete all posts': 'Izbriši sve objave',
    'The Page and its followers stay': 'Stranica i pratitelji ostaju',
    'Delete Page': 'Izbriši stranicu',
    'Posts, followers and contact details. Your account stays.':
        'Objave, pratitelji i kontakt. Račun ti ostaje.',
    'Delete {posts}?': 'Izbrisati {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Nestat će i komentari i lajkovi ispod njih. Stranica i {followers} ostaju. Ovo se ne može poništiti.',
    'Delete posts': 'Izbriši objave',
    'Posts deleted': 'Objave izbrisane',
    'Deleting posts': 'Objave se brišu',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Nestaju u pozadini, obično za nekoliko minuta. Stranica i {followers} ostaju.',
    'Publish your first post': 'Objavi prvu objavu',
    'pages.delete.goes': 'Nestaje',
    'The Page in Content and in search.':
        'Stranica u Sadržaju i u pretraživanju.',
    '{posts} with photos and recordings.':
        '{posts} s fotografijama i snimkama.',
    'Comments and likes under them.': 'Komentari i lajkovi ispod njih.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} stranice i njihove obavijesti o tvojim LIVE prijenosima.',
    'The Page\'s contact details.': 'Kontaktni podaci stranice.',
    'pages.delete.stays': 'Ostaje',
    'Your account: name, photo and cover.':
        'Tvoj račun: ime, fotografija i naslovnica.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Prijatelji, razgovori, serveri, Voice Moments i Yeels.',
    'Exception: reported content': 'Iznimka: prijavljeni sadržaj',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Prijavljeni sadržaj možemo čuvati, nejavno, do 90 dana.',
    'You have 30 days to come back': 'Imaš 30 dana za povratak',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Stranicu odmah skrivamo i brišemo je {date}. Do tada je možeš vratiti. Za vraćanje je potreban aktivan Premium ili VIP.',
    'Type the Page name': 'Upiši naziv stranice',
    'To confirm, type: {name}': 'Za potvrdu upiši: {name}',
    'pages.statusPendingDeletion': 'Za brisanje',
    'The Page will be deleted on {date}': 'Stranica će biti izbrisana {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Drugi je više ne vide, objave vidiš samo ti. Do tada je možeš vratiti zajedno s objavama i pratiteljima.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Drugi je više ne vide. Do tada je možeš vratiti zajedno s objavama i pratiteljima. Za vraćanje je potreban aktivan Premium ili VIP.',
    'Restore Page': 'Vrati stranicu',
    'Comes back to Content with its posts and followers':
        'Vraća se u Sadržaj zajedno s objavama i pratiteljima',
    'Page restored': 'Stranica vraćena',
    'Delete now, don\'t wait': 'Izbriši sada, bez čekanja',
    'Without waiting until {date}. This can\'t be undone.':
        'Bez čekanja do {date}. Ovo se ne može poništiti.',
    'Delete the Page now?': 'Izbrisati stranicu sada?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Objave, pratitelji i kontaktni podaci brišu se odmah i ne mogu se vratiti. Novu stranicu možeš izraditi nakon 7 dana.',
    'Deleting the Page': 'Stranica se briše',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Objave i pratitelje uklanjamo u pozadini. Novu stranicu možeš izraditi 7 dana nakon završetka.',
    'You can create a new Page after {date}.':
        'Novu stranicu možeš izraditi nakon {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Tvoja stranica bit će izbrisana za 3 dana. Vrati je u postavkama stranice ako je želiš zadržati.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Nova stranica može se izraditi 7 dana nakon brisanja prethodne.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Razumijem da će kontaktni podaci biti javni. Ostaju spremljeni dok je stranica pauzirana i brišu se zajedno sa stranicom. Mogu ih obrisati u bilo kojem trenutku.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Tvoj profil prikazivat će se kao stranica. Možeš je pauzirati ili izbrisati u bilo kojem trenutku u postavkama stranice.',
    'Page deleted': 'Stranica izbrisana',
    'pages.delete.confirmIdentity': 'Potvrdi da si to ti',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Za brisanje stranice odmah potrebna je nedavna prijava. Upiši lozinku.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nismo uspjeli potvrditi da si to ti, pa ništa nije izbrisano. Pokušaj ponovno ili se odjavi i ponovno prijavi.',
    'Deletion cancelled. The Page stays paused.':
        'Brisanje je otkazano. Stranica ostaje pauzirana.',
    '{count} posts.zero': '{count} objava',
    '{count} posts.one': '{count} objava',
    '{count} posts.two': '{count} objave',
    '{count} posts.few': '{count} objave',
    '{count} posts.many': '{count} objava',
    '{count} posts.other': '{count} objava',
  },
  'sr': <String, String>{
    'Delete all posts': 'Избриши све објаве',
    'The Page and its followers stay': 'Страница и пратиоци остају',
    'Delete Page': 'Избриши страницу',
    'Posts, followers and contact details. Your account stays.':
        'Објаве, пратиоци и контакт. Налог ти остаје.',
    'Delete {posts}?': 'Избрисати {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Нестаће и коментари и лајкови испод њих. Страница и {followers} остају. Ово се не може опозвати.',
    'Delete posts': 'Избриши објаве',
    'Posts deleted': 'Објаве су избрисане',
    'Deleting posts': 'Објаве се бришу',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Нестају у позадини, обично за неколико минута. Страница и {followers} остају.',
    'Publish your first post': 'Објави прву објаву',
    'pages.delete.goes': 'Нестаје',
    'The Page in Content and in search.': 'Страница у Садржају и у претрази.',
    '{posts} with photos and recordings.':
        '{posts} са фотографијама и снимцима.',
    'Comments and likes under them.': 'Коментари и лајкови испод њих.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} странице и њихова обавештења о твојим LIVE преносима.',
    'The Page\'s contact details.': 'Контакт подаци странице.',
    'pages.delete.stays': 'Остаје',
    'Your account: name, photo and cover.':
        'Твој налог: име, фотографија и насловна слика.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Пријатељи, ћаскања, сервери, Voice Moments и Yeels.',
    'Exception: reported content': 'Изузетак: пријављени садржај',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Пријављени садржај можемо чувати, непублично, до 90 дана.',
    'You have 30 days to come back': 'Имаш 30 дана за повратак',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Страницу одмах сакривамо и бришемо је {date}. До тада је можеш вратити. За враћање је потребан активан Premium или VIP.',
    'Type the Page name': 'Упиши назив странице',
    'To confirm, type: {name}': 'За потврду упиши: {name}',
    'pages.statusPendingDeletion': 'За брисање',
    'The Page will be deleted on {date}': 'Страница ће бити избрисана {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Други је више не виде, објаве видиш само ти. До тада је можеш вратити заједно са објавама и пратиоцима.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Други је више не виде. До тада је можеш вратити заједно са објавама и пратиоцима. За враћање је потребан активан Premium или VIP.',
    'Restore Page': 'Врати страницу',
    'Comes back to Content with its posts and followers':
        'Враћа се у Садржај заједно са објавама и пратиоцима',
    'Page restored': 'Страница је враћена',
    'Delete now, don\'t wait': 'Избриши сада, без чекања',
    'Without waiting until {date}. This can\'t be undone.':
        'Без чекања до {date}. Ово се не може опозвати.',
    'Delete the Page now?': 'Избрисати страницу сада?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Објаве, пратиоци и контакт подаци бришу се одмах и не могу се вратити. Нову страницу можеш направити после 7 дана.',
    'Deleting the Page': 'Страница се брише',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Објаве и пратиоце уклањамо у позадини. Нову страницу можеш направити 7 дана након завршетка.',
    'You can create a new Page after {date}.':
        'Нову страницу можеш направити после {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Твоја страница биће избрисана за 3 дана. Врати је у подешавањима странице ако желиш да је задржиш.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Нова страница може се направити 7 дана након брисања претходне.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Разумем да ће контакт подаци бити јавни. Остају сачувани док је страница паузирана и бришу се заједно са страницом. Могу да их обришем у било ком тренутку.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Твој профил ће се приказивати као страница. Можеш да је паузираш или избришеш у било ком тренутку у подешавањима странице.',
    'Page deleted': 'Страница је избрисана',
    'pages.delete.confirmIdentity': 'Потврди да си то ти',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'За брисање странице одмах потребна је недавна пријава. Унеси лозинку.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Нисмо успели да потврдимо да си то ти, па ништа није избрисано. Покушај поново или се одјави и поново пријави.',
    'Deletion cancelled. The Page stays paused.':
        'Брисање је отказано. Страница остаје паузирана.',
    '{count} posts.zero': '{count} објава',
    '{count} posts.one': '{count} објава',
    '{count} posts.two': '{count} објаве',
    '{count} posts.few': '{count} објаве',
    '{count} posts.many': '{count} објава',
    '{count} posts.other': '{count} објава',
  },
  'sv': <String, String>{
    'Delete all posts': 'Radera alla inlägg',
    'The Page and its followers stay': 'Sidan och följarna finns kvar',
    'Delete Page': 'Radera sidan',
    'Posts, followers and contact details. Your account stays.':
        'Inlägg, följare och kontaktuppgifter. Ditt konto finns kvar.',
    'Delete {posts}?': 'Radera {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Kommentarerna och gillningarna under dem försvinner också. Sidan och {followers} finns kvar. Det går inte att ångra.',
    'Delete posts': 'Radera inlägg',
    'Posts deleted': 'Inläggen har raderats',
    'Deleting posts': 'Inläggen raderas',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'De försvinner i bakgrunden, oftast inom några minuter. Sidan och {followers} finns kvar.',
    'Publish your first post': 'Publicera ditt första inlägg',
    'pages.delete.goes': 'Försvinner',
    'The Page in Content and in search.': 'Sidan i Innehåll och i sökningen.',
    '{posts} with photos and recordings.':
        '{posts} med foton och inspelningar.',
    'Comments and likes under them.':
        'Kommentarerna och gillningarna under dem.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} till sidan och deras aviseringar om dina LIVE-sändningar.',
    'The Page\'s contact details.': 'Sidans kontaktuppgifter.',
    'pages.delete.stays': 'Finns kvar',
    'Your account: name, photo and cover.':
        'Ditt konto: namn, foto och omslag.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Vänner, chattar, servrar, Voice Moments och Yeels.',
    'Exception: reported content': 'Undantag: anmält innehåll',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Anmält innehåll kan vi spara, inte offentligt, i upp till 90 dagar.',
    'You have 30 days to come back':
        'Du har 30 dagar på dig att komma tillbaka',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Vi döljer sidan direkt och raderar den den {date}. Fram till dess kan du återställa den. För att återställa krävs aktivt Premium eller VIP.',
    'Type the Page name': 'Skriv sidans namn',
    'To confirm, type: {name}': 'Bekräfta genom att skriva: {name}',
    'pages.statusPendingDeletion': 'Ska raderas',
    'The Page will be deleted on {date}': 'Sidan raderas den {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Andra ser den inte längre; bara du ser inläggen. Fram till dess kan du återställa den med inlägg och följare.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Andra ser den inte längre. Fram till dess kan du återställa den med inlägg och följare. För att återställa krävs aktivt Premium eller VIP.',
    'Restore Page': 'Återställ sidan',
    'Comes back to Content with its posts and followers':
        'Kommer tillbaka till Innehåll med inlägg och följare',
    'Page restored': 'Sidan har återställts',
    'Delete now, don\'t wait': 'Radera nu, vänta inte',
    'Without waiting until {date}. This can\'t be undone.':
        'Utan att vänta till den {date}. Det går inte att ångra.',
    'Delete the Page now?': 'Radera sidan nu?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Inlägg, följare och kontaktuppgifter raderas direkt och kan inte återställas. Du kan skapa en ny sida efter 7 dagar.',
    'Deleting the Page': 'Sidan raderas',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Inlägg och följare tas bort i bakgrunden. Du kan skapa en ny sida 7 dagar efter att det är klart.',
    'You can create a new Page after {date}.':
        'Du kan skapa en ny sida efter den {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Din sida raderas om 3 dagar. Återställ den i sidinställningarna om du vill behålla den.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'En ny sida kan skapas 7 dagar efter att den förra raderades.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Jag förstår att kontaktuppgifterna blir offentliga. De sparas medan sidan är pausad och raderas tillsammans med sidan. Jag kan rensa dem när som helst.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Din profil visas som en sida. Du kan pausa eller radera den när som helst i sidinställningarna.',
    'Page deleted': 'Sidan har raderats',
    'pages.delete.confirmIdentity': 'Bekräfta att det är du',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'För att radera sidan nu krävs en färsk inloggning. Ange ditt lösenord.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Vi kunde inte bekräfta att det är du, så inget raderades. Försök igen eller logga ut och logga in igen.',
    'Deletion cancelled. The Page stays paused.':
        'Raderingen har avbrutits. Sidan är fortfarande pausad.',
    '{count} posts.zero': '{count} inlägg',
    '{count} posts.one': '{count} inlägg',
    '{count} posts.two': '{count} inlägg',
    '{count} posts.few': '{count} inlägg',
    '{count} posts.many': '{count} inlägg',
    '{count} posts.other': '{count} inlägg',
  },
  'da': <String, String>{
    'Delete all posts': 'Slet alle opslag',
    'The Page and its followers stay': 'Siden og følgerne bliver',
    'Delete Page': 'Slet siden',
    'Posts, followers and contact details. Your account stays.':
        'Opslag, følgere og kontaktoplysninger. Din konto bliver.',
    'Delete {posts}?': 'Slet {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Kommentarerne og synes godt om under dem forsvinder også. Siden og {followers} bliver. Det kan ikke fortrydes.',
    'Delete posts': 'Slet opslag',
    'Posts deleted': 'Opslagene er slettet',
    'Deleting posts': 'Opslagene slettes',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'De forsvinder i baggrunden, som regel inden for få minutter. Siden og {followers} bliver.',
    'Publish your first post': 'Udgiv dit første opslag',
    'pages.delete.goes': 'Forsvinder',
    'The Page in Content and in search.': 'Siden i Indhold og i søgningen.',
    '{posts} with photos and recordings.': '{posts} med fotos og optagelser.',
    'Comments and likes under them.':
        'Kommentarerne og synes godt om under dem.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} af siden og deres notifikationer om dine LIVE-udsendelser.',
    'The Page\'s contact details.': 'Sidens kontaktoplysninger.',
    'pages.delete.stays': 'Bliver',
    'Your account: name, photo and cover.': 'Din konto: navn, foto og cover.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Venner, chats, servere, Voice Moments og Yeels.',
    'Exception: reported content': 'Undtagelse: anmeldt indhold',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Anmeldt indhold kan vi gemme, ikke offentligt, i op til 90 dage.',
    'You have 30 days to come back': 'Du har 30 dage til at vende tilbage',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Vi skjuler siden med det samme og sletter den den {date}. Indtil da kan du gendanne den. Gendannelse kræver aktivt Premium eller VIP.',
    'Type the Page name': 'Skriv sidens navn',
    'To confirm, type: {name}': 'Bekræft ved at skrive: {name}',
    'pages.statusPendingDeletion': 'Skal slettes',
    'The Page will be deleted on {date}': 'Siden slettes den {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Andre kan ikke længere se den; kun du ser opslagene. Indtil da kan du gendanne den med opslag og følgere.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Andre kan ikke længere se den. Indtil da kan du gendanne den med opslag og følgere. Gendannelse kræver aktivt Premium eller VIP.',
    'Restore Page': 'Gendan siden',
    'Comes back to Content with its posts and followers':
        'Vender tilbage til Indhold med opslag og følgere',
    'Page restored': 'Siden er gendannet',
    'Delete now, don\'t wait': 'Slet nu, vent ikke',
    'Without waiting until {date}. This can\'t be undone.':
        'Uden at vente til den {date}. Det kan ikke fortrydes.',
    'Delete the Page now?': 'Slet siden nu?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Opslag, følgere og kontaktoplysninger slettes med det samme og kan ikke gendannes. Du kan oprette en ny side efter 7 dage.',
    'Deleting the Page': 'Siden slettes',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Opslag og følgere fjernes i baggrunden. Du kan oprette en ny side 7 dage efter, at det er færdigt.',
    'You can create a new Page after {date}.':
        'Du kan oprette en ny side efter den {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Din side slettes om 3 dage. Gendan den i sideindstillingerne, hvis du vil beholde den.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'En ny side kan oprettes 7 dage efter, at den forrige blev slettet.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Jeg forstår, at kontaktoplysningerne bliver offentlige. De gemmes, mens siden er på pause, og slettes sammen med siden. Jeg kan rydde dem når som helst.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Din profil vises som en side. Du kan sætte den på pause eller slette den når som helst i sideindstillingerne.',
    'Page deleted': 'Siden er slettet',
    'pages.delete.confirmIdentity': 'Bekræft, at det er dig',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'For at slette siden nu kræves et nyligt login. Indtast din adgangskode.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Vi kunne ikke bekræfte, at det er dig, så intet blev slettet. Prøv igen, eller log ud og log ind igen.',
    'Deletion cancelled. The Page stays paused.':
        'Sletningen er annulleret. Siden er stadig på pause.',
    '{count} posts.zero': '{count} opslag',
    '{count} posts.one': '{count} opslag',
    '{count} posts.two': '{count} opslag',
    '{count} posts.few': '{count} opslag',
    '{count} posts.many': '{count} opslag',
    '{count} posts.other': '{count} opslag',
  },
  'nb': <String, String>{
    'Delete all posts': 'Slett alle innlegg',
    'The Page and its followers stay': 'Siden og følgerne blir værende',
    'Delete Page': 'Slett siden',
    'Posts, followers and contact details. Your account stays.':
        'Innlegg, følgere og kontaktinformasjon. Kontoen din blir værende.',
    'Delete {posts}?': 'Slette {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Kommentarene og likerklikkene under dem forsvinner også. Siden og {followers} blir værende. Dette kan ikke angres.',
    'Delete posts': 'Slett innlegg',
    'Posts deleted': 'Innleggene er slettet',
    'Deleting posts': 'Innleggene slettes',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'De forsvinner i bakgrunnen, vanligvis i løpet av noen minutter. Siden og {followers} blir værende.',
    'Publish your first post': 'Publiser ditt første innlegg',
    'pages.delete.goes': 'Forsvinner',
    'The Page in Content and in search.': 'Siden i Innhold og i søket.',
    '{posts} with photos and recordings.': '{posts} med bilder og opptak.',
    'Comments and likes under them.':
        'Kommentarene og likerklikkene under dem.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} av siden og varslene deres om LIVE-sendingene dine.',
    'The Page\'s contact details.': 'Sidens kontaktinformasjon.',
    'pages.delete.stays': 'Blir værende',
    'Your account: name, photo and cover.':
        'Kontoen din: navn, bilde og forsidebilde.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Venner, chatter, servere, Voice Moments og Yeels.',
    'Exception: reported content': 'Unntak: rapportert innhold',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Rapportert innhold kan vi oppbevare, ikke offentlig, i opptil 90 dager.',
    'You have 30 days to come back': 'Du har 30 dager på å komme tilbake',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Vi skjuler siden med en gang og sletter den {date}. Fram til da kan du gjenopprette den. Gjenoppretting krever aktivt Premium eller VIP.',
    'Type the Page name': 'Skriv navnet på siden',
    'To confirm, type: {name}': 'Bekreft ved å skrive: {name}',
    'pages.statusPendingDeletion': 'Skal slettes',
    'The Page will be deleted on {date}': 'Siden slettes {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Andre ser den ikke lenger; bare du ser innleggene. Fram til da kan du gjenopprette den med innlegg og følgere.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Andre ser den ikke lenger. Fram til da kan du gjenopprette den med innlegg og følgere. Gjenoppretting krever aktivt Premium eller VIP.',
    'Restore Page': 'Gjenopprett siden',
    'Comes back to Content with its posts and followers':
        'Kommer tilbake til Innhold med innlegg og følgere',
    'Page restored': 'Siden er gjenopprettet',
    'Delete now, don\'t wait': 'Slett nå, ikke vent',
    'Without waiting until {date}. This can\'t be undone.':
        'Uten å vente til {date}. Dette kan ikke angres.',
    'Delete the Page now?': 'Slette siden nå?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Innlegg, følgere og kontaktinformasjon slettes med en gang og kan ikke gjenopprettes. Du kan opprette en ny side etter 7 dager.',
    'Deleting the Page': 'Siden slettes',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Innlegg og følgere fjernes i bakgrunnen. Du kan opprette en ny side 7 dager etter at det er ferdig.',
    'You can create a new Page after {date}.':
        'Du kan opprette en ny side etter {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Siden din slettes om 3 dager. Gjenopprett den i sideinnstillingene hvis du vil beholde den.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'En ny side kan opprettes 7 dager etter at den forrige ble slettet.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Jeg forstår at kontaktinformasjonen blir offentlig. Den lagres mens siden er satt på pause, og slettes sammen med siden. Jeg kan fjerne den når som helst.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profilen din vises som en side. Du kan sette den på pause eller slette den når som helst i sideinnstillingene.',
    'Page deleted': 'Siden er slettet',
    'pages.delete.confirmIdentity': 'Bekreft at det er deg',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'For å slette siden nå kreves en fersk innlogging. Skriv inn passordet ditt.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Vi kunne ikke bekrefte at det er deg, så ingenting ble slettet. Prøv igjen, eller logg ut og logg inn på nytt.',
    'Deletion cancelled. The Page stays paused.':
        'Slettingen er avbrutt. Siden er fortsatt på pause.',
    '{count} posts.zero': '{count} innlegg',
    '{count} posts.one': '{count} innlegg',
    '{count} posts.two': '{count} innlegg',
    '{count} posts.few': '{count} innlegg',
    '{count} posts.many': '{count} innlegg',
    '{count} posts.other': '{count} innlegg',
  },
  'fi': <String, String>{
    'Delete all posts': 'Poista kaikki julkaisut',
    'The Page and its followers stay': 'Sivu ja seuraajat säilyvät',
    'Delete Page': 'Poista sivu',
    'Posts, followers and contact details. Your account stays.':
        'Julkaisut, seuraajat ja yhteystiedot. Tilisi säilyy.',
    'Delete {posts}?': 'Poistetaanko {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Myös niiden kommentit ja tykkäykset katoavat. Sivu ja {followers} säilyvät. Tätä ei voi perua.',
    'Delete posts': 'Poista julkaisut',
    'Posts deleted': 'Julkaisut poistettu',
    'Deleting posts': 'Julkaisuja poistetaan',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Ne katoavat taustalla, yleensä muutamassa minuutissa. Sivu ja {followers} säilyvät.',
    'Publish your first post': 'Julkaise ensimmäinen julkaisusi',
    'pages.delete.goes': 'Katoaa',
    'The Page in Content and in search.': 'Sivu Sisällössä ja haussa.',
    '{posts} with photos and recordings.': '{posts} kuvineen ja tallenteineen.',
    'Comments and likes under them.': 'Niiden kommentit ja tykkäykset.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ja heidän ilmoituksensa LIVE-lähetyksistäsi.',
    'The Page\'s contact details.': 'Sivun yhteystiedot.',
    'pages.delete.stays': 'Säilyy',
    'Your account: name, photo and cover.': 'Tilisi: nimi, kuva ja kansikuva.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Kaverit, keskustelut, palvelimet, Voice Moments ja Yeels.',
    'Exception: reported content': 'Poikkeus: ilmiannettu sisältö',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Ilmiannettua sisältöä voidaan säilyttää ei-julkisesti enintään 90 päivää.',
    'You have 30 days to come back': 'Sinulla on 30 päivää aikaa palata',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Piilotamme sivun heti. Poistopäivä: {date}. Siihen asti voit palauttaa sen. Palautus edellyttää aktiivista Premiumia tai VIP:tä.',
    'Type the Page name': 'Kirjoita sivun nimi',
    'To confirm, type: {name}': 'Vahvista kirjoittamalla: {name}',
    'pages.statusPendingDeletion': 'Poistetaan',
    'The Page will be deleted on {date}': 'Sivun poistopäivä: {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Muut eivät enää näe sitä; julkaisut näet vain sinä. Siihen asti voit palauttaa sen julkaisuineen ja seuraajineen.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Muut eivät enää näe sitä. Siihen asti voit palauttaa sen julkaisuineen ja seuraajineen. Palautus edellyttää aktiivista Premiumia tai VIP:tä.',
    'Restore Page': 'Palauta sivu',
    'Comes back to Content with its posts and followers':
        'Palaa Sisältöön julkaisuineen ja seuraajineen',
    'Page restored': 'Sivu palautettu',
    'Delete now, don\'t wait': 'Poista nyt, älä odota',
    'Without waiting until {date}. This can\'t be undone.':
        'Odottamatta poistopäivää ({date}). Tätä ei voi perua.',
    'Delete the Page now?': 'Poistetaanko sivu nyt?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Julkaisut, seuraajat ja yhteystiedot poistetaan heti, eikä niitä voi palauttaa. Voit luoda uuden sivun 7 päivän kuluttua.',
    'Deleting the Page': 'Sivua poistetaan',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Julkaisuja ja seuraajia poistetaan taustalla. Voit luoda uuden sivun 7 päivää sen jälkeen, kun poisto on valmis.',
    'You can create a new Page after {date}.':
        'Voit luoda uuden sivun tämän päivän jälkeen: {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Sivusi poistetaan 3 päivän kuluttua. Palauta se sivun asetuksista, jos haluat säilyttää sen.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Uuden sivun voi luoda 7 päivää edellisen poistamisen jälkeen.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Ymmärrän, että yhteystiedot ovat julkisia. Ne säilyvät, kun sivu on keskeytetty, ja poistetaan sivun mukana. Voin tyhjentää ne milloin tahansa.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profiilisi näkyy sivuna. Voit keskeyttää tai poistaa sen milloin tahansa sivun asetuksista.',
    'Page deleted': 'Sivu poistettu',
    'pages.delete.confirmIdentity': 'Vahvista, että se olet sinä',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Sivun poistaminen heti vaatii tuoreen kirjautumisen. Anna salasanasi.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Emme voineet vahvistaa, että se olet sinä, joten mitään ei poistettu. Yritä uudelleen tai kirjaudu ulos ja takaisin sisään.',
    'Deletion cancelled. The Page stays paused.':
        'Poisto peruttu. Sivu pysyy keskeytettynä.',
    '{count} posts.zero': '{count} julkaisua',
    '{count} posts.one': '{count} julkaisu',
    '{count} posts.two': '{count} julkaisua',
    '{count} posts.few': '{count} julkaisua',
    '{count} posts.many': '{count} julkaisua',
    '{count} posts.other': '{count} julkaisua',
  },
  'lt': <String, String>{
    'Delete all posts': 'Ištrinti visus įrašus',
    'The Page and its followers stay': 'Puslapis ir sekėjai lieka',
    'Delete Page': 'Ištrinti puslapį',
    'Posts, followers and contact details. Your account stays.':
        'Įrašai, sekėjai ir kontaktai. Jūsų paskyra lieka.',
    'Delete {posts}?': 'Ištrinti: {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Dings ir komentarai bei patiktukai po jais. Puslapis ir {followers} lieka. Šio veiksmo atšaukti negalima.',
    'Delete posts': 'Ištrinti įrašus',
    'Posts deleted': 'Įrašai ištrinti',
    'Deleting posts': 'Įrašai trinami',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Jie dingsta fone, paprastai per kelias minutes. Puslapis ir {followers} lieka.',
    'Publish your first post': 'Paskelbkite pirmą įrašą',
    'pages.delete.goes': 'Dings',
    'The Page in Content and in search.':
        'Puslapis skiltyje „Turinys“ ir paieškoje.',
    '{posts} with photos and recordings.':
        '{posts} su nuotraukomis ir garso įrašais.',
    'Comments and likes under them.': 'Komentarai ir patiktukai po jais.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ir jų pranešimai apie jūsų LIVE transliacijas.',
    'The Page\'s contact details.': 'Puslapio kontaktiniai duomenys.',
    'pages.delete.stays': 'Lieka',
    'Your account: name, photo and cover.':
        'Jūsų paskyra: vardas, nuotrauka ir viršelis.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Draugai, pokalbiai, serveriai, Voice Moments ir Yeels.',
    'Exception: reported content': 'Išimtis: turinys, apie kurį pranešta',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Turinį, apie kurį pranešta, galime saugoti neviešai iki 90 dienų.',
    'You have 30 days to come back': 'Turite 30 dienų sugrįžti',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Puslapį paslėpsime iš karto. Ištrynimo data: {date}. Iki tol galite jį atkurti. Atkūrimui reikia aktyvaus Premium arba VIP.',
    'Type the Page name': 'Įveskite puslapio pavadinimą',
    'To confirm, type: {name}': 'Kad patvirtintumėte, įveskite: {name}',
    'pages.statusPendingDeletion': 'Bus ištrintas',
    'The Page will be deleted on {date}': 'Puslapio ištrynimo data: {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Kiti jo nebemato, įrašus matote tik jūs. Iki tol galite jį atkurti kartu su įrašais ir sekėjais.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Kiti jo nebemato. Iki tol galite jį atkurti kartu su įrašais ir sekėjais. Atkūrimui reikia aktyvaus Premium arba VIP.',
    'Restore Page': 'Atkurti puslapį',
    'Comes back to Content with its posts and followers':
        'Grįžta į skiltį „Turinys“ kartu su įrašais ir sekėjais',
    'Page restored': 'Puslapis atkurtas',
    'Delete now, don\'t wait': 'Ištrinti dabar, nelaukti',
    'Without waiting until {date}. This can\'t be undone.':
        'Nelaukiant ištrynimo datos ({date}). Šio veiksmo atšaukti negalima.',
    'Delete the Page now?': 'Ištrinti puslapį dabar?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Įrašai, sekėjai ir kontaktiniai duomenys ištrinami iš karto ir jų atkurti negalima. Naują puslapį galėsite sukurti po 7 dienų.',
    'Deleting the Page': 'Puslapis trinamas',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Įrašai ir sekėjai šalinami fone. Naują puslapį galėsite sukurti praėjus 7 dienoms po pabaigos.',
    'You can create a new Page after {date}.':
        'Naują puslapį galėsite sukurti po šios datos: {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Jūsų puslapis bus ištrintas po 3 dienų. Jei norite jį išsaugoti, atkurkite jį puslapio nustatymuose.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Naują puslapį galima sukurti praėjus 7 dienoms po ankstesnio ištrynimo.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Suprantu, kad kontaktiniai duomenys bus vieši. Jie lieka išsaugoti, kol puslapis pristabdytas, ir ištrinami kartu su puslapiu. Galiu juos išvalyti bet kada.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Jūsų profilis bus rodomas kaip puslapis. Jį bet kada galite pristabdyti arba ištrinti puslapio nustatymuose.',
    'Page deleted': 'Puslapis ištrintas',
    'pages.delete.confirmIdentity': 'Patvirtinkite, kad tai jūs',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Norint ištrinti puslapį dabar, reikia neseniai atlikto prisijungimo. Įveskite slaptažodį.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Nepavyko patvirtinti, kad tai jūs, todėl niekas nebuvo ištrinta. Bandykite dar kartą arba atsijunkite ir prisijunkite iš naujo.',
    'Deletion cancelled. The Page stays paused.':
        'Ištrynimas atšauktas. Puslapis lieka pristabdytas.',
    '{count} posts.zero': '{count} įrašų',
    '{count} posts.one': '{count} įrašas',
    '{count} posts.two': '{count} įrašai',
    '{count} posts.few': '{count} įrašai',
    '{count} posts.many': '{count} įrašo',
    '{count} posts.other': '{count} įrašų',
  },
  'lv': <String, String>{
    'Delete all posts': 'Dzēst visas ziņas',
    'The Page and its followers stay': 'Lapa un sekotāji paliek',
    'Delete Page': 'Dzēst lapu',
    'Posts, followers and contact details. Your account stays.':
        'Ziņas, sekotāji un kontaktinformācija. Tavs konts paliek.',
    'Delete {posts}?': 'Dzēst: {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Pazudīs arī komentāri un “patīk” zem tām. Lapa un {followers} paliek. Šo darbību nevar atsaukt.',
    'Delete posts': 'Dzēst ziņas',
    'Posts deleted': 'Ziņas izdzēstas',
    'Deleting posts': 'Ziņas tiek dzēstas',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Tās pazūd fonā, parasti dažu minūšu laikā. Lapa un {followers} paliek.',
    'Publish your first post': 'Publicē savu pirmo ziņu',
    'pages.delete.goes': 'Pazudīs',
    'The Page in Content and in search.': 'Lapa sadaļā “Saturs” un meklēšanā.',
    '{posts} with photos and recordings.':
        '{posts} ar fotoattēliem un ierakstiem.',
    'Comments and likes under them.': 'Komentāri un “patīk” zem tām.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} un viņu paziņojumi par taviem LIVE.',
    'The Page\'s contact details.': 'Lapas kontaktinformācija.',
    'pages.delete.stays': 'Paliek',
    'Your account: name, photo and cover.':
        'Tavs konts: vārds, fotoattēls un vāka attēls.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Draugi, čati, serveri, Voice Moments un Yeels.',
    'Exception: reported content': 'Izņēmums: saturs, par kuru ziņots',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Saturu, par kuru ziņots, varam glabāt nepubliski līdz 90 dienām.',
    'You have 30 days to come back': 'Tev ir 30 dienas, lai atgrieztos',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Lapu paslēpsim uzreiz. Dzēšanas datums: {date}. Līdz tam vari to atjaunot. Atjaunošanai nepieciešams aktīvs Premium vai VIP.',
    'Type the Page name': 'Ieraksti lapas nosaukumu',
    'To confirm, type: {name}': 'Lai apstiprinātu, ieraksti: {name}',
    'pages.statusPendingDeletion': 'Tiks dzēsta',
    'The Page will be deleted on {date}': 'Lapas dzēšanas datums: {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Citi to vairs neredz, ziņas redzi tikai tu. Līdz tam vari to atjaunot kopā ar ziņām un sekotājiem.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Citi to vairs neredz. Līdz tam vari to atjaunot kopā ar ziņām un sekotājiem. Atjaunošanai nepieciešams aktīvs Premium vai VIP.',
    'Restore Page': 'Atjaunot lapu',
    'Comes back to Content with its posts and followers':
        'Atgriežas sadaļā “Saturs” kopā ar ziņām un sekotājiem',
    'Page restored': 'Lapa atjaunota',
    'Delete now, don\'t wait': 'Dzēst tagad, negaidīt',
    'Without waiting until {date}. This can\'t be undone.':
        'Negaidot dzēšanas datumu ({date}). Šo darbību nevar atsaukt.',
    'Delete the Page now?': 'Dzēst lapu tagad?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Ziņas, sekotāji un kontaktinformācija tiek dzēsti uzreiz, un tos nevar atjaunot. Jaunu lapu varēsi izveidot pēc 7 dienām.',
    'Deleting the Page': 'Lapa tiek dzēsta',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Ziņas un sekotāji tiek noņemti fonā. Jaunu lapu varēsi izveidot 7 dienas pēc pabeigšanas.',
    'You can create a new Page after {date}.':
        'Jaunu lapu varēsi izveidot pēc šī datuma: {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Tava lapa tiks dzēsta pēc 3 dienām. Atjauno to lapas iestatījumos, ja vēlies to paturēt.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Jaunu lapu var izveidot 7 dienas pēc iepriekšējās dzēšanas.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Saprotu, ka kontaktinformācija būs publiska. Tā paliek saglabāta, kamēr lapa ir pauzēta, un tiek dzēsta kopā ar lapu. Varu to notīrīt jebkurā brīdī.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Tavs profils tiks rādīts kā lapa. Lapas iestatījumos vari to jebkurā brīdī pauzēt vai dzēst.',
    'Page deleted': 'Lapa izdzēsta',
    'pages.delete.confirmIdentity': 'Apstiprini, ka tas esi tu',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Lai dzēstu lapu tagad, nepieciešama nesena pierakstīšanās. Ievadi paroli.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Neizdevās apstiprināt, ka tas esi tu, tāpēc nekas netika dzēsts. Mēģini vēlreiz vai izraksties un pieraksties no jauna.',
    'Deletion cancelled. The Page stays paused.':
        'Dzēšana atcelta. Lapa paliek pauzēta.',
    '{count} posts.zero': '{count} ziņu',
    '{count} posts.one': '{count} ziņa',
    '{count} posts.two': '{count} ziņas',
    '{count} posts.few': '{count} ziņas',
    '{count} posts.many': '{count} ziņu',
    '{count} posts.other': '{count} ziņas',
  },
  'et': <String, String>{
    'Delete all posts': 'Kustuta kõik postitused',
    'The Page and its followers stay': 'Leht ja jälgijad jäävad alles',
    'Delete Page': 'Kustuta leht',
    'Posts, followers and contact details. Your account stays.':
        'Postitused, jälgijad ja kontaktandmed. Sinu konto jääb alles.',
    'Delete {posts}?': 'Kas kustutada {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Kaovad ka nende all olevad kommentaarid ja meeldimised. Leht ja {followers} jäävad alles. Seda ei saa tagasi võtta.',
    'Delete posts': 'Kustuta postitused',
    'Posts deleted': 'Postitused kustutatud',
    'Deleting posts': 'Postitusi kustutatakse',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Need kaovad taustal, tavaliselt mõne minuti jooksul. Leht ja {followers} jäävad alles.',
    'Publish your first post': 'Avalda oma esimene postitus',
    'pages.delete.goes': 'Kaob',
    'The Page in Content and in search.': 'Leht Sisus ja otsingus.',
    '{posts} with photos and recordings.': '{posts} fotode ja salvestistega.',
    'Comments and likes under them.':
        'Nende all olevad kommentaarid ja meeldimised.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ja nende teavitused sinu LIVE-ülekannete kohta.',
    'The Page\'s contact details.': 'Lehe kontaktandmed.',
    'pages.delete.stays': 'Jääb alles',
    'Your account: name, photo and cover.':
        'Sinu konto: nimi, foto ja kaanepilt.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Sõbrad, vestlused, serverid, Voice Moments ja Yeels.',
    'Exception: reported content': 'Erand: teatatud sisu',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Teatatud sisu võime mitteavalikult säilitada kuni 90 päeva.',
    'You have 30 days to come back': 'Sul on tagasitulekuks 30 päeva',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Peidame lehe kohe. Kustutamise kuupäev: {date}. Seni saad selle taastada. Taastamiseks on vaja aktiivset Premiumi või VIP-i.',
    'Type the Page name': 'Sisesta lehe nimi',
    'To confirm, type: {name}': 'Kinnitamiseks sisesta: {name}',
    'pages.statusPendingDeletion': 'Kustutamisel',
    'The Page will be deleted on {date}': 'Lehe kustutamise kuupäev: {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Teised seda enam ei näe; postitusi näed ainult sina. Seni saad selle koos postituste ja jälgijatega taastada.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Teised seda enam ei näe. Seni saad selle koos postituste ja jälgijatega taastada. Taastamiseks on vaja aktiivset Premiumi või VIP-i.',
    'Restore Page': 'Taasta leht',
    'Comes back to Content with its posts and followers':
        'Naaseb Sisusse koos postituste ja jälgijatega',
    'Page restored': 'Leht taastatud',
    'Delete now, don\'t wait': 'Kustuta kohe, ära oota',
    'Without waiting until {date}. This can\'t be undone.':
        'Kustutamise kuupäeva ({date}) ootamata. Seda ei saa tagasi võtta.',
    'Delete the Page now?': 'Kas kustutada leht kohe?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Postitused, jälgijad ja kontaktandmed kustutatakse kohe ning neid ei saa taastada. Uue lehe saad luua 7 päeva pärast.',
    'Deleting the Page': 'Lehte kustutatakse',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Postitusi ja jälgijaid eemaldatakse taustal. Uue lehe saad luua 7 päeva pärast selle lõppu.',
    'You can create a new Page after {date}.':
        'Uue lehe saad luua pärast seda kuupäeva: {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Sinu leht kustutatakse 3 päeva pärast. Kui soovid selle alles jätta, taasta see lehe seadetes.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Uue lehe saab luua 7 päeva pärast eelmise kustutamist.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Mõistan, et kontaktandmed on avalikud. Need jäävad salvestatuks, kuni leht on peatatud, ja kustutatakse koos lehega. Saan need igal ajal eemaldada.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Sinu profiil kuvatakse lehena. Saad selle lehe seadetes igal ajal peatada või kustutada.',
    'Page deleted': 'Leht kustutatud',
    'pages.delete.confirmIdentity': 'Kinnita, et see oled sina',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Lehe kohe kustutamiseks on vaja värsket sisselogimist. Sisesta parool.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Me ei saanud kinnitada, et see oled sina, seega ei kustutatud midagi. Proovi uuesti või logi välja ja uuesti sisse.',
    'Deletion cancelled. The Page stays paused.':
        'Kustutamine tühistatud. Leht jääb peatatuks.',
    '{count} posts.zero': '{count} postitust',
    '{count} posts.one': '{count} postitus',
    '{count} posts.two': '{count} postitust',
    '{count} posts.few': '{count} postitust',
    '{count} posts.many': '{count} postitust',
    '{count} posts.other': '{count} postitust',
  },
  'id': <String, String>{
    'Delete all posts': 'Hapus semua postingan',
    'The Page and its followers stay': 'Halaman dan pengikut tetap ada',
    'Delete Page': 'Hapus halaman',
    'Posts, followers and contact details. Your account stays.':
        'Postingan, pengikut, dan kontak. Akunmu tetap ada.',
    'Delete {posts}?': 'Hapus {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Komentar dan suka di bawahnya juga hilang. Halaman dan {followers} tetap ada. Ini tidak bisa dibatalkan.',
    'Delete posts': 'Hapus postingan',
    'Posts deleted': 'Postingan dihapus',
    'Deleting posts': 'Menghapus postingan',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Postingan hilang di latar belakang, biasanya dalam beberapa menit. Halaman dan {followers} tetap ada.',
    'Publish your first post': 'Terbitkan postingan pertamamu',
    'pages.delete.goes': 'Hilang',
    'The Page in Content and in search.': 'Halaman di Konten dan di pencarian.',
    '{posts} with photos and recordings.': '{posts} dengan foto dan rekaman.',
    'Comments and likes under them.': 'Komentar dan suka di bawahnya.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} halaman dan notifikasi mereka tentang LIVE-mu.',
    'The Page\'s contact details.': 'Detail kontak halaman.',
    'pages.delete.stays': 'Tetap ada',
    'Your account: name, photo and cover.': 'Akunmu: nama, foto, dan sampul.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Teman, obrolan, server, Voice Moments, dan Yeels.',
    'Exception: reported content': 'Pengecualian: konten yang dilaporkan',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Konten yang dilaporkan dapat kami simpan secara tidak publik hingga 90 hari.',
    'You have 30 days to come back': 'Kamu punya 30 hari untuk kembali',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Kami langsung menyembunyikan halaman dan menghapusnya pada {date}. Sampai hari itu kamu bisa memulihkannya. Pemulihan memerlukan Premium atau VIP yang aktif.',
    'Type the Page name': 'Ketik nama halaman',
    'To confirm, type: {name}': 'Untuk mengonfirmasi, ketik: {name}',
    'pages.statusPendingDeletion': 'Akan dihapus',
    'The Page will be deleted on {date}': 'Halaman akan dihapus pada {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Orang lain tidak lagi melihatnya; hanya kamu yang melihat postingannya. Sampai hari itu kamu bisa memulihkannya beserta postingan dan pengikutnya.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Orang lain tidak lagi melihatnya. Sampai hari itu kamu bisa memulihkannya beserta postingan dan pengikutnya. Pemulihan memerlukan Premium atau VIP yang aktif.',
    'Restore Page': 'Pulihkan halaman',
    'Comes back to Content with its posts and followers':
        'Kembali ke Konten beserta postingan dan pengikutnya',
    'Page restored': 'Halaman dipulihkan',
    'Delete now, don\'t wait': 'Hapus sekarang, jangan menunggu',
    'Without waiting until {date}. This can\'t be undone.':
        'Tanpa menunggu sampai {date}. Ini tidak bisa dibatalkan.',
    'Delete the Page now?': 'Hapus halaman sekarang?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Postingan, pengikut, dan detail kontak langsung dihapus dan tidak bisa dipulihkan. Kamu bisa membuat halaman baru setelah 7 hari.',
    'Deleting the Page': 'Menghapus halaman',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Postingan dan pengikut sedang dihapus di latar belakang. Kamu bisa membuat halaman baru 7 hari setelah selesai.',
    'You can create a new Page after {date}.':
        'Kamu bisa membuat halaman baru setelah {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Halamanmu akan dihapus dalam 3 hari. Pulihkan di pengaturan halaman jika ingin tetap menyimpannya.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Halaman baru dapat dibuat 7 hari setelah halaman sebelumnya dihapus.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Saya mengerti bahwa detail kontak akan bersifat publik. Detail itu tetap tersimpan selama halaman dijeda dan dihapus bersama halaman. Saya bisa menghapusnya kapan saja.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profilmu akan tampil sebagai halaman. Kamu bisa menjeda atau menghapusnya kapan saja di pengaturan halaman.',
    'Page deleted': 'Halaman dihapus',
    'pages.delete.confirmIdentity': 'Konfirmasi bahwa ini kamu',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Menghapus halaman sekarang memerlukan login terbaru. Masukkan kata sandimu.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Kami tidak bisa mengonfirmasi bahwa ini kamu, jadi tidak ada yang dihapus. Coba lagi, atau keluar lalu masuk kembali.',
    'Deletion cancelled. The Page stays paused.':
        'Penghapusan dibatalkan. Halaman tetap dijeda.',
    '{count} posts.zero': '{count} postingan',
    '{count} posts.one': '{count} postingan',
    '{count} posts.two': '{count} postingan',
    '{count} posts.few': '{count} postingan',
    '{count} posts.many': '{count} postingan',
    '{count} posts.other': '{count} postingan',
  },
  'vi': <String, String>{
    'Delete all posts': 'Xóa tất cả bài đăng',
    'The Page and its followers stay': 'Trang và người theo dõi vẫn được giữ',
    'Delete Page': 'Xóa trang',
    'Posts, followers and contact details. Your account stays.':
        'Bài đăng, người theo dõi và thông tin liên hệ. Tài khoản của bạn vẫn còn.',
    'Delete {posts}?': 'Xóa {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Bình luận và lượt thích bên dưới cũng sẽ biến mất. Trang và {followers} vẫn được giữ. Không thể hoàn tác thao tác này.',
    'Delete posts': 'Xóa bài đăng',
    'Posts deleted': 'Đã xóa bài đăng',
    'Deleting posts': 'Đang xóa bài đăng',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Chúng biến mất ở chế độ nền, thường trong vài phút. Trang và {followers} vẫn được giữ.',
    'Publish your first post': 'Đăng bài đầu tiên của bạn',
    'pages.delete.goes': 'Sẽ mất',
    'The Page in Content and in search.':
        'Trang trong Nội dung và trong tìm kiếm.',
    '{posts} with photos and recordings.': '{posts} có ảnh và bản ghi âm.',
    'Comments and likes under them.': 'Bình luận và lượt thích bên dưới.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} của trang và thông báo của họ về các buổi LIVE của bạn.',
    'The Page\'s contact details.': 'Thông tin liên hệ của trang.',
    'pages.delete.stays': 'Vẫn còn',
    'Your account: name, photo and cover.':
        'Tài khoản của bạn: tên, ảnh và ảnh bìa.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Bạn bè, cuộc trò chuyện, máy chủ, Voice Moments và Yeels.',
    'Exception: reported content': 'Ngoại lệ: nội dung bị báo cáo',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Chúng tôi có thể lưu nội dung bị báo cáo ở chế độ không công khai tối đa 90 ngày.',
    'You have 30 days to come back': 'Bạn có 30 ngày để quay lại',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Chúng tôi ẩn trang ngay và xóa trang vào {date}. Cho đến ngày đó bạn có thể khôi phục trang. Việc khôi phục cần Premium hoặc VIP đang hoạt động.',
    'Type the Page name': 'Nhập tên trang',
    'To confirm, type: {name}': 'Để xác nhận, hãy nhập: {name}',
    'pages.statusPendingDeletion': 'Sắp bị xóa',
    'The Page will be deleted on {date}': 'Trang sẽ bị xóa vào {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Người khác không còn thấy trang; chỉ bạn thấy các bài đăng. Cho đến ngày đó bạn có thể khôi phục trang cùng bài đăng và người theo dõi.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Người khác không còn thấy trang. Cho đến ngày đó bạn có thể khôi phục trang cùng bài đăng và người theo dõi. Việc khôi phục cần Premium hoặc VIP đang hoạt động.',
    'Restore Page': 'Khôi phục trang',
    'Comes back to Content with its posts and followers':
        'Trở lại Nội dung cùng bài đăng và người theo dõi',
    'Page restored': 'Đã khôi phục trang',
    'Delete now, don\'t wait': 'Xóa ngay, không chờ',
    'Without waiting until {date}. This can\'t be undone.':
        'Không chờ đến {date}. Không thể hoàn tác thao tác này.',
    'Delete the Page now?': 'Xóa trang ngay bây giờ?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Bài đăng, người theo dõi và thông tin liên hệ sẽ bị xóa ngay và không thể khôi phục. Bạn có thể tạo trang mới sau 7 ngày.',
    'Deleting the Page': 'Đang xóa trang',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Bài đăng và người theo dõi đang được gỡ ở chế độ nền. Bạn có thể tạo trang mới sau 7 ngày kể từ khi hoàn tất.',
    'You can create a new Page after {date}.':
        'Bạn có thể tạo trang mới sau {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Trang của bạn sẽ bị xóa sau 3 ngày. Hãy khôi phục trong cài đặt trang nếu bạn muốn giữ lại.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Có thể tạo trang mới sau 7 ngày kể từ khi trang trước bị xóa.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Tôi hiểu rằng thông tin liên hệ sẽ công khai. Thông tin được lưu khi trang tạm dừng và bị xóa cùng với trang. Tôi có thể xóa chúng bất cứ lúc nào.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Hồ sơ của bạn sẽ hiển thị như một trang. Bạn có thể tạm dừng hoặc xóa trang bất cứ lúc nào trong cài đặt trang.',
    'Page deleted': 'Đã xóa trang',
    'pages.delete.confirmIdentity': 'Xác nhận đó là bạn',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Để xóa trang ngay, bạn cần đăng nhập lại gần đây. Hãy nhập mật khẩu.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Chúng tôi không thể xác nhận đó là bạn nên chưa có gì bị xóa. Hãy thử lại hoặc đăng xuất rồi đăng nhập lại.',
    'Deletion cancelled. The Page stays paused.':
        'Đã hủy xóa. Trang vẫn đang tạm dừng.',
    '{count} posts.zero': '{count} bài đăng',
    '{count} posts.one': '{count} bài đăng',
    '{count} posts.two': '{count} bài đăng',
    '{count} posts.few': '{count} bài đăng',
    '{count} posts.many': '{count} bài đăng',
    '{count} posts.other': '{count} bài đăng',
  },
  'zh_CN': <String, String>{
    'Delete all posts': '删除所有帖子',
    'The Page and its followers stay': '主页和关注者会保留',
    'Delete Page': '删除主页',
    'Posts, followers and contact details. Your account stays.':
        '帖子、关注者和联系方式。你的账号会保留。',
    'Delete {posts}?': '要删除{posts}吗？',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        '帖子下的评论和点赞也会消失。主页和{followers}会保留。此操作无法撤销。',
    'Delete posts': '删除帖子',
    'Posts deleted': '帖子已删除',
    'Deleting posts': '正在删除帖子',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        '帖子会在后台消失，通常只需几分钟。主页和{followers}会保留。',
    'Publish your first post': '发布你的第一条帖子',
    'pages.delete.goes': '将消失',
    'The Page in Content and in search.': '“内容”和搜索中的主页。',
    '{posts} with photos and recordings.': '{posts}，包括照片和录音。',
    'Comments and likes under them.': '帖子下的评论和点赞。',
    '{followers} of the Page and their notifications about your LIVE.':
        '主页的{followers}，以及他们收到的你的 LIVE 通知。',
    'The Page\'s contact details.': '主页的联系方式。',
    'pages.delete.stays': '会保留',
    'Your account: name, photo and cover.': '你的账号：名称、头像和封面。',
    'Friends, chats, servers, Voice Moments and Yeels.':
        '好友、聊天、服务器、Voice Moments 和 Yeels。',
    'Exception: reported content': '例外：被举报的内容',
    'We may keep reported content, not publicly, for up to 90 days.':
        '被举报的内容我们可能以非公开方式保留最多 90 天。',
    'You have 30 days to come back': '你有 30 天时间可以恢复',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        '我们会立即隐藏主页，并在{date}将其删除。在此之前你可以恢复主页。恢复需要有效的 Premium 或 VIP。',
    'Type the Page name': '输入主页名称',
    'To confirm, type: {name}': '请输入以确认：{name}',
    'pages.statusPendingDeletion': '待删除',
    'The Page will be deleted on {date}': '主页将于{date}删除',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        '其他人已看不到它，帖子只有你能看到。在此之前你可以连同帖子和关注者一起恢复。',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        '其他人已看不到它。在此之前你可以连同帖子和关注者一起恢复。恢复需要有效的 Premium 或 VIP。',
    'Restore Page': '恢复主页',
    'Comes back to Content with its posts and followers': '连同帖子和关注者一起回到“内容”',
    'Page restored': '主页已恢复',
    'Delete now, don\'t wait': '立即删除，不再等待',
    'Without waiting until {date}. This can\'t be undone.':
        '不等到{date}。此操作无法撤销。',
    'Delete the Page now?': '要立即删除主页吗？',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        '帖子、关注者和联系方式会立即删除且无法恢复。7 天后可以创建新主页。',
    'Deleting the Page': '正在删除主页',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        '正在后台移除帖子和关注者。完成 7 天后可以创建新主页。',
    'You can create a new Page after {date}.': '{date}之后可以创建新主页。',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        '你的主页将在 3 天后删除。如果想保留，请在主页设置中恢复。',
    'A new Page can be created 7 days after the previous one was deleted.':
        '上一个主页删除 7 天后才能创建新主页。',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        '我了解联系方式将公开显示。主页暂停期间它们会保留，并会随主页一起删除。我可以随时清除。',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        '你的个人资料将显示为主页。你可以随时在主页设置中暂停或删除它。',
    'Page deleted': '主页已删除',
    'pages.delete.confirmIdentity': '确认是你本人',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        '立即删除主页需要最近登录过。请输入密码。',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        '我们无法确认是你本人，因此没有删除任何内容。请重试，或退出后重新登录。',
    'Deletion cancelled. The Page stays paused.': '已取消删除。主页仍处于暂停状态。',
    '{count} posts.zero': '{count} 条帖子',
    '{count} posts.one': '{count} 条帖子',
    '{count} posts.two': '{count} 条帖子',
    '{count} posts.few': '{count} 条帖子',
    '{count} posts.many': '{count} 条帖子',
    '{count} posts.other': '{count} 条帖子',
  },
  'zh_TW': <String, String>{
    'Delete all posts': '刪除所有貼文',
    'The Page and its followers stay': '專頁和追蹤者會保留',
    'Delete Page': '刪除專頁',
    'Posts, followers and contact details. Your account stays.':
        '貼文、追蹤者和聯絡資訊。你的帳號會保留。',
    'Delete {posts}?': '要刪除{posts}嗎？',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        '貼文下的留言和按讚也會消失。專頁和{followers}會保留。此操作無法復原。',
    'Delete posts': '刪除貼文',
    'Posts deleted': '貼文已刪除',
    'Deleting posts': '正在刪除貼文',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        '貼文會在背景中消失，通常只需幾分鐘。專頁和{followers}會保留。',
    'Publish your first post': '發布你的第一則貼文',
    'pages.delete.goes': '將消失',
    'The Page in Content and in search.': '「內容」和搜尋中的專頁。',
    '{posts} with photos and recordings.': '{posts}，包含相片和錄音。',
    'Comments and likes under them.': '貼文下的留言和按讚。',
    '{followers} of the Page and their notifications about your LIVE.':
        '專頁的{followers}，以及他們收到的你的 LIVE 通知。',
    'The Page\'s contact details.': '專頁的聯絡資訊。',
    'pages.delete.stays': '會保留',
    'Your account: name, photo and cover.': '你的帳號：名稱、相片和封面。',
    'Friends, chats, servers, Voice Moments and Yeels.':
        '好友、聊天、伺服器、Voice Moments 和 Yeels。',
    'Exception: reported content': '例外：遭檢舉的內容',
    'We may keep reported content, not publicly, for up to 90 days.':
        '遭檢舉的內容我們可能以非公開方式保留最多 90 天。',
    'You have 30 days to come back': '你有 30 天可以恢復',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        '我們會立即隱藏專頁，並在{date}將其刪除。在此之前你可以恢復專頁。恢復需要有效的 Premium 或 VIP。',
    'Type the Page name': '輸入專頁名稱',
    'To confirm, type: {name}': '請輸入以確認：{name}',
    'pages.statusPendingDeletion': '待刪除',
    'The Page will be deleted on {date}': '專頁將於{date}刪除',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        '其他人已看不到它，貼文只有你看得到。在此之前你可以連同貼文和追蹤者一起恢復。',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        '其他人已看不到它。在此之前你可以連同貼文和追蹤者一起恢復。恢復需要有效的 Premium 或 VIP。',
    'Restore Page': '恢復專頁',
    'Comes back to Content with its posts and followers': '連同貼文和追蹤者一起回到「內容」',
    'Page restored': '專頁已恢復',
    'Delete now, don\'t wait': '立即刪除，不再等待',
    'Without waiting until {date}. This can\'t be undone.':
        '不等到{date}。此操作無法復原。',
    'Delete the Page now?': '要立即刪除專頁嗎？',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        '貼文、追蹤者和聯絡資訊會立即刪除且無法恢復。7 天後可以建立新專頁。',
    'Deleting the Page': '正在刪除專頁',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        '正在背景中移除貼文和追蹤者。完成 7 天後可以建立新專頁。',
    'You can create a new Page after {date}.': '{date}之後可以建立新專頁。',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        '你的專頁將在 3 天後刪除。如果想保留，請在專頁設定中恢復。',
    'A new Page can be created 7 days after the previous one was deleted.':
        '上一個專頁刪除 7 天後才能建立新專頁。',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        '我了解聯絡資訊將公開顯示。專頁暫停期間它們會保留，並會隨專頁一起刪除。我可以隨時清除。',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        '你的個人檔案將顯示為專頁。你可以隨時在專頁設定中暫停或刪除它。',
    'Page deleted': '專頁已刪除',
    'pages.delete.confirmIdentity': '確認是你本人',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        '立即刪除專頁需要最近登入過。請輸入密碼。',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        '我們無法確認是你本人，因此沒有刪除任何內容。請再試一次，或登出後重新登入。',
    'Deletion cancelled. The Page stays paused.': '已取消刪除。專頁仍處於暫停狀態。',
    '{count} posts.zero': '{count} 則貼文',
    '{count} posts.one': '{count} 則貼文',
    '{count} posts.two': '{count} 則貼文',
    '{count} posts.few': '{count} 則貼文',
    '{count} posts.many': '{count} 則貼文',
    '{count} posts.other': '{count} 則貼文',
  },
  'ja': <String, String>{
    'Delete all posts': 'すべての投稿を削除',
    'The Page and its followers stay': 'ページとフォロワーは残ります',
    'Delete Page': 'ページを削除',
    'Posts, followers and contact details. Your account stays.':
        '投稿、フォロワー、連絡先。アカウントは残ります。',
    'Delete {posts}?': '{posts}を削除しますか？',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        '投稿についたコメントといいねも消えます。ページと{followers}は残ります。この操作は取り消せません。',
    'Delete posts': '投稿を削除',
    'Posts deleted': '投稿を削除しました',
    'Deleting posts': '投稿を削除中',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'バックグラウンドで、通常は数分で消えます。ページと{followers}は残ります。',
    'Publish your first post': '最初の投稿を公開する',
    'pages.delete.goes': '消えるもの',
    'The Page in Content and in search.': '「コンテンツ」と検索に表示されるページ。',
    '{posts} with photos and recordings.': '{posts}（写真と録音を含む）。',
    'Comments and likes under them.': '投稿についたコメントといいね。',
    '{followers} of the Page and their notifications about your LIVE.':
        'ページの{followers}と、あなたの LIVE に関する通知。',
    'The Page\'s contact details.': 'ページの連絡先情報。',
    'pages.delete.stays': '残るもの',
    'Your account: name, photo and cover.': 'あなたのアカウント：名前、写真、カバー。',
    'Friends, chats, servers, Voice Moments and Yeels.':
        '友だち、チャット、サーバー、Voice Moments、Yeels。',
    'Exception: reported content': '例外：通報されたコンテンツ',
    'We may keep reported content, not publicly, for up to 90 days.':
        '通報されたコンテンツは、非公開で最長 90 日間保管することがあります。',
    'You have 30 days to come back': '30 日以内なら元に戻せます',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'ページはすぐに非表示になり、{date}に削除されます。それまでは復元できます。復元には有効な Premium または VIP が必要です。',
    'Type the Page name': 'ページ名を入力',
    'To confirm, type: {name}': '確認のため入力してください：{name}',
    'pages.statusPendingDeletion': '削除予定',
    'The Page will be deleted on {date}': 'ページは{date}に削除されます',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        '他の人にはもう表示されず、投稿が見えるのはあなただけです。それまでは投稿とフォロワーごと復元できます。',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        '他の人にはもう表示されません。それまでは投稿とフォロワーごと復元できます。復元には有効な Premium または VIP が必要です。',
    'Restore Page': 'ページを復元',
    'Comes back to Content with its posts and followers':
        '投稿とフォロワーごと「コンテンツ」に戻ります',
    'Page restored': 'ページを復元しました',
    'Delete now, don\'t wait': '待たずに今すぐ削除',
    'Without waiting until {date}. This can\'t be undone.':
        '{date}を待たずに削除します。この操作は取り消せません。',
    'Delete the Page now?': '今すぐページを削除しますか？',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        '投稿、フォロワー、連絡先情報はすぐに削除され、復元できません。新しいページは 7 日後に作成できます。',
    'Deleting the Page': 'ページを削除中',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        '投稿とフォロワーをバックグラウンドで削除しています。完了から 7 日後に新しいページを作成できます。',
    'You can create a new Page after {date}.': '新しいページは{date}より後に作成できます。',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'あなたのページは 3 日後に削除されます。残したい場合はページ設定で復元してください。',
    'A new Page can be created 7 days after the previous one was deleted.':
        '新しいページは、前のページの削除から 7 日後に作成できます。',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        '連絡先情報が公開されることを理解しました。ページの一時停止中も保存され、ページと一緒に削除されます。いつでも消去できます。',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'プロフィールはページとして表示されます。ページ設定でいつでも一時停止または削除できます。',
    'Page deleted': 'ページを削除しました',
    'pages.delete.confirmIdentity': 'ご本人であることを確認してください',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'ページを今すぐ削除するには、直近のログインが必要です。パスワードを入力してください。',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'ご本人であることを確認できなかったため、何も削除されていません。もう一度お試しいただくか、ログアウトしてからログインし直してください。',
    'Deletion cancelled. The Page stays paused.': '削除を取り消しました。ページは一時停止のままです。',
    '{count} posts.zero': '{count} 件の投稿',
    '{count} posts.one': '{count} 件の投稿',
    '{count} posts.two': '{count} 件の投稿',
    '{count} posts.few': '{count} 件の投稿',
    '{count} posts.many': '{count} 件の投稿',
    '{count} posts.other': '{count} 件の投稿',
  },
  'ko': <String, String>{
    'Delete all posts': '모든 게시물 삭제',
    'The Page and its followers stay': '페이지와 팔로워는 유지됩니다',
    'Delete Page': '페이지 삭제',
    'Posts, followers and contact details. Your account stays.':
        '게시물, 팔로워, 연락처 정보. 계정은 유지됩니다.',
    'Delete {posts}?': '{posts}를 삭제할까요?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        '게시물의 댓글과 좋아요도 사라집니다. 페이지와 {followers}은 유지됩니다. 이 작업은 되돌릴 수 없습니다.',
    'Delete posts': '게시물 삭제',
    'Posts deleted': '게시물이 삭제되었습니다',
    'Deleting posts': '게시물 삭제 중',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        '백그라운드에서 보통 몇 분 안에 사라집니다. 페이지와 {followers}은 유지됩니다.',
    'Publish your first post': '첫 게시물 올리기',
    'pages.delete.goes': '사라지는 항목',
    'The Page in Content and in search.': '콘텐츠와 검색에 표시되는 페이지.',
    '{posts} with photos and recordings.': '사진과 녹음이 포함된 {posts}.',
    'Comments and likes under them.': '게시물의 댓글과 좋아요.',
    '{followers} of the Page and their notifications about your LIVE.':
        '페이지의 {followers}과 내 LIVE에 대한 알림.',
    'The Page\'s contact details.': '페이지 연락처 정보.',
    'pages.delete.stays': '유지되는 항목',
    'Your account: name, photo and cover.': '내 계정: 이름, 사진, 커버.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        '친구, 채팅, 서버, Voice Moments, Yeels.',
    'Exception: reported content': '예외: 신고된 콘텐츠',
    'We may keep reported content, not publicly, for up to 90 days.':
        '신고된 콘텐츠는 비공개로 최대 90일 동안 보관할 수 있습니다.',
    'You have 30 days to come back': '30일 동안 되돌릴 수 있습니다',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        '페이지는 바로 숨겨지고 {date}에 삭제됩니다. 그때까지 복원할 수 있습니다. 복원하려면 활성 Premium 또는 VIP가 필요합니다.',
    'Type the Page name': '페이지 이름 입력',
    'To confirm, type: {name}': '확인하려면 입력하세요: {name}',
    'pages.statusPendingDeletion': '삭제 예정',
    'The Page will be deleted on {date}': '페이지가 {date}에 삭제됩니다',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        '다른 사람에게는 더 이상 보이지 않고 게시물은 나만 볼 수 있습니다. 그때까지 게시물과 팔로워를 포함해 복원할 수 있습니다.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        '다른 사람에게는 더 이상 보이지 않습니다. 그때까지 게시물과 팔로워를 포함해 복원할 수 있습니다. 복원하려면 활성 Premium 또는 VIP가 필요합니다.',
    'Restore Page': '페이지 복원',
    'Comes back to Content with its posts and followers':
        '게시물과 팔로워와 함께 콘텐츠로 돌아옵니다',
    'Page restored': '페이지가 복원되었습니다',
    'Delete now, don\'t wait': '기다리지 않고 지금 삭제',
    'Without waiting until {date}. This can\'t be undone.':
        '{date}까지 기다리지 않습니다. 이 작업은 되돌릴 수 없습니다.',
    'Delete the Page now?': '지금 페이지를 삭제할까요?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        '게시물, 팔로워, 연락처 정보가 즉시 삭제되며 복원할 수 없습니다. 새 페이지는 7일 후에 만들 수 있습니다.',
    'Deleting the Page': '페이지 삭제 중',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        '게시물과 팔로워를 백그라운드에서 제거하고 있습니다. 완료 후 7일이 지나면 새 페이지를 만들 수 있습니다.',
    'You can create a new Page after {date}.': '새 페이지는 {date} 이후에 만들 수 있습니다.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        '페이지가 3일 후에 삭제됩니다. 유지하려면 페이지 설정에서 복원하세요.',
    'A new Page can be created 7 days after the previous one was deleted.':
        '새 페이지는 이전 페이지가 삭제된 지 7일 후에 만들 수 있습니다.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        '연락처 정보가 공개된다는 점을 이해합니다. 페이지가 일시정지된 동안에도 저장되며 페이지와 함께 삭제됩니다. 언제든지 지울 수 있습니다.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        '프로필이 페이지로 표시됩니다. 페이지 설정에서 언제든지 일시정지하거나 삭제할 수 있습니다.',
    'Page deleted': '페이지가 삭제되었습니다',
    'pages.delete.confirmIdentity': '본인인지 확인해 주세요',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        '페이지를 지금 삭제하려면 최근 로그인이 필요합니다. 비밀번호를 입력하세요.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        '본인인지 확인하지 못해 아무것도 삭제되지 않았습니다. 다시 시도하거나 로그아웃한 뒤 다시 로그인하세요.',
    'Deletion cancelled. The Page stays paused.':
        '삭제가 취소되었습니다. 페이지는 일시정지 상태로 유지됩니다.',
    '{count} posts.zero': '게시물 {count}개',
    '{count} posts.one': '게시물 {count}개',
    '{count} posts.two': '게시물 {count}개',
    '{count} posts.few': '게시물 {count}개',
    '{count} posts.many': '게시물 {count}개',
    '{count} posts.other': '게시물 {count}개',
  },
  'ar': <String, String>{
    'Delete all posts': 'حذف كل المنشورات',
    'The Page and its followers stay': 'تبقى الصفحة والمتابعون',
    'Delete Page': 'حذف الصفحة',
    'Posts, followers and contact details. Your account stays.':
        'المنشورات والمتابعون وبيانات التواصل. حسابك يبقى.',
    'Delete {posts}?': 'هل تريد حذف {posts}؟',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'ستختفي أيضًا التعليقات والإعجابات عليها. تبقى الصفحة و{followers}. لا يمكن التراجع عن هذا الإجراء.',
    'Delete posts': 'حذف المنشورات',
    'Posts deleted': 'تم حذف المنشورات',
    'Deleting posts': 'جارٍ حذف المنشورات',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'تختفي في الخلفية، عادةً خلال دقائق. تبقى الصفحة و{followers}.',
    'Publish your first post': 'انشر أول منشور لك',
    'pages.delete.goes': 'سيختفي',
    'The Page in Content and in search.': 'الصفحة في المحتوى وفي البحث.',
    '{posts} with photos and recordings.': '{posts} مع الصور والتسجيلات.',
    'Comments and likes under them.': 'التعليقات والإعجابات عليها.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} للصفحة وإشعاراتهم عن بثوث LIVE الخاصة بك.',
    'The Page\'s contact details.': 'بيانات التواصل الخاصة بالصفحة.',
    'pages.delete.stays': 'يبقى',
    'Your account: name, photo and cover.': 'حسابك: الاسم والصورة والغلاف.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'الأصدقاء والمحادثات والخوادم وVoice Moments وYeels.',
    'Exception: reported content': 'استثناء: المحتوى المُبلَّغ عنه',
    'We may keep reported content, not publicly, for up to 90 days.':
        'قد نحتفظ بالمحتوى المُبلَّغ عنه بشكل غير علني لمدة تصل إلى 90 يومًا.',
    'You have 30 days to come back': 'لديك 30 يومًا للعودة',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'سنخفي الصفحة فورًا ونحذفها في {date}. يمكنك استعادتها حتى ذلك اليوم. تتطلب الاستعادة اشتراك Premium أو VIP نشطًا.',
    'Type the Page name': 'اكتب اسم الصفحة',
    'To confirm, type: {name}': 'للتأكيد، اكتب: {name}',
    'pages.statusPendingDeletion': 'قيد الحذف',
    'The Page will be deleted on {date}': 'ستُحذف الصفحة في {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'لم يعد الآخرون يرونها، وأنت فقط ترى المنشورات. يمكنك استعادتها مع منشوراتها ومتابعيها حتى ذلك اليوم.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'لم يعد الآخرون يرونها. يمكنك استعادتها مع منشوراتها ومتابعيها حتى ذلك اليوم. تتطلب الاستعادة اشتراك Premium أو VIP نشطًا.',
    'Restore Page': 'استعادة الصفحة',
    'Comes back to Content with its posts and followers':
        'تعود إلى المحتوى مع منشوراتها ومتابعيها',
    'Page restored': 'تمت استعادة الصفحة',
    'Delete now, don\'t wait': 'احذف الآن دون انتظار',
    'Without waiting until {date}. This can\'t be undone.':
        'دون انتظار حتى {date}. لا يمكن التراجع عن هذا الإجراء.',
    'Delete the Page now?': 'هل تريد حذف الصفحة الآن؟',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'تُحذف المنشورات والمتابعون وبيانات التواصل فورًا ولا يمكن استعادتها. يمكنك إنشاء صفحة جديدة بعد 7 أيام.',
    'Deleting the Page': 'جارٍ حذف الصفحة',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'نزيل المنشورات والمتابعين في الخلفية. يمكنك إنشاء صفحة جديدة بعد 7 أيام من الانتهاء.',
    'You can create a new Page after {date}.':
        'يمكنك إنشاء صفحة جديدة بعد {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'ستُحذف صفحتك خلال 3 أيام. استعدها من إعدادات الصفحة إذا أردت الاحتفاظ بها.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'يمكن إنشاء صفحة جديدة بعد 7 أيام من حذف الصفحة السابقة.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'أفهم أن بيانات التواصل ستكون علنية. تبقى محفوظة ما دامت الصفحة متوقفة مؤقتًا وتُحذف مع الصفحة. يمكنني مسحها في أي وقت.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'سيظهر ملفك الشخصي كصفحة. يمكنك إيقافها مؤقتًا أو حذفها في أي وقت من إعدادات الصفحة.',
    'Page deleted': 'تم حذف الصفحة',
    'pages.delete.confirmIdentity': 'أكّد أنك أنت',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'حذف الصفحة الآن يتطلب تسجيل دخول حديثًا. أدخل كلمة المرور.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'لم نتمكن من التأكد من أنك أنت، لذلك لم يُحذف شيء. حاول مرة أخرى أو سجّل الخروج ثم سجّل الدخول من جديد.',
    'Deletion cancelled. The Page stays paused.':
        'أُلغي الحذف. الصفحة ما زالت متوقفة مؤقتًا.',
    '{count} posts.zero': '{count} منشور',
    '{count} posts.one': '{count} منشور',
    '{count} posts.two': '{count} منشوران',
    '{count} posts.few': '{count} منشورات',
    '{count} posts.many': '{count} منشورًا',
    '{count} posts.other': '{count} منشور',
  },
  'th': <String, String>{
    'Delete all posts': 'ลบโพสต์ทั้งหมด',
    'The Page and its followers stay': 'เพจและผู้ติดตามยังอยู่',
    'Delete Page': 'ลบเพจ',
    'Posts, followers and contact details. Your account stays.':
        'โพสต์ ผู้ติดตาม และข้อมูลติดต่อ บัญชีของคุณยังอยู่',
    'Delete {posts}?': 'ลบ{posts}ไหม',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'ความคิดเห็นและการกดถูกใจใต้โพสต์จะหายไปด้วย เพจและ{followers}ยังอยู่ การดำเนินการนี้ย้อนกลับไม่ได้',
    'Delete posts': 'ลบโพสต์',
    'Posts deleted': 'ลบโพสต์แล้ว',
    'Deleting posts': 'กำลังลบโพสต์',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'โพสต์จะหายไปในเบื้องหลัง โดยปกติภายในไม่กี่นาที เพจและ{followers}ยังอยู่',
    'Publish your first post': 'เผยแพร่โพสต์แรกของคุณ',
    'pages.delete.goes': 'จะหายไป',
    'The Page in Content and in search.': 'เพจในเนื้อหาและในการค้นหา',
    '{posts} with photos and recordings.':
        '{posts} พร้อมรูปภาพและเสียงที่บันทึก',
    'Comments and likes under them.': 'ความคิดเห็นและการกดถูกใจใต้โพสต์',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers}ของเพจ และการแจ้งเตือนของพวกเขาเกี่ยวกับ LIVE ของคุณ',
    'The Page\'s contact details.': 'ข้อมูลติดต่อของเพจ',
    'pages.delete.stays': 'ยังอยู่',
    'Your account: name, photo and cover.': 'บัญชีของคุณ: ชื่อ รูปภาพ และภาพปก',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'เพื่อน แชต เซิร์ฟเวอร์ Voice Moments และ Yeels',
    'Exception: reported content': 'ข้อยกเว้น: เนื้อหาที่ถูกรายงาน',
    'We may keep reported content, not publicly, for up to 90 days.':
        'เนื้อหาที่ถูกรายงานอาจถูกเก็บไว้แบบไม่เปิดเผยได้นานสูงสุด 90 วัน',
    'You have 30 days to come back': 'คุณมีเวลา 30 วันในการกลับมา',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'เราจะซ่อนเพจทันทีและลบในวันที่ {date} คุณกู้คืนได้จนถึงวันนั้น การกู้คืนต้องมี Premium หรือ VIP ที่ใช้งานอยู่',
    'Type the Page name': 'พิมพ์ชื่อเพจ',
    'To confirm, type: {name}': 'พิมพ์เพื่อยืนยัน: {name}',
    'pages.statusPendingDeletion': 'รอลบ',
    'The Page will be deleted on {date}': 'เพจจะถูกลบในวันที่ {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'คนอื่นไม่เห็นเพจแล้ว มีเพียงคุณที่เห็นโพสต์ คุณกู้คืนเพจพร้อมโพสต์และผู้ติดตามได้จนถึงวันนั้น',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'คนอื่นไม่เห็นเพจแล้ว คุณกู้คืนเพจพร้อมโพสต์และผู้ติดตามได้จนถึงวันนั้น การกู้คืนต้องมี Premium หรือ VIP ที่ใช้งานอยู่',
    'Restore Page': 'กู้คืนเพจ',
    'Comes back to Content with its posts and followers':
        'กลับสู่เนื้อหาพร้อมโพสต์และผู้ติดตาม',
    'Page restored': 'กู้คืนเพจแล้ว',
    'Delete now, don\'t wait': 'ลบเลย ไม่ต้องรอ',
    'Without waiting until {date}. This can\'t be undone.':
        'ไม่ต้องรอถึงวันที่ {date} การดำเนินการนี้ย้อนกลับไม่ได้',
    'Delete the Page now?': 'ลบเพจตอนนี้เลยไหม',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'โพสต์ ผู้ติดตาม และข้อมูลติดต่อจะถูกลบทันทีและกู้คืนไม่ได้ คุณสร้างเพจใหม่ได้หลังจาก 7 วัน',
    'Deleting the Page': 'กำลังลบเพจ',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'กำลังนำโพสต์และผู้ติดตามออกในเบื้องหลัง คุณสร้างเพจใหม่ได้หลังจากเสร็จสิ้น 7 วัน',
    'You can create a new Page after {date}.':
        'คุณสร้างเพจใหม่ได้หลังวันที่ {date}',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'เพจของคุณจะถูกลบใน 3 วัน หากต้องการเก็บไว้ ให้กู้คืนในการตั้งค่าเพจ',
    'A new Page can be created 7 days after the previous one was deleted.':
        'สร้างเพจใหม่ได้หลังจากลบเพจก่อนหน้า 7 วัน',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'ฉันเข้าใจว่าข้อมูลติดต่อจะเปิดเผยต่อสาธารณะ ข้อมูลจะถูกเก็บไว้ขณะเพจหยุดชั่วคราว และถูกลบพร้อมกับเพจ ฉันล้างข้อมูลได้ทุกเมื่อ',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'โปรไฟล์ของคุณจะแสดงเป็นเพจ คุณหยุดชั่วคราวหรือลบเพจได้ทุกเมื่อในการตั้งค่าเพจ',
    'Page deleted': 'ลบเพจแล้ว',
    'pages.delete.confirmIdentity': 'ยืนยันว่าเป็นคุณ',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'การลบเพจทันทีต้องมีการเข้าสู่ระบบเมื่อไม่นานมานี้ โปรดป้อนรหัสผ่าน',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'เรายืนยันไม่ได้ว่าเป็นคุณ จึงยังไม่มีอะไรถูกลบ ลองอีกครั้ง หรือออกจากระบบแล้วเข้าสู่ระบบใหม่',
    'Deletion cancelled. The Page stays paused.':
        'ยกเลิกการลบแล้ว เพจยังคงหยุดชั่วคราว',
    '{count} posts.zero': 'โพสต์ {count} รายการ',
    '{count} posts.one': 'โพสต์ {count} รายการ',
    '{count} posts.two': 'โพสต์ {count} รายการ',
    '{count} posts.few': 'โพสต์ {count} รายการ',
    '{count} posts.many': 'โพสต์ {count} รายการ',
    '{count} posts.other': 'โพสต์ {count} รายการ',
  },
  'ms': <String, String>{
    'Delete all posts': 'Padam semua hantaran',
    'The Page and its followers stay': 'Halaman dan pengikut kekal',
    'Delete Page': 'Padam halaman',
    'Posts, followers and contact details. Your account stays.':
        'Hantaran, pengikut dan butiran hubungan. Akaun anda kekal.',
    'Delete {posts}?': 'Padam {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Komen dan suka di bawahnya turut hilang. Halaman dan {followers} kekal. Tindakan ini tidak boleh dibuat asal.',
    'Delete posts': 'Padam hantaran',
    'Posts deleted': 'Hantaran dipadam',
    'Deleting posts': 'Memadam hantaran',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Hantaran hilang di latar belakang, biasanya dalam beberapa minit. Halaman dan {followers} kekal.',
    'Publish your first post': 'Terbitkan hantaran pertama anda',
    'pages.delete.goes': 'Akan hilang',
    'The Page in Content and in search.':
        'Halaman dalam Kandungan dan dalam carian.',
    '{posts} with photos and recordings.': '{posts} dengan foto dan rakaman.',
    'Comments and likes under them.': 'Komen dan suka di bawahnya.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} halaman dan pemberitahuan mereka tentang LIVE anda.',
    'The Page\'s contact details.': 'Butiran hubungan halaman.',
    'pages.delete.stays': 'Kekal',
    'Your account: name, photo and cover.':
        'Akaun anda: nama, foto dan muka depan.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Rakan, sembang, pelayan, Voice Moments dan Yeels.',
    'Exception: reported content': 'Pengecualian: kandungan yang dilaporkan',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Kandungan yang dilaporkan boleh kami simpan secara tidak umum sehingga 90 hari.',
    'You have 30 days to come back': 'Anda ada 30 hari untuk kembali',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Kami menyembunyikan halaman serta-merta dan memadamnya pada {date}. Sehingga hari itu anda boleh memulihkannya. Pemulihan memerlukan Premium atau VIP yang aktif.',
    'Type the Page name': 'Taip nama halaman',
    'To confirm, type: {name}': 'Untuk mengesahkan, taip: {name}',
    'pages.statusPendingDeletion': 'Akan dipadam',
    'The Page will be deleted on {date}': 'Halaman akan dipadam pada {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Orang lain tidak lagi melihatnya; hanya anda yang melihat hantaran. Sehingga hari itu anda boleh memulihkannya bersama hantaran dan pengikut.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Orang lain tidak lagi melihatnya. Sehingga hari itu anda boleh memulihkannya bersama hantaran dan pengikut. Pemulihan memerlukan Premium atau VIP yang aktif.',
    'Restore Page': 'Pulihkan halaman',
    'Comes back to Content with its posts and followers':
        'Kembali ke Kandungan bersama hantaran dan pengikut',
    'Page restored': 'Halaman dipulihkan',
    'Delete now, don\'t wait': 'Padam sekarang, jangan tunggu',
    'Without waiting until {date}. This can\'t be undone.':
        'Tanpa menunggu sehingga {date}. Tindakan ini tidak boleh dibuat asal.',
    'Delete the Page now?': 'Padam halaman sekarang?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Hantaran, pengikut dan butiran hubungan dipadam serta-merta dan tidak boleh dipulihkan. Anda boleh mencipta halaman baharu selepas 7 hari.',
    'Deleting the Page': 'Memadam halaman',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Hantaran dan pengikut sedang dialih keluar di latar belakang. Anda boleh mencipta halaman baharu 7 hari selepas selesai.',
    'You can create a new Page after {date}.':
        'Anda boleh mencipta halaman baharu selepas {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Halaman anda akan dipadam dalam 3 hari. Pulihkannya dalam tetapan halaman jika anda mahu mengekalkannya.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Halaman baharu boleh dicipta 7 hari selepas halaman sebelumnya dipadam.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Saya faham bahawa butiran hubungan akan menjadi umum. Butiran itu kekal disimpan semasa halaman dijeda dan dipadam bersama halaman. Saya boleh mengosongkannya pada bila-bila masa.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Profil anda akan dipaparkan sebagai halaman. Anda boleh menjeda atau memadamnya pada bila-bila masa dalam tetapan halaman.',
    'Page deleted': 'Halaman dipadam',
    'pages.delete.confirmIdentity': 'Sahkan bahawa ini anda',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Untuk memadam halaman sekarang, log masuk terkini diperlukan. Masukkan kata laluan anda.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Kami tidak dapat mengesahkan bahawa ini anda, jadi tiada apa-apa dipadam. Cuba lagi, atau log keluar dan log masuk semula.',
    'Deletion cancelled. The Page stays paused.':
        'Pemadaman dibatalkan. Halaman kekal dijeda.',
    '{count} posts.zero': '{count} hantaran',
    '{count} posts.one': '{count} hantaran',
    '{count} posts.two': '{count} hantaran',
    '{count} posts.few': '{count} hantaran',
    '{count} posts.many': '{count} hantaran',
    '{count} posts.other': '{count} hantaran',
  },
  'fil': <String, String>{
    'Delete all posts': 'Burahin ang lahat ng post',
    'The Page and its followers stay':
        'Mananatili ang Page at ang mga follower',
    'Delete Page': 'Burahin ang Page',
    'Posts, followers and contact details. Your account stays.':
        'Mga post, follower at detalye ng contact. Mananatili ang account mo.',
    'Delete {posts}?': 'Burahin ang {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Mawawala rin ang mga komento at like sa ilalim ng mga ito. Mananatili ang Page at ang {followers}. Hindi na ito mababawi.',
    'Delete posts': 'Burahin ang mga post',
    'Posts deleted': 'Nabura na ang mga post',
    'Deleting posts': 'Binubura ang mga post',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Nawawala ang mga ito sa background, kadalasan sa loob ng ilang minuto. Mananatili ang Page at ang {followers}.',
    'Publish your first post': 'I-publish ang una mong post',
    'pages.delete.goes': 'Mawawala',
    'The Page in Content and in search.':
        'Ang Page sa Nilalaman at sa paghahanap.',
    '{posts} with photos and recordings.':
        '{posts} na may mga larawan at recording.',
    'Comments and likes under them.':
        'Mga komento at like sa ilalim ng mga ito.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} ng Page at ang mga notification nila tungkol sa mga LIVE mo.',
    'The Page\'s contact details.': 'Mga detalye ng contact ng Page.',
    'pages.delete.stays': 'Mananatili',
    'Your account: name, photo and cover.':
        'Ang account mo: pangalan, larawan at cover.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Mga kaibigan, chat, server, Voice Moments at Yeels.',
    'Exception: reported content': 'Exception: nai-report na content',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Maaari naming itago nang hindi pampubliko ang nai-report na content nang hanggang 90 araw.',
    'You have 30 days to come back': 'May 30 araw ka para bumalik',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Itatago namin agad ang Page at buburahin ito sa {date}. Hanggang sa araw na iyon, maaari mo itong i-restore. Kailangan ng aktibong Premium o VIP para mag-restore.',
    'Type the Page name': 'I-type ang pangalan ng Page',
    'To confirm, type: {name}': 'Para kumpirmahin, i-type: {name}',
    'pages.statusPendingDeletion': 'Buburahin',
    'The Page will be deleted on {date}': 'Buburahin ang Page sa {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Hindi na ito nakikita ng iba; ikaw lang ang nakakakita ng mga post. Hanggang sa araw na iyon, maaari mo itong i-restore kasama ang mga post at follower.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Hindi na ito nakikita ng iba. Hanggang sa araw na iyon, maaari mo itong i-restore kasama ang mga post at follower. Kailangan ng aktibong Premium o VIP para mag-restore.',
    'Restore Page': 'I-restore ang Page',
    'Comes back to Content with its posts and followers':
        'Babalik sa Nilalaman kasama ang mga post at follower',
    'Page restored': 'Na-restore ang Page',
    'Delete now, don\'t wait': 'Burahin ngayon, huwag nang maghintay',
    'Without waiting until {date}. This can\'t be undone.':
        'Nang hindi naghihintay hanggang {date}. Hindi na ito mababawi.',
    'Delete the Page now?': 'Burahin na ang Page ngayon?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Agad na buburahin ang mga post, follower at detalye ng contact at hindi na maibabalik. Makakagawa ka ng bagong Page pagkalipas ng 7 araw.',
    'Deleting the Page': 'Binubura ang Page',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Inaalis ang mga post at follower sa background. Makakagawa ka ng bagong Page 7 araw pagkatapos nito.',
    'You can create a new Page after {date}.':
        'Makakagawa ka ng bagong Page pagkatapos ng {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Buburahin ang Page mo sa loob ng 3 araw. I-restore ito sa mga setting ng Page kung gusto mo itong panatilihin.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Makakagawa ng bagong Page 7 araw matapos burahin ang nauna.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Nauunawaan kong magiging pampubliko ang mga detalye ng contact. Nananatiling naka-save ang mga ito habang naka-pause ang Page at buburahin kasama ng Page. Maaari ko itong i-clear anumang oras.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Lalabas ang profile mo bilang Page. Maaari mo itong i-pause o burahin anumang oras sa mga setting ng Page.',
    'Page deleted': 'Nabura na ang Page',
    'pages.delete.confirmIdentity': 'Kumpirmahin na ikaw ito',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Kailangan ng bagong pag-sign in para mabura ang Page ngayon. Ilagay ang password mo.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Hindi namin nakumpirma na ikaw ito, kaya walang nabura. Subukan ulit, o mag-sign out at mag-sign in muli.',
    'Deletion cancelled. The Page stays paused.':
        'Kinansela ang pagbura. Naka-pause pa rin ang Page.',
    '{count} posts.zero': '{count} post',
    '{count} posts.one': '{count} post',
    '{count} posts.two': '{count} post',
    '{count} posts.few': '{count} post',
    '{count} posts.many': '{count} post',
    '{count} posts.other': '{count} post',
  },
  'he': <String, String>{
    'Delete all posts': 'מחיקת כל הפוסטים',
    'The Page and its followers stay': 'הדף והעוקבים נשארים',
    'Delete Page': 'מחיקת הדף',
    'Posts, followers and contact details. Your account stays.':
        'פוסטים, עוקבים ופרטי קשר. החשבון שלכם נשאר.',
    'Delete {posts}?': 'למחוק {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'גם התגובות והלייקים שמתחתיהם ייעלמו. הדף ו־{followers} נשארים. אי אפשר לבטל את הפעולה.',
    'Delete posts': 'מחיקת פוסטים',
    'Posts deleted': 'הפוסטים נמחקו',
    'Deleting posts': 'הפוסטים נמחקים',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'הם נעלמים ברקע, בדרך כלל בתוך כמה דקות. הדף ו־{followers} נשארים.',
    'Publish your first post': 'פרסמו את הפוסט הראשון שלכם',
    'pages.delete.goes': 'ייעלם',
    'The Page in Content and in search.': 'הדף ב\'תוכן\' ובחיפוש.',
    '{posts} with photos and recordings.': '{posts} עם תמונות והקלטות.',
    'Comments and likes under them.': 'התגובות והלייקים שמתחתיהם.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} של הדף וההתראות שלהם על שידורי ה־LIVE שלכם.',
    'The Page\'s contact details.': 'פרטי הקשר של הדף.',
    'pages.delete.stays': 'נשאר',
    'Your account: name, photo and cover.':
        'החשבון שלכם: שם, תמונה ותמונת נושא.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'חברים, צ\'אטים, שרתים, Voice Moments ו־Yeels.',
    'Exception: reported content': 'חריג: תוכן שדווח',
    'We may keep reported content, not publicly, for up to 90 days.':
        'תוכן שדווח עשוי להישמר, לא באופן ציבורי, עד 90 יום.',
    'You have 30 days to come back': 'יש לכם 30 יום לחזור',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'נסתיר את הדף מיד ונמחק אותו בתאריך {date}. עד אז אפשר לשחזר אותו. לשחזור נדרש Premium או VIP פעיל.',
    'Type the Page name': 'הקלידו את שם הדף',
    'To confirm, type: {name}': 'לאישור, הקלידו: {name}',
    'pages.statusPendingDeletion': 'מיועד למחיקה',
    'The Page will be deleted on {date}': 'הדף יימחק בתאריך {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'אחרים כבר לא רואים אותו, ורק אתם רואים את הפוסטים. עד אז אפשר לשחזר אותו יחד עם הפוסטים והעוקבים.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'אחרים כבר לא רואים אותו. עד אז אפשר לשחזר אותו יחד עם הפוסטים והעוקבים. לשחזור נדרש Premium או VIP פעיל.',
    'Restore Page': 'שחזור הדף',
    'Comes back to Content with its posts and followers':
        'חוזר ל\'תוכן\' יחד עם הפוסטים והעוקבים',
    'Page restored': 'הדף שוחזר',
    'Delete now, don\'t wait': 'למחוק עכשיו, בלי לחכות',
    'Without waiting until {date}. This can\'t be undone.':
        'בלי לחכות עד {date}. אי אפשר לבטל את הפעולה.',
    'Delete the Page now?': 'למחוק את הדף עכשיו?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'הפוסטים, העוקבים ופרטי הקשר נמחקים מיד ואי אפשר לשחזר אותם. אפשר ליצור דף חדש אחרי 7 ימים.',
    'Deleting the Page': 'הדף בתהליך מחיקה',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'הפוסטים והעוקבים מוסרים ברקע. אפשר ליצור דף חדש 7 ימים אחרי הסיום.',
    'You can create a new Page after {date}.': 'אפשר ליצור דף חדש אחרי {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'הדף שלכם יימחק בעוד 3 ימים. שחזרו אותו בהגדרות הדף אם תרצו לשמור אותו.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'אפשר ליצור דף חדש 7 ימים אחרי מחיקת הדף הקודם.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'ברור לי שפרטי הקשר יהיו ציבוריים. הם נשמרים כל עוד הדף מושהה ונמחקים יחד עם הדף. אפשר לנקות אותם בכל עת.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'הפרופיל שלכם יוצג כדף. אפשר להשהות או למחוק אותו בכל עת בהגדרות הדף.',
    'Page deleted': 'הדף נמחק',
    'pages.delete.confirmIdentity': 'אשרו שזה אתם',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'כדי למחוק את הדף עכשיו נדרשת התחברות עדכנית. הזינו את הסיסמה.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'לא הצלחנו לאשר שזה אתם, ולכן שום דבר לא נמחק. נסו שוב, או התנתקו והתחברו מחדש.',
    'Deletion cancelled. The Page stays paused.':
        'המחיקה בוטלה. הדף נשאר מושהה.',
    '{count} posts.zero': '{count} פוסטים',
    '{count} posts.one': '{count} פוסט',
    '{count} posts.two': '{count} פוסטים',
    '{count} posts.few': '{count} פוסטים',
    '{count} posts.many': '{count} פוסטים',
    '{count} posts.other': '{count} פוסטים',
  },
  'fa': <String, String>{
    'Delete all posts': 'حذف همه پست‌ها',
    'The Page and its followers stay': 'صفحه و دنبال‌کنندگان می‌مانند',
    'Delete Page': 'حذف صفحه',
    'Posts, followers and contact details. Your account stays.':
        'پست‌ها، دنبال‌کنندگان و اطلاعات تماس. حساب شما می‌ماند.',
    'Delete {posts}?': '{posts} حذف شود؟',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'نظرها و پسندهای زیر آن‌ها هم ناپدید می‌شوند. صفحه و {followers} می‌مانند. این کار قابل بازگشت نیست.',
    'Delete posts': 'حذف پست‌ها',
    'Posts deleted': 'پست‌ها حذف شدند',
    'Deleting posts': 'در حال حذف پست‌ها',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'در پس‌زمینه و معمولاً ظرف چند دقیقه ناپدید می‌شوند. صفحه و {followers} می‌مانند.',
    'Publish your first post': 'اولین پست خود را منتشر کنید',
    'pages.delete.goes': 'ناپدید می‌شود',
    'The Page in Content and in search.': 'صفحه در «مواد» و در جست‌وجو.',
    '{posts} with photos and recordings.':
        '{posts} همراه با عکس‌ها و صداهای ضبط‌شده.',
    'Comments and likes under them.': 'نظرها و پسندهای زیر آن‌ها.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} صفحه و اعلان‌هایشان درباره LIVE شما.',
    'The Page\'s contact details.': 'اطلاعات تماس صفحه.',
    'pages.delete.stays': 'می‌ماند',
    'Your account: name, photo and cover.': 'حساب شما: نام، عکس و کاور.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'دوستان، گفت‌وگوها، سرورها، Voice Moments و Yeels.',
    'Exception: reported content': 'استثنا: محتوای گزارش‌شده',
    'We may keep reported content, not publicly, for up to 90 days.':
        'محتوای گزارش‌شده را ممکن است تا ۹۰ روز به‌صورت غیرعمومی نگه داریم.',
    'You have 30 days to come back': '۳۰ روز برای بازگشت فرصت دارید',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'صفحه را فوراً پنهان می‌کنیم و در تاریخ {date} حذف می‌کنیم. تا آن روز می‌توانید آن را بازیابی کنید. بازیابی به Premium یا VIP فعال نیاز دارد.',
    'Type the Page name': 'نام صفحه را بنویسید',
    'To confirm, type: {name}': 'برای تأیید بنویسید: {name}',
    'pages.statusPendingDeletion': 'در انتظار حذف',
    'The Page will be deleted on {date}': 'صفحه در تاریخ {date} حذف می‌شود',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'دیگران دیگر آن را نمی‌بینند و پست‌ها را فقط شما می‌بینید. تا آن روز می‌توانید آن را همراه با پست‌ها و دنبال‌کنندگان بازیابی کنید.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'دیگران دیگر آن را نمی‌بینند. تا آن روز می‌توانید آن را همراه با پست‌ها و دنبال‌کنندگان بازیابی کنید. بازیابی به Premium یا VIP فعال نیاز دارد.',
    'Restore Page': 'بازیابی صفحه',
    'Comes back to Content with its posts and followers':
        'همراه با پست‌ها و دنبال‌کنندگان به «مواد» برمی‌گردد',
    'Page restored': 'صفحه بازیابی شد',
    'Delete now, don\'t wait': 'همین حالا حذف شود، بدون انتظار',
    'Without waiting until {date}. This can\'t be undone.':
        'بدون انتظار تا {date}. این کار قابل بازگشت نیست.',
    'Delete the Page now?': 'صفحه همین حالا حذف شود؟',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'پست‌ها، دنبال‌کنندگان و اطلاعات تماس فوراً حذف می‌شوند و قابل بازیابی نیستند. پس از ۷ روز می‌توانید صفحه جدیدی بسازید.',
    'Deleting the Page': 'در حال حذف صفحه',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'پست‌ها و دنبال‌کنندگان در پس‌زمینه برداشته می‌شوند. ۷ روز پس از پایان می‌توانید صفحه جدیدی بسازید.',
    'You can create a new Page after {date}.':
        'پس از {date} می‌توانید صفحه جدیدی بسازید.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'صفحه شما ۳ روز دیگر حذف می‌شود. اگر می‌خواهید آن را نگه دارید، در تنظیمات صفحه بازیابی‌اش کنید.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'صفحه جدید را می‌توان ۷ روز پس از حذف صفحه قبلی ساخت.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'می‌دانم که اطلاعات تماس عمومی خواهد بود. تا زمانی که صفحه متوقف است ذخیره می‌ماند و همراه با صفحه حذف می‌شود. هر زمان بخواهم می‌توانم آن را پاک کنم.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'نمایه شما به‌صورت صفحه نمایش داده می‌شود. هر زمان بخواهید می‌توانید در تنظیمات صفحه آن را متوقف یا حذف کنید.',
    'Page deleted': 'صفحه حذف شد',
    'pages.delete.confirmIdentity': 'تأیید کنید که خودتان هستید',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'برای حذف فوری صفحه، ورود تازه لازم است. گذرواژه‌تان را وارد کنید.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'نتوانستیم تأیید کنیم که خودتان هستید، بنابراین چیزی حذف نشد. دوباره تلاش کنید یا از حساب خارج شوید و دوباره وارد شوید.',
    'Deletion cancelled. The Page stays paused.':
        'حذف لغو شد. صفحه همچنان متوقف است.',
    '{count} posts.zero': '{count} پست',
    '{count} posts.one': '{count} پست',
    '{count} posts.two': '{count} پست',
    '{count} posts.few': '{count} پست',
    '{count} posts.many': '{count} پست',
    '{count} posts.other': '{count} پست',
  },
  'sw': <String, String>{
    'Delete all posts': 'Futa machapisho yote',
    'The Page and its followers stay': 'Ukurasa na wafuasi wanabaki',
    'Delete Page': 'Futa ukurasa',
    'Posts, followers and contact details. Your account stays.':
        'Machapisho, wafuasi na maelezo ya mawasiliano. Akaunti yako inabaki.',
    'Delete {posts}?': 'Ufute {posts}?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'Maoni na vipendwa vilivyo chini yake pia vitatoweka. Ukurasa na {followers} wanabaki. Hatua hii haiwezi kutenduliwa.',
    'Delete posts': 'Futa machapisho',
    'Posts deleted': 'Machapisho yamefutwa',
    'Deleting posts': 'Machapisho yanafutwa',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'Yanatoweka chinichini, kwa kawaida ndani ya dakika chache. Ukurasa na {followers} wanabaki.',
    'Publish your first post': 'Chapisha chapisho lako la kwanza',
    'pages.delete.goes': 'Kitatoweka',
    'The Page in Content and in search.':
        'Ukurasa kwenye Maudhui na kwenye utafutaji.',
    '{posts} with photos and recordings.': '{posts} yenye picha na rekodi.',
    'Comments and likes under them.': 'Maoni na vipendwa vilivyo chini yake.',
    '{followers} of the Page and their notifications about your LIVE.':
        '{followers} wa ukurasa na arifa zao kuhusu LIVE zako.',
    'The Page\'s contact details.': 'Maelezo ya mawasiliano ya ukurasa.',
    'pages.delete.stays': 'Kinabaki',
    'Your account: name, photo and cover.':
        'Akaunti yako: jina, picha na jalada.',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'Marafiki, gumzo, seva, Voice Moments na Yeels.',
    'Exception: reported content': 'Isipokuwa: maudhui yaliyoripotiwa',
    'We may keep reported content, not publicly, for up to 90 days.':
        'Maudhui yaliyoripotiwa tunaweza kuyahifadhi bila kuyaonyesha hadharani kwa hadi siku 90.',
    'You have 30 days to come back': 'Una siku 30 za kurudi',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'Tunaficha ukurasa mara moja na kuufuta tarehe {date}. Hadi siku hiyo unaweza kuurejesha. Kurejesha kunahitaji Premium au VIP inayotumika.',
    'Type the Page name': 'Andika jina la ukurasa',
    'To confirm, type: {name}': 'Ili kuthibitisha, andika: {name}',
    'pages.statusPendingDeletion': 'Utafutwa',
    'The Page will be deleted on {date}': 'Ukurasa utafutwa tarehe {date}',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'Wengine hawauoni tena; ni wewe tu unayeona machapisho. Hadi siku hiyo unaweza kuurejesha pamoja na machapisho na wafuasi.',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'Wengine hawauoni tena. Hadi siku hiyo unaweza kuurejesha pamoja na machapisho na wafuasi. Kurejesha kunahitaji Premium au VIP inayotumika.',
    'Restore Page': 'Rejesha ukurasa',
    'Comes back to Content with its posts and followers':
        'Unarudi kwenye Maudhui pamoja na machapisho na wafuasi',
    'Page restored': 'Ukurasa umerejeshwa',
    'Delete now, don\'t wait': 'Futa sasa, usisubiri',
    'Without waiting until {date}. This can\'t be undone.':
        'Bila kusubiri hadi {date}. Hatua hii haiwezi kutenduliwa.',
    'Delete the Page now?': 'Ufute ukurasa sasa?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'Machapisho, wafuasi na maelezo ya mawasiliano yanafutwa mara moja na hayawezi kurejeshwa. Unaweza kuunda ukurasa mpya baada ya siku 7.',
    'Deleting the Page': 'Ukurasa unafutwa',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'Machapisho na wafuasi wanaondolewa chinichini. Unaweza kuunda ukurasa mpya siku 7 baada ya kukamilika.',
    'You can create a new Page after {date}.':
        'Unaweza kuunda ukurasa mpya baada ya {date}.',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'Ukurasa wako utafutwa baada ya siku 3. Urejeshe kwenye mipangilio ya ukurasa ukitaka kuuhifadhi.',
    'A new Page can be created 7 days after the previous one was deleted.':
        'Ukurasa mpya unaweza kuundwa siku 7 baada ya ule wa awali kufutwa.',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'Ninaelewa kuwa maelezo ya mawasiliano yatakuwa ya umma. Yanabaki yamehifadhiwa wakati ukurasa umesitishwa na yanafutwa pamoja na ukurasa. Ninaweza kuyafuta wakati wowote.',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'Wasifu wako utaonekana kama ukurasa. Unaweza kuusitisha au kuufuta wakati wowote kwenye mipangilio ya ukurasa.',
    'Page deleted': 'Ukurasa umefutwa',
    'pages.delete.confirmIdentity': 'Thibitisha kuwa ni wewe',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'Kufuta ukurasa sasa kunahitaji uwe umeingia hivi karibuni. Weka nenosiri lako.',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'Hatukuweza kuthibitisha kuwa ni wewe, kwa hivyo hakuna kilichofutwa. Jaribu tena, au ondoka kisha uingie tena.',
    'Deletion cancelled. The Page stays paused.':
        'Ufutaji umeghairiwa. Ukurasa unabaki umesitishwa.',
    '{count} posts.zero': 'Machapisho {count}',
    '{count} posts.one': 'Chapisho {count}',
    '{count} posts.two': 'Machapisho {count}',
    '{count} posts.few': 'Machapisho {count}',
    '{count} posts.many': 'Machapisho {count}',
    '{count} posts.other': 'Machapisho {count}',
  },
  'hi': <String, String>{
    'Delete all posts': 'सभी पोस्ट मिटाएँ',
    'The Page and its followers stay': 'पेज और फ़ॉलोअर्स बने रहते हैं',
    'Delete Page': 'पेज मिटाएँ',
    'Posts, followers and contact details. Your account stays.':
        'पोस्ट, फ़ॉलोअर्स और संपर्क जानकारी। आपका खाता बना रहता है।',
    'Delete {posts}?': '{posts} मिटाएँ?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'इनके नीचे की टिप्पणियाँ और लाइक भी हट जाएँगे। पेज और {followers} बने रहेंगे। इसे वापस नहीं किया जा सकता।',
    'Delete posts': 'पोस्ट मिटाएँ',
    'Posts deleted': 'पोस्ट मिटा दी गईं',
    'Deleting posts': 'पोस्ट मिटाई जा रही हैं',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'ये बैकग्राउंड में, आम तौर पर कुछ मिनटों में हट जाती हैं। पेज और {followers} बने रहेंगे।',
    'Publish your first post': 'अपनी पहली पोस्ट प्रकाशित करें',
    'pages.delete.goes': 'हट जाएगा',
    'The Page in Content and in search.': 'सामग्री और खोज में दिखने वाला पेज।',
    '{posts} with photos and recordings.': 'फ़ोटो और रिकॉर्डिंग वाली {posts}।',
    'Comments and likes under them.': 'इनके नीचे की टिप्पणियाँ और लाइक।',
    '{followers} of the Page and their notifications about your LIVE.':
        'पेज के {followers} और आपके LIVE के बारे में उनकी सूचनाएँ।',
    'The Page\'s contact details.': 'पेज की संपर्क जानकारी।',
    'pages.delete.stays': 'बना रहेगा',
    'Your account: name, photo and cover.': 'आपका खाता: नाम, फ़ोटो और कवर।',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'दोस्त, चैट, सर्वर, Voice Moments और Yeels।',
    'Exception: reported content': 'अपवाद: रिपोर्ट की गई सामग्री',
    'We may keep reported content, not publicly, for up to 90 days.':
        'रिपोर्ट की गई सामग्री हम गैर-सार्वजनिक रूप से 90 दिनों तक रख सकते हैं।',
    'You have 30 days to come back': 'वापस आने के लिए आपके पास 30 दिन हैं',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'हम पेज को तुरंत छिपा देंगे और {date} को मिटा देंगे। उस दिन तक आप इसे बहाल कर सकते हैं। बहाल करने के लिए सक्रिय Premium या VIP ज़रूरी है।',
    'Type the Page name': 'पेज का नाम लिखें',
    'To confirm, type: {name}': 'पुष्टि के लिए लिखें: {name}',
    'pages.statusPendingDeletion': 'मिटाया जाएगा',
    'The Page will be deleted on {date}': 'पेज {date} को मिटा दिया जाएगा',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'दूसरे लोग इसे अब नहीं देखते; पोस्ट सिर्फ़ आप देखते हैं। उस दिन तक आप इसे पोस्ट और फ़ॉलोअर्स के साथ बहाल कर सकते हैं।',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'दूसरे लोग इसे अब नहीं देखते। उस दिन तक आप इसे पोस्ट और फ़ॉलोअर्स के साथ बहाल कर सकते हैं। बहाल करने के लिए सक्रिय Premium या VIP ज़रूरी है।',
    'Restore Page': 'पेज बहाल करें',
    'Comes back to Content with its posts and followers':
        'पोस्ट और फ़ॉलोअर्स के साथ सामग्री में वापस आता है',
    'Page restored': 'पेज बहाल हो गया',
    'Delete now, don\'t wait': 'अभी मिटाएँ, इंतज़ार न करें',
    'Without waiting until {date}. This can\'t be undone.':
        '{date} तक इंतज़ार किए बिना। इसे वापस नहीं किया जा सकता।',
    'Delete the Page now?': 'पेज अभी मिटाएँ?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'पोस्ट, फ़ॉलोअर्स और संपर्क जानकारी तुरंत मिटा दी जाती है और बहाल नहीं की जा सकती। 7 दिन बाद आप नया पेज बना सकते हैं।',
    'Deleting the Page': 'पेज मिटाया जा रहा है',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'पोस्ट और फ़ॉलोअर्स बैकग्राउंड में हटाए जा रहे हैं। पूरा होने के 7 दिन बाद आप नया पेज बना सकते हैं।',
    'You can create a new Page after {date}.':
        '{date} के बाद आप नया पेज बना सकते हैं।',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'आपका पेज 3 दिन में मिटा दिया जाएगा। इसे रखना चाहते हैं तो पेज सेटिंग में बहाल करें।',
    'A new Page can be created 7 days after the previous one was deleted.':
        'पिछला पेज मिटाने के 7 दिन बाद नया पेज बनाया जा सकता है।',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'मैं समझता/समझती हूँ कि संपर्क जानकारी सार्वजनिक होगी। पेज रुका होने पर यह सेव रहती है और पेज के साथ मिटा दी जाती है। मैं इसे कभी भी हटा सकता/सकती हूँ।',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'आपकी प्रोफ़ाइल पेज के रूप में दिखेगी। आप इसे पेज सेटिंग में कभी भी रोक या मिटा सकते हैं।',
    'Page deleted': 'पेज मिटा दिया गया',
    'pages.delete.confirmIdentity': 'पुष्टि करें कि यह आप ही हैं',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'पेज अभी मिटाने के लिए हाल का साइन-इन ज़रूरी है। अपना पासवर्ड डालें।',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'हम पुष्टि नहीं कर सके कि यह आप ही हैं, इसलिए कुछ भी नहीं मिटाया गया। फिर कोशिश करें, या साइन आउट करके दोबारा साइन इन करें।',
    'Deletion cancelled. The Page stays paused.':
        'मिटाना रद्द किया गया। पेज रुका हुआ रहेगा।',
    '{count} posts.zero': '{count} पोस्ट',
    '{count} posts.one': '{count} पोस्ट',
    '{count} posts.two': '{count} पोस्ट',
    '{count} posts.few': '{count} पोस्ट',
    '{count} posts.many': '{count} पोस्ट',
    '{count} posts.other': '{count} पोस्ट',
  },
  'bn': <String, String>{
    'Delete all posts': 'সব পোস্ট মুছুন',
    'The Page and its followers stay': 'পেজ ও ফলোয়ার থেকে যাবে',
    'Delete Page': 'পেজ মুছুন',
    'Posts, followers and contact details. Your account stays.':
        'পোস্ট, ফলোয়ার ও যোগাযোগের তথ্য। আপনার অ্যাকাউন্ট থেকে যাবে।',
    'Delete {posts}?': '{posts} মুছবেন?',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'এগুলোর নিচের মন্তব্য ও লাইকও মুছে যাবে। পেজ ও {followers} থেকে যাবে। এটি ফিরিয়ে আনা যাবে না।',
    'Delete posts': 'পোস্ট মুছুন',
    'Posts deleted': 'পোস্ট মুছে ফেলা হয়েছে',
    'Deleting posts': 'পোস্ট মোছা হচ্ছে',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'এগুলো ব্যাকগ্রাউন্ডে, সাধারণত কয়েক মিনিটের মধ্যে মুছে যায়। পেজ ও {followers} থেকে যাবে।',
    'Publish your first post': 'আপনার প্রথম পোস্ট প্রকাশ করুন',
    'pages.delete.goes': 'মুছে যাবে',
    'The Page in Content and in search.': 'কনটেন্ট ও সার্চে থাকা পেজ।',
    '{posts} with photos and recordings.': 'ছবি ও রেকর্ডিংসহ {posts}।',
    'Comments and likes under them.': 'এগুলোর নিচের মন্তব্য ও লাইক।',
    '{followers} of the Page and their notifications about your LIVE.':
        'পেজের {followers} এবং আপনার LIVE সম্পর্কে তাদের নোটিফিকেশন।',
    'The Page\'s contact details.': 'পেজের যোগাযোগের তথ্য।',
    'pages.delete.stays': 'থেকে যাবে',
    'Your account: name, photo and cover.':
        'আপনার অ্যাকাউন্ট: নাম, ছবি ও কভার।',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'বন্ধু, চ্যাট, সার্ভার, Voice Moments ও Yeels।',
    'Exception: reported content': 'ব্যতিক্রম: রিপোর্ট করা কনটেন্ট',
    'We may keep reported content, not publicly, for up to 90 days.':
        'রিপোর্ট করা কনটেন্ট আমরা অপ্রকাশ্যভাবে সর্বোচ্চ ৯০ দিন রাখতে পারি।',
    'You have 30 days to come back': 'ফিরে আসার জন্য আপনার ৩০ দিন আছে',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'আমরা পেজটি সঙ্গে সঙ্গে লুকিয়ে ফেলব এবং {date} তারিখে মুছে ফেলব। সেই দিন পর্যন্ত আপনি এটি ফিরিয়ে আনতে পারবেন। ফিরিয়ে আনতে সক্রিয় Premium বা VIP প্রয়োজন।',
    'Type the Page name': 'পেজের নাম লিখুন',
    'To confirm, type: {name}': 'নিশ্চিত করতে লিখুন: {name}',
    'pages.statusPendingDeletion': 'মোছা হবে',
    'The Page will be deleted on {date}': 'পেজটি {date} তারিখে মুছে ফেলা হবে',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'অন্যরা এটি আর দেখতে পায় না; পোস্টগুলো শুধু আপনি দেখেন। সেই দিন পর্যন্ত পোস্ট ও ফলোয়ারসহ এটি ফিরিয়ে আনতে পারবেন।',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'অন্যরা এটি আর দেখতে পায় না। সেই দিন পর্যন্ত পোস্ট ও ফলোয়ারসহ এটি ফিরিয়ে আনতে পারবেন। ফিরিয়ে আনতে সক্রিয় Premium বা VIP প্রয়োজন।',
    'Restore Page': 'পেজ ফিরিয়ে আনুন',
    'Comes back to Content with its posts and followers':
        'পোস্ট ও ফলোয়ারসহ কনটেন্টে ফিরে আসে',
    'Page restored': 'পেজ ফিরিয়ে আনা হয়েছে',
    'Delete now, don\'t wait': 'এখনই মুছুন, অপেক্ষা নয়',
    'Without waiting until {date}. This can\'t be undone.':
        '{date} পর্যন্ত অপেক্ষা না করে। এটি ফিরিয়ে আনা যাবে না।',
    'Delete the Page now?': 'পেজটি এখনই মুছবেন?',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'পোস্ট, ফলোয়ার ও যোগাযোগের তথ্য সঙ্গে সঙ্গে মুছে যায় এবং ফিরিয়ে আনা যায় না। ৭ দিন পর আপনি নতুন পেজ তৈরি করতে পারবেন।',
    'Deleting the Page': 'পেজ মোছা হচ্ছে',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'পোস্ট ও ফলোয়ার ব্যাকগ্রাউন্ডে সরানো হচ্ছে। শেষ হওয়ার ৭ দিন পর আপনি নতুন পেজ তৈরি করতে পারবেন।',
    'You can create a new Page after {date}.':
        '{date}-এর পরে আপনি নতুন পেজ তৈরি করতে পারবেন।',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'আপনার পেজ ৩ দিনের মধ্যে মুছে ফেলা হবে। রাখতে চাইলে পেজ সেটিংসে গিয়ে ফিরিয়ে আনুন।',
    'A new Page can be created 7 days after the previous one was deleted.':
        'আগের পেজ মোছার ৭ দিন পর নতুন পেজ তৈরি করা যায়।',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'আমি বুঝি যে যোগাযোগের তথ্য সবার জন্য দৃশ্যমান হবে। পেজ বিরতিতে থাকলে এগুলো সংরক্ষিত থাকে এবং পেজের সঙ্গে মুছে যায়। আমি যেকোনো সময় এগুলো মুছতে পারি।',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'আপনার প্রোফাইল পেজ হিসেবে দেখাবে। পেজ সেটিংসে গিয়ে যেকোনো সময় এটি বিরতিতে রাখতে বা মুছতে পারবেন।',
    'Page deleted': 'পেজ মুছে ফেলা হয়েছে',
    'pages.delete.confirmIdentity': 'নিশ্চিত করুন যে এটি আপনিই',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'পেজটি এখনই মুছতে সাম্প্রতিক সাইন-ইন দরকার। আপনার পাসওয়ার্ড দিন।',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'আমরা নিশ্চিত হতে পারিনি যে এটি আপনিই, তাই কিছুই মোছা হয়নি। আবার চেষ্টা করুন, অথবা সাইন আউট করে আবার সাইন ইন করুন।',
    'Deletion cancelled. The Page stays paused.':
        'মুছে ফেলা বাতিল হয়েছে। পেজ বিরতিতেই থাকছে।',
    '{count} posts.zero': '{count}টি পোস্ট',
    '{count} posts.one': '{count}টি পোস্ট',
    '{count} posts.two': '{count}টি পোস্ট',
    '{count} posts.few': '{count}টি পোস্ট',
    '{count} posts.many': '{count}টি পোস্ট',
    '{count} posts.other': '{count}টি পোস্ট',
  },
  'ur': <String, String>{
    'Delete all posts': 'تمام پوسٹس حذف کریں',
    'The Page and its followers stay': 'پیج اور فالوورز باقی رہتے ہیں',
    'Delete Page': 'پیج حذف کریں',
    'Posts, followers and contact details. Your account stays.':
        'پوسٹس، فالوورز اور رابطے کی معلومات۔ آپ کا اکاؤنٹ باقی رہتا ہے۔',
    'Delete {posts}?': '{posts} حذف کریں؟',
    'Comments and likes under them go too. The Page and {followers} stay. This can\'t be undone.':
        'ان کے نیچے کے تبصرے اور لائکس بھی ختم ہو جائیں گے۔ پیج اور {followers} باقی رہیں گے۔ اسے واپس نہیں کیا جا سکتا۔',
    'Delete posts': 'پوسٹس حذف کریں',
    'Posts deleted': 'پوسٹس حذف ہو گئیں',
    'Deleting posts': 'پوسٹس حذف ہو رہی ہیں',
    'They disappear in the background, usually within several minutes. The Page and {followers} stay.':
        'یہ پس منظر میں، عام طور پر چند منٹ میں ختم ہو جاتی ہیں۔ پیج اور {followers} باقی رہیں گے۔',
    'Publish your first post': 'اپنی پہلی پوسٹ شائع کریں',
    'pages.delete.goes': 'ختم ہو جائے گا',
    'The Page in Content and in search.': 'مواد اور تلاش میں نظر آنے والا پیج۔',
    '{posts} with photos and recordings.': 'تصاویر اور ریکارڈنگز والی {posts}۔',
    'Comments and likes under them.': 'ان کے نیچے کے تبصرے اور لائکس۔',
    '{followers} of the Page and their notifications about your LIVE.':
        'پیج کے {followers} اور آپ کے LIVE کے بارے میں ان کی اطلاعات۔',
    'The Page\'s contact details.': 'پیج کی رابطے کی معلومات۔',
    'pages.delete.stays': 'باقی رہے گا',
    'Your account: name, photo and cover.': 'آپ کا اکاؤنٹ: نام، تصویر اور کور۔',
    'Friends, chats, servers, Voice Moments and Yeels.':
        'دوست، چیٹس، سرورز، Voice Moments اور Yeels۔',
    'Exception: reported content': 'استثنا: رپورٹ شدہ مواد',
    'We may keep reported content, not publicly, for up to 90 days.':
        'رپورٹ شدہ مواد ہم غیر عوامی طور پر 90 دن تک رکھ سکتے ہیں۔',
    'You have 30 days to come back': 'واپسی کے لیے آپ کے پاس 30 دن ہیں',
    'We hide the Page right away and delete it on {date}. Until then you can restore it. Restoring needs active Premium or VIP.':
        'ہم پیج کو فوراً چھپا دیں گے اور {date} کو حذف کر دیں گے۔ اس دن تک آپ اسے بحال کر سکتے ہیں۔ بحالی کے لیے فعال Premium یا VIP ضروری ہے۔',
    'Type the Page name': 'پیج کا نام لکھیں',
    'To confirm, type: {name}': 'تصدیق کے لیے لکھیں: {name}',
    'pages.statusPendingDeletion': 'حذف ہونے والا',
    'The Page will be deleted on {date}': 'پیج {date} کو حذف کر دیا جائے گا',
    'Others no longer see it; only you see the posts. Until then you can restore it with its posts and followers.':
        'دوسرے اسے اب نہیں دیکھتے؛ پوسٹس صرف آپ دیکھتے ہیں۔ اس دن تک آپ اسے پوسٹس اور فالوورز کے ساتھ بحال کر سکتے ہیں۔',
    'Others no longer see it. Until then you can restore it with its posts and followers. Restoring needs active Premium or VIP.':
        'دوسرے اسے اب نہیں دیکھتے۔ اس دن تک آپ اسے پوسٹس اور فالوورز کے ساتھ بحال کر سکتے ہیں۔ بحالی کے لیے فعال Premium یا VIP ضروری ہے۔',
    'Restore Page': 'پیج بحال کریں',
    'Comes back to Content with its posts and followers':
        'پوسٹس اور فالوورز کے ساتھ مواد میں واپس آتا ہے',
    'Page restored': 'پیج بحال ہو گیا',
    'Delete now, don\'t wait': 'ابھی حذف کریں، انتظار نہ کریں',
    'Without waiting until {date}. This can\'t be undone.':
        '{date} تک انتظار کیے بغیر۔ اسے واپس نہیں کیا جا سکتا۔',
    'Delete the Page now?': 'پیج ابھی حذف کریں؟',
    'Posts, followers and contact details are deleted right away and can\'t be restored. You can create a new Page after 7 days.':
        'پوسٹس، فالوورز اور رابطے کی معلومات فوراً حذف ہو جاتی ہیں اور بحال نہیں ہو سکتیں۔ 7 دن بعد آپ نیا پیج بنا سکتے ہیں۔',
    'Deleting the Page': 'پیج حذف ہو رہا ہے',
    'Posts and followers are being removed in the background. You can create a new Page 7 days after it is gone.':
        'پوسٹس اور فالوورز پس منظر میں ہٹائے جا رہے ہیں۔ مکمل ہونے کے 7 دن بعد آپ نیا پیج بنا سکتے ہیں۔',
    'You can create a new Page after {date}.':
        '{date} کے بعد آپ نیا پیج بنا سکتے ہیں۔',
    'Your Page will be deleted in 3 days. Restore it in Page settings to keep it.':
        'آپ کا پیج 3 دن میں حذف کر دیا جائے گا۔ اسے رکھنا چاہتے ہیں تو پیج کی ترتیبات میں بحال کریں۔',
    'A new Page can be created 7 days after the previous one was deleted.':
        'پچھلا پیج حذف ہونے کے 7 دن بعد نیا پیج بنایا جا سکتا ہے۔',
    'I understand that the contact details will be public. They stay saved while the Page is paused and are deleted together with the Page. I can clear them any time.':
        'میں سمجھتا/سمجھتی ہوں کہ رابطے کی معلومات عوامی ہوں گی۔ پیج رکا ہونے پر یہ محفوظ رہتی ہیں اور پیج کے ساتھ حذف ہو جاتی ہیں۔ میں انہیں کسی بھی وقت صاف کر سکتا/سکتی ہوں۔',
    'Your profile will show as a Page. You can pause or delete it any time in Page settings.':
        'آپ کی پروفائل پیج کے طور پر دکھائی دے گی۔ آپ اسے پیج کی ترتیبات میں کسی بھی وقت روک یا حذف کر سکتے ہیں۔',
    'Page deleted': 'پیج حذف ہو گیا',
    'pages.delete.confirmIdentity': 'تصدیق کریں کہ یہ آپ ہی ہیں',
    'Deleting the Page now needs a fresh sign-in. Enter your password.':
        'پیج ابھی حذف کرنے کے لیے تازہ سائن اِن ضروری ہے۔ اپنا پاس ورڈ درج کریں۔',
    'We couldn\'t confirm it is you, so nothing was deleted. Try again, or sign out and sign in again.':
        'ہم تصدیق نہیں کر سکے کہ یہ آپ ہی ہیں، اس لیے کچھ بھی حذف نہیں ہوا۔ دوبارہ کوشش کریں، یا سائن آؤٹ کر کے دوبارہ سائن اِن کریں۔',
    'Deletion cancelled. The Page stays paused.':
        'حذف منسوخ ہو گیا۔ پیج رکا ہوا رہے گا۔',
    '{count} posts.zero': '{count} پوسٹس',
    '{count} posts.one': '{count} پوسٹ',
    '{count} posts.two': '{count} پوسٹس',
    '{count} posts.few': '{count} پوسٹس',
    '{count} posts.many': '{count} پوسٹس',
    '{count} posts.other': '{count} پوسٹس',
  },
};
