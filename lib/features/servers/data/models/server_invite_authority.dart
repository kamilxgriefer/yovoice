/// Who may offer `Zaproś`, mirroring `canInviteToServer` in
/// `functions/servers/authority.js`.
///
/// The client decides which affordance to OFFER; `createServerInviteV1`
/// re-proves every part of this and is the only authority. A patched client
/// that calls the callable anyway is refused at issuance, and again at
/// acceptance by `pendingInvitation`.
library;

import 'server.dart';
import 'server_member_role.dart';
import 'server_type.dart';

/// The exact condition `memberships.js` uses to admit somebody with no
/// invitation at all: a community or podcast root whose privacy is `public`.
///
/// Total and fail-closed — a legacy root carries no V1 privacy authority, and
/// `private` / `inviteOnly` are both "not publicly joinable" (no code path
/// distinguishes them), so both fall to the narrow set.
bool serverAdmitsPublicJoin(Server server) =>
    !server.isLegacy &&
    server.type.allowsPublic &&
    server.privacy == ServerPrivacy.public;

/// On a server anyone may already join without an invitation, an invitation
/// grants no access — it is a pointer, not a key — so every ordinary member
/// may send one. On every other server the invitation *is* the admission
/// capability, so it stays with the moderator roles.
///
/// `guest` is excluded deliberately: it is the demoted state an owner assigns
/// to a participant they want to keep but not trust, and `capabilitiesFor`
/// already denies it `write`, `joinVoice` and `startSession`. If a guest could
/// invite, demotion would stop being a control.
bool canInviteToServer(Server server, ServerMemberRole? role) {
  if (role == null) return false;
  // Moderator power first and unconditionally, so no affordance any role has
  // today — legacy roots included — is taken away by the widening below.
  if (role.canModerate) return true;
  return role == ServerMemberRole.member && serverAdmitsPublicJoin(server);
}
