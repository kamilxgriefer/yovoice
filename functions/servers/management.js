// Servers V1 management parity (ADR-F).
//
// Club's MEMBER-facing spine already has V1 equivalents; its MANAGEMENT AND
// SAFETY half did not. This module is that half, and nothing else:
//
//   removeServerMemberV1   — a manager removes someone (R1)
//   setServerMemberBanV1   — a manager sets AND lifts a ban (R2); V1 already
//                            HONOURED `member.banned` (authority.js
//                            canonicalMember) with no writer anywhere
//   deleteServerV1         — the owner deletes the server (R3)
//
// plus the four staff adapters the legacy admin callables delegate to when
// their target is a versioned root (R4). The adapters are deliberately NOT
// callables: `functions/admin/clubs.js` keeps ownership of staff
// authentication, step-up, audit logging and its own client contract, and
// requires this module lazily so a legacy-only cold start never loads the
// server domain (the posture utils/server_access.js already established).
//
// Every writer here obeys the five properties the rest of functions/servers/*
// obeys, because a moderation action that skips one of them is a document
// edit rather than an enforcement:
//
//   1. the operation ledger and an idempotent requestId (operations.js), so a
//      retried removal is the same removal and never a second one;
//   2. `authorizationRevision` bumped on the target, with the matching
//      `memberAuthorizations/{uid}` record, so every grant and every issued
//      media token fails closed immediately;
//   3. a `serverControlOutbox` job, so the convergence worker actually ends
//      the removed or banned person's LIVE session rather than leaving them
//      connected to a room they were just thrown out of;
//   4. the single uniform `permission-denied` of authority.js — a missing,
//      foreign, held, suspended or higher-ranked target all answer the same,
//      so no callable here becomes an oracle for server or roster existence;
//   5. reads strictly before writes, inside one transaction.
//
// What this module does NOT do, on purpose:
//   - it never activates an existing root. New-root activation belongs only to
//     the exact registration-time creation capability;
//   - it never deletes content inline. It closes authority and writes the
//     fenced outbox state consumed by the bounded content cleanup worker;
//   - it never widens staff power. Each adapter does on a versioned root what
//     its legacy caller does on a Club, and no more.

const { randomUUID } = require("node:crypto");
const {
  activeProfile, digest, fail, isValidOpaqueUid, normalizeText, requireBoolean,
  requireId, requireUid, transactionGetAll,
} = require("../integrity/guards");
const { ROLES, ROLE_POWER, SERVER_TYPES } = require("./contract");
const {
  MODERATOR_ROLES, denied, readServerAccess, validRevision,
} = require("./authority");
const { createServerOperations } = require("./operations");
const { mutationInput } = require("./channels");
const {
  authorizationReference, authorizationRevision, membershipOutbox,
  readGrantChannels, refreshMemberGrants, retireMembershipInvitation, writeAuthorization,
} = require("./memberships");
const { membershipMirror } = require("./documents");
const {
  convergenceState, readConvergenceBindings, stageConvergenceSessionEnd,
} = require("./convergence_lifecycle");
const { readServerOwnerGuards, writeOwnerGuards } = require("./capacity");
const { deletionCleanupState } = require("./content_cleanup");

// Club's server-side removal authority, verbatim: functions/clubs/members.js
// REMOVAL_ROLES (`owner`, `coOwner`, `admin`, `moderator`) plus a strict
// power comparison. MODERATOR_ROLES is the same four roles, already canonical
// in authority.js, so the parity is by reuse and not by a second list that
// can drift.
const REMOVAL_ROLES = MODERATOR_ROLES;

const MAX_BAN_REASON = 500;

function memberCount(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value >= Number.MAX_SAFE_INTEGER) {
    fail("data-loss", "The member counter needs reconciliation.");
  }
  return value;
}

/**
 * `canonicalMember` minus the ban check, and nothing else.
 *
 * Lifting a ban has to read a banned member, and `canonicalMember` denies one
 * by design — that denial is the whole point of the ban. So the ban field is
 * validated here instead of being read as truthy: a `banned` that is neither
 * absent nor a real boolean is `data-loss`, never "banned" and never "not
 * banned". (The same string-vs-boolean confusion is a CONFIRMED finding on
 * the migration engine's `isPrivate === true`; it does not get to repeat here.)
 */
