const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { canonicalPair } = require("../integrity/guards");
const {
  DIRECT_MESSAGE_TYPES,
  canonicalConversationId,
  canonicalPairKey,
  directMessagePreview,
  validateConversation,
  validateMessage,
} = require("../messaging/direct_integrity");
const {
  createDirectMigrationService,
} = require("../messaging/direct_migration");
const { gifMessageFallback } = require("../messaging/gif_message");
const { GIF_PROVIDERS, gifCdnUrl } = require("../media/gif/gif_ref");

// FMP-04 / RC-6. `migrateDirectIntegrityConversation` carried three drifts that
// together made the operator scan claim almost every active conversation needed
// migrating, and would have made an apply OVERWRITE a healthy root with an
// empty media preview, a reset typing map and recomputed read state. This suite
// is what makes the tool safe to hand an operator.

const db = getFirestore();
const A = "dmd-alice";
const B = "dmd-bob";
const PARTICIPANTS = canonicalPair(A, B);
const PAIR_KEY = canonicalPairKey(...PARTICIPANTS);
const CONVERSATION_ID = canonicalConversationId(...PARTICIPANTS);
const LEGACY_ID = `${PARTICIPANTS[0]}_${PARTICIPANTS[1]}`;
const NOW_MS = 1_812_000_000_000;

const GIF = Object.freeze({
  provider: GIF_PROVIDERS.yovoice,
  id: "celebrate-01",
  url: gifCdnUrl(GIF_PROVIDERS.yovoice, "celebrate-01"),
  title: "Celebrate",
  width: 320,
  height: 240,
});

function migrator() {
  return createDirectMigrationService({
    db,
    FieldPath,
    Timestamp,
    clock: () => NOW_MS,
  });
}

function participantMap(value) {
  return Object.fromEntries(PARTICIPANTS.map((uid) => [uid, value]));
}

function canonicalMessage(overrides = {}) {
  const base = {
    schemaVersion: 2,
    sequence: 1,
    conversationId: CONVERSATION_ID,
    senderId: PARTICIPANTS[0],
    type: "text",
    content: "hello",
    mediaUrl: null,
    durationSeconds: null,
    sentAt: Timestamp.fromMillis(NOW_MS - 60_000),
    readBy: [...PARTICIPANTS],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  };
  return { ...base, ...overrides };
}

function canonicalRoot(message, messageId) {
  return {
    schemaVersion: 2,
    pairKey: PAIR_KEY,
    participantIds: [...PARTICIPANTS],
    participantNames: {
      [PARTICIPANTS[0]]: "Alice",
      [PARTICIPANTS[1]]: "Bob",
    },
    participantEmails: participantMap(""),
    participantPhotoUrls: participantMap(""),
    unreadCounts: participantMap(0),
    readSequences: participantMap(1),
    // A live typing entry. Legacy roots let either participant overwrite the
    // peer's state, so the tool deliberately writes `{}` — but it must not
    // compare on a field it intentionally does not migrate.
    typing: {
      [PARTICIPANTS[1]]: {
        isTyping: true,
        updatedAt: Timestamp.fromMillis(NOW_MS - 1_000),
      },
    },
    archivedBy: [],
    mutedBy: [],
    lastMessage: directMessagePreview(message),
    lastMessageId: messageId,
    lastMessageSequence: 1,
    lastMessageType: message.type,
    lastMessageSenderId: message.senderId,
    createdAt: Timestamp.fromMillis(NOW_MS - 120_000),
    updatedAt: Timestamp.fromMillis(NOW_MS - 60_000),
  };
}

async function seedCanonical(message, messageId = "dmd-message-1") {
  const root = canonicalRoot(message, messageId);
  const rootRef = db.doc(`conversations/${CONVERSATION_ID}`);
  const guardRef = db.doc(`directConversationPairs/${PAIR_KEY}`);
  await Promise.all([
    rootRef.set(root),
    rootRef.collection("messages").doc(messageId).set(message),
    guardRef.set({
      schemaVersion: 1,
      pairKey: PAIR_KEY,
      conversationId: CONVERSATION_ID,
      participantIds: [...PARTICIPANTS],
      createdAt: Timestamp.fromMillis(NOW_MS - 120_000),
    }),
  ]);
  // The fixture is only meaningful if the LIVE readers accept it. Proving that
  // here is what makes "the tool reported conflict" a defect rather than an
  // opinion.
  const rootSnapshot = await rootRef.get();
  const guardSnapshot = await guardRef.get();
  validateConversation(
    rootSnapshot,
    CONVERSATION_ID,
    PARTICIPANTS[0],
    guardSnapshot,
  );
  validateMessage(
    await rootRef.collection("messages").doc(messageId).get(),
    CONVERSATION_ID,
  );
  return { guardRef, messageId, rootRef };
}

