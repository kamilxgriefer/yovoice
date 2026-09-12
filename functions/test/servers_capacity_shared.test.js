const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// Shared version-aware allocation accounting (docs/Servers.md, "Creation,
// ownership and capacity"). Only an explicitly selected localhost demo
// emulator project is used. The default app is initialized because the legacy
// Club quota reads through utils/firestore's default Firestore instance; the
// V1 services receive the same instance through their dependencies.
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const projectId = "demo-yovoice-servers-capacity";
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
const { isActiveOrdinaryRoom } = require("../rooms/creation");

const nowMs = 1_900_000_000_000;
const CAPACITY_DETAILS = { reason: "server-capacity-reached", limit: FREE_SERVER_LIMIT };
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const input = (overrides = {}) => ({ requestId: randomUUID(), serverType: "friends", templateVersion: 1,
  name: "Trusted server", description: "", privacy: "inviteOnly", defaultLanguage: "English", ...overrides });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const capacityRejection = (promise) => assert.rejects(promise, (error) =>
  error.code === "resource-exhausted" && error.details?.reason === CAPACITY_DETAILS.reason &&
  error.details?.limit === CAPACITY_DETAILS.limit);
const read = (uid, extra = {}) => db.runTransaction((transaction) => readOwnerAllocations({ db, transaction, uid, ...extra }));
const premium = (uid, limit = 3) => db.runTransaction((transaction) => readPremiumClubAllocations({ db, transaction, uid, limit }));
const legacyQuota = (uid) => db.runTransaction((transaction) =>
  require("../clubs/quota").requireCommunityClubCapacity(transaction, uid));
const ownedRoots = async (uid) => (await db.collection("clubs").where("ownerId", "==", uid).get()).size;

