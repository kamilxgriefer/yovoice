const {
  fail, requireExactInput, requireId, requireRequestId, transactionGetAll,
} = require("../integrity/guards");
const {
  MAX_SERVER_CHANNELS, accessPolicy, canonicalChannelId, categoryId,
  channelCreationInput, revision, text, validatedPrivacy,
} = require("./contract");
const {
  canonicalChannel, canonicalMember, denied, grantMatches, policyAllowsMember, readChannelAccess,
  readServerAccess, requireServerManager,
} = require("./authority");
const { createServerOperations } = require("./operations");
const { channelDocument, channelRoomDocument, membershipMirror, writeChannelGrant } = require("./documents");
const { capturedRecipientTargets, convergenceState, readConvergenceBindings,
  stageConvergenceSessionEnd } = require("./convergence_lifecycle");

function mutationInput(data, extras = [], { channel = false } = {}) {
  const fields = ["serverId", "requestId", ...(channel ? ["channelId"] : []), ...extras];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    requestId: requireRequestId(data.requestId),
    ...(channel ? { channelId: requireId(data.channelId, "channelId") } : {}),
  };
}

function exactPatch(patch, allowed) {
  requireExactInput(patch, allowed);
  if (Object.keys(patch).length === 0) fail("invalid-argument", "The patch is empty.");
  return patch;
}

function requireExpected(actual, expected) {
  if (actual !== expected) fail("aborted", "This resource changed. Refresh before retrying this change.");
}

async function readCategory(transaction, serverReference, id) {
  if (id === null) return;
  const snapshot = await transaction.get(serverReference.collection("channelCategories").doc(id));
  if (!snapshot.exists || snapshot.data()?.status !== "active" ||
      snapshot.data()?.serverId !== serverReference.id) {
    fail("invalid-argument", "The selected category is unavailable.");
  }
}

function accessJobDocument({ identity, serverId, channelId, aclRevision, rtcTargets, now }) {
  return {
    schemaVersion: 1, kind: "channelAccess", serverId, channelId, aclRevision,
    operationId: identity.id, status: "pending", cursor: null,
    ...convergenceState(rtcTargets, { grantsComplete: false }),
    createdAt: now, updatedAt: now,
  };
}

