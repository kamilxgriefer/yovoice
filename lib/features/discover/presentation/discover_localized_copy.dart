import 'package:yovoice/core/localization/app_localizations.dart';

String localizedDiscoverCategory(AppLocalizations copy, String category) {
  final normalized = category.trim().toLowerCase();
  return switch (normalized) {
    'all' => copy.text('All', 'Wszystkie'),
    'talk' => copy.text('Talk', 'Rozmowy'),
    'music' => copy.text('Music', 'Muzyka'),
    'gaming' => copy.text('Gaming', 'Gry'),
    'chill' => copy.text('Chill', 'Na luzie'),
    'study' => copy.text('Study', 'Nauka'),
    'business' => copy.text('Business', 'Biznes'),
    'broadcast' => copy.text('Broadcast', 'Podcast'),
    'tech' => copy.text('Tech', 'Technologia'),
    _ => category,
  };
}

String localizedDiscoverAudience(
  AppLocalizations copy, {
  required int count,
  required bool isBroadcast,
}) {
  if (!copy.isPolish) {
    return isBroadcast ? '$count listening' : '$count inside';
  }

  if (isBroadcast) {
    return count == 1 ? '1 słuchacz' : '$count słuchaczy';
  }

  return '$count ${_polishForm(count, 'osoba', 'osoby', 'osób')}';
}

String localizedLiveRoomCount(AppLocalizations copy, int count) {
  if (!copy.isPolish) {
    return '$count live ${count == 1 ? 'room' : 'rooms'}';
  }
  return '$count ${_polishForm(count, 'aktywny pokój', 'aktywne pokoje', 'aktywnych pokojów')}';
}

String localizedHostedBy(AppLocalizations copy, String hostName) =>
    copy.text('Hosted by $hostName', 'Prowadzi: $hostName');

String _polishForm(int count, String one, String few, String many) {
  if (count == 1) return one;
  final lastTwo = count % 100;
  final last = count % 10;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return few;
  }
  return many;
}
