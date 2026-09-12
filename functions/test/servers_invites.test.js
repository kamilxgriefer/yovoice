// V1 invitations (gap G1, ADR-178): the only writer of the document
// respondToServerInviteV1 consumes, its private discovery pointer, and the
// generation/expiry/revocation semantics, proven on a real Firestore
// emulator through the reviewed factories. Fixture activation is the same
// isolated emulator step the membership suite uses; nothing here is a
// shipped activation path.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let db;
let app;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp({ projectId: "demo-yovoice-servers-invites" }, `server-invites-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerInviteService, INVITER_ROLES } = require("../servers/invites");
const { createServerMembershipService } = require("../servers/memberships");
const { SERVER_INVITE_TTL_MS, serverInviteRefPath } = require("../servers/contract");
const { rateLimitReference } = require("../integrity/guards");

const START_MS = 1_900_000_000_000;
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const rejection = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const creation = (serverType = "friends") => ({ requestId: randomUUID(), serverType, templateVersion: 1,
  name: "Invite server", description: "", privacy: serverType === "community" ? "public" : "inviteOnly", defaultLanguage: "English" });
const operation = (serverId, extra = {}) => ({ serverId, requestId: randomUUID(), ...extra });
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

async function user(label = "u") {
  const uid = `si-${label}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({ displayName: `Canonical ${label}`, status: "active" });
  return uid;
}

// The canonical friendship authority, in the exact shape social_graph.js mints.
async function friends(first, second) {
  const establishedAt = Timestamp.fromMillis(START_MS - 1);
  await Promise.all([[first, second], [second, first]].map(([ownerId, friendId]) =>
    db.doc(`friendshipGuards/${ownerId}/friends/${friendId}`).set({ ownerId, friendId, schemaVersion: 1, establishedAt })));
}

