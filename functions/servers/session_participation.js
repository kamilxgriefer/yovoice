const {
  activeProfile, fail, requireBoolean, requireExactInput, requireId, requireRequestId,
  requireUid, transactionGetAll,
} = require("../integrity/guards");
const { ROLE_POWER, requireEnum } = require("./contract");
const { canonicalMember, denied, readBoundSessionAccess, validRevision } = require("./authority");
const { createServerOperations } = require("./operations");
const { convergenceState } = require("./convergence_lifecycle");
const { assertRoomBinding, assertSessionBinding, participantForSession } = require("./session_contract");

// The outbox kind that carries one participant's changed session authority to
// the existing convergence worker (convergence_runtime.js MEMBER_KINDS). Its
// single `recipient` target names exactly this generation and this identity,
// so `reconcileServerSessionParticipant` re-derives the person's grant from
// the participant document, sees a fingerprint the issued token no longer
// matches, and revokes that token with a positive provider cutoff.
const PARTICIPATION_KIND = "sessionParticipantChanged";
// The only roles a host or moderator may set. `host` is not assignable: it is
// bound to `channelSessions.startedById` (participantForSession) and changes
// only when a new generation starts.
const ASSIGNABLE_SESSION_ROLES = Object.freeze(["guest", "listener"]);

function participationInput(data, extras) {
  const keys = ["serverId", "channelId", "sessionId", "requestId", ...extras];
  requireExactInput(data, keys, keys);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    sessionId: requireId(data.sessionId, "sessionId"),
    requestId: requireRequestId(data.requestId),
  };
}

/**
 * Session participation (gap G5, contract decision C): promote or demote a
 * participant between `listener` and `guest`, raise or lower one's own hand,
 * and apply the host's or a moderator's mute. Every callable proves the same
 * reciprocal server/channel/room/session binding token issuance proves, so a
 * call naming another channel's or another generation's session id fails
 * closed before any participant document is read. Standing comes only from
 * the server role model on the channel ACL — the session host
 * (`startedById`) and members holding the channel's `moderate` capability
 * (owner, coOwner, admin, moderator) — never from a platform staff claim.
 *
 * Each authorized role or mute change bumps the participant's own
 * `authorizationRevision`, which the token authority fingerprint includes, so
 * the receipt of an already-issued token stops replaying at once and the
 * `sessionParticipantChanged` outbox job revokes the bearer through the
 * existing convergence worker. That holds for a promotion too: the recipient
 * ledger binds one fingerprint per identity per generation, so the person
 * re-mints a token under the new grant and reconnects. A promotion grants
 * permission only — the new token permits publishing; nothing here unmutes a
 * microphone, and `isMuted` stays the person's own capture consent.
 */
