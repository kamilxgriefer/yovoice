const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const { moderateClubMessage, MINUTE_LIMIT } = require(
  "../clubs/message_moderation",
);
const { db } = require("../utils/firestore");
const { clubActionRateReferences } = require("../clubs/quota");

const run = moderateClubMessage.run ?? moderateClubMessage;
const CLUB = "moderation-club";
const CHANNEL = "general";
const OWNER = "moderation-owner";
const MODERATOR = "moderation-mod";
const MEMBER = "moderation-member";

function request(uid, messageId, { verified = true } = {}) {
  return {
    auth: {
      uid,
      token: {
        email: `${uid}@example.invalid`,
        email_verified: verified,
      },
    },
    data: { clubId: CLUB, channelId: CHANNEL, messageId },
  };
}

function quota(uid) {
  return clubActionRateReferences(db, uid, "moderateClubMessage");
}

async function remove(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function reset() {
  await Promise.all([
    remove(db.doc(`clubs/${CLUB}`)),
    ...[OWNER, MODERATOR, MEMBER, "moderation-admin", "moderation-co"]
      .map((uid) => remove(db.doc(`users/${uid}`))),
    ...[OWNER, MODERATOR, MEMBER, "moderation-admin", "moderation-co"]
      .map((uid) => db.doc(`restrictions/${uid}`).delete()),
    ...[OWNER, MODERATOR, MEMBER, "moderation-admin", "moderation-co"]
      .flatMap((uid) => {
        const references = quota(uid);
        return [references.minute.delete(), references.hour.delete()];
      }),
  ]);
  const audits = await db
    .collection("adminAuditLogs")
    .where("action", "==", "moderateClubMessage")
    .get();
  await Promise.all(audits.docs.map((document) => document.ref.delete()));
}

async function seedMember(uid, role, overrides = {}) {
  await Promise.all([
    db.doc(`users/${uid}`).set({ uid, banned: false, disabled: false }),
    db.doc(`clubs/${CLUB}/members/${uid}`).set({
      userId: uid,
      role,
      banned: false,
      ...overrides,
    }),
  ]);
}

async function seedMessage(messageId, senderId) {
  await db.doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/${messageId}`).set({
    clubId: CLUB,
    channelId: CHANNEL,
    senderId,
    senderName: senderId,
    content: "unsafe content",
    isDeleted: false,
    sentAt: Timestamp.now(),
    editedAt: null,
  });
}

beforeEach(async () => {
  await reset();
  await db.doc(`clubs/${CLUB}`).set({
    ownerId: OWNER,
    status: "active",
    deletionInProgress: false,
  });
  await db.doc(`clubs/${CLUB}/channels/${CHANNEL}`).set({
    type: "chat",
  });
  await Promise.all([
    seedMember(OWNER, "owner"),
    seedMember(MODERATOR, "moderator"),
    seedMember(MEMBER, "member"),
  ]);
});
after(reset);

test("moderator redaction is target-independently rate-limited and audited", async () => {
  await seedMessage("message-1", MEMBER);
  const result = await run(request(MODERATOR, "message-1"));
  assert.deepEqual(result, { outcome: "redacted", redacted: true });

  const message = await db
    .doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/message-1`)
    .get();
  assert.equal(message.data().content, "");
  assert.equal(message.data().isDeleted, true);
  assert.equal(message.data().deletedBy, MODERATOR);
  assert.equal(message.data().deletedByRole, "moderator");
  assert.equal(message.data().moderationRemoved, true);

  const audits = await db
    .collection("adminAuditLogs")
    .where("action", "==", "moderateClubMessage")
    .get();
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].data().details.authorId, MEMBER);
  assert.equal("content" in audits.docs[0].data().details, false);
  const minute = await quota(MODERATOR).minute.get();
  assert.equal(minute.data().count, 1);
});

test("club hierarchy protects equal and higher roles", async () => {
  await Promise.all([
    seedMember("moderation-admin", "admin"),
    seedMember("moderation-co", "coOwner"),
  ]);
  await seedMessage("admin-message", "moderation-admin");
  await seedMessage("co-message", "moderation-co");

  await assert.rejects(
    run(request(MODERATOR, "admin-message")),
    (error) => error.code === "permission-denied",
  );
  await assert.rejects(
    run(request("moderation-admin", "co-message")),
    (error) => error.code === "permission-denied",
  );
});

