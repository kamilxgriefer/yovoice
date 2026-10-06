/// Copy for the Chats friend rail, build 42 "Równy rytm 48": the one-word
/// labels under the two action discs ("Dodaj" / "Napisz") and the full
/// phrases they are spoken and hovered as ("Dodaj znajomego" /
/// "Nowa wiadomość").
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
///   renders all 43 pairs, `rail-languages`). A language takes the word the
///   catalog already uses for "Add" and "Write…" where that fits with a
///   pixel to spare; where its verb does not (German "Hinzufügen" 62.8 px,
///   Dutch "Toevoegen" 59.6 px, Hungarian "Hozzáadás" 59.6 px, Greek
///   "Προσθήκη" 56.1 px and 58.1 px with the letter spacing), it takes the
///   noun of its spoken name ("Freund" / "Nachricht", "Vriend" / "Bericht",
///   "Ismerős" / "Üzenet", "Φίλος" / "Μήνυμα"), so the visible word is
///   still part of what a screen reader says. A label a device draws wider
///   than this (a fallback font) widens the two action tiles instead of
///   being cut (`_FriendsRow`).
/// * `chatsRail.addFriend` / `chatsRail.newMessage` — the full phrase: the
///   tile's semantics label and tooltip. They follow the catalog's own
///   "Add friends" / "Message" vocabulary in each language.
const chatsRailTranslationKeys = <String>[
  'chatsRail.add',
  'chatsRail.write',
  'chatsRail.addFriend',
  'chatsRail.newMessage',
];

