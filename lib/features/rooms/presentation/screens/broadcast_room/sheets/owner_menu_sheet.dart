import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

class OwnerMenuSheet extends StatelessWidget {
  const OwnerMenuSheet({
    super.key,
    required this.onShare,
    required this.onParticipants,
    required this.onHands,
    required this.onSettings,
    required this.onAnalytics,
    required this.onEnd,
    required this.onDelete,
  });

  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onHands;
  final VoidCallback onSettings;
  final VoidCallback onAnalytics;
  final VoidCallback onEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.text('manage podcast', 'zarządzanie podcastem'),
            surfaceColor: BroadcastRoomColors.surface,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                      child: Text(
                        copy.text('Manage podcast', 'Zarządzaj podcastem'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  OwnerMenuItem(
                    icon: Icons.ios_share_rounded,
                    title: copy.text('Share room', 'Udostępnij pokój'),
                    subtitle: copy.text(
                      'Copy the invitation link or room ID',
                      'Skopiuj link z zaproszeniem lub identyfikator pokoju',
                    ),
                    onTap: onShare,
                  ),
                  OwnerMenuItem(
                    icon: Icons.groups_rounded,
                    title: copy.text('Participants', 'Uczestnicy'),
                    subtitle: copy.text(
                      'Manage stage, audience, mute and removal',
                      'Zarządzaj sceną, publicznością, wyciszeniem i usuwaniem',
                    ),
                    onTap: onParticipants,
                  ),
                  OwnerMenuItem(
                    icon: Icons.back_hand_rounded,
                    title: copy.text('Raised hands', 'Zgłoszenia do głosu'),
                    subtitle: copy.text(
                      'Review listeners requesting the stage',
                      'Sprawdź osoby proszące o wejście na scenę',
                    ),
                    onTap: onHands,
                  ),
                  OwnerMenuItem(
                    icon: Icons.settings_rounded,
                    title: copy.text('Podcast settings', 'Ustawienia podcastu'),
                    subtitle: copy.text(
                      'Edit the episode, format and stage requests',
                      'Edytuj odcinek, format i zgłoszenia na scenę',
                    ),
                    onTap: onSettings,
                  ),
                  OwnerMenuItem(
                    icon: Icons.analytics_rounded,
                    title: copy.text('Live analytics', 'Statystyki na żywo'),
                    subtitle: copy.text(
                      'View the current podcast snapshot',
                      'Zobacz bieżące statystyki podcastu',
                    ),
                    onTap: onAnalytics,
                  ),
                  const Divider(color: Color(0xFF3B171E), height: 22),
                  OwnerMenuItem(
                    icon: Icons.stop_circle_rounded,
                    title: copy.text('End podcast', 'Zakończ podcast'),
                    subtitle: copy.text(
                      'Disconnect everyone and close this podcast',
                      'Rozłącz wszystkich i zamknij podcast',
                    ),
                    onTap: onEnd,
                    destructive: true,
                  ),
                  OwnerMenuItem(
                    icon: Icons.delete_forever_rounded,
                    title: copy.text(
                      'Delete room permanently',
                      'Usuń pokój na stałe',
                    ),
                    subtitle: copy.text(
                      'Remove the room and its messages from YO Voice',
                      'Usuń pokój i jego wiadomości z YO Voice',
                    ),
                    onTap: onDelete,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerMenuItem extends StatelessWidget {
  const OwnerMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? BroadcastRoomColors.accentSoft : Colors.white;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFF45151F)
              : const Color(0xFF301219),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: BroadcastRoomColors.muted, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: color),
    );
  }
}
