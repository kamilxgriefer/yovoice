const { fail, requireUid, transactionGetAll } = require("../integrity/guards");
const { HttpsError } = require("firebase-functions/v2/https");
const {
  boundedLegacyRoomQuery, isActiveOrdinaryRoom, validatedGuardRoomIds,
} = require("../rooms/creation");
const { isVersionedServer } = require("../utils/server_access");
const { FREE_SERVER_LIMIT } = require("./contract");

/**
 * Allocation provenance, never a user-editable subscription setting. A V1
 * root carries it as `entitlementPolicyId`; a legacy Club root or a standalone
 * room is classified by its shape (docs/Servers.md, "Creation, ownership and
 * capacity").
 */
const ALLOCATION_POLICIES = Object.freeze([
  "freeServersV1", "legacyRoomV1", "familyFreeV1", "legacyCommunityPremiumV1",
]);
// Charged to the free allowance. A family keeps its one-per-owner reservation
// and a retained paid Club keeps the Premium allowance instead.
const FREE_ALLOCATION_POLICIES = Object.freeze(["freeServersV1", "legacyRoomV1"]);
const FAMILY_SERVER_LIMIT = 1;
// Free-policy roots are factory-created inside the bounded free allowance, so
// a legacy owned-Club scan that has to skip more than this is corrupt data,
// not a legitimate account. It fails closed instead of scanning further.
const MAX_SKIPPED_FREE_ROOTS = 5 * FREE_SERVER_LIMIT;
const COUNTED_SERVER_STATUSES = Object.freeze(["active", "preparing"]);

function capacityDenied() {
  throw new HttpsError("resource-exhausted", `You can keep up to ${FREE_SERVER_LIMIT} free server allocations.`, {
    reason: "server-capacity-reached", limit: FREE_SERVER_LIMIT,
  });
}

/**
 * The ONE mismatch that is reconciled instead of refused: the earliest
 * `createServerV1` stamped the community policy on a family root, so exactly
 * `serverSchemaVersion: 1` + `type: "family"` + `freeServersV1` is read as the
 * family allocation it always was. The pair is unambiguous — a family is
 * charged to its own one-per-owner policy and never to the free allowance —
 * and without this adapter every allocation path for that owner fails closed
 * permanently. V1 was never deployed, so only development and pre-activation
 * data can carry it. It is deliberately NOT a default: any other policy, type
 * or schema version still fails closed.
 */
function isLegacyFamilyPolicyPair(data) {
  return data.serverSchemaVersion === 1 && data.type === "family" &&
    data.entitlementPolicyId === "freeServersV1";
}

/**
 * Classifies one Club root by provenance. Version markers select the adapter:
 * an explicitly versioned root must be canonical (`serverSchemaVersion: 1`, a
 * known policy, family type and family policy agreeing) and unknown values
 * fail closed rather than silently becoming a community default. A root
 * without markers keeps the historical legacy rule: missing `type` means
 * community.
 */
function classifyServerAllocation(server) {
  const data = server ?? {};
  const family = data.type === "family";
  if (!isVersionedServer(data)) {
    return { policy: family ? "familyFreeV1" : "legacyCommunityPremiumV1", versioned: false };
  }
  const policy = isLegacyFamilyPolicyPair(data) ? "familyFreeV1" : data.entitlementPolicyId;
  if (data.serverSchemaVersion !== 1 || !ALLOCATION_POLICIES.includes(policy)) {
    fail("data-loss", "A versioned allocation needs reconciliation.");
  }
  if ((policy === "familyFreeV1") !== family) {
    fail("data-loss", "A family allocation needs reconciliation.");
  }
  return { policy, versioned: true };
}

/**
 * The source of truth is canonical roots plus the existing ordinary-room
 * guard, not a client count. All allocation-changing paths must acquire these
 * same locks and call this reader before V1 can be activated. In particular,
 * merely touching the legacy guard does not repair an old writer's count.
 */
async function readServerOwnerGuards({ db, transaction, uid }) {
  requireUid(uid);
  const serverGuardReference = db.doc(`privateServerOwnerGuards/${uid}`);
  const roomGuardReference = db.doc(`privateRoomHostGuards/${uid}`);
  const clubGuardReference = db.doc(`clubOwnershipGuards/${uid}`);
  const [serverGuard, roomGuard, clubGuard] = await transactionGetAll(
    transaction, serverGuardReference, roomGuardReference, clubGuardReference,
  );
  const guard = serverGuard.exists ? serverGuard.data() : null;
  if (guard && (guard.schemaVersion !== 1 || guard.ownerId !== uid ||
      !Number.isSafeInteger(guard.revision) || guard.revision < 1 ||
      guard.revision >= Number.MAX_SAFE_INTEGER - 1)) {
    fail("data-loss", "The server allocation guard needs reconciliation.");
  }
  return { serverGuardReference, roomGuardReference, clubGuardReference,
    serverGuard: guard, roomGuard,
    clubGuard: clubGuard.exists ? clubGuard.data() : null };
}

