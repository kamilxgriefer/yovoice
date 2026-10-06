import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/presentation/achievement_localized_copy.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/pages/presentation/page_notice_copy.dart';

/// What a notification says, in the reader's language.
///
/// One definition for every surface that names a notification: the bell row,
/// the foreground banner and — through [NotificationPushCopy] — the push the
/// server sends. Each sentence is composed here from the row's type, its
/// actor and its label; nothing a row carries is trusted as finished copy
/// except a server-authored `system` or `moderation` label.
///
/// Polish uses the present tense throughout ("wysyła", "dodaje"): its past
/// tense is gendered and the actor's gender is unknown.
class NotificationCopy {
  const NotificationCopy(this.copy);

  final AppLocalizations copy;

  /// The name shown for a row that carries none.
  String get unknownActor => copy.text('YO Voice user', 'Użytkownik YO Voice');

  /// The row's title.
  String title(AppNotification notification) {
    final label = _label(notification);
    return switch (notification.type) {
      NotificationType.pageModeration => PageNoticeCopy(
        copy,
      ).moderation(notification),
      NotificationType.pageLapse => PageNoticeCopy(copy).lapse(notification),
      _ => titleFor(
        type: notification.type,
        actor: notification.actorName,
        label: label,
      ),
    };
  }

  /// The line under the title, when the row has one: the first words of a
  /// followed Page's post. Every other row is a title and a time.
  String? body(AppNotification notification) {
    if (notification.type != NotificationType.pagePostPublished) return null;
    final preview = notification.postPreview?.trim();
    return preview == null || preview.isEmpty ? null : preview;
  }

  /// An unlocked achievement's label is its catalogue title in the reader's
  /// language (the row stores the English one); every other label is the
  /// name the server wrote.
  String? _label(AppNotification notification) {
    final label = notification.targetLabel?.trim();
    if (notification.type == NotificationType.achievementUnlocked) {
      final achievement = AchievementCatalog.byId(notification.targetId);
      if (achievement != null) {
        return localizedAchievementTitle(copy, achievement);
      }
    }
    return label == null || label.isEmpty ? null : label;
  }

