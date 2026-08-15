const test = require("node:test");
const assert = require("node:assert/strict");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const { writeActivityNotification } = require("../notifications/activity");

const ACTOR = "activity-actor";
const RECIPIENT = "activity-recipient";

async function reset() {
  for (const uid of [ACTOR, RECIPIENT]) {
    const user = db.doc(`users/${uid}`);
    for (const collection of ["notifications", "blocked"]) {
      const snapshot = await user.collection(collection).get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }
    await user.delete();
  }
}

async function seed() {
  await db.doc(`users/${ACTOR}`).set({ displayName: "Ada", photoUrl: "photo" });
  await db.doc(`users/${RECIPIENT}`).set({ displayName: "Bo" });
}

test("server-derived activity notifications", async (t) => {
  t.beforeEach(async () => {
    await reset();
    await seed();
  });
  t.after(reset);

  await t.test("writes a routable live notification with a safe payload", async () => {
    const outcome = await writeActivityNotification({
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "liveStarted",
      entryId: "live_room_1_session_1",
      targetId: "room-1",
      targetLabel: "Friday show",
    });
    assert.equal(outcome, "written");
    const record = (await db.doc(
      `users/${RECIPIENT}/notifications/live_room_1_session_1`,
    ).get()).data();
    assert.equal(record.type, "liveStarted");
    assert.equal(record.actorName, "Ada");
    assert.equal(record.targetId, "room-1");
    assert.equal(record.targetLabel, "Friday show");
    assert.equal(record.bellSuppressed, false);
    assert.ok(record.createdAt);
  });

  await t.test("a retry overwrites its deterministic record", async () => {
    const input = {
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "directMessage",
      entryId: "message-1",
      targetId: "conversation-1",
      bellSuppressed: true,
    };
    await writeActivityNotification(input);
    await writeActivityNotification(input);
    const inbox = await db.collection(`users/${RECIPIENT}/notifications`).get();
    assert.equal(inbox.size, 1);
    assert.equal(inbox.docs[0].data().bellSuppressed, true);
  });

  await t.test("a block in either direction suppresses delivery", async () => {
    await db.doc(`users/${RECIPIENT}/blocked/${ACTOR}`).set({ blocked: true });
    const outcome = await writeActivityNotification({
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "directMessage",
      entryId: "blocked-message",
      targetId: "conversation-1",
    });
    assert.equal(outcome, "skipped:blocked");
    assert.equal(
      (await db.collection(`users/${RECIPIENT}/notifications`).get()).size,
      0,
    );
  });

  await t.test("both activity triggers are part of the deploy export", () => {
    const deployed = require("../index");
    assert.equal(typeof deployed.onDirectMessageCreated, "function");
    assert.equal(typeof deployed.onRoomLiveChanged, "function");
  });
});