function managedMember(snapshot, uid, server) {
  const member = snapshot?.exists ? snapshot.data() : null;
  if (!member || member.userId !== uid || !ROLES.includes(member.role) ||
      !validRevision(member.authorizationRevision) ||
      ((member.role === "owner") !== (server.ownerId === uid))) denied();
  if (member.banned !== undefined && typeof member.banned !== "boolean") {
    fail("data-loss", "The membership ban state needs reconciliation.");
  }
  return member;
}

function isBanned(member) {
  return member.banned === true;
}

/** The status a non-suspended root of this activation state carries. */
function activeStatusFor(server) {
  return server.serverActivationState === "held" ? "preparing" : "active";
}

/**
 * `canonicalServer` for a STAFF target. Staff act on roots ordinary authority
 * refuses — a suspended one (restoring it is the point) and, for deletion, one
 * already marked — so exactly those two gates are relaxed here and only here.
 * Every other canonical property is re-stated rather than inherited, because
 * a staff writer that trusts a malformed root writes malformed enforcement.
 *
 * This is `not-found`, not the uniform `permission-denied`: the caller has
 * already proved verified staff authority through requireVerifiedStaff, so
 * there is no oracle left to protect and a moderator needs to be told the
 * difference between "no such server" and "I refuse".
 */
function staffServer(snapshot, { allowDeleting = false } = {}) {
  const data = snapshot?.exists ? snapshot.data() : null;
  if (!data) fail("not-found", "The selected server was not found.");
  const deleting = data.deletionInProgress === true;
  const expected = data.serverActivationState === "held" ? "preparing" : "active";
  if (data.serverSchemaVersion !== 1 || !SERVER_TYPES.includes(data.serverType) ||
      data.templateVersion !== 1 ||
      data.type !== (data.serverType === "family" ? "family" : "community") ||
      !["active", "held"].includes(data.serverActivationState) ||
      !["suspended", expected].includes(data.status) ||
      !validRevision(data.revision) || !isValidOpaqueUid(data.ownerId) ||
      (deleting && !allowDeleting)) {
    fail("failed-precondition", "This server needs reconciliation before a moderation action.");
  }
  // A HELD root is refused outright, in the uniform denial shape. It has never
  // been activated, nobody but its owner can reach it, and ADR-176 states this
  // whole surface has no activation writer — so the legacy staff path must not
  // become one by accident. `setClubModerationStatus(suspended: false)` on a
  // held root would otherwise be a restore that computes "preparing" and
  // silently does nothing, which reads like a staff action that worked.
  if (data.serverActivationState === "held") denied();
  return data;
}

/** A staff operation id: the same 64-hex grammar every ledger id and outbox
 * document already uses, so the dispatcher's `requireId` accepts it and a
 * document written by any other shape is visibly not ours. Computed ONCE per
 * call, outside the transaction, so a Firestore retry of that transaction
 * reuses the same id and cannot create a second job; the nonce keeps two
 * staff actions on the same member in the same millisecond from colliding. */
function staffOperationId(kind, serverId, subjectId, nowMs, nonce = randomUUID()) {
  return digest("server.staff.operation.v1", kind, serverId, subjectId ?? "", String(nowMs), nonce);
}

/**
 * The removal write set, shared by `removeServerMemberV1` and the staff
 * adapter behind `removeClubMember`. Identical to the tail of `leaveServerV1`
 * — that is deliberate: a manager's removal and a self-initiated leave must
 * converge on the same membership state, or "removed" and "left" become two
 * different kinds of non-member.
 */
function applyMemberRemoval({
  db, transaction, reference, server, serverId, memberId, member,
  authorization, inviteSnapshot, actorUid, channels, bindings, operationId, now,
}) {
  const next = authorizationRevision(authorization, memberId, member) + 1;
  if (!validRevision(next)) fail("data-loss", "Membership revision is exhausted.");
  const count = memberCount(server.memberCount);
  if (count < 2) fail("data-loss", "Membership count needs reconciliation.");
  transaction.delete(reference.collection("members").doc(memberId));
  transaction.delete(db.doc(`users/${memberId}/clubs/${serverId}`));
  retireMembershipInvitation({ db, transaction, reference, serverId, uid: memberId,
    snapshot: inviteSnapshot, now, status: "revoked", actorUid });
  writeAuthorization(transaction, authorizationReference(reference, memberId), memberId, next, "left", now);
  refreshMemberGrants({ db, transaction, serverId, channels, member, now, remove: true });
  transaction.update(reference, {
    memberCount: count - 1, revision: server.revision + 1, updatedAt: now,
  });
  membershipOutbox({
    db, transaction, identity: { id: operationId }, serverId, uid: memberId,
    revision: next, kind: "memberRemoved", bindings, now,
  });
  return next;
}

