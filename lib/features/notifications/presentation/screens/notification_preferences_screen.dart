import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
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
    title: 'Servers',
    types: [
      NotificationType.clubInvite,
      NotificationType.clubInviteAccepted,
      NotificationType.roomInvite,
      NotificationType.broadcastInvite,
      NotificationType.liveStarted,
      NotificationType.serverEventReminder,
      NotificationType.serverRole,
    ],
  ),
  // Moments & Yeels (ADR-212). One switch stands for three server types —
  // see _coveredTypes: a person who turns comments off does not expect an
  // @mention inside a comment to still ring.
  _PreferenceGroup(
    title: 'Moments & Yeels',
    types: [NotificationType.momentComment],
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

/// The server notification types one visible switch controls.
///
/// The push boundary reads one key per type. A row that stands for several
/// types therefore writes all of them together, and reads as ON only while
/// every type it covers is on.
List<NotificationType> _coveredTypes(NotificationType type) =>
    switch (type) {
      NotificationType.momentComment => const [
        NotificationType.momentComment,
        NotificationType.reelComment,
        NotificationType.commentMention,
      ],
      _ => <NotificationType>[type],
    };

String _groupTitle(AppLocalizations copy, String title) => switch (title) {
  'Friends' => copy.text('Friends', 'Znajomi'),
  'Friends & follows' => copy.text(
    'Friends & follows',
    'Znajomi i obserwowani',
  ),
  'Servers' => copy.text('Servers', 'Serwery'),
  'Moments & Yeels' => copy.text('Moments & Yeels', 'Momenty i Yeels'),
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
      return copy.text('Server invitations', 'Zaproszenia do serwerów');
    case NotificationType.clubInviteAccepted:
      return copy.text(
        'Server invitation accepted',
        'Przyjęte zaproszenie do serwera',
      );
    case NotificationType.roomInvite:
      return copy.text(
        'Voice channel invitations',
        'Zaproszenia do kanałów głosowych',
      );
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
    case NotificationType.momentComment:
    case NotificationType.reelComment:
    case NotificationType.commentMention:
      return copy.text(
        'Comments and mentions',
        'Komentarze i oznaczenia',
      );
    case NotificationType.serverEventReminder:
      return copy.text('Server events', 'Wydarzenia na serwerach');
    case NotificationType.serverRole:
      return copy.text('Your server role', 'Twoja rola na serwerze');
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
    this.auth,
    this.creatorAudienceService,
    this.creatorAudienceVisibleStream,
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

  /// Public-safe audience eligibility. Raw Premium and age verification are
  /// intentionally absent: only the server-written public projection decides
  /// whether a follower notification can exist for this account.
  final FirebaseAuth? auth;
  final CreatorAudienceService? creatorAudienceService;

  /// Focused-test/host seam. Production resolves the same boolean from
  /// `publicProfiles/{uid}.creatorAudienceVisible`.
  final Stream<bool>? creatorAudienceVisibleStream;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();
  late final Stream<Map<String, bool>> _preferencesStream;
  late final Stream<bool> _creatorAudienceVisibleStream;

  final Set<NotificationType> _pending = <NotificationType>{};

  @override
  void initState() {
    super.initState();
    _preferencesStream = _notificationService.watchPreferences();
    _creatorAudienceVisibleStream =
        widget.creatorAudienceVisibleStream ?? _watchCreatorAudience();
  }

  Stream<bool> _watchCreatorAudience() async* {
    try {
      final auth = widget.auth ?? FirebaseAuth.instance;
      final uid = auth.currentUser?.uid ?? '';
      if (uid.isEmpty) {
        yield false;
        return;
      }
      final service = widget.creatorAudienceService ?? CreatorAudienceService();
      await for (final projection in service.watchPublicProjection(uid)) {
        yield projection.visible;
      }
    } catch (_) {
      // This optional preference fails closed when the public projection is
      // unavailable. Friends, Servers, Calls and Messages remain usable.
      yield false;
    }
  }

  Future<void> _toggle(NotificationType type, bool enabled) async {
    if (_pending.contains(type)) return;
    setState(() => _pending.add(type));
    try {
      await _notificationService.setPreferences(_coveredTypes(type), enabled);
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
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<bool>(
                  stream: _creatorAudienceVisibleStream,
                  initialData: false,
                  builder: (context, audienceSnapshot) {
                    final audienceVisible = audienceSnapshot.data == true;
                    final groups = <_PreferenceGroup>[
                      for (final group in _kPreferenceGroups)
                        _PreferenceGroup(
                          title:
                              group.title == 'Friends & follows' &&
                                  !audienceVisible
                              ? 'Friends'
                              : group.title,
                          types: group.types
                              .where(
                                (type) =>
                                    type != NotificationType.follow ||
                                    audienceVisible,
                              )
                              .toList(growable: false),
                        ),
                    ];
                    return StreamBuilder<Map<String, bool>>(
                      stream: _preferencesStream,
                      builder: (context, snapshot) {
                        final preferences =
                            snapshot.data ?? const <String, bool>{};
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
                            for (final group in groups) ...[
                              // THE section heading (ADR-209): it owns the
                              // 24 px above and 16 px below its ink, so the
                              // private 20 / 8 / 18 spacers are gone.
                              HomeSectionHeader(
                                title: _groupTitle(copy, group.title),
                              ),
                              // One flat layer: 1 px border, radius 12.
                              Container(
                                decoration: BoxDecoration(
                                  color: palette.surface,
                                  borderRadius: BorderRadius.circular(12),
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
                                        // Indented to the rows' 16 px text edge.
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: palette.border,
                                          indent: 16,
                                        ),
                                      _PreferenceRow(
                                        label: _labelFor(
                                          copy,
                                          group.types[index],
                                        ),
                                        // Preferences are opt-out: an absent key
                                        // means enabled, matching
                                        // onNotificationCreated's default in
                                        // functions/notifications/push.js.
                                        // A row covering several types is ON
                                        // only while every one of them is.
                                        value: _coveredTypes(
                                          group.types[index],
                                        ).every(
                                          (type) =>
                                              preferences[type.name] != false,
                                        ),
                                        isPending: _pending.contains(
                                          group.types[index],
                                        ),
                                        onChanged: (enabled) => _toggle(
                                          group.types[index],
                                          enabled,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
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
            // No activeThumbColor override: the theme's switchTheme already
            // paints the selected thumb with colorScheme.onPrimary against the
            // primary track. Forcing the thumb to primary made it vanish into
            // the track, so an ON switch read as a solid lozenge.
            Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