// Mirrors createRoom: a locked guard keeps its ids untouched, a legacy account
// is read through the same bounded query and never scanned further.
async function readOwnerRooms({ db, transaction, uid, roomState }) {
  if (roomState?.capacityLocked) return { snapshots: [], locked: true };
  if (roomState) {
    const snapshots = roomState.activeRoomIds.length === 0 ? [] : await transactionGetAll(
      transaction, ...roomState.activeRoomIds.map((id) => db.doc(`rooms/${id}`)),
    );
    return { snapshots, locked: false };
  }
  const legacy = await transaction.get(boundedLegacyRoomQuery(db, uid, FREE_SERVER_LIMIT));
  return { snapshots: legacy.docs, locked: legacy.size > FREE_SERVER_LIMIT };
}

/**
 * Shared version-aware allocation accounting for one owner: every persistent
 * allocation is classified by provenance and counted under its policy with
 * exact canonical queries. Over-limit or unreadable data is reported, never
 * rewritten; only `requireFreeServerCapacity` and the family check refuse an
 * additional allocation. Malformed data still fails closed.
 *
 * `freeServersV1` and `legacyRoomV1` share the free allowance. A standalone
 * room keeps the same allocation identity before and after adoption, so it is
 * never counted twice and cannot vanish from the allowance by acquiring
 * `clubId`. Families and retained paid Clubs are never charged to it.
 */
async function readOwnerAllocations({ db, transaction, uid }) {
  const guards = await readServerOwnerGuards({ db, transaction, uid });
  const roomState = validatedGuardRoomIds(guards.roomGuard, uid, FREE_SERVER_LIMIT);
  const [serverSnapshot, familySnapshot, rooms] = await Promise.all([
    transaction.get(db.collection("clubs")
      .where("ownerId", "==", uid)
      .where("entitlementPolicyId", "in", FREE_ALLOCATION_POLICIES)
      .where("status", "in", COUNTED_SERVER_STATUSES)
      .limit(FREE_SERVER_LIMIT + 1)),
    transaction.get(db.collection("clubs")
      .where("ownerId", "==", uid)
      .where("type", "==", "family")
      .limit(FAMILY_SERVER_LIMIT + 1)),
    readOwnerRooms({ db, transaction, uid, roomState }),
  ]);

  const allocations = new Set();
  const migratedRoomIds = new Set();
  for (const snapshot of serverSnapshot.docs) {
    const server = snapshot.data();
    const { policy } = classifyServerAllocation(server);
    if (policy === "legacyRoomV1") {
      const source = server.migration;
      if (!source || source.version !== 1 || source.sourceKind !== "room" ||
          typeof source.sourceId !== "string" || source.sourceId.length === 0) {
        fail("data-loss", "A migrated room allocation needs reconciliation.");
      }
      if (migratedRoomIds.has(source.sourceId)) {
        fail("data-loss", "A migrated room has duplicate allocations.");
      }
      migratedRoomIds.add(source.sourceId);
      allocations.add(`room:${source.sourceId}`);
    } else if (policy === "freeServersV1") {
      allocations.add(`server:${snapshot.id}`);
    } else if (policy === "familyFreeV1") {
      // The reconciled legacy V1 family pair: its policy FIELD matches this
      // exact query, but a family is charged by the canonical family count
      // below, never to the free allowance.
      continue;
    } else {
      fail("data-loss", "A free allocation needs reconciliation.");
    }
  }

  let activeRoomIds = [];
  for (const snapshot of rooms.snapshots) {
    if (!snapshot.exists) continue;
    const room = snapshot.data();
    if (isActiveOrdinaryRoom(snapshot, uid)) {
      activeRoomIds.push(snapshot.id);
      allocations.add(`room:${snapshot.id}`);
    } else if (room.hostId === uid && room.status === "active" &&
        room.serverSchemaVersion !== undefined && room.roomKind !== "serverChannel" &&
        !migratedRoomIds.has(snapshot.id)) {
      // An adopted room cannot vanish from capacity by acquiring clubId.
      fail("data-loss", "A bound room allocation needs reconciliation.");
    }
  }
  activeRoomIds = [...new Set(activeRoomIds)].sort();
  if (roomState?.capacityLocked) activeRoomIds = roomState.activeRoomIds;
  else if (rooms.locked) activeRoomIds = activeRoomIds.slice(0, FREE_SERVER_LIMIT);

  let familyCount = 0;
  for (const snapshot of familySnapshot.docs) {
    classifyServerAllocation(snapshot.data());
    familyCount += 1;
  }

  let freeServersV1 = 0;
  for (const key of allocations) if (key.startsWith("server:")) freeServersV1 += 1;
  return {
    ...guards,
    counts: {
      freeServersV1, legacyRoomV1: allocations.size - freeServersV1, familyFreeV1: familyCount,
    },
    free: {
      count: allocations.size, limit: FREE_SERVER_LIMIT,
      exhaustive: serverSnapshot.size <= FREE_SERVER_LIMIT, locked: rooms.locked,
    },
    family: { count: familyCount, limit: FAMILY_SERVER_LIMIT },
    rooms: { locked: rooms.locked },
    activeRoomIds,
  };
}

