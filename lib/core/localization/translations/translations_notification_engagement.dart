/// Copy introduced by the comment, @mention, Server event reminder and
/// Server role notifications (ADR-212).
///
/// Every string here is a notification title the bell renders, or a label in
/// the notification preferences screen. "Moment" and "Yeel" are product
/// names and stay untranslated inside a sentence; the plural group heading
/// is localized where a language inflects it naturally.
///
/// Every selectable locale receives an explicit translation.
const notificationEngagementTranslationKeys = <String>[
  '{actor} commented on your Moment',
  '{actor} commented on your Yeel',
  '{actor} mentioned you in a comment',
  'Starting soon: {label}',
  'An event is starting soon',
  '{actor} promoted you in {label}',
  '{actor} promoted you in a server',
  'Moments & Yeels',
  'Comments and mentions',
  'Server events',
  'Your server role',
];

const notificationEngagementTranslations = <String, Map<String, String>>{
  'de': {
    '{actor} commented on your Moment':
        '{actor} hat deinen Moment kommentiert',
    '{actor} commented on your Yeel':
        '{actor} hat dein Yeel kommentiert',
    '{actor} mentioned you in a comment':
        '{actor} hat dich in einem Kommentar erwähnt',
    'Starting soon: {label}':
        'Beginnt bald: {label}',
    'An event is starting soon':
        'Ein Termin beginnt bald',
    '{actor} promoted you in {label}':
        '{actor} hat dich auf {label} befördert',
    '{actor} promoted you in a server':
        '{actor} hat dich auf einem Server befördert',
    'Moments & Yeels':
        'Momente & Yeels',
    'Comments and mentions':
        'Kommentare und Erwähnungen',
    'Server events':
        'Server-Termine',
    'Your server role':
        'Deine Server-Rolle',
  },
  'es': {
    '{actor} commented on your Moment':
        '{actor} ha comentado tu Moment',
    '{actor} commented on your Yeel':
        '{actor} ha comentado tu Yeel',
    '{actor} mentioned you in a comment':
        '{actor} te ha mencionado en un comentario',
    'Starting soon: {label}':
        'Empieza pronto: {label}',
    'An event is starting soon':
        'Un evento empieza pronto',
    '{actor} promoted you in {label}':
        '{actor} te ha ascendido en {label}',
    '{actor} promoted you in a server':
        '{actor} te ha ascendido en un servidor',
    'Moments & Yeels':
        'Moments y Yeels',
    'Comments and mentions':
        'Comentarios y menciones',
    'Server events':
        'Eventos del servidor',
    'Your server role':
        'Tu rol en el servidor',
  },
  'pt': {
    '{actor} commented on your Moment':
        '{actor} comentou o teu Moment',
    '{actor} commented on your Yeel':
        '{actor} comentou o teu Yeel',
    '{actor} mentioned you in a comment':
        '{actor} mencionou-te num comentário',
    'Starting soon: {label}':
        'Começa em breve: {label}',
    'An event is starting soon':
        'Um evento começa em breve',
    '{actor} promoted you in {label}':
        '{actor} promoveu-te em {label}',
    '{actor} promoted you in a server':
        '{actor} promoveu-te num servidor',
    'Moments & Yeels':
        'Moments e Yeels',
    'Comments and mentions':
        'Comentários e menções',
    'Server events':
        'Eventos do servidor',
    'Your server role':
        'O teu cargo no servidor',
  },
  'pt_BR': {
    '{actor} commented on your Moment':
        '{actor} comentou no seu Moment',
    '{actor} commented on your Yeel':
        '{actor} comentou no seu Yeel',
    '{actor} mentioned you in a comment':
        '{actor} mencionou você em um comentário',
    'Starting soon: {label}':
        'Começa em breve: {label}',
    'An event is starting soon':
        'Um evento começa em breve',
    '{actor} promoted you in {label}':
        '{actor} promoveu você em {label}',
    '{actor} promoted you in a server':
        '{actor} promoveu você em um servidor',
    'Moments & Yeels':
        'Moments e Yeels',
    'Comments and mentions':
        'Comentários e menções',
    'Server events':
        'Eventos do servidor',
    'Your server role':
        'Seu cargo no servidor',
  },
  'fr': {
    '{actor} commented on your Moment':
        '{actor} a commenté ton Moment',
    '{actor} commented on your Yeel':
        '{actor} a commenté ton Yeel',
    '{actor} mentioned you in a comment':
        '{actor} t\'a mentionné dans un commentaire',
    'Starting soon: {label}':
        'Bientôt : {label}',
    'An event is starting soon':
        'Un événement commence bientôt',
    '{actor} promoted you in {label}':
        '{actor} t\'a promu sur {label}',
    '{actor} promoted you in a server':
        '{actor} t\'a promu sur un serveur',
    'Moments & Yeels':
        'Moments et Yeels',
    'Comments and mentions':
        'Commentaires et mentions',
    'Server events':
        'Événements des serveurs',
    'Your server role':
        'Ton rôle sur le serveur',
  },
  'it': {
    '{actor} commented on your Moment':
        '{actor} ha commentato il tuo Moment',
    '{actor} commented on your Yeel':
        '{actor} ha commentato il tuo Yeel',
    '{actor} mentioned you in a comment':
        '{actor} ti ha menzionato in un commento',
    'Starting soon: {label}':
        'Inizia presto: {label}',
    'An event is starting soon':
        'Un evento sta per iniziare',
    '{actor} promoted you in {label}':
        '{actor} ti ha promosso in {label}',
    '{actor} promoted you in a server':
        '{actor} ti ha promosso in un server',
    'Moments & Yeels':
        'Moments e Yeels',
    'Comments and mentions':
        'Commenti e menzioni',
    'Server events':
        'Eventi dei server',
    'Your server role':
        'Il tuo ruolo nel server',
  },
  'uk': {
    '{actor} commented on your Moment':
        '{actor} прокоментував ваш Moment',
    '{actor} commented on your Yeel':
        '{actor} прокоментував ваш Yeel',
    '{actor} mentioned you in a comment':
        '{actor} згадав вас у коментарі',
    'Starting soon: {label}':
        'Скоро початок: {label}',
    'An event is starting soon':
        'Подія незабаром почнеться',
    '{actor} promoted you in {label}':
        '{actor} підвищив вас на сервері {label}',
    '{actor} promoted you in a server':
        '{actor} підвищив вас на сервері',
    'Moments & Yeels':
        'Moments і Yeels',
    'Comments and mentions':
        'Коментарі та згадки',
    'Server events':
        'Події на серверах',
    'Your server role':
        'Ваша роль на сервері',
  },
  'ru': {
    '{actor} commented on your Moment':
        '{actor} прокомментировал ваш Moment',
    '{actor} commented on your Yeel':
        '{actor} прокомментировал ваш Yeel',
    '{actor} mentioned you in a comment':
        '{actor} упомянул вас в комментарии',
    'Starting soon: {label}':
        'Скоро начало: {label}',
    'An event is starting soon':
        'Событие скоро начнётся',
    '{actor} promoted you in {label}':
        '{actor} повысил вас на сервере {label}',
    '{actor} promoted you in a server':
        '{actor} повысил вас на сервере',
    'Moments & Yeels':
        'Moments и Yeels',
    'Comments and mentions':
        'Комментарии и упоминания',
    'Server events':
        'События на серверах',
    'Your server role':
        'Ваша роль на сервере',
  },
  'cs': {
    '{actor} commented on your Moment':
        '{actor} okomentoval tvůj Moment',
    '{actor} commented on your Yeel':
        '{actor} okomentoval tvůj Yeel',
    '{actor} mentioned you in a comment':
        '{actor} tě zmínil v komentáři',
    'Starting soon: {label}':
        'Brzy začíná: {label}',
    'An event is starting soon':
        'Událost brzy začne',
    '{actor} promoted you in {label}':
        '{actor} tě povýšil na serveru {label}',
    '{actor} promoted you in a server':
        '{actor} tě povýšil na serveru',
    'Moments & Yeels':
        'Momenty a Yeely',
    'Comments and mentions':
        'Komentáře a zmínky',
    'Server events':
        'Události na serverech',
    'Your server role':
        'Tvoje role na serveru',
  },
  'sk': {
    '{actor} commented on your Moment':
        '{actor} okomentoval tvoj Moment',
    '{actor} commented on your Yeel':
        '{actor} okomentoval tvoj Yeel',
    '{actor} mentioned you in a comment':
        '{actor} ťa spomenul v komentári',
    'Starting soon: {label}':
        'Čoskoro začína: {label}',
    'An event is starting soon':
        'Udalosť čoskoro začne',
    '{actor} promoted you in {label}':
        '{actor} ťa povýšil na serveri {label}',
    '{actor} promoted you in a server':
        '{actor} ťa povýšil na serveri',
    'Moments & Yeels':
        'Momenty a Yeely',
    'Comments and mentions':
        'Komentáre a zmienky',
    'Server events':
        'Udalosti na serveroch',
    'Your server role':
        'Tvoja rola na serveri',
  },
  'bg': {
    '{actor} commented on your Moment':
        '{actor} коментира твоя Moment',
    '{actor} commented on your Yeel':
        '{actor} коментира твоя Yeel',
    '{actor} mentioned you in a comment':
        '{actor} те спомена в коментар',
    'Starting soon: {label}':
        'Започва скоро: {label}',
    'An event is starting soon':
        'Събитие започва скоро',
    '{actor} promoted you in {label}':
        '{actor} те повиши в {label}',
    '{actor} promoted you in a server':
        '{actor} те повиши в сървър',
    'Moments & Yeels':
        'Moments и Yeels',
    'Comments and mentions':
        'Коментари и споменавания',
    'Server events':
        'Събития в сървърите',
    'Your server role':
        'Твоята роля в сървъра',
  },
  'nl': {
    '{actor} commented on your Moment':
        '{actor} heeft op je Moment gereageerd',
    '{actor} commented on your Yeel':
        '{actor} heeft op je Yeel gereageerd',
    '{actor} mentioned you in a comment':
        '{actor} heeft je genoemd in een reactie',
    'Starting soon: {label}':
        'Begint binnenkort: {label}',
    'An event is starting soon':
        'Een evenement begint binnenkort',
    '{actor} promoted you in {label}':
        '{actor} heeft je gepromoveerd in {label}',
    '{actor} promoted you in a server':
        '{actor} heeft je gepromoveerd in een server',
    'Moments & Yeels':
        'Moments en Yeels',
    'Comments and mentions':
        'Reacties en vermeldingen',
    'Server events':
        'Serverevenementen',
    'Your server role':
        'Jouw rol in de server',
  },
  'ro': {
    '{actor} commented on your Moment':
        '{actor} a comentat la Momentul tău',
    '{actor} commented on your Yeel':
        '{actor} a comentat la Yeel-ul tău',
    '{actor} mentioned you in a comment':
        '{actor} te-a menționat într-un comentariu',
    'Starting soon: {label}':
        'Începe curând: {label}',
    'An event is starting soon':
        'Un eveniment începe curând',
    '{actor} promoted you in {label}':
        '{actor} te-a promovat în {label}',
    '{actor} promoted you in a server':
        '{actor} te-a promovat într-un server',
    'Moments & Yeels':
        'Moments și Yeels',
    'Comments and mentions':
        'Comentarii și mențiuni',
    'Server events':
        'Evenimente din servere',
    'Your server role':
        'Rolul tău în server',
  },
  'tr': {
    '{actor} commented on your Moment':
        '{actor} Moment\'ine yorum yaptı',
    '{actor} commented on your Yeel':
        '{actor} Yeel\'ine yorum yaptı',
    '{actor} mentioned you in a comment':
        '{actor} bir yorumda senden bahsetti',
    'Starting soon: {label}':
        'Yakında başlıyor: {label}',
    'An event is starting soon':
        'Bir etkinlik yakında başlıyor',
    '{actor} promoted you in {label}':
        '{actor} seni {label} sunucusunda terfi ettirdi',
    '{actor} promoted you in a server':
        '{actor} seni bir sunucuda terfi ettirdi',
    'Moments & Yeels':
        'Moments ve Yeels',
    'Comments and mentions':
        'Yorumlar ve bahsetmeler',
    'Server events':
        'Sunucu etkinlikleri',
    'Your server role':
        'Sunucudaki rolün',
  },
  'el': {
    '{actor} commented on your Moment':
        'Ο/Η {actor} σχολίασε το Moment σου',
    '{actor} commented on your Yeel':
        'Ο/Η {actor} σχολίασε το Yeel σου',
    '{actor} mentioned you in a comment':
        'Ο/Η {actor} σε ανέφερε σε ένα σχόλιο',
    'Starting soon: {label}':
        'Ξεκινά σύντομα: {label}',
    'An event is starting soon':
        'Μια εκδήλωση ξεκινά σύντομα',
    '{actor} promoted you in {label}':
        'Ο/Η {actor} σε προήγαγε στο {label}',
    '{actor} promoted you in a server':
        'Ο/Η {actor} σε προήγαγε σε έναν διακομιστή',
    'Moments & Yeels':
        'Moments και Yeels',
    'Comments and mentions':
        'Σχόλια και αναφορές',
    'Server events':
        'Εκδηλώσεις διακομιστών',
    'Your server role':
        'Ο ρόλος σου στον διακομιστή',
  },
  'hu': {
    '{actor} commented on your Moment':
        '{actor} hozzászólt a Momentedhez',
    '{actor} commented on your Yeel':
        '{actor} hozzászólt a Yeeledhez',
    '{actor} mentioned you in a comment':
        '{actor} megemlített egy hozzászólásban',
    'Starting soon: {label}':
        'Hamarosan kezdődik: {label}',
    'An event is starting soon':
        'Egy esemény hamarosan kezdődik',
    '{actor} promoted you in {label}':
        '{actor} előléptetett a(z) {label} szerveren',
    '{actor} promoted you in a server':
        '{actor} előléptetett egy szerveren',
    'Moments & Yeels':
        'Momentek és Yeelek',
    'Comments and mentions':
        'Hozzászólások és említések',
    'Server events':
        'Szervereseményok',
    'Your server role':
        'A szerepköröd a szerveren',
  },
  'hr': {
    '{actor} commented on your Moment':
        '{actor} je komentirao tvoj Moment',
    '{actor} commented on your Yeel':
        '{actor} je komentirao tvoj Yeel',
    '{actor} mentioned you in a comment':
        '{actor} te spomenuo u komentaru',
    'Starting soon: {label}':
        'Uskoro počinje: {label}',
    'An event is starting soon':
        'Događaj uskoro počinje',
    '{actor} promoted you in {label}':
        '{actor} te promaknuo na serveru {label}',
    '{actor} promoted you in a server':
        '{actor} te promaknuo na serveru',
    'Moments & Yeels':
        'Momenti i Yeeli',
    'Comments and mentions':
        'Komentari i spominjanja',
    'Server events':
        'Događaji na serverima',
    'Your server role':
        'Tvoja uloga na serveru',
  },
  'sr': {
    '{actor} commented on your Moment':
        '{actor} је коментарисао твој Moment',
    '{actor} commented on your Yeel':
        '{actor} је коментарисао твој Yeel',
    '{actor} mentioned you in a comment':
        '{actor} те је споменуо у коментару',
    'Starting soon: {label}':
        'Ускоро почиње: {label}',
    'An event is starting soon':
        'Догађај ускоро почиње',
    '{actor} promoted you in {label}':
        '{actor} те је унапредио на серверу {label}',
    '{actor} promoted you in a server':
        '{actor} те је унапредио на серверу',
    'Moments & Yeels':
        'Moments и Yeels',
    'Comments and mentions':
        'Коментари и помињања',
    'Server events':
        'Догађаји на серверима',
    'Your server role':
        'Твоја улога на серверу',
  },
  'sv': {
    '{actor} commented on your Moment':
        '{actor} kommenterade ditt Moment',
    '{actor} commented on your Yeel':
        '{actor} kommenterade ditt Yeel',
    '{actor} mentioned you in a comment':
        '{actor} nämnde dig i en kommentar',
    'Starting soon: {label}':
        'Börjar snart: {label}',
    'An event is starting soon':
        'Ett evenemang börjar snart',
    '{actor} promoted you in {label}':
        '{actor} befordrade dig i {label}',
    '{actor} promoted you in a server':
        '{actor} befordrade dig i en server',
    'Moments & Yeels':
        'Moments och Yeels',
    'Comments and mentions':
        'Kommentarer och omnämnanden',
    'Server events':
        'Serverevenemang',
    'Your server role':
        'Din roll i servern',
  },
  'da': {
    '{actor} commented on your Moment':
        '{actor} kommenterede dit Moment',
    '{actor} commented on your Yeel':
        '{actor} kommenterede dit Yeel',
    '{actor} mentioned you in a comment':
        '{actor} nævnte dig i en kommentar',
    'Starting soon: {label}':
        'Starter snart: {label}',
    'An event is starting soon':
        'En begivenhed starter snart',
    '{actor} promoted you in {label}':
        '{actor} forfremmede dig i {label}',
    '{actor} promoted you in a server':
        '{actor} forfremmede dig i en server',
    'Moments & Yeels':
        'Moments og Yeels',
    'Comments and mentions':
        'Kommentarer og omtaler',
    'Server events':
        'Serverbegivenheder',
    'Your server role':
        'Din rolle i serveren',
  },
  'nb': {
    '{actor} commented on your Moment':
        '{actor} kommenterte Momentet ditt',
    '{actor} commented on your Yeel':
        '{actor} kommenterte Yeelen din',
    '{actor} mentioned you in a comment':
        '{actor} nevnte deg i en kommentar',
    'Starting soon: {label}':
        'Starter snart: {label}',
    'An event is starting soon':
        'En hendelse starter snart',
    '{actor} promoted you in {label}':
        '{actor} forfremmet deg i {label}',
    '{actor} promoted you in a server':
        '{actor} forfremmet deg i en server',
    'Moments & Yeels':
        'Moments og Yeels',
    'Comments and mentions':
        'Kommentarer og omtaler',
    'Server events':
        'Serverhendelser',
    'Your server role':
        'Rollen din i serveren',
  },
  'fi': {
    '{actor} commented on your Moment':
        '{actor} kommentoi Momenttiasi',
    '{actor} commented on your Yeel':
        '{actor} kommentoi Yeeliäsi',
    '{actor} mentioned you in a comment':
        '{actor} mainitsi sinut kommentissa',
    'Starting soon: {label}':
        'Alkaa pian: {label}',
    'An event is starting soon':
        'Tapahtuma alkaa pian',
    '{actor} promoted you in {label}':
        '{actor} ylensi sinut palvelimella {label}',
    '{actor} promoted you in a server':
        '{actor} ylensi sinut palvelimella',
    'Moments & Yeels':
        'Momentit ja Yeelit',
    'Comments and mentions':
        'Kommentit ja maininnat',
    'Server events':
        'Palvelintapahtumat',
    'Your server role':
        'Roolisi palvelimella',
  },
  'lt': {
    '{actor} commented on your Moment':
        '{actor} pakomentavo tavo Moment',
    '{actor} commented on your Yeel':
        '{actor} pakomentavo tavo Yeel',
    '{actor} mentioned you in a comment':
        '{actor} paminėjo tave komentare',
    'Starting soon: {label}':
        'Netrukus prasideda: {label}',
    'An event is starting soon':
        'Renginys netrukus prasidės',
    '{actor} promoted you in {label}':
        '{actor} paaukštino tave serveryje {label}',
    '{actor} promoted you in a server':
        '{actor} paaukštino tave serveryje',
    'Moments & Yeels':
        'Moments ir Yeels',
    'Comments and mentions':
        'Komentarai ir paminėjimai',
    'Server events':
        'Serverių renginiai',
    'Your server role':
        'Tavo vaidmuo serveryje',
  },
  'lv': {
    '{actor} commented on your Moment':
        '{actor} komentēja tavu Moment',
    '{actor} commented on your Yeel':
        '{actor} komentēja tavu Yeel',
    '{actor} mentioned you in a comment':
        '{actor} pieminēja tevi komentārā',
    'Starting soon: {label}':
        'Drīz sākas: {label}',
    'An event is starting soon':
        'Pasākums drīz sāksies',
    '{actor} promoted you in {label}':
        '{actor} paaugstināja tevi serverī {label}',
    '{actor} promoted you in a server':
        '{actor} paaugstināja tevi serverī',
    'Moments & Yeels':
        'Moments un Yeels',
    'Comments and mentions':
        'Komentāri un pieminējumi',
    'Server events':
        'Serveru pasākumi',
    'Your server role':
        'Tava loma serverī',
  },
  'et': {
    '{actor} commented on your Moment':
        '{actor} kommenteeris sinu Momenti',
    '{actor} commented on your Yeel':
        '{actor} kommenteeris sinu Yeeli',
    '{actor} mentioned you in a comment':
        '{actor} mainis sind kommentaaris',
    'Starting soon: {label}':
        'Algab varsti: {label}',
    'An event is starting soon':
        'Sündmus algab varsti',
    '{actor} promoted you in {label}':
        '{actor} ülendas sind serveris {label}',
    '{actor} promoted you in a server':
        '{actor} ülendas sind serveris',
    'Moments & Yeels':
        'Momentid ja Yeelid',
    'Comments and mentions':
        'Kommentaarid ja mainimised',
    'Server events':
        'Serverite sündmused',
    'Your server role':
        'Sinu roll serveris',
  },
  'id': {
    '{actor} commented on your Moment':
        '{actor} mengomentari Moment kamu',
    '{actor} commented on your Yeel':
        '{actor} mengomentari Yeel kamu',
    '{actor} mentioned you in a comment':
        '{actor} menyebut kamu di sebuah komentar',
    'Starting soon: {label}':
        'Segera dimulai: {label}',
    'An event is starting soon':
        'Sebuah acara segera dimulai',
    '{actor} promoted you in {label}':
        '{actor} mempromosikan kamu di {label}',
    '{actor} promoted you in a server':
        '{actor} mempromosikan kamu di sebuah server',
    'Moments & Yeels':
        'Moments dan Yeels',
    'Comments and mentions':
        'Komentar dan sebutan',
    'Server events':
        'Acara server',
    'Your server role':
        'Peran kamu di server',
  },
  'vi': {
    '{actor} commented on your Moment':
        '{actor} đã bình luận về Moment của bạn',
    '{actor} commented on your Yeel':
        '{actor} đã bình luận về Yeel của bạn',
    '{actor} mentioned you in a comment':
        '{actor} đã nhắc đến bạn trong một bình luận',
    'Starting soon: {label}':
        'Sắp bắt đầu: {label}',
    'An event is starting soon':
        'Một sự kiện sắp bắt đầu',
    '{actor} promoted you in {label}':
        '{actor} đã thăng cấp cho bạn trong {label}',
    '{actor} promoted you in a server':
        '{actor} đã thăng cấp cho bạn trong một máy chủ',
    'Moments & Yeels':
        'Moments và Yeels',
    'Comments and mentions':
        'Bình luận và nhắc đến',
    'Server events':
        'Sự kiện máy chủ',
    'Your server role':
        'Vai trò của bạn trong máy chủ',
  },
  'zh_CN': {
    '{actor} commented on your Moment':
        '{actor} 评论了你的 Moment',
    '{actor} commented on your Yeel':
        '{actor} 评论了你的 Yeel',
    '{actor} mentioned you in a comment':
        '{actor} 在评论中提到了你',
    'Starting soon: {label}':
        '即将开始：{label}',
    'An event is starting soon':
        '一个活动即将开始',
    '{actor} promoted you in {label}':
        '{actor} 在 {label} 中提升了你的身份',
    '{actor} promoted you in a server':
        '{actor} 在一个服务器中提升了你的身份',
    'Moments & Yeels':
        'Moments 与 Yeels',
    'Comments and mentions':
        '评论和提及',
    'Server events':
        '服务器活动',
    'Your server role':
        '你在服务器中的身份',
  },
  'zh_TW': {
    '{actor} commented on your Moment':
        '{actor} 留言了你的 Moment',
    '{actor} commented on your Yeel':
        '{actor} 留言了你的 Yeel',
    '{actor} mentioned you in a comment':
        '{actor} 在留言中提到你',
    'Starting soon: {label}':
        '即將開始：{label}',
    'An event is starting soon':
        '活動即將開始',
    '{actor} promoted you in {label}':
        '{actor} 在 {label} 中提升了你的身分',
    '{actor} promoted you in a server':
        '{actor} 在某個伺服器中提升了你的身分',
    'Moments & Yeels':
        'Moments 與 Yeels',
    'Comments and mentions':
        '留言和提及',
    'Server events':
        '伺服器活動',
    'Your server role':
        '你在伺服器中的身分',
  },
  'ja': {
    '{actor} commented on your Moment':
        '{actor} さんがあなたの Moment にコメントしました',
    '{actor} commented on your Yeel':
        '{actor} さんがあなたの Yeel にコメントしました',
    '{actor} mentioned you in a comment':
        '{actor} さんがコメントであなたにメンションしました',
    'Starting soon: {label}':
        'まもなく開始：{label}',
    'An event is starting soon':
        'イベントがまもなく始まります',
    '{actor} promoted you in {label}':
        '{actor} さんが {label} であなたの役割を上げました',
    '{actor} promoted you in a server':
        '{actor} さんがサーバーであなたの役割を上げました',
    'Moments & Yeels':
        'Moments と Yeels',
    'Comments and mentions':
        'コメントとメンション',
    'Server events':
        'サーバーのイベント',
    'Your server role':
        'サーバーでのあなたの役割',
  },
  'ko': {
    '{actor} commented on your Moment':
        '{actor} 님이 회원님의 Moment에 댓글을 남겼습니다',
    '{actor} commented on your Yeel':
        '{actor} 님이 회원님의 Yeel에 댓글을 남겼습니다',
    '{actor} mentioned you in a comment':
        '{actor} 님이 댓글에서 회원님을 언급했습니다',
    'Starting soon: {label}':
        '곧 시작: {label}',
    'An event is starting soon':
        '이벤트가 곧 시작됩니다',
    '{actor} promoted you in {label}':
        '{actor} 님이 {label}에서 회원님의 역할을 올렸습니다',
    '{actor} promoted you in a server':
        '{actor} 님이 서버에서 회원님의 역할을 올렸습니다',
    'Moments & Yeels':
        'Moments 및 Yeels',
    'Comments and mentions':
        '댓글 및 언급',
    'Server events':
        '서버 이벤트',
    'Your server role':
        '서버에서의 내 역할',
  },
  'ar': {
    '{actor} commented on your Moment':
        'علّق {actor} على Moment الخاص بك',
    '{actor} commented on your Yeel':
        'علّق {actor} على Yeel الخاص بك',
    '{actor} mentioned you in a comment':
        'ذكرك {actor} في تعليق',
    'Starting soon: {label}':
        'يبدأ قريبًا: {label}',
    'An event is starting soon':
        'سيبدأ حدث قريبًا',
    '{actor} promoted you in {label}':
        'رقّاك {actor} في {label}',
    '{actor} promoted you in a server':
        'رقّاك {actor} في خادم',
    'Moments & Yeels':
        'Moments وYeels',
    'Comments and mentions':
        'التعليقات والإشارات',
    'Server events':
        'أحداث الخوادم',
    'Your server role':
        'دورك في الخادم',
  },
  'hi': {
    '{actor} commented on your Moment':
        '{actor} ने आपके Moment पर टिप्पणी की',
    '{actor} commented on your Yeel':
        '{actor} ने आपके Yeel पर टिप्पणी की',
    '{actor} mentioned you in a comment':
        '{actor} ने एक टिप्पणी में आपका उल्लेख किया',
    'Starting soon: {label}':
        'जल्द शुरू: {label}',
    'An event is starting soon':
        'एक इवेंट जल्द शुरू हो रहा है',
    '{actor} promoted you in {label}':
        '{actor} ने {label} में आपको पदोन्नत किया',
    '{actor} promoted you in a server':
        '{actor} ने एक सर्वर में आपको पदोन्नत किया',
    'Moments & Yeels':
        'Moments और Yeels',
    'Comments and mentions':
        'टिप्पणियाँ और उल्लेख',
    'Server events':
        'सर्वर इवेंट',
    'Your server role':
        'सर्वर में आपकी भूमिका',
  },
  'bn': {
    '{actor} commented on your Moment':
        '{actor} আপনার Moment-এ মন্তব্য করেছেন',
    '{actor} commented on your Yeel':
        '{actor} আপনার Yeel-এ মন্তব্য করেছেন',
    '{actor} mentioned you in a comment':
        '{actor} একটি মন্তব্যে আপনাকে উল্লেখ করেছেন',
    'Starting soon: {label}':
        'শীঘ্রই শুরু: {label}',
    'An event is starting soon':
        'একটি ইভেন্ট শীঘ্রই শুরু হচ্ছে',
    '{actor} promoted you in {label}':
        '{actor} আপনাকে {label}-এ পদোন্নতি দিয়েছেন',
    '{actor} promoted you in a server':
        '{actor} আপনাকে একটি সার্ভারে পদোন্নতি দিয়েছেন',
    'Moments & Yeels':
        'Moments এবং Yeels',
    'Comments and mentions':
        'মন্তব্য ও উল্লেখ',
    'Server events':
        'সার্ভারের ইভেন্ট',
    'Your server role':
        'সার্ভারে আপনার ভূমিকা',
  },
  'ur': {
    '{actor} commented on your Moment':
        '{actor} نے آپ کے Moment پر تبصرہ کیا',
    '{actor} commented on your Yeel':
        '{actor} نے آپ کے Yeel پر تبصرہ کیا',
    '{actor} mentioned you in a comment':
        '{actor} نے ایک تبصرے میں آپ کا ذکر کیا',
    'Starting soon: {label}':
        'جلد شروع: {label}',
    'An event is starting soon':
        'ایک ایونٹ جلد شروع ہو رہا ہے',
    '{actor} promoted you in {label}':
        '{actor} نے {label} میں آپ کو ترقی دی',
    '{actor} promoted you in a server':
        '{actor} نے ایک سرور میں آپ کو ترقی دی',
    'Moments & Yeels':
        'Moments اور Yeels',
    'Comments and mentions':
        'تبصرے اور ذکر',
    'Server events':
        'سرور کے ایونٹس',
    'Your server role':
        'سرور میں آپ کا کردار',
  },
  'th': {
    '{actor} commented on your Moment':
        '{actor} แสดงความคิดเห็นใน Moment ของคุณ',
    '{actor} commented on your Yeel':
        '{actor} แสดงความคิดเห็นใน Yeel ของคุณ',
    '{actor} mentioned you in a comment':
        '{actor} กล่าวถึงคุณในความคิดเห็น',
    'Starting soon: {label}':
        'จะเริ่มเร็ว ๆ นี้: {label}',
    'An event is starting soon':
        'กิจกรรมกำลังจะเริ่ม',
    '{actor} promoted you in {label}':
        '{actor} เลื่อนตำแหน่งให้คุณใน {label}',
    '{actor} promoted you in a server':
        '{actor} เลื่อนตำแหน่งให้คุณในเซิร์ฟเวอร์',
    'Moments & Yeels':
        'Moments และ Yeels',
    'Comments and mentions':
        'ความคิดเห็นและการกล่าวถึง',
    'Server events':
        'กิจกรรมของเซิร์ฟเวอร์',
    'Your server role':
        'บทบาทของคุณในเซิร์ฟเวอร์',
  },
  'ms': {
    '{actor} commented on your Moment':
        '{actor} mengulas Moment anda',
    '{actor} commented on your Yeel':
        '{actor} mengulas Yeel anda',
    '{actor} mentioned you in a comment':
        '{actor} menyebut anda dalam satu komen',
    'Starting soon: {label}':
        'Bermula tidak lama lagi: {label}',
    'An event is starting soon':
        'Satu acara akan bermula tidak lama lagi',
    '{actor} promoted you in {label}':
        '{actor} menaikkan pangkat anda di {label}',
    '{actor} promoted you in a server':
        '{actor} menaikkan pangkat anda di sebuah pelayan',
    'Moments & Yeels':
        'Moments dan Yeels',
    'Comments and mentions':
        'Komen dan sebutan',
    'Server events':
        'Acara pelayan',
    'Your server role':
        'Peranan anda di pelayan',
  },
  'fil': {
    '{actor} commented on your Moment':
        'Nag-komento si {actor} sa Moment mo',
    '{actor} commented on your Yeel':
        'Nag-komento si {actor} sa Yeel mo',
    '{actor} mentioned you in a comment':
        'Binanggit ka ni {actor} sa isang komento',
    'Starting soon: {label}':
        'Malapit nang magsimula: {label}',
    'An event is starting soon':
        'May event na malapit nang magsimula',
    '{actor} promoted you in {label}':
        'Itinaas ni {actor} ang role mo sa {label}',
    '{actor} promoted you in a server':
        'Itinaas ni {actor} ang role mo sa isang server',
    'Moments & Yeels':
        'Moments at Yeels',
    'Comments and mentions':
        'Mga komento at pagbanggit',
    'Server events':
        'Mga event sa server',
    'Your server role':
        'Ang role mo sa server',
  },
  'he': {
    '{actor} commented on your Moment':
        '{actor} הגיב/ה ל-Moment שלך',
    '{actor} commented on your Yeel':
        '{actor} הגיב/ה ל-Yeel שלך',
    '{actor} mentioned you in a comment':
        '{actor} הזכיר/ה אותך בתגובה',
    'Starting soon: {label}':
        'מתחיל בקרוב: {label}',
    'An event is starting soon':
        'אירוע מתחיל בקרוב',
    '{actor} promoted you in {label}':
        '{actor} קידם/ה אותך ב-{label}',
    '{actor} promoted you in a server':
        '{actor} קידם/ה אותך בשרת',
    'Moments & Yeels':
        'Moments ו-Yeels',
    'Comments and mentions':
        'תגובות ואזכורים',
    'Server events':
        'אירועים בשרתים',
    'Your server role':
        'התפקיד שלך בשרת',
  },
  'fa': {
    '{actor} commented on your Moment':
        '{actor} روی Moment شما نظر گذاشت',
    '{actor} commented on your Yeel':
        '{actor} روی Yeel شما نظر گذاشت',
    '{actor} mentioned you in a comment':
        '{actor} در یک نظر از شما نام برد',
    'Starting soon: {label}':
        'به‌زودی شروع می‌شود: {label}',
    'An event is starting soon':
        'یک رویداد به‌زودی شروع می‌شود',
    '{actor} promoted you in {label}':
        '{actor} شما را در {label} ارتقا داد',
    '{actor} promoted you in a server':
        '{actor} شما را در یک سرور ارتقا داد',
    'Moments & Yeels':
        'Moments و Yeels',
    'Comments and mentions':
        'نظرها و نام‌بردن‌ها',
    'Server events':
        'رویدادهای سرور',
    'Your server role':
        'نقش شما در سرور',
  },
  'sw': {
    '{actor} commented on your Moment':
        '{actor} ametoa maoni kwenye Moment yako',
    '{actor} commented on your Yeel':
        '{actor} ametoa maoni kwenye Yeel yako',
    '{actor} mentioned you in a comment':
        '{actor} amekutaja kwenye maoni',
    'Starting soon: {label}':
        'Inaanza hivi karibuni: {label}',
    'An event is starting soon':
        'Tukio linaanza hivi karibuni',
    '{actor} promoted you in {label}':
        '{actor} amekupandisha cheo katika {label}',
    '{actor} promoted you in a server':
        '{actor} amekupandisha cheo katika seva',
    'Moments & Yeels':
        'Moments na Yeels',
    'Comments and mentions':
        'Maoni na kutajwa',
    'Server events':
        'Matukio ya seva',
    'Your server role':
        'Wajibu wako kwenye seva',
  },
};
