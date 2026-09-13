// Family server shared list. Every mutation is callable-only, replay-safe and
// reauthorizes the actor against the canonical server/channel ACL.

const {
  digest,
  fail,
  requireExactInput,
  requireId,
  requireRequestId,
} = require("../integrity/guards");
const {
  MODERATOR_ROLES,
  denied,
  readChannelAccess,
  validRevision,
} = require("./authority");
const { revision, text } = require("./contract");
const { createServerOperations } = require("./operations");

function canonicalListItemId(uid, requestId) {
  requireRequestId(requestId);
  return `li_${digest("server.list.create.v1", uid, requestId).slice(0, 40)}`;
}

function baseInput(data, extras = []) {
  const fields = ["serverId", "channelId", "requestId", ...extras];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
  };
}

function requireFamilyList(access) {
  if (access.server.serverType !== "family" || access.channel.kind !== "list") {
    denied();
  }
  return access;
}

function canonicalItem(snapshot, { serverId, channelId, itemId }) {
  if (!snapshot.exists) fail("not-found", "The selected list item is unavailable.");
  const item = snapshot.data() ?? {};
  if (item.schemaVersion !== 1 || item.serverId !== serverId ||
      item.channelId !== channelId || item.itemId !== itemId ||
      typeof item.text !== "string" || item.text.length < 1 ||
      typeof item.checked !== "boolean" ||
      typeof item.createdById !== "string" ||
      (item.checkedById !== null && typeof item.checkedById !== "string") ||
      !validRevision(item.revision) || !item.createdAt || !item.updatedAt) {
    fail("data-loss", "The list item needs reconciliation.");
  }
  return item;
}

function expectedRevision(actual, expected) {
  if (actual !== expected) {
    fail("aborted", "This list item changed. Refresh before retrying.");
  }
}

function nextRevision(value) {
  const next = value + 1;
  if (!validRevision(next)) fail("data-loss", "The list item revision is exhausted.");
  return next;
}

function createServerSharedListService(dependencies) {
  const { db } = dependencies;
  if (!db?.runTransaction) throw new TypeError("db is required.");
  const operations = createServerOperations(dependencies);

  async function createServerListItemV1(request) {
    const input = baseInput(request.data, ["text"]);
    input.text = text(request.data.text, 160, "text", 1);
    return operations.execute(request, "server.list.create.v1", input, async ({
      transaction, auth, prior, now,
    }) => {
      const access = requireFamilyList(await readChannelAccess({
        db,
        transaction,
        uid: auth.uid,
        serverId: input.serverId,
        channelId: input.channelId,
        capability: "write",
      }));
      const itemId = canonicalListItemId(auth.uid, input.requestId);
      const reference = access.channelReference.collection("listItems").doc(itemId);
      const existing = await transaction.get(reference);
      if (prior) {
        const item = canonicalItem(existing, { ...input, itemId });
        if (item.createdById === auth.uid && item.revision === prior.revision) {
          return prior;
        }
        fail("aborted", "The list item changed after the original request.");
      }
      if (existing.exists) {
        fail("data-loss", "A list item exists without its creation receipt.");
      }
      transaction.create(reference, {
        schemaVersion: 1,
        serverId: input.serverId,
        channelId: input.channelId,
        itemId,
        text: input.text,
        checked: false,
        checkedById: null,
        createdById: auth.uid,
        revision: 1,
        createdAt: now,
        updatedAt: now,
      });
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        itemId,
        revision: 1,
      };
    });
  }

  async function updateServerListItemV1(request) {
    const input = baseInput(request.data, ["itemId", "expectedRevision", "patch"]);
    input.itemId = requireId(request.data.itemId, "itemId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    requireExactInput(request.data.patch, ["text", "checked"]);
    if (Object.keys(request.data.patch).length === 0) {
      fail("invalid-argument", "The patch is empty.");
    }
    input.patch = {};
    if (Object.hasOwn(request.data.patch, "text")) {
      input.patch.text = text(request.data.patch.text, 160, "text", 1);
    }
    if (Object.hasOwn(request.data.patch, "checked")) {
      if (typeof request.data.patch.checked !== "boolean") {
        fail("invalid-argument", "checked is invalid.");
      }
      input.patch.checked = request.data.patch.checked;
    }
    return operations.execute(request, "server.list.update.v1", input, async ({
      transaction, auth, prior, now,
    }) => {
      const access = requireFamilyList(await readChannelAccess({
        db,
        transaction,
        uid: auth.uid,
        serverId: input.serverId,
        channelId: input.channelId,
        capability: "write",
      }));
      const reference = access.channelReference.collection("listItems").doc(input.itemId);
      const item = canonicalItem(await transaction.get(reference), input);
      if (prior) {
        if (item.revision === prior.revision) return prior;
        fail("aborted", "The list item changed after the original request.");
      }
      expectedRevision(item.revision, input.expectedRevision);
      const itemRevision = nextRevision(item.revision);
      const patch = {
        ...input.patch,
        revision: itemRevision,
        updatedAt: now,
      };
      if (Object.hasOwn(input.patch, "checked")) {
        patch.checkedById = input.patch.checked ? auth.uid : null;
      }
      transaction.update(reference, patch);
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        itemId: input.itemId,
        revision: itemRevision,
      };
    });
  }

  async function deleteServerListItemV1(request) {
    const input = baseInput(request.data, ["itemId", "expectedRevision"]);
    input.itemId = requireId(request.data.itemId, "itemId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    return operations.execute(request, "server.list.delete.v1", input, async ({
      transaction, auth, prior,
    }) => {
      const access = requireFamilyList(await readChannelAccess({
        db,
        transaction,
        uid: auth.uid,
        serverId: input.serverId,
        channelId: input.channelId,
        capability: "write",
      }));
      const reference = access.channelReference.collection("listItems").doc(input.itemId);
      const snapshot = await transaction.get(reference);
      if (prior) {
        if (!snapshot.exists) return prior;
        fail("aborted", "The list item still exists after the original request.");
      }
      const item = canonicalItem(snapshot, input);
      expectedRevision(item.revision, input.expectedRevision);
      if (item.createdById !== auth.uid && !MODERATOR_ROLES.includes(access.member.role)) {
        denied();
      }
      transaction.delete(reference);
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        itemId: input.itemId,
        deleted: true,
      };
    });
  }

  return {
    createServerListItemV1,
    updateServerListItemV1,
    deleteServerListItemV1,
  };
}

module.exports = {
  canonicalListItemId,
  createServerSharedListService,
};