async function removeAll() {
  for (const path of [
    `conversations/${CONVERSATION_ID}`,
    `conversations/${LEGACY_ID}`,
  ]) {
    const reference = db.doc(path);
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(reference).catch(() => {});
    } else {
      await reference.delete().catch(() => {});
    }
  }
  await Promise.all([
    db.doc(`directConversationPairs/${PAIR_KEY}`).delete().catch(() => {}),
    ...PARTICIPANTS.map((uid) =>
      db.doc(`users/${uid}`).delete().catch(() => {})),
    ...PARTICIPANTS.map((uid) =>
      db.doc(`publicProfiles/${uid}`).delete().catch(() => {})),
  ]);
}

async function seedProfiles() {
  await Promise.all(PARTICIPANTS.map((uid) => db.doc(`users/${uid}`).set({
    uid,
    displayName: uid === PARTICIPANTS[0] ? "Alice" : "Bob",
  })));
  await Promise.all(PARTICIPANTS.map((uid) =>
    db.doc(`publicProfiles/${uid}`).set({
      accountType: "personal",
      bannerUrl: null,
      bio: "",
      country: "",
      displayName: uid === PARTICIPANTS[0] ? "Alice" : "Bob",
      displayNameSearch: uid === PARTICIPANTS[0] ? "alice" : "bob",
      followerCount: 0,
      followingCount: 0,
      friendCount: 0,
      learningLanguages: [],
      nativeLanguage: "",
      photoUrl: null,
      premiumIdentity: false,
      schemaVersion: 1,
      spokenLanguages: [],
      statusMessage: "",
      uid,
      updatedAt: Timestamp.fromMillis(NOW_MS),
      username: uid,
      usernameSearch: uid,
      website: null,
    })));
}

beforeEach(async () => {
  await removeAll();
  await seedProfiles();
});

after(removeAll);

test("the tool's accepted message types are the live writer's, not a copy",
  () => {
    assert.deepEqual(
      [...DIRECT_MESSAGE_TYPES],
      ["text", "voice", "image", "video", "gif"],
    );
  });

test("a healthy GIF thread with a live typing entry is alreadyMigrated",
  async () => {
    const message = canonicalMessage({
      type: "gif",
      gif: { ...GIF },
      content: gifMessageFallback(GIF),
    });
    const { rootRef, messageId } = await seedCanonical(message);

    // At HEAD: `conflict`, because canonicalizeMessage only accepted
    // ["text","voice","image"] and because `typing` was compared.
    const inspection = await migrator().inspectDirectConversation({
      conversationId: CONVERSATION_ID,
    });
    assert.deepEqual(inspection.issues, []);
    assert.equal(inspection.status, "alreadyMigrated");
    assert.equal(inspection.rootIsCanonical, true);

    // And an apply writes nothing at all.
    const before = (await rootRef.get()).updateTime;
    const messageBefore =
      (await rootRef.collection("messages").doc(messageId).get()).updateTime;
    const applied = await migrator().migrateDirectConversation({
      conversationId: CONVERSATION_ID,
      dryRun: false,
    });
    assert.equal(applied.status, "alreadyMigrated");
    const after = await rootRef.get();
    assert.equal(after.updateTime.isEqual(before), true);
    assert.equal(
      (await rootRef.collection("messages").doc(messageId).get())
        .updateTime.isEqual(messageBefore),
      true,
    );
    // The GIF asset survived, and so did the live preview and typing map.
    assert.deepEqual(after.data().typing, {
      [PARTICIPANTS[1]]: {
        isTyping: true,
        updatedAt: Timestamp.fromMillis(NOW_MS - 1_000),
      },
    });
    assert.equal(after.data().lastMessage, gifMessageFallback(GIF));
    assert.deepEqual(
      (await rootRef.collection("messages").doc(messageId).get()).data().gif,
      { ...GIF },
    );
  });

