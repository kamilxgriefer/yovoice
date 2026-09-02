import 'package:yovoice/core/localization/app_localizations.dart';

import '../data/models/achievement_definition.dart';

/// Presentation-only localization for achievement metadata.
///
/// Achievement identifiers and their English catalog values are persisted and
/// shared with older clients. Keeping Polish copy here lets the UI translate
/// those stable definitions without changing data, unlock rules or Firestore
/// values.
const Map<String, String> _polishAchievementTitles = {
  'messages_1': 'Pierwsze słowo',
  'messages_10': 'Przełamane lody',
  'messages_50': 'Początek rozmowy',
  'messages_100': 'Codzienny rozmówca',
  'messages_250': 'Twórca wiadomości',
  'messages_500': 'Społeczna iskra',
  'messages_1000': 'Tysiąc głosów',
  'messages_2500': 'Awangarda czatu',
  'messages_5000': 'Legenda czatu',
  'messages_10000': 'Głos tłumu',
  'followers_1': 'W centrum uwagi',
  'followers_10': 'Mały krąg',
  'followers_50': 'Wschodzący głos',
  'followers_100': 'Magnes na tłumy',
  'followers_250': 'Ulubieniec społeczności',
  'followers_500': 'Influencer głosu',
  'followers_1000': 'Osoba publiczna',
  'followers_2500': 'W świetle reflektorów',
  'followers_5000': 'Gwiazda sieci',
  'followers_10000': 'Ikona YO Voice',
  'voiceMinutes_1': 'Próba mikrofonu',
  'voiceMinutes_30': 'Pierwsza rozmowa',
  'voiceMinutes_120': 'Otwarty mikrofon',
  'voiceMinutes_300': 'Nocny rozmówca',
  'voiceMinutes_600': 'Bywalec głosowy',
  'voiceMinutes_1200': 'Na fali',
  'voiceMinutes_3000': 'Weteran głosu',
  'voiceMinutes_6000': 'Dźwiękowy podróżnik',
  'voiceMinutes_12000': 'Mistrz fal',
  'voiceMinutes_30000': 'Wieczny głos',
  'rooms_1': 'Otwarcie pokoju',
  'rooms_10': 'Punkt spotkań',
  'rooms_50': 'Założyciel pokoju',
  'rooms_100': 'Gospodarz spotkań',
  'rooms_250': 'Budowniczy społeczności',
  'rooms_500': 'Kurator pokoi',
  'rooms_1000': 'Architekt pokoi',
  'rooms_2500': 'Założyciel sieci',
  'rooms_5000': 'Budowniczy królestwa',
  'rooms_10000': 'Założyciel królestwa',
  'communities_1': 'Nowa twarz',
  'communities_10': 'Odkrywca',
  'communities_50': 'Wędrowiec społeczności',
  'communities_100': 'Lokalny głos',
  'communities_250': 'Łącznik',
  'communities_500': 'Sieciowiec',
  'communities_1000': 'Obywatel YO Voice',
  'communities_2500': 'Słuchacz świata',
  'communities_5000': 'Nomada społeczności',
  'communities_10000': 'Wszędzie naraz',
  'friends_1': 'Pierwsza więź',
  'friends_10': 'Przyjazna twarz',
  'friends_50': 'Krąg znajomych',
  'friends_100': 'Zaufany kontakt',
  'friends_250': 'Dusza towarzystwa',
  'friends_500': 'Kolekcjoner znajomości',
  'friends_1000': 'Społeczna kotwica',
  'friends_2500': 'Serce społeczności',
  'friends_5000': 'Przyjaciel wszystkich',
  'friends_10000': 'Wszyscy Cię znają',
  'reactions_1': 'Pierwsze brawa',
  'reactions_10': 'Dobre przyjęcie',
  'reactions_50': 'Ulubieniec tłumu',
  'reactions_100': 'Dobra energia',
  'reactions_250': 'Magnes na reakcje',
  'reactions_500': 'Ulubieniec fanów',
  'reactions_1000': 'Wybór publiczności',
  'reactions_2500': 'Owacje na stojąco',
  'reactions_5000': 'Ukochany głos',
  'reactions_10000': 'Powszechny aplauz',
  'hostMinutes_1': 'Pierwszy gospodarz',
  'hostMinutes_30': 'Przewodnik pokoju',
  'hostMinutes_120': 'Lider rozmowy',
  'hostMinutes_300': 'Kapitan głosu',
  'hostMinutes_600': 'Reżyser głosu',
  'hostMinutes_1200': 'Strażnik sceny',
  'hostMinutes_3000': 'Mistrz podcastu',
  'hostMinutes_6000': 'Dyrygent społeczności',
  'hostMinutes_12000': 'Wielki gospodarz',
  'hostMinutes_30000': 'Wielki strażnik głosu',
  'activeDays_1': 'Witaj w YO Voice',
  'activeDays_3': 'Powrót',
  'activeDays_7': 'Stały bywalec tygodnia',
  'activeDays_14': 'Dwutygodniowy płomień',
  'activeDays_30': 'Stały bywalec miesiąca',
  'activeDays_60': 'Oddany głos',
  'activeDays_100': 'Seria stu dni',
  'activeDays_180': 'Półroczny rytm',
  'activeDays_365': 'Rok głosu',
  'activeDays_730': 'Ponadczasowy członek',
  'moments_1': 'Pierwszy moment',
  'moments_10': 'Gawędziarz',
  'moments_50': 'Twórca momentów',
  'moments_100': 'Dziennik głosowy',
  'moments_250': 'Twórca audio',
  'moments_500': 'Kurator momentów',
  'moments_1000': 'Wydawca głosu',
  'moments_2500': 'Gwiazda momentów',
  'moments_5000': 'Gwiazda audio',
  'moments_10000': 'Legenda Voice Moments',
};

