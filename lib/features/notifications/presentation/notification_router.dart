import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
import 'package:yovoice/features/servers/presentation/screens/server_invite_response_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
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
  none,
}

/// Routes a tapped notification (from a push, or from the in-app
/// notification center) to its destination screen. Every target is
/// re-fetched fresh from Firestore rather than trusting the notification
/// doc's own denormalized fields, so a deleted server/conversation/user
/// or a since-revoked read permission fails closed — silently does
/// nothing — instead of opening a broken or unauthorized screen.
class NotificationRouter {
  const NotificationRouter._();

  static NotificationDestination destinationFor(NotificationType type) =>
      switch (type) {
        NotificationType.friendRequest =>
          NotificationDestination.friendRequests,
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
        NotificationType.momentComment =>
          NotificationDestination.momentComments,
        NotificationType.reelComment => NotificationDestination.reelComments,
        NotificationType.commentMention =>
          NotificationDestination.commentThread,
        NotificationType.serverEventReminder =>
          NotificationDestination.serverEvent,
        NotificationType.serverRole => NotificationDestination.club,
        NotificationType.achievementUnlocked ||
        NotificationType.moderation ||
        NotificationType.system => NotificationDestination.none,
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

    try {
      switch (destinationFor(type)) {
        case NotificationDestination.friendRequests:
          await _openFriendRequests(navigator);
        case NotificationDestination.profile:
          await _openProfile(navigator, actorId);
        case NotificationDestination.clubInvite:
          await _openServerInvite(navigator, targetId);
        case NotificationDestination.club:
          await _openServer(navigator, targetId);
        case NotificationDestination.room:
          await _openLegacyRoom(navigator, targetId);
        case NotificationDestination.conversation:
          await _openConversation(navigator, targetId);
        case NotificationDestination.directCall:
          await _openDirectCall(navigator, targetId);
        case NotificationDestination.missedCall:
          await _openMissedCall(navigator, targetId);
        case NotificationDestination.momentComments:
          await _openMomentComments(navigator, targetId);
        case NotificationDestination.reelComments:
          await _openReel(navigator, targetId);
        case NotificationDestination.commentThread:
          if (resolvedSourcePath?.startsWith('reels/') == true) {
            await _openReel(navigator, targetId);
          } else if (resolvedSourcePath?.startsWith('voiceMoments/') == true) {
            await _openMomentComments(navigator, targetId);
          }
        case NotificationDestination.serverEvent:
          await _openServer(navigator, targetId, channelId: resolvedSubId);
        case NotificationDestination.none:
          // No dedicated destination yet — landing on the notification
          // center itself (where the tap originated) is enough for these.
          break;
      }
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
  }

  static Future<void> _openProfile(
    NavigatorState navigator,
    String? userId,
  ) async {
    if (userId == null || userId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(userId)
        .get();
    if (!doc.exists || !navigator.mounted) return;
    final friend = FriendUser.fromFirestore(doc);
    await showProfilePreview(
      navigator.context,
      userId: friend.id,
      displayName: friend.displayName,
      photoUrl: friend.photoUrl,
    );
  }

  static Future<void> _openFriendRequests(NavigatorState navigator) {
    return navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FriendsScreen(showRequestsInitially: true),
      ),
    );
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

  static Future<void> _openServer(
    NavigatorState navigator,
    String? serverId, {
    String? channelId,
  }) async {
    if (serverId == null || serverId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(serverId)
        .get();
    if (!doc.exists || !navigator.mounted) return;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(
          serverId: serverId,
          initialChannelId: channelId?.isNotEmpty == true ? channelId : null,
        ),
      ),
    );
  }

  /// Opens the Moment's own comment thread. The Moment is re-fetched through
  /// `getVoiceMomentViewV2`, which rechecks the audience and refuses an
  /// expired or deleted Moment — so a stale row simply does nothing rather
  /// than opening something the viewer may no longer see.
  static Future<void> _openMomentComments(
    NavigatorState navigator,
    String? momentId,
  ) async {
    if (momentId == null || momentId.isEmpty) return;
    final view = await MomentService().loadMomentView(momentId);
    if (!navigator.mounted) return;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(moment: view.moment),
      ),
    );
  }

  /// Opens the Yeel viewer. Reel documents are never client-readable, so the
  /// destination screen calls `getReelViewV2` itself and shows its own
  /// unavailable state when the Yeel is gone.
  static Future<void> _openReel(
    NavigatorState navigator,
    String? reelId,
  ) async {
    if (reelId == null || reelId.isEmpty || !navigator.mounted) return;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReelLinkDestinationScreen(reelId: reelId),
      ),
    );
  }

  static Future<void> _openServerInvite(
    NavigatorState navigator,
    String? serverId,
  ) async {
    if (serverId == null || serverId.isEmpty || !navigator.mounted) return;
    // A private Server root is not readable before acceptance. The response
    // screen reads only the invitee-owned preview and the callable re-proves
    // the invitation before creating membership.
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerInviteResponseScreen(serverId: serverId),
      ),
    );
  }

  static Future<void> _openLegacyRoom(
    NavigatorState navigator,
    String? roomId,
  ) async {
    if (roomId == null || roomId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .get();
    if (!doc.exists || !navigator.mounted) return;
    final serverId = (doc.data()?['clubId'] as String?)?.trim();
    if (serverId != null && serverId.isNotEmpty) {
      await _openServer(navigator, serverId);
      return;
    }
    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const ServersScreen()),
    );
  }

  static Future<void> _openDirectCall(
    NavigatorState navigator,
    String? callId,
  ) async {
    if (callId == null || callId.isEmpty) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('directCalls')
        .doc(callId)
        .get();
    if (!snapshot.exists || !navigator.mounted) return;
    if (!DirectCallRouteRegistry.claim(callId)) return;
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
  }

  static Future<void> _openMissedCall(
    NavigatorState navigator,
    String? callId,
  ) async {
    if (callId == null || callId.isEmpty) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('directCalls')
        .doc(callId)
        .get();
    if (!snapshot.exists || !navigator.mounted) return;
    final conversationId = snapshot.data()?['conversationId'] as String?;
    await _openConversation(navigator, conversationId);
  }

  static Future<void> _openConversation(
    NavigatorState navigator,
    String? conversationId,
  ) async {
    if (conversationId == null || conversationId.isEmpty) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final conversationDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .get();
    if (!conversationDoc.exists) return;

    final participantIds = List<String>.from(
      conversationDoc.data()?['participantIds'] as List? ?? const [],
    );
    final otherUserId = participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    if (otherUserId.isEmpty) return;

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
  }
}