function createServerSessionParticipationService(dependencies) {
  const { db } = dependencies;
  const operations = createServerOperations(dependencies);

  async function readParticipationAccess({ transaction, uid, input }) {
    const access = await readBoundSessionAccess({ db, transaction, uid, ...input, capability: "joinVoice" });
    assertRoomBinding(access.room, access);
    assertSessionBinding(access.session, { ...input, roomId: access.roomReference.id });
    if (access.room.serverSessionCleanupId != null) fail("failed-precondition", "The previous media session is still being closed.");
    return {
      ...access,
      isHost: access.session.startedById === uid,
      isModerator: access.capabilities.moderate === true,
    };
  }

  /**
   * The target's participant document, validated exactly as token issuance
   * validates it, plus the target's canonical membership. A person who never
   * received a token has no document and cannot be governed: there is no
   * pre-admission role to set.
   */
  async function readTargetParticipant({ transaction, access, participantId }) {
    const reference = access.roomReference.collection("participants").doc(participantId);
    const [snapshot, memberSnapshot, profileSnapshot] = await transactionGetAll(transaction,
      reference, access.reference.collection("members").doc(participantId), db.doc(`users/${participantId}`));
    const member = canonicalMember(memberSnapshot, participantId, access.server);
    activeProfile(profileSnapshot, "Participant");
    if (!snapshot.exists) fail("failed-precondition", "This person has not joined the session.");
    const participant = participantForSession(snapshot, access, participantId);
    if (participant.authorizationRevision >= Number.MAX_SAFE_INTEGER - 1) fail("data-loss", "The participant authorization revision is exhausted.");
    return { reference, participant, member };
  }

  /**
   * Which standing lets the caller govern this target. The server hierarchy
   * outranks the session hierarchy: a host governs peers and everyone below
   * their own server role, a moderator governs only members they strictly
   * outrank (the `setServerMemberRoleV1` rule), and a moderator may always
   * act on themselves — nobody outranks themselves, and a moderator joining a
   * stage as a listener needs a way onto it. A plain member who started a
   * voice session therefore cannot mute or demote the server's admin, and an
   * admin cannot server-mute the owner.
   */
  function standingOver(access, uid, participantId, member) {
    const callerPower = ROLE_POWER[access.member.role];
    const targetPower = ROLE_POWER[member.role];
    const self = participantId === uid;
    return {
      host: access.isHost && !self && targetPower <= callerPower,
      moderator: access.isModerator && (self || targetPower < callerPower),
    };
  }

  function participationOutbox({ transaction, identity, access, participantId, revision, now }) {
    const target = {
      serverId: access.reference.id, channelId: access.channelReference.id,
      roomId: access.roomReference.id, sessionId: access.session.sessionId,
      livekitRoomName: access.livekitRoomName, mode: "recipient", userId: participantId,
    };
    transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
      schemaVersion: 1, kind: PARTICIPATION_KIND, serverId: access.reference.id,
      channelId: access.channelReference.id, sessionId: access.session.sessionId,
      userId: participantId, participantRevision: revision,
      operationId: identity.id, status: "pending", cursor: null, createdAt: now, updatedAt: now,
      ...convergenceState([target]),
    });
  }

  function receipt(access, participantId, participant, extra) {
    return {
      serverId: access.reference.id, channelId: access.channelReference.id,
      sessionId: access.session.sessionId, participantId,
      role: participant.role, hostMuted: participant.hostMuted, serverMuted: participant.serverMuted,
      participantRevision: participant.authorizationRevision, ...extra,
    };
  }

  async function setServerSessionParticipantRoleV1(request) {
    const input = participationInput(request.data, ["participantId", "role"]);
    input.participantId = requireUid(request.data.participantId, "participantId");
    input.role = requireEnum(request.data.role, ASSIGNABLE_SESSION_ROLES, "role");
    return operations.execute(request, "server.session.participant.role.v1", input, async ({
      transaction, auth, prior, now, identity,
    }) => {
      const { participantId, role, ...binding } = input;
      const access = await readParticipationAccess({ transaction, uid: auth.uid, input: binding });
      if (!access.isHost && !access.isModerator) denied();
      const target = await readTargetParticipant({ transaction, access, participantId });
      const standing = standingOver(access, auth.uid, participantId, target.member);
      if (!standing.host && !standing.moderator) denied();
      if (target.participant.role === "host") fail("failed-precondition", "The session host keeps the host role for this generation.");
      if (prior) return prior;
      if (target.participant.role === role) {
        return receipt(access, participantId, target.participant, { changed: false, cleanupPending: false });
      }
      const revision = target.participant.authorizationRevision + 1;
      if (!validRevision(revision)) fail("data-loss", "The participant authorization revision is exhausted.");
      const promotion = role === "guest";
      transaction.update(target.reference, {
        role, authorizationRevision: revision,
        // A promotion answers the request that raised the hand. A demotion
        // leaves the hand as it is: the person may still be asking.
        ...(promotion ? { isHandRaised: false, handRaisedAt: null } : {}),
        lastModeratedById: auth.uid, lastModeratedAt: now, updatedAt: now,
      });
      participationOutbox({ transaction, identity, access, participantId, revision, now });
      return receipt(access, participantId, { ...target.participant, role, authorizationRevision: revision },
        { changed: true, cleanupPending: true });
    });
  }

  async function setServerSessionHandV1(request) {
    const input = participationInput(request.data, ["raised"]);
    input.raised = requireBoolean(request.data.raised, "raised");
    return operations.execute(request, "server.session.hand.v1", input, async ({ transaction, auth, prior, now }) => {
      const { raised, ...binding } = input;
      const access = await readParticipationAccess({ transaction, uid: auth.uid, input: binding });
      const reference = access.roomReference.collection("participants").doc(auth.uid);
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) fail("failed-precondition", "Join the session before raising a hand.");
      const participant = participantForSession(snapshot, access, auth.uid);
      if (participant.role === "host") fail("failed-precondition", "The session host does not queue for the stage.");
      if (prior) return prior;
      if (participant.isHandRaised === raised) {
        return receipt(access, auth.uid, participant, { raised, changed: false });
      }
      // A hand is a request, not authority: the token fingerprint does not
      // include it, so no revision moves and no token is revoked.
      transaction.update(reference, { isHandRaised: raised, handRaisedAt: raised ? now : null, updatedAt: now });
      return receipt(access, auth.uid, participant, { raised, changed: true });
    });
  }

  async function setServerSessionMuteV1(request) {
    const input = participationInput(request.data, ["participantId", "muted"]);
    input.participantId = requireUid(request.data.participantId, "participantId");
    input.muted = requireBoolean(request.data.muted, "muted");
    return operations.execute(request, "server.session.mute.v1", input, async ({
      transaction, auth, prior, now, identity,
    }) => {
      const { participantId, muted, ...binding } = input;
      if (participantId === auth.uid) fail("invalid-argument", "Use your own microphone control to mute yourself.");
      const access = await readParticipationAccess({ transaction, uid: auth.uid, input: binding });
      if (!access.isHost && !access.isModerator) denied();
      const target = await readTargetParticipant({ transaction, access, participantId });
      const standing = standingOver(access, auth.uid, participantId, target.member);
      if (!standing.host && !standing.moderator) denied();
      if (prior) return prior;
      // The host's standing writes `hostMuted`; a moderator's writes
      // `serverMuted`; a caller holding both writes both. Either flag alone
      // removes the publish grant, so a host cannot lift a moderator's mute
      // and a moderator cannot lift the host's: each clears only its own.
      const patch = {};
      if (standing.host && target.participant.hostMuted !== muted) patch.hostMuted = muted;
      if (standing.moderator && target.participant.serverMuted !== muted) patch.serverMuted = muted;
      if (Object.keys(patch).length === 0) {
        return receipt(access, participantId, target.participant, { muted, changed: false, cleanupPending: false });
      }
      const revision = target.participant.authorizationRevision + 1;
      if (!validRevision(revision)) fail("data-loss", "The participant authorization revision is exhausted.");
      transaction.update(target.reference, {
        ...patch, authorizationRevision: revision,
        lastModeratedById: auth.uid, lastModeratedAt: now, updatedAt: now,
      });
      participationOutbox({ transaction, identity, access, participantId, revision, now });
      return receipt(access, participantId, { ...target.participant, ...patch, authorizationRevision: revision },
        { muted, changed: true, cleanupPending: true });
    });
  }

  return { setServerSessionParticipantRoleV1, setServerSessionHandV1, setServerSessionMuteV1 };
}

module.exports = { ASSIGNABLE_SESSION_ROLES, PARTICIPATION_KIND, createServerSessionParticipationService };