String localizedAchievementTitle(
  AppLocalizations copy,
  AchievementDefinition achievement,
) => copy.text(
  achievement.title,
  _polishAchievementTitles[achievement.id] ?? achievement.title,
);

String localizedAchievementDescription(
  AppLocalizations copy,
  AchievementDefinition achievement,
) => copy.text(
  achievement.description,
  _polishAchievementDescription(achievement),
);

String localizedAchievementRarity(
  AppLocalizations copy,
  AchievementRarity rarity,
) => switch (rarity) {
  AchievementRarity.common => copy.text('Common', 'Zwykłe'),
  AchievementRarity.uncommon => copy.text('Uncommon', 'Niezwykłe'),
  AchievementRarity.rare => copy.text('Rare', 'Rzadkie'),
  AchievementRarity.epic => copy.text('Epic', 'Epickie'),
  AchievementRarity.legendary => copy.text('Legendary', 'Legendarne'),
  AchievementRarity.mythic => copy.text('Mythic', 'Mityczne'),
};

String _polishAchievementDescription(AchievementDefinition achievement) {
  final count = achievement.threshold;

  return switch (achievement.metric) {
    'messages' =>
      'Napisz $count ${_polishForm(count, 'wiadomość', 'wiadomości', 'wiadomości')}.',
    'followers' =>
      'Zdobądź $count ${count == 1 ? 'obserwującego' : 'obserwujących'}.',
    'voiceMinutes' =>
      'Spędź $count ${_polishForm(count, 'minutę', 'minuty', 'minut')} na rozmowach głosowych.',
    'rooms' =>
      'Utwórz $count ${_polishForm(count, 'pokój', 'pokoje', 'pokojów')}.',
    'communities' =>
      'Dołącz do $count ${count == 1 ? 'społeczności' : 'społeczności'}.',
    'friends' =>
      'Nawiąż $count ${_polishForm(count, 'znajomość', 'znajomości', 'znajomości')}.',
    'reactions' =>
      'Otrzymaj $count ${_polishForm(count, 'reakcję', 'reakcje', 'reakcji')}.',
    'hostMinutes' =>
      'Prowadź pokoje głosowe przez $count ${_polishForm(count, 'minutę', 'minuty', 'minut')}.',
    'activeDays' =>
      'Korzystaj z YO Voice przez $count ${_polishForm(count, 'dzień', 'dni', 'dni')}.',
    'moments' =>
      'Opublikuj $count ${_polishForm(count, 'moment głosowy', 'momenty głosowe', 'momentów głosowych')}.',
    _ => achievement.description,
  };
}

String _polishForm(int count, String one, String few, String many) {
  if (count == 1) return one;
  final lastTwo = count % 100;
  final last = count % 10;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return few;
  }
  return many;
}
