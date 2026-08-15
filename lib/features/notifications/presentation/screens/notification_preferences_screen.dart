import 'package:flutter/material.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

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
    title: 'Messages',
    types: [
      NotificationType.directMessage,
      NotificationType.mention,
      NotificationType.reply,
    ],
  ),
];

String _labelFor(NotificationType type) {
  switch (type) {
    case NotificationType.friendRequest:
      return 'Friend requests';
    case NotificationType.friendAccepted:
      return 'Friend request accepted';
    case NotificationType.follow:
      return 'New followers';
    case NotificationType.clubInvite:
      return 'Club invitations';
    case NotificationType.clubInviteAccepted:
      return 'Club invitation accepted';
    case NotificationType.roomInvite:
      return 'Room invitations';
    case NotificationType.broadcastInvite:
      return 'Podcast invitations';
    case NotificationType.liveStarted:
      return 'People you follow go live';
    case NotificationType.directMessage:
      return 'Direct messages';
    case NotificationType.mention:
      return 'Mentions';
    case NotificationType.reply:
      return 'Replies';
    case NotificationType.achievementUnlocked:
      return 'Achievements';
    case NotificationType.moderation:
      return 'Moderation';
    case NotificationType.system:
      return 'System announcements';
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({this.isRootTab = false, super.key});

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF12101D);
  static const _border = Color(0xFF2C253B);
  static const _secondaryText = Color(0xFF9D95AD);
  static const _primary = Color(0xFFB348FF);

  final NotificationService _notificationService = NotificationService();
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not update preference: $error'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF481C30),
          ),
        );
    } finally {
      if (mounted) setState(() => _pending.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
              child: Row(
                children: [
                  if (!widget.isRootTab) ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Expanded(
                    child: Text(
                      'Notification preferences',
                      style: TextStyle(
                        color: Colors.white,
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
                      const Text(
                        'Choose which activity sends you a push '
                        'notification. In-app activity is always recorded '
                        'in your notification center regardless of these '
                        'settings.',
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (final group in _kPreferenceGroups) ...[
                        Text(
                          group.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < group.types.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  const Divider(
                                    height: 1,
                                    color: _border,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                _PreferenceRow(
                                  label: _labelFor(group.types[index]),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isPending)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _NotificationPreferencesScreenState._primary,
              ),
            )
          else
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: _NotificationPreferencesScreenState._primary,
            ),
        ],
      ),
    );
  }
}
