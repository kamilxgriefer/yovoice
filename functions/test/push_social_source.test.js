const assert = require("node:assert/strict");
const { test, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const {
  isLegacySocialNotificationId,
  socialNotificationSourceIsCurrent,
} = require("../notifications/push");

const RECIPIENT = "push-source-recipient";
const ACTOR = "push-source-actor";

async function cleanup() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${RECIPIENT}`)),
    db.recursiveDelete(db.doc(`users/${ACTOR}`)),
  ]);
}

after(cleanup);

test("rollout guard identifies only the retired deterministic social ids", () => {
  assert.equal(
    isLegacySocialNotificationId("friendRequest_actor", {
      type: "friendRequest",
      actorId: "actor",
    }),
    true,
  );
  assert.equal(
    isLegacySocialNotificationId("friendRequest_actor_generation", {
      type: "friendRequest",
      actorId: "actor",
    }),
    false,
  );
  assert.equal(
    isLegacySocialNotificationId("directMessage_actor", {
      type: "directMessage",
      actorId: "actor",
    }),
    false,
  );
});

test("non-social notifications never require a relationship actor", async () => {
  const neverReadFirestore = {
    doc: () => {
      throw new Error("non-social notifications must not read social state");
    },
  };
  for (const type of ["system", "moderation", "directMessage"]) {
    assert.equal(
      await socialNotificationSourceIsCurrent({
        recipientId: RECIPIENT,
        notificationId: `${type}_event`,
        notification: {type},
        firestore: neverReadFirestore,
      }),
      true,
      type,
    );
  }
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: "friendRequest_missing-actor",
      notification: {type: "friendRequest"},
      firestore: neverReadFirestore,
    }),
    false,
  );
});

test("social push guard requires the live canonical relationship source", async () => {
  await cleanup();

  const request = { type: "friendRequest", actorId: ACTOR };
  const requestNotificationId = `friendRequest_${ACTOR}_generation`;
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: requestNotificationId,
      notification: request,
    }),
    false,
  );
  await db.doc(`users/${RECIPIENT}/friendRequests/${ACTOR}`).set({
    senderId: ACTOR,
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendRequest_${ACTOR}`,
      notification: request,
    }),
    true,
    "a genuine pre-cutover request keeps one alert during staged rollout",
  );
  await db.doc(`users/${RECIPIENT}/friendRequests/${ACTOR}`).update({
    notificationId: requestNotificationId,
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendRequest_${ACTOR}`,
      notification: request,
    }),
    false,
    "a generation-bound request suppresses the old trigger's duplicate",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendRequest_${ACTOR}_older`,
      notification: request,
    }),
    false,
    "a delayed request generation must not borrow a newer request edge",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: requestNotificationId,
      notification: request,
    }),
    true,
  );
  await db.doc(`users/${RECIPIENT}/friendRequests/${ACTOR}`).delete();

  const accepted = { type: "friendAccepted", actorId: ACTOR };
  const acceptedNotificationId = `friendAccepted_${ACTOR}_generation`;
  await db.doc(`users/${RECIPIENT}/friends/${ACTOR}`).set({
    userId: ACTOR,
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: acceptedNotificationId,
      notification: accepted,
    }),
    false,
    "one-sided friendship mirrors must not authorize a push",
  );
  await db.doc(`users/${ACTOR}/friends/${RECIPIENT}`).set({
    userId: RECIPIENT,
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendAccepted_${ACTOR}`,
      notification: accepted,
    }),
    true,
    "a genuine pre-cutover friendship keeps its legacy acceptance alert",
  );
  await Promise.all([
    db.doc(`users/${RECIPIENT}/friends/${ACTOR}`).update({
      acceptanceNotificationId: acceptedNotificationId,
      acceptanceRecipientId: RECIPIENT,
    }),
    db.doc(`users/${ACTOR}/friends/${RECIPIENT}`).update({
      acceptanceNotificationId: acceptedNotificationId,
      acceptanceRecipientId: RECIPIENT,
    }),
  ]);
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendAccepted_${ACTOR}`,
      notification: accepted,
    }),
    false,
    "generation-bound friendship mirrors suppress the old duplicate",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `friendAccepted_${ACTOR}_older`,
      notification: accepted,
    }),
    false,
    "a delayed acceptance generation must not borrow a newer friendship",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: acceptedNotificationId,
      notification: accepted,
    }),
    true,
  );

  const follow = { type: "follow", actorId: ACTOR };
  const followNotificationId = `follow_${ACTOR}_generation`;
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: followNotificationId,
      notification: follow,
    }),
    false,
  );
  await db.doc(`users/${RECIPIENT}/followers/${ACTOR}`).set({
    uid: ACTOR,
    followedAt: Timestamp.fromMillis(1_770_000_000_000),
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `follow_${ACTOR}`,
      notification: follow,
    }),
    true,
    "a genuine pre-cutover follow keeps its legacy alert",
  );
  await db.doc(`users/${RECIPIENT}/followers/${ACTOR}`).update({
    notificationId: followNotificationId,
  });
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `follow_${ACTOR}`,
      notification: follow,
    }),
    false,
    "a generation-bound follow suppresses the old trigger's duplicate",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: `follow_${ACTOR}_older`,
      notification: follow,
    }),
    false,
    "a delayed previous generation must not borrow the current edge",
  );
  assert.equal(
    await socialNotificationSourceIsCurrent({
      recipientId: RECIPIENT,
      notificationId: followNotificationId,
      notification: follow,
    }),
    true,
  );
});
