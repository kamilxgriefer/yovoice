/// Copy for the Chats friend rail, build 42 "Równy rytm 48": the one-word
/// labels under the two action discs ("Dodaj" / "Napisz"), the full
/// phrases they are spoken and hovered as ("Dodaj znajomego" /
/// "Nowa wiadomość"), and the presence word a friend's tile is spoken with
/// ("Ola Nowak, aktywny").
///
/// English and Polish are authored at the call site (`_FriendsRow` in
/// `messages_screen.dart`, through `AppLocalizations.contextualText`); this
/// module gives every other selectable locale an explicit translation, so
/// none of these strings falls back to English.
///
/// The keys are `chatsRail.*` context keys rather than the English phrase:
/// "Add" and "Write" already exist in the catalog with other meanings and
/// lengths, and the rail's short words must fit its own box.
///
/// * `chatsRail.add` / `chatsRail.write` — the visible label. Each one must
///   fit the 58 px label box of a 64 px tile at 11 px bold Inter on one line
///   (`test/chats_rail_rhythm_test.dart` measures every Latin, Cyrillic and
///   Greek value with the product font and bounds the other scripts by
///   length; the widest today is Russian "Добавить", 54.8 px, 56.8 px
///   with the theme's letter spacing, and `test/slim_chats_capture.dart`
///   renders all 43 pairs, `rail-languages`). The scripts Inter does not
///   draw were measured once with the fonts a phone draws them with
///   (2026-10-06: Android's Noto Naskh Arabic, Noto Sans Hebrew,
///   Devanagari, Bengali, Thai and CJK, at the label's own style): the
///   widest are Bengali "যোগ করুন", 53.4 px, and Urdu "شامل کریں", 45.0 px.
///   A language takes the word the
///   catalog already uses for "Add" and "Write…" where that fits with a
///   pixel to spare; where its verb does not (German "Hinzufügen" 62.8 px,
///   Dutch "Toevoegen" 59.6 px, Hungarian "Hozzáadás" 59.6 px, Greek
///   "Προσθήκη" 56.1 px and 58.1 px with the letter spacing), it takes the
///   noun of its spoken name ("Freund" / "Nachricht", "Vriend" / "Bericht",
///   "Ismerős" / "Üzenet", "Φίλος" / "Μήνυμα"). A label a device draws
///   wider than this (a fallback font) widens the two action tiles instead
///   of being cut (`_FriendsRow`).
/// * `chatsRail.addFriend` / `chatsRail.newMessage` — the full phrase: the
///   tile's tooltip and its spoken name. They follow the catalog's own
///   "Add friends" / "Message" vocabulary in each language. Where the
///   phrase does not contain the visible word ("Napisz" is not in
///   "Nowa wiadomość"), the spoken name is led by that word
///   (`_FriendStory.actionName`: "Napisz, Nowa wiadomość"), so the name a
///   voice-control user says is always the one on screen (WCAG 2.5.3).
/// * `chatsRail.online` / `chatsRail.offline` — a friend's presence in the
///   tile's spoken name, after the friend's name and a comma, so lower case
///   where the script has one. Several languages say "online" / "offline"
///   themselves; that is their translation, not a fallback.
const chatsRailTranslationKeys = <String>[
  'chatsRail.add',
  'chatsRail.write',
  'chatsRail.addFriend',
  'chatsRail.newMessage',
  'chatsRail.online',
  'chatsRail.offline',
];

const chatsRailTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'chatsRail.add': 'Freund',
    'chatsRail.write': 'Nachricht',
    'chatsRail.addFriend': 'Freund hinzufügen',
    'chatsRail.newMessage': 'Neue Nachricht',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'es': <String, String>{
    'chatsRail.add': 'Agregar',
    'chatsRail.write': 'Escribir',
    'chatsRail.addFriend': 'Agregar amigo',
    'chatsRail.newMessage': 'Nuevo mensaje',
    'chatsRail.online': 'en línea',
    'chatsRail.offline': 'desconectado',
  },
  'pt': <String, String>{
    'chatsRail.add': 'Adicionar',
    'chatsRail.write': 'Escrever',
    'chatsRail.addFriend': 'Adicionar amigo',
    'chatsRail.newMessage': 'Nova mensagem',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'pt_BR': <String, String>{
    'chatsRail.add': 'Adicionar',
    'chatsRail.write': 'Escrever',
    'chatsRail.addFriend': 'Adicionar amigo',
    'chatsRail.newMessage': 'Nova mensagem',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'fr': <String, String>{
    'chatsRail.add': 'Ajouter',
    'chatsRail.write': 'Écrire',
    'chatsRail.addFriend': 'Ajouter un ami',
    'chatsRail.newMessage': 'Nouveau message',
    'chatsRail.online': 'en ligne',
    'chatsRail.offline': 'hors ligne',
  },
  'it': <String, String>{
    'chatsRail.add': 'Aggiungi',
    'chatsRail.write': 'Scrivi',
    'chatsRail.addFriend': 'Aggiungi amico',
    'chatsRail.newMessage': 'Nuovo messaggio',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'nl': <String, String>{
    'chatsRail.add': 'Vriend',
    'chatsRail.write': 'Bericht',
    'chatsRail.addFriend': 'Vriend toevoegen',
    'chatsRail.newMessage': 'Nieuw bericht',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'ro': <String, String>{
    'chatsRail.add': 'Adaugă',
    'chatsRail.write': 'Scrie',
    'chatsRail.addFriend': 'Adaugă prieten',
    'chatsRail.newMessage': 'Mesaj nou',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'tr': <String, String>{
    'chatsRail.add': 'Ekle',
    'chatsRail.write': 'Yaz',
    'chatsRail.addFriend': 'Arkadaş ekle',
    'chatsRail.newMessage': 'Yeni mesaj',
    'chatsRail.online': 'çevrimiçi',
    'chatsRail.offline': 'çevrimdışı',
  },
  'el': <String, String>{
    'chatsRail.add': 'Φίλος',
    'chatsRail.write': 'Μήνυμα',
    'chatsRail.addFriend': 'Προσθήκη φίλου',
    'chatsRail.newMessage': 'Νέο μήνυμα',
    'chatsRail.online': 'σε σύνδεση',
    'chatsRail.offline': 'εκτός σύνδεσης',
  },
  'hu': <String, String>{
    'chatsRail.add': 'Ismerős',
    'chatsRail.write': 'Üzenet',
    'chatsRail.addFriend': 'Ismerős hozzáadása',
    'chatsRail.newMessage': 'Új üzenet',
    'chatsRail.online': 'elérhető',
    'chatsRail.offline': 'nem elérhető',
  },
  'uk': <String, String>{
    'chatsRail.add': 'Додати',
    'chatsRail.write': 'Написати',
    'chatsRail.addFriend': 'Додати друга',
    'chatsRail.newMessage': 'Нове повідомлення',
    'chatsRail.online': 'у мережі',
    'chatsRail.offline': 'не в мережі',
  },
  'ru': <String, String>{
    'chatsRail.add': 'Добавить',
    'chatsRail.write': 'Написать',
    'chatsRail.addFriend': 'Добавить друга',
    'chatsRail.newMessage': 'Новое сообщение',
    'chatsRail.online': 'в сети',
    'chatsRail.offline': 'не в сети',
  },
  'cs': <String, String>{
    'chatsRail.add': 'Přidat',
    'chatsRail.write': 'Napsat',
    'chatsRail.addFriend': 'Přidat přítele',
    'chatsRail.newMessage': 'Nová zpráva',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'sk': <String, String>{
    'chatsRail.add': 'Pridať',
    'chatsRail.write': 'Napísať',
    'chatsRail.addFriend': 'Pridať priateľa',
    'chatsRail.newMessage': 'Nová správa',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'bg': <String, String>{
    'chatsRail.add': 'Добави',
    'chatsRail.write': 'Напиши',
    'chatsRail.addFriend': 'Добави приятел',
    'chatsRail.newMessage': 'Ново съобщение',
    'chatsRail.online': 'на линия',
    'chatsRail.offline': 'извън линия',
  },
  'hr': <String, String>{
    'chatsRail.add': 'Dodaj',
    'chatsRail.write': 'Napiši',
    'chatsRail.addFriend': 'Dodaj prijatelja',
    'chatsRail.newMessage': 'Nova poruka',
    'chatsRail.online': 'na mreži',
    'chatsRail.offline': 'izvan mreže',
  },
  'sr': <String, String>{
    'chatsRail.add': 'Додај',
    'chatsRail.write': 'Напиши',
    'chatsRail.addFriend': 'Додај пријатеља',
    'chatsRail.newMessage': 'Нова порука',
    'chatsRail.online': 'на мрежи',
    'chatsRail.offline': 'ван мреже',
  },
  'sv': <String, String>{
    'chatsRail.add': 'Lägg till',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Lägg till vän',
    'chatsRail.newMessage': 'Nytt meddelande',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'da': <String, String>{
    'chatsRail.add': 'Tilføj',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Tilføj ven',
    'chatsRail.newMessage': 'Ny besked',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'nb': <String, String>{
    'chatsRail.add': 'Legg til',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Legg til venn',
    'chatsRail.newMessage': 'Ny melding',
    'chatsRail.online': 'pålogget',
    'chatsRail.offline': 'avlogget',
  },
  'fi': <String, String>{
    'chatsRail.add': 'Lisää',
    'chatsRail.write': 'Kirjoita',
    'chatsRail.addFriend': 'Lisää ystävä',
    'chatsRail.newMessage': 'Uusi viesti',
    'chatsRail.online': 'linjoilla',
    'chatsRail.offline': 'ei linjoilla',
  },
  'lt': <String, String>{
    'chatsRail.add': 'Pridėti',
    'chatsRail.write': 'Rašyti',
    'chatsRail.addFriend': 'Pridėti draugą',
    'chatsRail.newMessage': 'Nauja žinutė',
    'chatsRail.online': 'prisijungęs',
    'chatsRail.offline': 'neprisijungęs',
  },
  'lv': <String, String>{
    'chatsRail.add': 'Pievienot',
    'chatsRail.write': 'Rakstīt',
    'chatsRail.addFriend': 'Pievienot draugu',
    'chatsRail.newMessage': 'Jauns ziņojums',
    'chatsRail.online': 'tiešsaistē',
    'chatsRail.offline': 'bezsaistē',
  },
  'et': <String, String>{
    'chatsRail.add': 'Lisa',
    'chatsRail.write': 'Kirjuta',
    'chatsRail.addFriend': 'Lisa sõber',
    'chatsRail.newMessage': 'Uus sõnum',
    'chatsRail.online': 'võrgus',
    'chatsRail.offline': 'pole võrgus',
  },
  'id': <String, String>{
    'chatsRail.add': 'Tambah',
    'chatsRail.write': 'Tulis',
    'chatsRail.addFriend': 'Tambah teman',
    'chatsRail.newMessage': 'Pesan baru',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'vi': <String, String>{
    'chatsRail.add': 'Thêm',
    'chatsRail.write': 'Viết',
    'chatsRail.addFriend': 'Thêm bạn',
    'chatsRail.newMessage': 'Tin nhắn mới',
    'chatsRail.online': 'trực tuyến',
    'chatsRail.offline': 'ngoại tuyến',
  },
  'zh_CN': <String, String>{
    'chatsRail.add': '添加',
    'chatsRail.write': '发消息',
    'chatsRail.addFriend': '添加好友',
    'chatsRail.newMessage': '新消息',
    'chatsRail.online': '在线',
    'chatsRail.offline': '离线',
  },
  'zh_TW': <String, String>{
    'chatsRail.add': '新增',
    'chatsRail.write': '傳訊息',
    'chatsRail.addFriend': '新增好友',
    'chatsRail.newMessage': '新訊息',
    'chatsRail.online': '線上',
    'chatsRail.offline': '離線',
  },
  'ja': <String, String>{
    'chatsRail.add': '追加',
    'chatsRail.write': '作成',
    'chatsRail.addFriend': '友達を追加',
    'chatsRail.newMessage': '新しいメッセージ',
    'chatsRail.online': 'オンライン',
    'chatsRail.offline': 'オフライン',
  },
  'ko': <String, String>{
    'chatsRail.add': '추가',
    'chatsRail.write': '쓰기',
    'chatsRail.addFriend': '친구 추가',
    'chatsRail.newMessage': '새 메시지',
    'chatsRail.online': '온라인',
    'chatsRail.offline': '오프라인',
  },
  'ar': <String, String>{
    'chatsRail.add': 'إضافة',
    'chatsRail.write': 'اكتب',
    'chatsRail.addFriend': 'إضافة صديق',
    'chatsRail.newMessage': 'رسالة جديدة',
    'chatsRail.online': 'متصل',
    'chatsRail.offline': 'غير متصل',
  },
  'th': <String, String>{
    'chatsRail.add': 'เพิ่ม',
    'chatsRail.write': 'เขียน',
    'chatsRail.addFriend': 'เพิ่มเพื่อน',
    'chatsRail.newMessage': 'ข้อความใหม่',
    'chatsRail.online': 'ออนไลน์',
    'chatsRail.offline': 'ออฟไลน์',
  },
  'ms': <String, String>{
    'chatsRail.add': 'Tambah',
    'chatsRail.write': 'Tulis',
    'chatsRail.addFriend': 'Tambah rakan',
    'chatsRail.newMessage': 'Mesej baharu',
    'chatsRail.online': 'dalam talian',
    'chatsRail.offline': 'luar talian',
  },
  'fil': <String, String>{
    'chatsRail.add': 'Idagdag',
    'chatsRail.write': 'Sumulat',
    'chatsRail.addFriend': 'Magdagdag ng kaibigan',
    'chatsRail.newMessage': 'Bagong mensahe',
    'chatsRail.online': 'online',
    'chatsRail.offline': 'offline',
  },
  'he': <String, String>{
    'chatsRail.add': 'הוסף',
    'chatsRail.write': 'כתיבה',
    'chatsRail.addFriend': 'הוסף חבר',
    'chatsRail.newMessage': 'הודעה חדשה',
    'chatsRail.online': 'מקוון',
    'chatsRail.offline': 'לא מקוון',
  },
  'fa': <String, String>{
    'chatsRail.add': 'افزودن',
    'chatsRail.write': 'نوشتن',
    'chatsRail.addFriend': 'افزودن دوست',
    'chatsRail.newMessage': 'پیام جدید',
    'chatsRail.online': 'آنلاین',
    'chatsRail.offline': 'آفلاین',
  },
  'sw': <String, String>{
    'chatsRail.add': 'Ongeza',
    'chatsRail.write': 'Andika',
    'chatsRail.addFriend': 'Ongeza rafiki',
    'chatsRail.newMessage': 'Ujumbe mpya',
    'chatsRail.online': 'mtandaoni',
    'chatsRail.offline': 'nje ya mtandao',
  },
  'hi': <String, String>{
    'chatsRail.add': 'जोड़ें',
    'chatsRail.write': 'लिखें',
    'chatsRail.addFriend': 'मित्र जोड़ें',
    'chatsRail.newMessage': 'नया संदेश',
    'chatsRail.online': 'ऑनलाइन',
    'chatsRail.offline': 'ऑफ़लाइन',
  },
  'bn': <String, String>{
    'chatsRail.add': 'যোগ করুন',
    'chatsRail.write': 'লিখুন',
    'chatsRail.addFriend': 'বন্ধু যোগ করুন',
    'chatsRail.newMessage': 'নতুন বার্তা',
    'chatsRail.online': 'অনলাইন',
    'chatsRail.offline': 'অফলাইন',
  },
  'ur': <String, String>{
    'chatsRail.add': 'شامل کریں',
    'chatsRail.write': 'لکھیں',
    'chatsRail.addFriend': 'دوست شامل کریں',
    'chatsRail.newMessage': 'نیا پیغام',
    'chatsRail.online': 'آن لائن',
    'chatsRail.offline': 'آف لائن',
  },
};