  /// The title of [type] for [actor] and an optional [label].
  ///
  /// `pageModeration` and `pageLapse` need the whole row ([title]); here
  /// they fall back to their label.
  String titleFor({
    required NotificationType type,
    required String actor,
    String? label,
  }) {
    final name = actor.trim().isEmpty ? unknownActor : actor.trim();
    final hasLabel = label != null && label.isNotEmpty;

    return switch (type) {
      NotificationType.friendRequest => copy.template(
        '{actor} sent you a friend request',
        '{actor} wysyła Ci zaproszenie do znajomych',
        values: {'actor': name},
      ),
      NotificationType.friendAccepted => copy.template(
        '{actor} accepted your friend request',
        '{actor} przyjmuje Twoje zaproszenie do znajomych',
        values: {'actor': name},
      ),
      NotificationType.follow => copy.template(
        '{actor} started following you',
        '{actor} zaczyna Cię obserwować',
        values: {'actor': name},
      ),
      NotificationType.clubInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do serwera {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a server',
                '{actor} zaprasza Cię do serwera',
                values: {'actor': name},
              ),
      NotificationType.clubInviteAccepted =>
        hasLabel
            ? copy.template(
                '{actor} joined {label}',
                '{actor} dołącza do serwera {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} accepted your server invitation',
                '{actor} przyjmuje Twoje zaproszenie do serwera',
                values: {'actor': name},
              ),
      NotificationType.roomInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do kanału głosowego {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a voice channel',
                '{actor} zaprasza Cię do kanału głosowego',
                values: {'actor': name},
              ),
      NotificationType.broadcastInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do transmisji {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a broadcast',
                '{actor} zaprasza Cię do transmisji',
                values: {'actor': name},
              ),
      NotificationType.liveStarted =>
        hasLabel
            ? copy.template(
                '{actor} is live: {label}',
                '{actor} prowadzi teraz: {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} is live now',
                '{actor} jest teraz na żywo',
                values: {'actor': name},
              ),
      NotificationType.directMessage => copy.template(
        '{actor} sent you a message request',
        '{actor} wysyła Ci prośbę o wiadomość',
        values: {'actor': name},
      ),
      NotificationType.directCall => copy.template(
        '{actor} is calling you',
        '{actor} dzwoni do Ciebie',
        values: {'actor': name},
      ),
      NotificationType.missedCall => copy.template(
        'Missed call from {actor}',
        'Nieodebrane połączenie od {actor}',
        values: {'actor': name},
      ),
      NotificationType.mention =>
        hasLabel
            ? copy.template(
                '{actor} mentioned you in {label}',
                '{actor} wspomina o Tobie w {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} mentioned you',
                '{actor} wspomina o Tobie',
                values: {'actor': name},
              ),
      NotificationType.reply =>
        hasLabel
            ? copy.template(
                '{actor} replied to you in {label}',
                '{actor} odpowiada Ci w {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} replied to you',
                '{actor} odpowiada Ci',
                values: {'actor': name},
              ),
      NotificationType.momentComment => copy.template(
        '{actor} commented on your Moment',
        '{actor} komentuje Twój Moment',
        values: {'actor': name},
      ),
      NotificationType.reelComment => copy.template(
        '{actor} commented on your Yeel',
        '{actor} komentuje Twojego Yeela',
        values: {'actor': name},
      ),
      NotificationType.commentMention => copy.template(
        '{actor} mentioned you in a comment',
        '{actor} oznacza Cię w komentarzu',
        values: {'actor': name},
      ),
      NotificationType.serverEventReminder =>
        hasLabel
            ? copy.template(
                'Starting soon: {label}',
                'Niedługo start: {label}',
                values: {'label': label},
              )
            : copy.text(
                'An event is starting soon',
                'Wydarzenie niedługo się zacznie',
              ),
      NotificationType.serverRole =>
        hasLabel
            ? copy.template(
                '{actor} promoted you in {label}',
                '{actor} awansuje Cię na serwerze {label}',
                values: {'actor': name, 'label': label},
              )
            : copy.template(
                '{actor} promoted you in a server',
                '{actor} awansuje Cię na serwerze',
                values: {'actor': name},
              ),
      NotificationType.pagePostComment => copy.template(
        '{actor} commented on your Page post',
        '{actor} komentuje Twój post na stronie',
        values: {'actor': name},
      ),
      // The actor is a Page. The label a row of this type carries is the
      // sentence for builds that do not know the type, never part of this.
      NotificationType.pagePostPublished => copy.template(
        '{actor} published a post',
        '{actor} dodaje post',
        values: {'actor': name},
      ),
      NotificationType.achievementUnlocked =>
        hasLabel
            ? copy.template(
                'Achievement unlocked: {label}',
                'Odblokowano osiągnięcie: {label}',
                values: {'label': label},
              )
            : copy.text('Achievement unlocked', 'Odblokowano osiągnięcie'),
      NotificationType.moderation =>
        hasLabel
            ? label
            : copy.text(
                'A moderator took action on your account',
                'Moderator wykonał działanie na Twoim koncie',
              ),
      // A Page notice is composed from the whole row by [title]; without the
      // row only the server's own label can be shown.
      NotificationType.pageModeration ||
      NotificationType.pageLapse ||
      NotificationType.system => hasLabel ? label : 'YO Voice',
    };
  }
}

/// The lock-screen copy of a push, in one language.
///
/// The app never shows these itself: the SERVER does, and it has no catalog
/// of its own. `test/push_copy_export_test.dart` renders every template
/// below in all 43 languages and writes the 42 non-English ones to
/// `functions/notifications/push_copy.json`, which
/// `functions/notifications/push_locale.js` reads. Keeping them here puts a
/// push's Polish beside the bell's Polish and its other 41 translations in
/// the same catalog, so a push and its bell row cannot drift apart.
///
/// A template id is `type` or `type.label` (the row carries a label), with
/// `directCall.video` / `missedCall.video` for a video call and five
/// non-title sentences. The ids are the contract with the server:
/// `pushTitleTemplateId` in push_locale.js must produce exactly these.
class NotificationPushCopy {
  const NotificationPushCopy(this.copy);