/**
 * The ban write set, for both directions. A ban that cannot be lifted is a
 * second defect, so `banned: false` is a first-class transition and not an
 * afterthought: it restores exactly the grants the ban removed, through the
 * same `refreshMemberGrants` both directions share.
 *
 * The membership document survives a ban on purpose. It is what keeps the ban
 * durable — `canonicalMember` denies the banned member, so they can neither
 * act, nor leave, nor re-join around it — and it is Club's behaviour
 * (`setClubMemberBan` sets a field on the member, it does not delete them),
 * which keeps `memberCount` meaning the same thing before and after.
 */
function applyMemberBan({
  db, transaction, reference, server, serverId, memberId, member, authorization,
  channels, bindings, banned, reason, actorUid, operationId, now,
}) {
  const next = authorizationRevision(authorization, memberId, member) + 1;
  if (!validRevision(next)) fail("data-loss", "Membership revision is exhausted.");
  const updated = { ...member, banned, authorizationRevision: next };
  transaction.update(reference.collection("members").doc(memberId), {
    banned,
    banReason: banned ? reason : null,
    bannedBy: banned ? actorUid : null,
    bannedAt: banned ? now : null,
    authorizationRevision: next,
  });
  writeAuthorization(transaction, authorizationReference(reference, memberId), memberId, next, "member", now);
  // A ban strips every private channel grant and its opaque discovery
  // pointer; lifting one re-derives both from the CURRENT roles and ACLs, so
  // no pre-ban grant snapshot is restored.
  refreshMemberGrants({ db, transaction, serverId, channels, member: updated, now, remove: banned });
  if (!banned) {
    transaction.set(db.doc(`users/${memberId}/clubs/${serverId}`), membershipMirror(serverId, server, updated));
  }
  transaction.update(reference, { revision: server.revision + 1, updatedAt: now });
  membershipOutbox({
    db, transaction, identity: { id: operationId }, serverId, uid: memberId,
    revision: next, kind: banned ? "memberBanned" : "memberBanLifted", bindings, now,
  });
  return next;
}

/**
 * The deletion write set. `endLive` is the ONE difference between the owner's
 * callable and the staff adapter, and it is a deliberate asymmetry:
 *
 *   - an owner must close the live session first (`endLive: false`). Deleting
 *     a server out from under a live room is the migration engine's own named
 *     failure, and an owner always has `endServerChannelSessionV1`;
 *   - staff must never be blocked by an abuser holding a session open
 *     (`endLive: true`), so the adapter stages the same authorized end the
 *     archive/transfer paths stage, through the same reviewed writer.
 *
 * The root is first marked `deletionInProgress`, which every canonical read
 * treats as closed. The outbox then drains content in bounded transactions
 * after every captured RTC generation has positively ended.
 */
function applyServerDeletion({
  db, transaction, reference, server, serverId, actorUid, bindings,
  guards, reservation, operationId, now, endLive,
}) {
  const targets = [];
  for (const item of bindings) {
    if (!item.session) continue;
    if (!endLive) fail("failed-precondition", "End the live session in this server before deleting it.");
    const ending = stageConvergenceSessionEnd({ db, transaction, item, identity: { id: operationId }, now });
    if (ending.target) targets.push(ending.target);
    // The room's own `status` is deliberately NOT moved to `deleting` here.
    // The root's `deletionInProgress` closes the complete server immediately;
    // the bounded worker removes the channel and room together after RTC ACK.
    transaction.update(item.roomReference, {
      isLive: false, voiceSessionId: null, livekitRoomName: null,
      ...ending.roomPatch, updatedAt: now,
    });
    transaction.update(item.reference, {
      ...ending.channelPatch, revision: item.channel.revision + 1, updatedAt: now,
    });
  }
  transaction.update(reference, {
    deletionInProgress: true, deletionRequestedBy: actorUid, deletionRequestedAt: now,
    deletionOperationId: operationId,
    revision: server.revision + 1, updatedAt: now,
  });
  // A family's one-per-owner reservation is released in THIS transaction, or
  // the owner loses families for good: createServerV1 fails closed on a
  // reservation whose server no longer exists, and firestore.rules refuses
  // the legacy family bootstrap while any reservation exists. Exactly what
  // clubs/deletion.js does, and only when the reservation names THIS server.
  if (reservation?.release) transaction.delete(reservation.reference);
  if (guards) writeOwnerGuards(transaction, guards, server.ownerId, now);
  transaction.create(db.doc(`serverControlOutbox/${operationId}`), {
    schemaVersion: 1, kind: "serverDelete", serverId, operationId,
    requestedBy: actorUid, status: "pending", cursor: null, createdAt: now, updatedAt: now,
    ...convergenceState(targets, { contentCleanupPending: true }),
    ...deletionCleanupState("serverDelete", {
      deletionRevision: server.revision + 1, ownerId: server.ownerId,
    }),
  });
  return targets;
}

