const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const { initializeApp, getApps } = require("firebase-admin/app");
const {
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const {
  sanitizedErrorCode,
  scrubRetiredSocialNotifications,
} = require("../scripts/scrub_retired_social_notifications");

const db = getFirestore();
const USER = "retired-social-scrub-recipient";
const ACTOR = "retired-social-scrub-actor";
const LEGACY_REQUEST_ACTOR = "retired-social-valid-request";
const LEGACY_FOLLOW_ACTOR = "retired-social-valid-follow";
const LEGACY_ACCEPT_ACTOR = "retired-social-valid-accept";
const UPGRADED_ACTOR = "retired-social-upgraded-request";

async function wipe() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${USER}`)),
    db.recursiveDelete(db.doc(`users/${LEGACY_REQUEST_ACTOR}`)),
    db.recursiveDelete(db.doc(`users/${LEGACY_FOLLOW_ACTOR}`)),
    db.recursiveDelete(db.doc(`users/${LEGACY_ACCEPT_ACTOR}`)),
    db.recursiveDelete(db.doc(`users/${UPGRADED_ACTOR}`)),
    db.doc("privateMigrationState/retiredSocialNotifications").delete(),
  ]);
}

beforeEach(wipe);
after(wipe);

function args(apply) {
  return {
    apply,
    restart: true,
    batchSize: 100,
    maxDocuments: 500,
  };
}

function fixtureQuery() {
  return db
    .doc(`users/${USER}`)
    .collection("notifications")
    .orderBy(FieldPath.documentId());
}

test("retired social id scrub is bounded, dry-first and idempotent", async () => {
  const notifications = db.doc(`users/${USER}`).collection("notifications");
  await Promise.all([
    notifications.doc(`friendRequest_${ACTOR}`).set({
      type: "friendRequest",
      actorId: ACTOR,
    }),
    notifications.doc(`follow_${ACTOR}`).set({
      type: "follow",
      actorId: ACTOR,
    }),
    notifications.doc(`follow_${ACTOR}_generation`).set({
      type: "follow",
      actorId: ACTOR,
    }),
    notifications.doc(`directMessage_${ACTOR}`).set({
      type: "directMessage",
      actorId: ACTOR,
    }),
    db.doc(`users/${USER}/friendRequests/${LEGACY_REQUEST_ACTOR}`).set({
      senderId: LEGACY_REQUEST_ACTOR,
    }),
    notifications.doc(`friendRequest_${LEGACY_REQUEST_ACTOR}`).set({
      type: "friendRequest",
      actorId: LEGACY_REQUEST_ACTOR,
    }),
    db.doc(`users/${USER}/followers/${LEGACY_FOLLOW_ACTOR}`).set({
      uid: LEGACY_FOLLOW_ACTOR,
      followedAt: Timestamp.fromMillis(1_770_000_000_000),
    }),
    notifications.doc(`follow_${LEGACY_FOLLOW_ACTOR}`).set({
      type: "follow",
      actorId: LEGACY_FOLLOW_ACTOR,
    }),
    db.doc(`users/${USER}/friends/${LEGACY_ACCEPT_ACTOR}`).set({
      userId: LEGACY_ACCEPT_ACTOR,
    }),
    db.doc(`users/${LEGACY_ACCEPT_ACTOR}/friends/${USER}`).set({
      userId: USER,
    }),
    notifications.doc(`friendAccepted_${LEGACY_ACCEPT_ACTOR}`).set({
      type: "friendAccepted",
      actorId: LEGACY_ACCEPT_ACTOR,
    }),
    db.doc(`users/${USER}/friendRequests/${UPGRADED_ACTOR}`).set({
      senderId: UPGRADED_ACTOR,
      notificationId: `friendRequest_${UPGRADED_ACTOR}_generation`,
    }),
    notifications.doc(`friendRequest_${UPGRADED_ACTOR}`).set({
      type: "friendRequest",
      actorId: UPGRADED_ACTOR,
    }),
  ]);

  const dry = await scrubRetiredSocialNotifications({
    db,
    args: args(false),
    queryFactory: fixtureQuery,
  });
  assert.equal(dry.plannedDeletes, 3);
  assert.equal(dry.appliedDeletes, 0);
  assert.equal((await notifications.get()).size, 8);

  const applied = await scrubRetiredSocialNotifications({
    db,
    args: args(true),
    queryFactory: fixtureQuery,
  });
  assert.equal(applied.plannedDeletes, 3);
  assert.equal(applied.appliedDeletes, 3);
  assert.equal((await notifications.doc(`friendRequest_${ACTOR}`).get()).exists, false);
  assert.equal((await notifications.doc(`follow_${ACTOR}`).get()).exists, false);
  assert.equal((await notifications.doc(`follow_${ACTOR}_generation`).get()).exists, true);
  assert.equal((await notifications.doc(`directMessage_${ACTOR}`).get()).exists, true);
  assert.equal(
    (await notifications.doc(`friendRequest_${LEGACY_REQUEST_ACTOR}`).get())
      .exists,
    true,
  );
  assert.equal(
    (await notifications.doc(`follow_${LEGACY_FOLLOW_ACTOR}`).get()).exists,
    true,
  );
  assert.equal(
    (await notifications.doc(`friendAccepted_${LEGACY_ACCEPT_ACTOR}`).get())
      .exists,
    true,
  );
  assert.equal(
    (await notifications.doc(`friendRequest_${UPGRADED_ACTOR}`).get()).exists,
    false,
  );

  const replay = await scrubRetiredSocialNotifications({
    db,
    args: args(true),
    queryFactory: fixtureQuery,
  });
  assert.equal(replay.plannedDeletes, 0);
  assert.equal(replay.appliedDeletes, 0);
});

test("a concurrent rewrite aborts the page without advancing its cursor", async () => {
  const notifications = db.doc(`users/${USER}`).collection("notifications");
  const retired = notifications.doc(`friendRequest_${ACTOR}`);
  await retired.set({
    type: "friendRequest",
    actorId: ACTOR,
    generation: "scanned",
  });

  await assert.rejects(
    scrubRetiredSocialNotifications({
      db,
      args: args(true),
      queryFactory: fixtureQuery,
      beforeCommit: async () => {
        await retired.update({generation: "rewritten"});
      },
    }),
    (error) => error.code === 9 || error.code === "failed-precondition",
  );

  const current = await retired.get();
  assert.equal(current.exists, true);
  assert.equal(current.data().generation, "rewritten");
  assert.equal(
    (await db.doc("privateMigrationState/retiredSocialNotifications").get())
      .exists,
    false,
  );
});

test("retired social scrub errors never expose resource paths", () => {
  assert.equal(sanitizedErrorCode({ code: "permission-denied" }), "permission-denied");
  assert.equal(sanitizedErrorCode({ code: 7 }), "7");
  assert.equal(
    sanitizedErrorCode({
      code: "users/private-user/notifications/private-document",
      message: "users/private-user/notifications/private-document",
    }),
    "unknown",
  );
  assert.equal(
    sanitizedErrorCode({
      message: "users/private-user/notifications/private-document",
    }),
    "unknown",
  );
});
