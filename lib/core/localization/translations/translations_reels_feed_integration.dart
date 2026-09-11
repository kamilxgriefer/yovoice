/// Copy for the server-ranked feed's verified watched-content empty state.
const reelsFeedIntegrationKeys = <String>[
  "You’re all caught up",
  "Watch Reels again or come back later.",
  "Watch again",
];

final reelsFeedIntegrationTranslations = <String, Map<String, String>>{
  for (final entry in _values.entries)
    entry.key: Map<String, String>.unmodifiable(
      Map<String, String>.fromIterables(reelsFeedIntegrationKeys, entry.value),
    ),
};

const _values = <String, List<String>>{
  "de": <String>[
    "Du hast alles gesehen",
    "Sieh dir Reels erneut an oder schau später wieder vorbei.",
    "Erneut ansehen",
  ],
  "es": <String>[
    "Ya lo has visto todo",
    "Vuelve a ver los Reels o regresa más tarde.",
    "Volver a ver",
  ],
  "pt": <String>[
    "Já viste tudo",
    "Vê os Reels novamente ou volta mais tarde.",
    "Ver novamente",
  ],
  "pt_BR": <String>[
    "Você já viu tudo",
    "Assista aos Reels novamente ou volte mais tarde.",
    "Assistir novamente",
  ],
  "fr": <String>[
    "Vous avez tout vu",
    "Regardez à nouveau les Reels ou revenez plus tard.",
    "Revoir",
  ],
  "it": <String>[
    "Hai visto tutto",
    "Guarda di nuovo i Reels o torna più tardi.",
    "Guarda di nuovo",
  ],
  "uk": <String>[
    "Усе переглянуто",
    "Переглянь Reels знову або повернися пізніше.",
    "Переглянути знову",
  ],
  "ru": <String>[
    "Всё просмотрено",
    "Посмотри Reels снова или вернись позже.",
    "Посмотреть снова",
  ],
  "cs": <String>[
    "Už jsi viděl vše",
    "Přehraj si Reels znovu nebo se vrať později.",
    "Přehrát znovu",
  ],
  "sk": <String>[
    "Už máš všetko pozreté",
    "Pozri si Reels znova alebo sa vráť neskôr.",
    "Pozrieť znova",
  ],
  "bg": <String>[
    "Всичко е прегледано",
    "Гледай Reels отново или се върни по-късно.",
    "Гледай отново",
  ],
  "nl": <String>[
    "Je hebt alles gezien",
    "Bekijk Reels opnieuw of kom later terug.",
    "Opnieuw bekijken",
  ],
  "ro": <String>[
    "Ai văzut tot",
    "Urmărește Reels din nou sau revino mai târziu.",
    "Urmărește din nou",
  ],
  "tr": <String>[
    "Hepsini gördün",
    "Reels içeriklerini yeniden izle veya daha sonra geri gel.",
    "Yeniden izle",
  ],
  "el": <String>[
    "Τα είδες όλα",
    "Δες ξανά τα Reels ή επέστρεψε αργότερα.",
    "Δες ξανά",
  ],
  "hu": <String>[
    "Már mindent láttál",
    "Nézd meg újra a Reels tartalmakat, vagy térj vissza később.",
    "Megnézem újra",
  ],
  "hr": <String>[
    "Sve je pogledano",
    "Pogledaj Reels ponovno ili se vrati kasnije.",
    "Pogledaj ponovno",
  ],
  "sr": <String>[
    "Све је прегледано",
    "Погледај Reels поново или се врати касније.",
    "Погледај поново",
  ],
  "sv": <String>[
    "Du har sett allt",
    "Titta på Reels igen eller kom tillbaka senare.",
    "Titta igen",
  ],
  "da": <String>[
    "Du har set det hele",
    "Se Reels igen, eller kom tilbage senere.",
    "Se igen",
  ],
  "nb": <String>[
    "Du har sett alt",
    "Se Reels igjen, eller kom tilbake senere.",
    "Se igjen",
  ],
  "fi": <String>[
    "Olet nähnyt kaiken",
    "Katso Reels uudelleen tai palaa myöhemmin.",
    "Katso uudelleen",
  ],
  "lt": <String>[
    "Viską peržiūrėjai",
    "Žiūrėk Reels dar kartą arba grįžk vėliau.",
    "Žiūrėti dar kartą",
  ],
  "lv": <String>[
    "Viss ir noskatīts",
    "Skaties Reels vēlreiz vai atgriezies vēlāk.",
    "Skatīties vēlreiz",
  ],
  "et": <String>[
    "Kõik on vaadatud",
    "Vaata Reels uuesti või tule hiljem tagasi.",
    "Vaata uuesti",
  ],
  "id": <String>[
    "Kamu sudah melihat semuanya",
    "Tonton Reels lagi atau kembali nanti.",
    "Tonton lagi",
  ],
  "vi": <String>[
    "Bạn đã xem hết",
    "Xem lại Reels hoặc quay lại sau.",
    "Xem lại",
  ],
  "zh_CN": <String>["你已看完所有内容", "重看 Reels，或稍后再来。", "再次观看"],
  "zh_TW": <String>["你已看完所有內容", "重看 Reels，或稍後再來。", "再次觀看"],
  "ja": <String>["すべて視聴済みです", "Reelsをもう一度見るか、後でもう一度確認してください。", "もう一度見る"],
  "ko": <String>["모두 시청했어요", "Reels를 다시 보거나 나중에 다시 방문하세요.", "다시 보기"],
  "ar": <String>[
    "شاهدت كل المحتوى",
    "شاهد Reels مرة أخرى أو عُد لاحقًا.",
    "المشاهدة مجددًا",
  ],
  "hi": <String>[
    "आपने सब देख लिया है",
    "Reels फिर से देखें या बाद में लौटें।",
    "फिर से देखें",
  ],
  "bn": <String>[
    "সব দেখা হয়ে গেছে",
    "Reels আবার দেখুন অথবা পরে ফিরে আসুন।",
    "আবার দেখুন",
  ],
  "ur": <String>[
    "آپ نے سب دیکھ لیا ہے",
    "Reels دوبارہ دیکھیں یا بعد میں واپس آئیں۔",
    "دوبارہ دیکھیں",
  ],
  "th": <String>[
    "คุณดูครบแล้ว",
    "ดู Reels อีกครั้งหรือกลับมาใหม่ภายหลัง",
    "ดูอีกครั้ง",
  ],
  "ms": <String>[
    "Anda sudah menonton semuanya",
    "Tonton Reels semula atau kembali kemudian.",
    "Tonton semula",
  ],
  "fil": <String>[
    "Napanood mo na ang lahat",
    "Panoorin muli ang Reels o bumalik mamaya.",
    "Panoorin muli",
  ],
  "he": <String>[
    "צפית בכל התוכן",
    "אפשר לצפות שוב ב-Reels או לחזור מאוחר יותר.",
    "לצפות שוב",
  ],
  "fa": <String>[
    "همه را دیده‌اید",
    "Reels را دوباره ببینید یا بعداً برگردید.",
    "مشاهده دوباره",
  ],
  "sw": <String>[
    "Umeona kila kitu",
    "Tazama Reels tena au urudi baadaye.",
    "Tazama tena",
  ],
};