/** Reads the family ownership reservation, if this server is a family and the
 * reservation names it. A reservation pointing somewhere else is left alone. */
async function readFamilyReservation({ db, transaction, server, serverId }) {
  if (server.serverType !== "family" && server.type !== "family") return null;
  const reference = db.doc(`serverFamilyOwnerReservations/${server.ownerId}`);
  const snapshot = await transaction.get(reference);
  const data = snapshot.exists ? snapshot.data() : null;
  return { reference, release: Boolean(data && data.serverId === serverId && data.ownerId === server.ownerId) };
}

function createServerManagementService(dependencies) {
  const { db, Timestamp, clock = Date.now } = dependencies;
  const operations = createServerOperations(dependencies);

  async function removeServerMemberV1(request) {
    const input = mutationInput(request.data, ["memberId"]);
    input.memberId = requireUid(request.data.memberId, "memberId");
    return operations.execute(request, "server.member.remove.v1", input, async ({
      transaction, auth, prior, now, identity,
    }) => {
      const access = await readServerAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true,
      });
      // Self-removal is `leaveServerV1`, which owns the owner check and the
      // restricted-caller allowance. Refusing it here keeps one writer per
      // membership transition instead of two that can disagree.
      if (auth.uid === input.memberId || !REMOVAL_ROLES.includes(access.member.role)) denied();
      const memberReference = access.reference.collection("members").doc(input.memberId);
      const revisionReference = authorizationReference(access.reference, input.memberId);
      const inviteReference = access.reference.collection("invites").doc(input.memberId);
      const [snapshot, authorization, inviteSnapshot] = await transactionGetAll(
        transaction, memberReference, revisionReference, inviteReference,
      );
      if (prior) {
        // The receipt is re-served only when the membership is still exactly
        // what this operation left behind. A member who rejoined since has a
        // new revision, and replaying the receipt would report them removed
        // while they are not. Same shape as leaveServerV1's replay branch.
        if (!snapshot.exists &&
            authorizationRevision(authorization, input.memberId) === prior.membershipRevision) return prior;
        fail("aborted", "Membership changed after the original removal request.");
      }
      const member = managedMember(snapshot, input.memberId, access.server);
      // The owner is unremovable, and rank is strict: equal rank cannot
      // remove equal rank. Same comparison as clubs/members.js.
      if (member.role === "owner" || access.server.ownerId === input.memberId ||
          ROLE_POWER[access.member.role] <= ROLE_POWER[member.role]) denied();
      const channels = await readGrantChannels(transaction, access.reference);
      const bindings = await readConvergenceBindings({
        db, transaction, serverId: input.serverId, server: access.server, channels,
      });
      const revision = applyMemberRemoval({
        db, transaction, reference: access.reference, server: access.server,
        serverId: input.serverId, memberId: input.memberId, member, authorization,
        inviteSnapshot, actorUid: auth.uid, channels, bindings, operationId: identity.id, now,
      });
      return {
        serverId: input.serverId, memberId: input.memberId, removed: true,
        membershipRevision: revision, cleanupPending: true,
      };
    });
  }

  async function setServerMemberBanV1(request) {
    const input = mutationInput(request.data, ["memberId", "banned", "reason"]);
    input.memberId = requireUid(request.data.memberId, "memberId");
    input.banned = requireBoolean(request.data.banned, "banned");
    // A lift carries no reason, and refusing one keeps a stale justification
    // from being recorded against an account that is no longer banned.
    input.reason = normalizeText(request.data.reason, MAX_BAN_REASON, "reason", { allowEmpty: true });
    if (input.banned && input.reason.length === 0) fail("invalid-argument", "A ban reason is required.");
    if (!input.banned && input.reason.length > 0) fail("invalid-argument", "Lifting a ban does not take a reason.");
    return operations.execute(request, "server.member.ban.v1", input, async ({
      transaction, auth, prior, now, identity,
    }) => {
      const access = await readServerAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true,
      });
      if (auth.uid === input.memberId || !REMOVAL_ROLES.includes(access.member.role)) denied();
      const memberReference = access.reference.collection("members").doc(input.memberId);
      const revisionReference = authorizationReference(access.reference, input.memberId);
      const [snapshot, authorization, profileSnapshot] = await transactionGetAll(
        transaction, memberReference, revisionReference, db.doc(`users/${input.memberId}`),
      );
      const member = managedMember(snapshot, input.memberId, access.server);
      if (member.role === "owner" || access.server.ownerId === input.memberId ||
          ROLE_POWER[access.member.role] <= ROLE_POWER[member.role]) denied();
      // Lifting a ban restores access, so the account behind it must still be
      // one that may hold access at all. Setting a ban does not care.
      if (!input.banned) activeProfile(profileSnapshot, "Member");
      if (prior) return prior;
      if (isBanned(member) === input.banned) {
        return {
          serverId: input.serverId, memberId: input.memberId, banned: input.banned,
          changed: false, membershipRevision: member.authorizationRevision, cleanupPending: false,
        };
      }
      const channels = await readGrantChannels(transaction, access.reference);
      const bindings = await readConvergenceBindings({
        db, transaction, serverId: input.serverId, server: access.server, channels,
      });
      const revision = applyMemberBan({
        db, transaction, reference: access.reference, server: access.server,
        serverId: input.serverId, memberId: input.memberId, member, authorization, channels,
        bindings, banned: input.banned, reason: input.banned ? input.reason : null,
        actorUid: auth.uid, operationId: identity.id, now,
      });
      return {
        serverId: input.serverId, memberId: input.memberId, banned: input.banned,
        changed: true, membershipRevision: revision, cleanupPending: true,
      };
    });
  }

  async function deleteServerV1(request) {
    const input = mutationInput(request.data);
    return operations.execute(request, "server.delete.v1", input, async ({
      transaction, auth, prior, now, identity,
    }) => {
      if (prior) {
        // A deleted root denies every subsequent authority read, so the
        // receipt is re-served only against the exact root this operation
        // marked — never against a rebuilt or foreign one.
        const snapshot = await transaction.get(db.doc(`clubs/${input.serverId}`));
        const root = snapshot.exists ? snapshot.data() : null;
        if (root && root.deletionInProgress === true && root.ownerId === auth.uid &&
            root.serverSchemaVersion === 1 && root.deletionOperationId === identity.id &&
            root.revision === prior.revision) return prior;
        if (!root) {
          const outbox = await transaction.get(db.doc(`serverControlOutbox/${identity.id}`));
          const job = outbox.exists ? outbox.data() : null;
          if (job?.schemaVersion === 1 && job.kind === "serverDelete" &&
              job.operationId === identity.id && job.serverId === input.serverId &&
              job.ownerId === auth.uid && job.requestedBy === auth.uid &&
              job.deletionRevision === prior.revision && job.status === "completed" &&
              job.contentCleanupPending === false) return prior;
        }
        denied();
      }
      const access = await readServerAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true,
      });
      if (access.member.role !== "owner") denied();
      const guards = await readServerOwnerGuards({ db, transaction, uid: auth.uid });
      const reservation = await readFamilyReservation({
        db, transaction, server: access.server, serverId: input.serverId,
      });
      const channels = await readGrantChannels(transaction, access.reference);
      const bindings = await readConvergenceBindings({
        db, transaction, serverId: input.serverId, server: access.server, channels,
      });
      applyServerDeletion({
        db, transaction, reference: access.reference, server: access.server,
        serverId: input.serverId, actorUid: auth.uid, bindings, guards, reservation,
        operationId: identity.id, now, endLive: false,
      });
      return {
        serverId: input.serverId, deleted: true, revision: access.server.revision + 1,
        cleanupPending: true, contentCleanupPending: true,
      };
    });
  }

  // ---------------------------------------------------------------------
  // Staff adapters (R4). Not callables. functions/admin/clubs.js owns staff
  // authentication, step-up, the audit log and the client contract; these
  // own the V1 invariants that a raw admin `set()` would silently skip.
  //
  // They take no requestId because their legacy callers have none, so
  // idempotence here is idempotence of STATE: re-running a suspension,
  // a ban, a removal or a deletion converges on the same document and
  // reports `changed: false` rather than writing a second time.
  // ---------------------------------------------------------------------

  function stamp() {
    const nowMs = clock();
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  async function readStaffTarget(transaction, serverId, { allowDeleting = false } = {}) {
    const reference = db.doc(`clubs/${requireId(serverId, "serverId")}`);
    const snapshot = await transaction.get(reference);
    return { reference, server: staffServer(snapshot, { allowDeleting }) };
  }

  async function staffSetServerModerationStatus({ serverId, suspended, reason, actorUid }) {
    requireUid(actorUid, "actorUid");
    requireBoolean(suspended, "suspended");
    const { nowMs, now } = stamp();
    const operationId = staffOperationId("moderation", serverId, actorUid, nowMs);
    return db.runTransaction(async (transaction) => {
      const { reference, server } = await readStaffTarget(transaction, serverId);
      const target = suspended ? "suspended" : activeStatusFor(server);
      if (server.status === target) return { changed: false, status: target, cleanupPending: false };
      const targets = [];
      if (suspended) {
        // A suspension that leaves the voice channel running suspends
        // nothing. Every live generation is ended through the SAME reviewed
        // writer archive and ownership transfer use.
        //
        // The media graph is read ONLY on the way in. A RESTORE must not be
        // blocked by an inconsistent graph: readConvergenceBindings refuses
        // one, and a moderator being unable to un-suspend a server because
        // its rooms need reconciliation is the wrong failure.
        const channels = await readGrantChannels(transaction, reference);
        const bindings = await readConvergenceBindings({ db, transaction, serverId, server, channels });
        for (const item of bindings) {
          if (!item.session) continue;
          const ending = stageConvergenceSessionEnd({ db, transaction, item, identity: { id: operationId }, now });
          if (ending.target) targets.push(ending.target);
          transaction.update(item.roomReference, {
            isLive: false, voiceSessionId: null, livekitRoomName: null, ...ending.roomPatch, updatedAt: now,
          });
          transaction.update(item.reference, {
            ...ending.channelPatch, revision: item.channel.revision + 1, updatedAt: now,
          });
        }
      }
      transaction.update(reference, {
        status: target,
        moderationReason: suspended ? reason ?? null : null,
        moderatedBy: actorUid,
        moderatedAt: now,
        revision: server.revision + 1,
        updatedAt: now,
      });
      if (targets.length > 0) {
        transaction.create(db.doc(`serverControlOutbox/${operationId}`), {
          schemaVersion: 1, kind: "serverModeration", serverId, operationId,
          requestedBy: actorUid, status: "pending", cursor: null, createdAt: now, updatedAt: now,
          ...convergenceState(targets),
        });
      }
      return { changed: true, status: target, cleanupPending: targets.length > 0, operationId };
    });
  }

  async function staffRemoveServerMember({ serverId, memberId, actorUid }) {
    requireUid(actorUid, "actorUid");
    requireUid(memberId, "memberId");
    const { nowMs, now } = stamp();
    const operationId = staffOperationId("member.remove", serverId, memberId, nowMs);
    return db.runTransaction(async (transaction) => {
      const { reference, server } = await readStaffTarget(transaction, serverId);
      // The owner is unremovable by staff too: legacy `removeClubMember`
      // refuses `club.ownerId === userId` and the owner role outright, and a
      // roster with no owner is not a state any V1 read can validate.
      if (server.ownerId === memberId) {
        fail("failed-precondition", "The server owner cannot be removed from the server.");
      }
      const memberReference = reference.collection("members").doc(memberId);
      const revisionReference = authorizationReference(reference, memberId);
      const inviteReference = reference.collection("invites").doc(memberId);
      const [snapshot, authorization, inviteSnapshot] = await transactionGetAll(
        transaction, memberReference, revisionReference, inviteReference,
      );
      if (!snapshot.exists) {
        // Same shape as legacy removeClubMember: an already-absent member is
        // reported, not an error, and the private projection is swept anyway.
        transaction.delete(db.doc(`users/${memberId}/clubs/${serverId}`));
        retireMembershipInvitation({ db, transaction, reference, serverId, uid: memberId,
          snapshot: inviteSnapshot, now, status: "revoked", actorUid });
        return { changed: false, alreadyRemoved: true, cleanupPending: false };
      }
      const member = managedMember(snapshot, memberId, server);
      if (member.role === "owner") {
        fail("failed-precondition", "The server owner cannot be removed from the server.");
      }
      const channels = await readGrantChannels(transaction, reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId, server, channels });
      const revision = applyMemberRemoval({
        db, transaction, reference, server, serverId, memberId, member, authorization,
        inviteSnapshot, actorUid, channels, bindings, operationId, now,
      });
      return { changed: true, alreadyRemoved: false, membershipRevision: revision, cleanupPending: true, operationId };
    });
  }

  async function staffSetServerMemberBan({ serverId, memberId, banned, reason, actorUid }) {
    requireUid(actorUid, "actorUid");
    requireUid(memberId, "memberId");
    requireBoolean(banned, "banned");
    const { nowMs, now } = stamp();
    const operationId = staffOperationId("member.ban", serverId, memberId, nowMs);
    return db.runTransaction(async (transaction) => {
      const { reference, server } = await readStaffTarget(transaction, serverId);
      if (server.ownerId === memberId) {
        fail("failed-precondition", "The server owner cannot be banned from their own server.");
      }
      const memberReference = reference.collection("members").doc(memberId);
      const revisionReference = authorizationReference(reference, memberId);
      const [snapshot, authorization] = await transactionGetAll(transaction, memberReference, revisionReference);
      if (!snapshot.exists) fail("not-found", "The selected user is not a member of this server.");
      const member = managedMember(snapshot, memberId, server);
      if (member.role === "owner") {
        fail("failed-precondition", "The server owner cannot be banned from their own server.");
      }
      if (isBanned(member) === banned) {
        return { changed: false, banned, membershipRevision: member.authorizationRevision, cleanupPending: false };
      }
      const channels = await readGrantChannels(transaction, reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId, server, channels });
      const revision = applyMemberBan({
        db, transaction, reference, server, serverId, memberId, member, authorization, channels,
        bindings, banned, reason: banned ? (reason ?? null) : null, actorUid, operationId, now,
      });
      return { changed: true, banned, membershipRevision: revision, cleanupPending: true, operationId };
    });
  }

  async function staffDeleteServer({ serverId, actorUid }) {
    requireUid(actorUid, "actorUid");
    const { nowMs, now } = stamp();
    const operationId = staffOperationId("delete", serverId, actorUid, nowMs);
    return db.runTransaction(async (transaction) => {
      const { reference, server } = await readStaffTarget(transaction, serverId, { allowDeleting: true });
      if (server.deletionInProgress === true) {
        return { changed: false, alreadyMarked: true, cleanupPending: true };
      }
      const guards = await readServerOwnerGuards({ db, transaction, uid: server.ownerId });
      const reservation = await readFamilyReservation({ db, transaction, server, serverId });
      const channels = await readGrantChannels(transaction, reference);
      const bindings = await readConvergenceBindings({ db, transaction, serverId, server, channels });
      const targets = applyServerDeletion({
        db, transaction, reference, server, serverId, actorUid, bindings, guards, reservation,
        operationId, now, endLive: true,
      });
      return {
        changed: true, alreadyMarked: false, cleanupPending: true,
        contentCleanupPending: true, endedSessions: targets.length, operationId,
      };
    });
  }

  return {
    removeServerMemberV1, setServerMemberBanV1, deleteServerV1,
    staffDeleteServer, staffRemoveServerMember, staffSetServerMemberBan,
    staffSetServerModerationStatus,
  };
}

module.exports = {
  MAX_BAN_REASON, REMOVAL_ROLES, applyMemberBan, applyMemberRemoval,
  applyServerDeletion, createServerManagementService, managedMember, staffOperationId,
};