function createServerChannelService(dependencies) {
  const { db } = dependencies;
  const operations = createServerOperations(dependencies);

  async function updateServerV1(request) {
    const input = mutationInput(request.data, ["expectedRevision", "patch"]);
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    const patch = exactPatch(request.data.patch, ["name", "description", "privacy", "defaultLanguage"]);
    input.patch = {};
    if (Object.hasOwn(patch, "name")) input.patch.name = text(patch.name, 40, "name", 3);
    if (Object.hasOwn(patch, "description")) input.patch.description = text(patch.description, 220, "description");
    if (Object.hasOwn(patch, "privacy")) input.patch.privacy = text(patch.privacy, 32, "privacy", 1);
    if (Object.hasOwn(patch, "defaultLanguage")) input.patch.defaultLanguage = text(patch.defaultLanguage, 64, "defaultLanguage", 1);
    return operations.execute(request, "server.update.v1", input, async ({ transaction, auth, prior, now, identity }) => {
      const access = requireServerManager(await readServerAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true,
      }), { ownerOnly: true });
      if (prior) return prior;
      requireExpected(access.server.revision, input.expectedRevision);
      if (Object.hasOwn(input.patch, "privacy")) validatedPrivacy(input.patch.privacy, access.server.serverType);
      const next = { ...access.server, ...input.patch, revision: access.server.revision + 1 };
      transaction.update(access.reference, { ...input.patch, revision: next.revision, updatedAt: now });
      transaction.set(db.doc(`users/${auth.uid}/clubs/${input.serverId}`), membershipMirror(input.serverId, next, access.member));
      transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
        schemaVersion: 1, kind: "serverMetadata", serverId: input.serverId,
        operationId: identity.id, revision: next.revision, status: "pending", cursor: null,
        createdAt: now, updatedAt: now,
      });
      return { serverId: input.serverId, revision: next.revision, propagationPending: true };
    });
  }

  async function createServerChannelV1(request) {
    const input = channelCreationInput(request.data);
    return operations.execute(request, "server.channel.create.v1", input, async ({ transaction, auth, prior, now }) => {
      const access = requireServerManager(await readServerAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId, allowHeld: true,
      }));
      const channelId = canonicalChannelId(input.serverId, `request:${auth.uid}:${input.requestId}`);
      const reference = access.reference.collection("channels").doc(channelId);
      if (prior) {
        await readChannelAccess({ db, transaction, uid: auth.uid, serverId: input.serverId,
          channelId, capability: "manage", allowHeld: true, allowArchived: true, serverAccess: access });
        return prior;
      }
      // Restricted creation is deliberately owner-only. An admin cannot mint
      // an inaccessible resource and mistake a global role for HR access.
      if (input.accessMode === "restricted" && access.member.role !== "owner") denied();
      await readCategory(transaction, access.reference, input.categoryId);
      const [existing, channelSnapshot] = await Promise.all([
        transaction.get(reference),
        transaction.get(access.reference.collection("channels").limit(MAX_SERVER_CHANNELS + 1)),
      ]);
      if (existing.exists) fail("data-loss", "A channel exists without its creation receipt.");
      if (channelSnapshot.size >= MAX_SERVER_CHANNELS) fail("resource-exhausted", "This server has reached its channel limit.");
      const positions = channelSnapshot.docs.map((doc) => doc.data().position);
      if (positions.some((position) => !Number.isSafeInteger(position) || position < 0 || position >= Number.MAX_SAFE_INTEGER - 1)) {
        fail("data-loss", "Channel positions need reconciliation.");
      }
      const channel = channelDocument({
        serverId: input.serverId, channelId, input, uid: auth.uid,
        position: positions.length === 0 ? 0 : Math.max(...positions) + 1, now,
      });
      if (channel.roomId && (await transaction.get(db.doc(`rooms/${channel.roomId}`))).exists) {
        fail("data-loss", "A channel room exists without its creation receipt.");
      }
      transaction.create(reference, channel);
      if (channel.roomId) transaction.create(db.doc(`rooms/${channel.roomId}`), channelRoomDocument({
        serverId: input.serverId, channelId, server: access.server, channel, now,
      }));
      if (channel.accessMode === "restricted") writeChannelGrant({
        db, transaction, serverId: input.serverId, channelId, channel, member: access.member, now,
      });
      transaction.update(access.reference, { revision: access.server.revision + 1, updatedAt: now });
      return { serverId: input.serverId, channelId, roomId: channel.roomId, revision: 1, aclRevision: 1 };
    });
  }

  async function updateServerChannelV1(request) {
    const input = mutationInput(request.data, ["expectedRevision", "patch"], { channel: true });
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    const patch = exactPatch(request.data.patch, ["name", "categoryId"]);
    input.patch = {};
    if (Object.hasOwn(patch, "name")) input.patch.name = text(patch.name, 80, "name", 1);
    if (Object.hasOwn(patch, "categoryId")) input.patch.categoryId = categoryId(patch.categoryId);
    return operations.execute(request, "server.channel.update.v1", input, async ({ transaction, auth, prior, now }) => {
      const access = await readChannelAccess({ db, transaction, uid: auth.uid, ...input,
        capability: "manage", allowHeld: true, allowArchived: true });
      if (prior) return prior;
      requireExpected(access.channel.revision, input.expectedRevision);
      if (Object.hasOwn(input.patch, "categoryId")) await readCategory(transaction, access.reference, input.patch.categoryId);
      let roomReference = null;
      if (access.channel.roomId && Object.hasOwn(input.patch, "name")) {
        roomReference = db.doc(`rooms/${access.channel.roomId}`);
        const room = await transaction.get(roomReference);
        if (!room.exists || room.data()?.serverId !== input.serverId || room.data()?.channelId !== input.channelId) denied();
      }
      const nextRevision = access.channel.revision + 1;
      transaction.update(access.channelReference, { ...input.patch, revision: nextRevision, updatedAt: now });
      if (roomReference) transaction.update(roomReference, { name: input.patch.name, updatedAt: now });
      transaction.update(access.reference, { revision: access.server.revision + 1, updatedAt: now });
      return { serverId: input.serverId, channelId: input.channelId, revision: nextRevision };
    });
  }

  async function reorderServerChannelsV1(request) {
    const input = mutationInput(request.data, ["expectedRevision", "channelIds"]);
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    if (!Array.isArray(request.data.channelIds) || request.data.channelIds.length > MAX_SERVER_CHANNELS) {
      fail("invalid-argument", "channelIds is invalid.");
    }
    input.channelIds = request.data.channelIds.map((id) => requireId(id, "channelId"));
    if (new Set(input.channelIds).size !== input.channelIds.length) fail("invalid-argument", "channelIds contains duplicates.");
    return operations.execute(request, "server.channels.reorder.v1", input, async ({ transaction, auth, prior, now }) => {
      const access = requireServerManager(await readServerAccess({ db, transaction, uid: auth.uid,
        serverId: input.serverId, allowHeld: true }));
      const snapshot = await transaction.get(access.reference.collection("channels").limit(MAX_SERVER_CHANNELS + 1));
      if (snapshot.size > MAX_SERVER_CHANNELS) fail("failed-precondition", "The channel set needs reconciliation.");
      const active = snapshot.docs.filter((doc) => doc.data().status === "active");
      const candidates = active.filter((doc) => policyAllowsMember(
        canonicalChannel(doc, input.serverId), auth.uid, access.member,
      ));
      const restricted = candidates.filter((doc) => doc.data().accessMode === "restricted");
      const grantSnapshots = restricted.length ? await transactionGetAll(transaction,
        ...restricted.map((doc) => doc.ref.collection("accessGrants").doc(auth.uid))) : [];
      const grants = new Map(restricted.map((doc, index) => [doc.id, grantSnapshots[index]]));
      const permitted = candidates.filter((doc) => doc.data().accessMode === "members" || grantMatches(
        grants.get(doc.id)?.data(), { uid: auth.uid, serverId: input.serverId, channelId: doc.id,
          member: access.member, channel: doc.data() },
      ));
      if (prior) return prior;
      requireExpected(access.server.revision, input.expectedRevision);
      if (permitted.length !== input.channelIds.length || permitted.some((doc) => !input.channelIds.includes(doc.id))) {
        fail("invalid-argument", "The exact current channel set is required.");
      }
      const byId = new Map(permitted.map((doc) => [doc.id, doc]));
      const slots = permitted.map((doc) => doc.data().position).sort((a, b) => a - b);
      const allPositions = active.map((doc) => doc.data().position);
      if (allPositions.some((position) => !Number.isSafeInteger(position) || position < 0) ||
          new Set(allPositions).size !== allPositions.length) fail("data-loss", "Channel positions need reconciliation.");
      // Hidden channels retain their exact slots. A manager submits only the
      // IDs the current ACL allows, never an inferred full private channel set.
      input.channelIds.forEach((id, index) => transaction.update(byId.get(id).ref, {
        position: slots[index], revision: byId.get(id).data().revision + 1, updatedAt: now,
      }));
      transaction.update(access.reference, { revision: access.server.revision + 1, updatedAt: now });
      return { serverId: input.serverId, revision: access.server.revision + 1 };
    });
  }

  async function setServerChannelAccessV1(request) {
    const input = mutationInput(request.data, ["expectedAclRevision", "policy"], { channel: true });
    input.expectedAclRevision = revision(request.data.expectedAclRevision, "expectedAclRevision");
    input.policy = accessPolicy(request.data.policy);
    return operations.execute(request, "server.channel.access.v1", input, async ({ transaction, auth, prior, now, identity }) => {
      const access = await readChannelAccess({ db, transaction, uid: auth.uid, ...input,
        capability: "manage", allowHeld: true, allowArchived: true });
      if (prior) return prior;
      requireExpected(access.channel.aclRevision, input.expectedAclRevision);
      const subjects = [...new Set([access.server.ownerId, auth.uid, ...input.policy.userIds])];
      const snapshots = await transactionGetAll(transaction,
        ...subjects.map((uid) => access.reference.collection("members").doc(uid)));
      const members = snapshots.map((snapshot, index) => canonicalMember(snapshot, subjects[index], access.server));
      const bindings = await readConvergenceBindings({ db, transaction, serverId: input.serverId,
        server: access.server, channels: [{ id: input.channelId, reference: access.channelReference, channel: access.channel }] });
      const channel = { ...access.channel, accessMode: input.policy.accessMode,
        accessPolicy: input.policy, isPrivate: input.policy.accessMode === "restricted",
        aclRevision: access.channel.aclRevision + 1, revision: access.channel.revision + 1 };
      transaction.update(access.channelReference, {
        accessMode: channel.accessMode, accessPolicy: channel.accessPolicy, isPrivate: channel.isPrivate,
        aclRevision: channel.aclRevision, revision: channel.revision, updatedAt: now,
      });
      members.forEach((member) => writeChannelGrant({ db, transaction,
        serverId: input.serverId, channelId: input.channelId, channel, member, now }));
      // Old grants are invalid immediately; the outbox grants current role
      // members in bounded pages and must also revoke live media downstream.
      transaction.create(db.doc(`serverControlOutbox/${identity.id}`), accessJobDocument({
        identity, serverId: input.serverId, channelId: input.channelId,
        aclRevision: channel.aclRevision, rtcTargets: capturedRecipientTargets(bindings), now,
      }));
      transaction.update(access.reference, { revision: access.server.revision + 1, updatedAt: now });
      return { serverId: input.serverId, channelId: input.channelId,
        aclRevision: channel.aclRevision, revision: channel.revision, propagationPending: true };
    });
  }

  async function terminateChannel(request, deleting) {
    const input = mutationInput(request.data, [], { channel: true });
    const kind = deleting ? "server.channel.delete.v1" : "server.channel.archive.v1";
    return operations.execute(request, kind, input, async ({ transaction, auth, prior, now, identity }) => {
      const parent = requireServerManager(await readServerAccess({ db, transaction, uid: auth.uid,
        serverId: input.serverId, allowHeld: true }));
      const access = await readChannelAccess({ db, transaction, uid: auth.uid, ...input,
        capability: "manage", allowHeld: true, allowArchived: true,
        allowDeleting: deleting && prior !== null, serverAccess: parent });
      if (prior) return prior;
      const bindings = await readConvergenceBindings({ db, transaction, serverId: input.serverId,
        server: access.server, channels: [{ id: input.channelId, reference: access.channelReference, channel: access.channel }] });
      const item = bindings[0];
      const roomReference = item?.roomReference ?? null;
      const sessionId = item?.session?.sessionId ?? null;
      const ending = item ? stageConvergenceSessionEnd({ db, transaction, item, identity, now })
        : { target: null, roomPatch: {}, channelPatch: {} };
      const status = deleting ? "deleting" : "archived";
      transaction.update(access.channelReference, {
        status, activeSessionId: null, aclRevision: access.channel.aclRevision + 1,
        revision: access.channel.revision + 1, updatedAt: now,
      });
      writeChannelGrant({ db, transaction, serverId: input.serverId, channelId: input.channelId,
        channel: { ...access.channel, status, aclRevision: access.channel.aclRevision + 1 },
        member: access.member, now });
      if (roomReference) transaction.update(roomReference, {
        status: deleting ? "deleting" : "archived", isLive: false,
        voiceSessionId: null, livekitRoomName: null, ...ending.roomPatch, updatedAt: now,
      });
      const defaults = {};
      if (access.server.defaultChatChannelId === input.channelId) defaults.defaultChatChannelId = null;
      if (access.server.defaultVoiceChannelId === input.channelId) {
        defaults.defaultVoiceChannelId = null;
        defaults.loungeRoomId = null;
      }
      if (access.server.announcementChannelId === input.channelId) defaults.announcementChannelId = null;
      transaction.update(access.reference, { ...defaults, revision: access.server.revision + 1, updatedAt: now });
      transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
        schemaVersion: 1, kind: deleting ? "channelDelete" : "channelArchive",
        serverId: input.serverId, channelId: input.channelId, roomId: access.channel.roomId,
        sessionId, operationId: identity.id, aclRevision: access.channel.aclRevision + 1,
        status: "pending", cursor: null, createdAt: now, updatedAt: now,
        ...convergenceState(ending.target ? [ending.target] : [], { contentCleanupPending: deleting }),
      });
      return { serverId: input.serverId, channelId: input.channelId, status, cleanupPending: true };
    });
  }

  return {
    updateServerV1, createServerChannelV1, updateServerChannelV1,
    reorderServerChannelsV1, setServerChannelAccessV1,
    archiveServerChannelV1: (request) => terminateChannel(request, false),
    deleteServerChannelV1: (request) => terminateChannel(request, true),
  };
}

module.exports = { accessJobDocument, createServerChannelService, mutationInput, requireExpected };
