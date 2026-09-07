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
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  onProfileIdentityChanged,
  syncTargetPage,
  syncProfileIdentity,
} = require("../profile/fanout");
const { canonicalPairKey } = require("../messaging/direct_integrity");

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
const friendUid = "pf-security-friend";
const fixedTimestamp = Timestamp.fromMillis(1_725_000_000_000);

function codeUnitPair(firstUid, secondUid) {
  return [firstUid, secondUid].sort((left, right) =>
    left < right ? -1 : left > right ? 1 : 0);
}

function ownValue(values, key, fallback) {
  return Object.prototype.hasOwnProperty.call(values, key)
    ? values[key]
    : fallback;
}

function canonicalConversationData({
  participants = codeUnitPair(uid, friendUid),
  names = {},
  photos = {},
  overrides = {},
} = {}) {
  const pairKey = canonicalPairKey(...participants);
  const participantNames = Object.fromEntries(participants.map((participantId) => [
    participantId,
    ownValue(
      names,
      participantId,
      participantId === uid ? "Before" : "Friend",
    ),
  ]));
  const participantPhotoUrls = Object.fromEntries(
    participants.map((participantId) => [
      participantId,
      ownValue(photos, participantId, ""),
    ]),
  );
  return {
    schemaVersion: 2,
    pairKey,
    participantIds: participants,
    participantNames,
    participantEmails: Object.fromEntries(
      participants.map((participantId) => [participantId, ""]),
    ),
    participantPhotoUrls,
    unreadCounts: Object.fromEntries(
      participants.map((participantId) => [participantId, 0]),
    ),
    readSequences: Object.fromEntries(
      participants.map((participantId) => [participantId, 0]),
    ),
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "",
    lastMessageId: null,
    lastMessageSequence: 0,
    lastMessageType: "text",
    lastMessageSenderId: "",
    createdAt: fixedTimestamp,
    updatedAt: fixedTimestamp,
    ...overrides,
  };
}

function canonicalPairGuardData({
  conversationId: guardedConversationId = conversationId,
  participants = codeUnitPair(uid, friendUid),
  overrides = {},
} = {}) {
  const pairKey = canonicalPairKey(...participants);
  return {
    schemaVersion: 1,
    pairKey,
    conversationId: guardedConversationId,
    participantIds: participants,
    createdAt: fixedTimestamp,
    ...overrides,
  };
}