  final AppLocalizations copy;

  static const String _actor = '{actor}';
  static const String _label = '{label}';

  static const Map<String, NotificationType> _plain = {
    'friendRequest': NotificationType.friendRequest,
    'friendAccepted': NotificationType.friendAccepted,
    'follow': NotificationType.follow,
    'momentComment': NotificationType.momentComment,
    'reelComment': NotificationType.reelComment,
    'commentMention': NotificationType.commentMention,
    'pagePostComment': NotificationType.pagePostComment,
    'pagePostPublished': NotificationType.pagePostPublished,
  };

  static const Map<String, NotificationType> _labelled = {
    'clubInvite': NotificationType.clubInvite,
    'clubInviteAccepted': NotificationType.clubInviteAccepted,
    'roomInvite': NotificationType.roomInvite,
    'broadcastInvite': NotificationType.broadcastInvite,
    'liveStarted': NotificationType.liveStarted,
    'mention': NotificationType.mention,
    'reply': NotificationType.reply,
    'serverEventReminder': NotificationType.serverEventReminder,
    'serverRole': NotificationType.serverRole,
    'achievementUnlocked': NotificationType.achievementUnlocked,
  };

  /// Every template id the server may ask for, sorted.
  static List<String> get templateIds => <String>[
    ..._plain.keys,
    for (final id in _labelled.keys) ...[id, '$id.label'],
    'directMessage',
    'directCall',
    'directCall.video',
    'missedCall',
    'missedCall.video',
    'moderation',
    'actor.unknown',
    'body.default',
    'call.incoming.title',
    'call.incoming.body',
    'call.missed.title',
    'call.missed.body',
  ]..sort();

  /// The template of [id] with its `{actor}` / `{label}` placeholders left
  /// in place for the server to fill.
  String template(String id) {
    final titles = NotificationCopy(copy);
    final plain = _plain[id];
    if (plain != null) return titles.titleFor(type: plain, actor: _actor);
    if (id.endsWith('.label')) {
      final labelled = _labelled[id.substring(0, id.length - '.label'.length)];
      if (labelled != null) {
        return titles.titleFor(type: labelled, actor: _actor, label: _label);
      }
    }
    final unlabelled = _labelled[id];
    if (unlabelled != null) {
      return titles.titleFor(type: unlabelled, actor: _actor);
    }
    return switch (id) {
      // A friend's message pushes too, so the push cannot say "request".
      'directMessage' => copy.template(
        '{actor} sent you a message',
        '{actor} wysyła Ci wiadomość',
        values: {'actor': _actor},
      ),
      'directCall' => titles.titleFor(
        type: NotificationType.directCall,
        actor: _actor,
      ),
      'directCall.video' => copy.template(
        '{actor} is video calling you',
        '{actor} dzwoni do Ciebie z wideo',
        values: {'actor': _actor},
      ),
      'missedCall' => titles.titleFor(
        type: NotificationType.missedCall,
        actor: _actor,
      ),
      'missedCall.video' => copy.template(
        'Missed video call from {actor}',
        'Nieodebrane połączenie wideo od {actor}',
        values: {'actor': _actor},
      ),
      'moderation' => titles.titleFor(
        type: NotificationType.moderation,
        actor: _actor,
      ),
      'actor.unknown' => titles.unknownActor,
      'body.default' => copy.text(
        'Tap to open YO Voice',
        'Dotknij, aby otworzyć YO Voice',
      ),
      'call.incoming.title' => copy.text(
        'Incoming YO Voice call',
        'Połączenie przychodzące w YO Voice',
      ),
      'call.incoming.body' => copy.text(
        'Open YO Voice to answer.',
        'Otwórz YO Voice, aby odebrać.',
      ),
      'call.missed.title' => copy.text(
        'Missed YO Voice call',
        'Nieodebrane połączenie w YO Voice',
      ),
      'call.missed.body' => copy.text(
        'Open YO Voice to view the call.',
        'Otwórz YO Voice, aby zobaczyć połączenie.',
      ),
      _ => throw ArgumentError.value(id, 'id', 'Unknown push template.'),
    };
  }
}
