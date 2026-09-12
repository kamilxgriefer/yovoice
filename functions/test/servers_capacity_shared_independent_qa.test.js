const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// Independent QA for the shared version-aware allocation accounting
// (docs/Servers.md, "Creation, ownership and capacity"). Adversarial cases the
// author suite does not cover: transaction races, replay identity, transfer
// atomicity, Premium page boundaries, status predicates, malformed roots and
// guard immutability. Only an explicitly selected localhost demo emulator
// project is used; the default app is initialized because the legacy Club
// quota reads through utils/firestore's default Firestore instance.
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const projectId = "demo-yovoice-servers-capacity-qa";
let db;
let app;
let Timestamp;
if (enabled) {
  process.env.GCLOUD_PROJECT = projectId;
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.getApps().length === 0 ? adminApp.initializeApp({ projectId }) : adminApp.getApp();
  db = firestore.getFirestore(app);
}
const {
  FAMILY_SERVER_LIMIT, MAX_SKIPPED_FREE_ROOTS, classifyServerAllocation, readOwnerAllocations,
  readPremiumClubAllocations,
} = require("../servers/capacity");
const { FREE_SERVER_LIMIT } = require("../servers/contract");
const { createServerCreationService } = require("../servers/creation");
const { createServerMembershipService } = require("../servers/memberships");

const nowMs = 1_900_000_000_000;
const CAPACITY_DETAILS = { reason: "server-capacity-reached", limit: FREE_SERVER_LIMIT };
// Contention retries below must never be throttled by the per-owner budgets.
const LIMITS = Object.freeze({
  attempts: Object.freeze({ maxEvents: 10_000, windowMs: 60_000 }),
  creation: Object.freeze({ maxEvents: 10_000, windowMs: 3_600_000 }),
});
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const input = (overrides = {}) => ({ requestId: randomUUID(), serverType: "friends", templateVersion: 1,
  name: "Trusted server", description: "", privacy: "inviteOnly", defaultLanguage: "English", ...overrides });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const isCapacity = (error) => error?.code === "resource-exhausted" &&
  error.details?.reason === CAPACITY_DETAILS.reason && error.details?.limit === CAPACITY_DETAILS.limit;
const capacityRejection = (promise) => assert.rejects(promise, isCapacity);
const read = (uid, extra = {}) => db.runTransaction((transaction) => readOwnerAllocations({ db, transaction, uid, ...extra }));
const premium = (uid, limit = 3) => db.runTransaction((transaction) => readPremiumClubAllocations({ db, transaction, uid, limit }));
const legacyQuota = (uid) => db.runTransaction((transaction) =>
  require("../clubs/quota").requireCommunityClubCapacity(transaction, uid));
const ownedRoots = async (uid) => (await db.collection("clubs").where("ownerId", "==", uid).get()).size;
const doc = async (path) => (await db.doc(path).get()).data();
const exists = async (path) => (await db.doc(path).get()).exists;