function services() {
  const deps = { db, Timestamp, clock: () => nowMs };
  return { ...createServerCreationService(deps), ...createServerMembershipService(deps) };
}
async function owner() {
  const uid = `cap-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: "Canonical owner", status: "active" });
  return uid;
}
async function seed(documents) {
  const batch = db.batch();
  for (const [path, data] of documents) batch.set(db.doc(path), data);
  await batch.commit();
}
const freeRoot = (uid, extra = {}) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "freeServersV1",
  type: "community", status: "preparing", ...extra });
const freeRoots = (uid, count, prefix = `free-${uid}`) => Array.from({ length: count }, (_, index) =>
  [`clubs/${prefix}-${index}`, freeRoot(uid)]);
const legacyClub = (uid, extra = {}) => ({ ownerId: uid, type: "community", status: "active", ...extra });
const legacyFamily = (uid) => ({ ownerId: uid, type: "family", status: "active" });
const paidRoot = (uid) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "legacyCommunityPremiumV1",
  type: "community", status: "active" });
const familyRoot = (uid) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "familyFreeV1",
  type: "family", status: "active" });
const adoptedRoot = (uid, roomId) => ({ ownerId: uid, serverSchemaVersion: 1, entitlementPolicyId: "legacyRoomV1",
  type: "community", status: "active", migration: { version: 1, sourceKind: "room", sourceId: roomId, state: "applied" } });
const ordinaryRoom = (uid) => ({ hostId: uid, status: "active", roomType: "community" });
const roomGuard = (uid, activeRoomIds, capacityLocked = false) =>
  ({ schemaVersion: 2, ownerId: uid, activeRoomIds, capacityLocked });
const entitlement = () => ({ status: "active", isPremium: true, premiumIdentityEnabled: true, canCreateClubs: true,
  maxOwnedClubs: 3, currentPeriodEnd: Timestamp.fromMillis(Date.now() + 86_400_000) });

// deleteClubSelf runs its LiveKit and Storage work after the commit; the
// legacy family path under test needs neither a real provider nor a real
// bucket, only the interfaces club_self_deletion.test.js already exercises.
const clubControl = () => ({ async endRoom() {}, async revokeParticipant() {} });
const storageBucket = () => ({ name: "demo-yovoice.appspot.com",
  async deleteFiles() {}, file: () => ({ async delete() {} }) });
const deleteClub = (uid, clubId) => require("../clubs/deletion")
  .executeDeleteClubSelf(request(uid, { clubId }), clubControl(), storageBucket());
// The protected legacy family graph createServerV1 recovers: no version
// markers, invite-only, owner membership and the referenced voice channel.
const legacyFamilyGraph = (uid, clubId) => [
  [`clubs/${clubId}`, { ...legacyFamily(uid), name: "Family", privacy: "inviteOnly",
    defaultVoiceChannelId: `voice-${clubId}`, loungeRoomId: `club_lounge_${clubId}` }],
  [`clubs/${clubId}/members/${uid}`, { userId: uid, role: "owner" }],
  [`clubs/${clubId}/channels/voice-${clubId}`, { name: "Salon", kind: "voice" }],
];

// Emulator fixture activation only, never a shipped activation path.
async function activate(serverId, uid) {
  await db.doc(`clubs/${serverId}`).update({ status: "active", serverActivationState: "active" });
  const anchors = await db.collection("rooms").where("serverId", "==", serverId).get();
  for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: uid });
}
async function invite(serverId, inviterId, inviteeId) {
  const inviter = (await db.doc(`clubs/${serverId}/members/${inviterId}`).get()).data();
  await db.doc(`clubs/${serverId}/invites/${inviteeId}`).set({
    serverSchemaVersion: 1, serverId, inviteeId, inviterId, inviterAuthorizationRevision: inviter.authorizationRevision,
    generation: 1, status: "pending", expiresAt: Timestamp.fromMillis(nowMs + 60_000),
  });
}

after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

test("classification follows version markers and fails closed on malformed versioned roots", () => {
  assert.deepEqual(classifyServerAllocation({ ownerId: "u" }), { policy: "legacyCommunityPremiumV1", versioned: false });
  assert.deepEqual(classifyServerAllocation({ ownerId: "u", type: "community" }), { policy: "legacyCommunityPremiumV1", versioned: false });
  assert.deepEqual(classifyServerAllocation({ ownerId: "u", type: "family" }), { policy: "familyFreeV1", versioned: false });
  // A policy id alone is not a version marker: the legacy adapter still applies.
  assert.deepEqual(classifyServerAllocation({ type: "community", entitlementPolicyId: "legacyCommunityPremiumV1" }),
    { policy: "legacyCommunityPremiumV1", versioned: false });
  for (const policy of ["freeServersV1", "legacyRoomV1", "legacyCommunityPremiumV1"]) {
    assert.deepEqual(classifyServerAllocation({ serverSchemaVersion: 1, type: "community", entitlementPolicyId: policy }),
      { policy, versioned: true });
  }
  assert.deepEqual(classifyServerAllocation({ serverSchemaVersion: 1, type: "family", entitlementPolicyId: "familyFreeV1" }),
    { policy: "familyFreeV1", versioned: true });
  // The ONE reconciled mismatch: a canonical V1 family root that the earliest
  // createServerV1 stamped with the community policy is read as the family
  // allocation it always was, instead of wedging every allocation path.
  assert.deepEqual(classifyServerAllocation({ serverSchemaVersion: 1, type: "family", entitlementPolicyId: "freeServersV1" }),
    { policy: "familyFreeV1", versioned: true });
  // ...and it is exactly that pair: a different schema version, a different
  // policy or a community root still fails closed.
  for (const malformed of [
    { serverSchemaVersion: 1, type: "community" },
    { serverSchemaVersion: 2, type: "community", entitlementPolicyId: "freeServersV1" },
    { serverSchemaVersion: 2, type: "family", entitlementPolicyId: "freeServersV1" },
    { serverSchemaVersion: 1, type: "community", entitlementPolicyId: "unlimitedV9" },
    { serverType: "friends", type: "family", entitlementPolicyId: "freeServersV1" },
    { serverSchemaVersion: 1, type: "family", entitlementPolicyId: "legacyRoomV1" },
    { serverSchemaVersion: 1, type: "community", entitlementPolicyId: "familyFreeV1" },
  ]) assert.throws(() => classifyServerAllocation(malformed), (error) => error.code === "data-loss");
});

emulatorTest("the free allowance is exact at the 20/21 boundary and refuses with the structured capacity error", async () => {
  const uid = await owner();
  const service = services();
  await seed(freeRoots(uid, FREE_SERVER_LIMIT - 1));
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT - 1, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.deepEqual(state.free, { count: FREE_SERVER_LIMIT - 1, limit: FREE_SERVER_LIMIT, exhaustive: true, locked: false });
  const twentieth = await service.createServerV1(request(uid, input()));
  assert.equal(twentieth.alreadyExisted, false);
  assert.equal((await db.doc(`clubs/${twentieth.serverId}`).get()).data().entitlementPolicyId, "freeServersV1");
  state = await read(uid);
  assert.equal(state.free.count, FREE_SERVER_LIMIT);
  await capacityRejection(service.createServerV1(request(uid, input())));
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT);
});

emulatorTest("legacy Clubs, retained paid Clubs and a legacy family are never charged to the free allowance", async () => {
  const uid = await owner();
  const service = services();
  await seed([
    [`clubs/legacy-a-${uid}`, legacyClub(uid)], [`clubs/legacy-b-${uid}`, legacyClub(uid)],
    [`clubs/legacy-untyped-${uid}`, { ownerId: uid, status: "active" }],
    // A family owned under another root id (for example transferred in) must
    // be recovered first; the deterministic id would take the recovery path.
    [`clubs/paid-${uid}`, paidRoot(uid)], [`clubs/family-transferred-${uid}`, legacyFamily(uid)],
    ...freeRoots(uid, FREE_SERVER_LIMIT - 1),
  ]);
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT - 1, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.equal(state.free.count, FREE_SERVER_LIMIT - 1);
  await service.createServerV1(request(uid, input()));
  await capacityRejection(service.createServerV1(request(uid, input())));
  // Existing family constraints are unchanged: the legacy family must be recovered.
  await rejection(service.createServerV1(request(uid, input({ serverType: "family" }))), "failed-precondition");
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 5);
});

emulatorTest("a V1 family is charged to familyFreeV1, keeps its reservation and never consumes the free allowance", async () => {
  const uid = await owner();
  const service = services();
  await seed(freeRoots(uid, FREE_SERVER_LIMIT));
  await capacityRejection(service.createServerV1(request(uid, input())));
  const family = await service.createServerV1(request(uid, input({ serverType: "family" })));
  assert.equal(family.serverId, `family_${uid}`);
  const root = (await db.doc(`clubs/${family.serverId}`).get()).data();
  assert.equal(root.entitlementPolicyId, "familyFreeV1");
  assert.equal(root.type, "family");
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).data().serverId, family.serverId);
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.deepEqual(state.family, { count: 1, limit: FAMILY_SERVER_LIMIT });
  const replay = await service.createServerV1(request(uid, input({ serverType: "family", name: "Second family" })));
  assert.equal(replay.serverId, family.serverId);
  assert.equal(replay.alreadyExisted, true);
  await capacityRejection(service.createServerV1(request(uid, input())));
});

emulatorTest("mixed owner: 3 legacy Clubs, 20 free servers, a family and a standalone room are reported over the free limit, retained and block only additional free allocation", async () => {
  const uid = await owner();
  const service = services();
  const roomId = `room-${uid}`;
  await seed([
    [`clubs/legacy-a-${uid}`, legacyClub(uid)], [`clubs/legacy-b-${uid}`, legacyClub(uid)], [`clubs/legacy-c-${uid}`, legacyClub(uid)],
    [`clubs/family-transferred-${uid}`, legacyFamily(uid)], [`rooms/${roomId}`, ordinaryRoom(uid)],
    [`privateRoomHostGuards/${uid}`, roomGuard(uid, [roomId])],
    ...freeRoots(uid, FREE_SERVER_LIMIT),
  ]);
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 1, familyFreeV1: 1 });
  assert.deepEqual(state.free, { count: FREE_SERVER_LIMIT + 1, limit: FREE_SERVER_LIMIT, exhaustive: true, locked: false });
  assert.deepEqual(state.activeRoomIds, [roomId]);
  await capacityRejection(service.createServerV1(request(uid, input())));
  await rejection(service.createServerV1(request(uid, input({ serverType: "family" }))), "failed-precondition");
  // The Premium allowance sees exactly the legacy data: three Clubs plus the
  // family-shaped root fill the bounded legacy read, as before.
  assert.deepEqual(await premium(uid), { count: 3, limit: 3, exhaustive: false });
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 4);
  assert.deepEqual((await db.doc(`privateRoomHostGuards/${uid}`).get()).data(), roomGuard(uid, [roomId]));
});

emulatorTest("an adopted room keeps one allocation: never double-counted, never lost by acquiring clubId", async () => {
  const uid = await owner();
  const roomId = `adopted-${uid}`;
  const serverId = `server-${uid}`;
  await seed([
    [`rooms/${roomId}`, ordinaryRoom(uid)], [`privateRoomHostGuards/${uid}`, roomGuard(uid, [roomId])],
    [`clubs/${serverId}`, adoptedRoot(uid, roomId)],
  ]);
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 1, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, [roomId]);
  await db.doc(`rooms/${roomId}`).update({ serverSchemaVersion: 1, serverId, clubId: serverId });
  state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 1, familyFreeV1: 0 });
  assert.equal(state.free.count, 1);
  assert.deepEqual(state.activeRoomIds, []);
  await db.doc(`clubs/duplicate-${uid}`).set(adoptedRoot(uid, roomId));
  await rejection(read(uid), "data-loss");
  await db.doc(`clubs/duplicate-${uid}`).delete();
  await db.doc(`clubs/${serverId}`).delete();
  await rejection(read(uid), "data-loss");
});

emulatorTest("held V1 anchors are excluded from room allocation counting for legacy-bootstrap and guarded owners", async () => {
  const uid = await owner();
  const service = services();
  const roomIds = [`ordinary-a-${uid}`, `ordinary-b-${uid}`];
  await seed(roomIds.map((id) => [`rooms/${id}`, ordinaryRoom(uid)]));
  assert.equal((await db.doc(`privateRoomHostGuards/${uid}`).get()).exists, false);
  const created = await service.createServerV1(request(uid, input({ serverType: "company" })));
  const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
  assert.ok(anchors.size > 0);
  for (const anchor of anchors.docs) {
    assert.equal(anchor.data().hostId, null);
    assert.equal(anchor.data().status, "preparing");
    assert.equal(isActiveOrdinaryRoom(anchor, uid), false);
  }
  let state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: 2, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, roomIds);
  const guard = (await db.doc(`privateRoomHostGuards/${uid}`).get()).data();
  assert.deepEqual(guard.activeRoomIds, roomIds);
  assert.equal(guard.capacityLocked, false);
  await activate(created.serverId, uid);
  for (const anchor of anchors.docs) assert.equal(isActiveOrdinaryRoom(await anchor.ref.get(), uid), false);
  state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: 2, familyFreeV1: 0 });
  await db.doc(`privateRoomHostGuards/${uid}`).delete();
  state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 1, legacyRoomV1: 2, familyFreeV1: 0 });
  assert.deepEqual(state.activeRoomIds, roomIds);
});

emulatorTest("a locked room guard blocks free allocation, reports, and is neither rewritten nor charged to a family", async () => {
  const uid = await owner();
  const service = services();
  await seed([[`privateRoomHostGuards/${uid}`, roomGuard(uid, [`locked-${uid}`], true)]]);
  const state = await read(uid);
  assert.equal(state.free.locked, true);
  assert.equal(state.free.count, 0);
  await capacityRejection(service.createServerV1(request(uid, input())));
  await service.createServerV1(request(uid, input({ serverType: "family" })));
  const guard = (await db.doc(`privateRoomHostGuards/${uid}`).get()).data();
  assert.equal(guard.capacityLocked, true);
  assert.deepEqual(guard.activeRoomIds, [`locked-${uid}`]);
});

emulatorTest("over-limit free data is reported without rewriting and blocks only additional free allocation", async () => {
  const uid = await owner();
  const service = services();
  await seed(freeRoots(uid, FREE_SERVER_LIMIT + 2));
  const state = await read(uid);
  assert.equal(state.free.exhaustive, false);
  assert.equal(state.free.count, FREE_SERVER_LIMIT + 1);
  await capacityRejection(service.createServerV1(request(uid, input())));
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 2);
  const family = await service.createServerV1(request(uid, input({ serverType: "family" })));
  assert.equal((await db.doc(`clubs/${family.serverId}`).get()).data().entitlementPolicyId, "familyFreeV1");
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 3);
});

emulatorTest("legacy Premium accounting is byte-for-byte for legacy-only owners", async () => {
  const uid = await owner();
  await seed([[`clubs/one-${uid}`, legacyClub(uid)], [`clubs/two-${uid}`, { ownerId: uid }]]);
  assert.deepEqual(await premium(uid), { count: 2, limit: 3, exhaustive: true });
  await db.doc(`clubs/three-${uid}`).set(legacyClub(uid, { deletionInProgress: true }));
  assert.deepEqual(await premium(uid), { count: 3, limit: 3, exhaustive: true });
  await db.doc(`clubs/three-${uid}`).delete();
  await db.doc(`clubs/family_${uid}`).set(legacyFamily(uid));
  assert.deepEqual(await premium(uid), { count: 2, limit: 3, exhaustive: true });
  await db.doc(`clubs/flood-${uid}`).set(legacyFamily(uid));
  assert.deepEqual(await premium(uid), { count: 2, limit: 3, exhaustive: false });
});

emulatorTest("legacy requireCommunityClubCapacity skips every free-policy V1 root and keeps the bounded fail-closed scan", async () => {
  const uid = await owner();
  await db.doc(`entitlements/${uid}`).set(entitlement());
  // Free roots sort before the legacy roots so the first legacy page is
  // entirely skipped and the scan has to page deterministically.
  await seed([
    ...freeRoots(uid, FREE_SERVER_LIMIT, `a-free-${uid}`),
    [`clubs/a-family-${uid}`, familyRoot(uid)],
    [`clubs/a-room-${uid}`, adoptedRoot(uid, `room-${uid}`)],
    [`rooms/room-${uid}`, ordinaryRoom(uid)],
  ]);
  assert.deepEqual(await legacyQuota(uid), { ownedCommunityClubs: 0, limit: 3 });
  await seed([[`clubs/z-legacy-a-${uid}`, legacyClub(uid)], [`clubs/z-legacy-b-${uid}`, legacyClub(uid)], [`clubs/z-paid-${uid}`, paidRoot(uid)]]);
  await rejection(legacyQuota(uid), "resource-exhausted");
  await db.doc(`clubs/z-paid-${uid}`).delete();
  assert.deepEqual(await legacyQuota(uid), { ownedCommunityClubs: 2, limit: 3 });
  // Interleaved ids: legacy roots between free roots are still seen exactly once.
  await db.doc(`clubs/free-${uid}-middle`).set(legacyClub(uid));
  await rejection(legacyQuota(uid), "resource-exhausted");
  await db.doc(`clubs/free-${uid}-middle`).delete();
  await seed(Array.from({ length: 4 }, (_, index) => [`clubs/z-flood-${uid}-${index}`, legacyFamily(uid)]));
  await rejection(legacyQuota(uid), "resource-exhausted");
  for (const index of [1, 2, 3]) await db.doc(`clubs/z-flood-${uid}-${index}`).delete();
  assert.deepEqual(await legacyQuota(uid), { ownedCommunityClubs: 2, limit: 3 });
  await seed(freeRoots(uid, MAX_SKIPPED_FREE_ROOTS + 1 - FREE_SERVER_LIMIT, `b-free-${uid}`));
  await rejection(legacyQuota(uid), "data-loss");
});

emulatorTest("createCommunityClub end-to-end: a full free allowance leaves the Premium allowance untouched", async () => {
  const uid = await owner();
  await db.doc(`entitlements/${uid}`).set(entitlement());
  await seed(freeRoots(uid, FREE_SERVER_LIMIT));
  const { createCommunityClub } = require("../clubs/creation");
  const run = (clubId) => createCommunityClub.run({
    auth: { uid, token: { email_verified: true, email: `${uid}@example.invalid`, name: "Club Owner" } },
    data: { clubId, name: "Secure Club", description: "Created atomically", privacy: "public",
      defaultLanguage: "English", avatarUrl: null, bannerUrl: null },
  });
  for (const index of [0, 1, 2]) assert.equal((await run(`legacy-${uid}-${index}`)).alreadyExisted, false);
  await rejection(run(`legacy-${uid}-3`), "resource-exhausted");
  assert.equal(await ownedRoots(uid), FREE_SERVER_LIMIT + 3);
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
});

emulatorTest("transfer charges the recipient under the transferred policy: a full recipient cannot gain a free allocation", async () => {
  const uid = await owner();
  const recipient = await owner();
  const service = services();
  const created = await service.createServerV1(request(uid, input({ serverType: "community", privacy: "public" })));
  await activate(created.serverId, uid);
  await service.joinServerV1(request(recipient, { serverId: created.serverId, requestId: randomUUID() }));
  await seed(freeRoots(recipient, FREE_SERVER_LIMIT));
  const transfer = () => service.transferServerOwnershipV1(request(uid, {
    serverId: created.serverId, requestId: randomUUID(), newOwnerId: recipient,
  }));
  await capacityRejection(transfer());
  assert.equal((await db.doc(`clubs/${created.serverId}`).get()).data().ownerId, uid);
  await db.doc(`clubs/free-${recipient}-0`).delete();
  await transfer();
  assert.equal((await db.doc(`clubs/${created.serverId}`).get()).data().ownerId, recipient);
  assert.deepEqual((await read(recipient)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 0 });
  assert.deepEqual((await read(uid)).counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 0 });
});

emulatorTest("a family transfer needs the recipient's family capacity and reservation, never free allowance", async () => {
  const service = services();
  const fullRecipient = await owner();
  await seed(freeRoots(fullRecipient, FREE_SERVER_LIMIT));
  const first = await owner();
  const family = await service.createServerV1(request(first, input({ serverType: "family" })));
  await activate(family.serverId, first);
  await invite(family.serverId, first, fullRecipient);
  await service.respondToServerInviteV1(request(fullRecipient, { serverId: family.serverId, requestId: randomUUID(), response: "accept" }));
  await service.transferServerOwnershipV1(request(first, { serverId: family.serverId, requestId: randomUUID(), newOwnerId: fullRecipient }));
  assert.equal((await db.doc(`clubs/${family.serverId}`).get()).data().ownerId, fullRecipient);
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${fullRecipient}`).get()).data().serverId, family.serverId);
  assert.deepEqual((await read(fullRecipient)).counts, { freeServersV1: FREE_SERVER_LIMIT, legacyRoomV1: 0, familyFreeV1: 1 });
  await capacityRejection(service.createServerV1(request(fullRecipient, input())));

  const second = await owner();
  const familyOwner = await owner();
  await seed([[`clubs/family_${familyOwner}`, legacyFamily(familyOwner)]]);
  const other = await service.createServerV1(request(second, input({ serverType: "family" })));
  await activate(other.serverId, second);
  await invite(other.serverId, second, familyOwner);
  await service.respondToServerInviteV1(request(familyOwner, { serverId: other.serverId, requestId: randomUUID(), response: "accept" }));
  await rejection(service.transferServerOwnershipV1(request(second, {
    serverId: other.serverId, requestId: randomUUID(), newOwnerId: familyOwner,
  })), "resource-exhausted");
  assert.equal((await db.doc(`clubs/${other.serverId}`).get()).data().ownerId, second);
  await db.doc(`clubs/${other.serverId}`).update({ entitlementPolicyId: "freeServersV1" });
  await rejection(service.transferServerOwnershipV1(request(second, {
    serverId: other.serverId, requestId: randomUUID(), newOwnerId: familyOwner,
  })), "data-loss");
});

