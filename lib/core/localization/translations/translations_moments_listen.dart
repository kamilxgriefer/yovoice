/// Copy introduced by the expanded Voice Moment (board 07): the listening
/// progress ring, the transport with its ±15 s skips, the "Rozmowa" thread
/// with its voice-reply mini-players, and the hand-off list of the loaded
/// neighbours.
///
/// Short words that mean something else elsewhere in the product ("Play",
/// "Pause", "Reply", "Conversation") are keyed by context so this surface
/// cannot leak into unrelated copy. Position and duration strings are
/// templates: the numbers are substituted AFTER localization.
///
/// Every selectable locale receives an explicit translation instead of
/// silently falling back to English — with one deliberate exception. The
/// bare percentage under the ring ("40 %" / "40%") is NOT catalogued: in
/// most of the extended locales its correct rendering is byte-identical to
/// English, which the catalog's own guard reads as untranslated fallback
/// copy. It stays a `template` carrying the English and Polish spellings
/// (Polish keeps the space), and every other locale resolves to the English
/// form — a number and a sign, with no prose in it to translate.
const momentsListenTranslationKeys = <String>[
  'yoMoments.play',
  'yoMoments.pause',
  'yoMoments.loading',
  'yoMoments.conversation',
  'yoMoments.replyToComment',
  'Listening progress',
  'Skip back 15 seconds',
  'Skip forward 15 seconds',
  'Next Moments',
  'Show more replies',
  'You can no longer reply.',
  'Could not load more replies. Try again.',
  '{position} of {total}',
  'Play voice reply from {name}, {duration}',
  'Pause voice reply from {name}, {duration}',
  'Now playing: {caption}',
  'Open Voice Moment: {caption}, {author}',
];

