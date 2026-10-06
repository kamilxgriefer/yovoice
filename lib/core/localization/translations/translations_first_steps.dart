/// Copy for "Zacznij tutaj" (firstSteps A, 2026-10-03): Start's checklist
/// card ("Start here", its progress, five steps with their hints and the
/// "Done" line) and the one action each of the three dead ends gained: the
/// server invite sheet with no friends ("Share the server link"), the empty
/// Notifications screen ("Find Pages to follow") and the empty friends list
/// ("Add friend").
///
/// English and Polish are authored at the call site (`FirstStepsCopy` in
/// `lib/features/home/presentation/first_steps_copy.dart`); this module gives
/// every other selectable locale an explicit translation, so none of these
/// strings falls back to English.
///
/// It also carries the MESSAGE each of those three dead ends shows above its
/// new action (title and body: "You are all caught up", "No friends yet",
/// "No friends to invite yet"). Those six strings are older than the actions
/// and were never catalogued, so 41 locales read an English sentence over a
/// translated button. They keep their call sites (`notifications_screen.dart`,
/// `friends_screen.dart`, `server_localized_copy.dart`): the catalog key is
/// the English phrase itself, and `test/first_steps_localization_test.dart`
/// fails if a call site's wording moves away from its key.
///
/// Two kinds of key live here:
///
/// * The final English phrase or template (`{done} of {total}`), resolved by
///   `AppLocalizations.text` / `.template`.
/// * `firstSteps.*` context keys for short words whose meaning depends on the
///   surface ("Close" the card, "Done" a ticked step, "Add friend" under the
///   empty friends list), resolved by `AppLocalizations.contextualText`.
///
/// "YO Voice" stays as written. "Voice" is the YO Moments format and uses the
/// word of `yoMoments.voiceFormat`; "Content" is the Treści destination and
/// uses the word of `navigation.content`; "Page" follows the Pages catalog.
/// Digits stay ASCII, as elsewhere in the catalog.
///
/// Every value keeps exactly the placeholders of its key
/// (`test/first_steps_localization_test.dart`).
const firstStepsTranslationKeys = <String>[
  'Start here',
  '{done} of {total}',
  'firstSteps.close',
  'firstSteps.stepDone',
  'Done. You know YO Voice now.',
  'Add a profile photo',
  'Friends will recognise you faster',
  'Add your first friend',
  'Search by name or send your link',
  'Join a server or create your own',
  'See public servers or start your own',
  'Record your first Voice',
  'A short voice recording, up to 60 seconds',
  'Follow a Page or creator',
  'You will see their news in Content',
  'Share the server link',
  "Couldn't share the link. Try again.",
  'Find Pages to follow',
  'firstSteps.addFriend',
  // The messages above the three dead ends' actions (see the header).
  'You are all caught up',
  'New friend requests, messages and activity will appear here.',
  'No friends yet',
  'Find someone and start building your circle.',
  'No friends to invite yet',
  'Add friends first — a server invitation can only go to a friend.',
];

const firstStepsTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'Start here': 'Hier starten',
    '{done} of {total}': '{done} von {total}',
    'firstSteps.close': 'Schließen',
    'firstSteps.stepDone': 'Erledigt',
    'Done. You know YO Voice now.': 'Fertig. Jetzt kennst du YO Voice.',
    'Add a profile photo': 'Profilbild hinzufügen',
    'Friends will recognise you faster': 'Freunde erkennen dich schneller',
    'Add your first friend': 'Ersten Freund hinzufügen',
    'Search by name or send your link':
        'Nach Namen suchen oder deinen Link senden',
    'Join a server or create your own':
        'Einem Server beitreten oder einen eigenen erstellen',
    'See public servers or start your own':
        'Öffentliche Server ansehen oder einen eigenen gründen',
    'Record your first Voice': 'Erste Stimme aufnehmen',
    'A short voice recording, up to 60 seconds':
        'Eine kurze Sprachaufnahme, bis zu 60 Sekunden',
    'Follow a Page or creator': 'Einer Seite oder Kreativen folgen',
    'You will see their news in Content':
        'Ihre Neuigkeiten siehst du unter Inhalte',
    'Share the server link': 'Serverlink teilen',
    "Couldn't share the link. Try again.":
        'Der Link konnte nicht geteilt werden. Versuche es erneut.',
    'Find Pages to follow': 'Seiten zum Folgen finden',
    'firstSteps.addFriend': 'Freund hinzufügen',
    'You are all caught up': 'Du bist auf dem neuesten Stand',
    'New friend requests, messages and activity will appear here.':
        'Neue Freundschaftsanfragen, Nachrichten und Aktivitäten erscheinen hier.',
    'No friends yet': 'Noch keine Freunde',
    'Find someone and start building your circle.':
        'Finde jemanden und bau dir deinen Kreis auf.',
    'No friends to invite yet': 'Noch keine Freunde zum Einladen',
    'Add friends first — a server invitation can only go to a friend.':
        'Füge zuerst Freunde hinzu – eine Servereinladung kann nur an Freunde gehen.',
  },
  'es': <String, String>{
    'Start here': 'Empieza aquí',
    '{done} of {total}': '{done} de {total}',
    'firstSteps.close': 'Cerrar',
    'firstSteps.stepDone': 'Hecho',
    'Done. You know YO Voice now.': 'Listo. Ya conoces YO Voice.',
    'Add a profile photo': 'Añadir una foto de perfil',
    'Friends will recognise you faster': 'Tus amigos te reconocerán antes',
    'Add your first friend': 'Añadir tu primer amigo',
    'Search by name or send your link': 'Busca por nombre o envía tu enlace',
    'Join a server or create your own': 'Unirte a un servidor o crear el tuyo',
    'See public servers or start your own':
        'Mira los servidores públicos o crea el tuyo',
    'Record your first Voice': 'Grabar tu primera Voz',
    'A short voice recording, up to 60 seconds':
        'Una grabación de voz corta, de hasta 60 segundos',
    'Follow a Page or creator': 'Seguir una página o a un creador',
    'You will see their news in Content': 'Verás sus novedades en Contenido',
    'Share the server link': 'Compartir el enlace del servidor',
    "Couldn't share the link. Try again.":
        'No se pudo compartir el enlace. Vuelve a intentarlo.',
    'Find Pages to follow': 'Buscar páginas para seguir',
    'firstSteps.addFriend': 'Añadir amigo',
    'You are all caught up': 'Estás al día',
    'New friend requests, messages and activity will appear here.':
        'Las nuevas solicitudes de amistad, mensajes y actividad aparecerán aquí.',
    'No friends yet': 'Aún no tienes amigos',
    'Find someone and start building your circle.':
        'Busca a alguien y empieza a crear tu círculo.',
    'No friends to invite yet': 'Aún no tienes amigos a quienes invitar',
    'Add friends first — a server invitation can only go to a friend.':
        'Primero añade amigos: una invitación al servidor solo puede enviarse a un amigo.',
  },
  'pt': <String, String>{
    'Start here': 'Começa aqui',
    '{done} of {total}': '{done} de {total}',
    'firstSteps.close': 'Fechar',
    'firstSteps.stepDone': 'Concluído',
    'Done. You know YO Voice now.': 'Pronto. Já conheces o YO Voice.',
    'Add a profile photo': 'Adicionar uma foto de perfil',
    'Friends will recognise you faster':
        'Os amigos reconhecem-te mais depressa',
    'Add your first friend': 'Adicionar o primeiro amigo',
    'Search by name or send your link':
        'Procura pelo nome ou envia a tua ligação',
    'Join a server or create your own': 'Entrar num servidor ou criar o teu',
    'See public servers or start your own':
        'Vê os servidores públicos ou cria o teu',
    'Record your first Voice': 'Gravar a primeira Voz',
    'A short voice recording, up to 60 seconds':
        'Uma gravação de voz curta, até 60 segundos',
    'Follow a Page or creator': 'Seguir uma página ou um criador',
    'You will see their news in Content': 'Vês as novidades deles em Conteúdos',
    'Share the server link': 'Partilhar a ligação do servidor',
    "Couldn't share the link. Try again.":
        'Não foi possível partilhar a ligação. Tenta novamente.',
    'Find Pages to follow': 'Encontrar páginas para seguir',
    'firstSteps.addFriend': 'Adicionar amigo',
    'You are all caught up': 'Está tudo em dia',
    'New friend requests, messages and activity will appear here.':
        'Os novos pedidos de amizade, mensagens e atividade aparecem aqui.',
    'No friends yet': 'Ainda não tens amigos',
    'Find someone and start building your circle.':
        'Encontra alguém e começa a criar o teu círculo.',
    'No friends to invite yet': 'Ainda não tens amigos para convidar',
    'Add friends first — a server invitation can only go to a friend.':
        'Adiciona amigos primeiro — um convite para o servidor só pode ser enviado a um amigo.',
  },
  'pt_BR': <String, String>{
    'Start here': 'Comece aqui',
    '{done} of {total}': '{done} de {total}',
    'firstSteps.close': 'Fechar',
    'firstSteps.stepDone': 'Concluído',
    'Done. You know YO Voice now.': 'Pronto. Você já conhece o YO Voice.',
    'Add a profile photo': 'Adicionar uma foto de perfil',
    'Friends will recognise you faster':
        'Seus amigos reconhecem você mais rápido',
    'Add your first friend': 'Adicionar o primeiro amigo',
    'Search by name or send your link': 'Busque pelo nome ou envie seu link',
    'Join a server or create your own': 'Entrar em um servidor ou criar o seu',
    'See public servers or start your own':
        'Veja os servidores públicos ou crie o seu',
    'Record your first Voice': 'Gravar a primeira Voz',
    'A short voice recording, up to 60 seconds':
        'Uma gravação de voz curta, de até 60 segundos',
    'Follow a Page or creator': 'Seguir uma página ou um criador',
    'You will see their news in Content':
        'Você vê as novidades deles em Conteúdo',
    'Share the server link': 'Compartilhar o link do servidor',
    "Couldn't share the link. Try again.":
        'Não foi possível compartilhar o link. Tente novamente.',
    'Find Pages to follow': 'Encontrar páginas para seguir',
    'firstSteps.addFriend': 'Adicionar amigo',
    'You are all caught up': 'Está tudo em dia',
    'New friend requests, messages and activity will appear here.':
        'Novas solicitações de amizade, mensagens e atividades aparecerão aqui.',
    'No friends yet': 'Você ainda não tem amigos',
    'Find someone and start building your circle.':
        'Encontre alguém e comece a formar seu círculo.',
    'No friends to invite yet': 'Você ainda não tem amigos para convidar',
    'Add friends first — a server invitation can only go to a friend.':
        'Adicione amigos primeiro — um convite para o servidor só pode ser enviado a um amigo.',
  },
  'fr': <String, String>{
    'Start here': 'Commencez ici',
    '{done} of {total}': '{done} sur {total}',
    'firstSteps.close': 'Fermer',
    'firstSteps.stepDone': 'Terminé',
    'Done. You know YO Voice now.':
        'C’est fait. Vous connaissez maintenant YO Voice.',
    'Add a profile photo': 'Ajouter une photo de profil',
    'Friends will recognise you faster':
        'Vos amis vous reconnaîtront plus vite',
    'Add your first friend': 'Ajouter votre premier ami',
    'Search by name or send your link':
        'Cherchez par nom ou envoyez votre lien',
    'Join a server or create your own':
        'Rejoindre un serveur ou créer le vôtre',
    'See public servers or start your own':
        'Voir les serveurs publics ou créer le vôtre',
    'Record your first Voice': 'Enregistrer votre première Voix',
    'A short voice recording, up to 60 seconds':
        'Un court enregistrement vocal, jusqu’à 60 secondes',
    'Follow a Page or creator': 'Suivre une page ou un créateur',
    'You will see their news in Content':
        'Vous verrez leurs nouveautés dans Contenus',
    'Share the server link': 'Partager le lien du serveur',
    "Couldn't share the link. Try again.":
        'Impossible de partager le lien. Réessayez.',
    'Find Pages to follow': 'Trouver des pages à suivre',
    'firstSteps.addFriend': 'Ajouter un ami',
    'You are all caught up': 'Vous êtes à jour',
    'New friend requests, messages and activity will appear here.':
        "Les nouvelles demandes d'ami, les messages et l'activité apparaîtront ici.",
    'No friends yet': "Pas encore d'amis",
    'Find someone and start building your circle.':
        "Trouvez quelqu'un et commencez à créer votre cercle.",
    'No friends to invite yet': "Pas encore d'amis à inviter",
    'Add friends first — a server invitation can only go to a friend.':
        "Ajoutez d'abord des amis : une invitation à un serveur ne peut être envoyée qu'à un ami.",
  },
  'it': <String, String>{
    'Start here': 'Inizia qui',
    '{done} of {total}': '{done} di {total}',
    'firstSteps.close': 'Chiudi',
    'firstSteps.stepDone': 'Fatto',
    'Done. You know YO Voice now.': 'Fatto. Ora conosci YO Voice.',
    'Add a profile photo': 'Aggiungi una foto del profilo',
    'Friends will recognise you faster':
        'Gli amici ti riconosceranno più in fretta',
    'Add your first friend': 'Aggiungi il tuo primo amico',
    'Search by name or send your link': 'Cerca per nome o invia il tuo link',
    'Join a server or create your own': 'Unisciti a un server o creane uno tuo',
    'See public servers or start your own':
        'Guarda i server pubblici o creane uno tuo',
    'Record your first Voice': 'Registra la tua prima Voce',
    'A short voice recording, up to 60 seconds':
        'Una breve registrazione vocale, fino a 60 secondi',
    'Follow a Page or creator': 'Segui una pagina o un creator',
    'You will see their news in Content': 'Vedrai le loro novità in Contenuti',
    'Share the server link': 'Condividi il link del server',
    "Couldn't share the link. Try again.":
        'Impossibile condividere il link. Riprova.',
    'Find Pages to follow': 'Trova pagine da seguire',
    'firstSteps.addFriend': 'Aggiungi amico',
    'You are all caught up': 'Hai già visto tutto',
    'New friend requests, messages and activity will appear here.':
        'Le nuove richieste di amicizia, i messaggi e le attività appariranno qui.',
    'No friends yet': 'Non hai ancora amici',
    'Find someone and start building your circle.':
        'Trova qualcuno e inizia a costruire la tua cerchia.',
    'No friends to invite yet': 'Non hai ancora amici da invitare',
    'Add friends first — a server invitation can only go to a friend.':
        'Aggiungi prima degli amici: un invito al server può essere inviato solo a un amico.',
  },
  'nl': <String, String>{
    'Start here': 'Begin hier',
    '{done} of {total}': '{done} van {total}',
    'firstSteps.close': 'Sluiten',
    'firstSteps.stepDone': 'Klaar',
    'Done. You know YO Voice now.': 'Klaar. Je kent YO Voice nu.',
    'Add a profile photo': 'Profielfoto toevoegen',
    'Friends will recognise you faster': 'Vrienden herkennen je sneller',
    'Add your first friend': 'Je eerste vriend toevoegen',
    'Search by name or send your link': 'Zoek op naam of stuur je link',
    'Join a server or create your own':
        'Word lid van een server of maak je eigen',
    'See public servers or start your own':
        'Bekijk openbare servers of begin je eigen',
    'Record your first Voice': 'Je eerste Stem opnemen',
    'A short voice recording, up to 60 seconds':
        'Een korte spraakopname, tot 60 seconden',
    'Follow a Page or creator': 'Een pagina of maker volgen',
    'You will see their news in Content': 'Hun nieuws zie je in Inhoud',
    'Share the server link': 'Serverlink delen',
    "Couldn't share the link. Try again.":
        'Kan de link niet delen. Probeer het opnieuw.',
    'Find Pages to follow': "Pagina's zoeken om te volgen",
    'firstSteps.addFriend': 'Vriend toevoegen',
    'You are all caught up': 'Je bent helemaal bij',
    'New friend requests, messages and activity will appear here.':
        'Nieuwe vriendschapsverzoeken, berichten en activiteit verschijnen hier.',
    'No friends yet': 'Nog geen vrienden',
    'Find someone and start building your circle.':
        'Zoek iemand en begin je kring op te bouwen.',
    'No friends to invite yet': 'Nog geen vrienden om uit te nodigen',
    'Add friends first — a server invitation can only go to a friend.':
        'Voeg eerst vrienden toe: een serveruitnodiging kun je alleen naar een vriend sturen.',
  },
  'ro': <String, String>{
    'Start here': 'Începe aici',
    '{done} of {total}': '{done} din {total}',
    'firstSteps.close': 'Închide',
    'firstSteps.stepDone': 'Gata',
    'Done. You know YO Voice now.': 'Gata. Acum cunoști YO Voice.',
    'Add a profile photo': 'Adaugă o fotografie de profil',
    'Friends will recognise you faster':
        'Prietenii te vor recunoaște mai repede',
    'Add your first friend': 'Adaugă primul prieten',
    'Search by name or send your link':
        'Caută după nume sau trimite linkul tău',
    'Join a server or create your own':
        'Intră pe un server sau creează-ți unul',
    'See public servers or start your own':
        'Vezi serverele publice sau creează-ți unul',
    'Record your first Voice': 'Înregistrează prima Voce',
    'A short voice recording, up to 60 seconds':
        'O scurtă înregistrare vocală, de până la 60 de secunde',
    'Follow a Page or creator': 'Urmărește o pagină sau un creator',
    'You will see their news in Content': 'Le vei vedea noutățile în Conținut',
    'Share the server link': 'Distribuie linkul serverului',
    "Couldn't share the link. Try again.":
        'Linkul nu a putut fi distribuit. Încearcă din nou.',
    'Find Pages to follow': 'Găsește pagini de urmărit',
    'firstSteps.addFriend': 'Adaugă prieten',
    'You are all caught up': 'Ești la zi',
    'New friend requests, messages and activity will appear here.':
        'Noile cereri de prietenie, mesaje și activități vor apărea aici.',
    'No friends yet': 'Încă nu ai prieteni',
    'Find someone and start building your circle.':
        'Găsește pe cineva și începe să-ți formezi cercul.',
    'No friends to invite yet': 'Încă nu ai prieteni de invitat',
    'Add friends first — a server invitation can only go to a friend.':
        'Adaugă mai întâi prieteni — o invitație pe server poate fi trimisă doar unui prieten.',
  },
  'tr': <String, String>{
    'Start here': 'Buradan başla',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': 'Kapat',
    'firstSteps.stepDone': 'Tamamlandı',
    'Done. You know YO Voice now.': 'Tamam. Artık YO Voice’u tanıyorsun.',
    'Add a profile photo': 'Profil fotoğrafı ekle',
    'Friends will recognise you faster': 'Arkadaşların seni daha çabuk tanır',
    'Add your first friend': 'İlk arkadaşını ekle',
    'Search by name or send your link': 'Adıyla ara veya bağlantını gönder',
    'Join a server or create your own':
        'Bir sunucuya katıl veya kendi sunucunu oluştur',
    'See public servers or start your own':
        'Herkese açık sunuculara bak veya kendininkini kur',
    'Record your first Voice': 'İlk Ses kaydını yap',
    'A short voice recording, up to 60 seconds':
        'Kısa bir ses kaydı, en fazla 60 saniye',
    'Follow a Page or creator': 'Bir sayfayı veya içerik üreticisini takip et',
    'You will see their news in Content':
        'Yeniliklerini İçerik bölümünde görürsün',
    'Share the server link': 'Sunucu bağlantısını paylaş',
    "Couldn't share the link. Try again.":
        'Bağlantı paylaşılamadı. Tekrar dene.',
    'Find Pages to follow': 'Takip edilecek sayfalar bul',
    'firstSteps.addFriend': 'Arkadaş ekle',
    'You are all caught up': 'Her şey güncel',
    'New friend requests, messages and activity will appear here.':
        'Yeni arkadaşlık istekleri, mesajlar ve etkinlikler burada görünecek.',
    'No friends yet': 'Henüz arkadaşın yok',
    'Find someone and start building your circle.':
        'Birini bul ve çevreni oluşturmaya başla.',
    'No friends to invite yet': 'Henüz davet edebileceğin arkadaşın yok',
    'Add friends first — a server invitation can only go to a friend.':
        'Önce arkadaş ekle: sunucu daveti yalnızca bir arkadaşa gönderilebilir.',
  },
  'el': <String, String>{
    'Start here': 'Ξεκίνα εδώ',
    '{done} of {total}': '{done} από {total}',
    'firstSteps.close': 'Κλείσιμο',
    'firstSteps.stepDone': 'Ολοκληρώθηκε',
    'Done. You know YO Voice now.': 'Έτοιμο. Τώρα γνωρίζεις το YO Voice.',
    'Add a profile photo': 'Πρόσθεσε φωτογραφία προφίλ',
    'Friends will recognise you faster':
        'Οι φίλοι θα σε αναγνωρίζουν πιο γρήγορα',
    'Add your first friend': 'Πρόσθεσε τον πρώτο σου φίλο',
    'Search by name or send your link':
        'Αναζήτησε με όνομα ή στείλε τον σύνδεσμό σου',
    'Join a server or create your own':
        'Μπες σε έναν διακομιστή ή φτιάξε τον δικό σου',
    'See public servers or start your own':
        'Δες τους δημόσιους διακομιστές ή φτιάξε τον δικό σου',
    'Record your first Voice': 'Ηχογράφησε την πρώτη σου Φωνή',
    'A short voice recording, up to 60 seconds':
        'Μια σύντομη ηχογράφηση φωνής, έως 60 δευτερόλεπτα',
    'Follow a Page or creator': 'Ακολούθησε μια σελίδα ή έναν δημιουργό',
    'You will see their news in Content':
        'Θα βλέπεις τα νέα τους στο Περιεχόμενο',
    'Share the server link': 'Κοινοποίησε τον σύνδεσμο του διακομιστή',
    "Couldn't share the link. Try again.":
        'Δεν ήταν δυνατή η κοινοποίηση του συνδέσμου. Δοκίμασε ξανά.',
    'Find Pages to follow': 'Βρες σελίδες για να ακολουθήσεις',
    'firstSteps.addFriend': 'Πρόσθεσε φίλο',
    'You are all caught up': 'Τα έχεις δει όλα',
    'New friend requests, messages and activity will appear here.':
        'Τα νέα αιτήματα φιλίας, τα μηνύματα και η δραστηριότητα θα εμφανίζονται εδώ.',
    'No friends yet': 'Δεν έχεις φίλους ακόμα',
    'Find someone and start building your circle.':
        'Βρες κάποιον και ξεκίνα να φτιάχνεις τον κύκλο σου.',
    'No friends to invite yet': 'Δεν έχεις ακόμα φίλους να προσκαλέσεις',
    'Add friends first — a server invitation can only go to a friend.':
        'Πρόσθεσε πρώτα φίλους — η πρόσκληση σε διακομιστή στέλνεται μόνο σε φίλο.',
  },
  'hu': <String, String>{
    'Start here': 'Kezdd itt',
    '{done} of {total}': '{done} / {total}',
    'firstSteps.close': 'Bezárás',
    'firstSteps.stepDone': 'Kész',
    'Done. You know YO Voice now.': 'Kész. Már ismered a YO Voice-t.',
    'Add a profile photo': 'Adj hozzá profilképet',
    'Friends will recognise you faster': 'Az ismerőseid gyorsabban felismernek',
    'Add your first friend': 'Add hozzá az első ismerősödet',
    'Search by name or send your link':
        'Keress név szerint, vagy küldd el a linkedet',
    'Join a server or create your own':
        'Csatlakozz egy szerverhez, vagy hozz létre sajátot',
    'See public servers or start your own':
        'Nézd meg a nyilvános szervereket, vagy indíts sajátot',
    'Record your first Voice': 'Vedd fel az első Hangodat',
    'A short voice recording, up to 60 seconds':
        'Rövid hangfelvétel, legfeljebb 60 másodperc',
    'Follow a Page or creator': 'Kövess egy oldalt vagy alkotót',
    'You will see their news in Content':
        'Az újdonságaikat a Tartalom fülön látod',
    'Share the server link': 'Szerverlink megosztása',
    "Couldn't share the link. Try again.":
        'Nem sikerült megosztani a linket. Próbáld újra.',
    'Find Pages to follow': 'Keress követhető oldalakat',
    'firstSteps.addFriend': 'Ismerős hozzáadása',
    'You are all caught up': 'Mindent megnéztél',
    'New friend requests, messages and activity will appear here.':
        'Az új barátkérések, üzenetek és tevékenységek itt jelennek meg.',
    'No friends yet': 'Még nincsenek ismerőseid',
    'Find someone and start building your circle.':
        'Keress valakit, és kezdd el építeni a saját körödet.',
    'No friends to invite yet': 'Még nincs kit meghívnod',
    'Add friends first — a server invitation can only go to a friend.':
        'Előbb adj hozzá ismerősöket – szervermeghívót csak ismerősnek lehet küldeni.',
  },
  'uk': <String, String>{
    'Start here': 'Почни тут',
    '{done} of {total}': '{done} із {total}',
    'firstSteps.close': 'Закрити',
    'firstSteps.stepDone': 'Виконано',
    'Done. You know YO Voice now.': 'Готово. Тепер ти знаєш YO Voice.',
    'Add a profile photo': 'Додати фото профілю',
    'Friends will recognise you faster': 'Друзі швидше тебе впізнають',
    'Add your first friend': 'Додати першого друга',
    'Search by name or send your link':
        'Шукай за іменем або надішли своє посилання',
    'Join a server or create your own':
        'Приєднатися до сервера або створити власний',
    'See public servers or start your own':
        'Переглянь публічні сервери або створи власний',
    'Record your first Voice': 'Записати перший Голос',
    'A short voice recording, up to 60 seconds':
        'Короткий голосовий запис, до 60 секунд',
    'Follow a Page or creator': 'Стежити за сторінкою або автором',
    'You will see their news in Content':
        'Їхні новини побачиш у розділі «Контент»',
    'Share the server link': 'Поділитися посиланням на сервер',
    "Couldn't share the link. Try again.":
        'Не вдалося поділитися посиланням. Спробуй ще раз.',
    'Find Pages to follow': 'Знайти сторінки, за якими стежити',
    'firstSteps.addFriend': 'Додати друга',
    'You are all caught up': 'Усе переглянуто',
    'New friend requests, messages and activity will appear here.':
        'Нові запити на дружбу, повідомлення й активність з’являтимуться тут.',
    'No friends yet': 'У тебе ще немає друзів',
    'Find someone and start building your circle.':
        'Знайди когось і почни збирати своє коло.',
    'No friends to invite yet': 'Поки що немає кого запросити',
    'Add friends first — a server invitation can only go to a friend.':
        'Спершу додай друзів — запрошення на сервер можна надіслати лише другові.',
  },
  'ru': <String, String>{
    'Start here': 'Начните здесь',
    '{done} of {total}': '{done} из {total}',
    'firstSteps.close': 'Закрыть',
    'firstSteps.stepDone': 'Выполнено',
    'Done. You know YO Voice now.': 'Готово. Теперь вы знаете YO Voice.',
    'Add a profile photo': 'Добавить фото профиля',
    'Friends will recognise you faster': 'Друзья быстрее вас узнают',
    'Add your first friend': 'Добавить первого друга',
    'Search by name or send your link':
        'Найдите по имени или отправьте свою ссылку',
    'Join a server or create your own': 'Вступить на сервер или создать свой',
    'See public servers or start your own':
        'Посмотрите публичные серверы или создайте свой',
    'Record your first Voice': 'Записать первый Голос',
    'A short voice recording, up to 60 seconds':
        'Короткая голосовая запись, до 60 секунд',
    'Follow a Page or creator': 'Подписаться на страницу или автора',
    'You will see their news in Content':
        'Их новости появятся в разделе «Контент»',
    'Share the server link': 'Поделиться ссылкой на сервер',
    "Couldn't share the link. Try again.":
        'Не удалось поделиться ссылкой. Повторите попытку.',
    'Find Pages to follow': 'Найти страницы для подписки',
    'firstSteps.addFriend': 'Добавить друга',
    'You are all caught up': 'Всё просмотрено',
    'New friend requests, messages and activity will appear here.':
        'Новые запросы на дружбу, сообщения и активность появятся здесь.',
    'No friends yet': 'У вас пока нет друзей',
    'Find someone and start building your circle.':
        'Найдите кого-нибудь и начните собирать свой круг.',
    'No friends to invite yet': 'Пока некого пригласить',
    'Add friends first — a server invitation can only go to a friend.':
        'Сначала добавьте друзей — приглашение на сервер можно отправить только другу.',
  },
  'cs': <String, String>{
    'Start here': 'Začněte tady',
    '{done} of {total}': '{done} z {total}',
    'firstSteps.close': 'Zavřít',
    'firstSteps.stepDone': 'Hotovo',
    'Done. You know YO Voice now.': 'Hotovo. Teď už YO Voice znáte.',
    'Add a profile photo': 'Přidat profilovou fotku',
    'Friends will recognise you faster': 'Přátelé vás rychleji poznají',
    'Add your first friend': 'Přidat prvního přítele',
    'Search by name or send your link':
        'Hledejte podle jména nebo pošlete svůj odkaz',
    'Join a server or create your own':
        'Připojit se k serveru nebo vytvořit vlastní',
    'See public servers or start your own':
        'Podívejte se na veřejné servery nebo založte vlastní',
    'Record your first Voice': 'Nahrát první Hlas',
    'A short voice recording, up to 60 seconds':
        'Krátká hlasová nahrávka, až 60 sekund',
    'Follow a Page or creator': 'Sledovat stránku nebo tvůrce',
    'You will see their news in Content': 'Jejich novinky uvidíte v Obsahu',
    'Share the server link': 'Sdílet odkaz na server',
    "Couldn't share the link. Try again.":
        'Odkaz se nepodařilo sdílet. Zkuste to znovu.',
    'Find Pages to follow': 'Najít stránky ke sledování',
    'firstSteps.addFriend': 'Přidat přítele',
    'You are all caught up': 'Vše je zkontrolováno',
    'New friend requests, messages and activity will appear here.':
        'Nové žádosti o přátelství, zprávy a aktivita se zobrazí zde.',
    'No friends yet': 'Zatím nemáte žádné přátele',
    'Find someone and start building your circle.':
        'Najděte někoho a začněte si budovat svůj okruh.',
    'No friends to invite yet': 'Zatím nemáte koho pozvat',
    'Add friends first — a server invitation can only go to a friend.':
        'Nejdřív přidejte přátele – pozvánku na server lze poslat jen příteli.',
  },
  'sk': <String, String>{
    'Start here': 'Začnite tu',
    '{done} of {total}': '{done} z {total}',
    'firstSteps.close': 'Zavrieť',
    'firstSteps.stepDone': 'Hotovo',
    'Done. You know YO Voice now.': 'Hotovo. Teraz už YO Voice poznáte.',
    'Add a profile photo': 'Pridať profilovú fotku',
    'Friends will recognise you faster': 'Priatelia vás rýchlejšie spoznajú',
    'Add your first friend': 'Pridať prvého priateľa',
    'Search by name or send your link':
        'Hľadajte podľa mena alebo pošlite svoj odkaz',
    'Join a server or create your own':
        'Pripojiť sa k serveru alebo vytvoriť vlastný',
    'See public servers or start your own':
        'Pozrite si verejné servery alebo založte vlastný',
    'Record your first Voice': 'Nahrať prvý Hlas',
    'A short voice recording, up to 60 seconds':
        'Krátka hlasová nahrávka, až 60 sekúnd',
    'Follow a Page or creator': 'Sledovať stránku alebo tvorcu',
    'You will see their news in Content': 'Ich novinky uvidíte v Obsahu',
    'Share the server link': 'Zdieľať odkaz na server',
    "Couldn't share the link. Try again.":
        'Odkaz sa nepodarilo zdieľať. Skúste to znova.',
    'Find Pages to follow': 'Nájsť stránky na sledovanie',
    'firstSteps.addFriend': 'Pridať priateľa',
    'You are all caught up': 'Všetko je skontrolované',
    'New friend requests, messages and activity will appear here.':
        'Nové žiadosti o priateľstvo, správy a aktivita sa zobrazia tu.',
    'No friends yet': 'Zatiaľ nemáte žiadnych priateľov',
    'Find someone and start building your circle.':
        'Nájdite niekoho a začnite si budovať svoj okruh.',
    'No friends to invite yet': 'Zatiaľ nemáte koho pozvať',
    'Add friends first — a server invitation can only go to a friend.':
        'Najprv pridajte priateľov – pozvánku na server možno poslať len priateľovi.',
  },
  'bg': <String, String>{
    'Start here': 'Започни оттук',
    '{done} of {total}': '{done} от {total}',
    'firstSteps.close': 'Затвори',
    'firstSteps.stepDone': 'Готово',
    'Done. You know YO Voice now.': 'Готово. Вече познаваш YO Voice.',
    'Add a profile photo': 'Добави профилна снимка',
    'Friends will recognise you faster':
        'Приятелите ще те разпознават по-бързо',
    'Add your first friend': 'Добави първия си приятел',
    'Search by name or send your link': 'Търси по име или изпрати своя линк',
    'Join a server or create your own':
        'Присъедини се към сървър или създай свой',
    'See public servers or start your own':
        'Виж публичните сървъри или създай свой',
    'Record your first Voice': 'Запиши първия си Глас',
    'A short voice recording, up to 60 seconds':
        'Кратък гласов запис, до 60 секунди',
    'Follow a Page or creator': 'Последвай страница или творец',
    'You will see their news in Content': 'Новостите им ще виждаш в Съдържание',
    'Share the server link': 'Сподели линка към сървъра',
    "Couldn't share the link. Try again.":
        'Линкът не можа да бъде споделен. Опитай отново.',
    'Find Pages to follow': 'Намери страници за следване',
    'firstSteps.addFriend': 'Добави приятел',
    'You are all caught up': 'Всичко е прегледано',
    'New friend requests, messages and activity will appear here.':
        'Новите покани за приятелство, съобщения и активност ще се показват тук.',
    'No friends yet': 'Все още нямаш приятели',
    'Find someone and start building your circle.':
        'Намери някого и започни да изграждаш своя кръг.',
    'No friends to invite yet': 'Все още няма кого да поканиш',
    'Add friends first — a server invitation can only go to a friend.':
        'Първо добави приятели — покана за сървър може да се изпрати само на приятел.',
  },
  'hr': <String, String>{
    'Start here': 'Počni ovdje',
    '{done} of {total}': '{done} od {total}',
    'firstSteps.close': 'Zatvori',
    'firstSteps.stepDone': 'Gotovo',
    'Done. You know YO Voice now.': 'Gotovo. Sada poznaješ YO Voice.',
    'Add a profile photo': 'Dodaj profilnu fotografiju',
    'Friends will recognise you faster': 'Prijatelji će te brže prepoznati',
    'Add your first friend': 'Dodaj prvog prijatelja',
    'Search by name or send your link':
        'Traži po imenu ili pošalji svoju poveznicu',
    'Join a server or create your own':
        'Pridruži se poslužitelju ili stvori vlastiti',
    'See public servers or start your own':
        'Pogledaj javne poslužitelje ili pokreni vlastiti',
    'Record your first Voice': 'Snimi svoj prvi Glas',
    'A short voice recording, up to 60 seconds':
        'Kratka glasovna snimka, do 60 sekundi',
    'Follow a Page or creator': 'Prati stranicu ili autora',
    'You will see their news in Content':
        'Njihove novosti vidjet ćeš u Sadržaju',
    'Share the server link': 'Podijeli poveznicu poslužitelja',
    "Couldn't share the link. Try again.":
        'Poveznicu nije moguće podijeliti. Pokušaj ponovno.',
    'Find Pages to follow': 'Pronađi stranice za praćenje',
    'firstSteps.addFriend': 'Dodaj prijatelja',
    'You are all caught up': 'Sve je pregledano',
    'New friend requests, messages and activity will appear here.':
        'Novi zahtjevi za prijateljstvo, poruke i aktivnosti prikazat će se ovdje.',
    'No friends yet': 'Još nemaš prijatelja',
    'Find someone and start building your circle.':
        'Pronađi nekoga i počni graditi svoj krug.',
    'No friends to invite yet': 'Još nemaš koga pozvati',
    'Add friends first — a server invitation can only go to a friend.':
        'Najprije dodaj prijatelje — pozivnica za poslužitelj može se poslati samo prijatelju.',
  },
  'sr': <String, String>{
    'Start here': 'Почни овде',
    '{done} of {total}': '{done} од {total}',
    'firstSteps.close': 'Затвори',
    'firstSteps.stepDone': 'Готово',
    'Done. You know YO Voice now.': 'Готово. Сада познајеш YO Voice.',
    'Add a profile photo': 'Додај профилну фотографију',
    'Friends will recognise you faster': 'Пријатељи ће те брже препознати',
    'Add your first friend': 'Додај првог пријатеља',
    'Search by name or send your link': 'Тражи по имену или пошаљи свој линк',
    'Join a server or create your own': 'Придружи се серверу или направи свој',
    'See public servers or start your own':
        'Погледај јавне сервере или покрени свој',
    'Record your first Voice': 'Сними свој први Глас',
    'A short voice recording, up to 60 seconds':
        'Кратак гласовни снимак, до 60 секунди',
    'Follow a Page or creator': 'Прати страницу или аутора',
    'You will see their news in Content': 'Њихове новости видећеш у Садржају',
    'Share the server link': 'Подели линк сервера',
    "Couldn't share the link. Try again.":
        'Линк није могуће поделити. Покушај поново.',
    'Find Pages to follow': 'Пронађи странице за праћење',
    'firstSteps.addFriend': 'Додај пријатеља',
    'You are all caught up': 'Све је прегледано',
    'New friend requests, messages and activity will appear here.':
        'Нови захтеви за пријатељство, поруке и активности појавиће се овде.',
    'No friends yet': 'Још немаш пријатеља',
    'Find someone and start building your circle.':
        'Пронађи некога и почни да градиш свој круг.',
    'No friends to invite yet': 'Још немаш кога да позовеш',
    'Add friends first — a server invitation can only go to a friend.':
        'Прво додај пријатеље — позивница за сервер може да се пошаље само пријатељу.',
  },
  'sv': <String, String>{
    'Start here': 'Börja här',
    '{done} of {total}': '{done} av {total}',
    'firstSteps.close': 'Stäng',
    'firstSteps.stepDone': 'Klart',
    'Done. You know YO Voice now.': 'Klart. Nu känner du YO Voice.',
    'Add a profile photo': 'Lägg till en profilbild',
    'Friends will recognise you faster': 'Dina vänner känner igen dig snabbare',
    'Add your first friend': 'Lägg till din första vän',
    'Search by name or send your link': 'Sök på namn eller skicka din länk',
    'Join a server or create your own':
        'Gå med i en server eller skapa en egen',
    'See public servers or start your own':
        'Se offentliga servrar eller starta en egen',
    'Record your first Voice': 'Spela in din första Röst',
    'A short voice recording, up to 60 seconds':
        'En kort röstinspelning, upp till 60 sekunder',
    'Follow a Page or creator': 'Följ en sida eller kreatör',
    'You will see their news in Content': 'Deras nyheter ser du i Innehåll',
    'Share the server link': 'Dela serverlänken',
    "Couldn't share the link. Try again.":
        'Det gick inte att dela länken. Försök igen.',
    'Find Pages to follow': 'Hitta sidor att följa',
    'firstSteps.addFriend': 'Lägg till vän',
    'You are all caught up': 'Du är ikapp med allt',
    'New friend requests, messages and activity will appear here.':
        'Nya vänförfrågningar, meddelanden och aktivitet visas här.',
    'No friends yet': 'Inga vänner än',
    'Find someone and start building your circle.':
        'Hitta någon och börja bygga din krets.',
    'No friends to invite yet': 'Inga vänner att bjuda in än',
    'Add friends first — a server invitation can only go to a friend.':
        'Lägg till vänner först – en serverinbjudan kan bara skickas till en vän.',
  },
  'da': <String, String>{
    'Start here': 'Start her',
    '{done} of {total}': '{done} af {total}',
    'firstSteps.close': 'Luk',
    'firstSteps.stepDone': 'Udført',
    'Done. You know YO Voice now.': 'Færdig. Nu kender du YO Voice.',
    'Add a profile photo': 'Tilføj et profilbillede',
    'Friends will recognise you faster': 'Dine venner genkender dig hurtigere',
    'Add your first friend': 'Tilføj din første ven',
    'Search by name or send your link': 'Søg på navn, eller send dit link',
    'Join a server or create your own':
        'Bliv medlem af en server, eller opret din egen',
    'See public servers or start your own':
        'Se offentlige servere, eller start din egen',
    'Record your first Voice': 'Optag din første Stemme',
    'A short voice recording, up to 60 seconds':
        'En kort stemmeoptagelse, op til 60 sekunder',
    'Follow a Page or creator': 'Følg en side eller indholdsskaber',
    'You will see their news in Content': 'Deres nyheder ser du i Indhold',
    'Share the server link': 'Del serverlinket',
    "Couldn't share the link. Try again.":
        'Linket kunne ikke deles. Prøv igen.',
    'Find Pages to follow': 'Find sider at følge',
    'firstSteps.addFriend': 'Tilføj ven',
    'You are all caught up': 'Du er helt ajour',
    'New friend requests, messages and activity will appear here.':
        'Nye venneanmodninger, beskeder og aktivitet vises her.',
    'No friends yet': 'Ingen venner endnu',
    'Find someone and start building your circle.':
        'Find nogen, og begynd at opbygge din kreds.',
    'No friends to invite yet': 'Ingen venner at invitere endnu',
    'Add friends first — a server invitation can only go to a friend.':
        'Tilføj venner først – en serverinvitation kan kun sendes til en ven.',
  },
  'nb': <String, String>{
    'Start here': 'Start her',
    '{done} of {total}': '{done} av {total}',
    'firstSteps.close': 'Lukk',
    'firstSteps.stepDone': 'Fullført',
    'Done. You know YO Voice now.': 'Ferdig. Nå kjenner du YO Voice.',
    'Add a profile photo': 'Legg til et profilbilde',
    'Friends will recognise you faster':
        'Vennene dine kjenner deg igjen raskere',
    'Add your first friend': 'Legg til din første venn',
    'Search by name or send your link': 'Søk på navn eller send lenken din',
    'Join a server or create your own':
        'Bli med i en server eller opprett din egen',
    'See public servers or start your own':
        'Se offentlige servere eller start din egen',
    'Record your first Voice': 'Spill inn din første Stemme',
    'A short voice recording, up to 60 seconds':
        'Et kort stemmeopptak, opptil 60 sekunder',
    'Follow a Page or creator': 'Følg en side eller skaper',
    'You will see their news in Content': 'Nyhetene deres ser du i Innhold',
    'Share the server link': 'Del serverlenken',
    "Couldn't share the link. Try again.":
        'Kunne ikke dele lenken. Prøv igjen.',
    'Find Pages to follow': 'Finn sider å følge',
    'firstSteps.addFriend': 'Legg til venn',
    'You are all caught up': 'Du er oppdatert på alt',
    'New friend requests, messages and activity will appear here.':
        'Nye venneforespørsler, meldinger og aktivitet vises her.',
    'No friends yet': 'Ingen venner ennå',
    'Find someone and start building your circle.':
        'Finn noen og begynn å bygge kretsen din.',
    'No friends to invite yet': 'Ingen venner å invitere ennå',
    'Add friends first — a server invitation can only go to a friend.':
        'Legg til venner først – en serverinvitasjon kan bare sendes til en venn.',
  },
  'fi': <String, String>{
    'Start here': 'Aloita tästä',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': 'Sulje',
    'firstSteps.stepDone': 'Valmis',
    'Done. You know YO Voice now.': 'Valmista. Nyt tunnet YO Voicen.',
    'Add a profile photo': 'Lisää profiilikuva',
    'Friends will recognise you faster': 'Ystävät tunnistavat sinut nopeammin',
    'Add your first friend': 'Lisää ensimmäinen ystäväsi',
    'Search by name or send your link': 'Hae nimellä tai lähetä linkkisi',
    'Join a server or create your own': 'Liity palvelimelle tai luo oma',
    'See public servers or start your own':
        'Katso julkiset palvelimet tai perusta oma',
    'Record your first Voice': 'Äänitä ensimmäinen Äänesi',
    'A short voice recording, up to 60 seconds':
        'Lyhyt äänitallenne, enintään 60 sekuntia',
    'Follow a Page or creator': 'Seuraa sivua tai sisällöntuottajaa',
    'You will see their news in Content':
        'Näet heidän uutisensa Sisältö-välilehdellä',
    'Share the server link': 'Jaa palvelimen linkki',
    "Couldn't share the link. Try again.":
        'Linkin jakaminen epäonnistui. Yritä uudelleen.',
    'Find Pages to follow': 'Etsi seurattavia sivuja',
    'firstSteps.addFriend': 'Lisää ystävä',
    'You are all caught up': 'Olet ajan tasalla',
    'New friend requests, messages and activity will appear here.':
        'Uudet ystäväpyynnöt, viestit ja tapahtumat näkyvät täällä.',
    'No friends yet': 'Ei vielä ystäviä',
    'Find someone and start building your circle.':
        'Etsi joku ja ala rakentaa omaa piiriäsi.',
    'No friends to invite yet': 'Ei vielä ystäviä kutsuttavaksi',
    'Add friends first — a server invitation can only go to a friend.':
        'Lisää ensin ystäviä – palvelinkutsun voi lähettää vain ystävälle.',
  },
  'lt': <String, String>{
    'Start here': 'Pradėk čia',
    '{done} of {total}': '{done} iš {total}',
    'firstSteps.close': 'Uždaryti',
    'firstSteps.stepDone': 'Atlikta',
    'Done. You know YO Voice now.': 'Atlikta. Dabar jau pažįsti YO Voice.',
    'Add a profile photo': 'Pridėti profilio nuotrauką',
    'Friends will recognise you faster': 'Draugai tave greičiau atpažins',
    'Add your first friend': 'Pridėti pirmą draugą',
    'Search by name or send your link':
        'Ieškok pagal vardą arba nusiųsk savo nuorodą',
    'Join a server or create your own':
        'Prisijungti prie serverio arba sukurti savo',
    'See public servers or start your own':
        'Peržiūrėk viešus serverius arba sukurk savo',
    'Record your first Voice': 'Įrašyti pirmą Balsą',
    'A short voice recording, up to 60 seconds':
        'Trumpas balso įrašas, iki 60 sekundžių',
    'Follow a Page or creator': 'Sekti puslapį arba kūrėją',
    'You will see their news in Content':
        'Jų naujienas matysi skiltyje „Turinys“',
    'Share the server link': 'Bendrinti serverio nuorodą',
    "Couldn't share the link. Try again.":
        'Nepavyko bendrinti nuorodos. Bandyk dar kartą.',
    'Find Pages to follow': 'Rasti puslapių, kuriuos verta sekti',
    'firstSteps.addFriend': 'Pridėti draugą',
    'You are all caught up': 'Viskas peržiūrėta',
    'New friend requests, messages and activity will appear here.':
        'Naujos draugų užklausos, žinutės ir veikla bus rodomos čia.',
    'No friends yet': 'Dar neturi draugų',
    'Find someone and start building your circle.':
        'Surask ką nors ir pradėk kurti savo ratą.',
    'No friends to invite yet': 'Dar neturi ko pakviesti',
    'Add friends first — a server invitation can only go to a friend.':
        'Pirmiausia pridėk draugų – kvietimą į serverį galima siųsti tik draugui.',
  },
  'lv': <String, String>{
    'Start here': 'Sāc šeit',
    '{done} of {total}': '{done} no {total}',
    'firstSteps.close': 'Aizvērt',
    'firstSteps.stepDone': 'Paveikts',
    'Done. You know YO Voice now.': 'Gatavs. Tagad tu pazīsti YO Voice.',
    'Add a profile photo': 'Pievienot profila fotoattēlu',
    'Friends will recognise you faster': 'Draugi tevi atpazīs ātrāk',
    'Add your first friend': 'Pievienot pirmo draugu',
    'Search by name or send your link': 'Meklē pēc vārda vai nosūti savu saiti',
    'Join a server or create your own':
        'Pievienoties serverim vai izveidot savu',
    'See public servers or start your own':
        'Apskati publiskos serverus vai izveido savu',
    'Record your first Voice': 'Ierakstīt pirmo Balsi',
    'A short voice recording, up to 60 seconds':
        'Īss balss ieraksts, līdz 60 sekundēm',
    'Follow a Page or creator': 'Sekot lapai vai autoram',
    'You will see their news in Content':
        'Viņu jaunumus redzēsi sadaļā “Saturs”',
    'Share the server link': 'Kopīgot servera saiti',
    "Couldn't share the link. Try again.":
        'Neizdevās kopīgot saiti. Mēģini vēlreiz.',
    'Find Pages to follow': 'Atrast lapas, kurām sekot',
    'firstSteps.addFriend': 'Pievienot draugu',
    'You are all caught up': 'Viss ir apskatīts',
    'New friend requests, messages and activity will appear here.':
        'Jauni draugu pieprasījumi, ziņas un aktivitātes parādīsies šeit.',
    'No friends yet': 'Tev vēl nav draugu',
    'Find someone and start building your circle.':
        'Atrodi kādu un sāc veidot savu loku.',
    'No friends to invite yet': 'Vēl nav neviena, ko uzaicināt',
    'Add friends first — a server invitation can only go to a friend.':
        'Vispirms pievieno draugus — servera ielūgumu var nosūtīt tikai draugam.',
  },
  'et': <String, String>{
    'Start here': 'Alusta siit',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': 'Sulge',
    'firstSteps.stepDone': 'Tehtud',
    'Done. You know YO Voice now.': 'Valmis. Nüüd tunned YO Voice’i.',
    'Add a profile photo': 'Lisa profiilifoto',
    'Friends will recognise you faster': 'Sõbrad tunnevad su kiiremini ära',
    'Add your first friend': 'Lisa oma esimene sõber',
    'Search by name or send your link': 'Otsi nime järgi või saada oma link',
    'Join a server or create your own': 'Liitu serveriga või loo oma',
    'See public servers or start your own':
        'Vaata avalikke servereid või loo oma',
    'Record your first Voice': 'Salvesta oma esimene Hääl',
    'A short voice recording, up to 60 seconds':
        'Lühike häälsalvestis, kuni 60 sekundit',
    'Follow a Page or creator': 'Jälgi lehte või sisuloojat',
    'You will see their news in Content': 'Nende uudiseid näed jaotises Sisu',
    'Share the server link': 'Jaga serveri linki',
    "Couldn't share the link. Try again.":
        'Linki ei saanud jagada. Proovi uuesti.',
    'Find Pages to follow': 'Leia lehti, mida jälgida',
    'firstSteps.addFriend': 'Lisa sõber',
    'You are all caught up': 'Kõik on üle vaadatud',
    'New friend requests, messages and activity will appear here.':
        'Uued sõbrakutsed, sõnumid ja tegevused ilmuvad siia.',
    'No friends yet': 'Sõpru veel pole',
    'Find someone and start building your circle.':
        'Leia keegi ja hakka oma ringi looma.',
    'No friends to invite yet': 'Pole veel sõpru, keda kutsuda',
    'Add friends first — a server invitation can only go to a friend.':
        'Lisa esmalt sõpru – serverikutse saab saata ainult sõbrale.',
  },
  'id': <String, String>{
    'Start here': 'Mulai di sini',
    '{done} of {total}': '{done} dari {total}',
    'firstSteps.close': 'Tutup',
    'firstSteps.stepDone': 'Selesai',
    'Done. You know YO Voice now.':
        'Selesai. Sekarang kamu sudah mengenal YO Voice.',
    'Add a profile photo': 'Tambahkan foto profil',
    'Friends will recognise you faster': 'Teman akan lebih cepat mengenalimu',
    'Add your first friend': 'Tambahkan teman pertamamu',
    'Search by name or send your link':
        'Cari berdasarkan nama atau kirim tautanmu',
    'Join a server or create your own':
        'Gabung ke server atau buat servermu sendiri',
    'See public servers or start your own':
        'Lihat server publik atau buat servermu sendiri',
    'Record your first Voice': 'Rekam Suara pertamamu',
    'A short voice recording, up to 60 seconds':
        'Rekaman suara singkat, hingga 60 detik',
    'Follow a Page or creator': 'Ikuti halaman atau kreator',
    'You will see their news in Content':
        'Kabar terbaru mereka akan muncul di Konten',
    'Share the server link': 'Bagikan tautan server',
    "Couldn't share the link. Try again.":
        'Tidak dapat membagikan tautan. Coba lagi.',
    'Find Pages to follow': 'Temukan halaman untuk diikuti',
    'firstSteps.addFriend': 'Tambah teman',
    'You are all caught up': 'Semua sudah kamu lihat',
    'New friend requests, messages and activity will appear here.':
        'Permintaan pertemanan, pesan, dan aktivitas baru akan muncul di sini.',
    'No friends yet': 'Belum ada teman',
    'Find someone and start building your circle.':
        'Cari seseorang dan mulai bangun lingkaranmu.',
    'No friends to invite yet': 'Belum ada teman untuk diundang',
    'Add friends first — a server invitation can only go to a friend.':
        'Tambahkan teman dulu — undangan server hanya bisa dikirim ke teman.',
  },
  'vi': <String, String>{
    'Start here': 'Bắt đầu tại đây',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': 'Đóng',
    'firstSteps.stepDone': 'Đã xong',
    'Done. You know YO Voice now.': 'Xong rồi. Giờ bạn đã biết YO Voice.',
    'Add a profile photo': 'Thêm ảnh hồ sơ',
    'Friends will recognise you faster': 'Bạn bè sẽ nhận ra bạn nhanh hơn',
    'Add your first friend': 'Thêm người bạn đầu tiên',
    'Search by name or send your link':
        'Tìm theo tên hoặc gửi liên kết của bạn',
    'Join a server or create your own':
        'Tham gia một máy chủ hoặc tạo máy chủ riêng',
    'See public servers or start your own':
        'Xem các máy chủ công khai hoặc tự tạo máy chủ',
    'Record your first Voice': 'Ghi Giọng nói đầu tiên',
    'A short voice recording, up to 60 seconds':
        'Một bản ghi âm ngắn, tối đa 60 giây',
    'Follow a Page or creator': 'Theo dõi một trang hoặc nhà sáng tạo',
    'You will see their news in Content':
        'Bạn sẽ thấy tin mới của họ trong Nội dung',
    'Share the server link': 'Chia sẻ liên kết máy chủ',
    "Couldn't share the link. Try again.":
        'Không thể chia sẻ liên kết. Hãy thử lại.',
    'Find Pages to follow': 'Tìm trang để theo dõi',
    'firstSteps.addFriend': 'Thêm bạn',
    'You are all caught up': 'Bạn đã xem hết mọi thứ',
    'New friend requests, messages and activity will appear here.':
        'Lời mời kết bạn, tin nhắn và hoạt động mới sẽ xuất hiện ở đây.',
    'No friends yet': 'Chưa có bạn bè',
    'Find someone and start building your circle.':
        'Hãy tìm ai đó và bắt đầu xây dựng vòng kết nối của bạn.',
    'No friends to invite yet': 'Chưa có bạn bè để mời',
    'Add friends first — a server invitation can only go to a friend.':
        'Hãy thêm bạn bè trước — lời mời vào máy chủ chỉ có thể gửi cho bạn bè.',
  },
  'zh_CN': <String, String>{
    'Start here': '从这里开始',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': '关闭',
    'firstSteps.stepDone': '已完成',
    'Done. You know YO Voice now.': '完成了。你已经了解 YO Voice。',
    'Add a profile photo': '添加头像',
    'Friends will recognise you faster': '好友能更快认出你',
    'Add your first friend': '添加第一位好友',
    'Search by name or send your link': '按名称搜索，或发送你的链接',
    'Join a server or create your own': '加入服务器，或创建自己的服务器',
    'See public servers or start your own': '看看公开服务器，或创建自己的服务器',
    'Record your first Voice': '录制第一条语音',
    'A short voice recording, up to 60 seconds': '一段简短的语音，最长 60 秒',
    'Follow a Page or creator': '关注一个主页或创作者',
    'You will see their news in Content': '他们的新动态会显示在“内容”中',
    'Share the server link': '分享服务器链接',
    "Couldn't share the link. Try again.": '无法分享链接。请重试。',
    'Find Pages to follow': '查找可关注的主页',
    'firstSteps.addFriend': '添加好友',
    'You are all caught up': '你已全部看完',
    'New friend requests, messages and activity will appear here.':
        '新的好友请求、消息和动态会显示在这里。',
    'No friends yet': '还没有好友',
    'Find someone and start building your circle.': '找到朋友，开始建立你的圈子。',
    'No friends to invite yet': '还没有可以邀请的好友',
    'Add friends first — a server invitation can only go to a friend.':
        '请先添加好友——服务器邀请只能发送给好友。',
  },
  'zh_TW': <String, String>{
    'Start here': '從這裡開始',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': '關閉',
    'firstSteps.stepDone': '已完成',
    'Done. You know YO Voice now.': '完成了。你已經認識 YO Voice。',
    'Add a profile photo': '新增大頭貼照',
    'Friends will recognise you faster': '好友能更快認出你',
    'Add your first friend': '新增第一位好友',
    'Search by name or send your link': '依名稱搜尋，或傳送你的連結',
    'Join a server or create your own': '加入伺服器，或建立自己的伺服器',
    'See public servers or start your own': '看看公開伺服器，或建立自己的伺服器',
    'Record your first Voice': '錄製第一則語音',
    'A short voice recording, up to 60 seconds': '一段簡短的語音，最長 60 秒',
    'Follow a Page or creator': '追蹤一個專頁或創作者',
    'You will see their news in Content': '他們的最新動態會顯示在「內容」中',
    'Share the server link': '分享伺服器連結',
    "Couldn't share the link. Try again.": '無法分享連結。請再試一次。',
    'Find Pages to follow': '尋找可追蹤的專頁',
    'firstSteps.addFriend': '新增好友',
    'You are all caught up': '你已全部看完',
    'New friend requests, messages and activity will appear here.':
        '新的好友邀請、訊息和動態會顯示在這裡。',
    'No friends yet': '還沒有好友',
    'Find someone and start building your circle.': '找到朋友，開始建立你的圈子。',
    'No friends to invite yet': '還沒有可以邀請的好友',
    'Add friends first — a server invitation can only go to a friend.':
        '請先新增好友——伺服器邀請只能傳送給好友。',
  },
  'ja': <String, String>{
    'Start here': 'ここから始めよう',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': '閉じる',
    'firstSteps.stepDone': '完了',
    'Done. You know YO Voice now.': '完了です。YO Voice の使い方はもう大丈夫。',
    'Add a profile photo': 'プロフィール写真を追加',
    'Friends will recognise you faster': '友達に見つけてもらいやすくなります',
    'Add your first friend': '最初の友達を追加',
    'Search by name or send your link': '名前で検索するか、自分のリンクを送信',
    'Join a server or create your own': 'サーバーに参加するか、自分で作成',
    'See public servers or start your own': '公開サーバーを見るか、自分のサーバーを作成',
    'Record your first Voice': '最初の音声を録音',
    'A short voice recording, up to 60 seconds': '最長60秒の短い音声録音',
    'Follow a Page or creator': 'ページやクリエイターをフォロー',
    'You will see their news in Content': '最新情報は「コンテンツ」に表示されます',
    'Share the server link': 'サーバーのリンクを共有',
    "Couldn't share the link. Try again.": 'リンクを共有できませんでした。もう一度お試しください。',
    'Find Pages to follow': 'フォローするページを探す',
    'firstSteps.addFriend': '友達を追加',
    'You are all caught up': 'すべて確認済みです',
    'New friend requests, messages and activity will appear here.':
        '新しい友達リクエスト、メッセージ、アクティビティがここに表示されます。',
    'No friends yet': 'まだ友達がいません',
    'Find someone and start building your circle.': '誰かを見つけて、つながりの輪を広げましょう。',
    'No friends to invite yet': '招待できる友達がまだいません',
    'Add friends first — a server invitation can only go to a friend.':
        'まず友達を追加してください。サーバーへの招待は友達にのみ送れます。',
  },
  'ko': <String, String>{
    'Start here': '여기서 시작하세요',
    '{done} of {total}': '{done}/{total}',
    'firstSteps.close': '닫기',
    'firstSteps.stepDone': '완료',
    'Done. You know YO Voice now.': '완료했어요. 이제 YO Voice를 알게 되었어요.',
    'Add a profile photo': '프로필 사진 추가',
    'Friends will recognise you faster': '친구들이 더 빨리 알아볼 수 있어요',
    'Add your first friend': '첫 친구 추가',
    'Search by name or send your link': '이름으로 검색하거나 내 링크를 보내세요',
    'Join a server or create your own': '서버에 참여하거나 직접 만들기',
    'See public servers or start your own': '공개 서버를 둘러보거나 직접 만들어 보세요',
    'Record your first Voice': '첫 음성 녹음',
    'A short voice recording, up to 60 seconds': '최대 60초의 짧은 음성 녹음',
    'Follow a Page or creator': '페이지 또는 크리에이터 팔로우',
    'You will see their news in Content': '새 소식은 콘텐츠에서 볼 수 있어요',
    'Share the server link': '서버 링크 공유',
    "Couldn't share the link. Try again.": '링크를 공유할 수 없습니다. 다시 시도하세요.',
    'Find Pages to follow': '팔로우할 페이지 찾기',
    'firstSteps.addFriend': '친구 추가',
    'You are all caught up': '모두 확인했어요',
    'New friend requests, messages and activity will appear here.':
        '새 친구 요청, 메시지, 활동이 여기에 표시돼요.',
    'No friends yet': '아직 친구가 없어요',
    'Find someone and start building your circle.': '누군가를 찾아 나만의 모임을 만들어 보세요.',
    'No friends to invite yet': '아직 초대할 친구가 없어요',
    'Add friends first — a server invitation can only go to a friend.':
        '먼저 친구를 추가하세요. 서버 초대는 친구에게만 보낼 수 있어요.',
  },
  'ar': <String, String>{
    'Start here': 'ابدأ من هنا',
    '{done} of {total}': '{done} من {total}',
    'firstSteps.close': 'إغلاق',
    'firstSteps.stepDone': 'تم',
    'Done. You know YO Voice now.': 'تم. أنت الآن تعرف YO Voice.',
    'Add a profile photo': 'إضافة صورة للملف الشخصي',
    'Friends will recognise you faster': 'سيتعرّف عليك أصدقاؤك بسرعة أكبر',
    'Add your first friend': 'إضافة أول صديق',
    'Search by name or send your link': 'ابحث بالاسم أو أرسل رابطك',
    'Join a server or create your own': 'الانضمام إلى خادم أو إنشاء خادمك',
    'See public servers or start your own':
        'تصفّح الخوادم العامة أو أنشئ خادمك',
    'Record your first Voice': 'تسجيل أول صوت',
    'A short voice recording, up to 60 seconds':
        'تسجيل صوتي قصير، حتى 60 ثانية',
    'Follow a Page or creator': 'متابعة صفحة أو صانع محتوى',
    'You will see their news in Content': 'سترى جديدهم في المحتوى',
    'Share the server link': 'مشاركة رابط الخادم',
    "Couldn't share the link. Try again.":
        'تعذّرت مشاركة الرابط. حاول مرة أخرى.',
    'Find Pages to follow': 'البحث عن صفحات لمتابعتها',
    'firstSteps.addFriend': 'إضافة صديق',
    'You are all caught up': 'لقد اطّلعت على كل شيء',
    'New friend requests, messages and activity will appear here.':
        'ستظهر هنا طلبات الصداقة والرسائل والنشاطات الجديدة.',
    'No friends yet': 'ليس لديك أصدقاء بعد',
    'Find someone and start building your circle.':
        'ابحث عن شخص وابدأ ببناء دائرتك.',
    'No friends to invite yet': 'ليس لديك أصدقاء لدعوتهم بعد',
    'Add friends first — a server invitation can only go to a friend.':
        'أضف أصدقاء أولًا — دعوة الخادم لا تُرسل إلا إلى صديق.',
  },
  'th': <String, String>{
    'Start here': 'เริ่มที่นี่',
    '{done} of {total}': '{done} จาก {total}',
    'firstSteps.close': 'ปิด',
    'firstSteps.stepDone': 'เสร็จแล้ว',
    'Done. You know YO Voice now.': 'เรียบร้อย ตอนนี้คุณรู้จัก YO Voice แล้ว',
    'Add a profile photo': 'เพิ่มรูปโปรไฟล์',
    'Friends will recognise you faster': 'เพื่อนจะจำคุณได้เร็วขึ้น',
    'Add your first friend': 'เพิ่มเพื่อนคนแรก',
    'Search by name or send your link': 'ค้นหาด้วยชื่อหรือส่งลิงก์ของคุณ',
    'Join a server or create your own': 'เข้าร่วมเซิร์ฟเวอร์หรือสร้างของคุณเอง',
    'See public servers or start your own':
        'ดูเซิร์ฟเวอร์สาธารณะหรือสร้างของคุณเอง',
    'Record your first Voice': 'บันทึกเสียงแรกของคุณ',
    'A short voice recording, up to 60 seconds':
        'บันทึกเสียงสั้น ๆ ไม่เกิน 60 วินาที',
    'Follow a Page or creator': 'ติดตามเพจหรือครีเอเตอร์',
    'You will see their news in Content':
        'คุณจะเห็นความเคลื่อนไหวของพวกเขาในเนื้อหา',
    'Share the server link': 'แชร์ลิงก์เซิร์ฟเวอร์',
    "Couldn't share the link. Try again.": 'แชร์ลิงก์ไม่ได้ โปรดลองอีกครั้ง',
    'Find Pages to follow': 'ค้นหาเพจเพื่อติดตาม',
    'firstSteps.addFriend': 'เพิ่มเพื่อน',
    'You are all caught up': 'คุณดูครบทุกอย่างแล้ว',
    'New friend requests, messages and activity will appear here.':
        'คำขอเป็นเพื่อน ข้อความ และความเคลื่อนไหวใหม่จะแสดงที่นี่',
    'No friends yet': 'ยังไม่มีเพื่อน',
    'Find someone and start building your circle.':
        'ค้นหาใครสักคนแล้วเริ่มสร้างกลุ่มของคุณ',
    'No friends to invite yet': 'ยังไม่มีเพื่อนให้เชิญ',
    'Add friends first — a server invitation can only go to a friend.':
        'เพิ่มเพื่อนก่อน — คำเชิญเข้าเซิร์ฟเวอร์ส่งได้เฉพาะถึงเพื่อนเท่านั้น',
  },
  'ms': <String, String>{
    'Start here': 'Mula di sini',
    '{done} of {total}': '{done} daripada {total}',
    'firstSteps.close': 'Tutup',
    'firstSteps.stepDone': 'Selesai',
    'Done. You know YO Voice now.':
        'Selesai. Kini anda sudah mengenali YO Voice.',
    'Add a profile photo': 'Tambah foto profil',
    'Friends will recognise you faster':
        'Kawan akan lebih cepat mengenali anda',
    'Add your first friend': 'Tambah kawan pertama anda',
    'Search by name or send your link':
        'Cari mengikut nama atau hantar pautan anda',
    'Join a server or create your own':
        'Sertai pelayan atau cipta pelayan sendiri',
    'See public servers or start your own':
        'Lihat pelayan awam atau cipta pelayan sendiri',
    'Record your first Voice': 'Rakam Suara pertama anda',
    'A short voice recording, up to 60 seconds':
        'Rakaman suara ringkas, sehingga 60 saat',
    'Follow a Page or creator': 'Ikuti halaman atau pencipta',
    'You will see their news in Content':
        'Berita terbaharu mereka akan muncul dalam Kandungan',
    'Share the server link': 'Kongsi pautan pelayan',
    "Couldn't share the link. Try again.":
        'Tidak dapat berkongsi pautan. Cuba lagi.',
    'Find Pages to follow': 'Cari halaman untuk diikuti',
    'firstSteps.addFriend': 'Tambah kawan',
    'You are all caught up': 'Anda sudah melihat semuanya',
    'New friend requests, messages and activity will appear here.':
        'Permintaan rakan, mesej dan aktiviti baharu akan dipaparkan di sini.',
    'No friends yet': 'Belum ada kawan',
    'Find someone and start building your circle.':
        'Cari seseorang dan mula bina kalangan anda.',
    'No friends to invite yet': 'Belum ada kawan untuk dijemput',
    'Add friends first — a server invitation can only go to a friend.':
        'Tambah kawan dahulu — jemputan pelayan hanya boleh dihantar kepada kawan.',
  },
  'fil': <String, String>{
    'Start here': 'Magsimula rito',
    '{done} of {total}': '{done} sa {total}',
    'firstSteps.close': 'Isara',
    'firstSteps.stepDone': 'Tapos na',
    'Done. You know YO Voice now.': 'Tapos na. Kilala mo na ang YO Voice.',
    'Add a profile photo': 'Magdagdag ng larawan sa profile',
    'Friends will recognise you faster':
        'Mas mabilis kang makikilala ng mga kaibigan',
    'Add your first friend': 'Idagdag ang una mong kaibigan',
    'Search by name or send your link':
        'Maghanap ayon sa pangalan o ipadala ang link mo',
    'Join a server or create your own':
        'Sumali sa isang server o gumawa ng sarili mo',
    'See public servers or start your own':
        'Tingnan ang mga pampublikong server o gumawa ng sarili mo',
    'Record your first Voice': 'I-record ang una mong Boses',
    'A short voice recording, up to 60 seconds':
        'Maikling voice recording, hanggang 60 segundo',
    'Follow a Page or creator': 'Mag-follow ng Page o creator',
    'You will see their news in Content':
        'Makikita mo ang mga balita nila sa Nilalaman',
    'Share the server link': 'Ibahagi ang link ng server',
    "Couldn't share the link. Try again.":
        'Hindi maibahagi ang link. Subukan ulit.',
    'Find Pages to follow': 'Maghanap ng mga Page na ifa-follow',
    'firstSteps.addFriend': 'Magdagdag ng kaibigan',
    'You are all caught up': 'Nakita mo na ang lahat',
    'New friend requests, messages and activity will appear here.':
        'Dito lalabas ang mga bagong kahilingan sa pagkakaibigan, mensahe, at aktibidad.',
    'No friends yet': 'Wala ka pang kaibigan',
    'Find someone and start building your circle.':
        'Humanap ng tao at simulang buuin ang iyong circle.',
    'No friends to invite yet': 'Wala ka pang kaibigang maiimbitahan',
    'Add friends first — a server invitation can only go to a friend.':
        'Magdagdag muna ng mga kaibigan — sa kaibigan lang maipapadala ang imbitasyon sa server.',
  },
  'he': <String, String>{
    'Start here': 'מתחילים כאן',
    '{done} of {total}': '{done} מתוך {total}',
    'firstSteps.close': 'סגירה',
    'firstSteps.stepDone': 'בוצע',
    'Done. You know YO Voice now.': 'זהו. עכשיו כבר מכירים את YO Voice.',
    'Add a profile photo': 'הוספת תמונת פרופיל',
    'Friends will recognise you faster': 'חברים יזהו אותך מהר יותר',
    'Add your first friend': 'הוספת חבר ראשון',
    'Search by name or send your link':
        'אפשר לחפש לפי שם או לשלוח את הקישור שלך',
    'Join a server or create your own': 'הצטרפות לשרת או יצירת שרת משלך',
    'See public servers or start your own':
        'אפשר לראות שרתים ציבוריים או לפתוח שרת משלך',
    'Record your first Voice': 'הקלטת קול ראשון',
    'A short voice recording, up to 60 seconds':
        'הקלטה קולית קצרה, עד 60 שניות',
    'Follow a Page or creator': 'מעקב אחרי דף או יוצר',
    'You will see their news in Content': 'העדכונים שלהם יופיעו בתוכן',
    'Share the server link': 'שיתוף הקישור לשרת',
    "Couldn't share the link. Try again.":
        'לא ניתן לשתף את הקישור. אפשר לנסות שוב.',
    'Find Pages to follow': 'חיפוש דפים למעקב',
    'firstSteps.addFriend': 'הוספת חבר',
    'You are all caught up': 'ראית הכול',
    'New friend requests, messages and activity will appear here.':
        'בקשות חברות, הודעות ופעילות חדשות יופיעו כאן.',
    'No friends yet': 'אין עדיין חברים',
    'Find someone and start building your circle.':
        'כדאי למצוא מישהו ולהתחיל לבנות את המעגל שלך.',
    'No friends to invite yet': 'אין עדיין חברים להזמין',
    'Add friends first — a server invitation can only go to a friend.':
        'קודם יש להוסיף חברים — הזמנה לשרת אפשר לשלוח רק לחבר.',
  },
  'fa': <String, String>{
    'Start here': 'از اینجا شروع کنید',
    '{done} of {total}': '{done} از {total}',
    'firstSteps.close': 'بستن',
    'firstSteps.stepDone': 'انجام شد',
    'Done. You know YO Voice now.': 'تمام شد. حالا YO Voice را می‌شناسید.',
    'Add a profile photo': 'افزودن عکس نمایه',
    'Friends will recognise you faster': 'دوستان زودتر شما را می‌شناسند',
    'Add your first friend': 'افزودن اولین دوست',
    'Search by name or send your link':
        'با نام جستجو کنید یا پیوندتان را بفرستید',
    'Join a server or create your own': 'پیوستن به یک سرور یا ساخت سرور خودتان',
    'See public servers or start your own':
        'سرورهای عمومی را ببینید یا سرور خودتان را بسازید',
    'Record your first Voice': 'ضبط اولین صدا',
    'A short voice recording, up to 60 seconds':
        'یک صدای ضبط‌شدهٔ کوتاه، تا 60 ثانیه',
    'Follow a Page or creator': 'دنبال کردن یک صفحه یا سازنده',
    'You will see their news in Content': 'تازه‌های آن‌ها را در محتوا می‌بینید',
    'Share the server link': 'هم‌رسانی پیوند سرور',
    "Couldn't share the link. Try again.":
        'هم‌رسانی پیوند ممکن نشد. دوباره امتحان کنید.',
    'Find Pages to follow': 'یافتن صفحه برای دنبال کردن',
    'firstSteps.addFriend': 'افزودن دوست',
    'You are all caught up': 'همه چیز را دیده‌اید',
    'New friend requests, messages and activity will appear here.':
        'درخواست‌های دوستی، پیام‌ها و فعالیت‌های جدید اینجا نمایش داده می‌شوند.',
    'No friends yet': 'هنوز دوستی ندارید',
    'Find someone and start building your circle.':
        'کسی را پیدا کنید و ساختن حلقهٔ خود را شروع کنید.',
    'No friends to invite yet': 'هنوز دوستی برای دعوت ندارید',
    'Add friends first — a server invitation can only go to a friend.':
        'ابتدا دوستانی اضافه کنید — دعوت به سرور فقط برای دوستان ارسال می‌شود.',
  },
  'sw': <String, String>{
    'Start here': 'Anzia hapa',
    '{done} of {total}': '{done} kati ya {total}',
    'firstSteps.close': 'Funga',
    'firstSteps.stepDone': 'Imekamilika',
    'Done. You know YO Voice now.': 'Tayari. Sasa unaifahamu YO Voice.',
    'Add a profile photo': 'Ongeza picha ya wasifu',
    'Friends will recognise you faster': 'Marafiki watakutambua haraka zaidi',
    'Add your first friend': 'Ongeza rafiki yako wa kwanza',
    'Search by name or send your link': 'Tafuta kwa jina au tuma kiungo chako',
    'Join a server or create your own': 'Jiunge na seva au unda yako mwenyewe',
    'See public servers or start your own':
        'Tazama seva za umma au anzisha yako mwenyewe',
    'Record your first Voice': 'Rekodi Sauti yako ya kwanza',
    'A short voice recording, up to 60 seconds':
        'Rekodi fupi ya sauti, hadi sekunde 60',
    'Follow a Page or creator': 'Fuata ukurasa au mtayarishi',
    'You will see their news in Content': 'Utaona habari zao katika Maudhui',
    'Share the server link': 'Shiriki kiungo cha seva',
    "Couldn't share the link. Try again.":
        'Imeshindwa kushiriki kiungo. Jaribu tena.',
    'Find Pages to follow': 'Tafuta kurasa za kufuata',
    'firstSteps.addFriend': 'Ongeza rafiki',
    'You are all caught up': 'Umeona kila kitu',
    'New friend requests, messages and activity will appear here.':
        'Maombi mapya ya urafiki, ujumbe na shughuli vitaonekana hapa.',
    'No friends yet': 'Bado huna marafiki',
    'Find someone and start building your circle.':
        'Tafuta mtu na uanze kujenga mduara wako.',
    'No friends to invite yet': 'Bado huna marafiki wa kualika',
    'Add friends first — a server invitation can only go to a friend.':
        'Ongeza marafiki kwanza — mwaliko wa seva unaweza kutumwa kwa rafiki pekee.',
  },
  'hi': <String, String>{
    'Start here': 'यहाँ से शुरू करें',
    '{done} of {total}': '{total} में से {done}',
    'firstSteps.close': 'बंद करें',
    'firstSteps.stepDone': 'पूरा हुआ',
    'Done. You know YO Voice now.': 'हो गया। अब आप YO Voice को जानते हैं।',
    'Add a profile photo': 'प्रोफ़ाइल फ़ोटो जोड़ें',
    'Friends will recognise you faster': 'दोस्त आपको जल्दी पहचान लेंगे',
    'Add your first friend': 'अपना पहला दोस्त जोड़ें',
    'Search by name or send your link': 'नाम से खोजें या अपना लिंक भेजें',
    'Join a server or create your own':
        'किसी सर्वर से जुड़ें या अपना सर्वर बनाएँ',
    'See public servers or start your own':
        'सार्वजनिक सर्वर देखें या अपना सर्वर शुरू करें',
    'Record your first Voice': 'अपनी पहली आवाज़ रिकॉर्ड करें',
    'A short voice recording, up to 60 seconds':
        'एक छोटी वॉइस रिकॉर्डिंग, 60 सेकंड तक',
    'Follow a Page or creator': 'किसी पेज या रचनाकार को फ़ॉलो करें',
    'You will see their news in Content':
        'उनकी नई जानकारी आपको सामग्री में दिखेगी',
    'Share the server link': 'सर्वर का लिंक शेयर करें',
    "Couldn't share the link. Try again.":
        'लिंक शेयर नहीं हो सका। फिर से कोशिश करें।',
    'Find Pages to follow': 'फ़ॉलो करने के लिए पेज खोजें',
    'firstSteps.addFriend': 'दोस्त जोड़ें',
    'You are all caught up': 'आपने सब कुछ देख लिया है',
    'New friend requests, messages and activity will appear here.':
        'नए दोस्ती के अनुरोध, संदेश और गतिविधि यहाँ दिखेंगे।',
    'No friends yet': 'अभी कोई दोस्त नहीं है',
    'Find someone and start building your circle.':
        'किसी को खोजें और अपना दायरा बनाना शुरू करें।',
    'No friends to invite yet': 'आमंत्रित करने के लिए अभी कोई दोस्त नहीं है',
    'Add friends first — a server invitation can only go to a friend.':
        'पहले दोस्त जोड़ें — सर्वर का आमंत्रण केवल किसी दोस्त को भेजा जा सकता है।',
  },
  'bn': <String, String>{
    'Start here': 'এখান থেকে শুরু করুন',
    '{done} of {total}': '{total}টির মধ্যে {done}টি',
    'firstSteps.close': 'বন্ধ করুন',
    'firstSteps.stepDone': 'সম্পন্ন',
    'Done. You know YO Voice now.': 'হয়ে গেছে। এখন আপনি YO Voice চেনেন।',
    'Add a profile photo': 'প্রোফাইল ছবি যোগ করুন',
    'Friends will recognise you faster': 'বন্ধুরা আপনাকে দ্রুত চিনতে পারবে',
    'Add your first friend': 'আপনার প্রথম বন্ধু যোগ করুন',
    'Search by name or send your link':
        'নাম দিয়ে খুঁজুন অথবা আপনার লিংক পাঠান',
    'Join a server or create your own':
        'কোনো সার্ভারে যোগ দিন অথবা নিজের সার্ভার তৈরি করুন',
    'See public servers or start your own':
        'পাবলিক সার্ভার দেখুন অথবা নিজের সার্ভার শুরু করুন',
    'Record your first Voice': 'আপনার প্রথম কণ্ঠ রেকর্ড করুন',
    'A short voice recording, up to 60 seconds':
        'একটি ছোট ভয়েস রেকর্ডিং, সর্বোচ্চ 60 সেকেন্ড',
    'Follow a Page or creator': 'কোনো পেজ বা নির্মাতাকে ফলো করুন',
    'You will see their news in Content': 'তাদের নতুন খবর কনটেন্টে দেখতে পাবেন',
    'Share the server link': 'সার্ভারের লিংক শেয়ার করুন',
    "Couldn't share the link. Try again.":
        'লিংক শেয়ার করা যায়নি। আবার চেষ্টা করুন।',
    'Find Pages to follow': 'ফলো করার জন্য পেজ খুঁজুন',
    'firstSteps.addFriend': 'বন্ধু যোগ করুন',
    'You are all caught up': 'আপনি সবকিছু দেখে ফেলেছেন',
    'New friend requests, messages and activity will appear here.':
        'নতুন বন্ধুত্বের অনুরোধ, বার্তা ও কার্যকলাপ এখানে দেখা যাবে।',
    'No friends yet': 'এখনও কোনো বন্ধু নেই',
    'Find someone and start building your circle.':
        'কাউকে খুঁজে নিন এবং নিজের বৃত্ত গড়া শুরু করুন।',
    'No friends to invite yet': 'আমন্ত্রণ জানানোর মতো কোনো বন্ধু এখনও নেই',
    'Add friends first — a server invitation can only go to a friend.':
        'আগে বন্ধু যোগ করুন — সার্ভারের আমন্ত্রণ শুধু বন্ধুকেই পাঠানো যায়।',
  },
  'ur': <String, String>{
    'Start here': 'یہاں سے شروع کریں',
    '{done} of {total}': '{total} میں سے {done}',
    'firstSteps.close': 'بند کریں',
    'firstSteps.stepDone': 'مکمل',
    'Done. You know YO Voice now.': 'ہو گیا۔ اب آپ YO Voice کو جانتے ہیں۔',
    'Add a profile photo': 'پروفائل تصویر شامل کریں',
    'Friends will recognise you faster': 'دوست آپ کو جلدی پہچان لیں گے',
    'Add your first friend': 'اپنا پہلا دوست شامل کریں',
    'Search by name or send your link': 'نام سے تلاش کریں یا اپنا لنک بھیجیں',
    'Join a server or create your own':
        'کسی سرور میں شامل ہوں یا اپنا سرور بنائیں',
    'See public servers or start your own':
        'عوامی سرور دیکھیں یا اپنا سرور شروع کریں',
    'Record your first Voice': 'اپنی پہلی آواز ریکارڈ کریں',
    'A short voice recording, up to 60 seconds':
        'ایک مختصر صوتی ریکارڈنگ، 60 سیکنڈ تک',
    'Follow a Page or creator': 'کسی پیج یا تخلیق کار کو فالو کریں',
    'You will see their news in Content':
        'ان کی نئی خبریں آپ کو مواد میں نظر آئیں گی',
    'Share the server link': 'سرور کا لنک شیئر کریں',
    "Couldn't share the link. Try again.":
        'لنک شیئر نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    'Find Pages to follow': 'فالو کرنے کے لیے پیجز تلاش کریں',
    'firstSteps.addFriend': 'دوست شامل کریں',
    'You are all caught up': 'آپ نے سب کچھ دیکھ لیا ہے',
    'New friend requests, messages and activity will appear here.':
        'نئی فرینڈ ریکویسٹس، پیغامات اور سرگرمی یہاں نظر آئیں گی۔',
    'No friends yet': 'ابھی کوئی دوست نہیں ہے',
    'Find someone and start building your circle.':
        'کسی کو تلاش کریں اور اپنا حلقہ بنانا شروع کریں۔',
    'No friends to invite yet': 'مدعو کرنے کے لیے ابھی کوئی دوست نہیں ہے',
    'Add friends first — a server invitation can only go to a friend.':
        'پہلے دوست شامل کریں — سرور کی دعوت صرف کسی دوست کو بھیجی جا سکتی ہے۔',
  },
};
