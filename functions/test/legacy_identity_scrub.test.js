const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
if (getApps().length === 0) initializeApp();

const { scrubIdentitySnapshots } = require(
  "../scripts/scrub_legacy_identity_snapshots",
);

const db = getFirestore();
const PREFIX = "legacy-identity-scrub";

async function wipe() {
  const conversationSnapshot = await db.collection("conversations").get();
  await Promise.all([
    ...conversationSnapshot.docs
      .filter((doc) => doc.id.startsWith(`${PREFIX}-`))
      .map((doc) => db.recursiveDelete(doc.ref)),
    db.recursiveDelete(db.doc(`users/${PREFIX}-owner`)),
    db.recursiveDelete(db.doc(`users/${PREFIX}-target`)),
    ...["conversations", "friendRequests", "following", "followers"].map(
      (phase) =>
        db.doc(`privateMigrationState/legacyIdentity_${phase}`).delete(),
    ),
  ]);
}

beforeEach(wipe);
after(wipe);

function args(phase, apply) {
  return {
    phase,
    apply,
    restart: true,
    batchSize: 100,
    maxDocuments: 100,
  };
}

test("dry run is bounded, aggregate-only and performs no write", async () => {
  // scrubIdentitySnapshots scans the whole `conversations` collection — it has
  // no uid/prefix scoping — so this file cannot isolate itself the way wipe()
  // isolates its own fixtures. `node --test test/*.test.js` runs files
  // concurrently against one emulator, so any conversation another file has
  // seeded is counted here too, and asserting an absolute `scanned === 1` made
  // this test fail only on unlucky interleavings (green locally, red in CI).
  // Assert the guarantees that belong to this migration run (bounded,
  // aggregate-only and no write) without assuming exclusive ownership of the
  // shared emulator collection. Another test may legitimately create a
  // conversation between this write and the scan.
  await db.doc(`conversations/${PREFIX}-conversation`).set({
    participantEmails: {
      owner: "private-owner@example.invalid",
      target: "private-target@example.invalid",
    },
  });
  const report = await scrubIdentitySnapshots({
    db,
    args: args("conversations", false),
  });
  assert.equal(report.scanned >= 1, true);
  assert.equal(report.scanned <= 100, true);
  assert.equal(report.plannedScrubs >= 1, true);
  assert.equal(report.appliedScrubs, 0);
  assert.equal(JSON.stringify(report).includes("@example.invalid"), false);
  const stored = await db.doc(`conversations/${PREFIX}-conversation`).get();
  assert.equal(stored.data().participantEmails.owner.includes("@"), true);
});

test("apply scrubs DM, request and follow-edge snapshots exactly", async () => {
  const followedAt = Timestamp.fromMillis(1_770_000_000_000);
  await Promise.all([
    db.doc(`conversations/${PREFIX}-conversation`).set({
      participantEmails: {
        owner: "private-owner@example.invalid",
        target: "private-target@example.invalid",
      },
    }),
    db.doc(`users/${PREFIX}-owner/friendRequests/${PREFIX}-target`).set({
      senderId: `${PREFIX}-target`,
      senderName: "Target",
      senderEmail: "private-target@example.invalid",
    }),
    db.doc(`users/${PREFIX}-owner/following/${PREFIX}-target`).set({
      uid: `${PREFIX}-target`,
      followedAt,
      displayName: "Stale target",
      photoUrl: "https://stale.invalid/target.jpg",
    }),
    db.doc(`users/${PREFIX}-target/followers/${PREFIX}-owner`).set({
      uid: `${PREFIX}-owner`,
      followedAt,
      username: "stale-owner",
    }),
  ]);

  for (const phase of [
    "conversations",
    "friendRequests",
    "following",
    "followers",
  ]) {
    const report = await scrubIdentitySnapshots({
      db,
      args: args(phase, true),
    });
    assert.equal(report.conflicts, 0, phase);
    assert.equal(report.appliedScrubs, 1, phase);
  }

  const [conversation, request, following, follower] = await db.getAll(
    db.doc(`conversations/${PREFIX}-conversation`),
    db.doc(`users/${PREFIX}-owner/friendRequests/${PREFIX}-target`),
    db.doc(`users/${PREFIX}-owner/following/${PREFIX}-target`),
    db.doc(`users/${PREFIX}-target/followers/${PREFIX}-owner`),
  );
  assert.deepEqual(conversation.data().participantEmails, {
    owner: "",
    target: "",
  });
  assert.equal("senderEmail" in request.data(), false);
  assert.deepEqual(Object.keys(following.data()).sort(), ["followedAt", "uid"]);
  assert.deepEqual(Object.keys(follower.data()).sort(), ["followedAt", "uid"]);
});
