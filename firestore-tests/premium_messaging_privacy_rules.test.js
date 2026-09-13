const fs = require("node:fs");
const path = require("node:path");
const { after, before, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const PROJECT = "demo-yovoice-premium-messaging-privacy-rules";
const OWNER = "privacy-owner";
const PEER = "privacy-peer";
let env;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(":");
  return { host: parts[0], port: Number(parts[1]) };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      ...endpoint(process.env.FIRESTORE_EMULATOR_HOST, 8080),
      rules: fs.readFileSync(path.join(__dirname, "../firestore.rules"), "utf8"),
    },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, `directPrivacyPreferences/${OWNER}`), {
        schemaVersion: 1,
        ownerId: OWNER,
        hideReadReceipts: true,
        hideTyping: false,
        updatedAt: Timestamp.now(),
      }),
      setDoc(doc(db, "directPrivateReadStates/opaque-state"), {
        schemaVersion: 1,
        ownerId: OWNER,
        conversationId: "conversation-1",
        processedThroughSequence: 4,
        hiddenThroughSequence: 3,
        updatedAt: Timestamp.now(),
      }),
      setDoc(doc(db, "directConversationUnreadStates/owner-state"), {
        schemaVersion: 1,
        ownerId: OWNER,
        conversationId: "conversation-1",
        unreadCount: 0,
        updatedAt: Timestamp.now(),
      }),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid) {
  return env.authenticatedContext(uid, { email_verified: true }).firestore();
}

test("the owner can point-read only their preference projection", async () => {
  const snapshot = await assertSucceeds(
    getDoc(doc(context(OWNER), `directPrivacyPreferences/${OWNER}`)),
  );
  if (snapshot.data().hideReadReceipts !== true) {
    throw new Error("Owner read returned the wrong projection.");
  }
  await assertFails(
    getDoc(doc(context(PEER), `directPrivacyPreferences/${OWNER}`)),
  );
  await assertFails(
    getDoc(doc(env.unauthenticatedContext().firestore(),
      `directPrivacyPreferences/${OWNER}`)),
  );
  await assertFails(getDocs(query(
    collection(context(OWNER), "directPrivacyPreferences"),
    where("ownerId", "==", OWNER),
  )));
});

test("no client can author Premium messaging privacy", async () => {
  const owner = context(OWNER);
  await assertFails(updateDoc(
    doc(owner, `directPrivacyPreferences/${OWNER}`),
    { hideTyping: true },
  ));
  await assertFails(setDoc(
    doc(owner, "directPrivacyPreferences/another-user"),
    {
      schemaVersion: 1,
      ownerId: OWNER,
      hideReadReceipts: true,
      hideTyping: true,
      updatedAt: Timestamp.now(),
    },
  ));
});

test("private read cursors are invisible and immutable even to their owner", async () => {
  const owner = context(OWNER);
  const peer = context(PEER);
  await assertFails(getDoc(doc(owner, "directPrivateReadStates/opaque-state")));
  await assertFails(getDoc(doc(peer, "directPrivateReadStates/opaque-state")));
  await assertFails(setDoc(doc(owner, "directPrivateReadStates/forged"), {
    schemaVersion: 1,
    ownerId: OWNER,
    conversationId: "conversation-1",
    processedThroughSequence: 999,
    hiddenThroughSequence: 999,
    updatedAt: Timestamp.now(),
  }));
});

test("only the owner can read the server-written unread projection", async () => {
  const owner = context(OWNER);
  const peer = context(PEER);
  const reference = doc(
    owner,
    "directConversationUnreadStates/owner-state",
  );
  const snapshot = await assertSucceeds(getDoc(reference));
  if (snapshot.data().unreadCount !== 0) {
    throw new Error("Owner unread projection returned the wrong value.");
  }
  const owned = await assertSucceeds(getDocs(query(
    collection(owner, "directConversationUnreadStates"),
    where("ownerId", "==", OWNER),
  )));
  if (owned.size !== 1) {
    throw new Error("Owner unread query returned the wrong projection set.");
  }
  await assertFails(getDoc(doc(
    peer,
    "directConversationUnreadStates/owner-state",
  )));
  await assertFails(getDocs(query(
    collection(peer, "directConversationUnreadStates"),
    where("ownerId", "==", OWNER),
  )));
  await assertFails(updateDoc(reference, { unreadCount: 99 }));
});