/**
 * Version-aware replacement for the legacy owned-Club scan behind
 * `requireCommunityClubCapacity`. Legacy semantics stay exact: a legacy-only
 * owner is read with the same single `limit + 1` query, legacy family roots
 * still occupy that bound, and a full bound fails closed. Free-policy V1 roots
 * are charged elsewhere, so they are skipped page by page and can neither
 * consume the Premium allowance nor obscure its count.
 */
async function readPremiumClubAllocations({ db, transaction, uid, limit }) {
  requireUid(uid);
  if (!Number.isSafeInteger(limit) || limit < 1) throw new TypeError("limit must be a positive integer.");
  const owned = db.collection("clubs").where("ownerId", "==", uid);
  let count = 0;
  let visible = 0;
  let skipped = 0;
  let cursor = null;
  let pageSize = limit + 1;
  for (;;) {
    const snapshot = await transaction.get(
      (cursor ? owned.startAfter(cursor) : owned).limit(pageSize),
    );
    for (const document of snapshot.docs) {
      const { policy, versioned } = classifyServerAllocation(document.data());
      if (versioned && policy !== "legacyCommunityPremiumV1") {
        skipped += 1;
        continue;
      }
      visible += 1;
      if (policy === "legacyCommunityPremiumV1") count += 1;
    }
    if (skipped > MAX_SKIPPED_FREE_ROOTS) fail("data-loss", "The owned server set needs reconciliation.");
    if (visible > limit) return { count, limit, exhaustive: false };
    if (snapshot.size < pageSize) return { count, limit, exhaustive: true };
    cursor = snapshot.docs[snapshot.size - 1];
    pageSize = FREE_SERVER_LIMIT + limit + 1;
  }
}

function hasFreeServerCapacity(state) {
  return state.free.exhaustive && !state.free.locked && state.free.count < state.free.limit;
}

function hasFamilyServerCapacity(state) {
  return state.family.count < state.family.limit;
}

function requireFreeServerCapacity(state) {
  if (!hasFreeServerCapacity(state)) capacityDenied();
}

function writeOwnerGuards(transaction, state, uid, now) {
  transaction.set(state.serverGuardReference, {
    schemaVersion: 1, ownerId: uid,
    revision: (state.serverGuard?.revision ?? 0) + 1, updatedAt: now,
  });
  const oldRevision = state.clubGuard?.revision;
  transaction.set(state.clubGuardReference, {
    revision: Number.isSafeInteger(oldRevision) && oldRevision >= 0 ? oldRevision + 1 : 1,
    updatedAt: now,
  }, { merge: true });
}

function writeCapacityGuards(transaction, state, uid, now) {
  writeOwnerGuards(transaction, state, uid, now);
  transaction.set(state.roomGuardReference, {
    schemaVersion: 2, ownerId: uid, activeRoomIds: state.activeRoomIds,
    capacityLocked: state.rooms.locked, updatedAt: now,
  }, { merge: true });
}

module.exports = {
  ALLOCATION_POLICIES, FAMILY_SERVER_LIMIT, FREE_ALLOCATION_POLICIES, MAX_SKIPPED_FREE_ROOTS,
  classifyServerAllocation, hasFamilyServerCapacity, hasFreeServerCapacity,
  readOwnerAllocations, readPremiumClubAllocations, readServerOwnerGuards,
  requireFreeServerCapacity, writeCapacityGuards, writeOwnerGuards,
  // Retained name for in-flight importers; identical to readOwnerAllocations.
  readFreeServerCapacity: readOwnerAllocations,
};
