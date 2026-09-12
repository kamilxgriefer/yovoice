const {
  activeProfile, assertNotRestricted, fail, requireUid, timestampMillis, transactionGetAll,
} = require("../integrity/guards");
const { SERVER_INVITE_TTL_MS, serverInviteRefPath } = require("./contract");
const {
  MODERATOR_ROLES, canonicalMember, denied, readServerAccess, validRevision,
} = require("./authority");
const { createServerOperations } = require("./operations");
const { canonicalDisplayName } = require("./documents");
const { mutationInput } = require("./channels");

// The roles that may issue an invitation are exactly the roles the consumer
// (memberships.js `pendingInvitation`) re-proves at acceptance time. Widening
// one side without the other would mint invitations nobody can accept.
const INVITER_ROLES = MODERATOR_ROLES;
const INVITE_STATUSES = Object.freeze(["pending", "accepted", "declined", "revoked"]);

/**
 * The canonical friendship authority (ADR-054 era `friendshipGuards`), read
 * the way direct messages and calls read it, never the client-writable
 * `users/{uid}/friends` mirror the legacy Club invite consults.
 */
function friendshipGuardMatches(snapshot, ownerId, friendId) {
  const guard = snapshot?.exists ? snapshot.data() : null;
  return Boolean(guard) && guard.schemaVersion === 1 && guard.ownerId === ownerId &&
    guard.friendId === friendId && timestampMillis(guard.establishedAt) !== null;
}

function canonicalInvite(invite, serverId, inviteeId) {
  return Boolean(invite) && invite.serverSchemaVersion === 1 && invite.serverId === serverId &&
    invite.inviteeId === inviteeId && INVITE_STATUSES.includes(invite.status) &&
    validRevision(invite.generation) && typeof invite.inviterId === "string";
}

function inviteSummary(serverId, inviteeId, invite, extra) {
  return {
    serverId, inviteeId, generation: invite.generation, status: invite.status,
    expiresAtMillis: timestampMillis(invite.expiresAt), ...extra,
  };
}

/**
 * V1 invitations (gap G1 of the stage-1 contract). The document consumed by
 * `respondToServerInviteV1` is written here and nowhere else: Rules keep
 * every client create/update at `false` and the legacy `sendClubInvite`
 * refuses versioned roots. A held server refuses invitations entirely — see
 * docs/Servers.md "Invitations" for why — so nothing about a server reaches
 * a non-owner before activation.
 */
