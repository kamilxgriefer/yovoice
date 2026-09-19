/**
 * The push boundary's two refusals (review round, 2026-09-20).
 *
 * `notificationSourceIsCurrent` denies by default, which is right, but the
 * boundary used to treat both of its "false" answers identically and DELETE
 * the recipient's bell row:
 *
 *   - "the source is gone" — the friendship was withdrawn, the comment was
 *     removed, the event was cancelled. Deleting the row is correct, and the
 *     first test below proves that path is untouched;
 *   - "nobody registered a validator for this type" — an engineering gap.
 *     Destroying somebody's notification because of it is the wrong failure
 *     mode; the second test proves the row now survives.
 *
 * Every shipped type currently has both a push title and a validator
 * (`engagement_push_contract.test.js` pins that containment), so the second
 * situation cannot be produced with real data. The registry predicate is
 * therefore injected, exactly as `messaging` already is, while the refusal
 * itself stays real: the `follow` row below has no follower edge behind it.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const { handleNotificationCreated } = require("../notifications/push");

const emulatorTest = (name, fn) => test(
  `Push boundary: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

const neverSends = {
  sendEachForMulticast: async () => {
    throw new Error("a refused notification must never reach FCM");
  },
};

/** A row whose `follow` edge does not exist, so the real validator says no. */
async function staleFollowRow() {
  const recipient = `push-boundary-recipient-${randomUUID()}`;
  const actor = `push-boundary-actor-${randomUUID()}`;
  const notificationId = `follow_${actor}`;
  const reference = db.doc(
    `users/${recipient}/notifications/${notificationId}`,
  );
  await db.doc(`users/${recipient}`).set({ displayName: "Recipient" });
  await reference.set({
    type: "follow",
    actorId: actor,
    actorName: "Ada",
    targetId: actor,
    isRead: false,
  });
  return {
    actor,
    notificationId,
    recipient,
    reference,
    event: {
      id: `push-boundary-${randomUUID()}`,
      params: { userId: recipient, notificationId },
      data: await reference.get(),
    },
  };
}

emulatorTest("a genuinely stale source is still cleaned up", async () => {
  const row = await staleFollowRow();
  await handleNotificationCreated(row.event, { messaging: neverSends });
  assert.equal((await row.reference.get()).exists, false);
});

emulatorTest("an unregistered type is skipped, and its row survives",
  async () => {
    const row = await staleFollowRow();
    await handleNotificationCreated(row.event, {
      messaging: neverSends,
      // "Nobody added a validator for this type."
      isRegisteredType: () => false,
    });
    const current = await row.reference.get();
    assert.equal(
      current.exists,
      true,
      "an unregistered type must not destroy the recipient's bell row",
    );
    assert.equal(current.data().type, "follow");
    assert.equal(current.data().pushDeliveryStatus, "skipped");
    assert.equal(current.data().pushSkipReason, "unregistered-type");
  });
