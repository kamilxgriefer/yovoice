const {
  activeProfile, assertNotRestricted, fail, requireUid, timestampMillis, transactionGetAll,
} = require("../integrity/guards");
const {
  MAX_SERVER_CHANNELS, ROLE_POWER, ROLES, requireEnum, serverChannelRefId, serverInviteRefPath,
} = require("./contract");
const {
  admitsPublicJoin, canInviteToServer, canonicalChannel, canonicalMember, canonicalServer, denied,
  invitePredatesDeparture, readServerAccess, validRevision,
} = require("./authority");
const {
  hasFamilyServerCapacity, readOwnerAllocations, readServerOwnerGuards, requireFreeServerCapacity,
  writeCapacityGuards, writeOwnerGuards,
} = require("./capacity");
const { createServerOperations } = require("./operations");
const { friendshipGuardMatches } = require("./invites");
const { canonicalDisplayName, memberDocument, membershipMirror, writeChannelGrant } = require("./documents");
const { mutationInput } = require("./channels");
const { capturedRecipientTargets, convergenceState, readConvergenceBindings,
  stageConvergenceSessionEnd } = require("./convergence_lifecycle");

function count(value, label) {
  if (!Number.isSafeInteger(value) || value < 1 || value >= Number.MAX_SAFE_INTEGER) {
    fail("data-loss", `The ${label} counter needs reconciliation.`);
  }
  return value;
}

function authorizationReference(serverReference, uid) {
  return serverReference.collection("memberAuthorizations").doc(uid);
}

function authorizationRevision(snapshot, uid, member = null) {
  if (!snapshot.exists) return member?.authorizationRevision ?? 0;
  const state = snapshot.data();
  if (state.schemaVersion !== 1 || state.userId !== uid || !validRevision(state.revision) ||
      !["member", "left"].includes(state.status) ||
      (member && (state.status !== "member" || state.revision !== member.authorizationRevision))) {
    fail("data-loss", "The membership authorization record needs reconciliation.");
  }
  return state.revision;
}

function writeAuthorization(transaction, reference, uid, revision, status, now) {
  transaction.set(reference, { schemaVersion: 1, userId: uid, revision, status, updatedAt: now });
}

async function readGrantChannels(transaction, serverReference) {
  const snapshot = await transaction.get(serverReference.collection("channels").limit(MAX_SERVER_CHANNELS + 1));
  if (snapshot.size > MAX_SERVER_CHANNELS) fail("failed-precondition", "The channel set needs reconciliation.");
  return snapshot.docs.map((doc) => ({ reference: doc.ref, id: doc.id, channel: doc.data() }));
}

function refreshMemberGrants({ db, transaction, serverId, channels, member, now, remove = false }) {
  for (const item of channels) {
    if (remove || item.channel.status === "deleting") {
      transaction.delete(item.reference.collection("accessGrants").doc(member.userId));
      transaction.delete(db.doc(`users/${member.userId}/serverChannelRefs/${serverChannelRefId(serverId, item.id)}`));
    } else {
      canonicalChannel({ exists: true, data: () => item.channel }, serverId, { allowArchived: true });
      writeChannelGrant({ db, transaction, serverId, channelId: item.id, channel: item.channel, member, now });
    }
  }
}

function membershipOutbox({ db, transaction, identity, serverId, uid, revision, kind, bindings, now }) {
  transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
    schemaVersion: 1, kind, serverId, userId: uid, membershipRevision: revision,
    operationId: identity.id, status: "pending", cursor: null, createdAt: now, updatedAt: now,
    ...convergenceState(capturedRecipientTargets(bindings, uid)),
  });
}

function lifecycleInvitation(snapshot, serverId, uid) {
  const invite = snapshot?.exists ? snapshot.data() : null;
  if (!invite || invite.serverSchemaVersion !== 1 || invite.serverId !== serverId ||
      invite.inviteeId !== uid || invite.status !== "pending" ||
      !validRevision(invite.generation)) return null;
  return invite;
}

