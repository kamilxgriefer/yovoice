import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

/// Global navigator handle used purely for notification-tap routing. The
/// app has no router package — navigation everywhere else is plain
/// imperative `Navigator.push` off a widget's own `context` — but an FCM
/// tap that launches the app cold or from background has no context to
/// push from, so this is the one place that genuinely needs one.
final GlobalKey<NavigatorState> notificationNavigatorKey =
    GlobalKey<NavigatorState>();

/// Routes a tapped notification (from a push, or from the in-app
/// notification center) to its destination screen. Every target is
/// re-fetched fresh from Firestore rather than trusting the notification
/// doc's own denormalized fields, so a deleted club/room/conversation/user
/// or a since-revoked read permission fails closed — silently does
/// nothing — instead of opening a broken or unauthorized screen.
class NotificationRouter {
  const NotificationRouter._();

  static Future<void> route({
    required NotificationType type,
    String? targetId,
    String? actorId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final navigator = notificationNavigatorKey.currentState;
    if (navigator == null) return;

    try {
      switch (type) {
        case NotificationType.friendRequest:
        case NotificationType.friendAccepted:
        case NotificationType.follow:
          await _openProfile(navigator, actorId);
        case NotificationType.clubInvite:
        case NotificationType.clubInviteAccepted:
          await _openClub(navigator, targetId);
        case NotificationType.roomInvite:
        case NotificationType.broadcastInvite:
        case NotificationType.liveStarted:
          await _openRoom(navigator, targetId);
        case NotificationType.directMessage:
        case NotificationType.mention:
        case NotificationType.reply:
          await _openConversation(navigator, targetId);
        case NotificationType.achievementUnlocked:
        case NotificationType.moderation:
        case NotificationType.system:
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
        .collection('users')
        .doc(userId)
        .get();
    if (!doc.exists) return;
    final friend = FriendUser.fromFirestore(doc);
    navigator.push(
      MaterialPageRoute(builder: (_) => FriendProfileScreen(friend: friend)),
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

    final otherUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId)
        .get();
    if (!otherUserDoc.exists) return;
    final otherUserData = otherUserDoc.data() ?? const <String, dynamic>{};
    final displayName = (otherUserData['displayName'] as String?)?.trim();

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          otherUserId: otherUserId,
          otherDisplayName: displayName?.isNotEmpty == true
              ? displayName!
              : 'YO Voice user',
          otherEmail: otherUserData['email'] as String? ?? '',
          otherPhotoUrl: otherUserData['photoUrl'] as String? ?? '',
        ),
      ),
    );
  }
}