emulatorTest("a V1 family root stamped with the community policy is reconciled to its family allocation and never wedges the owner", async () => {
  const uid = await owner();
  const service = services();
  const family = await service.createServerV1(request(uid, input({ serverType: "family" })));
  // Exactly what the earliest createServerV1 persisted: a canonical V1 family
  // root carrying entitlementPolicyId freeServersV1.
  await db.doc(`clubs/${family.serverId}`).update({ entitlementPolicyId: "freeServersV1" });
  const state = await read(uid);
  assert.deepEqual(state.counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
  assert.deepEqual(state.free, { count: 0, limit: FREE_SERVER_LIMIT, exhaustive: true, locked: false });
  assert.deepEqual(state.family, { count: 1, limit: FAMILY_SERVER_LIMIT });
  // A family is never charged to the Premium allowance either.
  assert.deepEqual(await premium(uid), { count: 0, limit: 3, exhaustive: true });
  const created = await service.createServerV1(request(uid, input()));
  assert.equal(created.alreadyExisted, false);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: 1, legacyRoomV1: 0, familyFreeV1: 1 });
  const replay = await service.createServerV1(request(uid, input({ serverType: "family", name: "Second family" })));
  assert.equal(replay.serverId, family.serverId);
  assert.equal(replay.alreadyExisted, true);
  assert.equal(await ownedRoots(uid), 2);
});

