import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_invite_response_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
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
  none,
}

/// Routes a tapped notification (from a push, or from the in-app
/// notification center) to its destination screen. Every target is
/// re-fetched fresh from Firestore rather than trusting the notification
/// doc's own denormalized fields, so a deleted club/room/conversation/user
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
        NotificationType.achievementUnlocked ||
        NotificationType.moderation ||
        NotificationType.system => NotificationDestination.none,
      };

  static Future<void> route({
    required NotificationType type,
    String? targetId,
    String? actorId,
    String? notificationId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final navigator = notificationNavigatorKey.currentState;
    if (navigator == null) return;

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
          await _openClubInvite(navigator, targetId);
        case NotificationDestination.club:
          await _openClub(navigator, targetId);
        case NotificationDestination.room:
          await _openRoom(navigator, targetId);
        case NotificationDestination.conversation:
          await _openConversation(navigator, targetId);
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

  static Future<void> _openClub(
    NavigatorState navigator,
    String? clubId,
  ) async {
    if (clubId == null || clubId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('clubs')
        .doc(clubId)
        .get();
    if (!doc.exists) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => ClubOverviewScreen(clubId: clubId)),
    );
  }

  static Future<void> _openClubInvite(
    NavigatorState navigator,
    String? clubId,
  ) async {
    if (clubId == null || clubId.isEmpty) return;
    // Intentionally bypasses the Premium Clubs hub. Receiving and responding
    // to an invitation is free; the destination re-fetches the invitee's
    // canonical pending invite and exposes only Accept/Decline.
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ClubInviteResponseScreen(clubId: clubId),
      ),
    );
  }

  static Future<void> _openRoom(
    NavigatorState navigator,
    String? roomId,
  ) async {
    if (roomId == null || roomId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .get();
    if (!doc.exists) return;
    final room = VoiceRoom.fromFirestore(doc);
    navigator.push(
      MaterialPageRoute(builder: (_) => RoomEntryScreen(room: room)),
    );
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