async function setCanonicalConversation({
  reference = db.collection("conversations").doc(conversationId),
  participants = codeUnitPair(uid, friendUid),
  names = {},
  photos = {},
  rootOverrides = {},
  guard = true,
  guardOverrides = {},
} = {}) {
  const pairKey = canonicalPairKey(...participants);
  const operations = [reference.set(canonicalConversationData({
    participants,
    names,
    photos,
    overrides: rootOverrides,
  }))];
  if (guard) {
    operations.push(
      db.collection("directConversationPairs").doc(pairKey).set(
        canonicalPairGuardData({
          conversationId: reference.id,
          participants,
          overrides: guardOverrides,
        }),
      ),
    );
  }
  await Promise.all(operations);
  return { pairKey, reference };
}

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
  const pairKey = canonicalPairKey(...codeUnitPair(uid, friendUid));
  await Promise.all([
    db.collection("users").doc(uid).delete(),
    db.collection("users").doc(friendUid).delete(),
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
    db.collection("directConversationPairs").doc(pairKey).delete(),
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

  test("a real membership receives identity updates without a bearer URL", async () => {
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
    assert.equal(member.data().photoUrl, null);
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
      null,
    );
    assert.equal(otherMoment.data().authorName, "Other");
    assert.equal(otherMoment.data().authorPhotoUrl, null);
    assert.equal(legacyMoment.data().authorName, "Legacy");
    assert.equal(legacyMoment.data().authorPhotoUrl, null);
  });

  test("an out-of-order event cannot restore any bearer chat avatar", async () => {
    await Promise.all([
      setCanonical({
        displayName: "Newest name",
        photoUrl: "https://example.com/newest.jpg",
      }),
      setCanonicalConversation({
        names: { [uid]: "Old name", [friendUid]: "Friend" },
        photos: {
          [uid]: "https://example.com/old.jpg",
          [friendUid]: "https://example.com/friend.jpg",
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
      "",
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

  test("fan-out removes legacy FieldPath poison and is idempotent", async () => {
    const reference = db.collection("conversations").doc(conversationId);
    const poisonKey = `\`${uid}\``;
    await Promise.all([
      setCanonical({
        displayName: "Canonical name",
        photoUrl: "https://example.com/canonical.jpg",
      }),
      setCanonicalConversation({
        reference,
        names: { [uid]: "Canonical name", [friendUid]: "Friend" },
        photos: Object.fromEntries([
          [uid, "https://example.com/canonical.jpg"],
          [friendUid, "https://example.com/friend.jpg"],
        ]),
        rootOverrides: {
          participantPhotoUrls: Object.fromEntries([
            [uid, "https://example.com/canonical.jpg"],
            [friendUid, "https://example.com/friend.jpg"],
            [poisonKey, "https://example.com/poison.jpg"],
          ]),
        },
      }),
    ]);

    const target = { kind: "conversation", reference };
    const dryRun = await syncTargetPage({
      userReference: db.collection("users").doc(uid),
      uid,
      targets: [target],
      apply: false,
    });
    assert.equal(dryRun.writes, 1);
    assert.equal(
      (await reference.get()).data().participantPhotoUrls[poisonKey],
      "https://example.com/poison.jpg",
    );

    const applied = await syncTargetPage({
      userReference: db.collection("users").doc(uid),
      uid,
      targets: [target],
      apply: true,
    });
    assert.equal(applied.writes, 1);
    const repaired = (await reference.get()).data();
    assert.deepEqual(Object.keys(repaired.participantNames).sort(), [
      friendUid,
      uid,
    ].sort());
    assert.deepEqual(Object.keys(repaired.participantPhotoUrls).sort(), [
      friendUid,
      uid,
    ].sort());
    assert.equal(
      repaired.participantPhotoUrls[uid],
      "",
    );
    assert.equal(
      repaired.participantPhotoUrls[friendUid],
      "https://example.com/friend.jpg",
    );
    assert.equal(repaired.participantNames[friendUid], "Friend");

    const idempotent = await syncTargetPage({
      userReference: db.collection("users").doc(uid),
      uid,
      targets: [target],
      apply: true,
    });
    assert.equal(idempotent.writes, 0);
  });

  const rejectedConversationCases = [
    {
      label: "a schema-v1 conversation",
      rootOverrides: { schemaVersion: 1 },
    },
    {
      label: "non-canonically ordered participant ids",
      rootOverrides: { participantIds: [uid, friendUid] },
    },
    {
      label: "a mismatched root pair key",
      rootOverrides: { pairKey: "not-the-canonical-pair-key" },
    },
    {
      label: "an unexpected outer root field",
      rootOverrides: { legacyIdentityRepair: true },
    },
    {
      label: "a missing exact pair guard",
      guard: false,
    },
    {
      label: "a conflicting exact pair guard",
      guardOverrides: { conversationId: "different-conversation" },
    },
  ];

  for (const scenario of rejectedConversationCases) {
    test(`fan-out refuses to clean ${scenario.label}`, async () => {
      const reference = db.collection("conversations").doc(conversationId);
      const poisonKey = `\`${uid}\``;
      await Promise.all([
        setCanonical({
          displayName: "Canonical name",
          photoUrl: "https://example.com/canonical.jpg",
        }),
        setCanonicalConversation({
          reference,
          rootOverrides: {
            participantPhotoUrls: Object.fromEntries([
              [uid, "https://example.com/canonical.jpg"],
              [friendUid, "https://example.com/friend.jpg"],
              [poisonKey, "https://example.com/poison.jpg"],
            ]),
            ...(scenario.rootOverrides ?? {}),
          },
          guard: scenario.guard ?? true,
          guardOverrides: scenario.guardOverrides ?? {},
        }),
      ]);

      const result = await syncTargetPage({
        userReference: db.collection("users").doc(uid),
        uid,
        targets: [{ kind: "conversation", reference }],
        apply: true,
      });
      const after = (await reference.get()).data();
      assert.equal(result.writes, 0);
      assert.equal(
        after.participantPhotoUrls[poisonKey],
        "https://example.com/poison.jpg",
      );
    });
  }

  test("a reserved __proto__ participant uid fails closed", async () => {
    const protoUid = "__proto__";
    const constructorUid = "constructor";
    const participants = codeUnitPair(protoUid, constructorUid);
    const reference = db
      .collection("conversations")
      .doc("pf-security-opaque-uids");
    const guardReference = db
      .collection("directConversationPairs")
      .doc(canonicalPairKey(...participants));
    const constructorReference = db.collection("users").doc(constructorUid);
    try {
      await Promise.all([
        constructorReference.set({
          displayName: "Constructor after",
          photoUrl: "https://example.com/constructor-after.jpg",
        }),
        setCanonicalConversation({
          reference,
          participants,
          names: Object.fromEntries([
            [protoUid, "Proto before"],
            [constructorUid, "Constructor before"],
          ]),
          photos: Object.fromEntries([
            [protoUid, "https://example.com/proto-before.jpg"],
            [constructorUid, "https://example.com/constructor-before.jpg"],
          ]),
          rootOverrides: {
            participantNames: Object.fromEntries([
              [protoUid, "Proto before"],
              [constructorUid, "Constructor before"],
              ["`__proto__`", "Poison"],
            ]),
            participantPhotoUrls: Object.fromEntries([
              [protoUid, "https://example.com/proto-before.jpg"],
              [constructorUid, "https://example.com/constructor-before.jpg"],
              ["`__proto__`", "https://example.com/poison.jpg"],
            ]),
          },
        }),
      ]);

      const result = await syncTargetPage({
        userReference: constructorReference,
        uid: constructorUid,
        targets: [{ kind: "conversation", reference }],
        apply: true,
      });

      // Firestore reserves __.*__ document ids and its Admin deserializer
      // cannot expose a stored __proto__ map field as an own enumerable key.
      // The fan-out must therefore refuse the root rather than erase or
      // reinterpret the peer identity while attempting a cleanup.
      const snapshot = await reference.get();
      const unchanged = snapshot.data();
      assert.equal(result.writes, 0);
      assert.equal(
        unchanged.participantNames[constructorUid],
        "Constructor before",
      );
      assert.equal(
        unchanged.participantNames["`__proto__`"],
        "Poison",
      );
    } finally {
      await Promise.all([
        constructorReference.delete(),
        reference.delete(),
        guardReference.delete(),
      ]);
    }
  });

  test("an opaque constructor uid remains an own canonical map key", async () => {
    const constructorUid = "constructor";
    const peerUid = "opaque-peer";
    const participants = codeUnitPair(constructorUid, peerUid);
    const reference = db
      .collection("conversations")
      .doc("pf-security-constructor-uid");
    const guardReference = db
      .collection("directConversationPairs")
      .doc(canonicalPairKey(...participants));
    const constructorReference = db.collection("users").doc(constructorUid);
    try {
      await Promise.all([
        constructorReference.set({
          displayName: "Constructor after",
          photoUrl: "https://example.com/constructor-after.jpg",
        }),
        setCanonicalConversation({
          reference,
          participants,
          names: Object.fromEntries([
            [constructorUid, "Constructor before"],
            [peerUid, "Peer"],
          ]),
          photos: Object.fromEntries([
            [constructorUid, "https://example.com/constructor-before.jpg"],
            [peerUid, "https://example.com/peer.jpg"],
          ]),
          rootOverrides: {
            participantNames: Object.fromEntries([
              [constructorUid, "Constructor before"],
              [peerUid, "Peer"],
              ["stale", "Poison"],
            ]),
            participantPhotoUrls: Object.fromEntries([
              [constructorUid, "https://example.com/constructor-before.jpg"],
              [peerUid, "https://example.com/peer.jpg"],
              ["stale", "https://example.com/poison.jpg"],
            ]),
          },
        }),
      ]);

      const result = await syncTargetPage({
        userReference: constructorReference,
        uid: constructorUid,
        targets: [{ kind: "conversation", reference }],
        apply: true,
      });
      const repaired = (await reference.get()).data();
      assert.equal(result.writes, 1);
      assert.deepEqual(
        Object.keys(repaired.participantNames).sort(),
        [...participants].sort(),
      );
      assert.deepEqual(
        Object.keys(repaired.participantPhotoUrls).sort(),
        [...participants].sort(),
      );
      assert.equal(repaired.participantNames[peerUid], "Peer");
      assert.equal(
        repaired.participantNames[constructorUid],
        "Constructor after",
      );
      assert.equal(
        repaired.participantPhotoUrls[constructorUid],
        "",
      );
      assert.equal(
        Object.prototype.hasOwnProperty.call(
          repaired.participantNames,
          constructorUid,
        ),
        true,
      );
    } finally {
      await Promise.all([
        constructorReference.delete(),
        reference.delete(),
        guardReference.delete(),
      ]);
    }
  });

  test("concurrent identity fan-outs preserve both participants", async () => {
    const reference = db.collection("conversations").doc(conversationId);
    await Promise.all([
      setCanonical({
        displayName: "Owner after",
        photoUrl: "https://example.com/owner-after.jpg",
      }),
      db.collection("users").doc(friendUid).set({
        displayName: "Friend after",
        photoUrl: "https://example.com/friend-after.jpg",
      }),
      setCanonicalConversation({
        reference,
        rootOverrides: {
          participantNames: {
            [uid]: "Owner before",
            [friendUid]: "Friend before",
            stale: "Poison",
          },
          participantPhotoUrls: {
            [uid]: "https://example.com/owner-before.jpg",
            [friendUid]: "https://example.com/friend-before.jpg",
            stale: "https://example.com/poison.jpg",
          },
        },
      }),
    ]);

    const target = { kind: "conversation", reference };
    await Promise.all([
      syncTargetPage({
        userReference: db.collection("users").doc(uid),
        uid,
        targets: [target],
        apply: true,
      }),
      syncTargetPage({
        userReference: db.collection("users").doc(friendUid),
        uid: friendUid,
        targets: [target],
        apply: true,
      }),
    ]);

    const repaired = (await reference.get()).data();
    assert.deepEqual(Object.keys(repaired.participantNames).sort(), [
      friendUid,
      uid,
    ].sort());
    assert.deepEqual(Object.keys(repaired.participantPhotoUrls).sort(), [
      friendUid,
      uid,
    ].sort());
    assert.equal(repaired.participantNames[uid], "Owner after");
    assert.equal(repaired.participantNames[friendUid], "Friend after");
    assert.equal(
      repaired.participantPhotoUrls[uid],
      "",
    );
    assert.equal(
      repaired.participantPhotoUrls[friendUid],
      "",
    );
  });

  test("removing an avatar clears the chat snapshot", async () => {
    await Promise.all([
      setCanonical({ displayName: "After", photoUrl: null }),
      setCanonicalConversation({
        photos: {
          [uid]: "https://example.com/avatar.jpg",
          [friendUid]: "https://example.com/friend.jpg",
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
      setCanonicalConversation({
        photos: {
          [uid]: "https://example.com/before.jpg",
          [friendUid]: "https://example.com/friend.jpg",
        },
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

  test("a conversation someone deleted for themselves still receives identity updates", async () => {
    // `deletedBy`/`deletedSequences` are optional keys on the root. A fan-out
    // that treated them as unknown would judge the whole root non-canonical
    // and SKIP it — leaving a stale display name and avatar in that thread
    // forever, for the participant who never deleted anything.
    await Promise.all([
      setCanonical({
        displayName: "Renamed after a delete",
        photoUrl: "https://example.com/renamed.jpg",
      }),
      setCanonicalConversation({
        names: { [uid]: "Old name", [friendUid]: "Friend" },
        photos: {
          [uid]: "https://example.com/old.jpg",
          [friendUid]: "https://example.com/friend.jpg",
        },
        rootOverrides: {
          deletedBy: [friendUid],
          deletedSequences: { [uid]: 0, [friendUid]: 0 },
        },
      }),
    ]);

    await run(
      identityEvent(
        { displayName: "Old name", photoUrl: "https://example.com/old.jpg" },
        {
          displayName: "Renamed after a delete",
          photoUrl: "https://example.com/renamed.jpg",
        },
      ),
    );

    const conversation = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    assert.equal(
      conversation.data().participantNames[uid],
      "Renamed after a delete",
    );
    // And the deletion state itself is left exactly as it was.
    assert.deepEqual(conversation.data().deletedBy, [friendUid]);
    assert.deepEqual(
      conversation.data().deletedSequences,
      { [uid]: 0, [friendUid]: 0 },
    );
  });

  test("fan-out pages safely beyond one 150-target transaction", async () => {
    const count = 151;
    const references = Array.from({ length: count }, (_, index) =>
      db.collection("conversations").doc(`pf-security-page-${index}`),
    );
    const peerUids = Array.from(
      { length: count },
      (_, index) => `pf-security-page-peer-${String(index).padStart(3, "0")}`,
    );
    const guardReferences = peerUids.map((peerUid) =>
      db.collection("directConversationPairs").doc(
        canonicalPairKey(...codeUnitPair(uid, peerUid)),
      ),
    );
    await setCanonical({
      displayName: "Paged identity",
      photoUrl: "https://example.com/paged.jpg",
    });
    for (let offset = 0; offset < references.length; offset += 200) {
      const batch = db.batch();
      for (let index = offset;
        index < Math.min(offset + 200, references.length);
        index += 1) {
        const reference = references[index];
        const peerUid = peerUids[index];
        const participants = codeUnitPair(uid, peerUid);
        batch.set(reference, canonicalConversationData({
          participants,
          names: {
            [uid]: "Before",
            [peerUid]: "Friend",
          },
          photos: {
            [uid]: "",
            [peerUid]: "https://example.com/friend.jpg",
          },
        }));
        batch.set(guardReferences[index], canonicalPairGuardData({
          conversationId: reference.id,
          participants,
        }));
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
        "",
      );
    } finally {
      for (let offset = 0; offset < references.length; offset += 200) {
        const batch = db.batch();
        for (let index = offset;
          index < Math.min(offset + 200, references.length);
          index += 1) {
          batch.delete(references[index]);
          batch.delete(guardReferences[index]);
        }
        await batch.commit();
      }
    }
  });
});
