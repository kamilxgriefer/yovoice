// Security regression for the profile identity fan-out. A user's private
// users/{uid}/clubs mirror is only an index; it must never be trusted to
// create canonical Club membership or redirect a write to another Club.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { onProfileIdentityChanged } = require("../profile/fanout");

const db = getFirestore();
const run = onProfileIdentityChanged.run ?? onProfileIdentityChanged;
const uid = "pf-security-user";
const realClubId = "pf-security-real-club";
const mirrorClubId = "pf-security-mirror-club";
const redirectedClubId = "pf-security-redirected-club";
const ownMomentId = "pf-security-own-moment";
const otherMomentId = "pf-security-other-moment";
const legacyMomentId = "pf-security-legacy-moment";

function identityEvent(before, after) {
  return {
    params: { uid },
    data: {
      before: { data: () => before },
      after: { data: () => after },
    },
  };
}

async function wipeOwn() {
  await Promise.all([
    db.collection("users").doc(uid).delete(),
    db
      .collection("users")
      .doc(uid)
      .collection("clubs")
      .doc(realClubId)
      .delete(),
    db
      .collection("users")
      .doc(uid)
      .collection("clubs")
      .doc(mirrorClubId)
      .delete(),
    db.collection("clubs").doc(realClubId).collection("members").doc(uid).delete(),
    db
      .collection("clubs")
      .doc(mirrorClubId)
      .collection("members")
      .doc(uid)
      .delete(),
    db
      .collection("clubs")
      .doc(redirectedClubId)
      .collection("members")
      .doc(uid)
      .delete(),
    db.collection("voiceMoments").doc(ownMomentId).delete(),
    db.collection("voiceMoments").doc(otherMomentId).delete(),
    db.collection("voice_moments").doc(legacyMomentId).delete(),
  ]);
}

beforeEach(wipeOwn);

describe("profile identity Club fan-out authorization", () => {
  test("the idempotent trigger is configured to retry transient races", () => {
    assert.equal(onProfileIdentityChanged.__endpoint.eventTrigger.retry, true);
  });

  test("a forged mirror cannot create or redirect canonical membership", async () => {
    await db
      .collection("users")
      .doc(uid)
      .collection("clubs")
      .doc(mirrorClubId)
      .set({ clubId: redirectedClubId, role: "owner" });

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: null },
        { displayName: "After", photoUrl: null },
      ),
    );

    const [mirrorTarget, redirectedTarget] = await Promise.all([
      db
        .collection("clubs")
        .doc(mirrorClubId)
        .collection("members")
        .doc(uid)
        .get(),
      db
        .collection("clubs")
        .doc(redirectedClubId)
        .collection("members")
        .doc(uid)
        .get(),
    ]);
    assert.equal(mirrorTarget.exists, false);
    assert.equal(redirectedTarget.exists, false);
  });

  test("a real membership still receives identity updates", async () => {
    await Promise.all([
      db
        .collection("users")
        .doc(uid)
        .collection("clubs")
        .doc(realClubId)
        .set({ clubId: realClubId, role: "member" }),
      db
        .collection("clubs")
        .doc(realClubId)
        .collection("members")
        .doc(uid)
        .set({ userId: uid, displayName: "Before", photoUrl: null }),
    ]);

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: null },
        { displayName: "After", photoUrl: "https://example.com/avatar.jpg" },
      ),
    );

    const member = await db
      .collection("clubs")
      .doc(realClubId)
      .collection("members")
      .doc(uid)
      .get();
    assert.equal(member.data().displayName, "After");
    assert.equal(member.data().photoUrl, "https://example.com/avatar.jpg");
  });

  test("clearing an optional display name never enqueues an empty update", async () => {
    await Promise.all([
      db
        .collection("users")
        .doc(uid)
        .collection("clubs")
        .doc(realClubId)
        .set({ clubId: realClubId, role: "member" }),
      db
        .collection("clubs")
        .doc(realClubId)
        .collection("members")
        .doc(uid)
        .set({ userId: uid, displayName: "Before", photoUrl: null }),
    ]);

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: null },
        { displayName: null, photoUrl: null },
      ),
    );

    const member = await db
      .collection("clubs")
      .doc(realClubId)
      .collection("members")
      .doc(uid)
      .get();
    assert.equal(member.data().displayName, "Before");
  });

  test("identity updates reach only the author's canonical voiceMoments", async () => {
    await Promise.all([
      db.collection("voiceMoments").doc(ownMomentId).set({
        authorId: uid,
        authorName: "Before",
        authorPhotoUrl: null,
      }),
      db.collection("voiceMoments").doc(otherMomentId).set({
        authorId: "pf-security-other-user",
        authorName: "Other",
        authorPhotoUrl: null,
      }),
      // Storage paths use voice_moments, but this legacy-shaped Firestore
      // collection is not part of the application data model.
      db.collection("voice_moments").doc(legacyMomentId).set({
        authorId: uid,
        authorName: "Legacy",
        authorPhotoUrl: null,
      }),
    ]);

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: null },
        {
          displayName: "After",
          photoUrl: "https://example.com/avatar.jpg",
        },
      ),
    );

    const [ownMoment, otherMoment, legacyMoment] = await Promise.all([
      db.collection("voiceMoments").doc(ownMomentId).get(),
      db.collection("voiceMoments").doc(otherMomentId).get(),
      db.collection("voice_moments").doc(legacyMomentId).get(),
    ]);
    assert.equal(ownMoment.data().authorName, "After");
    assert.equal(
      ownMoment.data().authorPhotoUrl,
      "https://example.com/avatar.jpg",
    );
    assert.equal(otherMoment.data().authorName, "Other");
    assert.equal(otherMoment.data().authorPhotoUrl, null);
    assert.equal(legacyMoment.data().authorName, "Legacy");
    assert.equal(legacyMoment.data().authorPhotoUrl, null);
  });
});