const chatsRailTranslations = <String, Map<String, String>>{
  'de': <String, String>{
    'chatsRail.add': 'Freund',
    'chatsRail.write': 'Nachricht',
    'chatsRail.addFriend': 'Freund hinzufügen',
    'chatsRail.newMessage': 'Neue Nachricht',
  },
  'es': <String, String>{
    'chatsRail.add': 'Agregar',
    'chatsRail.write': 'Escribir',
    'chatsRail.addFriend': 'Agregar amigo',
    'chatsRail.newMessage': 'Nuevo mensaje',
  },
  'pt': <String, String>{
    'chatsRail.add': 'Adicionar',
    'chatsRail.write': 'Escrever',
    'chatsRail.addFriend': 'Adicionar amigo',
    'chatsRail.newMessage': 'Nova mensagem',
  },
  'pt_BR': <String, String>{
    'chatsRail.add': 'Adicionar',
    'chatsRail.write': 'Escrever',
    'chatsRail.addFriend': 'Adicionar amigo',
    'chatsRail.newMessage': 'Nova mensagem',
  },
  'fr': <String, String>{
    'chatsRail.add': 'Ajouter',
    'chatsRail.write': 'Écrire',
    'chatsRail.addFriend': 'Ajouter un ami',
    'chatsRail.newMessage': 'Nouveau message',
  },
  'it': <String, String>{
    'chatsRail.add': 'Aggiungi',
    'chatsRail.write': 'Scrivi',
    'chatsRail.addFriend': 'Aggiungi amico',
    'chatsRail.newMessage': 'Nuovo messaggio',
  },
  'nl': <String, String>{
    'chatsRail.add': 'Vriend',
    'chatsRail.write': 'Bericht',
    'chatsRail.addFriend': 'Vriend toevoegen',
    'chatsRail.newMessage': 'Nieuw bericht',
  },
  'ro': <String, String>{
    'chatsRail.add': 'Adaugă',
    'chatsRail.write': 'Scrie',
    'chatsRail.addFriend': 'Adaugă prieten',
    'chatsRail.newMessage': 'Mesaj nou',
  },
  'tr': <String, String>{
    'chatsRail.add': 'Ekle',
    'chatsRail.write': 'Yaz',
    'chatsRail.addFriend': 'Arkadaş ekle',
    'chatsRail.newMessage': 'Yeni mesaj',
  },
  'el': <String, String>{
    'chatsRail.add': 'Φίλος',
    'chatsRail.write': 'Μήνυμα',
    'chatsRail.addFriend': 'Προσθήκη φίλου',
    'chatsRail.newMessage': 'Νέο μήνυμα',
  },
  'hu': <String, String>{
    'chatsRail.add': 'Ismerős',
    'chatsRail.write': 'Üzenet',
    'chatsRail.addFriend': 'Ismerős hozzáadása',
    'chatsRail.newMessage': 'Új üzenet',
  },
  'uk': <String, String>{
    'chatsRail.add': 'Додати',
    'chatsRail.write': 'Написати',
    'chatsRail.addFriend': 'Додати друга',
    'chatsRail.newMessage': 'Нове повідомлення',
  },
  'ru': <String, String>{
    'chatsRail.add': 'Добавить',
    'chatsRail.write': 'Написать',
    'chatsRail.addFriend': 'Добавить друга',
    'chatsRail.newMessage': 'Новое сообщение',
  },
  'cs': <String, String>{
    'chatsRail.add': 'Přidat',
    'chatsRail.write': 'Napsat',
    'chatsRail.addFriend': 'Přidat přítele',
    'chatsRail.newMessage': 'Nová zpráva',
  },
  'sk': <String, String>{
    'chatsRail.add': 'Pridať',
    'chatsRail.write': 'Napísať',
    'chatsRail.addFriend': 'Pridať priateľa',
    'chatsRail.newMessage': 'Nová správa',
  },
  'bg': <String, String>{
    'chatsRail.add': 'Добави',
    'chatsRail.write': 'Напиши',
    'chatsRail.addFriend': 'Добави приятел',
    'chatsRail.newMessage': 'Ново съобщение',
  },
  'hr': <String, String>{
    'chatsRail.add': 'Dodaj',
    'chatsRail.write': 'Napiši',
    'chatsRail.addFriend': 'Dodaj prijatelja',
    'chatsRail.newMessage': 'Nova poruka',
  },
  'sr': <String, String>{
    'chatsRail.add': 'Додај',
    'chatsRail.write': 'Напиши',
    'chatsRail.addFriend': 'Додај пријатеља',
    'chatsRail.newMessage': 'Нова порука',
  },
  'sv': <String, String>{
    'chatsRail.add': 'Lägg till',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Lägg till vän',
    'chatsRail.newMessage': 'Nytt meddelande',
  },
  'da': <String, String>{
    'chatsRail.add': 'Tilføj',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Tilføj ven',
    'chatsRail.newMessage': 'Ny besked',
  },
  'nb': <String, String>{
    'chatsRail.add': 'Legg til',
    'chatsRail.write': 'Skriv',
    'chatsRail.addFriend': 'Legg til venn',
    'chatsRail.newMessage': 'Ny melding',
  },
  'fi': <String, String>{
    'chatsRail.add': 'Lisää',
    'chatsRail.write': 'Kirjoita',
    'chatsRail.addFriend': 'Lisää ystävä',
    'chatsRail.newMessage': 'Uusi viesti',
  },
  'lt': <String, String>{
    'chatsRail.add': 'Pridėti',
    'chatsRail.write': 'Rašyti',
    'chatsRail.addFriend': 'Pridėti draugą',
    'chatsRail.newMessage': 'Nauja žinutė',
  },
  'lv': <String, String>{
    'chatsRail.add': 'Pievienot',
    'chatsRail.write': 'Rakstīt',
    'chatsRail.addFriend': 'Pievienot draugu',
    'chatsRail.newMessage': 'Jauns ziņojums',
  },
  'et': <String, String>{
    'chatsRail.add': 'Lisa',
    'chatsRail.write': 'Kirjuta',
    'chatsRail.addFriend': 'Lisa sõber',
    'chatsRail.newMessage': 'Uus sõnum',
  },
  'id': <String, String>{
    'chatsRail.add': 'Tambah',
    'chatsRail.write': 'Tulis',
    'chatsRail.addFriend': 'Tambah teman',
    'chatsRail.newMessage': 'Pesan baru',
  },
  'vi': <String, String>{
    'chatsRail.add': 'Thêm',
    'chatsRail.write': 'Viết',
    'chatsRail.addFriend': 'Thêm bạn',
    'chatsRail.newMessage': 'Tin nhắn mới',
  },
  'zh_CN': <String, String>{
    'chatsRail.add': '添加',
    'chatsRail.write': '发消息',
    'chatsRail.addFriend': '添加好友',
    'chatsRail.newMessage': '新消息',
  },
  'zh_TW': <String, String>{
    'chatsRail.add': '新增',
    'chatsRail.write': '傳訊息',
    'chatsRail.addFriend': '新增好友',
    'chatsRail.newMessage': '新訊息',
  },
  'ja': <String, String>{
    'chatsRail.add': '追加',
    'chatsRail.write': '作成',
    'chatsRail.addFriend': '友達を追加',
    'chatsRail.newMessage': '新しいメッセージ',
  },
  'ko': <String, String>{
    'chatsRail.add': '추가',
    'chatsRail.write': '쓰기',
    'chatsRail.addFriend': '친구 추가',
    'chatsRail.newMessage': '새 메시지',
  },
  'ar': <String, String>{
    'chatsRail.add': 'إضافة',
    'chatsRail.write': 'اكتب',
    'chatsRail.addFriend': 'إضافة صديق',
    'chatsRail.newMessage': 'رسالة جديدة',
  },
  'th': <String, String>{
    'chatsRail.add': 'เพิ่ม',
    'chatsRail.write': 'เขียน',
    'chatsRail.addFriend': 'เพิ่มเพื่อน',
    'chatsRail.newMessage': 'ข้อความใหม่',
  },
  'ms': <String, String>{
    'chatsRail.add': 'Tambah',
    'chatsRail.write': 'Tulis',
    'chatsRail.addFriend': 'Tambah rakan',
    'chatsRail.newMessage': 'Mesej baharu',
  },
  'fil': <String, String>{
    'chatsRail.add': 'Idagdag',
    'chatsRail.write': 'Sumulat',
    'chatsRail.addFriend': 'Magdagdag ng kaibigan',
    'chatsRail.newMessage': 'Bagong mensahe',
  },
  'he': <String, String>{
    'chatsRail.add': 'הוסף',
    'chatsRail.write': 'כתיבה',
    'chatsRail.addFriend': 'הוסף חבר',
    'chatsRail.newMessage': 'הודעה חדשה',
  },
  'fa': <String, String>{
    'chatsRail.add': 'افزودن',
    'chatsRail.write': 'نوشتن',
    'chatsRail.addFriend': 'افزودن دوست',
    'chatsRail.newMessage': 'پیام جدید',
  },
  'sw': <String, String>{
    'chatsRail.add': 'Ongeza',
    'chatsRail.write': 'Andika',
    'chatsRail.addFriend': 'Ongeza rafiki',
    'chatsRail.newMessage': 'Ujumbe mpya',
  },
  'hi': <String, String>{
    'chatsRail.add': 'जोड़ें',
    'chatsRail.write': 'लिखें',
    'chatsRail.addFriend': 'मित्र जोड़ें',
    'chatsRail.newMessage': 'नया संदेश',
  },
  'bn': <String, String>{
    'chatsRail.add': 'যোগ করুন',
    'chatsRail.write': 'লিখুন',
    'chatsRail.addFriend': 'বন্ধু যোগ করুন',
    'chatsRail.newMessage': 'নতুন বার্তা',
  },
  'ur': <String, String>{
    'chatsRail.add': 'شامل کریں',
    'chatsRail.write': 'لکھیں',
    'chatsRail.addFriend': 'دوست شامل کریں',
    'chatsRail.newMessage': 'نیا پیغام',
  },
};