const momentsListenTranslations = <String, Map<String, String>>{
  'de': {
    'yoMoments.play': 'Abspielen',
    'yoMoments.pause': 'Pause',
    'yoMoments.loading': 'Wird geladen',
    'yoMoments.conversation': 'Gespräch',
    'yoMoments.replyToComment': 'Antworten',
    'Listening progress': 'Hörfortschritt',
    'Skip back 15 seconds': '15 Sekunden zurück',
    'Skip forward 15 seconds': '15 Sekunden vor',
    'Next Moments': 'Weitere Moments',
    'Show more replies': 'Weitere Antworten anzeigen',
    'You can no longer reply.': 'Du kannst nicht mehr antworten.',
    'Could not load more replies. Try again.':
        'Weitere Antworten konnten nicht geladen werden. Versuche es erneut.',
    '{position} of {total}': '{position} von {total}',
    'Play voice reply from {name}, {duration}':
        'Sprachantwort von {name} abspielen, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Sprachantwort von {name} pausieren, {duration}',
    'Now playing: {caption}': 'Läuft gerade: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment öffnen: {caption}, {author}',
  },
  'es': {
    'yoMoments.play': 'Reproducir',
    'yoMoments.pause': 'Pausa',
    'yoMoments.loading': 'Cargando',
    'yoMoments.conversation': 'Conversación',
    'yoMoments.replyToComment': 'Responder',
    'Listening progress': 'Progreso de escucha',
    'Skip back 15 seconds': 'Retroceder 15 segundos',
    'Skip forward 15 seconds': 'Avanzar 15 segundos',
    'Next Moments': 'Próximos Moments',
    'Show more replies': 'Ver más respuestas',
    'You can no longer reply.': 'Ya no puedes responder.',
    'Could not load more replies. Try again.':
        'No se pudieron cargar más respuestas. Inténtalo de nuevo.',
    '{position} of {total}': '{position} de {total}',
    'Play voice reply from {name}, {duration}':
        'Reproducir la respuesta de voz de {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pausar la respuesta de voz de {name}, {duration}',
    'Now playing: {caption}': 'Reproduciendo: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Abrir Voice Moment: {caption}, {author}',
  },
  'pt': {
    'yoMoments.play': 'Reproduzir',
    'yoMoments.pause': 'Pausa',
    'yoMoments.loading': 'A carregar',
    'yoMoments.conversation': 'Conversa',
    'yoMoments.replyToComment': 'Responder',
    'Listening progress': 'Progresso da audição',
    'Skip back 15 seconds': 'Recuar 15 segundos',
    'Skip forward 15 seconds': 'Avançar 15 segundos',
    'Next Moments': 'Próximos Moments',
    'Show more replies': 'Ver mais respostas',
    'You can no longer reply.': 'Já não podes responder.',
    'Could not load more replies. Try again.':
        'Não foi possível carregar mais respostas. Tenta novamente.',
    '{position} of {total}': '{position} de {total}',
    'Play voice reply from {name}, {duration}':
        'Reproduzir a resposta de voz de {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pausar a resposta de voz de {name}, {duration}',
    'Now playing: {caption}': 'A reproduzir: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Abrir Voice Moment: {caption}, {author}',
  },
  'pt_BR': {
    'yoMoments.play': 'Reproduzir',
    'yoMoments.pause': 'Pausar',
    'yoMoments.loading': 'Carregando',
    'yoMoments.conversation': 'Conversa',
    'yoMoments.replyToComment': 'Responder',
    'Listening progress': 'Progresso da escuta',
    'Skip back 15 seconds': 'Voltar 15 segundos',
    'Skip forward 15 seconds': 'Avançar 15 segundos',
    'Next Moments': 'Próximos Moments',
    'Show more replies': 'Ver mais respostas',
    'You can no longer reply.': 'Você não pode mais responder.',
    'Could not load more replies. Try again.':
        'Não foi possível carregar mais respostas. Tente de novo.',
    '{position} of {total}': '{position} de {total}',
    'Play voice reply from {name}, {duration}':
        'Reproduzir a resposta de voz de {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pausar a resposta de voz de {name}, {duration}',
    'Now playing: {caption}': 'Tocando agora: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Abrir Voice Moment: {caption}, {author}',
  },
  'fr': {
    'yoMoments.play': 'Lire',
    'yoMoments.pause': 'Pause',
    'yoMoments.loading': 'Chargement',
    'yoMoments.conversation': 'Conversation',
    'yoMoments.replyToComment': 'Répondre',
    'Listening progress': 'Progression de l\'écoute',
    'Skip back 15 seconds': 'Reculer de 15 secondes',
    'Skip forward 15 seconds': 'Avancer de 15 secondes',
    'Next Moments': 'Moments suivants',
    'Show more replies': 'Afficher plus de réponses',
    'You can no longer reply.': 'Tu ne peux plus répondre.',
    'Could not load more replies. Try again.':
        'Impossible de charger plus de réponses. Réessaie.',
    '{position} of {total}': '{position} sur {total}',
    'Play voice reply from {name}, {duration}':
        'Lire la réponse vocale de {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Mettre en pause la réponse vocale de {name}, {duration}',
    'Now playing: {caption}': 'En cours d\'écoute : {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Ouvrir le Voice Moment : {caption}, {author}',
  },
  'it': {
    'yoMoments.play': 'Riproduci',
    'yoMoments.pause': 'Pausa',
    'yoMoments.loading': 'Caricamento',
    'yoMoments.conversation': 'Conversazione',
    'yoMoments.replyToComment': 'Rispondi',
    'Listening progress': 'Avanzamento dell\'ascolto',
    'Skip back 15 seconds': 'Indietro di 15 secondi',
    'Skip forward 15 seconds': 'Avanti di 15 secondi',
    'Next Moments': 'Prossimi Moments',
    'Show more replies': 'Mostra altre risposte',
    'You can no longer reply.': 'Non puoi più rispondere.',
    'Could not load more replies. Try again.':
        'Non è stato possibile caricare altre risposte. Riprova.',
    '{position} of {total}': '{position} di {total}',
    'Play voice reply from {name}, {duration}':
        'Riproduci la risposta vocale di {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Metti in pausa la risposta vocale di {name}, {duration}',
    'Now playing: {caption}': 'In riproduzione: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Apri il Voice Moment: {caption}, {author}',
  },
  'uk': {
    'yoMoments.play': 'Відтворити',
    'yoMoments.pause': 'Пауза',
    'yoMoments.loading': 'Завантаження',
    'yoMoments.conversation': 'Розмова',
    'yoMoments.replyToComment': 'Відповісти',
    'Listening progress': 'Прогрес прослуховування',
    'Skip back 15 seconds': 'Назад на 15 секунд',
    'Skip forward 15 seconds': 'Вперед на 15 секунд',
    'Next Moments': 'Наступні Moments',
    'Show more replies': 'Показати більше відповідей',
    'You can no longer reply.': 'Відповідати вже не можна.',
    'Could not load more replies. Try again.':
        'Не вдалося завантажити більше відповідей. Спробуйте ще раз.',
    '{position} of {total}': '{position} з {total}',
    'Play voice reply from {name}, {duration}':
        'Відтворити голосову відповідь: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Призупинити голосову відповідь: {name}, {duration}',
    'Now playing: {caption}': 'Зараз відтворюється: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Відкрити Voice Moment: {caption}, {author}',
  },
  'ru': {
    'yoMoments.play': 'Воспроизвести',
    'yoMoments.pause': 'Пауза',
    'yoMoments.loading': 'Загрузка',
    'yoMoments.conversation': 'Разговор',
    'yoMoments.replyToComment': 'Ответить',
    'Listening progress': 'Прогресс прослушивания',
    'Skip back 15 seconds': 'Назад на 15 секунд',
    'Skip forward 15 seconds': 'Вперёд на 15 секунд',
    'Next Moments': 'Следующие Moments',
    'Show more replies': 'Показать больше ответов',
    'You can no longer reply.': 'Отвечать больше нельзя.',
    'Could not load more replies. Try again.':
        'Не удалось загрузить больше ответов. Попробуйте ещё раз.',
    '{position} of {total}': '{position} из {total}',
    'Play voice reply from {name}, {duration}':
        'Воспроизвести голосовой ответ: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Приостановить голосовой ответ: {name}, {duration}',
    'Now playing: {caption}': 'Сейчас звучит: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Открыть Voice Moment: {caption}, {author}',
  },
  'cs': {
    'yoMoments.play': 'Přehrát',
    'yoMoments.pause': 'Pauza',
    'yoMoments.loading': 'Načítání',
    'yoMoments.conversation': 'Rozhovor',
    'yoMoments.replyToComment': 'Odpovědět',
    'Listening progress': 'Průběh poslechu',
    'Skip back 15 seconds': 'Zpět o 15 sekund',
    'Skip forward 15 seconds': 'Vpřed o 15 sekund',
    'Next Moments': 'Další Moments',
    'Show more replies': 'Zobrazit další odpovědi',
    'You can no longer reply.': 'Už nelze odpovídat.',
    'Could not load more replies. Try again.':
        'Další odpovědi se nepodařilo načíst. Zkuste to znovu.',
    '{position} of {total}': '{position} z {total}',
    'Play voice reply from {name}, {duration}':
        'Přehrát hlasovou odpověď: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pozastavit hlasovou odpověď: {name}, {duration}',
    'Now playing: {caption}': 'Právě hraje: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Otevřít Voice Moment: {caption}, {author}',
  },
  'sk': {
    'yoMoments.play': 'Prehrať',
    'yoMoments.pause': 'Pauza',
    'yoMoments.loading': 'Načítava sa',
    'yoMoments.conversation': 'Rozhovor',
    'yoMoments.replyToComment': 'Odpovedať',
    'Listening progress': 'Priebeh počúvania',
    'Skip back 15 seconds': 'Späť o 15 sekúnd',
    'Skip forward 15 seconds': 'Vpred o 15 sekúnd',
    'Next Moments': 'Ďalšie Moments',
    'Show more replies': 'Zobraziť ďalšie odpovede',
    'You can no longer reply.': 'Už sa nedá odpovedať.',
    'Could not load more replies. Try again.':
        'Ďalšie odpovede sa nepodarilo načítať. Skúste to znova.',
    '{position} of {total}': '{position} z {total}',
    'Play voice reply from {name}, {duration}':
        'Prehrať hlasovú odpoveď: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pozastaviť hlasovú odpoveď: {name}, {duration}',
    'Now playing: {caption}': 'Práve hrá: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Otvoriť Voice Moment: {caption}, {author}',
  },
  'bg': {
    'yoMoments.play': 'Пусни',
    'yoMoments.pause': 'Пауза',
    'yoMoments.loading': 'Зарежда се',
    'yoMoments.conversation': 'Разговор',
    'yoMoments.replyToComment': 'Отговори',
    'Listening progress': 'Напредък на слушането',
    'Skip back 15 seconds': 'Назад с 15 секунди',
    'Skip forward 15 seconds': 'Напред с 15 секунди',
    'Next Moments': 'Следващи Moments',
    'Show more replies': 'Покажи още отговори',
    'You can no longer reply.': 'Вече не можеш да отговаряш.',
    'Could not load more replies. Try again.':
        'Още отговори не бяха заредени. Опитай отново.',
    '{position} of {total}': '{position} от {total}',
    'Play voice reply from {name}, {duration}':
        'Пусни гласовия отговор на {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Спри гласовия отговор на {name}, {duration}',
    'Now playing: {caption}': 'Сега звучи: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Отвори Voice Moment: {caption}, {author}',
  },
  'nl': {
    'yoMoments.play': 'Afspelen',
    'yoMoments.pause': 'Pauze',
    'yoMoments.loading': 'Laden',
    'yoMoments.conversation': 'Gesprek',
    'yoMoments.replyToComment': 'Reageren',
    'Listening progress': 'Luistervoortgang',
    'Skip back 15 seconds': '15 seconden terug',
    'Skip forward 15 seconds': '15 seconden vooruit',
    'Next Moments': 'Volgende Moments',
    'Show more replies': 'Meer reacties tonen',
    'You can no longer reply.': 'Je kunt niet meer reageren.',
    'Could not load more replies. Try again.':
        'Meer reacties konden niet worden geladen. Probeer het opnieuw.',
    '{position} of {total}': '{position} van {total}',
    'Play voice reply from {name}, {duration}':
        'Spraakreactie van {name} afspelen, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Spraakreactie van {name} pauzeren, {duration}',
    'Now playing: {caption}': 'Nu te horen: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment openen: {caption}, {author}',
  },
  'ro': {
    'yoMoments.play': 'Redă',
    'yoMoments.pause': 'Pauză',
    'yoMoments.loading': 'Se încarcă',
    'yoMoments.conversation': 'Conversație',
    'yoMoments.replyToComment': 'Răspunde',
    'Listening progress': 'Progresul ascultării',
    'Skip back 15 seconds': 'Înapoi cu 15 secunde',
    'Skip forward 15 seconds': 'Înainte cu 15 secunde',
    'Next Moments': 'Următoarele Moments',
    'Show more replies': 'Arată mai multe răspunsuri',
    'You can no longer reply.': 'Nu mai poți răspunde.',
    'Could not load more replies. Try again.':
        'Nu s-au putut încărca mai multe răspunsuri. Încearcă din nou.',
    '{position} of {total}': '{position} din {total}',
    'Play voice reply from {name}, {duration}':
        'Redă răspunsul vocal de la {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pune pauză răspunsului vocal de la {name}, {duration}',
    'Now playing: {caption}': 'Se redă acum: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Deschide Voice Moment: {caption}, {author}',
  },
  'tr': {
    'yoMoments.play': 'Oynat',
    'yoMoments.pause': 'Duraklat',
    'yoMoments.loading': 'Yükleniyor',
    'yoMoments.conversation': 'Sohbet',
    'yoMoments.replyToComment': 'Yanıtla',
    'Listening progress': 'Dinleme ilerlemesi',
    'Skip back 15 seconds': '15 saniye geri',
    'Skip forward 15 seconds': '15 saniye ileri',
    'Next Moments': 'Sonraki Moments',
    'Show more replies': 'Daha fazla yanıt göster',
    'You can no longer reply.': 'Artık yanıt veremezsin.',
    'Could not load more replies. Try again.':
        'Daha fazla yanıt yüklenemedi. Tekrar dene.',
    '{position} of {total}': '{total} içinde {position}',
    'Play voice reply from {name}, {duration}':
        '{name} kişisinin sesli yanıtını oynat, {duration}',
    'Pause voice reply from {name}, {duration}':
        '{name} kişisinin sesli yanıtını duraklat, {duration}',
    'Now playing: {caption}': 'Şimdi çalıyor: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment aç: {caption}, {author}',
  },
  'el': {
    'yoMoments.play': 'Αναπαραγωγή',
    'yoMoments.pause': 'Παύση',
    'yoMoments.loading': 'Φόρτωση',
    'yoMoments.conversation': 'Συζήτηση',
    'yoMoments.replyToComment': 'Απάντηση',
    'Listening progress': 'Πρόοδος ακρόασης',
    'Skip back 15 seconds': 'Πίσω 15 δευτερόλεπτα',
    'Skip forward 15 seconds': 'Μπροστά 15 δευτερόλεπτα',
    'Next Moments': 'Επόμενα Moments',
    'Show more replies': 'Εμφάνιση περισσότερων απαντήσεων',
    'You can no longer reply.': 'Δεν μπορείς πλέον να απαντήσεις.',
    'Could not load more replies. Try again.':
        'Δεν φορτώθηκαν περισσότερες απαντήσεις. Δοκίμασε ξανά.',
    '{position} of {total}': '{position} από {total}',
    'Play voice reply from {name}, {duration}':
        'Αναπαραγωγή φωνητικής απάντησης από {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Παύση φωνητικής απάντησης από {name}, {duration}',
    'Now playing: {caption}': 'Παίζει τώρα: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Άνοιγμα Voice Moment: {caption}, {author}',
  },
  'hu': {
    'yoMoments.play': 'Lejátszás',
    'yoMoments.pause': 'Szünet',
    'yoMoments.loading': 'Betöltés',
    'yoMoments.conversation': 'Beszélgetés',
    'yoMoments.replyToComment': 'Válasz',
    'Listening progress': 'Hallgatás állapota',
    'Skip back 15 seconds': '15 másodperccel vissza',
    'Skip forward 15 seconds': '15 másodperccel előre',
    'Next Moments': 'További Moments',
    'Show more replies': 'További válaszok megjelenítése',
    'You can no longer reply.': 'Már nem válaszolhatsz.',
    'Could not load more replies. Try again.':
        'Nem sikerült több választ betölteni. Próbáld újra.',
    '{position} of {total}': '{position} / {total}',
    'Play voice reply from {name}, {duration}':
        '{name} hangüzenetének lejátszása, {duration}',
    'Pause voice reply from {name}, {duration}':
        '{name} hangüzenetének szüneteltetése, {duration}',
    'Now playing: {caption}': 'Most szól: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment megnyitása: {caption}, {author}',
  },
  'hr': {
    'yoMoments.play': 'Reproduciraj',
    'yoMoments.pause': 'Pauza',
    'yoMoments.loading': 'Učitavanje',
    'yoMoments.conversation': 'Razgovor',
    'yoMoments.replyToComment': 'Odgovori',
    'Listening progress': 'Napredak slušanja',
    'Skip back 15 seconds': 'Natrag 15 sekundi',
    'Skip forward 15 seconds': 'Naprijed 15 sekundi',
    'Next Moments': 'Sljedeći Moments',
    'Show more replies': 'Prikaži više odgovora',
    'You can no longer reply.': 'Više ne možeš odgovoriti.',
    'Could not load more replies. Try again.':
        'Nije bilo moguće učitati više odgovora. Pokušaj ponovno.',
    '{position} of {total}': '{position} od {total}',
    'Play voice reply from {name}, {duration}':
        'Reproduciraj glasovni odgovor: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pauziraj glasovni odgovor: {name}, {duration}',
    'Now playing: {caption}': 'Sada svira: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Otvori Voice Moment: {caption}, {author}',
  },
  'sr': {
    'yoMoments.play': 'Пусти',
    'yoMoments.pause': 'Пауза',
    'yoMoments.loading': 'Учитавање',
    'yoMoments.conversation': 'Разговор',
    'yoMoments.replyToComment': 'Одговори',
    'Listening progress': 'Напредак слушања',
    'Skip back 15 seconds': 'Назад 15 секунди',
    'Skip forward 15 seconds': 'Напред 15 секунди',
    'Next Moments': 'Следећи Moments',
    'Show more replies': 'Прикажи још одговора',
    'You can no longer reply.': 'Више не можеш да одговориш.',
    'Could not load more replies. Try again.':
        'Није било могуће учитати још одговора. Покушај поново.',
    '{position} of {total}': '{position} од {total}',
    'Play voice reply from {name}, {duration}':
        'Пусти гласовни одговор: {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Паузирај гласовни одговор: {name}, {duration}',
    'Now playing: {caption}': 'Сада се чује: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Отвори Voice Moment: {caption}, {author}',
  },
  'sv': {
    'yoMoments.play': 'Spela upp',
    'yoMoments.pause': 'Pausa',
    'yoMoments.loading': 'Laddar',
    'yoMoments.conversation': 'Samtal',
    'yoMoments.replyToComment': 'Svara',
    'Listening progress': 'Lyssningsförlopp',
    'Skip back 15 seconds': '15 sekunder bakåt',
    'Skip forward 15 seconds': '15 sekunder framåt',
    'Next Moments': 'Nästa Moments',
    'Show more replies': 'Visa fler svar',
    'You can no longer reply.': 'Du kan inte svara längre.',
    'Could not load more replies. Try again.':
        'Fler svar kunde inte laddas. Försök igen.',
    '{position} of {total}': '{position} av {total}',
    'Play voice reply from {name}, {duration}':
        'Spela upp röstsvar från {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pausa röstsvar från {name}, {duration}',
    'Now playing: {caption}': 'Spelas nu: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Öppna Voice Moment: {caption}, {author}',
  },
  'da': {
    'yoMoments.play': 'Afspil',
    'yoMoments.pause': 'Pause',
    'yoMoments.loading': 'Indlæser',
    'yoMoments.conversation': 'Samtale',
    'yoMoments.replyToComment': 'Svar',
    'Listening progress': 'Lytteforløb',
    'Skip back 15 seconds': '15 sekunder tilbage',
    'Skip forward 15 seconds': '15 sekunder frem',
    'Next Moments': 'Næste Moments',
    'Show more replies': 'Vis flere svar',
    'You can no longer reply.': 'Du kan ikke svare længere.',
    'Could not load more replies. Try again.':
        'Flere svar kunne ikke indlæses. Prøv igen.',
    '{position} of {total}': '{position} af {total}',
    'Play voice reply from {name}, {duration}':
        'Afspil stemmesvar fra {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Sæt stemmesvar fra {name} på pause, {duration}',
    'Now playing: {caption}': 'Afspilles nu: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Åbn Voice Moment: {caption}, {author}',
  },
  'nb': {
    'yoMoments.play': 'Spill av',
    'yoMoments.pause': 'Pause',
    'yoMoments.loading': 'Laster',
    'yoMoments.conversation': 'Samtale',
    'yoMoments.replyToComment': 'Svar',
    'Listening progress': 'Lytteframdrift',
    'Skip back 15 seconds': '15 sekunder tilbake',
    'Skip forward 15 seconds': '15 sekunder fram',
    'Next Moments': 'Neste Moments',
    'Show more replies': 'Vis flere svar',
    'You can no longer reply.': 'Du kan ikke svare lenger.',
    'Could not load more replies. Try again.':
        'Flere svar kunne ikke lastes. Prøv igjen.',
    '{position} of {total}': '{position} av {total}',
    'Play voice reply from {name}, {duration}':
        'Spill av talesvar fra {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Sett talesvar fra {name} på pause, {duration}',
    'Now playing: {caption}': 'Spilles nå: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Åpne Voice Moment: {caption}, {author}',
  },
  'fi': {
    'yoMoments.play': 'Toista',
    'yoMoments.pause': 'Tauko',
    'yoMoments.loading': 'Ladataan',
    'yoMoments.conversation': 'Keskustelu',
    'yoMoments.replyToComment': 'Vastaa',
    'Listening progress': 'Kuuntelun eteneminen',
    'Skip back 15 seconds': '15 sekuntia taaksepäin',
    'Skip forward 15 seconds': '15 sekuntia eteenpäin',
    'Next Moments': 'Seuraavat Moments',
    'Show more replies': 'Näytä lisää vastauksia',
    'You can no longer reply.': 'Et voi enää vastata.',
    'Could not load more replies. Try again.':
        'Lisää vastauksia ei voitu ladata. Yritä uudelleen.',
    '{position} of {total}': '{position} / {total}',
    'Play voice reply from {name}, {duration}':
        'Toista käyttäjän {name} ääniviesti, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Keskeytä käyttäjän {name} ääniviesti, {duration}',
    'Now playing: {caption}': 'Soi nyt: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Avaa Voice Moment: {caption}, {author}',
  },
  'lt': {
    'yoMoments.play': 'Leisti',
    'yoMoments.pause': 'Pauzė',
    'yoMoments.loading': 'Įkeliama',
    'yoMoments.conversation': 'Pokalbis',
    'yoMoments.replyToComment': 'Atsakyti',
    'Listening progress': 'Klausymo eiga',
    'Skip back 15 seconds': 'Atgal 15 sekundžių',
    'Skip forward 15 seconds': 'Pirmyn 15 sekundžių',
    'Next Moments': 'Kiti Moments',
    'Show more replies': 'Rodyti daugiau atsakymų',
    'You can no longer reply.': 'Nebegalima atsakyti.',
    'Could not load more replies. Try again.':
        'Nepavyko įkelti daugiau atsakymų. Bandyk dar kartą.',
    '{position} of {total}': '{position} iš {total}',
    'Play voice reply from {name}, {duration}':
        'Leisti {name} balso atsakymą, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Pristabdyti {name} balso atsakymą, {duration}',
    'Now playing: {caption}': 'Dabar grojama: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Atidaryti Voice Moment: {caption}, {author}',
  },
  'lv': {
    'yoMoments.play': 'Atskaņot',
    'yoMoments.pause': 'Pauze',
    'yoMoments.loading': 'Notiek ielāde',
    'yoMoments.conversation': 'Saruna',
    'yoMoments.replyToComment': 'Atbildēt',
    'Listening progress': 'Klausīšanās gaita',
    'Skip back 15 seconds': 'Atpakaļ par 15 sekundēm',
    'Skip forward 15 seconds': 'Uz priekšu par 15 sekundēm',
    'Next Moments': 'Nākamie Moments',
    'Show more replies': 'Rādīt vairāk atbilžu',
    'You can no longer reply.': 'Vairs nevar atbildēt.',
    'Could not load more replies. Try again.':
        'Neizdevās ielādēt vairāk atbilžu. Mēģini vēlreiz.',
    '{position} of {total}': '{position} no {total}',
    'Play voice reply from {name}, {duration}':
        'Atskaņot {name} balss atbildi, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Apturēt {name} balss atbildi, {duration}',
    'Now playing: {caption}': 'Tagad skan: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Atvērt Voice Moment: {caption}, {author}',
  },
  'et': {
    'yoMoments.play': 'Esita',
    'yoMoments.pause': 'Paus',
    'yoMoments.loading': 'Laadimine',
    'yoMoments.conversation': 'Vestlus',
    'yoMoments.replyToComment': 'Vasta',
    'Listening progress': 'Kuulamise edenemine',
    'Skip back 15 seconds': '15 sekundit tagasi',
    'Skip forward 15 seconds': '15 sekundit edasi',
    'Next Moments': 'Järgmised Moments',
    'Show more replies': 'Näita rohkem vastuseid',
    'You can no longer reply.': 'Sa ei saa enam vastata.',
    'Could not load more replies. Try again.':
        'Rohkem vastuseid ei õnnestunud laadida. Proovi uuesti.',
    '{position} of {total}': '{position} / {total}',
    'Play voice reply from {name}, {duration}':
        'Esita kasutaja {name} häälvastus, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Peata kasutaja {name} häälvastus, {duration}',
    'Now playing: {caption}': 'Praegu mängib: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Ava Voice Moment: {caption}, {author}',
  },
  'id': {
    'yoMoments.play': 'Putar',
    'yoMoments.pause': 'Jeda',
    'yoMoments.loading': 'Memuat',
    'yoMoments.conversation': 'Percakapan',
    'yoMoments.replyToComment': 'Balas',
    'Listening progress': 'Progres mendengarkan',
    'Skip back 15 seconds': 'Mundur 15 detik',
    'Skip forward 15 seconds': 'Maju 15 detik',
    'Next Moments': 'Moments berikutnya',
    'Show more replies': 'Tampilkan lebih banyak balasan',
    'You can no longer reply.': 'Kamu tidak bisa membalas lagi.',
    'Could not load more replies. Try again.':
        'Tidak bisa memuat balasan lain. Coba lagi.',
    '{position} of {total}': '{position} dari {total}',
    'Play voice reply from {name}, {duration}':
        'Putar balasan suara dari {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Jeda balasan suara dari {name}, {duration}',
    'Now playing: {caption}': 'Sedang diputar: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Buka Voice Moment: {caption}, {author}',
  },
  'vi': {
    'yoMoments.play': 'Phát',
    'yoMoments.pause': 'Tạm dừng',
    'yoMoments.loading': 'Đang tải',
    'yoMoments.conversation': 'Cuộc trò chuyện',
    'yoMoments.replyToComment': 'Trả lời',
    'Listening progress': 'Tiến độ nghe',
    'Skip back 15 seconds': 'Lùi 15 giây',
    'Skip forward 15 seconds': 'Tiến 15 giây',
    'Next Moments': 'Moments tiếp theo',
    'Show more replies': 'Xem thêm phản hồi',
    'You can no longer reply.': 'Bạn không thể trả lời nữa.',
    'Could not load more replies. Try again.':
        'Không tải được thêm phản hồi. Hãy thử lại.',
    '{position} of {total}': '{position} trên {total}',
    'Play voice reply from {name}, {duration}':
        'Phát phản hồi bằng giọng nói của {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Tạm dừng phản hồi bằng giọng nói của {name}, {duration}',
    'Now playing: {caption}': 'Đang phát: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Mở Voice Moment: {caption}, {author}',
  },
  'zh_CN': {
    'yoMoments.play': '播放',
    'yoMoments.pause': '暂停',
    'yoMoments.loading': '加载中',
    'yoMoments.conversation': '对话',
    'yoMoments.replyToComment': '回复',
    'Listening progress': '收听进度',
    'Skip back 15 seconds': '后退 15 秒',
    'Skip forward 15 seconds': '前进 15 秒',
    'Next Moments': '接下来的 Moments',
    'Show more replies': '显示更多回复',
    'You can no longer reply.': '已无法回复。',
    'Could not load more replies. Try again.': '无法加载更多回复。请重试。',
    '{position} of {total}': '{position} / {total}',
    'Play voice reply from {name}, {duration}': '播放 {name} 的语音回复，{duration}',
    'Pause voice reply from {name}, {duration}': '暂停 {name} 的语音回复，{duration}',
    'Now playing: {caption}': '正在播放：{caption}',
    'Open Voice Moment: {caption}, {author}': '打开 Voice Moment：{caption}，{author}',
  },
  'zh_TW': {
    'yoMoments.play': '播放',
    'yoMoments.pause': '暫停',
    'yoMoments.loading': '載入中',
    'yoMoments.conversation': '對話',
    'yoMoments.replyToComment': '回覆',
    'Listening progress': '收聽進度',
    'Skip back 15 seconds': '倒退 15 秒',
    'Skip forward 15 seconds': '快轉 15 秒',
    'Next Moments': '接下來的 Moments',
    'Show more replies': '顯示更多回覆',
    'You can no longer reply.': '已無法回覆。',
    'Could not load more replies. Try again.': '無法載入更多回覆。請再試一次。',
    '{position} of {total}': '{position} / {total}',
    'Play voice reply from {name}, {duration}': '播放 {name} 的語音回覆，{duration}',
    'Pause voice reply from {name}, {duration}': '暫停 {name} 的語音回覆，{duration}',
    'Now playing: {caption}': '正在播放：{caption}',
    'Open Voice Moment: {caption}, {author}': '開啟 Voice Moment：{caption}，{author}',
  },
  'ja': {
    'yoMoments.play': '再生',
    'yoMoments.pause': '一時停止',
    'yoMoments.loading': '読み込み中',
    'yoMoments.conversation': '会話',
    'yoMoments.replyToComment': '返信',
    'Listening progress': '再生の進行状況',
    'Skip back 15 seconds': '15秒戻る',
    'Skip forward 15 seconds': '15秒進む',
    'Next Moments': '次の Moments',
    'Show more replies': '返信をもっと見る',
    'You can no longer reply.': 'もう返信できません。',
    'Could not load more replies. Try again.': '返信を読み込めませんでした。もう一度お試しください。',
    '{position} of {total}': '{total} 中 {position}',
    'Play voice reply from {name}, {duration}': '{name} の音声返信を再生、{duration}',
    'Pause voice reply from {name}, {duration}': '{name} の音声返信を一時停止、{duration}',
    'Now playing: {caption}': '再生中：{caption}',
    'Open Voice Moment: {caption}, {author}': 'Voice Moment を開く：{caption}、{author}',
  },
  'ko': {
    'yoMoments.play': '재생',
    'yoMoments.pause': '일시정지',
    'yoMoments.loading': '불러오는 중',
    'yoMoments.conversation': '대화',
    'yoMoments.replyToComment': '답글',
    'Listening progress': '청취 진행도',
    'Skip back 15 seconds': '15초 뒤로',
    'Skip forward 15 seconds': '15초 앞으로',
    'Next Moments': '다음 Moments',
    'Show more replies': '답글 더 보기',
    'You can no longer reply.': '더 이상 답글을 쓸 수 없습니다.',
    'Could not load more replies. Try again.': '답글을 더 불러오지 못했습니다. 다시 시도해 주세요.',
    '{position} of {total}': '{total} 중 {position}',
    'Play voice reply from {name}, {duration}': '{name}의 음성 답글 재생, {duration}',
    'Pause voice reply from {name}, {duration}': '{name}의 음성 답글 일시정지, {duration}',
    'Now playing: {caption}': '재생 중: {caption}',
    'Open Voice Moment: {caption}, {author}': 'Voice Moment 열기: {caption}, {author}',
  },
  'ar': {
    'yoMoments.play': 'تشغيل',
    'yoMoments.pause': 'إيقاف مؤقت',
    'yoMoments.loading': 'جارٍ التحميل',
    'yoMoments.conversation': 'محادثة',
    'yoMoments.replyToComment': 'رد',
    'Listening progress': 'تقدّم الاستماع',
    'Skip back 15 seconds': 'رجوع 15 ثانية',
    'Skip forward 15 seconds': 'تقديم 15 ثانية',
    'Next Moments': 'لحظات Moments التالية',
    'Show more replies': 'عرض المزيد من الردود',
    'You can no longer reply.': 'لم يعد بإمكانك الرد.',
    'Could not load more replies. Try again.':
        'تعذّر تحميل المزيد من الردود. حاول مرة أخرى.',
    '{position} of {total}': '{position} من {total}',
    'Play voice reply from {name}, {duration}':
        'تشغيل الرد الصوتي من {name}، {duration}',
    'Pause voice reply from {name}, {duration}':
        'إيقاف الرد الصوتي من {name} مؤقتًا، {duration}',
    'Now playing: {caption}': 'قيد التشغيل: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'فتح Voice Moment: {caption}، {author}',
  },
  'hi': {
    'yoMoments.play': 'चलाएँ',
    'yoMoments.pause': 'रोकें',
    'yoMoments.loading': 'लोड हो रहा है',
    'yoMoments.conversation': 'बातचीत',
    'yoMoments.replyToComment': 'जवाब दें',
    'Listening progress': 'सुनने की प्रगति',
    'Skip back 15 seconds': '15 सेकंड पीछे',
    'Skip forward 15 seconds': '15 सेकंड आगे',
    'Next Moments': 'अगले Moments',
    'Show more replies': 'और जवाब दिखाएँ',
    'You can no longer reply.': 'अब आप जवाब नहीं दे सकते।',
    'Could not load more replies. Try again.':
        'और जवाब लोड नहीं हो सके। फिर कोशिश करें।',
    '{position} of {total}': '{total} में से {position}',
    'Play voice reply from {name}, {duration}':
        '{name} का वॉइस जवाब चलाएँ, {duration}',
    'Pause voice reply from {name}, {duration}':
        '{name} का वॉइस जवाब रोकें, {duration}',
    'Now playing: {caption}': 'अभी चल रहा है: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment खोलें: {caption}, {author}',
  },
  'bn': {
    'yoMoments.play': 'চালান',
    'yoMoments.pause': 'বিরতি',
    'yoMoments.loading': 'লোড হচ্ছে',
    'yoMoments.conversation': 'কথোপকথন',
    'yoMoments.replyToComment': 'উত্তর দিন',
    'Listening progress': 'শোনার অগ্রগতি',
    'Skip back 15 seconds': '১৫ সেকেন্ড পিছনে',
    'Skip forward 15 seconds': '১৫ সেকেন্ড সামনে',
    'Next Moments': 'পরবর্তী Moments',
    'Show more replies': 'আরও উত্তর দেখুন',
    'You can no longer reply.': 'আপনি আর উত্তর দিতে পারবেন না।',
    'Could not load more replies. Try again.':
        'আরও উত্তর লোড করা যায়নি। আবার চেষ্টা করুন।',
    '{position} of {total}': '{total}-এর {position}',
    'Play voice reply from {name}, {duration}':
        '{name}-এর ভয়েস উত্তর চালান, {duration}',
    'Pause voice reply from {name}, {duration}':
        '{name}-এর ভয়েস উত্তর থামান, {duration}',
    'Now playing: {caption}': 'এখন বাজছে: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment খুলুন: {caption}, {author}',
  },
  'ur': {
    'yoMoments.play': 'چلائیں',
    'yoMoments.pause': 'وقفہ',
    'yoMoments.loading': 'لوڈ ہو رہا ہے',
    'yoMoments.conversation': 'گفتگو',
    'yoMoments.replyToComment': 'جواب دیں',
    'Listening progress': 'سننے کی پیش رفت',
    'Skip back 15 seconds': '15 سیکنڈ پیچھے',
    'Skip forward 15 seconds': '15 سیکنڈ آگے',
    'Next Moments': 'اگلے Moments',
    'Show more replies': 'مزید جوابات دکھائیں',
    'You can no longer reply.': 'اب آپ جواب نہیں دے سکتے۔',
    'Could not load more replies. Try again.':
        'مزید جوابات لوڈ نہیں ہو سکے۔ دوبارہ کوشش کریں۔',
    '{position} of {total}': '{total} میں سے {position}',
    'Play voice reply from {name}, {duration}':
        '{name} کا صوتی جواب چلائیں، {duration}',
    'Pause voice reply from {name}, {duration}':
        '{name} کا صوتی جواب روکیں، {duration}',
    'Now playing: {caption}': 'ابھی چل رہا ہے: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Voice Moment کھولیں: {caption}، {author}',
  },
  'th': {
    'yoMoments.play': 'เล่น',
    'yoMoments.pause': 'หยุดชั่วคราว',
    'yoMoments.loading': 'กำลังโหลด',
    'yoMoments.conversation': 'บทสนทนา',
    'yoMoments.replyToComment': 'ตอบกลับ',
    'Listening progress': 'ความคืบหน้าการฟัง',
    'Skip back 15 seconds': 'ย้อนกลับ 15 วินาที',
    'Skip forward 15 seconds': 'ข้ามไป 15 วินาที',
    'Next Moments': 'Moments ถัดไป',
    'Show more replies': 'ดูการตอบกลับเพิ่มเติม',
    'You can no longer reply.': 'คุณไม่สามารถตอบกลับได้อีกแล้ว',
    'Could not load more replies. Try again.':
        'โหลดการตอบกลับเพิ่มเติมไม่สำเร็จ ลองอีกครั้ง',
    '{position} of {total}': '{position} จาก {total}',
    'Play voice reply from {name}, {duration}':
        'เล่นเสียงตอบกลับจาก {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'หยุดเสียงตอบกลับจาก {name} ชั่วคราว, {duration}',
    'Now playing: {caption}': 'กำลังเล่น: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'เปิด Voice Moment: {caption}, {author}',
  },
  'ms': {
    'yoMoments.play': 'Main',
    'yoMoments.pause': 'Jeda',
    'yoMoments.loading': 'Memuatkan',
    'yoMoments.conversation': 'Perbualan',
    'yoMoments.replyToComment': 'Balas',
    'Listening progress': 'Kemajuan mendengar',
    'Skip back 15 seconds': 'Undur 15 saat',
    'Skip forward 15 seconds': 'Maju 15 saat',
    'Next Moments': 'Moments seterusnya',
    'Show more replies': 'Tunjukkan lagi balasan',
    'You can no longer reply.': 'Anda tidak boleh membalas lagi.',
    'Could not load more replies. Try again.':
        'Tidak dapat memuatkan lagi balasan. Cuba lagi.',
    '{position} of {total}': '{position} daripada {total}',
    'Play voice reply from {name}, {duration}':
        'Main balasan suara daripada {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Jeda balasan suara daripada {name}, {duration}',
    'Now playing: {caption}': 'Sedang dimainkan: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Buka Voice Moment: {caption}, {author}',
  },
  'fil': {
    'yoMoments.play': 'I-play',
    'yoMoments.pause': 'I-pause',
    'yoMoments.loading': 'Naglo-load',
    'yoMoments.conversation': 'Usapan',
    'yoMoments.replyToComment': 'Sumagot',
    'Listening progress': 'Progreso ng pakikinig',
    'Skip back 15 seconds': 'Bumalik ng 15 segundo',
    'Skip forward 15 seconds': 'Sumulong ng 15 segundo',
    'Next Moments': 'Susunod na Moments',
    'Show more replies': 'Magpakita ng iba pang sagot',
    'You can no longer reply.': 'Hindi ka na puwedeng sumagot.',
    'Could not load more replies. Try again.':
        'Hindi na-load ang iba pang sagot. Subukan ulit.',
    '{position} of {total}': '{position} ng {total}',
    'Play voice reply from {name}, {duration}':
        'I-play ang voice reply ni {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'I-pause ang voice reply ni {name}, {duration}',
    'Now playing: {caption}': 'Pinapatugtog ngayon: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Buksan ang Voice Moment: {caption}, {author}',
  },
  'he': {
    'yoMoments.play': 'הפעלה',
    'yoMoments.pause': 'השהיה',
    'yoMoments.loading': 'טוען',
    'yoMoments.conversation': 'שיחה',
    'yoMoments.replyToComment': 'תגובה',
    'Listening progress': 'התקדמות ההאזנה',
    'Skip back 15 seconds': 'אחורה 15 שניות',
    'Skip forward 15 seconds': 'קדימה 15 שניות',
    'Next Moments': 'ה-Moments הבאים',
    'Show more replies': 'הצגת תגובות נוספות',
    'You can no longer reply.': 'אי אפשר יותר להגיב.',
    'Could not load more replies. Try again.':
        'לא ניתן היה לטעון תגובות נוספות. נסה שוב.',
    '{position} of {total}': '{position} מתוך {total}',
    'Play voice reply from {name}, {duration}':
        'הפעלת תגובה קולית של {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'השהיית תגובה קולית של {name}, {duration}',
    'Now playing: {caption}': 'מתנגן עכשיו: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'פתיחת Voice Moment: {caption}, {author}',
  },
  'fa': {
    'yoMoments.play': 'پخش',
    'yoMoments.pause': 'مکث',
    'yoMoments.loading': 'در حال بارگذاری',
    'yoMoments.conversation': 'گفت‌وگو',
    'yoMoments.replyToComment': 'پاسخ',
    'Listening progress': 'پیشرفت شنیدن',
    'Skip back 15 seconds': '۱۵ ثانیه به عقب',
    'Skip forward 15 seconds': '۱۵ ثانیه به جلو',
    'Next Moments': 'Moments بعدی',
    'Show more replies': 'نمایش پاسخ‌های بیشتر',
    'You can no longer reply.': 'دیگر نمی‌توانی پاسخ دهی.',
    'Could not load more replies. Try again.':
        'پاسخ‌های بیشتر بارگذاری نشد. دوباره تلاش کن.',
    '{position} of {total}': '{position} از {total}',
    'Play voice reply from {name}, {duration}':
        'پخش پاسخ صوتی {name}، {duration}',
    'Pause voice reply from {name}, {duration}':
        'مکث پاسخ صوتی {name}، {duration}',
    'Now playing: {caption}': 'در حال پخش: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'باز کردن Voice Moment: {caption}، {author}',
  },
  'sw': {
    'yoMoments.play': 'Cheza',
    'yoMoments.pause': 'Sitisha',
    'yoMoments.loading': 'Inapakia',
    'yoMoments.conversation': 'Mazungumzo',
    'yoMoments.replyToComment': 'Jibu',
    'Listening progress': 'Maendeleo ya kusikiliza',
    'Skip back 15 seconds': 'Rudi sekunde 15',
    'Skip forward 15 seconds': 'Sogea mbele sekunde 15',
    'Next Moments': 'Moments zinazofuata',
    'Show more replies': 'Onyesha majibu zaidi',
    'You can no longer reply.': 'Huwezi kujibu tena.',
    'Could not load more replies. Try again.':
        'Imeshindwa kupakia majibu zaidi. Jaribu tena.',
    '{position} of {total}': '{position} kati ya {total}',
    'Play voice reply from {name}, {duration}':
        'Cheza jibu la sauti la {name}, {duration}',
    'Pause voice reply from {name}, {duration}':
        'Sitisha jibu la sauti la {name}, {duration}',
    'Now playing: {caption}': 'Inachezwa sasa: {caption}',
    'Open Voice Moment: {caption}, {author}':
        'Fungua Voice Moment: {caption}, {author}',
  },
};
