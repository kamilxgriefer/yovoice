const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

// Refuse to run against production, even when a developer has ADC enabled.
if (!/^127\.0\.0\.1:\d+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "")) {
  throw new Error("An explicit loopback FIRESTORE_EMULATOR_HOST is required.");
}
process.env.GCLOUD_PROJECT = "demo-yovoice-server-consumers";
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldPath } = require("firebase-admin/firestore");
const app = initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore(app);
const { assertLegacyRoomAccess, isVersionedServer } = require("../utils/server_access");
const { createCommunityMessagingService } = require("../messaging/community_integrity");
const { createMomentIntegrityService } = require("../moments/integrity");
const { createLiveKitTokenHandler } = require("../livekit/token");
const { createRoomCoverService } = require("../rooms/covers");
const { executeSetRoomStatus } = require("../rooms/participants");
const { executeDeleteClubSelf } = require("../clubs/deletion");
const { transferClubOwnershipSelf } = require("../clubs/ownership");
const { removeClubMemberSelf } = require("../clubs/members");
const { moderateClubMessage } = require("../clubs/message_moderation");
const { createFinalizeClubMediaHandler } = require("../clubs/creation");
const { sendClubInvite } = require("../notifications/invites");
const { derivePublicClub } = require("../marketing/public_showcase");
const { setClubModerationStatus } = require("../admin/clubs");
const { setRoomModerationStatus } = require("../admin/rooms");

const OWNER = "v1-boundary-owner";
const MEMBER = "v1-boundary-member";
const OUTSIDER = "v1-boundary-outsider";
const SERVER = "v1-boundary-server";
const ROOM = "v1-boundary-room";
const CHANNEL = "restricted-chat";
const nowMs = 1_900_000_000_000;
const deny = (error) => error.code === "permission-denied";
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const invoke = (callable, value) => (callable.run ?? callable)(value);
const messaging = () => createCommunityMessagingService({ db, Timestamp, clock: () => nowMs });
const send = (uid = MEMBER, requestId = "send-server-001") => messaging().sendClubMessage(request(uid, {
  clubId: SERVER, channelId: CHANNEL, text: "private text", requestId,
}));
const storage = new Proxy({}, { get: (_target, method) => {
  if (method === "bucketName") return "test-bucket";
  return async () => { throw new Error(`Unexpected media access: ${String(method)}`); };
} });

async function seed({ held = false } = {}) {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
  for (const uid of [OWNER, MEMBER, OUTSIDER]) {
    await db.doc(`users/${uid}`).set({ uid, displayName: uid, banned: false, disabled: false });
  }
  await db.doc(`clubs/${SERVER}`).set({
    serverSchemaVersion: 1, serverType: "company", templateVersion: 1, type: "community",
    serverActivationState: held ? "held" : "active", status: held ? "preparing" : "active",
    revision: 1, name: "Private company", privacy: "inviteOnly", ownerId: OWNER, memberCount: 2,
  });
  for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"]]) {
    await db.doc(`clubs/${SERVER}/members/${uid}`).set({ userId: uid, role, authorizationRevision: 1 });
  }
  await db.doc(`clubs/${SERVER}/channels/${CHANNEL}`).set({
    serverSchemaVersion: 1, serverId: SERVER, kind: "text", type: "chat", revision: 1,
    aclRevision: 1, status: "active", roomId: null, activeSessionId: null,
    experience: null, mediaMode: null, isPrivate: true, accessMode: "restricted",
    accessPolicy: { accessMode: "restricted", roleIds: ["owner"], userIds: [MEMBER] },
  });
  for (const uid of [OWNER, MEMBER]) {
    await db.doc(`clubs/${SERVER}/channels/${CHANNEL}/accessGrants/${uid}`).set({
      schemaVersion: 1, userId: uid, serverId: SERVER, channelId: CHANNEL,
      aclRevision: 1, membershipRevision: 1,
      capabilities: { read: true, write: true, manage: uid === OWNER, moderate: uid === OWNER,
        joinVoice: false, startSession: false },
    });
  }
  await db.doc(`rooms/${ROOM}`).set({
    serverSchemaVersion: 1, serverId: SERVER, clubId: SERVER, channelId: CHANNEL,
    hostId: OWNER, status: "active", visibility: "public", isLive: true,
    roomType: "community", experience: "community",
  });
  await db.doc(`rooms/${ROOM}/participants/${MEMBER}`).set({ userId: MEMBER, role: "speaker" });
  await db.doc(`rooms/${ROOM}/roomMembers/${MEMBER}`).set({ userId: MEMBER, role: "member" });
}

beforeEach(() => seed());
after(async () => { await db.terminate(); await deleteApp(app); });