async function fixture(serverType = "friends", { held = false } = {}) {
  const uid = await user("owner");
  let nowMs = START_MS;
  const deps = { db, Timestamp, clock: () => nowMs };
  const service = { ...createServerCreationService(deps), ...createServerInviteService(deps), ...createServerMembershipService(deps) };
  const created = await service.createServerV1(request(uid, creation(serverType)));
  if (!held) {
    // Explicit emulator fixture activation, never a shipped activation path.
    await db.doc(`clubs/${created.serverId}`).update({ status: "active", serverActivationState: "active" });
    const anchors = await db.collection("rooms").where("serverId", "==", created.serverId).get();
    for (const anchor of anchors.docs) await anchor.ref.update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  const serverId = created.serverId;
  return {
    uid, serverId, ...service,
    advance: (ms) => { nowMs += ms; }, now: () => nowMs,
    invite: (inviter, inviteeId, requestId = randomUUID()) =>
      service.createServerInviteV1(request(inviter, { serverId, inviteeId, requestId })),
    revoke: (actor, inviteeId, requestId = randomUUID()) =>
      service.revokeServerInviteV1(request(actor, { serverId, inviteeId, requestId })),
    respond: (invitee, response, requestId = randomUUID()) =>
      service.respondToServerInviteV1(request(invitee, { serverId, requestId, response })),
    inviteDoc: async (inviteeId) => (await db.doc(`clubs/${serverId}/invites/${inviteeId}`).get()).data() ?? null,
    pointer: async (inviteeId) => (await db.doc(serverInviteRefPath(inviteeId, serverId)).get()),
    // Seeded roster rows in the canonical member shape, like the other suites.
    member: async (role = "member") => {
      const memberId = await user(role);
      await db.doc(`clubs/${serverId}/members/${memberId}`).set({ userId: memberId, role, displayName: `Canonical ${role}`,
        photoUrl: null, authorizationRevision: 1, joinedAt: Timestamp.fromMillis(START_MS), isOnline: false, invitedBy: null });
      return memberId;
    },
  };
}

emulatorTest("an inviter-capable member invites a friend: exact document, private pointer, replay, reuse, and acceptance retires the pointer", async () => {
  const f = await fixture();
  const invitee = await user("invitee");
  await friends(f.uid, invitee);
  const requestId = randomUUID();
  const result = await f.invite(f.uid, invitee, requestId);
  assert.deepEqual(result, { serverId: f.serverId, inviteeId: invitee, generation: 1, status: "pending",
    expiresAtMillis: START_MS + SERVER_INVITE_TTL_MS, alreadyExisted: false });
  const invite = await f.inviteDoc(invitee);
  assert.deepEqual(Object.keys(invite).sort(), ["createdAt", "expiresAt", "generation", "inviteeId",
    "inviterAuthorizationRevision", "inviterId", "inviterName", "serverId", "serverName", "serverSchemaVersion", "status", "updatedAt"]);
  assert.equal(invite.serverSchemaVersion, 1);
  assert.equal(invite.serverId, f.serverId);
  assert.equal(invite.inviteeId, invitee);
  assert.equal(invite.inviterId, f.uid);
  assert.equal(invite.inviterAuthorizationRevision, 1);
  assert.equal(invite.status, "pending");
  assert.equal(invite.generation, 1);
  assert.equal(invite.expiresAt.toMillis(), START_MS + SERVER_INVITE_TTL_MS);
  assert.equal(invite.serverName, "Invite server");
  assert.equal(invite.inviterName, "Canonical owner");
  // The pointer carries opaque ids, the generation and the expiry: no name,
  // no inviter, no preview.
  const pointer = await f.pointer(invitee);
  assert.deepEqual(Object.keys(pointer.data()).sort(), ["expiresAt", "generation", "serverId"]);
  assert.equal(pointer.data().serverId, f.serverId);
  assert.equal(pointer.data().generation, 1);
  assert.equal(pointer.data().expiresAt.toMillis(), START_MS + SERVER_INVITE_TTL_MS);
  // Same request replays; a new request while the invitation stands reuses
  // it without churning the generation or the expiry. Both calls charge the
  // dedicated invite budget: a replay is not a free existence probe.
  assert.deepEqual(await f.invite(f.uid, invitee, requestId), result);
  assert.equal((await rateLimitReference(db, "server.v1.invite", f.uid).get()).data().count, 2);
  f.advance(60_000);
  assert.deepEqual(await f.invite(f.uid, invitee), { ...result, alreadyExisted: true });
  assert.deepEqual(await f.inviteDoc(invitee), invite);
  // A moderator holds the same reach as the legacy INVITER_ROLES.
  assert.deepEqual([...INVITER_ROLES], ["owner", "coOwner", "admin", "moderator"]);
  // Acceptance goes through the unchanged consumer and retires the pointer.
  const joined = await f.respond(invitee, "accept");
  assert.equal(joined.joined, true);
  assert.equal(joined.inviteGeneration, 1);
  assert.equal((await f.inviteDoc(invitee)).status, "accepted");
  assert.equal((await f.pointer(invitee)).exists, false);
  assert.equal((await db.doc(`clubs/${f.serverId}/members/${invitee}`).get()).data().invitedBy, f.uid);
  await rejection(f.invite(f.uid, invitee), "failed-precondition");
  // The 60 s advance above opened a new fixed window; the reuse and the
  // refusal both landed in it, so a denied call is charged like any other.
  assert.equal((await rateLimitReference(db, "server.v1.invite", f.uid).get()).data().count, 2);
});

emulatorTest("who may invite: moderator yes; member, guest, self, outsider and a held server's own owner no, and a refusal writes nothing", async () => {
  const f = await fixture("company");
  const moderator = await f.member("moderator");
  const member = await f.member("member");
  const guest = await f.member("guest");
  const outsider = await user("outsider");
  const invitee = await user("invitee");
  for (const inviter of [moderator, member, guest, outsider]) await friends(inviter, invitee);
  await rejection(f.invite(member, invitee), "permission-denied");
  await rejection(f.invite(guest, invitee), "permission-denied");
  await rejection(f.invite(outsider, invitee), "permission-denied");
  await rejection(f.invite(f.uid, f.uid), "invalid-argument");
  assert.equal(await f.inviteDoc(invitee), null);
  assert.equal((await f.pointer(invitee)).exists, false);
  const issued = await f.invite(moderator, invitee);
  assert.equal(issued.generation, 1);
  assert.equal((await f.inviteDoc(invitee)).inviterId, moderator);
  // Unknown keys are refused whole, exactly like every other V1 input.
  await rejection(f.createServerInviteV1(request(f.uid, { ...operation(f.serverId), inviteeId: invitee, role: "admin" })), "invalid-argument");
  // A held server refuses invitations entirely, even from its owner: there is
  // no admission path while held, so nothing about it may reach a third party.
  const held = await fixture("friends", { held: true });
  const target = await user("held-target");
  await friends(held.uid, target);
  await rejection(held.invite(held.uid, target), "permission-denied");
  assert.equal(await held.inviteDoc(target), null);
  assert.equal((await held.pointer(target)).exists, false);
});

emulatorTest("invitee state fails closed with one denial: not friends, blocked either way, banned, restricted, missing; a restricted inviter is refused too", async () => {
  const f = await fixture();
  const cases = [];
  const stranger = await user("stranger");
  cases.push(["not friends", stranger]);
  const blockedByInviter = await user("blocked-by-inviter");
  await friends(f.uid, blockedByInviter);
  await db.doc(`users/${f.uid}/blocked/${blockedByInviter}`).set({ blockedAt: Timestamp.fromMillis(START_MS) });
  cases.push(["blocked by the inviter", blockedByInviter]);
  const blockingInviter = await user("blocking-inviter");
  await friends(f.uid, blockingInviter);
  await db.doc(`users/${blockingInviter}/blocked/${f.uid}`).set({ blockedAt: Timestamp.fromMillis(START_MS) });
  cases.push(["blocking the inviter", blockingInviter]);
  const banned = await user("banned");
  await friends(f.uid, banned);
  await db.doc(`users/${banned}`).update({ banned: true });
  cases.push(["banned", banned]);
  const restricted = await user("restricted");
  await friends(f.uid, restricted);
  await db.doc(`restrictions/${restricted}`).set({ type: "communicationMute", expiresAt: Timestamp.fromMillis(START_MS + 60_000) });
  cases.push(["restricted", restricted]);
  const missing = `si-missing-${randomUUID()}`;
  await friends(f.uid, missing);
  cases.push(["missing profile", missing]);
  const halfFriend = await user("half-friend");
  await db.doc(`friendshipGuards/${f.uid}/friends/${halfFriend}`).set({ ownerId: f.uid, friendId: halfFriend, schemaVersion: 1, establishedAt: Timestamp.fromMillis(START_MS) });
  cases.push(["one-sided guard", halfFriend]);
  for (const [label, invitee] of cases) {
    await assert.rejects(f.invite(f.uid, invitee), (error) => {
      assert.equal(error.code, "permission-denied", label);
      assert.equal(error.message, "You do not have access to this server resource.", label);
      return true;
    });
    assert.equal(await f.inviteDoc(invitee), null, label);
    assert.equal((await f.pointer(invitee)).exists, false, label);
  }
  // A sanctioned inviter cannot reach anyone.
  const invitee = await user("invitee");
  await friends(f.uid, invitee);
  await db.doc(`restrictions/${f.uid}`).set({ type: "communicationMute", expiresAt: null });
  await rejection(f.invite(f.uid, invitee), "permission-denied");
  await db.doc(`restrictions/${f.uid}`).delete();
  assert.equal((await f.invite(f.uid, invitee)).generation, 1);
});

emulatorTest("revocation invalidates the generation: acceptance is denied, the pointer is gone, a re-issue starts a new generation and an old decline receipt cannot touch it", async () => {
  const f = await fixture();
  const invitee = await user("invitee");
  await friends(f.uid, invitee);
  const member = await f.member("member");
  await rejection(f.revoke(f.uid, invitee), "not-found");
  await f.invite(f.uid, invitee);
  await rejection(f.revoke(member, invitee), "permission-denied");
  const revokeId = randomUUID();
  const revoked = await f.revoke(f.uid, invitee, revokeId);
  assert.deepEqual(revoked, { serverId: f.serverId, inviteeId: invitee, generation: 1, status: "revoked",
    expiresAtMillis: START_MS + SERVER_INVITE_TTL_MS, revoked: true });
  const stored = await f.inviteDoc(invitee);
  assert.equal(stored.status, "revoked");
  assert.equal(stored.revokedById, f.uid);
  assert.equal(stored.generation, 1);
  assert.equal((await f.pointer(invitee)).exists, false);
  await rejection(f.respond(invitee, "accept"), "permission-denied");
  await rejection(f.respond(invitee, "decline"), "permission-denied");
  assert.equal((await db.doc(`clubs/${f.serverId}/members/${invitee}`).get()).exists, false);
  // Replay and a fresh revoke of an already-revoked invitation are idempotent.
  assert.deepEqual(await f.revoke(f.uid, invitee, revokeId), revoked);
  assert.deepEqual(await f.revoke(f.uid, invitee), { ...revoked, revoked: false });
  // A re-issue is a new generation with a clean document and a fresh pointer.
  const reissued = await f.invite(f.uid, invitee);
  assert.equal(reissued.generation, 2);
  assert.equal(reissued.alreadyExisted, false);
  const fresh = await f.inviteDoc(invitee);
  assert.equal(fresh.status, "pending");
  assert.equal(Object.hasOwn(fresh, "revokedAt"), false);
  assert.equal(Object.hasOwn(fresh, "revokedById"), false);
  assert.equal((await f.pointer(invitee)).data().generation, 2);
  // The old revoke receipt is bound to generation 1 and cannot act on 2.
  await rejection(f.revoke(f.uid, invitee, revokeId), "aborted");
  // Decline answers generation 2 and retires the pointer; an answered
  // invitation can no longer be revoked, and its decline receipt is bound.
  const declineId = randomUUID();
  const declined = await f.respond(invitee, "decline", declineId);
  assert.equal(declined.inviteGeneration, 2);
  assert.equal((await f.pointer(invitee)).exists, false);
  await rejection(f.revoke(f.uid, invitee), "failed-precondition");
  assert.equal((await f.invite(f.uid, invitee)).generation, 3);
  await rejection(f.respond(invitee, "decline", declineId), "permission-denied");
  assert.equal((await f.inviteDoc(invitee)).status, "pending");
  // Generation 3 is a live invitation and is accepted normally.
  assert.equal((await f.respond(invitee, "accept")).inviteGeneration, 3);
});

emulatorTest("expiry and inviter authority: an expired invitation is re-issued as a new generation; a demoted inviter's invitation is dead on arrival and a manager re-issues it", async () => {
  const f = await fixture("company");
  const admin = await f.member("admin");
  const invitee = await user("invitee");
  await friends(admin, invitee);
  await friends(f.uid, invitee);
  const first = await f.invite(admin, invitee);
  assert.equal(first.generation, 1);
  f.advance(SERVER_INVITE_TTL_MS + 1);
  await rejection(f.respond(invitee, "accept"), "permission-denied");
  // The same inviter re-issues rather than reusing the expired one.
  const second = await f.invite(admin, invitee);
  assert.equal(second.generation, 2);
  assert.equal(second.alreadyExisted, false);
  assert.equal(second.expiresAtMillis, f.now() + SERVER_INVITE_TTL_MS);
  assert.equal((await f.pointer(invitee)).data().generation, 2);
  // Demotion: the inviter's authorization revision moves, so the consumer
  // refuses the invitation even though it is pending and unexpired.
  await f.setServerMemberRoleV1(request(f.uid, operation(f.serverId, { memberId: admin, role: "member" })));
  await rejection(f.respond(invitee, "accept"), "permission-denied");
  await rejection(f.invite(admin, invitee), "permission-denied");
  // The owner does not reuse a dead invitation; it re-issues under its own
  // authority, and that one is accepted.
  const third = await f.invite(f.uid, invitee);
  assert.equal(third.generation, 3);
  assert.equal(third.alreadyExisted, false);
  assert.equal((await f.inviteDoc(invitee)).inviterId, f.uid);
  const joined = await f.respond(invitee, "accept");
  assert.equal(joined.inviteGeneration, 3);
  assert.equal((await db.doc(`clubs/${f.serverId}/members/${invitee}`).get()).data().invitedBy, f.uid);
});
