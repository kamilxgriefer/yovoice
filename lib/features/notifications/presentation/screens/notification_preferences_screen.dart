import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class _PreferenceGroup {
  const _PreferenceGroup({required this.title, required this.types});

  final String title;
  final List<NotificationType> types;
}

const _kPreferenceGroups = [
  _PreferenceGroup(
    title: 'Friends & follows',
    types: [
      NotificationType.friendRequest,
      NotificationType.friendAccepted,
      NotificationType.follow,
    ],
  ),
  _PreferenceGroup(
    title: 'Clubs',
    types: [NotificationType.clubInvite, NotificationType.clubInviteAccepted],
  ),
  _PreferenceGroup(
    title: 'Rooms',
    types: [
      NotificationType.roomInvite,
      NotificationType.broadcastInvite,
      NotificationType.liveStarted,
    ],
  ),
  _PreferenceGroup(
    title: 'Calls',
    types: [NotificationType.directCall, NotificationType.missedCall],
  ),
  _PreferenceGroup(
    title: 'Messages',
    types: [
      NotificationType.directMessage,
      NotificationType.mention,
      NotificationType.reply,
    ],
  ),
];

String _groupTitle(AppLocalizations copy, String title) => switch (title) {
  'Friends & follows' => copy.text(
    'Friends & follows',
    'Znajomi i obserwowani',
  ),
  'Clubs' => copy.text('Clubs', 'Kluby'),
  'Rooms' => copy.text('Rooms', 'Pokoje'),
  'Calls' => copy.text('Calls', 'Połączenia'),
  'Messages' => copy.text('Messages', 'Wiadomości'),
  _ => title,
};

String _labelFor(AppLocalizations copy, NotificationType type) {
  switch (type) {
    case NotificationType.friendRequest:
      return copy.text('Friend requests', 'Zaproszenia do znajomych');
    case NotificationType.friendAccepted:
      return copy.text(
        'Friend request accepted',
        'Przyjęte zaproszenie do znajomych',
      );
    case NotificationType.follow:
      return copy.text('New followers', 'Nowi obserwujący');
    case NotificationType.clubInvite:
      return copy.text('Club invitations', 'Zaproszenia do klubów');
    case NotificationType.clubInviteAccepted:
      return copy.text(
        'Club invitation accepted',
        'Przyjęte zaproszenie do klubu',
      );
    case NotificationType.roomInvite:
      return copy.text('Room invitations', 'Zaproszenia do pokoi');
    case NotificationType.broadcastInvite:
      return copy.text('Podcast invitations', 'Zaproszenia do podcastów');
    case NotificationType.liveStarted:
      return copy.text(
        'People you follow go live',
        'Obserwowane osoby rozpoczynają transmisję',
      );
    case NotificationType.directMessage:
      return copy.text('Direct messages', 'Wiadomości bezpośrednie');
    case NotificationType.directCall:
      return copy.text('Incoming voice calls', 'Przychodzące połączenia');
    case NotificationType.missedCall:
      return copy.text('Missed calls', 'Nieodebrane połączenia');
    case NotificationType.mention:
      return copy.text('Mentions', 'Wzmianki');
    case NotificationType.reply:
      return copy.text('Replies', 'Odpowiedzi');
    case NotificationType.achievementUnlocked:
      return copy.text('Achievements', 'Osiągnięcia');
    case NotificationType.moderation:
      return copy.text('Moderation', 'Moderacja');
    case NotificationType.system:
      return copy.text('System announcements', 'Komunikaty systemowe');
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({
    this.isRootTab = false,
    this.notificationService,
    super.key,
  });

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  /// Injectable so the real preferences surface can be exercised without a
  /// process-global Firebase instance in widget tests.
  final NotificationService? notificationService;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();
  late final Stream<Map<String, bool>> _preferencesStream;

  final Set<NotificationType> _pending = <NotificationType>{};

  @override
  void initState() {
    super.initState();
    _preferencesStream = _notificationService.watchPreferences();
  }

  Future<void> _toggle(NotificationType type, bool enabled) async {
    if (_pending.contains(type)) return;
    setState(() => _pending.add(type));
    try {
      await _notificationService.setPreference(type, enabled);
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: copy.text(
                  'Could not update this notification setting.',
                  'Nie udało się zmienić ustawienia powiadomień.',
                ),
                copy: copy,
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
    } finally {
      if (mounted) setState(() => _pending.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                child: Row(
                  children: [
                    if (!widget.isRootTab) ...[
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: copy.text('Back', 'Wróć'),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: palette.textPrimary,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        copy.text(
                          'Notification preferences',
                          'Ustawienia powiadomień',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<Map<String, bool>>(
                  stream: _preferencesStream,
                  builder: (context, snapshot) {
                    final preferences = snapshot.data ?? const <String, bool>{};
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
                      children: [
                        Text(
                          copy.text(
                            'Choose which activity sends you a push '
                                'notification. In-app activity is always recorded '
                                'in your notification center regardless of these '
                                'settings.',
                            'Wybierz, o jakiej aktywności chcesz otrzymywać '
                                'powiadomienia push. Aktywność w aplikacji zawsze '
                                'pozostaje widoczna w centrum powiadomień.',
                          ),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final group in _kPreferenceGroups) ...[
                          Text(
                            _groupTitle(copy, group.title),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: palette.border),
                            ),
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < group.types.length;
                                  index++
                                ) ...[
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: palette.border,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                  _PreferenceRow(
                                    label: _labelFor(copy, group.types[index]),
                                    // Preferences are opt-out: an absent key
                                    // means enabled, matching
                                    // onNotificationCreated's default in
                                    // functions/notifications/push.js.
                                    value:
                                        preferences[group.types[index].name] !=
                                        false,
                                    isPending: _pending.contains(
                                      group.types[index],
                                    ),
                                    onChanged: (enabled) =>
                                        _toggle(group.types[index], enabled),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.label,
    required this.value,
    required this.isPending,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool isPending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isPending)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            )
          else
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.primary,
            ),
        ],
      ),
    );
  }
}
