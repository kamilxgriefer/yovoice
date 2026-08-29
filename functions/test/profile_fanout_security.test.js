// Security regression for the profile identity fan-out. A user's private
// users/{uid}/clubs mirror is only an index; it must never be trusted to
// create canonical Club membership or redirect a write to another Club.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  onProfileIdentityChanged,
  syncTargetPage,
  syncProfileIdentity,
} = require("../profile/fanout");

const db = getFirestore();
const auth = getAuth();
const run = onProfileIdentityChanged.run ?? onProfileIdentityChanged;
const uid = "pf-security-user";
const realClubId = "pf-security-real-club";
const mirrorClubId = "pf-security-mirror-club";
const redirectedClubId = "pf-security-redirected-club";
const ownMomentId = "pf-security-own-moment";
const otherMomentId = "pf-security-other-moment";
const legacyMomentId = "pf-security-legacy-moment";
const conversationId = "pf-security-conversation";
const malformedMomentId = "pf-security-malformed-moment";

function identityEvent(before, after) {
  return {
    params: { uid },
    data: {
      before: { data: () => before },
      after: { data: () => after },
    },
  };
}

async function setCanonical(after) {
  await db.collection("users").doc(uid).set(after, { merge: true });
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
    db
      .collection("clubs")
      .doc(realClubId)
      .collection("members")
      .doc(uid)
      .delete(),
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
    db.collection("conversations").doc(conversationId).delete(),
    db.collection("voiceMoments").doc(malformedMomentId).delete(),
  ]);
}

beforeEach(async () => {
  await wipeOwn();
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }
  await auth.createUser({ uid, emailVerified: true });
});

