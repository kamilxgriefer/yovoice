import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/calls/presentation/screens/direct_call_screen.dart';
import 'package:yovoice/features/calls/presentation/direct_call_route_registry.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_link_destination_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/servers/presentation/screens/server_invite_response_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// Global navigator handle used purely for notification-tap routing. The
/// app has no router package — navigation everywhere else is plain
/// imperative `Navigator.push` off a widget's own `context` — but an FCM
/// tap that launches the app cold or from background has no context to
/// push from, so this is the one place that genuinely needs one.
final GlobalKey<NavigatorState> notificationNavigatorKey =
    GlobalKey<NavigatorState>();

enum NotificationDestination {
  friendRequests,
  profile,
  clubInvite,
  club,
  room,
  conversation,
  directCall,
  missedCall,

  /// The comment thread under a Voice Moment.
  momentComments,

  /// The Yeel viewer, opened on its thread.
  reelComments,

  /// A Moment or a Yeel — which one is decided from the row's `sourcePath`,
  /// because one `commentMention` type covers both surfaces.
  commentThread,

  /// A Server, opened on the channel the event lives in.
  serverEvent,

  /// A Premium Page post's detail, with its comments (ADR-233).
  pagePost,

  /// The recipient's own Page profile (a moderation or lapse notice).
  ownPage,

  /// Awards: where an unlocked achievement lives.
  awards,

  /// The notification centre itself. A notice from YO Voice or a moderator
  /// has no screen of its own — the row IS the message — so a tapped push
  /// opens the list that shows it, and a tap inside that list stays put.
  inbox,
}

/// Routes a tapped notification (from a push, or from the in-app
/// notification center) to its destination screen. Every target is
/// re-fetched fresh from Firestore rather than trusting the notification
/// doc's own denormalized fields, so a deleted server/conversation/user
/// or a since-revoked read permission fails closed instead of opening a
/// broken or unauthorized screen.
///
/// A tap never does NOTHING (ADR-237). Every type has a destination, and a
/// destination that is gone — a retired room, a deleted server, an ended
/// call — answers with one uniform line, "This content is no longer
/// available.", which says the same thing whatever the reason so it cannot
/// be used to tell a block from a deletion.
class NotificationRouter {
  const NotificationRouter._();

  static NotificationDestination destinationFor(
    NotificationType type,
  ) => switch (type) {
    NotificationType.friendRequest => NotificationDestination.friendRequests,
    NotificationType.friendAccepted ||
    NotificationType.follow => NotificationDestination.profile,
    NotificationType.clubInvite => NotificationDestination.clubInvite,
    NotificationType.clubInviteAccepted => NotificationDestination.club,
    NotificationType.roomInvite ||
    NotificationType.broadcastInvite ||
    NotificationType.liveStarted => NotificationDestination.room,
    NotificationType.directMessage ||
    NotificationType.mention ||
    NotificationType.reply => NotificationDestination.conversation,
    NotificationType.directCall => NotificationDestination.directCall,
    NotificationType.missedCall => NotificationDestination.missedCall,
    NotificationType.momentComment => NotificationDestination.momentComments,
    NotificationType.reelComment => NotificationDestination.reelComments,
    NotificationType.commentMention => NotificationDestination.commentThread,
    NotificationType.serverEventReminder => NotificationDestination.serverEvent,
    NotificationType.serverRole => NotificationDestination.club,
    NotificationType.pagePostComment ||
    NotificationType.pagePostPublished => NotificationDestination.pagePost,
    NotificationType.pageModeration ||
    NotificationType.pageLapse => NotificationDestination.ownPage,
    NotificationType.achievementUnlocked => NotificationDestination.awards,
    NotificationType.moderation ||
    NotificationType.system => NotificationDestination.inbox,
  };

  /// Notification types whose destination needs a field a push payload does
  /// not always carry (the comment's parent surface, the event's channel).
  static bool _needsRowDetail(NotificationType type) =>
      type == NotificationType.commentMention ||
      type == NotificationType.serverEventReminder;

