import 'package:yovoice/features/clubs/data/models/club_member.dart';

class ClubPermissionService {
  const ClubPermissionService._();

  static bool canEditClub(ClubRole role) => role.canEditClub;
  static bool canDeleteClub(ClubRole role) => role.canDeleteClub;
  static bool canManageChannels(ClubRole role) => role.canManageChannels;
  static bool canInvite(ClubRole role) => role.canInvite;
  static bool canWriteChat(ClubRole role) => role.canWriteChat;
  static bool canJoinVoice(ClubRole role) => role.canJoinVoice;

  static bool canChangeRole({
    required ClubRole actor,
    required ClubRole target,
    required ClubRole next,
  }) {
    return actor.canManageMemberRole(target) && actor.canAssignRole(next);
  }

  static bool canRemoveMember({
    required ClubRole actor,
    required ClubRole target,
  }) {
    return actor.canRemoveRole(target);
  }
}