function createServerInviteService(dependencies) {
  const { db, Timestamp } = dependencies;
  const operations = createServerOperations(dependencies);

  function inviteInput(data) {
    const input = mutationInput(data, ["inviteeId"]);
    input.inviteeId = requireUid(data.inviteeId, "inviteeId");
    return input;
  }

  async function createServerInviteV1(request) {
    const input = inviteInput(request.data);
    return operations.execute(request, "server.invite.create.v1", input, async ({
      transaction, auth, profile, prior, now, nowMs,
    }) => {
      if (input.inviteeId === auth.uid) fail("invalid-argument", "You cannot invite yourself.");
      // `allowHeld` stays false on purpose: a held server has no admission
      // path (`admission` in memberships.js denies a preparing root), so an
      // invitation to one would be undeliverable and would still disclose
      // the server's name to a third party before activation.
      const access = await readServerAccess({ db, transaction, uid: auth.uid, serverId: input.serverId });
      if (!INVITER_ROLES.includes(access.member.role)) denied();
      const inviteReference = access.reference.collection("invites").doc(input.inviteeId);
      const [
        inviteSnapshot, memberSnapshot, inviteeProfile, inviteeRestriction,
        inviterBlock, inviteeBlock, inviterGuard, inviteeGuard,
      ] = await transactionGetAll(transaction,
        inviteReference,
        access.reference.collection("members").doc(input.inviteeId),
        db.doc(`users/${input.inviteeId}`),
        db.doc(`restrictions/${input.inviteeId}`),
        db.doc(`users/${auth.uid}/blocked/${input.inviteeId}`),
        db.doc(`users/${input.inviteeId}/blocked/${auth.uid}`),
        db.doc(`friendshipGuards/${auth.uid}/friends/${input.inviteeId}`),
        db.doc(`friendshipGuards/${input.inviteeId}/friends/${auth.uid}`));
      const existing = inviteSnapshot.exists ? inviteSnapshot.data() : null;
      if (prior) {
        // A receipt is replayable only while the document still carries the
        // generation it issued; a later generation is a different invitation.
        if (canonicalInvite(existing, input.serverId, input.inviteeId) && existing.generation === prior.generation) return prior;
        fail("aborted", "The invitation changed after the original request.");
      }
      if (memberSnapshot.exists) fail("failed-precondition", "This person already belongs to this server.");
      // One denial for every invitee-state refusal. The callable must not be
      // an oracle for another account's ban, sanction, block or friendship
      // state, so blocked, sanctioned, inactive and non-friend targets all
      // answer exactly as the legacy sendClubInvite does: permission-denied.
      try {
        activeProfile(inviteeProfile, "Invitee");
        assertNotRestricted(inviteeRestriction, "Invitee", nowMs);
      } catch {
        denied();
      }
      if (inviterBlock.exists || inviteeBlock.exists) denied();
      if (!friendshipGuardMatches(inviterGuard, auth.uid, input.inviteeId) ||
          !friendshipGuardMatches(inviteeGuard, input.inviteeId, auth.uid)) denied();
      const currentlyPending = canonicalInvite(existing, input.serverId, input.inviteeId) &&
        existing.status === "pending" && validRevision(existing.inviterAuthorizationRevision) &&
        (timestampMillis(existing.expiresAt) ?? 0) > nowMs;
      if (currentlyPending) {
        // A pending invitation is reused only while its own inviter can still
        // stand behind it at acceptance time; otherwise it is dead on arrival
        // (`pendingInvitation` denies it) and this inviter re-issues it.
        let inviterStillAuthorized = existing.inviterId === auth.uid &&
          existing.inviterAuthorizationRevision === access.member.authorizationRevision;
        if (!inviterStillAuthorized && existing.inviterId !== auth.uid) {
          try {
            requireUid(existing.inviterId);
            const original = canonicalMember(await transaction.get(
              access.reference.collection("members").doc(existing.inviterId)), existing.inviterId, access.server);
            inviterStillAuthorized = INVITER_ROLES.includes(original.role) &&
              original.authorizationRevision === existing.inviterAuthorizationRevision;
          } catch {
            inviterStillAuthorized = false;
          }
        }
        if (inviterStillAuthorized) return inviteSummary(input.serverId, input.inviteeId, existing, { alreadyExisted: true });
      }
      // Every re-issue advances the generation, so a receipt, a decline or a
      // revocation bound to an older generation can never act on this one.
      const generation = (existing && validRevision(existing.generation) ? existing.generation : 0) + 1;
      if (!validRevision(generation)) fail("data-loss", "The invitation generation is exhausted.");
      const expiresAt = Timestamp.fromMillis(nowMs + SERVER_INVITE_TTL_MS);
      const invite = {
        serverSchemaVersion: 1, serverId: input.serverId, inviteeId: input.inviteeId,
        inviterId: auth.uid, inviterAuthorizationRevision: access.member.authorizationRevision,
        status: "pending", generation, expiresAt,
        // The only pre-join preview a V1 root permits (docs/Servers.md
        // "Channel listing and access"): bound to this exact generation,
        // expiry and inviter authority revision, and readable only by the
        // invitee and the server's managers. No channel, roster or count.
        serverName: access.server.name, inviterName: canonicalDisplayName(profile),
        createdAt: now, updatedAt: now,
      };
      // `set`, not `update`: an older generation's respondedAt/revokedAt must
      // not survive onto the new one.
      transaction.set(inviteReference, invite);
      transaction.set(db.doc(serverInviteRefPath(input.inviteeId, input.serverId)),
        { serverId: input.serverId, generation, expiresAt });
      return inviteSummary(input.serverId, input.inviteeId, invite, { alreadyExisted: false });
    }, { invite: true });
  }

  async function revokeServerInviteV1(request) {
    const input = inviteInput(request.data);
    return operations.execute(request, "server.invite.revoke.v1", input, async ({ transaction, auth, prior, now }) => {
      // Revocation only ever narrows: a held owner and a sanctioned manager
      // may both withdraw an invitation they could not currently issue.
      const access = await readServerAccess({ db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true });
      if (!INVITER_ROLES.includes(access.member.role)) denied();
      const inviteReference = access.reference.collection("invites").doc(input.inviteeId);
      const snapshot = await transaction.get(inviteReference);
      const existing = snapshot.exists ? snapshot.data() : null;
      if (prior) {
        if (canonicalInvite(existing, input.serverId, input.inviteeId) && existing.generation === prior.generation) return prior;
        fail("aborted", "The invitation changed after the original request.");
      }
      // The caller is an authorized manager of this server, so the absence
      // of an invitation is not private and may be disclosed.
      if (!canonicalInvite(existing, input.serverId, input.inviteeId)) fail("not-found", "No invitation exists for this person.");
      if (existing.status === "revoked") return inviteSummary(input.serverId, input.inviteeId, existing, { revoked: false });
      if (existing.status !== "pending") fail("failed-precondition", "This invitation was already answered.");
      transaction.update(inviteReference, { status: "revoked", revokedAt: now, revokedById: auth.uid, updatedAt: now });
      transaction.delete(db.doc(serverInviteRefPath(input.inviteeId, input.serverId)));
      return inviteSummary(input.serverId, input.inviteeId, { ...existing, status: "revoked" }, { revoked: true });
    }, { allowRestricted: true });
  }

  return { createServerInviteV1, revokeServerInviteV1 };
}

module.exports = { INVITER_ROLES, INVITE_STATUSES, createServerInviteService, friendshipGuardMatches };