function retireMembershipInvitation({ db, transaction, reference, serverId, uid,
  snapshot, now, status, actorUid = null }) {
  transaction.delete(db.doc(serverInviteRefPath(uid, serverId)));
  const invite = lifecycleInvitation(snapshot, serverId, uid);
  if (!invite) return null;
  if (status === "accepted") {
    transaction.update(reference.collection("invites").doc(uid), {
      status: "accepted", respondedAt: now, updatedAt: now,
    });
  } else if (status === "revoked") {
    transaction.update(reference.collection("invites").doc(uid), {
      status: "revoked", revokedAt: now, revokedById: requireUid(actorUid, "actorUid"), updatedAt: now,
    });
  } else {
    throw new TypeError("A terminal invitation status is required.");
  }
  return invite;
}

async function pendingInvitation({ db, transaction, reference, server, uid, nowMs,
  snapshot, authorization, requireAdmissionPolicy = true }) {
  const inviteReference = reference.collection("invites").doc(uid);
  const invite = snapshot.exists ? snapshot.data() : null;
  if (!invite || invite.serverSchemaVersion !== 1 || invite.serverId !== reference.id ||
      invite.inviteeId !== uid || invite.status !== "pending" ||
      !validRevision(invite.generation) || !validRevision(invite.inviterAuthorizationRevision) ||
      timestampMillis(invite.expiresAt) === null || timestampMillis(invite.expiresAt) <= nowMs ||
      typeof invite.inviterId !== "string") denied();
  // A pending document from before the most recent departure can never be a
  // re-entry capability. New invitations remain possible because every
  // re-issue receives a fresh createdAt after the canonical `left` ledger.
  if (invitePredatesDeparture(invite, authorization, uid)) denied();
  requireUid(invite.inviterId);
  // Declining only narrows access and must stay available after either party
  // blocks, unfriends or becomes communication-restricted. Accepting (and the
  // implicit private join path) re-proves the complete issuance policy so a
  // seven-day-old capability cannot outlive the relationship that allowed it.
  if (!requireAdmissionPolicy) return { invite, inviteReference };
  const [inviterSnapshot, inviterProfile, inviterRestriction,
    inviterBlock, inviteeBlock, inviterGuard, inviteeGuard] =
    await transactionGetAll(transaction,
      reference.collection("members").doc(invite.inviterId),
      db.doc(`users/${invite.inviterId}`),
      db.doc(`restrictions/${invite.inviterId}`),
      db.doc(`users/${invite.inviterId}/blocked/${uid}`),
      db.doc(`users/${uid}/blocked/${invite.inviterId}`),
      db.doc(`friendshipGuards/${invite.inviterId}/friends/${uid}`),
      db.doc(`friendshipGuards/${uid}/friends/${invite.inviterId}`));
  const inviter = canonicalMember(inviterSnapshot, invite.inviterId, server);
  // The complete issuance policy, re-proved against the CURRENT root: an
  // owner's public → private flip takes an outstanding member-issued
  // invitation with it instead of letting a seven-day-old pointer become a key.
  if (!canInviteToServer(server, inviter) || inviter.authorizationRevision !== invite.inviterAuthorizationRevision) denied();
  try {
    activeProfile(inviterProfile, "Inviting");
    assertNotRestricted(inviterRestriction, "Inviting", nowMs);
  } catch {
    denied();
  }
  if (inviterBlock.exists || inviteeBlock.exists ||
      !friendshipGuardMatches(inviterGuard, invite.inviterId, uid) ||
      !friendshipGuardMatches(inviteeGuard, uid, invite.inviterId)) denied();
  return { invite, inviteReference };
}