test("unverified, restricted and saturated moderators fail closed", async () => {
  await seedMessage("message-2", MEMBER);
  await assert.rejects(
    run(request(MODERATOR, "message-2", { verified: false })),
    (error) => error.code === "failed-precondition",
  );

  await db.doc(`restrictions/${MODERATOR}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    run(request(MODERATOR, "message-2")),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`restrictions/${MODERATOR}`).delete();

  const now = Timestamp.now();
  const saturated = quota(MODERATOR);
  await saturated.minute.set({
    schemaVersion: 1,
    ownerId: MODERATOR,
    scope: saturated.minuteScope,
    windowStartedAt: now,
    count: MINUTE_LIMIT,
    updatedAt: now,
  });
  await assert.rejects(
    run(request(MODERATOR, "message-2")),
    (error) => error.code === "resource-exhausted",
  );
  const message = await db
    .doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/message-2`)
    .get();
  assert.equal(message.data().isDeleted, false);
});

test("banned or non-canonical moderators cannot mutate moderation state", async () => {
  let deniedAttempts = 0;
  for (const [caseName, membershipPatch] of [
    ["banned", { banned: true }],
    ["identity-mismatch", { userId: "different-user" }],
  ]) {
    const messageId = `inactive-${caseName}`;
    await seedMessage(messageId, MEMBER);
    await db.doc(`clubs/${CLUB}/members/${MODERATOR}`).set(
      membershipPatch,
      { merge: true },
    );

    await assert.rejects(
      run(request(MODERATOR, messageId)),
      (error) => error.code === "permission-denied",
    );
    deniedAttempts += 1;

    const [message, rate, audits] = await Promise.all([
      db.doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/${messageId}`).get(),
      quota(MODERATOR).minute.get(),
      db.collection("adminAuditLogs")
        .where("action", "==", "moderateClubMessage")
        .get(),
    ]);
    assert.equal(message.data().content, "unsafe content");
    assert.equal(message.data().isDeleted, false);
    assert.equal(rate.data().count, deniedAttempts);
    assert.equal(audits.size, 0);

    await seedMember(MODERATOR, "moderator");
  }
});

test("unknown Club lifecycle status fails closed", async () => {
  await Promise.all([
    seedMessage("unknown-status", MEMBER),
    db.doc(`clubs/${CLUB}`).update({ status: "pending-review" }),
  ]);

  await assert.rejects(
    run(request(MODERATOR, "unknown-status")),
    (error) => error.code === "permission-denied",
  );

  const [message, rate] = await Promise.all([
    db.doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/unknown-status`).get(),
    quota(MODERATOR).minute.get(),
  ]);
  assert.equal(message.data().isDeleted, false);
  assert.equal(rate.data().count, 1);
});

test("denied targets exhaust the same committed actor budget as valid targets", async () => {
  const references = quota(MODERATOR);
  const now = Timestamp.now();
  await references.minute.set({
    schemaVersion: 1,
    ownerId: MODERATOR,
    scope: references.minuteScope,
    windowStartedAt: now,
    count: MINUTE_LIMIT - 1,
    updatedAt: now,
  });
  await db.doc(`clubs/${CLUB}`).update({ status: "pending-review" });
  await seedMessage("denied-budget", MEMBER);

  await assert.rejects(
    run(request(MODERATOR, "denied-budget")),
    (error) => error.code === "permission-denied",
  );
  assert.equal((await references.minute.get()).data().count, MINUTE_LIMIT);

  await db.doc(`clubs/${CLUB}`).update({ status: "active" });
  await seedMessage("would-be-valid", MEMBER);
  await assert.rejects(
    run(request(MODERATOR, "would-be-valid")),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(
    (
      await db
        .doc(`clubs/${CLUB}/channels/${CHANNEL}/messages/would-be-valid`)
        .get()
    ).data().isDeleted,
    false,
  );
});
