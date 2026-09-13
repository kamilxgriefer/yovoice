/// Copy introduced by the Reels voice comment (slice 5): the mic beside the
/// text composer, what it says while the deployed backend has not proven it
/// accepts voice comments, the confirmation after one is published, the
/// recovery line of a failed publish, and how a voice row and a voice report
/// target name themselves.
///
/// "Coming soon" on the mic is a STATE of one control, not the product's
/// general "Coming soon" chip, so it is keyed by context: the sentence has to
/// carry the action as well as the state, because the control is an icon and
/// an icon alone cannot say which thing is coming.
///
/// The clock inside "Voice comment \u00b7 {duration}" is a number ("0:12"), not
/// prose, and is substituted after localization. "Reply with voice" itself is
/// NOT here: it already exists in the Moments overview catalog and the mic
/// reuses that entry rather than minting a second spelling of one phrase.
///
/// Every selectable locale receives an explicit translation.
const reelsVoiceCommentTranslationKeys = <String>[
  'reels.voiceCommentComingSoon',
  'reels.voiceCommentPosted',
  'reels.voiceCommentKept',
  'Voice comment by {author}',
  'Voice comment by {author}, reported by you',
  'Voice comment · {duration}',
];

const reelsVoiceCommentTranslations = <String, Map<String, String>>{
  'de': {
    'reels.voiceCommentComingSoon': 'Mit Stimme antworten – demnächst',
    'reels.voiceCommentPosted': 'Sprachkommentar veröffentlicht.',
    'reels.voiceCommentKept':
        'Deine Aufnahme ist noch da – versuche es noch einmal.',
    'Voice comment by {author}': 'Sprachkommentar von {author}',
    'Voice comment by {author}, reported by you':
        'Sprachkommentar von {author}, von dir gemeldet',
    'Voice comment · {duration}': 'Sprachkommentar · {duration}',
  },
  'es': {
    'reels.voiceCommentComingSoon': 'Responder con voz: próximamente',
    'reels.voiceCommentPosted': 'Comentario de voz publicado.',
    'reels.voiceCommentKept': 'Tu grabación sigue aquí: inténtalo de nuevo.',
    'Voice comment by {author}': 'Comentario de voz de {author}',
    'Voice comment by {author}, reported by you':
        'Comentario de voz de {author}, denunciado por ti',
    'Voice comment · {duration}': 'Comentario de voz · {duration}',
  },
  'pt': {
    'reels.voiceCommentComingSoon': 'Responder com voz — em breve',
    'reels.voiceCommentPosted': 'Comentário de voz publicado.',
    'reels.voiceCommentKept':
        'A tua gravação continua aqui — tenta publicar novamente.',
    'Voice comment by {author}': 'Comentário de voz de {author}',
    'Voice comment by {author}, reported by you':
        'Comentário de voz de {author}, denunciado por ti',
    'Voice comment · {duration}': 'Comentário de voz · {duration}',
  },
  'pt_BR': {
    'reels.voiceCommentComingSoon': 'Responder com voz — em breve',
    'reels.voiceCommentPosted': 'Comentário de voz publicado.',
    'reels.voiceCommentKept':
        'Sua gravação continua aqui — tente publicar novamente.',
    'Voice comment by {author}': 'Comentário de voz de {author}',
    'Voice comment by {author}, reported by you':
        'Comentário de voz de {author}, denunciado por você',
    'Voice comment · {duration}': 'Comentário de voz · {duration}',
  },
  'fr': {
    'reels.voiceCommentComingSoon': 'Répondre par la voix — bientôt disponible',
    'reels.voiceCommentPosted': 'Commentaire vocal publié.',
    'reels.voiceCommentKept':
        'Votre enregistrement est toujours là — réessayez de le publier.',
    'Voice comment by {author}': 'Commentaire vocal de {author}',
    'Voice comment by {author}, reported by you':
        'Commentaire vocal de {author}, signalé par vous',
    'Voice comment · {duration}': 'Commentaire vocal · {duration}',
  },
  'it': {
    'reels.voiceCommentComingSoon': 'Rispondi con la voce — in arrivo',
    'reels.voiceCommentPosted': 'Commento vocale pubblicato.',
    'reels.voiceCommentKept':
        'La tua registrazione è ancora qui — riprova a pubblicarla.',
    'Voice comment by {author}': 'Commento vocale di {author}',
    'Voice comment by {author}, reported by you':
        'Commento vocale di {author}, segnalato da te',
    'Voice comment · {duration}': 'Commento vocale · {duration}',
  },
  'uk': {
    'reels.voiceCommentComingSoon': 'Відповісти голосом — незабаром',
    'reels.voiceCommentPosted': 'Голосовий коментар опубліковано.',
    'reels.voiceCommentKept':
        'Ваш запис збережено — спробуйте опублікувати ще раз.',
    'Voice comment by {author}': 'Голосовий коментар від {author}',
    'Voice comment by {author}, reported by you':
        'Голосовий коментар від {author}, ви поскаржилися',
    'Voice comment · {duration}': 'Голосовий коментар · {duration}',
  },
  'ru': {
    'reels.voiceCommentComingSoon': 'Ответить голосом — скоро',
    'reels.voiceCommentPosted': 'Голосовой комментарий опубликован.',
    'reels.voiceCommentKept':
        'Запись сохранена — попробуйте опубликовать ещё раз.',
    'Voice comment by {author}': 'Голосовой комментарий от {author}',
    'Voice comment by {author}, reported by you':
        'Голосовой комментарий от {author}, вы пожаловались',
    'Voice comment · {duration}': 'Голосовой комментарий · {duration}',
  },
  'cs': {
    'reels.voiceCommentComingSoon': 'Odpovědět hlasem – již brzy',
    'reels.voiceCommentPosted': 'Hlasový komentář byl zveřejněn.',
    'reels.voiceCommentKept':
        'Nahrávka je stále tady – zkuste ji zveřejnit znovu.',
    'Voice comment by {author}': 'Hlasový komentář od {author}',
    'Voice comment by {author}, reported by you':
        'Hlasový komentář od {author}, nahlášeno vámi',
    'Voice comment · {duration}': 'Hlasový komentář · {duration}',
  },
  'sk': {
    'reels.voiceCommentComingSoon': 'Odpovedať hlasom – už čoskoro',
    'reels.voiceCommentPosted': 'Hlasový komentár bol zverejnený.',
    'reels.voiceCommentKept':
        'Nahrávka je stále tu – skúste ju zverejniť znova.',
    'Voice comment by {author}': 'Hlasový komentár od {author}',
    'Voice comment by {author}, reported by you':
        'Hlasový komentár od {author}, nahlásené vami',
    'Voice comment · {duration}': 'Hlasový komentár · {duration}',
  },
  'bg': {
    'reels.voiceCommentComingSoon': 'Отговор с глас — очаквайте скоро',
    'reels.voiceCommentPosted': 'Гласовият коментар е публикуван.',
    'reels.voiceCommentKept':
        'Записът ви е запазен — опитайте да го публикувате отново.',
    'Voice comment by {author}': 'Гласов коментар от {author}',
    'Voice comment by {author}, reported by you':
        'Гласов коментар от {author}, докладван от вас',
    'Voice comment · {duration}': 'Гласов коментар · {duration}',
  },
  'nl': {
    'reels.voiceCommentComingSoon': 'Antwoorden met je stem — binnenkort',
    'reels.voiceCommentPosted': 'Spraakreactie geplaatst.',
    'reels.voiceCommentKept':
        'Je opname is er nog — probeer opnieuw te plaatsen.',
    'Voice comment by {author}': 'Spraakreactie van {author}',
    'Voice comment by {author}, reported by you':
        'Spraakreactie van {author}, door jou gerapporteerd',
    'Voice comment · {duration}': 'Spraakreactie · {duration}',
  },
  'ro': {
    'reels.voiceCommentComingSoon': 'Răspunde prin voce — în curând',
    'reels.voiceCommentPosted': 'Comentariul vocal a fost publicat.',
    'reels.voiceCommentKept':
        'Înregistrarea ta este încă aici — încearcă să o publici din nou.',
    'Voice comment by {author}': 'Comentariu vocal de la {author}',
    'Voice comment by {author}, reported by you':
        'Comentariu vocal de la {author}, raportat de tine',
    'Voice comment · {duration}': 'Comentariu vocal · {duration}',
  },
  'tr': {
    'reels.voiceCommentComingSoon': 'Sesle yanıtla — çok yakında',
    'reels.voiceCommentPosted': 'Sesli yorum paylaşıldı.',
    'reels.voiceCommentKept': 'Kaydın hâlâ burada — tekrar paylaşmayı dene.',
    'Voice comment by {author}': '{author} adlı kişinin sesli yorumu',
    'Voice comment by {author}, reported by you':
        '{author} adlı kişinin sesli yorumu, senin tarafından bildirildi',
    'Voice comment · {duration}': 'Sesli yorum · {duration}',
  },
  'el': {
    'reels.voiceCommentComingSoon': 'Απάντηση με φωνή — προσεχώς',
    'reels.voiceCommentPosted': 'Το φωνητικό σχόλιο δημοσιεύτηκε.',
    'reels.voiceCommentKept':
        'Η ηχογράφησή σου είναι ακόμα εδώ — δοκίμασε ξανά.',
    'Voice comment by {author}': 'Φωνητικό σχόλιο από {author}',
    'Voice comment by {author}, reported by you':
        'Φωνητικό σχόλιο από {author}, αναφέρθηκε από εσένα',
    'Voice comment · {duration}': 'Φωνητικό σχόλιο · {duration}',
  },
  'hu': {
    'reels.voiceCommentComingSoon': 'Válasz hanggal – hamarosan',
    'reels.voiceCommentPosted': 'A hangkommentet közzétettük.',
    'reels.voiceCommentKept':
        'A felvételed megvan – próbáld meg újra közzétenni.',
    'Voice comment by {author}': '{author} hangkommentje',
    'Voice comment by {author}, reported by you':
        '{author} hangkommentje, általad jelentve',
    'Voice comment · {duration}': 'Hangkomment · {duration}',
  },
  'hr': {
    'reels.voiceCommentComingSoon': 'Odgovori glasom – uskoro',
    'reels.voiceCommentPosted': 'Glasovni komentar je objavljen.',
    'reels.voiceCommentKept':
        'Tvoja snimka je još tu – pokušaj je ponovno objaviti.',
    'Voice comment by {author}': 'Glasovni komentar korisnika {author}',
    'Voice comment by {author}, reported by you':
        'Glasovni komentar korisnika {author}, prijavljen od tebe',
    'Voice comment · {duration}': 'Glasovni komentar · {duration}',
  },
  'sr': {
    'reels.voiceCommentComingSoon': 'Одговори гласом – ускоро',
    'reels.voiceCommentPosted': 'Гласовни коментар је објављен.',
    'reels.voiceCommentKept':
        'Твој снимак је још овде – покушај поново да га објавиш.',
    'Voice comment by {author}': 'Гласовни коментар корисника {author}',
    'Voice comment by {author}, reported by you':
        'Гласовни коментар корисника {author}, пријављен од тебе',
    'Voice comment · {duration}': 'Гласовни коментар · {duration}',
  },
  'sv': {
    'reels.voiceCommentComingSoon': 'Svara med rösten – kommer snart',
    'reels.voiceCommentPosted': 'Röstkommentaren har publicerats.',
    'reels.voiceCommentKept':
        'Din inspelning finns kvar – försök publicera igen.',
    'Voice comment by {author}': 'Röstkommentar från {author}',
    'Voice comment by {author}, reported by you':
        'Röstkommentar från {author}, anmäld av dig',
    'Voice comment · {duration}': 'Röstkommentar · {duration}',
  },
  'da': {
    'reels.voiceCommentComingSoon': 'Svar med stemmen – kommer snart',
    'reels.voiceCommentPosted': 'Stemmekommentaren er slået op.',
    'reels.voiceCommentKept':
        'Din optagelse er her stadig – prøv at slå den op igen.',
    'Voice comment by {author}': 'Stemmekommentar fra {author}',
    'Voice comment by {author}, reported by you':
        'Stemmekommentar fra {author}, anmeldt af dig',
    'Voice comment · {duration}': 'Stemmekommentar · {duration}',
  },
  'nb': {
    'reels.voiceCommentComingSoon': 'Svar med stemmen – kommer snart',
    'reels.voiceCommentPosted': 'Stemmekommentaren er publisert.',
    'reels.voiceCommentKept':
        'Opptaket ditt er her fortsatt – prøv å publisere på nytt.',
    'Voice comment by {author}': 'Stemmekommentar fra {author}',
    'Voice comment by {author}, reported by you':
        'Stemmekommentar fra {author}, rapportert av deg',
    'Voice comment · {duration}': 'Stemmekommentar · {duration}',
  },
  'fi': {
    'reels.voiceCommentComingSoon': 'Vastaa äänellä – tulossa pian',
    'reels.voiceCommentPosted': 'Äänikommentti julkaistiin.',
    'reels.voiceCommentKept':
        'Tallenteesi on yhä tallessa – yritä julkaista uudelleen.',
    'Voice comment by {author}': 'Äänikommentti käyttäjältä {author}',
    'Voice comment by {author}, reported by you':
        'Äänikommentti käyttäjältä {author}, ilmoitit siitä',
    'Voice comment · {duration}': 'Äänikommentti · {duration}',
  },
  'lt': {
    'reels.voiceCommentComingSoon': 'Atsakyti balsu – netrukus',
    'reels.voiceCommentPosted': 'Balso komentaras paskelbtas.',
    'reels.voiceCommentKept':
        'Jūsų įrašas išsaugotas – bandykite paskelbti dar kartą.',
    'Voice comment by {author}': 'Balso komentaras nuo {author}',
    'Voice comment by {author}, reported by you':
        'Balso komentaras nuo {author}, jūsų praneštas',
    'Voice comment · {duration}': 'Balso komentaras · {duration}',
  },
  'lv': {
    'reels.voiceCommentComingSoon': 'Atbildēt ar balsi — drīzumā',
    'reels.voiceCommentPosted': 'Balss komentārs ir publicēts.',
    'reels.voiceCommentKept':
        'Tavs ieraksts ir saglabāts — mēĢini publicēt vēlreiz.',
    'Voice comment by {author}': 'Balss komentārs no {author}',
    'Voice comment by {author}, reported by you':
        'Balss komentārs no {author}, tu par to ziņoji',
    'Voice comment · {duration}': 'Balss komentārs · {duration}',
  },
  'et': {
    'reels.voiceCommentComingSoon': 'Vasta häälega – tulekul',
    'reels.voiceCommentPosted': 'Häälkommentaar avaldati.',
    'reels.voiceCommentKept':
        'Sinu salvestis on alles – proovi uuesti avaldada.',
    'Voice comment by {author}': 'Häälkommentaar kasutajalt {author}',
    'Voice comment by {author}, reported by you':
        'Häälkommentaar kasutajalt {author}, sinu teavitatud',
    'Voice comment · {duration}': 'Häälkommentaar · {duration}',
  },
  'id': {
    'reels.voiceCommentComingSoon': 'Balas dengan suara — segera hadir',
    'reels.voiceCommentPosted': 'Komentar suara telah diposting.',
    'reels.voiceCommentKept': 'Rekamanmu masih ada — coba posting lagi.',
    'Voice comment by {author}': 'Komentar suara dari {author}',
    'Voice comment by {author}, reported by you':
        'Komentar suara dari {author}, dilaporkan olehmu',
    'Voice comment · {duration}': 'Komentar suara · {duration}',
  },
  'vi': {
    'reels.voiceCommentComingSoon': 'Trả lời bằng giọng nói — sắp ra mắt',
    'reels.voiceCommentPosted': 'Đã đăng bình luận thoại.',
    'reels.voiceCommentKept': 'Bản ghi của bạn vẫn còn — hãy thử đăng lại.',
    'Voice comment by {author}': 'Bình luận thoại của {author}',
    'Voice comment by {author}, reported by you':
        'Bình luận thoại của {author}, bạn đã báo cáo',
    'Voice comment · {duration}': 'Bình luận thoại · {duration}',
  },
  'zh_CN': {
    'reels.voiceCommentComingSoon': '语音回复即将推出',
    'reels.voiceCommentPosted': '语音评论已发布。',
    'reels.voiceCommentKept': '录音仍在——请再试一次发布。',
    'Voice comment by {author}': '{author} 的语音评论',
    'Voice comment by {author}, reported by you': '{author} 的语音评论，已被你举报',
    'Voice comment · {duration}': '语音评论 · {duration}',
  },
  'zh_TW': {
    'reels.voiceCommentComingSoon': '語音回覆即將推出',
    'reels.voiceCommentPosted': '語音留言已發布。',
    'reels.voiceCommentKept': '你的錄音仍在——請再試一次發布。',
    'Voice comment by {author}': '{author} 的語音留言',
    'Voice comment by {author}, reported by you': '{author} 的語音留言，已被你檢舉',
    'Voice comment · {duration}': '語音留言 · {duration}',
  },
  'ja': {
    'reels.voiceCommentComingSoon': '音声で返信 — 近日公開',
    'reels.voiceCommentPosted': '音声コメントを投稿しました。',
    'reels.voiceCommentKept': '録音は残っています。もう一度投稿してみてください。',
    'Voice comment by {author}': '{author} さんの音声コメント',
    'Voice comment by {author}, reported by you':
        '{author} さんの音声コメント（あなたが報告済み）',
    'Voice comment · {duration}': '音声コメント · {duration}',
  },
  'ko': {
    'reels.voiceCommentComingSoon': '음성으로 답글 — 곳 제공 예정',
    'reels.voiceCommentPosted': '음성 댓글을 게시했습니다.',
    'reels.voiceCommentKept': '녹음은 그대로 있습니다. 다시 게시해 보세요.',
    'Voice comment by {author}': '{author}님의 음성 댓글',
    'Voice comment by {author}, reported by you': '{author}님의 음성 댓글, 내가 신고함',
    'Voice comment · {duration}': '음성 댓글 · {duration}',
  },
  'ar': {
    'reels.voiceCommentComingSoon': 'الرد بالصوت — قريبًا',
    'reels.voiceCommentPosted': 'تم نشر التعليق الصوتي.',
    'reels.voiceCommentKept': 'تسجيلك ما زال موجودًا — حاول نشره مرة أخرى.',
    'Voice comment by {author}': 'تعليق صوتي من {author}',
    'Voice comment by {author}, reported by you':
        'تعليق صوتي من {author}، أبلغت عنه',
    'Voice comment · {duration}': 'تعليق صوتي · {duration}',
  },
  'hi': {
    'reels.voiceCommentComingSoon': 'आव़ाज़ से जवाब दें — जल्द आ रहा है',
    'reels.voiceCommentPosted': 'वॉइस टिप्पणी पोस्ट हो गई।',
    'reels.voiceCommentKept':
        'आपकी रिकॉर्डिंग सुरक्षित है — फिर से पोस्ट करने की कोशिश करें।',
    'Voice comment by {author}': '{author} की वॉइस टिप्पणी',
    'Voice comment by {author}, reported by you':
        '{author} की वॉइस टिप्पणी, आपने रिपोर्ट की',
    'Voice comment · {duration}': 'वॉइस टिप्पणी · {duration}',
  },
  'bn': {
    'reels.voiceCommentComingSoon': 'কণ্ঠে উত্তর — শীঘ্রই আসছে',
    'reels.voiceCommentPosted': 'ভয়স মন্তব্য পোস্ট করা হয়েছে।',
    'reels.voiceCommentKept':
        'আপনার রেকর্ডিং এখনও আছে — আবার পোস্ট করার চেষ্টা করুন।',
    'Voice comment by {author}': '{author}-এর ভয়স মন্তব্য',
    'Voice comment by {author}, reported by you':
        '{author}-এর ভয়স মন্তব্য, আপনি রিপোর্ট করেছেন',
    'Voice comment · {duration}': 'ভয়স মন্তব্য · {duration}',
  },
  'ur': {
    'reels.voiceCommentComingSoon': 'آواز سے جواب دیں — جلد آ رہا ہے',
    'reels.voiceCommentPosted': 'صوتی تبصرہ پوسٹ ہو گیا۔',
    'reels.voiceCommentKept':
        'آپ کی ریکارڈنگ محفوظ ہے — دوبارہ پوسٹ کرنے کی کوشش کریں۔',
    'Voice comment by {author}': '{author} کا صوتی تبصرہ',
    'Voice comment by {author}, reported by you':
        '{author} کا صوتی تبصرہ، آپ نے رپورٹ کیا',
    'Voice comment · {duration}': 'صوتی تبصرہ · {duration}',
  },
  'th': {
    'reels.voiceCommentComingSoon': 'ตอบด้วยเสียง — เร็วๆ นี้',
    'reels.voiceCommentPosted': 'โพสต์ความคิดเห็นด้วยเสียงแล้ว',
    'reels.voiceCommentKept': 'การบันทึกของคุณยังอยู่ — ลองโพสต์อีกครั้ง',
    'Voice comment by {author}': 'ความคิดเห็นด้วยเสียงจาก {author}',
    'Voice comment by {author}, reported by you':
        'ความคิดเห็นด้วยเสียงจาก {author} ที่คุณรายงาน',
    'Voice comment · {duration}': 'ความคิดเห็นด้วยเสียง · {duration}',
  },
  'ms': {
    'reels.voiceCommentComingSoon': 'Balas dengan suara — akan datang',
    'reels.voiceCommentPosted': 'Komen suara telah disiarkan.',
    'reels.voiceCommentKept': 'Rakaman anda masih ada — cuba siarkan semula.',
    'Voice comment by {author}': 'Komen suara daripada {author}',
    'Voice comment by {author}, reported by you':
        'Komen suara daripada {author}, dilaporkan oleh anda',
    'Voice comment · {duration}': 'Komen suara · {duration}',
  },
  'fil': {
    'reels.voiceCommentComingSoon': 'Sumagot gamit ang boses — malapit na',
    'reels.voiceCommentPosted': 'Nai-post na ang komento sa boses.',
    'reels.voiceCommentKept':
        'Nandiyan pa ang iyong recording — subukang i-post muli.',
    'Voice comment by {author}': 'Komento sa boses ni {author}',
    'Voice comment by {author}, reported by you':
        'Komento sa boses ni {author}, iniulat mo',
    'Voice comment · {duration}': 'Komento sa boses · {duration}',
  },
  'he': {
    'reels.voiceCommentComingSoon': 'תגובה בקול — בקרוב',
    'reels.voiceCommentPosted': 'תגובת הקול פורסמה.',
    'reels.voiceCommentKept': 'ההקלטה שלך עדיין כאן — נסה לפרסם שוב.',
    'Voice comment by {author}': 'תגובת קול מאת {author}',
    'Voice comment by {author}, reported by you':
        'תגובת קול מאת {author}, דווחה על ידך',
    'Voice comment · {duration}': 'תגובת קול · {duration}',
  },
  'fa': {
    'reels.voiceCommentComingSoon': 'پاسخ با صدا — به زودی',
    'reels.voiceCommentPosted': 'نظر صوتی منتشر شد.',
    'reels.voiceCommentKept': 'ضبط شما هنوز اینجاست — دوباره تلاش کنید.',
    'Voice comment by {author}': 'نظر صوتی از {author}',
    'Voice comment by {author}, reported by you':
        'نظر صوتی از {author}، توسط شما گزارش شد',
    'Voice comment · {duration}': 'نظر صوتی · {duration}',
  },
  'sw': {
    'reels.voiceCommentComingSoon': 'Jibu kwa sauti — inakuja hivi karibuni',
    'reels.voiceCommentPosted': 'Maoni ya sauti yamechapishwa.',
    'reels.voiceCommentKept': 'Rekodi yako bado ipo — jaribu kuchapisha tena.',
    'Voice comment by {author}': 'Maoni ya sauti kutoka kwa {author}',
    'Voice comment by {author}, reported by you':
        'Maoni ya sauti kutoka kwa {author}, uliyoripoti',
    'Voice comment · {duration}': 'Maoni ya sauti · {duration}',
  },
};