  static Future<void> route({
    required NotificationType type,
    String? targetId,
    String? actorId,
    String? notificationId,
    String? targetSubId,
    String? sourcePath,
    // True when the tap happened inside the notification centre, which is
    // then already the destination of an `inbox` row.
    bool fromInbox = false,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final navigator = notificationNavigatorKey.currentState;
    if (navigator == null) return;

    var resolvedSubId = targetSubId;
    var resolvedSourcePath = sourcePath;
    if (_needsRowDetail(type) &&
        (resolvedSourcePath == null || resolvedSubId == null) &&
        notificationId?.isNotEmpty == true) {
      // A tapped push carries only type/targetId/actorId/notificationId (plus
      // the optional targetSubId). The owner-readable row itself is the
      // authoritative source for the rest, so read it rather than guessing.
      final row = await _loadNotification(notificationId!);
      resolvedSubId ??= row?['targetSubId'] as String?;
      resolvedSourcePath ??= row?['sourcePath'] as String?;
    }

    if (notificationId?.isNotEmpty == true) {
      try {
        await NotificationService().markAsRead(notificationId!);
      } on Exception catch (error) {
        debugPrint(
          'NotificationRouter: could not mark a tapped notification read '
          '(${error.runtimeType}); routing continues.',
        );
      }
    }

    var opened = false;
    try {
      opened = switch (destinationFor(type)) {
        NotificationDestination.friendRequests => await _openFriendRequests(
          navigator,
        ),
        NotificationDestination.profile => await _openProfile(
          navigator,
          actorId,
        ),
        NotificationDestination.clubInvite => await _openServerInvite(
          navigator,
          targetId,
        ),
        NotificationDestination.club => await _openServer(navigator, targetId),
        NotificationDestination.room => await _openLegacyRoom(
          navigator,
          targetId,
        ),
        NotificationDestination.conversation => await _openConversation(
          navigator,
          targetId,
        ),
        NotificationDestination.directCall => await _openDirectCall(
          navigator,
          targetId,
        ),
        NotificationDestination.missedCall => await _openMissedCall(
          navigator,
          targetId,
        ),
        NotificationDestination.momentComments => await _openMomentComments(
          navigator,
          targetId,
        ),
        NotificationDestination.reelComments => await _openReel(
          navigator,
          targetId,
        ),
        NotificationDestination.commentThread =>
          resolvedSourcePath?.startsWith('reels/') == true
              ? await _openReel(navigator, targetId)
              : resolvedSourcePath?.startsWith('voiceMoments/') == true
              ? await _openMomentComments(navigator, targetId)
              : false,
        NotificationDestination.serverEvent => await _openServer(
          navigator,
          targetId,
          channelId: resolvedSubId,
        ),
        NotificationDestination.pagePost => await _openPagePost(
          navigator,
          targetId,
        ),
        NotificationDestination.ownPage => await _openOwnPage(navigator),
        NotificationDestination.awards => await _openAwards(navigator),
        NotificationDestination.inbox => await _openInbox(
          navigator,
          fromInbox: fromInbox,
        ),
      };
    } on Exception catch (error) {
      // Fail closed: a deleted or now-inaccessible target must never
      // crash the tap, and must never fall through to showing content
      // the user has lost access to. Naming it distinguishes "this
      // conversation is gone" from "deep links are broken".
      debugPrint(
        'NotificationRouter: could not open the target of a '
        '${type.name} notification (${error.runtimeType}). Staying put.',
      );
    }
    if (!opened) _announceUnavailable(navigator);
  }

  /// Test seam for the one line below.
  @visibleForTesting
  static void announceUnavailable(NavigatorState navigator) =>
      _announceUnavailable(navigator);

  /// One line for every destination that could not be opened, whatever the
  /// reason: gone, retired, or no longer readable by this account.
  static void _announceUnavailable(NavigatorState navigator) {
    if (!navigator.mounted) return;
    final context = navigator.context;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final copy = AppLocalizations.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('notification-destination-unavailable'),
          behavior: SnackBarBehavior.floating,
          content: Text(
            copy.text(
              'This content is no longer available.',
              'Ta treść nie jest już dostępna.',
            ),
          ),
        ),
      );
  }

  /// An unlocked achievement opens Awards, where it now sits in its track.
  static Future<bool> _openAwards(NavigatorState navigator) async {
    if (!navigator.mounted) return false;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'notifications/awards'),
        builder: (_) => const AwardsHubScreen(),
      ),
    );
    return true;
  }

  /// A YO Voice or moderator notice: the row is the whole message. From a
  /// push it opens the list that shows it; inside the list there is nowhere
  /// further to go, and that is not a failure.
  static Future<bool> _openInbox(
    NavigatorState navigator, {
    required bool fromInbox,
  }) async {
    if (fromInbox) return true;
    if (!navigator.mounted) return false;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'notifications/inbox'),
        builder: (_) => const NotificationsScreen(),
      ),
    );
    return true;
  }

  static Future<bool> _openProfile(
    NavigatorState navigator,
    String? userId,
  ) async {
    if (userId == null || userId.isEmpty) return false;
    final doc = await FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(userId)
        .get();
    if (!doc.exists || !navigator.mounted) return false;
    final friend = FriendUser.fromFirestore(doc);
    await showProfilePreview(
      navigator.context,
      userId: friend.id,
      displayName: friend.displayName,
      photoUrl: friend.photoUrl,
    );
    return true;
  }

  /// A Page post: a comment on the recipient's own post, or the post a
  /// followed Page just published. Only while Pages are on for this account
  /// (the kill switch hides every Page); the detail itself shows
  /// "unavailable" for a post that is gone.
  static Future<bool> _openPagePost(
    NavigatorState navigator,
    String? postId,
  ) async {
    if (postId == null || !pagePostIdPattern.hasMatch(postId)) return false;
    if (!PagesAvailability.instance.enabled.value) return false;
    await navigator.push<void>(pagePostRoute(postId: postId));
    return true;
  }

  static Future<bool> _openOwnPage(NavigatorState navigator) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    if (!PagesAvailability.instance.enabled.value) return false;
    await navigator.push<void>(pageProfileRoute(pageId: uid));
    return true;
  }

  static Future<bool> _openFriendRequests(NavigatorState navigator) async {
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FriendsScreen(showRequestsInitially: true),
      ),
    );
    return true;
  }

  static Future<Map<String, dynamic>?> _loadNotification(
    String notificationId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .get();
      return doc.data();
    } on FirebaseException catch (error) {
      debugPrint(
        'NotificationRouter: could not read the tapped row '
        '(${error.code}); routing continues with what the push carried.',
      );
      return null;
    }
  }

  static Future<bool> _openServer(
    NavigatorState navigator,
    String? serverId, {
    String? channelId,
  }) async {
    if (serverId == null || serverId.isEmpty) return false;
    final doc = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(serverId)
        .get();
    if (!doc.exists || !navigator.mounted) return false;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(
          serverId: serverId,
          initialChannelId: channelId?.isNotEmpty == true ? channelId : null,
        ),
      ),
    );
    return true;
  }

  /// Opens the Moment's own comment thread. The Moment is re-fetched through
  /// `getVoiceMomentViewV2`, which rechecks the audience and refuses an
  /// expired or deleted Moment — so a stale row simply does nothing rather
  /// than opening something the viewer may no longer see.
  static Future<bool> _openMomentComments(
    NavigatorState navigator,
    String? momentId,
  ) async {
    if (momentId == null || momentId.isEmpty) return false;
    final view = await MomentService().loadMomentView(momentId);
    if (!navigator.mounted) return false;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(moment: view.moment),
      ),
    );
    return true;
  }

  /// Opens the Yeel viewer. Reel documents are never client-readable, so the
  /// destination screen calls `getReelViewV2` itself and shows its own
  /// unavailable state when the Yeel is gone.
  static Future<bool> _openReel(
    NavigatorState navigator,
    String? reelId,
  ) async {
    if (reelId == null || reelId.isEmpty || !navigator.mounted) return false;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReelLinkDestinationScreen(reelId: reelId),
      ),
    );
    return true;
  }

  static Future<bool> _openServerInvite(
    NavigatorState navigator,
    String? serverId,
  ) async {
    if (serverId == null || serverId.isEmpty || !navigator.mounted) {
      return false;
    }
    // A private Server root is not readable before acceptance. The response
    // screen reads only the invitee-owned preview and the callable re-proves
    // the invitation before creating membership.
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerInviteResponseScreen(serverId: serverId),
      ),
    );
    return true;
  }

  /// `roomInvite`, `broadcastInvite` and `liveStarted` name a `rooms/{id}`
  /// document. A room that belongs to a Server opens that Server. A
  /// standalone room is a retired surface: it used to drop the reader on the
  /// Servers list, which had nothing to do with what they tapped, and a room
  /// that no longer exists did nothing at all. Both now answer "no longer
  /// available" (the caller's uniform line) instead of pretending.
  static Future<bool> _openLegacyRoom(
    NavigatorState navigator,
    String? roomId,
  ) async {
    if (roomId == null || roomId.isEmpty) return false;
    final doc = await FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .get();
    if (!doc.exists || !navigator.mounted) return false;
    final serverId = (doc.data()?['clubId'] as String?)?.trim();
    if (serverId == null || serverId.isEmpty) return false;
    return _openServer(navigator, serverId);
  }

  static Future<bool> _openDirectCall(
    NavigatorState navigator,
    String? callId,
  ) async {
    if (callId == null || callId.isEmpty) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('directCalls')
        .doc(callId)
        .get();
    if (!snapshot.exists || !navigator.mounted) return false;
    // Another surface already owns this call's screen: that is the
    // destination, not a failure.
    if (!DirectCallRouteRegistry.claim(callId)) return true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DirectCallScreen(callId: callId),
        ),
      );
    } finally {
      DirectCallRouteRegistry.release(callId);
    }
    return true;
  }

  static Future<bool> _openMissedCall(
    NavigatorState navigator,
    String? callId,
  ) async {
    if (callId == null || callId.isEmpty) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('directCalls')
        .doc(callId)
        .get();
    if (!snapshot.exists || !navigator.mounted) return false;
    final conversationId = snapshot.data()?['conversationId'] as String?;
    return _openConversation(navigator, conversationId);
  }

  static Future<bool> _openConversation(
    NavigatorState navigator,
    String? conversationId,
  ) async {
    if (conversationId == null || conversationId.isEmpty) return false;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return false;

    final conversationDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .get();
    if (!conversationDoc.exists) return false;

    final participantIds = List<String>.from(
      conversationDoc.data()?['participantIds'] as List? ?? const [],
    );
    final otherUserId = participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    if (otherUserId.isEmpty) return false;

    final conversationData =
        conversationDoc.data() ?? const <String, dynamic>{};
    final participantNames = Map<String, dynamic>.from(
      conversationData['participantNames'] as Map? ?? const {},
    );
    var displayName = (participantNames[otherUserId] as String?)?.trim();
    var photoUrl = '';

    // An existing conversation remains usable when the other participant
    // makes their public profile private. Attempt the separately authorised
    // projection for fresh presentation data, but fall back to the immutable
    // conversation label rather than treating profile privacy as chat access.
    try {
      final otherUserDoc = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(otherUserId)
          .get();
      if (otherUserDoc.exists) {
        final otherUserData = otherUserDoc.data() ?? const <String, dynamic>{};
        final projectedName = (otherUserData['displayName'] as String?)?.trim();
        if (projectedName?.isNotEmpty == true) displayName = projectedName;
        photoUrl = otherUserData['photoUrl'] as String? ?? '';
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          otherUserId: otherUserId,
          otherDisplayName: displayName?.isNotEmpty == true
              ? displayName!
              : 'YO Voice user',
          // Email is private account data and is never part of the public
          // profile projection or a new conversation payload.
          otherEmail: '',
          otherPhotoUrl: photoUrl,
        ),
      ),
    );
    return true;
  }
}
