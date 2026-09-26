import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_request_decision.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';

/// The labelled Accept / Decline pair for a foreground friend-request card.
///
/// While the app is open, the in-app card replaces the system notification,
/// so it is the surface a user actually sees for a new request. It therefore
/// offers the same two explicit choices as every other request surface; its
/// body and "View request" only open the request list. Returns null for
/// every other type, and for a legacy row with no sender to answer.
YoTopNotificationDecision? friendRequestBannerDecision({
  required NotificationType type,
  required String? senderId,
  required String? senderName,
  required FriendService Function() friendService,
}) {
  final sender = senderId?.trim() ?? '';
  if (type != NotificationType.friendRequest || sender.isEmpty) return null;
  final name = senderName?.trim();
  return YoTopNotificationDecision(
    subjectName: name,
    onAccept: (copy) async => friendRequestResponseMessage(
      copy,
      await friendService().respondToFriendRequest(sender, accept: true),
      name: name,
    ),
    onDecline: (copy) async => friendRequestResponseMessage(
      copy,
      await friendService().respondToFriendRequest(sender, accept: false),
      name: name,
    ),
  );
}