emulatorTest("deleting a recovered legacy family releases its ownership reservation, so the owner can create a family again", async () => {
  const uid = await owner();
  const service = services();
  const clubId = `family_${uid}`;
  await seed(legacyFamilyGraph(uid, clubId));
  const recovered = await service.createServerV1(request(uid, input({ serverType: "family" })));
  assert.equal(recovered.serverId, clubId);
  assert.equal(recovered.alreadyExisted, true);
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).data().serverId, clubId);
  assert.deepEqual(await deleteClub(uid, clubId), { success: true, clubId });
  assert.equal((await db.doc(`clubs/${clubId}`).get()).exists, false);
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).exists, false);
  const again = await service.createServerV1(request(uid, input({ serverType: "family" })));
  assert.equal(again.alreadyExisted, false);
  assert.equal(again.serverId, clubId);
  const root = (await db.doc(`clubs/${clubId}`).get()).data();
  assert.equal(root.entitlementPolicyId, "familyFreeV1");
  assert.equal(root.serverSchemaVersion, 1);
  assert.equal((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).data().serverId, clubId);
  assert.deepEqual((await read(uid)).counts, { freeServersV1: 0, legacyRoomV1: 0, familyFreeV1: 1 });
});

emulatorTest("legacy Club deletion releases only a reservation bound to the deleted club", async () => {
  const uid = await owner();
  const clubId = `family_${uid}`;
  const reservation = { schemaVersion: 1, ownerId: uid, serverId: `family-elsewhere-${uid}`, status: "active" };
  await seed([...legacyFamilyGraph(uid, clubId), [`serverFamilyOwnerReservations/${uid}`, reservation]]);
  await deleteClub(uid, clubId);
  assert.equal((await db.doc(`clubs/${clubId}`).get()).exists, false);
  assert.deepEqual((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).data(), reservation);
  // A legacy community Club never touches the reservation, and still bumps the
  // ownership guard the community quota serializes.
  const community = `legacy-community-${uid}`;
  await seed([[`clubs/${community}`, legacyClub(uid, { name: "Legacy", loungeRoomId: `club_lounge_${community}` })]]);
  await deleteClub(uid, community);
  assert.equal((await db.doc(`clubs/${community}`).get()).exists, false);
  assert.deepEqual((await db.doc(`serverFamilyOwnerReservations/${uid}`).get()).data(), reservation);
  assert.ok(((await db.doc(`clubOwnershipGuards/${uid}`).get()).data()?.revision ?? 0) >= 1);
});