test("unknown/null server versions never fall back to legacy authority", async () => {
  for (const value of [null, 0, 1, 2, "1"]) assert.equal(isVersionedServer({ serverSchemaVersion: value }), true);
  assert.equal(isVersionedServer({ type: "family" }), false);
  await db.doc(`rooms/${ROOM}`).set({ clubId: SERVER, hostId: OWNER, visibility: "public" });
  await assert.rejects(assertLegacyRoomAccess({ db, roomId: ROOM }), deny);
});

test("legacy named chat writer accepts exact current channel authority", async () => {
  const result = await send();
  const stored = await db.doc(`clubs/${SERVER}/channels/${CHANNEL}/messages/${result.messageId}`).get();
  assert.equal(stored.exists, true);
  await assert.rejects(send(OUTSIDER), deny);
});

for (const [name, change] of [
  ["stale ACL", { aclRevision: 2 }], ["stale membership", { membershipRevision: 2 }],
  ["cross server", { serverId: "another-server" }], ["cross channel", { channelId: "another-channel" }],
]) test(`chat replay reauthorizes ${name} grant`, async () => {
  await send();
  await db.doc(`clubs/${SERVER}/channels/${CHANNEL}/accessGrants/${MEMBER}`).update(change);
  await assert.rejects(send(), deny);
  await assert.rejects(send(MEMBER, "send-server-002"), deny);
});

test("chat replay fails after canonical membership removal", async () => {
  await send();
  await db.doc(`clubs/${SERVER}/members/${MEMBER}`).delete();
  await assert.rejects(send(), deny);
});

test("held roots reject chat including a receipt created before the hold", async () => {
  await send();
  await db.doc(`clubs/${SERVER}`).update({ status: "preparing", serverActivationState: "held" });
  await assert.rejects(send(), deny);
  await assert.rejects(send(OWNER, "send-owner-001"), deny);
});

test("unsupported module kinds cannot be used as legacy chat channels", async () => {
  await db.doc(`clubs/${SERVER}/channels/${CHANNEL}`).update({ kind: "questions" });
  await assert.rejects(send(), deny);
});

test("public/host/member legacy room writer branches reject V1", async () => {
  for (const uid of [OWNER, MEMBER, OUTSIDER]) await assert.rejects(
    messaging().sendRoomMessage(request(uid, { roomId: ROOM, requestId: `room-send-${uid}`, text: "forged" })), deny,
  );
});

test("legacy token path rejects V1 before signing, including completed pre-upgrade replay", async () => {
  let signed = 0;
  class FakeToken { addGrant() {} async toJwt() { signed++; return "legacy-test-token"; } }
  const options = { AccessTokenClass: FakeToken, clock: () => nowMs,
    apiKey: () => "test", apiSecret: () => "test", serverUrl: () => "wss://example.invalid" };
  const tokenRequest = request(MEMBER, { roomId: ROOM, requestId: "token-boundary-001" });
  await assert.rejects(createLiveKitTokenHandler(tokenRequest, options), deny);
  assert.equal(signed, 0);
  await db.doc(`rooms/${ROOM}`).set({ hostId: OWNER, status: "active", isLive: true,
    visibility: "public", experience: "community" });
  const first = await createLiveKitTokenHandler(tokenRequest, options);
  assert.equal(first.token, "legacy-test-token");
  await db.doc(`rooms/${ROOM}`).update({ serverSchemaVersion: 1, serverId: SERVER, clubId: SERVER });
  await assert.rejects(createLiveKitTokenHandler(tokenRequest, options), deny);
  assert.equal(signed, 1);
});

test("legacy room lifecycle cannot restore or tear down a V1 session", async () => {
  const control = { async endRoom() { throw new Error("Unexpected legacy RTC control"); } };
  await assert.rejects(executeSetRoomStatus(request(OWNER, { roomId: ROOM, status: "closed" }), control), deny);
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().status, "active");
});

test("legacy Club ownership/removal/deletion cannot mutate a V1 authority graph", async () => {
  await assert.rejects(executeDeleteClubSelf(request(OWNER, { clubId: SERVER })), deny);
  await assert.rejects(invoke(transferClubOwnershipSelf, request(OWNER, { clubId: SERVER, newOwnerId: MEMBER })), deny);
  await assert.rejects(invoke(removeClubMemberSelf, request(OWNER, { clubId: SERVER, memberId: MEMBER })), deny);
  assert.equal((await db.doc(`clubs/${SERVER}`).get()).data().ownerId, OWNER);
  assert.equal((await db.doc(`clubs/${SERVER}/members/${MEMBER}`).get()).exists, true);
});