describe("profile identity Club fan-out authorization", () => {
  test("the idempotent trigger is configured to retry transient races", () => {
    assert.equal(onProfileIdentityChanged.__endpoint.eventTrigger.retry, true);
  });

  test("a forged mirror cannot create or redirect canonical membership", async () => {
    await setCanonical({ displayName: "After", photoUrl: null });
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
      setCanonical({
        displayName: "After",
        photoUrl: "https://example.com/avatar.jpg",
      }),
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

  test("clearing a display name converges on the canonical fallback", async () => {
    await Promise.all([
      setCanonical({ displayName: null, username: null, photoUrl: null }),
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
    assert.equal(member.data().displayName, "YO Voice user");
  });

  test("identity updates reach only the author's canonical voiceMoments", async () => {
    await Promise.all([
      setCanonical({
        displayName: "After",
        photoUrl: "https://example.com/avatar.jpg",
      }),
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

  test("an out-of-order event cannot restore an obsolete chat avatar", async () => {
    await Promise.all([
      setCanonical({
        displayName: "Newest name",
        photoUrl: "https://example.com/newest.jpg",
      }),
      db
        .collection("conversations")
        .doc(conversationId)
        .set({
          participantIds: [uid, "pf-security-friend"],
          participantNames: {
            [uid]: "Old name",
            "pf-security-friend": "Friend",
          },
          participantPhotoUrls: {
            [uid]: "https://example.com/old.jpg",
            "pf-security-friend": "https://example.com/friend.jpg",
          },
        }),
    ]);

    // Simulates delivery of A -> B after users/{uid} has already reached C.
    await run(
      identityEvent(
        { displayName: "Old name", photoUrl: "https://example.com/old.jpg" },
        {
          displayName: "Intermediate name",
          photoUrl: "https://example.com/intermediate.jpg",
        },
      ),
    );

    const conversation = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    assert.equal(conversation.data().participantNames[uid], "Newest name");
    assert.equal(
      conversation.data().participantPhotoUrls[uid],
      "https://example.com/newest.jpg",
    );
    assert.equal(
      conversation.data().participantNames["pf-security-friend"],
      "Friend",
    );
    assert.equal(
      conversation.data().participantPhotoUrls["pf-security-friend"],
      "https://example.com/friend.jpg",
    );
  });

  test("removing an avatar clears the chat snapshot", async () => {
    await Promise.all([
      setCanonical({ displayName: "After", photoUrl: null }),
      db
        .collection("conversations")
        .doc(conversationId)
        .set({
          participantIds: [uid, "pf-security-friend"],
          participantNames: { [uid]: "Before" },
          participantPhotoUrls: {
            [uid]: "https://example.com/avatar.jpg",
          },
        }),
    ]);

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: "https://example.com/avatar.jpg" },
        { displayName: "After", photoUrl: null },
      ),
    );

    const conversation = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    assert.equal(conversation.data().participantPhotoUrls[uid], "");
    assert.equal(conversation.data().participantNames[uid], "After");
  });

  test("malformed owner identity is sanitized before canonical fan-out", async () => {
    const longName = "N".repeat(120);
    const unsafePhoto = `https://example.com/${"x".repeat(2050)}`;
    await Promise.all([
      setCanonical({ displayName: longName, photoUrl: unsafePhoto }),
      db
        .collection("conversations")
        .doc(conversationId)
        .set({
          participantIds: [uid, "pf-security-friend"],
          participantNames: { [uid]: "Before" },
          participantPhotoUrls: { [uid]: "https://example.com/before.jpg" },
        }),
      db.collection("voiceMoments").doc(malformedMomentId).set({
        authorId: uid,
        authorName: "Before",
        authorPhotoUrl: "https://example.com/before.jpg",
      }),
    ]);

    await run(
      identityEvent(
        { displayName: "Before", photoUrl: null },
        { displayName: longName, photoUrl: unsafePhoto },
      ),
    );

    const [conversation, moment] = await Promise.all([
      db.collection("conversations").doc(conversationId).get(),
      db.collection("voiceMoments").doc(malformedMomentId).get(),
    ]);
    assert.equal(conversation.data().participantNames[uid].length, 80);
    assert.equal(conversation.data().participantPhotoUrls[uid], "");
    assert.equal(moment.data().authorName.length, 80);
    assert.equal(moment.data().authorPhotoUrl, null);
  });

  test("retired account sources never republish private identity", async () => {
    await Promise.all([
      setCanonical({
        displayName: "Deleted person",
        photoUrl: "https://example.com/deleted.jpg",
        disabled: true,
      }),
      db
        .collection("conversations")
        .doc(conversationId)
        .set({
          participantIds: [uid, "pf-security-friend"],
          participantNames: { [uid]: "Retired" },
          participantPhotoUrls: { [uid]: "" },
        }),
    ]);

    const result = await syncProfileIdentity(uid);
    const conversation = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    assert.equal(result.sourceUnavailable, true);
    assert.equal(result.writes, 0);
    assert.equal(conversation.data().participantNames[uid], "Retired");
    assert.equal(conversation.data().participantPhotoUrls[uid], "");
  });

  test("a banned profile never republishes private identity", async () => {
    await Promise.all([
      setCanonical({ displayName: "Banned person", banned: true }),
      db.collection("conversations").doc(conversationId).set({
        participantIds: [uid, "pf-security-friend"],
        participantNames: { [uid]: "Safe snapshot" },
        participantPhotoUrls: { [uid]: "" },
      }),
    ]);

    const result = await syncProfileIdentity(uid);
    const conversation = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    assert.equal(result.sourceUnavailable, true);
    assert.equal(result.writes, 0);
    assert.equal(conversation.data().participantNames[uid], "Safe snapshot");
  });

  test("a disabled Auth account never republishes private identity", async () => {
    await Promise.all([
      setCanonical({ displayName: "Disabled in Auth" }),
      auth.updateUser(uid, { disabled: true }),
      db.collection("conversations").doc(conversationId).set({
        participantIds: [uid, "pf-security-friend"],
        participantNames: { [uid]: "Safe snapshot" },
        participantPhotoUrls: { [uid]: "" },
      }),
    ]);

    const result = await syncProfileIdentity(uid);
    assert.equal(result.sourceUnavailable, true);
    assert.equal(result.writes, 0);
  });

  test("a missing Auth account never republishes a lingering profile", async () => {
    await Promise.all([
      setCanonical({ displayName: "Deleted from Auth" }),
      db.collection("conversations").doc(conversationId).set({
        participantIds: [uid, "pf-security-friend"],
        participantNames: { [uid]: "Safe snapshot" },
        participantPhotoUrls: { [uid]: "" },
      }),
    ]);
    await auth.deleteUser(uid);

    const result = await syncProfileIdentity(uid);
    assert.equal(result.sourceUnavailable, true);
    assert.equal(result.writes, 0);
  });

  test("a stale discovery target cannot inject identity after membership changes", async () => {
    const reference = db.collection("conversations").doc(conversationId);
    await Promise.all([
      setCanonical({ displayName: "Current identity" }),
      reference.set({
        participantIds: ["other-a", "other-b"],
        participantNames: { "other-a": "A", "other-b": "B" },
        participantPhotoUrls: { "other-a": "", "other-b": "" },
      }),
    ]);

    const result = await syncTargetPage({
      userReference: db.collection("users").doc(uid),
      uid,
      targets: [{ kind: "conversation", reference }],
      apply: true,
    });
    const conversation = await reference.get();
    assert.equal(result.writes, 0);
    assert.equal(conversation.data().participantNames[uid], undefined);
    assert.equal(conversation.data().participantPhotoUrls[uid], undefined);
  });

  test("fan-out pages safely beyond one 150-target transaction", async () => {
    const count = 151;
    const references = Array.from({ length: count }, (_, index) =>
      db.collection("conversations").doc(`pf-security-page-${index}`),
    );
    await setCanonical({
      displayName: "Paged identity",
      photoUrl: "https://example.com/paged.jpg",
    });
    for (let offset = 0; offset < references.length; offset += 400) {
      const batch = db.batch();
      for (const reference of references.slice(offset, offset + 400)) {
        batch.set(reference, {
          participantIds: [uid, "pf-security-friend"],
          participantNames: { [uid]: "Before" },
          participantPhotoUrls: { [uid]: "" },
        });
      }
      await batch.commit();
    }

    try {
      const result = await syncProfileIdentity(uid);
      assert.equal(result.conversations, count);
      assert.equal(result.writes, count);
      const last = await references[count - 1].get();
      assert.equal(last.data().participantNames[uid], "Paged identity");
      assert.equal(
        last.data().participantPhotoUrls[uid],
        "https://example.com/paged.jpg",
      );
    } finally {
      for (let offset = 0; offset < references.length; offset += 400) {
        const batch = db.batch();
        for (const reference of references.slice(offset, offset + 400)) {
          batch.delete(reference);
        }
        await batch.commit();
      }
    }
  });
});
