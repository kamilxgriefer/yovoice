/// Copy for deleting and leaving a server (directory actions, the
/// management sheet's danger zone and the type-the-name confirmation).
///
/// Every translated locale carries every key, so none of these falls back to
/// English outside English and Polish.
const serverDeletionTranslationKeys = <String>[
  'Channels, messages and files will be removed, and members will lose access.',
  'Type the server name to confirm',
  'A conversation is live on this server. End it before deleting the server.',
  'End conversations and delete',
  'Danger zone',
];

const serverDeletionTranslations = <String, Map<String, String>>{
  'de': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanäle, Nachrichten und Dateien werden entfernt, und Mitglieder verlieren den Zugriff.',
    'Type the server name to confirm':
        'Gib zur Bestätigung den Servernamen ein',
    'A conversation is live on this server. End it before deleting the server.':
        'Auf diesem Server läuft gerade ein Gespräch. Beende es, bevor du den Server löschst.',
    'End conversations and delete': 'Gespräche beenden und löschen',
    'Danger zone': 'Gefahrenbereich',
  },
  'es': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Se eliminarán los canales, los mensajes y los archivos, y los miembros perderán el acceso.',
    'Type the server name to confirm':
        'Escribe el nombre del servidor para confirmar',
    'A conversation is live on this server. End it before deleting the server.':
        'Hay una conversación en directo en este servidor. Finalízala antes de eliminar el servidor.',
    'End conversations and delete': 'Finalizar conversaciones y eliminar',
    'Danger zone': 'Zona de peligro',
  },
  'pt': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Os canais, as mensagens e os ficheiros serão removidos, e os membros perderão o acesso.',
    'Type the server name to confirm':
        'Escreve o nome do servidor para confirmar',
    'A conversation is live on this server. End it before deleting the server.':
        'Há uma conversa em direto neste servidor. Termina-a antes de eliminares o servidor.',
    'End conversations and delete': 'Terminar conversas e eliminar',
    'Danger zone': 'Zona de perigo',
  },
  'pt_BR': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Os canais, as mensagens e os arquivos serão removidos, e os membros perderão o acesso.',
    'Type the server name to confirm':
        'Digite o nome do servidor para confirmar',
    'A conversation is live on this server. End it before deleting the server.':
        'Há uma conversa ao vivo neste servidor. Encerre-a antes de excluir o servidor.',
    'End conversations and delete': 'Encerrar conversas e excluir',
    'Danger zone': 'Zona de perigo',
  },
  'fr': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Les salons, les messages et les fichiers seront supprimés, et les membres perdront l’accès.',
    'Type the server name to confirm':
        'Saisissez le nom du serveur pour confirmer',
    'A conversation is live on this server. End it before deleting the server.':
        'Une conversation est en direct sur ce serveur. Terminez-la avant de supprimer le serveur.',
    'End conversations and delete': 'Terminer les conversations et supprimer',
    'Danger zone': 'Zone de danger',
  },
  'it': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Canali, messaggi e file verranno rimossi e i membri perderanno l’accesso.',
    'Type the server name to confirm':
        'Digita il nome del server per confermare',
    'A conversation is live on this server. End it before deleting the server.':
        'Su questo server è in corso una conversazione dal vivo. Terminala prima di eliminare il server.',
    'End conversations and delete': 'Termina le conversazioni ed elimina',
    'Danger zone': 'Zona pericolosa',
  },
  'nl': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanalen, berichten en bestanden worden verwijderd en leden verliezen de toegang.',
    'Type the server name to confirm': 'Typ de servernaam om te bevestigen',
    'A conversation is live on this server. End it before deleting the server.':
        'Er is een live gesprek op deze server. Beëindig het voordat je de server verwijdert.',
    'End conversations and delete': 'Gesprekken beëindigen en verwijderen',
    'Danger zone': 'Gevarenzone',
  },
  'ro': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Canalele, mesajele și fișierele vor fi eliminate, iar membrii vor pierde accesul.',
    'Type the server name to confirm':
        'Scrie numele serverului pentru a confirma',
    'A conversation is live on this server. End it before deleting the server.':
        'Pe acest server are loc o conversație live. Încheie-o înainte de a șterge serverul.',
    'End conversations and delete': 'Încheie conversațiile și șterge',
    'Danger zone': 'Zonă periculoasă',
  },
  'tr': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanallar, mesajlar ve dosyalar kaldırılacak ve üyeler erişimini kaybedecek.',
    'Type the server name to confirm': 'Onaylamak için sunucu adını yaz',
    'A conversation is live on this server. End it before deleting the server.':
        'Bu sunucuda canlı bir konuşma var. Sunucuyu silmeden önce konuşmayı bitir.',
    'End conversations and delete': 'Konuşmaları bitir ve sil',
    'Danger zone': 'Tehlikeli bölge',
  },
  'el': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Τα κανάλια, τα μηνύματα και τα αρχεία θα αφαιρεθούν και τα μέλη θα χάσουν την πρόσβαση.',
    'Type the server name to confirm':
        'Πληκτρολόγησε το όνομα του διακομιστή για επιβεβαίωση',
    'A conversation is live on this server. End it before deleting the server.':
        'Υπάρχει ζωντανή συζήτηση σε αυτόν τον διακομιστή. Τερμάτισέ τη πριν διαγράψεις τον διακομιστή.',
    'End conversations and delete': 'Τερματισμός συζητήσεων και διαγραφή',
    'Danger zone': 'Ζώνη κινδύνου',
  },
  'hu': {
    'Channels, messages and files will be removed, and members will lose access.':
        'A csatornák, üzenetek és fájlok törlődnek, a tagok pedig elveszítik a hozzáférést.',
    'Type the server name to confirm':
        'A megerősítéshez írd be a szerver nevét',
    'A conversation is live on this server. End it before deleting the server.':
        'Ezen a szerveren élő beszélgetés zajlik. Fejezd be, mielőtt törlöd a szervert.',
    'End conversations and delete': 'Beszélgetések befejezése és törlés',
    'Danger zone': 'Veszélyzóna',
  },
  'uk': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Канали, повідомлення та файли буде видалено, а учасники втратять доступ.',
    'Type the server name to confirm': 'Введіть назву сервера, щоб підтвердити',
    'A conversation is live on this server. End it before deleting the server.':
        'На цьому сервері триває розмова. Завершіть її, перш ніж видаляти сервер.',
    'End conversations and delete': 'Завершити розмови й видалити',
    'Danger zone': 'Небезпечна зона',
  },
  'ru': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Каналы, сообщения и файлы будут удалены, а участники потеряют доступ.',
    'Type the server name to confirm':
        'Введите название сервера для подтверждения',
    'A conversation is live on this server. End it before deleting the server.':
        'На этом сервере идёт разговор. Завершите его перед удалением сервера.',
    'End conversations and delete': 'Завершить разговоры и удалить',
    'Danger zone': 'Опасная зона',
  },
  'cs': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanály, zprávy a soubory budou odstraněny a členové ztratí přístup.',
    'Type the server name to confirm': 'Pro potvrzení zadejte název serveru',
    'A conversation is live on this server. End it before deleting the server.':
        'Na tomto serveru právě probíhá konverzace. Než server smažete, ukončete ji.',
    'End conversations and delete': 'Ukončit konverzace a smazat',
    'Danger zone': 'Nebezpečná zóna',
  },
  'sk': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanály, správy a súbory budú odstránené a členovia stratia prístup.',
    'Type the server name to confirm': 'Na potvrdenie zadajte názov servera',
    'A conversation is live on this server. End it before deleting the server.':
        'Na tomto serveri práve prebieha konverzácia. Pred odstránením servera ju ukončite.',
    'End conversations and delete': 'Ukončiť konverzácie a odstrániť',
    'Danger zone': 'Nebezpečná zóna',
  },
  'bg': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Каналите, съобщенията и файловете ще бъдат премахнати, а членовете ще загубят достъп.',
    'Type the server name to confirm':
        'Въведете името на сървъра за потвърждение',
    'A conversation is live on this server. End it before deleting the server.':
        'В този сървър тече разговор на живо. Прекратете го, преди да изтриете сървъра.',
    'End conversations and delete': 'Прекрати разговорите и изтрий',
    'Danger zone': 'Опасна зона',
  },
  'hr': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanali, poruke i datoteke bit će uklonjeni, a članovi će izgubiti pristup.',
    'Type the server name to confirm': 'Upišite naziv poslužitelja za potvrdu',
    'A conversation is live on this server. End it before deleting the server.':
        'Na ovom poslužitelju traje razgovor uživo. Završite ga prije brisanja poslužitelja.',
    'End conversations and delete': 'Završi razgovore i izbriši',
    'Danger zone': 'Opasna zona',
  },
  'sr': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Канали, поруке и датотеке биће уклоњени, а чланови ће изгубити приступ.',
    'Type the server name to confirm':
        'Унесите назив сервера да бисте потврдили',
    'A conversation is live on this server. End it before deleting the server.':
        'На овом серверу је у току разговор уживо. Завршите га пре брисања сервера.',
    'End conversations and delete': 'Заврши разговоре и избриши',
    'Danger zone': 'Опасна зона',
  },
  'sv': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanaler, meddelanden och filer tas bort, och medlemmarna förlorar åtkomsten.',
    'Type the server name to confirm': 'Skriv serverns namn för att bekräfta',
    'A conversation is live on this server. End it before deleting the server.':
        'Ett samtal pågår live på den här servern. Avsluta det innan du tar bort servern.',
    'End conversations and delete': 'Avsluta samtal och ta bort',
    'Danger zone': 'Farozon',
  },
  'da': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanaler, beskeder og filer fjernes, og medlemmerne mister adgangen.',
    'Type the server name to confirm': 'Skriv serverens navn for at bekræfte',
    'A conversation is live on this server. End it before deleting the server.':
        'Der er en live samtale på denne server. Afslut den, før du sletter serveren.',
    'End conversations and delete': 'Afslut samtaler og slet',
    'Danger zone': 'Farezone',
  },
  'nb': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanaler, meldinger og filer fjernes, og medlemmene mister tilgangen.',
    'Type the server name to confirm': 'Skriv inn servernavnet for å bekrefte',
    'A conversation is live on this server. End it before deleting the server.':
        'Det pågår en direkte samtale på denne serveren. Avslutt den før du sletter serveren.',
    'End conversations and delete': 'Avslutt samtaler og slett',
    'Danger zone': 'Faresone',
  },
  'fi': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanavat, viestit ja tiedostot poistetaan, ja jäsenet menettävät pääsyn.',
    'Type the server name to confirm':
        'Vahvista kirjoittamalla palvelimen nimi',
    'A conversation is live on this server. End it before deleting the server.':
        'Tällä palvelimella on käynnissä suora keskustelu. Lopeta se ennen palvelimen poistamista.',
    'End conversations and delete': 'Lopeta keskustelut ja poista',
    'Danger zone': 'Vaaravyöhyke',
  },
  'lt': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanalai, žinutės ir failai bus pašalinti, o nariai praras prieigą.',
    'Type the server name to confirm':
        'Norėdami patvirtinti, įveskite serverio pavadinimą',
    'A conversation is live on this server. End it before deleting the server.':
        'Šiame serveryje vyksta tiesioginis pokalbis. Prieš ištrindami serverį, jį užbaikite.',
    'End conversations and delete': 'Užbaigti pokalbius ir ištrinti',
    'Danger zone': 'Pavojinga zona',
  },
  'lv': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanāli, ziņas un faili tiks noņemti, un dalībnieki zaudēs piekļuvi.',
    'Type the server name to confirm':
        'Lai apstiprinātu, ierakstiet servera nosaukumu',
    'A conversation is live on this server. End it before deleting the server.':
        'Šajā serverī notiek tiešraides saruna. Pabeidziet to, pirms dzēšat serveri.',
    'End conversations and delete': 'Beigt sarunas un dzēst',
    'Danger zone': 'Bīstamā zona',
  },
  'et': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Kanalid, sõnumid ja failid eemaldatakse ning liikmed kaotavad juurdepääsu.',
    'Type the server name to confirm': 'Kinnitamiseks sisesta serveri nimi',
    'A conversation is live on this server. End it before deleting the server.':
        'Selles serveris käib otsevestlus. Lõpeta see enne serveri kustutamist.',
    'End conversations and delete': 'Lõpeta vestlused ja kustuta',
    'Danger zone': 'Ohutsoon',
  },
  'id': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Saluran, pesan, dan file akan dihapus, dan anggota akan kehilangan akses.',
    'Type the server name to confirm': 'Ketik nama server untuk mengonfirmasi',
    'A conversation is live on this server. End it before deleting the server.':
        'Ada percakapan langsung di server ini. Akhiri sebelum menghapus server.',
    'End conversations and delete': 'Akhiri percakapan dan hapus',
    'Danger zone': 'Zona bahaya',
  },
  'vi': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Các kênh, tin nhắn và tệp sẽ bị xóa, và thành viên sẽ mất quyền truy cập.',
    'Type the server name to confirm': 'Nhập tên máy chủ để xác nhận',
    'A conversation is live on this server. End it before deleting the server.':
        'Máy chủ này đang có cuộc trò chuyện trực tiếp. Hãy kết thúc trước khi xóa máy chủ.',
    'End conversations and delete': 'Kết thúc trò chuyện và xóa',
    'Danger zone': 'Vùng nguy hiểm',
  },
  'zh_CN': {
    'Channels, messages and files will be removed, and members will lose access.':
        '频道、消息和文件将被删除，成员将失去访问权限。',
    'Type the server name to confirm': '输入服务器名称以确认',
    'A conversation is live on this server. End it before deleting the server.':
        '此服务器上正在进行实时对话。请先结束对话再删除服务器。',
    'End conversations and delete': '结束对话并删除',
    'Danger zone': '危险区域',
  },
  'zh_TW': {
    'Channels, messages and files will be removed, and members will lose access.':
        '頻道、訊息和檔案將被移除，成員將失去存取權。',
    'Type the server name to confirm': '輸入伺服器名稱以確認',
    'A conversation is live on this server. End it before deleting the server.':
        '此伺服器上正在進行即時對話。請先結束對話再刪除伺服器。',
    'End conversations and delete': '結束對話並刪除',
    'Danger zone': '危險區域',
  },
  'ja': {
    'Channels, messages and files will be removed, and members will lose access.':
        'チャンネル、メッセージ、ファイルは削除され、メンバーはアクセスできなくなります。',
    'Type the server name to confirm': '確認のためサーバー名を入力してください',
    'A conversation is live on this server. End it before deleting the server.':
        'このサーバーでライブの会話が進行中です。サーバーを削除する前に会話を終了してください。',
    'End conversations and delete': '会話を終了して削除',
    'Danger zone': '危険な操作',
  },
  'ko': {
    'Channels, messages and files will be removed, and members will lose access.':
        '채널, 메시지, 파일이 삭제되고 멤버는 접근 권한을 잃게 됩니다.',
    'Type the server name to confirm': '확인하려면 서버 이름을 입력하세요',
    'A conversation is live on this server. End it before deleting the server.':
        '이 서버에서 라이브 대화가 진행 중입니다. 서버를 삭제하기 전에 대화를 종료하세요.',
    'End conversations and delete': '대화 종료 후 삭제',
    'Danger zone': '위험 구역',
  },
  'ar': {
    'Channels, messages and files will be removed, and members will lose access.':
        'ستُزال القنوات والرسائل والملفات، وسيفقد الأعضاء إمكانية الوصول.',
    'Type the server name to confirm': 'اكتب اسم الخادم للتأكيد',
    'A conversation is live on this server. End it before deleting the server.':
        'توجد محادثة مباشرة على هذا الخادم. أنهِها قبل حذف الخادم.',
    'End conversations and delete': 'إنهاء المحادثات والحذف',
    'Danger zone': 'منطقة الخطر',
  },
  'th': {
    'Channels, messages and files will be removed, and members will lose access.':
        'ช่อง ข้อความ และไฟล์จะถูกลบ และสมาชิกจะไม่สามารถเข้าถึงได้อีก',
    'Type the server name to confirm': 'พิมพ์ชื่อเซิร์ฟเวอร์เพื่อยืนยัน',
    'A conversation is live on this server. End it before deleting the server.':
        'มีการสนทนาสดอยู่ในเซิร์ฟเวอร์นี้ โปรดจบการสนทนาก่อนลบเซิร์ฟเวอร์',
    'End conversations and delete': 'จบการสนทนาและลบ',
    'Danger zone': 'โซนอันตราย',
  },
  'ms': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Saluran, mesej dan fail akan dialih keluar, dan ahli akan hilang akses.',
    'Type the server name to confirm': 'Taip nama pelayan untuk mengesahkan',
    'A conversation is live on this server. End it before deleting the server.':
        'Ada perbualan langsung dalam pelayan ini. Tamatkannya sebelum memadam pelayan.',
    'End conversations and delete': 'Tamatkan perbualan dan padam',
    'Danger zone': 'Zon bahaya',
  },
  'fil': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Aalisin ang mga channel, mensahe, at file, at mawawalan ng access ang mga miyembro.',
    'Type the server name to confirm':
        'I-type ang pangalan ng server para kumpirmahin',
    'A conversation is live on this server. End it before deleting the server.':
        'May live na usapan sa server na ito. Tapusin muna ito bago burahin ang server.',
    'End conversations and delete': 'Tapusin ang mga usapan at burahin',
    'Danger zone': 'Mapanganib na bahagi',
  },
  'he': {
    'Channels, messages and files will be removed, and members will lose access.':
        'הערוצים, ההודעות והקבצים יוסרו, והחברים יאבדו את הגישה.',
    'Type the server name to confirm': 'הקלידו את שם השרת לאישור',
    'A conversation is live on this server. End it before deleting the server.':
        'מתקיימת שיחה חיה בשרת הזה. סיימו אותה לפני מחיקת השרת.',
    'End conversations and delete': 'סיום השיחות ומחיקה',
    'Danger zone': 'אזור מסוכן',
  },
  'fa': {
    'Channels, messages and files will be removed, and members will lose access.':
        'کانال‌ها، پیام‌ها و فایل‌ها حذف می‌شوند و اعضا دسترسی خود را از دست می‌دهند.',
    'Type the server name to confirm': 'برای تأیید، نام سرور را وارد کنید',
    'A conversation is live on this server. End it before deleting the server.':
        'یک گفتگوی زنده در این سرور در جریان است. پیش از حذف سرور آن را پایان دهید.',
    'End conversations and delete': 'پایان گفتگوها و حذف',
    'Danger zone': 'منطقهٔ خطر',
  },
  'sw': {
    'Channels, messages and files will be removed, and members will lose access.':
        'Chaneli, ujumbe na faili zitaondolewa, na wanachama watapoteza ufikiaji.',
    'Type the server name to confirm': 'Andika jina la seva ili kuthibitisha',
    'A conversation is live on this server. End it before deleting the server.':
        'Kuna mazungumzo ya moja kwa moja kwenye seva hii. Yamalize kabla ya kufuta seva.',
    'End conversations and delete': 'Maliza mazungumzo na ufute',
    'Danger zone': 'Eneo la hatari',
  },
  'hi': {
    'Channels, messages and files will be removed, and members will lose access.':
        'चैनल, संदेश और फ़ाइलें हटा दी जाएँगी, और सदस्यों की पहुँच समाप्त हो जाएगी।',
    'Type the server name to confirm': 'पुष्टि करने के लिए सर्वर का नाम लिखें',
    'A conversation is live on this server. End it before deleting the server.':
        'इस सर्वर पर एक लाइव बातचीत चल रही है। सर्वर हटाने से पहले उसे समाप्त करें।',
    'End conversations and delete': 'बातचीत समाप्त करें और हटाएँ',
    'Danger zone': 'ख़तरनाक क्षेत्र',
  },
  'bn': {
    'Channels, messages and files will be removed, and members will lose access.':
        'চ্যানেল, বার্তা ও ফাইল সরিয়ে ফেলা হবে, এবং সদস্যরা অ্যাক্সেস হারাবেন।',
    'Type the server name to confirm': 'নিশ্চিত করতে সার্ভারের নাম লিখুন',
    'A conversation is live on this server. End it before deleting the server.':
        'এই সার্ভারে একটি লাইভ কথোপকথন চলছে। সার্ভার মোছার আগে সেটি শেষ করুন।',
    'End conversations and delete': 'কথোপকথন শেষ করে মুছুন',
    'Danger zone': 'বিপজ্জনক এলাকা',
  },
  'ur': {
    'Channels, messages and files will be removed, and members will lose access.':
        'چینلز، پیغامات اور فائلیں ہٹا دی جائیں گی، اور اراکین کی رسائی ختم ہو جائے گی۔',
    'Type the server name to confirm': 'تصدیق کے لیے سرور کا نام لکھیں',
    'A conversation is live on this server. End it before deleting the server.':
        'اس سرور پر ایک لائیو گفتگو جاری ہے۔ سرور حذف کرنے سے پہلے اسے ختم کریں۔',
    'End conversations and delete': 'گفتگو ختم کریں اور حذف کریں',
    'Danger zone': 'خطرے کا علاقہ',
  },
};
