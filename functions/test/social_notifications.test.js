const test = require("node:test");
const assert = require("node:assert/strict");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const { writeSocialNotification } = require("../notifications/social");

// Eligibility and payload rules for the server-derived social
// notifications (ADR-041). The triggers themselves are exercised
// end-to-end, through real Firestore events, in
// social_notifications.smoke.js — this file pins the decision logic.

const A = "unit-actor";
const B = "unit-recipient";

async function seedUser(uid, data = {}) {
  await db.collection("users").doc(uid).set({
    uid,
    displayName: uid === A ? "Ada" : "Bo",
    email: `${uid}@example.invalid`,
    phoneNumber: "+48000000000",
    role: "user",
    notificationPreferences: { follow: true },
    ...data,
  });
}

async function inbox(uid) {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("notifications")
    .get();
  return snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function reset() {
  for (const uid of [A, B]) {
    const notifications = await db
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .get();
    await Promise.all(notifications.docs.map((d) => d.ref.delete()));
    for (const sub of ["blocked"]) {
      const docs = await db.collection("users").doc(uid).collection(sub).get();
      await Promise.all(docs.docs.map((d) => d.ref.delete()));
    }
    await db.collection("users").doc(uid).delete();
  }
}

test("social notification generation", async (t) => {
  t.beforeEach(reset);
  t.after(reset);

  await t.test("writes one record for the recipient, with the actor's public name", async () => {
    await seedUser(A);
    await seedUser(B);

    const outcome = await writeSocialNotification({
      recipientId: B,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    assert.equal(outcome, "written");

    const got = await inbox(B);
    assert.equal(got.length, 1);
    assert.equal(got[0].id, `follow_${A}`);
    assert.equal(got[0].type, "follow");
    assert.equal(got[0].actorId, A);
    assert.equal(got[0].actorName, "Ada");
    assert.equal(got[0].isRead, false);
    assert.equal(got[0].bellSuppressed, false);
    assert.ok(got[0].createdAt, "server timestamp must be set");
  });

  await t.test("no private field of the actor leaks into the payload", async () => {
    await seedUser(A);
    await seedUser(B);
    await writeSocialNotification({
      recipientId: B,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    const [record] = await inbox(B);
    const serialised = JSON.stringify(record);
    assert.ok(!serialised.includes("example.invalid"), "email leaked");
    assert.ok(!serialised.includes("+48000000000"), "phone leaked");
    assert.ok(!("role" in record), "role leaked");
    assert.ok(!("notificationPreferences" in record), "preferences leaked");
    assert.deepEqual(Object.keys(record).sort(), [
      "actorId",
      "actorName",
      "actorPhotoUrl",
      "bellSuppressed",
      "createdAt",
      "dedupeKey",
      "id",
      "isRead",
      "targetId",
      "targetLabel",
      "type",
    ]);
  });

  await t.test("the deterministic id absorbs a replay", async () => {
    await seedUser(A);
    await seedUser(B);
    for (let i = 0; i < 3; i++) {
      await writeSocialNotification({
        recipientId: B,
        actorId: A,
        type: "friendRequest",
        entryId: `friendRequest_${A}`,
      });
    }
    assert.equal((await inbox(B)).length, 1);
  });

  await t.test("an actor is never notified about their own action", async () => {
    await seedUser(A);
    const outcome = await writeSocialNotification({
      recipientId: A,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    assert.equal(outcome, "skipped:self");
    assert.equal((await inbox(A)).length, 0);
  });

  await t.test("a banned actor generates nothing", async () => {
    await seedUser(A, { banned: true });
    await seedUser(B);
    const outcome = await writeSocialNotification({
      recipientId: B,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    assert.equal(outcome, "skipped:actor-banned");
    assert.equal((await inbox(B)).length, 0);
  });

  await t.test("a banned recipient receives nothing", async () => {
    await seedUser(A);
    await seedUser(B, { banned: true });
    const outcome = await writeSocialNotification({
      recipientId: B,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    assert.equal(outcome, "skipped:recipient-banned");
    assert.equal((await inbox(B)).length, 0);
  });

  await t.test("a block in EITHER direction suppresses it", async () => {
    for (const [blocker, blockee] of [
      [A, B],
      [B, A],
    ]) {
      await reset();
      await seedUser(A);
      await seedUser(B);
      await db.doc(`users/${blocker}/blocked/${blockee}`).set({ at: new Date() });

      const outcome = await writeSocialNotification({
        recipientId: B,
        actorId: A,
        type: "follow",
        entryId: `follow_${A}`,
      });
      assert.equal(outcome, "skipped:blocked", `${blocker} blocked ${blockee}`);
      assert.equal((await inbox(B)).length, 0);
    }
  });

  await t.test("a deleted actor or recipient fails safely, writing nothing", async () => {
    await seedUser(B);
    assert.equal(
      await writeSocialNotification({
        recipientId: B,
        actorId: "ghost-actor",
        type: "follow",
        entryId: "follow_ghost-actor",
      }),
      "skipped:no-actor",
    );

    await reset();
    await seedUser(A);
    assert.equal(
      await writeSocialNotification({
        recipientId: "ghost-recipient",
        actorId: A,
        type: "follow",
        entryId: `follow_${A}`,
      }),
      "skipped:no-recipient",
    );
  });

  await t.test("an actor with no display name gets a neutral fallback", async () => {
    await seedUser(A, { displayName: "   " });
    await seedUser(B);
    await writeSocialNotification({
      recipientId: B,
      actorId: A,
      type: "follow",
      entryId: `follow_${A}`,
    });
    const [record] = await inbox(B);
    assert.equal(record.actorName, "YO Voice user");
  });

  await t.test("all three exports are wired into functions/index.js", () => {
    const index = require("../index");
    for (const name of [
      "onFriendRequestCreated",
      "onFriendRequestResolved",
      "onFollowerCreated",
    ]) {
      assert.ok(index[name], `${name} is not exported`);
    }
  });
});