function services() {
  const deps = { db, Timestamp, clock: () => nowMs, limits: LIMITS };
  return { ...createServerCreationService(deps), ...createServerMembershipService(deps) };
}
async function owner() {
  const uid = `qa-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: "Canonical owner", status: "active" });
  return uid;
}
async function seed(documents) {
  for (let index = 0; index < documents.length; index += 400) {
    const batch = db.batch();
    for (const [path, data] of documents.slice(index, index + 400)) batch.set(db.doc(path), data);
    await batch.commit();
  }
}
const freeRoot = (uid, extra = {}) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "freeServersV1",
  type: "community", status: "preparing", ...extra });
const freeRoots = (uid, count, prefix = `free-${uid}`) => Array.from({ length: count }, (_, index) =>
  [`clubs/${prefix}-${String(index).padStart(3, "0")}`, freeRoot(uid)]);
const legacyClub = (uid, extra = {}) => ({ ownerId: uid, type: "community", status: "active", ...extra });
const legacyFamily = (uid) => ({ ownerId: uid, type: "family", status: "active" });
const familyRoot = (uid, extra = {}) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "familyFreeV1",
  type: "family", status: "active", ...extra });
const adoptedRoot = (uid, roomId, extra = {}) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "legacyRoomV1",
  type: "community", status: "active", migration: { version: 1, sourceKind: "room", sourceId: roomId, state: "applied" }, ...extra });
const ordinaryRoom = (uid) => ({ hostId: uid, status: "active", roomType: "community" });
const heldAnchor = (serverId) => ({ hostId: null, status: "preparing", clubId: serverId, serverId,
  roomKind: "serverChannel", serverSchemaVersion: 1, serverActivationState: "held", roomType: "community" });
const activeAnchor = (uid, serverId) => ({ hostId: uid, status: "active", clubId: serverId, serverId,
  roomKind: "serverChannel", serverSchemaVersion: 1, serverActivationState: "active", roomType: "community" });
const roomGuard = (uid, activeRoomIds, capacityLocked = false) =>
  ({ schemaVersion: 2, ownerId: uid, activeRoomIds, capacityLocked });
const entitlement = () => ({ status: "active", isPremium: true, premiumIdentityEnabled: true, canCreateClubs: true,
  maxOwnedClubs: 3, currentPeriodEnd: Timestamp.fromMillis(Date.now() + 86_400_000) });

// Emulator fixture activation only, never a shipped activation path.
async function activate(serverId, uid) {
  await db.doc(`clubs/${serverId}`).update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", serverId).get();
  for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: uid });
}
async function joinedServer(service, uid, member) {
  const created = await service.createServerV1(request(uid, input({ serverType: "community", privacy: "public" })));
  await activate(created.serverId, uid);
  await service.joinServerV1(request(member, { serverId: created.serverId, requestId: randomUUID() }));
  return created.serverId;
}
const transfer = (service, from, serverId, to, requestId = randomUUID()) =>
  service.transferServerOwnershipV1(request(from, { serverId, requestId, newOwnerId: to }));

// gRPC contention after the SDK's own retries surfaces as a numeric status
// (ABORTED 10, DEADLINE 4, INTERNAL 13, UNAVAILABLE 14, ALREADY_EXISTS 6 on
// a lost create race). Nothing is committed for those, so the same request is
// replayed serially until every call ends in a product outcome.
const transient = (error) => typeof error?.code === "number" && [4, 6, 10, 13, 14].includes(error.code);
async function settle(calls) {
  const results = new Array(calls.length);
  let pending = calls.map((call, index) => ({ call, index }));
  let retried = 0;
  const record = (index, outcome) => {
    if (outcome.status === "fulfilled") results[index] = { status: "ok", value: outcome.value };
    else if (isCapacity(outcome.reason)) results[index] = { status: "capacity", error: outcome.reason };
    else if (transient(outcome.reason)) return false;
    else results[index] = { status: "error", error: outcome.reason };
    return true;
  };
  const first = await Promise.allSettled(pending.map(({ call }) => call()));
  pending = pending.filter((item, position) => !record(item.index, first[position]));
  for (let round = 0; pending.length > 0 && round < 8; round += 1) {
    const next = [];
    for (const item of pending) {
      retried += 1;
      const outcome = await item.call().then((value) => ({ status: "fulfilled", value }), (reason) => ({ status: "rejected", reason }));
      if (!record(item.index, outcome)) next.push(item);
    }
    pending = next;
  }
  for (const item of pending) results[item.index] = { status: "error", error: new Error("unresolved contention") };
  return { results, retried };
}
const tally = (results) => ({
  ok: results.filter((item) => item.status === "ok").length,
  capacity: results.filter((item) => item.status === "capacity").length,
  errors: results.filter((item) => item.status === "error").map((item) => `${item.error?.code}: ${item.error?.message}`),
});

after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

test("classification fails closed on a string schema version and on a marker without a policy", () => {
  for (const malformed of [
    { serverSchemaVersion: "1", type: "community", entitlementPolicyId: "freeServersV1" },
    { serverActivationState: "held", type: "community" },
    { serverSchemaVersion: 1, type: "community", entitlementPolicyId: "premium" },
    { serverSchemaVersion: 1, type: "family", entitlementPolicyId: "legacyRoomV1" },
  ]) assert.throws(() => classifyServerAllocation(malformed), (error) => error.code === "data-loss");
  assert.deepEqual(classifyServerAllocation({ type: "family", entitlementPolicyId: "freeServersV1" }),
    { policy: "familyFreeV1", versioned: false });
});

emulatorTest("(a) 25 parallel free creations by one owner land exactly 20, refuse 5 with the structured error, persist exactly 20 and replay without a second slot", async () => {
  const uid = await owner();
  const service = services();
  const inputs = Array.from({ length: FREE_SERVER_LIMIT + 5 }, () => input());
  const { results, retried } = await settle(inputs.map((data) => () => service.createServerV1(request(uid, data))));
  const counts = tally(results);
  assert.deepEqual(counts.errors, []);
  assert.equal(counts.ok, FREE_SERVER_LIMIT, `retried ${retried}`);
  assert.equal(counts.capacity, 5);
  const created = results.filter((item) => item.status === "ok").map((item) => item.value);
  assert.ok(created.every((value) => value.alreadyExisted === false));
  assert.equal(new Set(created.map((value) => value.serverId)).size, FREE_SERVER_LIMIT);
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT);
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.deepEqual(state.free, { count: FREE_SERVER_LIMIT, limit: FREE_SERVER_LIMIT, exhaustive: true, locked: false });
  assert.equal((await doc(`privateServerOwnerGuards/${uid}`)).revision, FREE_SERVER_LIMIT);
  const ledgers = () => db.collection("integrityOperationLedgers")
    .where("ownerId", "==", uid).where("kind", "==", "server.create.v1").get();
  assert.equal((await ledgers()).size, FREE_SERVER_LIMIT);
  // Replay of a committed request returns its receipt; a changed input or a
  // changed template under the same requestId is refused; a refused request
  // left no receipt and is refused again while the allowance is full.
  const winner = inputs[results.findIndex((item) => item.status === "ok")];
  const replay = await service.createServerV1(request(uid, winner));
  assert.equal(replay.alreadyExisted, true);
  assert.ok(created.some((value) => value.serverId === replay.serverId));
  await rejection(service.createServerV1(request(uid, { ...winner, name: "Renamed" })), "already-exists");
  await rejection(service.createServerV1(request(uid, { ...winner, serverType: "company" })), "already-exists");
  const loser = inputs[results.findIndex((item) => item.status === "capacity")];
  await capacityRejection(service.createServerV1(request(uid, loser)));
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT);
  assert.equal((await ledgers()).size, FREE_SERVER_LIMIT);
  assert.equal((await doc(`privateServerOwnerGuards/${uid}`)).revision, FREE_SERVER_LIMIT);
  state = await read(uid);
  assert.equal(state.free.count, FREE_SERVER_LIMIT);
});

emulatorTest("(a) 5 parallel family creations converge on one familyFreeV1 root and one reservation", async () => {
  const uid = await owner();
  const service = services();
  const { results } = await settle(Array.from({ length: 5 }, () =>
    () => service.createServerV1(request(uid, input({ serverType: "family" })))));
  const counts = tally(results);
  assert.deepEqual(counts.errors, []);
  assert.equal(counts.ok, 5);
  const values = results.map((item) => item.value);
  assert.equal(values.filter((value) => value.alreadyExisted === false).length, 1);
  assert.ok(values.every((value) => value.serverId === `family_${uid}`));
  assert.equal(await ownedRoots(uid), 1);
  assert.equal((await doc(`clubs/family_${uid}`)).entitlementPolicyId, "familyFreeV1");
  assert.equal((await doc(`serverFamilyOwnerReservations/${uid}`)).serverId, `family_${uid}`);
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.deepEqual(state.family, { count: 1, limit: FAMILY_SERVER_LIMIT });
});

emulatorTest("(a) a transfer into a recipient racing the recipient's own creation lands exactly one allocation on the recipient", async () => {
  const source = await owner();
  const recipient = await owner();
  const service = services();
  const serverId = await joinedServer(service, source, recipient);
  await seed(freeRoots(recipient, FREE_SERVER_LIMIT - 1));
  const { results } = await settle([
    () => service.createServerV1(request(recipient, input())),
    () => transfer(service, source, serverId, recipient),
  ]);
  const counts = tally(results);
  assert.deepEqual(counts.errors, []);
  assert.equal(counts.ok, 1);
  assert.equal(counts.capacity, 1);
  const state = await read(recipient);
  assert.deepEqual(state.free, { count: FREE_SERVER_LIMIT, limit: FREE_SERVER_LIMIT, exhaustive: true, locked: false });
  assert.equal(await ownedRoots(recipient), FREE_SERVER_LIMIT);
  const transferred = results[1].status === "ok";
  assert.equal((await doc(`clubs/${serverId}`)).ownerId, transferred ? recipient : source);
  assert.deepEqual((await read(source)).counts, { freeServersV1: transferred ? 0 : 1, legacyRoomV1: 0, familyFreeV1: 0 });
});

emulatorTest("(b) an owner at 20 free plus a family: the family lands via reservation, a 21st free is refused, one transfer out reopens exactly one slot and the ping-pong back is refused", async () => {
  const uid = await owner();
  const recipient = await owner();
  const service = services();
  await seed(freeRoots(uid, FREE_SERVER_LIMIT - 1));
  const serverId = await joinedServer(service, uid, recipient);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  const family = await service.createServerV1(request(uid, input({ serverType: "family" })));
  assert.equal(family.alreadyExisted, false);
  assert.equal((await doc(`clubs/${family.serverId}`)).entitlementPolicyId, "familyFreeV1");
  assert.equal((await doc(`serverFamilyOwnerReservations/${uid}`)).serverId, family.serverId);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 1 });
  await capacityRejection(service.createServerV1(request(uid, input())));
  await transfer(service, uid, serverId, recipient);
  assert.equal((await doc(`clubs/${serverId}`)).ownerId, recipient);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: FREE_SERVER_LIMIT - 1, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.deepEqual((await read(recipient)).counts, { freeServersV1: 1, legacyRoomV1: 0, familyFreeV1: 0 });
  const refill = await service.createServerV1(request(uid, input()));
  assert.equal(refill.alreadyExisted, false);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 1 });
  await capacityRejection(service.createServerV1(request(uid, input())));
  await capacityRejection(transfer(service, recipient, serverId, uid));
  assert.equal((await doc(`clubs/${serverId}`)).ownerId, recipient);
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 1);
});

emulatorTest("(c) a refused transfer into a full recipient is atomic: root, roles, authorizations, mirrors, guards, ledger and outbox are untouched, and the same requestId succeeds once a slot opens", async () => {
  const source = await owner();
  const recipient = await owner();
  const service = services();
  const serverId = await joinedServer(service, source, recipient);
  await seed(freeRoots(recipient, FREE_SERVER_LIMIT));
  const watched = [
    `clubs/${serverId}`, `clubs/${serverId}/members/${source}`, `clubs/${serverId}/members/${recipient}`,
    `clubs/${serverId}/memberAuthorizations/${source}`, `clubs/${serverId}/memberAuthorizations/${recipient}`,
    `users/${source}/clubs/${serverId}`, `users/${recipient}/clubs/${serverId}`,
    `privateServerOwnerGuards/${source}`, `clubOwnershipGuards/${source}`, `privateRoomHostGuards/${source}`,
  ];
  const before = await Promise.all(watched.map(doc));
  assert.equal(before[1].role, "owner");
  assert.equal(before[2].role, "member");
  const requestId = randomUUID();
  await capacityRejection(transfer(service, source, serverId, recipient, requestId));
  assert.deepEqual(await Promise.all(watched.map(doc)), before);
  assert.equal(await exists(`privateServerOwnerGuards/${recipient}`), false);
  assert.equal(await exists(`privateRoomHostGuards/${recipient}`), false);
  assert.equal(await exists(`serverFamilyOwnerReservations/${recipient}`), false);
  const outbox = () => db.collection("serverControlOutbox")
    .where("serverId", "==", serverId).where("kind", "==", "ownershipTransferred").get();
  const ledgers = () => db.collection("integrityOperationLedgers")
    .where("ownerId", "==", source).where("kind", "==", "server.ownership.transfer.v1").get();
  assert.equal((await outbox()).size, 0);
  assert.equal((await ledgers()).size, 0);
  await db.doc(`clubs/free-${recipient}-000`).delete();
  const result = await transfer(service, source, serverId, recipient, requestId);
  assert.equal(result.ownerId, recipient);
  assert.equal((await doc(`clubs/${serverId}`)).ownerId, recipient);
  assert.equal((await doc(`clubs/${serverId}/members/${source}`)).role, "coOwner");
  assert.equal((await doc(`clubs/${serverId}/members/${recipient}`)).role, "owner");
  assert.equal((await outbox()).size, 1);
  assert.equal((await ledgers()).size, 1);
  assert.deepEqual(await transfer(service, source, serverId, recipient, requestId), result);
  await rejection(transfer(service, source, serverId, await owner(), requestId), "already-exists");
  assert.equal((await outbox()).size, 1);
  assert.deepEqual((await read(recipient)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.deepEqual((await read(source)).counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.equal((await doc(`privateRoomHostGuards/${recipient}`)).capacityLocked, false);
});

emulatorTest("(d) a legacy Premium owner at the allowance stays refused before and after 20 free roots interleaved around the legacy roots; one release restores exactly one legacy creation", async () => {
  const uid = await owner();
  await db.doc(`entitlements/${uid}`).set(entitlement());
  const { createCommunityClub } = require("../clubs/creation");
  const run = (clubId) => createCommunityClub.run({
    auth: { uid, token: { email_verified: true, email: `${uid}@example.invalid`, name: "Club Owner" } },
    data: { clubId, name: "Secure Club", description: "Created atomically", privacy: "public",
      defaultLanguage: "English", avatarUrl: null, bannerUrl: null },
  });
  await seed([[`clubs/b-legacy-${uid}`, legacyClub(uid)], [`clubs/d-legacy-${uid}`, legacyClub(uid)],
    [`clubs/f-legacy-${uid}`, legacyClub(uid)]]);
  assert.deepEqual(await premium(uid), { count: 3, limit: 3, exhaustive: true });
  await rejection(run(`h-legacy-${uid}`), "resource-exhausted");
  await seed([...freeRoots(uid, 5, `a-${uid}`), ...freeRoots(uid, 5, `c-${uid}`),
    ...freeRoots(uid, 5, `e-${uid}`), ...freeRoots(uid, 5, `g-${uid}`)]);
  assert.deepEqual(await premium(uid), { count: 3, limit: 3, exhaustive: true });
  await rejection(run(`h-legacy-${uid}`), "resource-exhausted");
  await rejection(legacyQuota(uid), "resource-exhausted");
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  await capacityRejection(services().createServerV1(request(uid, input())));
  await db.doc(`clubs/f-legacy-${uid}`).delete();
  assert.deepEqual(await premium(uid), { count: 2, limit: 3, exhaustive: true });
  assert.equal((await run(`h-legacy-${uid}`)).alreadyExisted, false);
  await rejection(run(`i-legacy-${uid}`), "resource-exhausted");
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 3);
});

emulatorTest("(d) a free server transferred into a legacy Premium owner at the allowance neither loosens nor tightens the Premium count", async () => {
  const source = await owner();
  const recipient = await owner();
  const service = services();
  await db.doc(`entitlements/${recipient}`).set(entitlement());
  await seed([[`clubs/b-legacy-${recipient}`, legacyClub(recipient)], [`clubs/d-legacy-${recipient}`, legacyClub(recipient)],
    [`clubs/f-legacy-${recipient}`, legacyClub(recipient)], ...freeRoots(recipient, FREE_SERVER_LIMIT - 1)]);
  await rejection(legacyQuota(recipient), "resource-exhausted");
  const serverId = await joinedServer(service, source, recipient);
  await transfer(service, source, serverId, recipient);
  assert.deepEqual((await read(recipient)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.deepEqual(await premium(recipient), { count: 3, limit: 3, exhaustive: true });
  await rejection(legacyQuota(recipient), "resource-exhausted");
  await db.doc(`clubs/f-legacy-${recipient}`).delete();
  assert.deepEqual(await legacyQuota(recipient), { ownedCommunityClubs: 2, limit: 3 });
  const another = await joinedServer(service, source, recipient);
  await capacityRejection(transfer(service, source, another, recipient));
});

emulatorTest("(d) readPremiumClubAllocations page boundaries with free roots before, between and after legacy roots", async () => {
  const cases = [
    ["first page entirely skipped (limit+1 free), legacy on page two", (uid) => [
      ...freeRoots(uid, 4, `a-${uid}`), [`clubs/z-0-${uid}`, legacyClub(uid)], [`clubs/z-1-${uid}`, legacyClub(uid)],
    ], { count: 2, limit: 3, exhaustive: true }],
    ["legacy at the first page boundary, more legacy and free on page two", (uid) => [
      ...freeRoots(uid, 3, `a-${uid}`), [`clubs/b-${uid}`, legacyClub(uid)], [`clubs/c-${uid}`, legacyClub(uid)], ...freeRoots(uid, 1, `d-${uid}`),
    ], { count: 2, limit: 3, exhaustive: true }],
    ["free roots after the legacy roots fill the page exactly; the next page is empty", (uid) => [
      [`clubs/a-0-${uid}`, legacyClub(uid)], [`clubs/a-1-${uid}`, legacyClub(uid)], ...freeRoots(uid, 2, `b-${uid}`),
    ], { count: 2, limit: 3, exhaustive: true }],
    ["exactly the allowance plus one free root on the first page stays exhaustive", (uid) => [
      [`clubs/a-0-${uid}`, legacyClub(uid)], [`clubs/a-1-${uid}`, legacyClub(uid)], [`clubs/a-2-${uid}`, legacyClub(uid)],
      ...freeRoots(uid, 1, `b-${uid}`),
    ], { count: 3, limit: 3, exhaustive: true }],
    ["a legacy family beyond the first page still breaks the bound", (uid) => [
      [`clubs/a-0-${uid}`, legacyClub(uid)], [`clubs/a-1-${uid}`, legacyClub(uid)], [`clubs/a-2-${uid}`, legacyClub(uid)],
      ...freeRoots(uid, 1, `b-${uid}`), [`clubs/c-family-${uid}`, legacyFamily(uid)],
    ], { count: 3, limit: 3, exhaustive: false }],
    ["a paid retained V1 root counts like a legacy Club", (uid) => [
      ...freeRoots(uid, 4, `a-${uid}`), [`clubs/z-paid-${uid}`, { ...freeRoot(uid), entitlementPolicyId: "legacyCommunityPremiumV1", status: "active" }],
    ], { count: 1, limit: 3, exhaustive: true }],
    ["second page (24) exactly full of free roots after the legacy roots; the third page is empty", (uid) => [
      ...freeRoots(uid, 4, `a-${uid}`), [`clubs/m-0-${uid}`, legacyClub(uid)], [`clubs/m-1-${uid}`, legacyClub(uid)], ...freeRoots(uid, 22, `z-${uid}`),
    ], { count: 2, limit: 3, exhaustive: true }],
    ["exactly MAX_SKIPPED_FREE_ROOTS free roots are skipped", (uid) => [
      ...freeRoots(uid, MAX_SKIPPED_FREE_ROOTS, `a-${uid}`), [`clubs/z-0-${uid}`, legacyClub(uid)], [`clubs/z-1-${uid}`, legacyClub(uid)],
    ], { count: 2, limit: 3, exhaustive: true }],
  ];
  for (const [label, documents, expected] of cases) {
    const uid = await owner();
    await seed(documents(uid));
    assert.deepEqual(await premium(uid), expected, label);
  }
  const uid = await owner();
  await seed([...freeRoots(uid, MAX_SKIPPED_FREE_ROOTS + 1, `a-${uid}`), [`clubs/z-0-${uid}`, legacyClub(uid)]]);
  await rejection(premium(uid), "data-loss");
  await db.doc(`clubs/a-${uid}-100`).delete();
  assert.deepEqual(await premium(uid), { count: 1, limit: 3, exhaustive: true });
});

emulatorTest("(e) status predicates: active and preparing count, deleting/archived/missing do not, deletionInProgress still counts; legacy Premium and family counts ignore status", async () => {
  const uid = await owner();
  const service = services();
  const missing = freeRoot(uid);
  delete missing.status;
  await seed([
    [`clubs/s-active-${uid}`, freeRoot(uid, { status: "active" })],
    [`clubs/s-preparing-${uid}`, freeRoot(uid, { status: "preparing" })],
    [`clubs/s-deleting-${uid}`, freeRoot(uid, { status: "deleting" })],
    [`clubs/s-archived-${uid}`, freeRoot(uid, { status: "archived" })],
    [`clubs/s-missing-${uid}`, missing],
    [`clubs/s-dip-${uid}`, freeRoot(uid, { status: "active", deletionInProgress: true })],
  ]);
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 3, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.equal(state.free.exhaustive, true);
  await seed(freeRoots(uid, FREE_SERVER_LIMIT - 4, `t-${uid}`));
  state = await read(uid);
  assert.equal(state.free.count, FREE_SERVER_LIMIT - 1);
  const twentieth = await service.createServerV1(request(uid, input()));
  assert.equal(twentieth.alreadyExisted, false);
  await capacityRejection(service.createServerV1(request(uid, input())));
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 3);

  const legacy = await owner();
  await seed([
    [`clubs/l-active-${legacy}`, legacyClub(legacy)], [`clubs/l-preparing-${legacy}`, legacyClub(legacy, { status: "preparing" })],
    [`clubs/l-deleting-${legacy}`, legacyClub(legacy, { status: "deleting" })],
    [`clubs/l-archived-${legacy}`, legacyClub(legacy, { status: "archived" })],
    [`clubs/l-missing-${legacy}`, { ownerId: legacy, type: "community" }],
    [`clubs/l-dip-${legacy}`, legacyClub(legacy, { deletionInProgress: true })],
  ]);
  assert.deepEqual(await premium(legacy, 10), { count: 6, limit: 10, exhaustive: true });

  const familyOwner = await owner();
  await seed([[`clubs/archived-family-${familyOwner}`, familyRoot(familyOwner, { status: "archived" })]]);
  state = await read(familyOwner);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
  await rejection(service.createServerV1(request(familyOwner, input({ serverType: "family" }))), "failed-precondition");
  assert.equal(await exists(`serverFamilyOwnerReservations/${familyOwner}`), false);
});

emulatorTest("(f) adopted room: malformed migration sources fail closed, an unguarded bound room is counted once through its root, and a deleting adopted root with a live bound room fails closed", async () => {
  for (const [label, migration] of [
    ["wrong sourceKind", { version: 1, sourceKind: "club", sourceId: "x", state: "applied" }],
    ["wrong version", { version: 2, sourceKind: "room", sourceId: "x", state: "applied" }],
    ["empty sourceId", { version: 1, sourceKind: "room", sourceId: "", state: "applied" }],
  ]) {
    const uid = await owner();
    await seed([[`clubs/adopted-${uid}`, adoptedRoot(uid, "x", { migration })]]);
    await rejection(read(uid), "data-loss").catch((error) => { throw new Error(`${label}: ${error.message}`); });
  }
  const uid = await owner();
  const roomId = `room-${uid}`;
  const serverId = `adopted-${uid}`;
  await seed([[`clubs/${serverId}`, adoptedRoot(uid, roomId)],
    [`rooms/${roomId}`, { ...ordinaryRoom(uid), clubId: serverId, serverId, serverSchemaVersion: 1 }]]);
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 1, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, []);
  assert.equal(state.free.locked, false);
  // A legacy Club-bound room shape (clubId, no version marker) is simply not ordinary.
  await db.doc(`rooms/${roomId}`).set({ ...ordinaryRoom(uid), clubId: serverId });
  state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 1, familyFreeV1: 0 });
  await db.doc(`rooms/${roomId}`).set({ ...ordinaryRoom(uid), clubId: serverId, serverId, serverSchemaVersion: 1 });
  await db.doc(`clubs/${serverId}`).update({ status: "deleting" });
  await rejection(read(uid), "data-loss");
  await rejection(services().createServerV1(request(uid, input({ serverType: "family" }))), "data-loss");
  assert.equal(await exists(`clubs/family_${uid}`), false);
});

emulatorTest("(g) malformed roots fail closed on every path that can see them and are never counted as community", async () => {
  const service = services();
  const stringVersion = await owner();
  await seed([[`clubs/bad-${stringVersion}`, freeRoot(stringVersion, { serverSchemaVersion: "1", status: "active" })]]);
  await rejection(read(stringVersion), "data-loss");
  await rejection(service.createServerV1(request(stringVersion, input())), "data-loss");
  await rejection(service.createServerV1(request(stringVersion, input({ serverType: "family" }))), "data-loss");
  await rejection(premium(stringVersion), "data-loss");
  assert.equal(await ownedRoots(stringVersion), 1);

  // RESTATED AGAINST THE APPROVED P2-1 RECONCILIATION (review ledger, S2).
  // Exactly serverSchemaVersion 1 + type family + freeServersV1 is the one
  // mismatch capacity.js reconciles instead of refusing: the earliest
  // createServerV1 stamped the community policy on a family root, and without
  // the adapter every allocation path for that owner failed closed forever.
  // The original assertions (data-loss on read, create and premium) pinned the
  // pre-fix behaviour the ledger ordered reversed, so they are restated as the
  // reconciled outcome plus the proof that the adapter stays narrow.
  const familyFree = await owner();
  await seed([[`clubs/bad-${familyFree}`, freeRoot(familyFree, { type: "family", status: "active" })]]);
  const reconciled = await read(familyFree);
  assert.deepEqual(reconciled.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.equal(reconciled.free.count, 0);
  assert.deepEqual(reconciled.family, { count: 1, limit: FAMILY_SERVER_LIMIT });
  // Charged to the one-per-owner family policy: a second family is refused as
  // a family, not as unreadable data, and nothing is created.
  await rejection(service.createServerV1(request(familyFree, input({ serverType: "family" }))), "failed-precondition");
  assert.equal(await exists(`clubs/family_${familyFree}`), false);
  // Never charged to the free allowance...
  assert.equal((await service.createServerV1(request(familyFree, input()))).alreadyExisted, false);
  assert.deepEqual((await read(familyFree)).counts, { freeServersV1: 1, legacyRoomV1: 0, familyFreeV1: 1 });
  // ...and never visible to the Premium allowance either.
  assert.deepEqual(await premium(familyFree), { count: 0, limit: 3, exhaustive: true });
  // The adapter is one-directional, never a silent default: the mirror-image
  // pair (community root carrying the family policy) still fails closed.
  assert.throws(() => classifyServerAllocation({ serverSchemaVersion: 1, type: "community", entitlementPolicyId: "familyFreeV1" }),
    (error) => error.code === "data-loss");

  const futureFamily = await owner();
  await seed([[`clubs/bad-${futureFamily}`, familyRoot(futureFamily, { serverSchemaVersion: 2 })]]);
  await rejection(read(futureFamily), "data-loss");
  await rejection(service.createServerV1(request(futureFamily, input({ serverType: "family" }))), "data-loss");

  const unknownPolicy = await owner();
  await db.doc(`entitlements/${unknownPolicy}`).set(entitlement());
  await seed([[`clubs/bad-${unknownPolicy}`, freeRoot(unknownPolicy, { entitlementPolicyId: "premium", status: "active" })]]);
  await rejection(premium(unknownPolicy), "data-loss");
  await rejection(legacyQuota(unknownPolicy), "data-loss");
  // The exact free-policy queries cannot see an unknown policy: it is neither
  // charged to the free allowance nor to a family (reported as a coverage gap).
  const state = await read(unknownPolicy);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 0 });
});

emulatorTest("(h) held anchors, activated anchors and legacy lounges are excluded from the ordinary-room count for unguarded and guarded owners", async () => {
  const uid = await owner();
  const service = services();
  const serverId = `srv-${uid}`;
  const ordinary = [`ord-a-${uid}`, `ord-b-${uid}`];
  const others = [`held-${uid}`, `activated-${uid}`, `lounge-${uid}`];
  await seed([
    [`clubs/${serverId}`, freeRoot(uid, { status: "active" })],
    ...ordinary.map((id) => [`rooms/${id}`, ordinaryRoom(uid)]),
    [`rooms/held-${uid}`, heldAnchor(serverId)], [`rooms/activated-${uid}`, activeAnchor(uid, serverId)],
    [`rooms/lounge-${uid}`, { ...ordinaryRoom(uid), clubId: `legacy-${uid}`, roomKind: "clubLounge" }],
  ]);
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: 2, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, ordinary);
  assert.equal(state.free.locked, false);
  await seed([[`privateRoomHostGuards/${uid}`, roomGuard(uid, [...ordinary, ...others])]]);
  state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: 2, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, ordinary);
  const created = await service.createServerV1(request(uid, input()));
  assert.equal(created.alreadyExisted, false);
  assert.deepEqual((await doc(`privateRoomHostGuards/${uid}`)).activeRoomIds, ordinary);
  assert.equal((await doc(`privateRoomHostGuards/${uid}`)).capacityLocked, false);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: 2, legacyRoomV1: 2, familyFreeV1: 0 });
});

emulatorTest("(h) characterization of the author-flagged residual risk: for an owner WITHOUT a room guard, activated anchors are not counted but still occupy the legacy bounded room read", async () => {
  const uid = await owner();
  const serverId = `srv-${uid}`;
  const ordinary = Array.from({ length: FREE_SERVER_LIMIT - 2 }, (_, index) => `ord-${String(index).padStart(2, "0")}-${uid}`);
  await seed([
    [`clubs/${serverId}`, freeRoot(uid, { status: "active" })],
    ...ordinary.map((id) => [`rooms/${id}`, ordinaryRoom(uid)]),
    ...[0, 1, 2].map((index) => [`rooms/anchor-${index}-${uid}`, activeAnchor(uid, serverId)]),
  ]);
  const state = await read(uid);
  // 18 rooms + 1 free root = 19 allocations: the anchors are never counted...
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: FREE_SERVER_LIMIT - 2, familyFreeV1: 0 });
  assert.equal(state.free.count, FREE_SERVER_LIMIT - 1);
  // ...but 21 rows in the hostId/status bounded read report the owner locked,
  // exactly as legacy createRoom would. Revisit when activation is authorized.
  assert.equal(state.free.locked, true);
  await capacityRejection(services().createServerV1(request(uid, input())));
  assert.equal(await exists(`privateRoomHostGuards/${uid}`), false);
});

emulatorTest("(i) a locked room guard is never rewritten to unlocked: refused free create and transfer leave it untouched, a family transfer in persists it locked with its ids", async () => {
  const service = services();
  const source = await owner();
  const locked = await owner();
  const lockedGuard = roomGuard(locked, [`locked-a-${locked}`, `locked-b-${locked}`], true);
  await seed([[`privateRoomHostGuards/${locked}`, lockedGuard]]);
  await capacityRejection(service.createServerV1(request(locked, input())));
  assert.deepEqual(await doc(`privateRoomHostGuards/${locked}`), lockedGuard);
  const freeServer = await joinedServer(service, source, locked);
  await capacityRejection(transfer(service, source, freeServer, locked));
  assert.deepEqual(await doc(`privateRoomHostGuards/${locked}`), lockedGuard);
  assert.equal((await doc(`clubs/${freeServer}`)).ownerId, source);

  const family = await service.createServerV1(request(source, input({ serverType: "family" })));
  await activate(family.serverId, source);
  const inviter = await doc(`clubs/${family.serverId}/members/${source}`);
  await db.doc(`clubs/${family.serverId}/invites/${locked}`).set({
    serverSchemaVersion: 1, serverId: family.serverId, inviteeId: locked, inviterId: source,
    inviterAuthorizationRevision: inviter.authorizationRevision, generation: 1, status: "pending",
    expiresAt: Timestamp.fromMillis(nowMs + 60_000),
  });
  await service.respondToServerInviteV1(request(locked, { serverId: family.serverId, requestId: randomUUID(), response: "accept" }));
  await transfer(service, source, family.serverId, locked);
  assert.equal((await doc(`clubs/${family.serverId}`)).ownerId, locked);
  const guard = await doc(`privateRoomHostGuards/${locked}`);
  assert.equal(guard.capacityLocked, true);
  assert.deepEqual(guard.activeRoomIds, lockedGuard.activeRoomIds);
  assert.equal(guard.schemaVersion, 2);
  const state = await read(locked);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.equal(state.free.locked, true);
  await capacityRejection(service.createServerV1(request(locked, input())));
  assert.deepEqual((await doc(`privateRoomHostGuards/${locked}`)).activeRoomIds, lockedGuard.activeRoomIds);
});
