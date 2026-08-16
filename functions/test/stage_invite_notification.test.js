const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const { executeModerateRoomParticipant } = require("../rooms/participants");

const HOST = "sin-host";
const GUEST = "sin-guest";
const ROOM = "sin-room";

const request = () => ({
  auth: { uid: HOST, token: { email_verified: true } },
  data: { roomId: ROOM, participantId: GUEST, isSpeaker: true },
});

const control = {
  async setParticipantPermissions() {},
};

async function reset() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${HOST}`)),
    db.recursiveDelete(db.doc(`users/${GUEST}`)),
    db.recursiveDelete(db.doc(`rooms/${ROOM}`)),
    db.doc(`restrictions/${HOST}`).delete(),
    db.doc(`restrictions/${GUEST}`).delete(),
  ]);
}

async function seed() {
  await Promise.all([
    db.doc(`users/${HOST}`).set({
      uid: HOST,
      displayName: "Canonical Host",
      photoUrl: "https://example.invalid/host.jpg",
    }),
    db.doc(`users/${GUEST}`).set({
      uid: GUEST,
      displayName: "Guest",
    }),
    db.doc(`rooms/${ROOM}`).set({
      hostId: HOST,
      name: "Canonical Broadcast",
      experience: "broadcast",
      status: "active",
      isLive: true,
      participantCount: 2,
    }),
    db.doc(`rooms/${ROOM}/participants/${GUEST}`).set({
      userId: GUEST,
      role: "listener",
      isSpeaker: false,
      isMuted: false,
    }),
  ]);
}

beforeEach(async () => {
  await reset();
  await seed();
});
after(reset);

test("stage promotion and canonical notification commit together once", async () => {
  await executeModerateRoomParticipant(request(), control);
  const notificationReference = db.doc(
    `users/${GUEST}/notifications/broadcastInvite_${ROOM}_${GUEST}`,
  );
  const first = await notificationReference.get();
  assert.equal(first.data().type, "broadcastInvite");
  assert.equal(first.data().actorId, HOST);
  assert.equal(first.data().actorName, "Canonical Host");
  assert.equal(first.data().targetLabel, "Canonical Broadcast");
  const firstCreatedAt = first.data().createdAt.toMillis();

  await executeModerateRoomParticipant(request(), control);
  const replay = await notificationReference.get();
  assert.equal(replay.data().createdAt.toMillis(), firstCreatedAt);
  assert.equal(
    (await db.doc(`rooms/${ROOM}/participants/${GUEST}`).get()).data().isSpeaker,
    true,
  );
});

test("block or sanction prevents both stage promotion and invite", async () => {
  await db.doc(`users/${GUEST}/blocked/${HOST}`).set({ userId: HOST });
  await assert.rejects(
    executeModerateRoomParticipant(request(), control),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(
    (await db.doc(`rooms/${ROOM}/participants/${GUEST}`).get()).data().isSpeaker,
    false,
  );

  await db.doc(`users/${GUEST}/blocked/${HOST}`).delete();
  await db.doc(`restrictions/${GUEST}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    executeModerateRoomParticipant(request(), control),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(
    (await db.doc(`users/${GUEST}/notifications/broadcastInvite_${ROOM}_${GUEST}`).get()).exists,
    false,
  );
});
