/// Primary navigation labels, the Więcej menu descriptions that moved to the
/// desktop popover, and the guided tour's creation spotlight.
///
/// `navigation.yourMoments` is the compact noun on the dock and the rail
/// ("Moments"/"Momenty", O11); the destination heading keeps the invariant
/// YO Moments product name. Both tour sentences name that visible tab label:
/// the "Open Moments" key is the sentence the onboarding tour renders today,
/// and the older "Open Your Moments" key is kept (never deleted) so any build
/// or caller still passing the possessive source string resolves rather than
/// falling back to English. Neither renames the desktop tour's existing
/// create-action instructions.
const mobileNavigationTranslationKeys = <String>[
  'navigation.rooms',
  'navigation.servers',
  'navigation.yourMoments',
  'Could not load rooms',
  'Create a Voice Room here. Open Your Moments to record a Voice Moment.',
  'Create a Voice Room here. Open Moments to record a Voice Moment.',
  'Your circle',
  'Find rooms',
  'People to follow',
];

const mobileNavigationTranslations = <String, Map<String, String>>{
  'de': {
    'navigation.rooms': 'Räume',
    'navigation.servers': 'Server',
    'navigation.yourMoments': 'Momente',
    'Could not load rooms': 'Räume konnten nicht geladen werden',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Erstelle hier einen Sprachraum. Öffne „Momente“, um einen Voice Moment aufzunehmen.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Erstelle hier einen Sprachraum. Öffne „Momente“, um einen Voice Moment aufzunehmen.',
    'Your circle': 'Dein Kreis',
    'Find rooms': 'Räume finden',
    'People to follow': 'Leute, denen du folgen kannst',
  },
  'es': {
    'navigation.rooms': 'Salas',
    'navigation.servers': 'Servidores',
    'navigation.yourMoments': 'Momentos',
    'Could not load rooms': 'No se pudieron cargar las salas',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Crea una sala de voz aquí. Abre Momentos para grabar un Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Crea una sala de voz aquí. Abre Momentos para grabar un Voice Moment.',
    'Your circle': 'Tu círculo',
    'Find rooms': 'Buscar salas',
    'People to follow': 'Personas para seguir',
  },
  'pt': {
    'navigation.rooms': 'Salas',
    'navigation.servers': 'Servidores',
    'navigation.yourMoments': 'Momentos',
    'Could not load rooms': 'Não foi possível carregar as salas',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Cria uma sala de voz aqui. Abre Momentos para gravares um Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Cria uma sala de voz aqui. Abre Momentos para gravares um Voice Moment.',
    'Your circle': 'O teu círculo',
    'Find rooms': 'Encontrar salas',
    'People to follow': 'Pessoas para seguir',
  },
  'pt_BR': {
    'navigation.rooms': 'Salas',
    'navigation.servers': 'Servidores',
    'navigation.yourMoments': 'Momentos',
    'Could not load rooms': 'Não foi possível carregar as salas',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Crie uma sala de voz aqui. Abra Momentos para gravar um Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Crie uma sala de voz aqui. Abra Momentos para gravar um Voice Moment.',
    'Your circle': 'Seu círculo',
    'Find rooms': 'Encontrar salas',
    'People to follow': 'Pessoas para seguir',
  },
  'fr': {
    'navigation.rooms': 'Salons',
    'navigation.servers': 'Serveurs',
    'navigation.yourMoments': 'Moments',
    'Could not load rooms': 'Impossible de charger les salons',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Créez un salon vocal ici. Ouvrez Moments pour enregistrer un Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Créez un salon vocal ici. Ouvrez Moments pour enregistrer un Voice Moment.',
    'Your circle': 'Votre cercle',
    'Find rooms': 'Trouver des salons',
    'People to follow': 'Personnes à suivre',
  },
  'it': {
    'navigation.rooms': 'Stanze',
    'navigation.servers': 'Server',
    'navigation.yourMoments': 'Momenti',
    'Could not load rooms': 'Impossibile caricare le stanze',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Crea una stanza vocale qui. Apri Momenti per registrare un Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Crea una stanza vocale qui. Apri Momenti per registrare un Voice Moment.',
    'Your circle': 'La tua cerchia',
    'Find rooms': 'Trova stanze',
    'People to follow': 'Persone da seguire',
  },
  'uk': {
    'navigation.rooms': 'Кімнати',
    'navigation.servers': 'Сервери',
    'navigation.yourMoments': 'Моменти',
    'Could not load rooms': 'Не вдалося завантажити кімнати',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Створи тут голосову кімнату. Відкрий «Моменти», щоб записати Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Створи тут голосову кімнату. Відкрий «Моменти», щоб записати Voice Moment.',
    'Your circle': 'Твоє коло',
    'Find rooms': 'Знайти кімнати',
    'People to follow': 'Люди, за якими варто стежити',
  },
  'ru': {
    'navigation.rooms': 'Комнаты',
    'navigation.servers': 'Серверы',
    'navigation.yourMoments': 'Моменты',
    'Could not load rooms': 'Не удалось загрузить комнаты',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Создайте здесь голосовую комнату. Откройте «Моменты», чтобы записать Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Создайте здесь голосовую комнату. Откройте «Моменты», чтобы записать Voice Moment.',
    'Your circle': 'Ваш круг',
    'Find rooms': 'Найти комнаты',
    'People to follow': 'Люди, на которых стоит подписаться',
  },
  'cs': {
    'navigation.rooms': 'Místnosti',
    'navigation.servers': 'Servery',
    'navigation.yourMoments': 'Momenty',
    'Could not load rooms': 'Místnosti se nepodařilo načíst',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Zde vytvoříte hlasovou místnost. Otevřete „Momenty“ a nahrajte Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Zde vytvoříte hlasovou místnost. Otevřete „Momenty“ a nahrajte Voice Moment.',
    'Your circle': 'Váš okruh',
    'Find rooms': 'Najít místnosti',
    'People to follow': 'Lidé, které stojí za to sledovat',
  },
  'sk': {
    'navigation.rooms': 'Miestnosti',
    'navigation.servers': 'Servery',
    'navigation.yourMoments': 'Momenty',
    'Could not load rooms': 'Miestnosti sa nepodarilo načítať',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Tu vytvoríte hlasovú miestnosť. Otvorte „Momenty“ a nahrajte Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Tu vytvoríte hlasovú miestnosť. Otvorte „Momenty“ a nahrajte Voice Moment.',
    'Your circle': 'Váš okruh',
    'Find rooms': 'Nájsť miestnosti',
    'People to follow': 'Ľudia, ktorých sa oplatí sledovať',
  },
  'bg': {
    'navigation.rooms': 'Стаи',
    'navigation.servers': 'Сървъри',
    'navigation.yourMoments': 'Моменти',
    'Could not load rooms': 'Стаите не можаха да се заредят',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Създай гласова стая тук. Отвори „Моменти“, за да запишеш Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Създай гласова стая тук. Отвори „Моменти“, за да запишеш Voice Moment.',
    'Your circle': 'Твоят кръг',
    'Find rooms': 'Намери стаи',
    'People to follow': 'Хора, които да следваш',
  },
  'nl': {
    'navigation.rooms': 'Ruimtes',
    'navigation.servers': 'Servers',
    'navigation.yourMoments': 'Momenten',
    'Could not load rooms': 'Ruimtes konden niet worden geladen',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Maak hier een spraakruimte. Open Momenten om een Voice Moment op te nemen.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Maak hier een spraakruimte. Open Momenten om een Voice Moment op te nemen.',
    'Your circle': 'Jouw kring',
    'Find rooms': 'Ruimtes zoeken',
    'People to follow': 'Mensen om te volgen',
  },
  'ro': {
    'navigation.rooms': 'Camere',
    'navigation.servers': 'Servere',
    'navigation.yourMoments': 'Momente',
    'Could not load rooms': 'Camerele nu au putut fi încărcate',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Creează o cameră vocală aici. Deschide Momente pentru a înregistra un Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Creează o cameră vocală aici. Deschide Momente pentru a înregistra un Voice Moment.',
    'Your circle': 'Cercul tău',
    'Find rooms': 'Găsește camere',
    'People to follow': 'Persoane de urmărit',
  },
  'tr': {
    'navigation.rooms': 'Odalar',
    'navigation.servers': 'Sunucular',
    'navigation.yourMoments': 'Anlar',
    'Could not load rooms': 'Odalar yüklenemedi',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Buradan bir ses odası oluştur. Voice Moment kaydetmek için Anlar sekmesini aç.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Buradan bir ses odası oluştur. Voice Moment kaydetmek için Anlar sekmesini aç.',
    'Your circle': 'Çevren',
    'Find rooms': 'Oda bul',
    'People to follow': 'Takip edilecek kişiler',
  },
  'el': {
    'navigation.rooms': 'Δωμάτια',
    'navigation.servers': 'Διακομιστές',
    'navigation.yourMoments': 'Στιγμές',
    'Could not load rooms': 'Δεν ήταν δυνατή η φόρτωση των δωματίων',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Δημιούργησε εδώ ένα δωμάτιο φωνής. Άνοιξε την καρτέλα «Στιγμές» για να ηχογραφήσεις ένα Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Δημιούργησε εδώ ένα δωμάτιο φωνής. Άνοιξε την καρτέλα «Στιγμές» για να ηχογραφήσεις ένα Voice Moment.',
    'Your circle': 'Ο κύκλος σου',
    'Find rooms': 'Βρες δωμάτια',
    'People to follow': 'Άτομα που αξίζει να ακολουθήσεις',
  },
  'hu': {
    'navigation.rooms': 'Szobák',
    'navigation.servers': 'Szerverek',
    'navigation.yourMoments': 'Pillanatok',
    'Could not load rooms': 'Nem sikerült betölteni a szobákat',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Itt hozhatsz létre hangszobát. Voice Moment rögzítéséhez nyisd meg a Pillanatok lapot.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Itt hozhatsz létre hangszobát. Voice Moment rögzítéséhez nyisd meg a Pillanatok lapot.',
    'Your circle': 'A köröd',
    'Find rooms': 'Szobák keresése',
    'People to follow': 'Követésre érdemes emberek',
  },
  'hr': {
    'navigation.rooms': 'Sobe',
    'navigation.servers': 'Poslužitelji',
    'navigation.yourMoments': 'Trenuci',
    'Could not load rooms': 'Nije moguće učitati sobe',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Ovdje stvori glasovnu sobu. Otvori „Trenuci” za snimanje Voice Momenta.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Ovdje stvori glasovnu sobu. Otvori „Trenuci” za snimanje Voice Momenta.',
    'Your circle': 'Tvoj krug',
    'Find rooms': 'Pronađi sobe',
    'People to follow': 'Osobe vrijedne praćenja',
  },
  'sr': {
    'navigation.rooms': 'Собе',
    'navigation.servers': 'Сервери',
    'navigation.yourMoments': 'Тренуци',
    'Could not load rooms': 'Није могуће учитати собе',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Овде направи гласовну собу. Отвори „Тренуци” да снимиш Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Овде направи гласовну собу. Отвори „Тренуци” да снимиш Voice Moment.',
    'Your circle': 'Твој круг',
    'Find rooms': 'Пронађи собе',
    'People to follow': 'Особе вредне праћења',
  },
  'sv': {
    'navigation.rooms': 'Rum',
    'navigation.servers': 'Servrar',
    'navigation.yourMoments': 'Ögonblick',
    'Could not load rooms': 'Det gick inte att läsa in rummen',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Skapa ett röstrum här. Öppna Ögonblick för att spela in ett Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Skapa ett röstrum här. Öppna Ögonblick för att spela in ett Voice Moment.',
    'Your circle': 'Din krets',
    'Find rooms': 'Hitta rum',
    'People to follow': 'Personer att följa',
  },
  'da': {
    'navigation.rooms': 'Rum',
    'navigation.servers': 'Servere',
    'navigation.yourMoments': 'Øjeblikke',
    'Could not load rooms': 'Rummene kunne ikke indlæses',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Opret et talerum her. Åbn Øjeblikke for at optage et Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Opret et talerum her. Åbn Øjeblikke for at optage et Voice Moment.',
    'Your circle': 'Din kreds',
    'Find rooms': 'Find rum',
    'People to follow': 'Personer at følge',
  },
  'nb': {
    'navigation.rooms': 'Rom',
    'navigation.servers': 'Servere',
    'navigation.yourMoments': 'Øyeblikk',
    'Could not load rooms': 'Kunne ikke laste inn rommene',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Opprett et talerom her. Åpne Øyeblikk for å spille inn et Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Opprett et talerom her. Åpne Øyeblikk for å spille inn et Voice Moment.',
    'Your circle': 'Din krets',
    'Find rooms': 'Finn rom',
    'People to follow': 'Personer å følge',
  },
  'fi': {
    'navigation.rooms': 'Huoneet',
    'navigation.servers': 'Palvelimet',
    'navigation.yourMoments': 'Hetket',
    'Could not load rooms': 'Huoneita ei voitu ladata',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Luo puhehuone tästä. Avaa Hetket, kun haluat tallentaa Voice Momentin.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Luo puhehuone tästä. Avaa Hetket, kun haluat tallentaa Voice Momentin.',
    'Your circle': 'Oma piirisi',
    'Find rooms': 'Etsi huoneita',
    'People to follow': 'Seuraamisen arvoisia ihmisiä',
  },
  'lt': {
    'navigation.rooms': 'Kambariai',
    'navigation.servers': 'Serveriai',
    'navigation.yourMoments': 'Akimirkos',
    'Could not load rooms': 'Nepavyko įkelti kambarių',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Čia sukurk balso kambarį. Atverk „Akimirkos“ ir įrašyk Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Čia sukurk balso kambarį. Atverk „Akimirkos“ ir įrašyk Voice Moment.',
    'Your circle': 'Tavo ratas',
    'Find rooms': 'Rasti kambarių',
    'People to follow': 'Žmonės, kuriuos verta sekti',
  },
  'lv': {
    'navigation.rooms': 'Istabas',
    'navigation.servers': 'Serveri',
    'navigation.yourMoments': 'Mirkļi',
    'Could not load rooms': 'Neizdevās ielādēt istabas',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Šeit izveido balss istabu. Atver sadaļu „Mirkļi”, lai ierakstītu Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Šeit izveido balss istabu. Atver sadaļu „Mirkļi”, lai ierakstītu Voice Moment.',
    'Your circle': 'Tavs loks',
    'Find rooms': 'Atrast istabas',
    'People to follow': 'Cilvēki, kam sekot',
  },
  'et': {
    'navigation.rooms': 'Toad',
    'navigation.servers': 'Serverid',
    'navigation.yourMoments': 'Hetked',
    'Could not load rooms': 'Tubade laadimine ebaõnnestus',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Loo siin hääletuba. Ava Hetked, et salvestada Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Loo siin hääletuba. Ava Hetked, et salvestada Voice Moment.',
    'Your circle': 'Sinu ring',
    'Find rooms': 'Leia tube',
    'People to follow': 'Inimesed, keda jälgida',
  },
  'id': {
    'navigation.rooms': 'Ruang',
    'navigation.servers': 'Server',
    'navigation.yourMoments': 'Momen',
    'Could not load rooms': 'Ruang tidak dapat dimuat',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Buat ruang suara di sini. Buka Momen untuk merekam Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Buat ruang suara di sini. Buka Momen untuk merekam Voice Moment.',
    'Your circle': 'Lingkaranmu',
    'Find rooms': 'Temukan ruang',
    'People to follow': 'Orang yang layak diikuti',
  },
  'vi': {
    'navigation.rooms': 'Phòng',
    'navigation.servers': 'Máy chủ',
    'navigation.yourMoments': 'Khoảnh khắc',
    'Could not load rooms': 'Không thể tải các phòng',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Tạo phòng thoại tại đây. Mở Khoảnh khắc để ghi âm Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Tạo phòng thoại tại đây. Mở Khoảnh khắc để ghi âm Voice Moment.',
    'Your circle': 'Cộng đồng của bạn',
    'Find rooms': 'Tìm phòng',
    'People to follow': 'Những người đáng theo dõi',
  },
  'zh_CN': {
    'navigation.rooms': '房间',
    'navigation.servers': '服务器',
    'navigation.yourMoments': '时刻',
    'Could not load rooms': '无法加载房间',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        '在这里创建语音房间。打开“时刻”以录制 Voice Moment。',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        '在这里创建语音房间。打开“时刻”以录制 Voice Moment。',
    'Your circle': '你的圈子',
    'Find rooms': '查找房间',
    'People to follow': '值得关注的人',
  },
  'zh_TW': {
    'navigation.rooms': '房間',
    'navigation.servers': '伺服器',
    'navigation.yourMoments': '時刻',
    'Could not load rooms': '無法載入房間',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        '在這裡建立語音房間。開啟「時刻」以錄製 Voice Moment。',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        '在這裡建立語音房間。開啟「時刻」以錄製 Voice Moment。',
    'Your circle': '你的圈子',
    'Find rooms': '尋找房間',
    'People to follow': '值得追蹤的人',
  },
  'ja': {
    'navigation.rooms': 'ルーム',
    'navigation.servers': 'サーバー',
    'navigation.yourMoments': 'モーメント',
    'Could not load rooms': 'ルームを読み込めませんでした',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'ここでボイスルームを作成できます。「モーメント」を開くと Voice Moment を録音できます。',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'ここでボイスルームを作成できます。「モーメント」を開くと Voice Moment を録音できます。',
    'Your circle': 'あなたのつながり',
    'Find rooms': 'ルームを探す',
    'People to follow': 'フォローしたい人',
  },
  'ko': {
    'navigation.rooms': '방',
    'navigation.servers': '서버',
    'navigation.yourMoments': '모먼트',
    'Could not load rooms': '방을 불러올 수 없습니다',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        '여기에서 음성 방을 만드세요. 모먼트를 열어 Voice Moment를 녹음하세요.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        '여기에서 음성 방을 만드세요. 모먼트를 열어 Voice Moment를 녹음하세요.',
    'Your circle': '내 인맥',
    'Find rooms': '방 찾기',
    'People to follow': '팔로우할 만한 사람',
  },
  'ar': {
    'navigation.rooms': 'الغرف',
    'navigation.servers': 'الخوادم',
    'navigation.yourMoments': 'اللحظات',
    'Could not load rooms': 'تعذّر تحميل الغرف',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'أنشئ غرفة صوتية هنا. افتح اللحظات لتسجيل Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'أنشئ غرفة صوتية هنا. افتح اللحظات لتسجيل Voice Moment.',
    'Your circle': 'دائرتك',
    'Find rooms': 'العثور على الغرف',
    'People to follow': 'أشخاص يستحقون المتابعة',
  },
  'hi': {
    'navigation.rooms': 'रूम',
    'navigation.servers': 'सर्वर',
    'navigation.yourMoments': 'पल',
    'Could not load rooms': 'रूम लोड नहीं हो सके',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'यहाँ वॉइस रूम बनाएँ। Voice Moment रिकॉर्ड करने के लिए पल खोलें।',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'यहाँ वॉइस रूम बनाएँ। Voice Moment रिकॉर्ड करने के लिए पल खोलें।',
    'Your circle': 'आपका दायरा',
    'Find rooms': 'रूम खोजें',
    'People to follow': 'फ़ॉलो करने लायक लोग',
  },
  'bn': {
    'navigation.rooms': 'রুম',
    'navigation.servers': 'সার্ভার',
    'navigation.yourMoments': 'মুহূর্ত',
    'Could not load rooms': 'রুমগুলো লোড করা যায়নি',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'এখানে ভয়েস রুম তৈরি করুন। Voice Moment রেকর্ড করতে মুহূর্ত খুলুন।',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'এখানে ভয়েস রুম তৈরি করুন। Voice Moment রেকর্ড করতে মুহূর্ত খুলুন।',
    'Your circle': 'আপনার বৃত্ত',
    'Find rooms': 'রুম খুঁজুন',
    'People to follow': 'অনুসরণ করার মতো মানুষ',
  },
  'ur': {
    'navigation.rooms': 'روم',
    'navigation.servers': 'سرورز',
    'navigation.yourMoments': 'لمحات',
    'Could not load rooms': 'روم لوڈ نہیں ہو سکے',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'یہاں وائس روم بنائیں۔ Voice Moment ریکارڈ کرنے کے لیے لمحات کھولیں۔',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'یہاں وائس روم بنائیں۔ Voice Moment ریکارڈ کرنے کے لیے لمحات کھولیں۔',
    'Your circle': 'آپ کا حلقہ',
    'Find rooms': 'روم تلاش کریں',
    'People to follow': 'فالو کرنے کے قابل لوگ',
  },
  'th': {
    'navigation.rooms': 'ห้อง',
    'navigation.servers': 'เซิร์ฟเวอร์',
    'navigation.yourMoments': 'ช่วงเวลา',
    'Could not load rooms': 'โหลดห้องไม่ได้',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'สร้างห้องเสียงได้ที่นี่ เปิดช่วงเวลาเพื่อบันทึก Voice Moment',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'สร้างห้องเสียงได้ที่นี่ เปิดช่วงเวลาเพื่อบันทึก Voice Moment',
    'Your circle': 'วงสังคมของคุณ',
    'Find rooms': 'ค้นหาห้อง',
    'People to follow': 'คนที่น่าติดตาม',
  },
  'ms': {
    'navigation.rooms': 'Bilik',
    'navigation.servers': 'Pelayan',
    'navigation.yourMoments': 'Detik',
    'Could not load rooms': 'Bilik tidak dapat dimuatkan',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Cipta bilik suara di sini. Buka Detik untuk merakam Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Cipta bilik suara di sini. Buka Detik untuk merakam Voice Moment.',
    'Your circle': 'Lingkaran anda',
    'Find rooms': 'Cari bilik',
    'People to follow': 'Orang yang patut diikuti',
  },
  'fil': {
    'navigation.rooms': 'Mga kuwarto',
    'navigation.servers': 'Mga server',
    'navigation.yourMoments': 'Mga sandali',
    'Could not load rooms': 'Hindi ma-load ang mga kuwarto',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Gumawa ng voice room dito. Buksan ang Mga sandali para mag-record ng Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Gumawa ng voice room dito. Buksan ang Mga sandali para mag-record ng Voice Moment.',
    'Your circle': 'Mga kakilala mo',
    'Find rooms': 'Maghanap ng mga kuwarto',
    'People to follow': 'Mga taong sulit sundan',
  },
  'he': {
    'navigation.rooms': 'חדרים',
    'navigation.servers': 'שרתים',
    'navigation.yourMoments': 'רגעים',
    'Could not load rooms': 'לא ניתן לטעון את החדרים',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'כאן אפשר ליצור חדר קולי. כדי להקליט Voice Moment, פתחו את „רגעים”.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'כאן אפשר ליצור חדר קולי. כדי להקליט Voice Moment, פתחו את „רגעים”.',
    'Your circle': 'המעגל שלך',
    'Find rooms': 'חיפוש חדרים',
    'People to follow': 'אנשים ששווה לעקוב אחריהם',
  },
  'fa': {
    'navigation.rooms': 'اتاق‌ها',
    'navigation.servers': 'سرورها',
    'navigation.yourMoments': 'لحظه‌ها',
    'Could not load rooms': 'اتاق‌ها بارگیری نشدند',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'اینجا یک اتاق صوتی بسازید. برای ضبط Voice Moment، لحظه‌ها را باز کنید.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'اینجا یک اتاق صوتی بسازید. برای ضبط Voice Moment، لحظه‌ها را باز کنید.',
    'Your circle': 'حلقهٔ شما',
    'Find rooms': 'پیدا کردن اتاق‌ها',
    'People to follow': 'افرادی که ارزش دنبال کردن دارند',
  },
  'sw': {
    'navigation.rooms': 'Vyumba',
    'navigation.servers': 'Seva',
    'navigation.yourMoments': 'Matukio',
    'Could not load rooms': 'Vyumba havikuweza kupakiwa',
    'Create a Voice Room here. Open Your Moments to record a Voice Moment.':
        'Unda chumba cha sauti hapa. Fungua Matukio ili kurekodi Voice Moment.',
    'Create a Voice Room here. Open Moments to record a Voice Moment.':
        'Unda chumba cha sauti hapa. Fungua Matukio ili kurekodi Voice Moment.',
    'Your circle': 'Mduara wako',
    'Find rooms': 'Tafuta vyumba',
    'People to follow': 'Watu wanaofaa kufuatwa',
  },
};
