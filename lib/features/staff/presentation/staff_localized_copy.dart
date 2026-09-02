import 'package:yovoice/core/localization/app_localizations.dart';

/// Presentation-only labels for server-owned Staff identifiers.
///
/// Role, action and status values remain unchanged in requests and audit data;
/// only their visible labels are translated at the UI boundary.
String localizedStaffRole(AppLocalizations copy, String role) => switch (role) {
  'user' => copy.text('User', 'Użytkownik'),
  'guideMaster' => copy.text('GUIDE MASTER', 'Główny przewodnik'),
  'support' => copy.text('SUPPORT', 'Wsparcie'),
  'auditor' => copy.text('AUDITOR', 'Audytor'),
  'moderator' => copy.text('MODERATOR', 'Moderator'),
  'superModerator' => copy.text('SUPER MODERATOR', 'Supermoderator'),
  'admin' => copy.text('ADMIN', 'Administrator'),
  'superAdmin' => copy.text('SUPER ADMIN', 'Superadministrator'),
  'owner' => copy.text('OWNER', 'Właściciel'),
  _ => role,
};

String localizedStaffStatus(AppLocalizations copy, String status) =>
    switch (status) {
      'ACTIVE' => copy.text('ACTIVE', 'AKTYWNE'),
      'BANNED' => copy.text('BANNED', 'ZABLOKOWANE'),
      'MUTED' => copy.text('MUTED', 'WYCISZONE'),
      'SUSPENDED' => copy.text('SUSPENDED', 'ZAWIESZONE'),
      'LIVE' => copy.text('LIVE', 'NA ŻYWO'),
      _ => status,
    };

String localizedStaffOfficialRole(AppLocalizations copy, String role) =>
    switch (role) {
      'user' => copy.text('USER', 'UŻYTKOWNIK'),
      'superAdmin' => copy.text(
        'OWNER · SUPER ADMIN',
        'WŁAŚCICIEL · SUPERADMINISTRATOR',
      ),
      _ => localizedStaffRole(copy, role),
    };

String localizedStaffAuditAction(AppLocalizations copy, String action) =>
    switch (action) {
      'warn_user' => copy.text('warn user', 'Ostrzeżenie użytkownika'),
      'communication_mute' => copy.text(
        'communication mute',
        'Wyciszenie komunikacji',
      ),
      'lift_communication_mute' => copy.text(
        'lift communication mute',
        'Zdjęcie wyciszenia komunikacji',
      ),
      'ban_user' => copy.text('ban user', 'Blokada użytkownika'),
      'unban_user' => copy.text('unban user', 'Zdjęcie blokady'),
      'assign_user_role' => copy.text('assign user role', 'Zmiana roli'),
      'security_alert_non_owner_super_admin' => copy.text(
        'security alert non owner super admin',
        'Alert bezpieczeństwa',
      ),
      'denied_sanction_attempt' => copy.text(
        'denied sanction attempt',
        'Odrzucona próba nałożenia sankcji',
      ),
      'bootstrap_super_admin' => copy.text(
        'bootstrap super admin',
        'Utworzenie konta superadministratora',
      ),
      'report_claim' => copy.text('report claim', 'Przejęcie zgłoszenia'),
      'report_release' => copy.text('report release', 'Zwolnienie zgłoszenia'),
      'report_resolve' => copy.text('report resolve', 'Rozwiązanie zgłoszenia'),
      'report_removeAndResolve' => copy.text(
        'report removeAndResolve',
        'Usunięcie treści i rozwiązanie zgłoszenia',
      ),
      'report_dismiss' => copy.text('report dismiss', 'Odrzucenie zgłoszenia'),
      'adminDeleteMessage' => copy.text(
        'adminDeleteMessage',
        'Usunięcie wiadomości',
      ),
      'delete_global_message' => copy.text(
        'delete global message',
        'Usunięcie wiadomości',
      ),
      'livekit_control_failure' => copy.text(
        'livekit control failure',
        'Błąd sterowania LiveKit',
      ),
      'suspend_room' => copy.text('suspend room', 'Zawieszenie pokoju'),
      'restore_room' => copy.text('restore room', 'Przywrócenie pokoju'),
      'force_end_room' => copy.text(
        'force end room',
        'Wymuszone zakończenie pokoju',
      ),
      'remove_room_participant' => copy.text(
        'remove room participant',
        'Usunięcie uczestnika z pokoju',
      ),
      'mute_room_participant' => copy.text(
        'mute room participant',
        'Wyciszenie uczestnika pokoju',
      ),
      'unmute_room_participant' => copy.text(
        'unmute room participant',
        'Cofnięcie wyciszenia uczestnika pokoju',
      ),
      'delete_room' => copy.text('delete room', 'Usunięcie pokoju'),
      'suspend_club' => copy.text('suspend club', 'Zawieszenie klubu'),
      'restore_club' => copy.text('restore club', 'Przywrócenie klubu'),
      'remove_club_member' => copy.text(
        'remove club member',
        'Usunięcie członka klubu',
      ),
      'ban_club_member' => copy.text(
        'ban club member',
        'Zablokowanie członka klubu',
      ),
      'unban_club_member' => copy.text(
        'unban club member',
        'Odblokowanie członka klubu',
      ),
      'transfer_club_ownership' => copy.text(
        'transfer club ownership',
        'Przeniesienie własności klubu',
      ),
      'delete_club' => copy.text('delete club', 'Usunięcie klubu'),
      'delete_club_self' => copy.text(
        'delete club self',
        'Usunięcie własnego klubu',
      ),
      _ => action.replaceAll('_', ' '),
    };

String localizedStaffParticipantCount(AppLocalizations copy, int count) =>
    copy.text(
      '$count in room',
      '$count ${_polishNoun(count, 'osoba', 'osoby', 'osób')} w pokoju',
    );

String localizedStaffResultCount(
  AppLocalizations copy,
  int count, {
  bool moreAvailable = false,
}) {
  final englishLabel = '$count ${count == 1 ? 'result' : 'results'}';
  final polishLabel =
      '$count ${_polishNoun(count, 'wynik', 'wyniki', 'wyników')}';
  return moreAvailable
      ? copy.text(
          '$englishLabel — more available',
          '$polishLabel — dostępne są kolejne',
        )
      : copy.text(englishLabel, polishLabel);
}

String _polishNoun(int value, String one, String few, String many) {
  final absolute = value.abs();
  final lastTwo = absolute % 100;
  if (absolute == 1) return one;
  if (lastTwo >= 12 && lastTwo <= 14) return many;
  return switch (absolute % 10) {
    2 || 3 || 4 => few,
    _ => many,
  };
}
