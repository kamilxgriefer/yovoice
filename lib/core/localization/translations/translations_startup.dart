/// Warm, static headlines for the app-owned startup surface.
///
/// The caller chooses one headline per real app launch. These strings contain
/// no live activity claims, user data, or forced line breaks. Keep each phrase
/// intact so the layout can wrap it for its current locale and text scale.
const startupHeadlineTranslationKeys = <String>[
  'Where conversation begins.',
  'Your voice brings us closer.',
  'Good to hear you.',
  'Every connection starts with a hello.',
];

const startupTranslationKeys = <String>[
  ...startupHeadlineTranslationKeys,
  'Opening YO Voice',
];

/// All 43 selectable locale variants, including the English source and Polish.
///
/// The aggregate app catalog merges only its existing 41 translated locales.
/// English and Polish are included here so the startup caller can consume the
/// same source of copy for every app language without repeating headline text.
/// Automated coverage does not substitute for native-language editorial review.
const startupTranslations = <String, Map<String, String>>{
  'en': {
    'Where conversation begins.': 'Where conversation begins.',
    'Your voice brings us closer.': 'Your voice brings us closer.',
    'Good to hear you.': 'Good to hear you.',
    'Every connection starts with a hello.':
        'Every connection starts with a hello.',
    'Opening YO Voice': 'Opening YO Voice',
  },
  'pl': {
    'Where conversation begins.': 'Tu zaczyna się rozmowa.',
    'Your voice brings us closer.': 'Twój głos nas zbliża.',
    'Good to hear you.': 'Dobrze Cię słyszeć.',
    'Every connection starts with a hello.':
        'Każda znajomość zaczyna się od „cześć”.',
    'Opening YO Voice': 'Otwieranie YO Voice',
  },
  'de': {
    'Where conversation begins.': 'Hier beginnt das Gespräch.',
    'Your voice brings us closer.': 'Deine Stimme bringt uns näher zusammen.',
    'Good to hear you.': 'Schön, dich zu hören.',
    'Every connection starts with a hello.':
        'Jede Verbindung beginnt mit einem Hallo.',
    'Opening YO Voice': 'YO Voice wird geöffnet',
  },
  'es': {
    'Where conversation begins.': 'Aquí empieza la conversación.',
    'Your voice brings us closer.': 'Tu voz nos acerca.',
    'Good to hear you.': 'Qué gusto escucharte.',
    'Every connection starts with a hello.':
        'Cada conexión empieza con un hola.',
    'Opening YO Voice': 'Abriendo YO Voice',
  },
  'pt': {
    'Where conversation begins.': 'É aqui que a conversa começa.',
    'Your voice brings us closer.': 'A tua voz aproxima-nos.',
    'Good to hear you.': 'É bom ouvir-te.',
    'Every connection starts with a hello.': 'Cada ligação começa com um olá.',
    'Opening YO Voice': 'A abrir o YO Voice',
  },
  'pt_BR': {
    'Where conversation begins.': 'Aqui começa a conversa.',
    'Your voice brings us closer.': 'Sua voz nos aproxima.',
    'Good to hear you.': 'Que bom ouvir você.',
    'Every connection starts with a hello.': 'Toda conexão começa com um olá.',
    'Opening YO Voice': 'Abrindo o YO Voice',
  },
  'fr': {
    'Where conversation begins.': 'Ici, la conversation commence.',
    'Your voice brings us closer.': 'Ta voix nous rapproche.',
    'Good to hear you.': 'Ça fait plaisir de t’entendre.',
    'Every connection starts with a hello.':
        'Chaque lien commence par un bonjour.',
    'Opening YO Voice': 'Ouverture de YO Voice',
  },
  'it': {
    'Where conversation begins.': 'Qui inizia la conversazione.',
    'Your voice brings us closer.': 'La tua voce ci avvicina.',
    'Good to hear you.': 'Che bello sentirti.',
    'Every connection starts with a hello.': 'Ogni legame inizia con un ciao.',
    'Opening YO Voice': 'Apertura di YO Voice',
  },
  'uk': {
    'Where conversation begins.': 'Тут починається розмова.',
    'Your voice brings us closer.': 'Твій голос зближує нас.',
    'Good to hear you.': 'Приємно тебе чути.',
    'Every connection starts with a hello.':
        'Кожне знайомство починається з «привіт».',
    'Opening YO Voice': 'Відкриваємо YO Voice',
  },
  'ru': {
    'Where conversation begins.': 'Здесь начинается разговор.',
    'Your voice brings us closer.': 'Твой голос сближает нас.',
    'Good to hear you.': 'Приятно тебя слышать.',
    'Every connection starts with a hello.':
        'Любое знакомство начинается с «привет».',
    'Opening YO Voice': 'Открываем YO Voice',
  },
  'cs': {
    'Where conversation begins.': 'Tady začíná rozhovor.',
    'Your voice brings us closer.': 'Tvůj hlas nás sbližuje.',
    'Good to hear you.': 'Je hezké tě slyšet.',
    'Every connection starts with a hello.':
        'Každé seznámení začíná slovem „ahoj“.',
    'Opening YO Voice': 'Otevírání YO Voice',
  },
  'sk': {
    'Where conversation begins.': 'Tu sa začína rozhovor.',
    'Your voice brings us closer.': 'Tvoj hlas nás zbližuje.',
    'Good to hear you.': 'Je príjemné ťa počuť.',
    'Every connection starts with a hello.':
        'Každé zoznámenie sa začína slovom „ahoj“.',
    'Opening YO Voice': 'Otváranie YO Voice',
  },
  'bg': {
    'Where conversation begins.': 'Тук започва разговорът.',
    'Your voice brings us closer.': 'Твоят глас ни сближава.',
    'Good to hear you.': 'Хубаво е да те чуем.',
    'Every connection starts with a hello.':
        'Всяко запознанство започва със „здравей“.',
    'Opening YO Voice': 'Отваряне на YO Voice',
  },
  'nl': {
    'Where conversation begins.': 'Hier begint het gesprek.',
    'Your voice brings us closer.': 'Jouw stem brengt ons dichter bij elkaar.',
    'Good to hear you.': 'Fijn om je te horen.',
    'Every connection starts with a hello.':
        'Elk contact begint met een hallo.',
    'Opening YO Voice': 'YO Voice wordt geopend',
  },
  'ro': {
    'Where conversation begins.': 'Aici începe conversația.',
    'Your voice brings us closer.': 'Vocea ta ne apropie.',
    'Good to hear you.': 'Ce bine e să te auzim.',
    'Every connection starts with a hello.':
        'Orice legătură începe cu un salut.',
    'Opening YO Voice': 'Se deschide YO Voice',
  },
  'tr': {
    'Where conversation begins.': 'Sohbet burada başlar.',
    'Your voice brings us closer.': 'Sesin bizi yakınlaştırır.',
    'Good to hear you.': 'Sesini duymak güzel.',
    'Every connection starts with a hello.': 'Her bağ bir merhabayla başlar.',
    'Opening YO Voice': 'YO Voice açılıyor',
  },
  'el': {
    'Where conversation begins.': 'Εδώ αρχίζει η συζήτηση.',
    'Your voice brings us closer.': 'Η φωνή σου μας φέρνει πιο κοντά.',
    'Good to hear you.': 'Χαιρόμαστε που σε ακούμε.',
    'Every connection starts with a hello.':
        'Κάθε γνωριμία αρχίζει με ένα γεια.',
    'Opening YO Voice': 'Το YO Voice ανοίγει',
  },
  'hu': {
    'Where conversation begins.': 'Itt kezdődik a beszélgetés.',
    'Your voice brings us closer.': 'A hangod közelebb hoz minket.',
    'Good to hear you.': 'Jó hallani téged.',
    'Every connection starts with a hello.':
        'Minden kapcsolat egy köszönéssel kezdődik.',
    'Opening YO Voice': 'A YO Voice megnyitása',
  },
  'hr': {
    'Where conversation begins.': 'Ovdje počinje razgovor.',
    'Your voice brings us closer.': 'Tvoj nas glas zbližava.',
    'Good to hear you.': 'Lijepo te je čuti.',
    'Every connection starts with a hello.':
        'Svako poznanstvo počinje pozdravom.',
    'Opening YO Voice': 'Otvaranje aplikacije YO Voice',
  },
  'sr': {
    'Where conversation begins.': 'Овде почиње разговор.',
    'Your voice brings us closer.': 'Твој глас нас зближава.',
    'Good to hear you.': 'Лепо је чути те.',
    'Every connection starts with a hello.':
        'Свако познанство почиње поздравом.',
    'Opening YO Voice': 'Отварање апликације YO Voice',
  },
  'sv': {
    'Where conversation begins.': 'Här börjar samtalet.',
    'Your voice brings us closer.': 'Din röst för oss närmare.',
    'Good to hear you.': 'Fint att höra dig.',
    'Every connection starts with a hello.':
        'Varje kontakt börjar med ett hej.',
    'Opening YO Voice': 'Öppnar YO Voice',
  },
  'da': {
    'Where conversation begins.': 'Her begynder samtalen.',
    'Your voice brings us closer.': 'Din stemme bringer os tættere sammen.',
    'Good to hear you.': 'Dejligt at høre dig.',
    'Every connection starts with a hello.':
        'Enhver forbindelse begynder med et hej.',
    'Opening YO Voice': 'Åbner YO Voice',
  },
  'nb': {
    'Where conversation begins.': 'Her begynner samtalen.',
    'Your voice brings us closer.': 'Stemmen din bringer oss nærmere.',
    'Good to hear you.': 'Godt å høre deg.',
    'Every connection starts with a hello.':
        'Hver forbindelse starter med et hei.',
    'Opening YO Voice': 'Åpner YO Voice',
  },
  'fi': {
    'Where conversation begins.': 'Tästä keskustelu alkaa.',
    'Your voice brings us closer.': 'Äänesi tuo meidät lähemmäs.',
    'Good to hear you.': 'Mukava kuulla sinua.',
    'Every connection starts with a hello.':
        'Jokainen kohtaaminen alkaa tervehdyksestä.',
    'Opening YO Voice': 'Avataan YO Voice',
  },
  'lt': {
    'Where conversation begins.': 'Čia prasideda pokalbis.',
    'Your voice brings us closer.': 'Tavo balsas mus suartina.',
    'Good to hear you.': 'Gera tave girdėti.',
    'Every connection starts with a hello.':
        'Kiekviena pažintis prasideda nuo „labas“.',
    'Opening YO Voice': 'Atidaroma YO Voice',
  },
  'lv': {
    'Where conversation begins.': 'Šeit sākas saruna.',
    'Your voice brings us closer.': 'Tava balss mūs tuvina.',
    'Good to hear you.': 'Prieks tevi dzirdēt.',
    'Every connection starts with a hello.':
        'Katra iepazīšanās sākas ar sveicienu.',
    'Opening YO Voice': 'Tiek atvērta YO Voice',
  },
  'et': {
    'Where conversation begins.': 'Siit algab vestlus.',
    'Your voice brings us closer.': 'Sinu hääl lähendab meid.',
    'Good to hear you.': 'Tore on sind kuulda.',
    'Every connection starts with a hello.': 'Iga tutvus algab teretusest.',
    'Opening YO Voice': 'YO Voice avaneb',
  },
  'id': {
    'Where conversation begins.': 'Di sini percakapan dimulai.',
    'Your voice brings us closer.': 'Suaramu mendekatkan kita.',
    'Good to hear you.': 'Senang mendengar suaramu.',
    'Every connection starts with a hello.':
        'Setiap hubungan dimulai dengan sapaan.',
    'Opening YO Voice': 'Membuka YO Voice',
  },
  'vi': {
    'Where conversation begins.': 'Nơi cuộc trò chuyện bắt đầu.',
    'Your voice brings us closer.':
        'Giọng nói của bạn đưa ta đến gần nhau hơn.',
    'Good to hear you.': 'Thật vui khi nghe giọng bạn.',
    'Every connection starts with a hello.':
        'Mọi kết nối bắt đầu từ một lời chào.',
    'Opening YO Voice': 'Đang mở YO Voice',
  },
  'zh_CN': {
    'Where conversation begins.': '对话，从这里开始。',
    'Your voice brings us closer.': '你的声音，让我们更近。',
    'Good to hear you.': '很高兴听见你的声音。',
    'Every connection starts with a hello.': '每一段相识，都始于一声你好。',
    'Opening YO Voice': '正在打开 YO Voice',
  },
  'zh_TW': {
    'Where conversation begins.': '對話，從這裡開始。',
    'Your voice brings us closer.': '你的聲音，讓我們更靠近。',
    'Good to hear you.': '很高興聽見你的聲音。',
    'Every connection starts with a hello.': '每一段相識，都始於一聲你好。',
    'Opening YO Voice': '正在開啟 YO Voice',
  },
  'ja': {
    'Where conversation begins.': 'ここから、会話がはじまる。',
    'Your voice brings us closer.': 'あなたの声が、距離を縮める。',
    'Good to hear you.': '声が聞けて、うれしい。',
    'Every connection starts with a hello.': 'つながりは、ひとつの「こんにちは」から。',
    'Opening YO Voice': 'YO Voice を起動しています',
  },
  'ko': {
    'Where conversation begins.': '대화가 시작되는 곳.',
    'Your voice brings us closer.': '당신의 목소리가 우리를 더 가깝게 해요.',
    'Good to hear you.': '목소리를 들으니 반가워요.',
    'Every connection starts with a hello.': '모든 인연은 인사로 시작돼요.',
    'Opening YO Voice': 'YO Voice 여는 중',
  },
  'ar': {
    'Where conversation begins.': 'هنا يبدأ الحديث.',
    'Your voice brings us closer.': 'صوتك يقرّبنا.',
    'Good to hear you.': 'يسعدنا سماعك.',
    'Every connection starts with a hello.': 'كل علاقة تبدأ بكلمة «مرحبًا».',
    'Opening YO Voice': 'جارٍ فتح YO Voice',
  },
  'hi': {
    'Where conversation begins.': 'यहीं से बातचीत शुरू होती है।',
    'Your voice brings us closer.': 'आपकी आवाज़ हमें करीब लाती है।',
    'Good to hear you.': 'आपकी आवाज़ सुनकर अच्छा लगा।',
    'Every connection starts with a hello.':
        'हर रिश्ता एक नमस्ते से शुरू होता है।',
    'Opening YO Voice': 'YO Voice खुल रहा है',
  },
  'bn': {
    'Where conversation begins.': 'এখান থেকেই কথার শুরু।',
    'Your voice brings us closer.': 'আপনার কণ্ঠ আমাদের আরও কাছে আনে।',
    'Good to hear you.': 'আপনার কণ্ঠ শুনে ভালো লাগল।',
    'Every connection starts with a hello.':
        'প্রতিটি সম্পর্কের শুরু একটি হ্যালো দিয়ে।',
    'Opening YO Voice': 'YO Voice খোলা হচ্ছে',
  },
  'ur': {
    'Where conversation begins.': 'یہیں سے بات چیت شروع ہوتی ہے۔',
    'Your voice brings us closer.': 'آپ کی آواز ہمیں قریب لاتی ہے۔',
    'Good to hear you.': 'آپ کی آواز سن کر اچھا لگا۔',
    'Every connection starts with a hello.':
        'ہر تعلق ایک سلام سے شروع ہوتا ہے۔',
    'Opening YO Voice': 'YO Voice کھل رہا ہے',
  },
  'th': {
    'Where conversation begins.': 'บทสนทนาเริ่มต้นที่นี่',
    'Your voice brings us closer.': 'เสียงของคุณทำให้เราใกล้กัน',
    'Good to hear you.': 'ดีใจที่ได้ยินเสียงคุณ',
    'Every connection starts with a hello.':
        'ทุกความสัมพันธ์เริ่มต้นด้วยคำทักทาย',
    'Opening YO Voice': 'กำลังเปิด YO Voice',
  },
  'ms': {
    'Where conversation begins.': 'Di sinilah perbualan bermula.',
    'Your voice brings us closer.': 'Suaramu mendekatkan kita.',
    'Good to hear you.': 'Seronok mendengar suaramu.',
    'Every connection starts with a hello.':
        'Setiap hubungan bermula dengan sapaan.',
    'Opening YO Voice': 'Membuka YO Voice',
  },
  'fil': {
    'Where conversation begins.': 'Dito nagsisimula ang usapan.',
    'Your voice brings us closer.': 'Pinaglalapit tayo ng boses mo.',
    'Good to hear you.': 'Nakakatuwang marinig ang boses mo.',
    'Every connection starts with a hello.':
        'Bawat ugnayan ay nagsisimula sa isang kumusta.',
    'Opening YO Voice': 'Binubuksan ang YO Voice',
  },
  'he': {
    'Where conversation begins.': 'כאן מתחילה השיחה.',
    'Your voice brings us closer.': 'הקול שלך מקרב בינינו.',
    'Good to hear you.': 'טוב לשמוע אותך.',
    'Every connection starts with a hello.': 'כל קשר מתחיל במילה שלום.',
    'Opening YO Voice': 'YO Voice נפתח',
  },
  'fa': {
    'Where conversation begins.': 'گفت‌وگو از اینجا شروع می‌شود.',
    'Your voice brings us closer.': 'صدایت ما را به هم نزدیک‌تر می‌کند.',
    'Good to hear you.': 'چه خوب که صدایت را می‌شنویم.',
    'Every connection starts with a hello.':
        'هر آشنایی با یک سلام شروع می‌شود.',
    'Opening YO Voice': 'در حال باز کردن YO Voice',
  },
  'sw': {
    'Where conversation begins.': 'Hapa ndipo mazungumzo huanza.',
    'Your voice brings us closer.': 'Sauti yako inatuleta karibu.',
    'Good to hear you.': 'Ni vizuri kukusikia.',
    'Every connection starts with a hello.': 'Kila uhusiano huanza kwa salamu.',
    'Opening YO Voice': 'Inafungua YO Voice',
  },
};