function createServerMembershipService(dependencies) {
  const { db } = dependencies;
  const operations = createServerOperations(dependencies);

  async function admission(request, respond) {
    const input = mutationInput(request.data, respond ? ["response"] : []);
    if (respond) input.response = requireEnum(request.data.response, ["accept", "decline"], "response");
    return operations.execute(request, respond ? "server.invite.respond.v1" : "server.join.v1", input, async ({
      transaction, auth, profile, prior, now, nowMs, identity,
    }) => {
      const reference = db.doc(`clubs/${input.serverId}`);
      const memberReference = reference.collection("members").doc(auth.uid);
      const revisionReference = authorizationReference(reference, auth.uid);
      const inviteReference = reference.collection("invites").doc(auth.uid);
      const [rootSnapshot, existing, revisionSnapshot, inviteSnapshot] = await transactionGetAll(transaction,
        reference, memberReference, revisionReference, inviteReference);
      const server = canonicalServer(rootSnapshot);
      if (existing.exists) {
        const member = canonicalMember(existing, auth.uid, server);
        if (prior) return prior;
        if (respond) fail("failed-precondition", "You already belong to this server.");
        return { serverId: input.serverId, joined: true, alreadyMember: true, membershipRevision: member.authorizationRevision };
      }
      if (prior) {
        // A previously declined receipt is retryable only against that same
        // canonical invite generation; accepting again after leaving is not.
        if (respond && input.response === "decline") {
          const invite = await transaction.get(reference.collection("invites").doc(auth.uid));
          if (invite.exists && invite.data()?.inviteeId === auth.uid && invite.data()?.status === "declined" &&
              invite.data()?.generation === prior.inviteGeneration) return prior;
        }
        denied();
      }
      // One helper, shared with the inviter predicate: if these two ever
      // drifted, a server would exist where a member may invite but the
      // invitee cannot join without that invitation — which silently turns an
      // ordinary member into an admission granter.
      const publicJoin = !respond && admitsPublicJoin(server);
      const invitation = publicJoin ? null : await pendingInvitation({
        db, transaction, reference, server, uid: auth.uid, nowMs,
        snapshot: inviteSnapshot, authorization: revisionSnapshot,
        requireAdmissionPolicy: !(respond && input.response === "decline"),
      });
      if (respond && input.response === "decline") {
        transaction.update(invitation.inviteReference, { status: "declined", respondedAt: now, updatedAt: now });
        // An answered invitation is no longer discoverable; the document
        // itself stays so a decline receipt keeps binding to its generation.
        transaction.delete(db.doc(serverInviteRefPath(auth.uid, input.serverId)));
        return { serverId: input.serverId, response: "decline", inviteGeneration: invitation.invite.generation };
      }
      const channels = await readGrantChannels(transaction, reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId: input.serverId, server, channels });
      const nextRevision = authorizationRevision(revisionSnapshot, auth.uid) + 1;
      if (!validRevision(nextRevision)) fail("data-loss", "Membership revision is exhausted.");
      const member = memberDocument(auth.uid, profile, "member", now, invitation?.invite.inviterId ?? null, nextRevision);
      const memberCount = count(server.memberCount, "member");
      transaction.create(memberReference, member);
      writeAuthorization(transaction, revisionReference, auth.uid, nextRevision, "member", now);
      transaction.set(db.doc(`users/${auth.uid}/clubs/${input.serverId}`), membershipMirror(input.serverId, server, member));
      refreshMemberGrants({ db, transaction, serverId: input.serverId, channels, member, now });
      if (invitation) {
        transaction.update(invitation.inviteReference, { status: "accepted", respondedAt: now, updatedAt: now });
        transaction.delete(db.doc(serverInviteRefPath(auth.uid, input.serverId)));
      } else if (publicJoin) {
        // Public admission supersedes an outstanding invitation. Retiring it
        // prevents that old generation from becoming a private re-entry path
        // after the member later leaves or is removed.
        retireMembershipInvitation({ db, transaction, reference, serverId: input.serverId,
          uid: auth.uid, snapshot: inviteSnapshot, now, status: "accepted" });
      }
      transaction.update(reference, { memberCount: memberCount + 1, revision: server.revision + 1, updatedAt: now });
      membershipOutbox({ db, transaction, identity, serverId: input.serverId, uid: auth.uid, revision: nextRevision,
        kind: "memberJoined", bindings, now });
      return { serverId: input.serverId, joined: true, alreadyMember: false, membershipRevision: nextRevision,
        ...(invitation ? { inviteGeneration: invitation.invite.generation } : {}) };
    }, { verified: input.response !== "decline", allowRestricted: input.response === "decline" });
  }

  async function leaveServerV1(request) {
    const input = mutationInput(request.data);
    return operations.execute(request, "server.leave.v1", input, async ({ transaction, auth, prior, now, identity }) => {
      const reference = db.doc(`clubs/${input.serverId}`);
      const memberReference = reference.collection("members").doc(auth.uid);
      const revisionReference = authorizationReference(reference, auth.uid);
      const inviteReference = reference.collection("invites").doc(auth.uid);
      const [rootSnapshot, existing, revisionSnapshot, inviteSnapshot] = await transactionGetAll(transaction,
        reference, memberReference, revisionReference, inviteReference);
      const server = canonicalServer(rootSnapshot);
      if (prior) {
        if (!existing.exists && authorizationRevision(revisionSnapshot, auth.uid) === prior.membershipRevision) return prior;
        fail("aborted", "Membership changed after the original leave request.");
      }
      const member = canonicalMember(existing, auth.uid, server);
      if (member.role === "owner") fail("failed-precondition", "Transfer ownership before leaving this server.");
      const nextRevision = authorizationRevision(revisionSnapshot, auth.uid, member) + 1;
      if (!validRevision(nextRevision)) fail("data-loss", "Membership revision is exhausted.");
      const channels = await readGrantChannels(transaction, reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId: input.serverId, server, channels });
      const memberCount = count(server.memberCount, "member");
      if (memberCount < 2) fail("data-loss", "Membership count needs reconciliation.");
      transaction.delete(memberReference);
      transaction.delete(db.doc(`users/${auth.uid}/clubs/${input.serverId}`));
      retireMembershipInvitation({ db, transaction, reference, serverId: input.serverId,
        uid: auth.uid, snapshot: inviteSnapshot, now, status: "revoked", actorUid: auth.uid });
      writeAuthorization(transaction, revisionReference, auth.uid, nextRevision, "left", now);
      refreshMemberGrants({ db, transaction, serverId: input.serverId, channels, member, now, remove: true });
      transaction.update(reference, { memberCount: memberCount - 1, revision: server.revision + 1, updatedAt: now });
      membershipOutbox({ db, transaction, identity, serverId: input.serverId, uid: auth.uid, revision: nextRevision,
        kind: "memberLeft", bindings, now });
      return { serverId: input.serverId, left: true, membershipRevision: nextRevision, cleanupPending: true };
    }, { verified: false, allowRestricted: true });
  }

  async function setServerMemberRoleV1(request) {
    const input = mutationInput(request.data, ["memberId", "role"]);
    input.memberId = requireUid(request.data.memberId, "memberId");
    input.role = requireEnum(request.data.role, ROLES.filter((role) => role !== "owner"), "role");
    return operations.execute(request, "server.member.role.v1", input, async ({ transaction, auth, prior, now, identity }) => {
      const access = await readServerAccess({ db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true });
      if (auth.uid === input.memberId || !["owner", "coOwner"].includes(access.member.role)) denied();
      const memberReference = access.reference.collection("members").doc(input.memberId);
      const revisionReference = authorizationReference(access.reference, input.memberId);
      const [snapshot, authorization, profileSnapshot] = await transactionGetAll(transaction,
        memberReference, revisionReference, db.doc(`users/${input.memberId}`));
      const member = canonicalMember(snapshot, input.memberId, access.server);
      activeProfile(profileSnapshot, "Member");
      if (member.role === "owner" || ROLE_POWER[access.member.role] <= ROLE_POWER[member.role] ||
          ROLE_POWER[access.member.role] <= ROLE_POWER[input.role]) denied();
      if (prior) return prior;
      const nextRevision = authorizationRevision(authorization, input.memberId, member) + 1;
      if (!validRevision(nextRevision)) fail("data-loss", "Membership revision is exhausted.");
      const channels = await readGrantChannels(transaction, access.reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId: input.serverId, server: access.server, channels });
      const next = { ...member, role: input.role, authorizationRevision: nextRevision };
      transaction.update(memberReference, { role: input.role, authorizationRevision: nextRevision });
      writeAuthorization(transaction, revisionReference, input.memberId, nextRevision, "member", now);
      transaction.set(db.doc(`users/${input.memberId}/clubs/${input.serverId}`), membershipMirror(input.serverId, access.server, next));
      refreshMemberGrants({ db, transaction, serverId: input.serverId, channels, member: next, now });
      transaction.update(access.reference, { revision: access.server.revision + 1, updatedAt: now });
      membershipOutbox({ db, transaction, identity, serverId: input.serverId, uid: input.memberId, revision: nextRevision,
        kind: "memberRoleChanged", bindings, now });
      return { serverId: input.serverId, memberId: input.memberId, role: input.role, membershipRevision: nextRevision, cleanupPending: true };
    });
  }

  async function transferServerOwnershipV1(request) {
    const input = mutationInput(request.data, ["newOwnerId"]);
    input.newOwnerId = requireUid(request.data.newOwnerId, "newOwnerId");
    return operations.execute(request, "server.ownership.transfer.v1", input, async ({ transaction, auth, prior, now, identity }) => {
      if (prior) {
        const [root, membership] = await transactionGetAll(transaction,
          db.doc(`clubs/${input.serverId}`), db.doc(`clubs/${input.serverId}/members/${auth.uid}`));
        const server = canonicalServer(root, { allowHeld: true });
        const member = canonicalMember(membership, auth.uid, server);
        if (server.ownerId === input.newOwnerId && member.role === "coOwner") return prior;
        denied();
      }
      const access = await readServerAccess({ db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true });
      if (access.member.role !== "owner" || input.newOwnerId === auth.uid) denied();
      if (!["freeServersV1", "familyFreeV1", "legacyRoomV1"].includes(access.server.entitlementPolicyId)) {
        fail("failed-precondition", "This retained entitlement requires its ownership adapter.");
      }
      const newOwnerReference = access.reference.collection("members").doc(input.newOwnerId);
      const oldAuthorizationReference = authorizationReference(access.reference, auth.uid);
      const newAuthorizationReference = authorizationReference(access.reference, input.newOwnerId);
      const [targetSnapshot, targetProfile, oldAuthorization, newAuthorization] = await transactionGetAll(transaction,
        newOwnerReference, db.doc(`users/${input.newOwnerId}`), oldAuthorizationReference, newAuthorizationReference);
      const target = canonicalMember(targetSnapshot, input.newOwnerId, access.server);
      const profile = activeProfile(targetProfile, "New owner");
      const ownerName = canonicalDisplayName(profile);
      const oldRevision = authorizationRevision(oldAuthorization, auth.uid, access.member) + 1;
      const newRevision = authorizationRevision(newAuthorization, input.newOwnerId, target) + 1;
      if (!validRevision(oldRevision) || !validRevision(newRevision)) fail("data-loss", "Membership revision is exhausted.");
      // Read the transferred server's bounded media graph before acquiring the
      // destination owner's contention-sensitive capacity snapshot. Firestore
      // may abort that owner query as soon as a racing creator changes its
      // result; issuing further reads after that point can surface the closed
      // transaction attempt instead of letting the SDK retry the callback.
      const channels = await readGrantChannels(transaction, access.reference);
      const roomItems = await readConvergenceBindings({ db, transaction, serverId: input.serverId, server: access.server, channels });
      // Lexical locking prevents opposing concurrent transfers from acquiring
      // overlapping owner locks in inconsistent order.
      const guards = new Map();
      for (const uid of [auth.uid, input.newOwnerId].sort()) guards.set(uid,
        await readServerOwnerGuards({ db, transaction, uid }));
      // Every transferred Server consumes one slot in the recipient's total
      // owned-server allowance. A family additionally needs the recipient's
      // separate one-family policy and reservation.
      const family = access.server.serverType === "family";
      if (family !== (access.server.entitlementPolicyId === "familyFreeV1")) {
        fail("data-loss", "The family allocation policy needs reconciliation.");
      }
      const targetCapacity = await readOwnerAllocations({
        db, transaction, uid: input.newOwnerId, now,
      });
      requireFreeServerCapacity(targetCapacity);
      let oldReservationReference;
      let newReservationReference;
      if (family) {
        oldReservationReference = db.doc(`serverFamilyOwnerReservations/${auth.uid}`);
        newReservationReference = db.doc(`serverFamilyOwnerReservations/${input.newOwnerId}`);
        const [oldReservation, newReservation] = await transactionGetAll(
          transaction, oldReservationReference, newReservationReference,
        );
        if (!oldReservation.exists || oldReservation.data()?.serverId !== input.serverId ||
            oldReservation.data()?.ownerId !== auth.uid) fail("data-loss", "The current family ownership reservation needs reconciliation.");
        if (newReservation.exists || !hasFamilyServerCapacity(targetCapacity)) {
          fail("resource-exhausted", "The new owner already owns a family server.");
        }
      }
      const newRoot = { ...access.server, ownerId: input.newOwnerId, ownerName };
      const formerOwner = { ...access.member, role: "coOwner", authorizationRevision: oldRevision };
      const newOwner = { ...target, role: "owner", authorizationRevision: newRevision };
      transaction.update(access.reference, { ownerId: input.newOwnerId, ownerName, revision: access.server.revision + 1, updatedAt: now });
      transaction.update(access.membershipReference, { role: "coOwner", authorizationRevision: oldRevision });
      transaction.update(newOwnerReference, { role: "owner", authorizationRevision: newRevision });
      writeAuthorization(transaction, oldAuthorizationReference, auth.uid, oldRevision, "member", now);
      writeAuthorization(transaction, newAuthorizationReference, input.newOwnerId, newRevision, "member", now);
      transaction.set(db.doc(`users/${auth.uid}/clubs/${input.serverId}`), membershipMirror(input.serverId, newRoot, formerOwner));
      transaction.set(db.doc(`users/${input.newOwnerId}/clubs/${input.serverId}`), membershipMirror(input.serverId, newRoot, newOwner));
      // BOTH owners' grants fail closed by their new membership revisions.
      // Projection reads current roles/ACLs later; no owner wildcard or old
      // private grant snapshot restores access. 100 live media channels cost
      // 400 writes plus 16 fixed writes including family guards and ledger.
      const rtcTargets = [];
      for (const item of roomItems) {
        const ending = stageConvergenceSessionEnd({ db, transaction, item, identity, now });
        if (ending.target) rtcTargets.push(ending.target);
        transaction.update(item.roomReference, {
          hostId: access.server.serverActivationState === "held" ? null : input.newOwnerId,
          serverOwnerId: input.newOwnerId, hostName: ownerName, hostPhotoUrl: null,
          isLive: false, voiceSessionId: null, livekitRoomName: null, ...ending.roomPatch, updatedAt: now,
        });
        if (item.channel.activeSessionId) {
          transaction.update(item.reference, { ...ending.channelPatch, revision: item.channel.revision + 1, updatedAt: now });
        }
      }
      if (family) {
        transaction.delete(oldReservationReference);
        transaction.create(newReservationReference, { schemaVersion: 1, ownerId: input.newOwnerId,
          serverId: input.serverId, status: "active", updatedAt: now });
      }
      writeOwnerGuards(transaction, guards.get(auth.uid), auth.uid, now);
      writeCapacityGuards(transaction, targetCapacity, input.newOwnerId, now);
      transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
        schemaVersion: 1, kind: "ownershipTransferred", serverId: input.serverId,
        previousOwnerId: auth.uid, newOwnerId: input.newOwnerId, operationId: identity.id,
        sessions: rtcTargets.map((target) => ({
          channelId: target.channelId, roomId: target.roomId, sessionId: target.sessionId,
        })),
        status: "pending", cursor: null, createdAt: now, updatedAt: now,
        ...convergenceState(rtcTargets, { grantsComplete: false }),
      });
      return { serverId: input.serverId, ownerId: input.newOwnerId, cleanupPending: true, propagationPending: true };
    });
  }

  return {
    joinServerV1: (request) => admission(request, false),
    respondToServerInviteV1: (request) => admission(request, true),
    leaveServerV1, setServerMemberRoleV1, transferServerOwnershipV1,
  };
}

module.exports = {
  authorizationReference, authorizationRevision, createServerMembershipService,
  lifecycleInvitation, membershipOutbox, pendingInvitation, readGrantChannels,
  refreshMemberGrants, retireMembershipInvitation,
  writeAuthorization,
};