test("legacy invite writer cannot publish V1 invitation snapshots", async () => {
  await assert.rejects(invoke(sendClubInvite, request(OWNER, { clubId: SERVER, inviteeId: OUTSIDER })), deny);
  assert.equal((await db.doc(`clubs/${SERVER}/invites/${OUTSIDER}`).get()).exists, false);
});

test("legacy staff restore cannot activate a held root or its room anchor", async () => {
  await db.doc(`users/${OUTSIDER}`).update({ role: "superModerator" });
  const staff = (data) => ({ auth: { uid: OUTSIDER, token: { role: "superModerator",
    auth_time: Math.floor(Date.now() / 1000) } }, data });
  await db.doc(`clubs/${SERVER}`).update({ status: "preparing", serverActivationState: "held" });
  await db.doc(`rooms/${ROOM}`).update({ status: "preparing", hostId: null, serverOwnerId: OWNER,
    visibility: "private", isLive: false });
  await assert.rejects(invoke(setClubModerationStatus, staff({ clubId: SERVER, suspended: false })), deny);
  await assert.rejects(invoke(setRoomModerationStatus, staff({ roomId: ROOM, suspended: false })), deny);
  assert.equal((await db.doc(`clubs/${SERVER}`).get()).data().status, "preparing");
  assert.equal((await db.doc(`rooms/${ROOM}`).get()).data().status, "preparing");
});

test("legacy staff restore still restores unversioned roots", async () => {
  await db.doc(`users/${OUTSIDER}`).update({ role: "superModerator" });
  const staff = (data) => ({ auth: { uid: OUTSIDER, token: { role: "superModerator",
    auth_time: Math.floor(Date.now() / 1000) } }, data });
  await db.doc("clubs/legacy-restore").set({ type: "community", status: "suspended",
    ownerId: OWNER, name: "Legacy Club", privacy: "private" });
  await db.doc("rooms/legacy-restore").set({ status: "suspended", hostId: OWNER,
    visibility: "private", isLive: false, name: "Legacy room" });
  await invoke(setClubModerationStatus, staff({ clubId: "legacy-restore", suspended: false }));
  await invoke(setRoomModerationStatus, staff({ roomId: "legacy-restore", suspended: false }));
  assert.equal((await db.doc("clubs/legacy-restore").get()).data().status, "active");
  assert.equal((await db.doc("rooms/legacy-restore").get()).data().status, "active");
});

test("legacy moderation requires an exact restricted grant even for the owner", async () => {
  const result = await send();
  await db.doc(`clubs/${SERVER}/channels/${CHANNEL}/accessGrants/${OWNER}`).delete();
  await assert.rejects(invoke(moderateClubMessage, request(OWNER, {
    clubId: SERVER, channelId: CHANNEL, messageId: result.messageId,
  })), deny);
});

test("reporting and report replay cannot be private-channel existence oracles", async () => {
  const sent = await send();
  const reports = createMomentIntegrityService({ db, FieldPath, Timestamp, storage, clock: () => nowMs });
  const data = { targetType: "clubMessage", clubId: SERVER, channelId: CHANNEL,
    messageId: sent.messageId, reason: "Harassment", requestId: "report-server-001" };
  await assert.rejects(reports.createContentReport(request(OUTSIDER, data)), deny);
  await reports.createContentReport(request(MEMBER, data));
  await db.doc(`clubs/${SERVER}/members/${MEMBER}`).delete();
  await assert.rejects(reports.createContentReport(request(MEMBER, data)), deny);
});

test("legacy artwork resolver/finalizer cannot access V1 media", async () => {
  const covers = createRoomCoverService({ db, Timestamp, storage, clock: () => nowMs });
  await assert.rejects(covers.getRoomCoverMediaAccess(request(OWNER, { roomId: ROOM })), deny);
  const finalize = createFinalizeClubMediaHandler({ firestore: db, bucket: {
    file() { throw new Error("Unexpected public artwork metadata access"); },
  } });
  await assert.rejects(finalize(request(OWNER, { clubId: SERVER,
    avatar: { path: `clubs/${OWNER}/${SERVER}/avatar`, generation: "123" }, banner: null,
  })), deny);
});

test("V1 is excluded from legacy consent-backed website showcase", () => {
  const club = { type: "community", privacy: "public", status: "active", ownerId: OWNER,
    name: "Public server", memberCount: 2, serverSchemaVersion: 1 };
  const consent = { schemaVersion: 1, clubId: SERVER, ownerId: OWNER, showOnWebsite: true,
    updatedAt: Timestamp.fromMillis(nowMs) };
  assert.equal(derivePublicClub({ clubId: SERVER, club, consent }), null);
});
