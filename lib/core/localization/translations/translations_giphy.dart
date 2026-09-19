/// GIPHY copy (ADR-213): the picker's section labels, its GIPHY-only failure
/// line and the privacy disclosure beside "Load GIFs automatically".
///
/// "Powered by GIPHY" here is the accessibility label and text fallback of
/// GIPHY's official mark; the mark image itself carries GIPHY's own wording
/// and is never re-lettered. Every locale keeps the brand names "YO Voice"
/// and "GIPHY" verbatim.
const giphyTranslationKeys = <String>[
  giphyOriginalsSectionKey,
  giphyAttributionKey,
  giphyUnavailableKey,
  giphyPrivacyDisclosureKey,
];

const giphyOriginalsSectionKey = 'YO Voice Originals';
const giphyAttributionKey = 'Powered by GIPHY';
const giphyUnavailableKey = 'GIPHY results are unavailable right now.';
const giphyPrivacyDisclosureKey =
    'When a GIPHY GIF loads, GIPHY receives your IP address and device '
    'information.';

const giphyTranslations = <String, Map<String, String>>{
  'de': {
    giphyOriginalsSectionKey: 'YO Voice Originale',
    giphyAttributionKey: 'Bereitgestellt von GIPHY',
    giphyUnavailableKey: "GIPHY-Ergebnisse sind gerade nicht verfügbar.",
    giphyPrivacyDisclosureKey:
        "Wenn ein GIPHY-GIF geladen wird, erhält GIPHY deine IP-Adresse und Geräteinformationen.",
  },
  'es': {
    giphyOriginalsSectionKey: 'Originales de YO Voice',
    giphyAttributionKey: 'Con la tecnología de GIPHY',
    giphyUnavailableKey:
        "Los resultados de GIPHY no están disponibles ahora mismo.",
    giphyPrivacyDisclosureKey:
        "Cuando se carga un GIF de GIPHY, GIPHY recibe tu dirección IP y la información de tu dispositivo.",
  },
  'pt': {
    giphyOriginalsSectionKey: 'Originais YO Voice',
    giphyAttributionKey: 'Com tecnologia GIPHY',
    giphyUnavailableKey:
        "Os resultados do GIPHY não estão disponíveis de momento.",
    giphyPrivacyDisclosureKey:
        "Quando um GIF do GIPHY é carregado, o GIPHY recebe o teu endereço IP e informações do dispositivo.",
  },
  'pt_BR': {
    giphyOriginalsSectionKey: 'Originais YO Voice',
    giphyAttributionKey: 'Com tecnologia GIPHY',
    giphyUnavailableKey:
        "Os resultados do GIPHY não estão disponíveis no momento.",
    giphyPrivacyDisclosureKey:
        "Quando um GIF do GIPHY é carregado, o GIPHY recebe seu endereço IP e informações do dispositivo.",
  },
  'fr': {
    giphyOriginalsSectionKey: 'Originaux YO Voice',
    giphyAttributionKey: 'Propulsé par GIPHY',
    giphyUnavailableKey:
        "Les résultats GIPHY sont indisponibles pour le moment.",
    giphyPrivacyDisclosureKey:
        "Lorsqu'un GIF GIPHY se charge, GIPHY reçoit votre adresse IP et des informations sur votre appareil.",
  },
  'it': {
    giphyOriginalsSectionKey: 'Originali YO Voice',
    giphyAttributionKey: 'Con tecnologia GIPHY',
    giphyUnavailableKey:
        "I risultati di GIPHY non sono disponibili al momento.",
    giphyPrivacyDisclosureKey:
        "Quando si carica una GIF di GIPHY, GIPHY riceve il tuo indirizzo IP e le informazioni sul dispositivo.",
  },
  'uk': {
    giphyOriginalsSectionKey: 'Оригінали YO Voice',
    giphyAttributionKey: 'Надано GIPHY',
    giphyUnavailableKey: "Результати GIPHY зараз недоступні.",
    giphyPrivacyDisclosureKey:
        "Коли завантажується GIF із GIPHY, GIPHY отримує вашу IP-адресу та дані про пристрій.",
  },
  'ru': {
    giphyOriginalsSectionKey: 'Оригиналы YO Voice',
    giphyAttributionKey: 'Предоставлено GIPHY',
    giphyUnavailableKey: "Результаты GIPHY сейчас недоступны.",
    giphyPrivacyDisclosureKey:
        "Когда загружается GIF из GIPHY, GIPHY получает ваш IP-адрес и сведения об устройстве.",
  },
  'cs': {
    giphyOriginalsSectionKey: 'Originály YO Voice',
    giphyAttributionKey: 'Poskytuje GIPHY',
    giphyUnavailableKey: "Výsledky GIPHY teď nejsou k dispozici.",
    giphyPrivacyDisclosureKey:
        "Když se načte GIF z GIPHY, GIPHY obdrží vaši IP adresu a informace o zařízení.",
  },
  'sk': {
    giphyOriginalsSectionKey: 'Originály YO Voice',
    giphyAttributionKey: 'Poskytuje GIPHY',
    giphyUnavailableKey: "Výsledky GIPHY momentálne nie sú dostupné.",
    giphyPrivacyDisclosureKey:
        "Keď sa načíta GIF z GIPHY, GIPHY dostane vašu IP adresu a informácie o zariadení.",
  },
  'bg': {
    giphyOriginalsSectionKey: 'Оригинали на YO Voice',
    giphyAttributionKey: 'Предоставено от GIPHY',
    giphyUnavailableKey: "Резултатите от GIPHY в момента не са налични.",
    giphyPrivacyDisclosureKey:
        "Когато се зарежда GIF от GIPHY, GIPHY получава вашия IP адрес и информация за устройството.",
  },
  'nl': {
    giphyOriginalsSectionKey: 'YO Voice-originelen',
    giphyAttributionKey: 'Mogelijk gemaakt door GIPHY',
    giphyUnavailableKey: "GIPHY-resultaten zijn nu niet beschikbaar.",
    giphyPrivacyDisclosureKey:
        "Wanneer een GIPHY-GIF laadt, ontvangt GIPHY je IP-adres en apparaatgegevens.",
  },
  'ro': {
    giphyOriginalsSectionKey: 'Originale YO Voice',
    giphyAttributionKey: 'Oferit de GIPHY',
    giphyUnavailableKey: "Rezultatele GIPHY nu sunt disponibile momentan.",
    giphyPrivacyDisclosureKey:
        "Când se încarcă un GIF GIPHY, GIPHY primește adresa ta IP și informații despre dispozitiv.",
  },
  'tr': {
    giphyOriginalsSectionKey: 'YO Voice Orijinalleri',
    giphyAttributionKey: 'GIPHY tarafından desteklenmektedir',
    giphyUnavailableKey: "GIPHY sonuçları şu anda kullanılamıyor.",
    giphyPrivacyDisclosureKey:
        "Bir GIPHY GIF'i yüklendiğinde GIPHY, IP adresinizi ve cihaz bilgilerinizi alır.",
  },
  'el': {
    giphyOriginalsSectionKey: 'Πρωτότυπα YO Voice',
    giphyAttributionKey: 'Με την υποστήριξη του GIPHY',
    giphyUnavailableKey:
        "Τα αποτελέσματα του GIPHY δεν είναι διαθέσιμα αυτή τη στιγμή.",
    giphyPrivacyDisclosureKey:
        "Όταν φορτώνεται ένα GIF του GIPHY, το GIPHY λαμβάνει τη διεύθυνση IP σας και πληροφορίες της συσκευής σας.",
  },
  'hu': {
    giphyOriginalsSectionKey: 'YO Voice eredetik',
    giphyAttributionKey: 'A GIPHY szolgáltatásával',
    giphyUnavailableKey: "A GIPHY-találatok most nem érhetők el.",
    giphyPrivacyDisclosureKey:
        "Amikor betöltődik egy GIPHY GIF, a GIPHY megkapja az IP-címedet és az eszközadataidat.",
  },
  'hr': {
    giphyOriginalsSectionKey: 'YO Voice originali',
    giphyAttributionKey: 'Pokreće GIPHY',
    giphyUnavailableKey: "Rezultati GIPHY-ja trenutačno nisu dostupni.",
    giphyPrivacyDisclosureKey:
        "Kad se učita GIF s GIPHY-ja, GIPHY dobiva vašu IP adresu i podatke o uređaju.",
  },
  'sr': {
    giphyOriginalsSectionKey: 'YO Voice оригинали',
    giphyAttributionKey: 'Покреће GIPHY',
    giphyUnavailableKey: "Резултати са GIPHY-ја тренутно нису доступни.",
    giphyPrivacyDisclosureKey:
        "Када се учита GIF са GIPHY-ја, GIPHY добија вашу IP адресу и податке о уређају.",
  },
  'sv': {
    giphyOriginalsSectionKey: 'YO Voice-original',
    giphyAttributionKey: 'Drivs av GIPHY',
    giphyUnavailableKey: "GIPHY-resultat är inte tillgängliga just nu.",
    giphyPrivacyDisclosureKey:
        "När en GIPHY-GIF laddas får GIPHY din IP-adress och enhetsinformation.",
  },
  'da': {
    giphyOriginalsSectionKey: 'YO Voice-originaler',
    giphyAttributionKey: 'Leveret af GIPHY',
    giphyUnavailableKey: "GIPHY-resultater er ikke tilgængelige lige nu.",
    giphyPrivacyDisclosureKey:
        "Når en GIPHY-GIF indlæses, modtager GIPHY din IP-adresse og enhedsoplysninger.",
  },
  'nb': {
    giphyOriginalsSectionKey: 'YO Voice-originaler',
    giphyAttributionKey: 'Levert av GIPHY',
    giphyUnavailableKey: "GIPHY-resultater er ikke tilgjengelige akkurat nå.",
    giphyPrivacyDisclosureKey:
        "Når en GIPHY-GIF lastes inn, mottar GIPHY IP-adressen din og enhetsinformasjon.",
  },
  'fi': {
    giphyOriginalsSectionKey: 'YO Voice -alkuperäiset',
    giphyAttributionKey: 'Palvelun tarjoaa GIPHY',
    giphyUnavailableKey: "GIPHY-tulokset eivät ole juuri nyt saatavilla.",
    giphyPrivacyDisclosureKey:
        "Kun GIPHY-GIF latautuu, GIPHY saa IP-osoitteesi ja laitteen tiedot.",
  },
  'lt': {
    giphyOriginalsSectionKey: 'YO Voice originalai',
    giphyAttributionKey: 'Teikia GIPHY',
    giphyUnavailableKey: "GIPHY rezultatai šiuo metu nepasiekiami.",
    giphyPrivacyDisclosureKey:
        "Kai įkeliamas GIPHY GIF, GIPHY gauna jūsų IP adresą ir įrenginio informaciją.",
  },
  'lv': {
    giphyOriginalsSectionKey: 'YO Voice oriģināli',
    giphyAttributionKey: 'Nodrošina GIPHY',
    giphyUnavailableKey: "GIPHY rezultāti pašlaik nav pieejami.",
    giphyPrivacyDisclosureKey:
        "Kad tiek ielādēts GIPHY GIF, GIPHY saņem jūsu IP adresi un ierīces informāciju.",
  },
  'et': {
    giphyOriginalsSectionKey: "YO Voice'i originaalid",
    giphyAttributionKey: 'Teenust pakub GIPHY',
    giphyUnavailableKey: "GIPHY tulemused pole praegu saadaval.",
    giphyPrivacyDisclosureKey:
        "Kui GIPHY GIF laaditakse, saab GIPHY sinu IP-aadressi ja seadme teabe.",
  },
  'id': {
    giphyOriginalsSectionKey: 'Orisinal YO Voice',
    giphyAttributionKey: 'Didukung oleh GIPHY',
    giphyUnavailableKey: "Hasil GIPHY sedang tidak tersedia.",
    giphyPrivacyDisclosureKey:
        "Saat GIF GIPHY dimuat, GIPHY menerima alamat IP dan informasi perangkat Anda.",
  },
  'vi': {
    giphyOriginalsSectionKey: 'Bản gốc YO Voice',
    giphyAttributionKey: 'Được cung cấp bởi GIPHY',
    giphyUnavailableKey: "Kết quả GIPHY hiện không khả dụng.",
    giphyPrivacyDisclosureKey:
        "Khi một GIF GIPHY được tải, GIPHY nhận được địa chỉ IP và thông tin thiết bị của bạn.",
  },
  'zh_CN': {
    giphyOriginalsSectionKey: 'YO Voice 原创',
    giphyAttributionKey: '由 GIPHY 提供支持',
    giphyUnavailableKey: "GIPHY 结果暂时不可用。",
    giphyPrivacyDisclosureKey: "加载 GIPHY GIF 时，GIPHY 会收到你的 IP 地址和设备信息。",
  },
  'zh_TW': {
    giphyOriginalsSectionKey: 'YO Voice 原創',
    giphyAttributionKey: '由 GIPHY 提供',
    giphyUnavailableKey: "GIPHY 結果暫時無法使用。",
    giphyPrivacyDisclosureKey: "載入 GIPHY GIF 時，GIPHY 會收到你的 IP 位址和裝置資訊。",
  },
  'ja': {
    giphyOriginalsSectionKey: 'YO Voice オリジナル',
    giphyAttributionKey: 'GIPHY 提供',
    giphyUnavailableKey: "現在 GIPHY の結果を利用できません。",
    giphyPrivacyDisclosureKey:
        "GIPHY の GIF が読み込まれると、GIPHY はあなたの IP アドレスとデバイス情報を受け取ります。",
  },
  'ko': {
    giphyOriginalsSectionKey: 'YO Voice 오리지널',
    giphyAttributionKey: 'GIPHY 제공',
    giphyUnavailableKey: "지금은 GIPHY 결과를 사용할 수 없습니다.",
    giphyPrivacyDisclosureKey:
        "GIPHY GIF가 로드되면 GIPHY가 회원님의 IP 주소와 기기 정보를 받습니다.",
  },
  'ar': {
    giphyOriginalsSectionKey: 'أصليات YO Voice',
    giphyAttributionKey: 'مدعوم من GIPHY',
    giphyUnavailableKey: "نتائج GIPHY غير متاحة الآن.",
    giphyPrivacyDisclosureKey:
        "عند تحميل صورة GIF من GIPHY، يتلقى GIPHY عنوان IP الخاص بك ومعلومات جهازك.",
  },
  'hi': {
    giphyOriginalsSectionKey: 'YO Voice ओरिजिनल्स',
    giphyAttributionKey: 'GIPHY द्वारा संचालित',
    giphyUnavailableKey: "GIPHY परिणाम अभी उपलब्ध नहीं हैं।",
    giphyPrivacyDisclosureKey:
        "जब कोई GIPHY GIF लोड होता है, तो GIPHY को आपका IP पता और डिवाइस की जानकारी मिलती है।",
  },
  'bn': {
    giphyOriginalsSectionKey: 'YO Voice অরিজিনালস',
    giphyAttributionKey: 'GIPHY দ্বারা চালিত',
    giphyUnavailableKey: "GIPHY ফলাফল এখন উপলভ্য নয়।",
    giphyPrivacyDisclosureKey:
        "কোনো GIPHY GIF লোড হলে GIPHY আপনার IP ঠিকানা ও ডিভাইসের তথ্য পায়।",
  },
  'ur': {
    giphyOriginalsSectionKey: 'YO Voice اوریجنلز',
    giphyAttributionKey: 'GIPHY کی جانب سے',
    giphyUnavailableKey: "GIPHY کے نتائج ابھی دستیاب نہیں ہیں۔",
    giphyPrivacyDisclosureKey:
        "جب GIPHY کا GIF لوڈ ہوتا ہے تو GIPHY کو آپ کا IP پتہ اور ڈیوائس کی معلومات ملتی ہیں۔",
  },
  'th': {
    giphyOriginalsSectionKey: 'ต้นฉบับจาก YO Voice',
    giphyAttributionKey: 'ขับเคลื่อนโดย GIPHY',
    giphyUnavailableKey: "ขณะนี้ไม่สามารถใช้ผลลัพธ์จาก GIPHY ได้",
    giphyPrivacyDisclosureKey:
        "เมื่อโหลด GIF จาก GIPHY ทาง GIPHY จะได้รับที่อยู่ IP และข้อมูลอุปกรณ์ของคุณ",
  },
  'ms': {
    giphyOriginalsSectionKey: 'Asli YO Voice',
    giphyAttributionKey: 'Dikuasakan oleh GIPHY',
    giphyUnavailableKey: "Hasil GIPHY tidak tersedia buat masa ini.",
    giphyPrivacyDisclosureKey:
        "Apabila GIF GIPHY dimuatkan, GIPHY menerima alamat IP dan maklumat peranti anda.",
  },
  'fil': {
    giphyOriginalsSectionKey: 'Mga Orihinal ng YO Voice',
    giphyAttributionKey: 'Pinapagana ng GIPHY',
    giphyUnavailableKey: "Hindi available ang mga resulta ng GIPHY ngayon.",
    giphyPrivacyDisclosureKey:
        "Kapag nag-load ang isang GIPHY GIF, natatanggap ng GIPHY ang iyong IP address at impormasyon ng device.",
  },
  'he': {
    giphyOriginalsSectionKey: 'מקוריים של YO Voice',
    giphyAttributionKey: 'מופעל על ידי GIPHY',
    giphyUnavailableKey: "תוצאות GIPHY אינן זמינות כרגע.",
    giphyPrivacyDisclosureKey:
        "כש-GIF של GIPHY נטען, GIPHY מקבלת את כתובת ה-IP שלך ומידע על המכשיר.",
  },
  'fa': {
    giphyOriginalsSectionKey: 'اوریجینال‌های YO Voice',
    giphyAttributionKey: 'با پشتیبانی GIPHY',
    giphyUnavailableKey: "نتایج GIPHY در حال حاضر در دسترس نیست.",
    giphyPrivacyDisclosureKey:
        "وقتی یک GIF از GIPHY بارگیری می‌شود، GIPHY نشانی IP و اطلاعات دستگاه شما را دریافت می‌کند.",
  },
  'sw': {
    giphyOriginalsSectionKey: 'Asili za YO Voice',
    giphyAttributionKey: 'Inaendeshwa na GIPHY',
    giphyUnavailableKey: "Matokeo ya GIPHY hayapatikani kwa sasa.",
    giphyPrivacyDisclosureKey:
        "GIF ya GIPHY inapopakiwa, GIPHY hupokea anwani yako ya IP na maelezo ya kifaa chako.",
  },
};