test("healthy media threads keep the live preview instead of being blanked",
  async () => {
    for (const [type, extra, preview] of [
      ["image", { mediaUrl: "gs://bucket/photo.jpg", content: "" }, "Photo"],
      [
        "video",
        {
          mediaUrl: "gs://bucket/clip.mp4",
          content: "Video",
          durationSeconds: 12,
        },
        "Video",
      ],
      [
        "voice",
        {
          mediaUrl: "gs://bucket/note.m4a",
          content: "",
          durationSeconds: 8,
        },
        "Voice message",
      ],
    ]) {
      await removeAll();
      await seedProfiles();
      const message = canonicalMessage({ type, ...extra });
      const { rootRef } = await seedCanonical(message);
      assert.equal((await rootRef.get()).data().lastMessage, preview);

      // At HEAD the tool's canonical root used "" for every non-text type, so
      // each of these reported `ready` and an apply would have blanked the
      // conversation list preview.
      const inspection = await migrator().inspectDirectConversation({
        conversationId: CONVERSATION_ID,
      });
      assert.equal(
        inspection.status,
        "alreadyMigrated",
        `${type} threads must not be reported as needing migration`,
      );
      assert.equal(inspection.canonicalRoot.lastMessage, preview);
    }
  });

test("a genuine legacy root still reports ready and still migrates", async () => {
  const rootRef = db.doc(`conversations/${LEGACY_ID}`);
  await rootRef.set({
    participantIds: [...PARTICIPANTS],
    participantNames: {
      [PARTICIPANTS[0]]: "Legacy Alice",
      [PARTICIPANTS[1]]: "Legacy Bob",
    },
    participantEmails: participantMap("private@old.invalid"),
    participantPhotoUrls: participantMap(""),
    unreadCounts: participantMap(0),
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "legacy",
    lastMessageType: "text",
    lastMessageSenderId: PARTICIPANTS[0],
    createdAt: Timestamp.fromMillis(NOW_MS - 200_000),
    updatedAt: Timestamp.fromMillis(NOW_MS - 150_000),
  });
  await rootRef.collection("messages").doc("legacy-message-1").set({
    conversationId: LEGACY_ID,
    senderId: PARTICIPANTS[0],
    type: "text",
    content: "legacy",
    mediaUrl: null,
    durationSeconds: null,
    sentAt: Timestamp.fromMillis(NOW_MS - 150_000),
    readBy: [PARTICIPANTS[0]],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  });

  const inspection = await migrator().inspectDirectConversation({
    conversationId: LEGACY_ID,
  });
  assert.deepEqual(inspection.issues, []);
  assert.equal(inspection.status, "ready");
  assert.equal(inspection.rootIsCanonical, false);
  assert.equal(inspection.canonicalRoot.schemaVersion, 2);
  assert.deepEqual(inspection.canonicalRoot.typing, {});
  assert.deepEqual(
    inspection.canonicalRoot.participantEmails,
    participantMap(""),
  );

  const dryRun = await migrator().migrateDirectConversation({
    conversationId: LEGACY_ID,
    dryRun: true,
  });
  assert.equal(dryRun.status, "ready");
  assert.equal((await rootRef.get()).data().schemaVersion, undefined);

  const applied = await migrator().migrateDirectConversation({
    conversationId: LEGACY_ID,
    dryRun: false,
  });
  assert.equal(applied.status, "migrated");
  const migrated = await rootRef.get();
  assert.equal(migrated.data().schemaVersion, 2);
  assert.equal(migrated.data().lastMessageSequence, 1);
  // The safety guard now short-circuits the replay before any write.
  assert.equal(
    (await migrator().migrateDirectConversation({
      conversationId: LEGACY_ID,
      dryRun: false,
    })).status,
    "alreadyMigrated",
  );
});

test("a malformed GIF asset is reported rather than silently rewritten",
  async () => {
    const message = canonicalMessage({
      type: "gif",
      gif: { ...GIF, url: "https://evil.invalid/celebrate-01.gif" },
      content: gifMessageFallback(GIF),
    });
    const rootRef = db.doc(`conversations/${CONVERSATION_ID}`);
    await rootRef.set(canonicalRoot(message, "dmd-message-1"));
    await rootRef.collection("messages").doc("dmd-message-1").set(message);
    await db.doc(`directConversationPairs/${PAIR_KEY}`).set({
      schemaVersion: 1,
      pairKey: PAIR_KEY,
      conversationId: CONVERSATION_ID,
      participantIds: [...PARTICIPANTS],
      createdAt: Timestamp.fromMillis(NOW_MS - 120_000),
    });

    const inspection = await migrator().inspectDirectConversation({
      conversationId: CONVERSATION_ID,
    });
    assert.equal(inspection.status, "conflict");
    assert.ok(
      inspection.issues.some((issue) =>
        issue.startsWith("invalidMessageGif:")),
      `expected an invalidMessageGif issue, got ${inspection.issues.join(",")}`,
    );
  });
