// Private family check-ins for Servers V1. They carry one of four explicit
// statuses and never accept or store location data.

const {
  digest,
  fail,
  requireExactInput,
  requireId,
  requireRequestId,
  requireUid,
} = require("../integrity/guards");
const { MANAGER_ROLES, denied, readServerAccess } = require("./authority");
const { requireEnum } = require("./contract");
const { canonicalDisplayName } = require("./documents");
const { createServerOperations } = require("./operations");

const FAMILY_CHECK_IN_STATUSES = Object.freeze([
  "home",
  "onMyWay",
  "allGood",
  "callMe",
]);

function canonicalFamilyCheckInId(uid, requestId) {
  requireUid(uid);
  requireRequestId(requestId);
  return `ci_${digest("server.family.checkin.v1", uid, requestId).slice(0, 40)}`;
}

function checkIn(snapshot, { serverId, checkInId }) {
  if (!snapshot.exists) fail("not-found", "The selected check-in is unavailable.");
  const value = snapshot.data() ?? {};
  if (value.schemaVersion !== 1 || value.serverId !== serverId ||
      value.clubId !== serverId || value.checkInId !== checkInId ||
      typeof value.userId !== "string" || typeof value.displayName !== "string" ||
      (value.photoUrl !== null && typeof value.photoUrl !== "string") ||
      !FAMILY_CHECK_IN_STATUSES.includes(value.status) || !value.createdAt) {
    fail("data-loss", "The family check-in needs reconciliation.");
  }
  return value;
}

function requireFamily(access) {
  if (access.server.serverType !== "family") denied();
  return access;
}

function createServerFamilyCheckInService(dependencies) {
  const { db } = dependencies;
  if (!db?.runTransaction) throw new TypeError("db is required.");
  const operations = createServerOperations(dependencies);

  async function createServerFamilyCheckInV1(request) {
    requireExactInput(request.data, ["serverId", "requestId", "status"], [
      "serverId",
      "requestId",
      "status",
    ]);
    const input = {
      serverId: requireId(request.data.serverId, "serverId"),
      requestId: requireRequestId(request.data.requestId),
      status: requireEnum(
        request.data.status,
        FAMILY_CHECK_IN_STATUSES,
        "status",
      ),
    };
    return operations.execute(
      request,
      "server.family.checkin.create.v1",
      input,
      async ({ transaction, auth, profile, prior, now }) => {
        const access = requireFamily(await readServerAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
        }));
        const checkInId = canonicalFamilyCheckInId(auth.uid, input.requestId);
        const reference = access.reference.collection("checkIns").doc(checkInId);
        const existing = await transaction.get(reference);
        if (prior) {
          const stored = checkIn(existing, { ...input, checkInId });
          if (stored.userId === auth.uid) return prior;
          fail("aborted", "The check-in changed after the original request.");
        }
        if (existing.exists) {
          fail("data-loss", "A check-in exists without its creation receipt.");
        }
        transaction.create(reference, {
          schemaVersion: 1,
          serverId: input.serverId,
          clubId: input.serverId,
          checkInId,
          userId: auth.uid,
          displayName: canonicalDisplayName(profile),
          photoUrl: null,
          status: input.status,
          createdAt: now,
        });
        return {
          serverId: input.serverId,
          checkInId,
          status: input.status,
        };
      },
    );
  }

  async function deleteServerFamilyCheckInV1(request) {
    requireExactInput(
      request.data,
      ["serverId", "checkInId", "requestId"],
      ["serverId", "checkInId", "requestId"],
    );
    const input = {
      serverId: requireId(request.data.serverId, "serverId"),
      checkInId: requireId(request.data.checkInId, "checkInId"),
      requestId: requireRequestId(request.data.requestId),
    };
    return operations.execute(
      request,
      "server.family.checkin.delete.v1",
      input,
      async ({ transaction, auth, prior }) => {
        const access = requireFamily(await readServerAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
        }));
        const reference = access.reference.collection("checkIns").doc(input.checkInId);
        const snapshot = await transaction.get(reference);
        if (prior) {
          if (!snapshot.exists) return prior;
          fail("aborted", "The check-in still exists after the original request.");
        }
        const stored = checkIn(snapshot, input);
        if (stored.userId !== auth.uid &&
            !MANAGER_ROLES.includes(access.member.role)) {
          denied();
        }
        transaction.delete(reference);
        return {
          serverId: input.serverId,
          checkInId: input.checkInId,
          deleted: true,
        };
      },
    );
  }

  return {
    createServerFamilyCheckInV1,
    deleteServerFamilyCheckInV1,
  };
}

module.exports = {
  FAMILY_CHECK_IN_STATUSES,
  canonicalFamilyCheckInId,
  createServerFamilyCheckInService,
};
