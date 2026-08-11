// End-to-end smoke test for the onGlobalMessageModerated BINDING.
//
// The unit tests next door call the handler directly, which proves its
// decision and payload but not that Firestore actually delivers the
// event to it. This closes that gap: it writes a real document, soft
// deletes it as a moderator would, and waits for the audit entry the
// deployed trigger is supposed to produce.
//
// Kept OUT of `npm test` on purpose — it needs the functions emulator as
// well as Firestore, which takes ~90s to boot and loads every function
// in the catalogue. Run it deliberately:
//
//   firebase emulators:start --only functions,firestore \
//     --project yovoice-fn-test
//   node test/global_chat_trigger.smoke.js
//
// Exits non-zero on failure so it can gate a release if it is ever
// wired into one.

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const assert = require("node:assert/strict");
const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const db = getFirestore();
const MESSAGE = "globalChat/main/messages/smoke-msg";

async function waitForAuditEntry({ timeoutMs = 20000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const entries = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", "smoke-msg")
      .get();
    if (!entries.empty) return entries;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return null;
}

async function main() {
  // Clean slate.
  const stale = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", "smoke-msg")
    .get();
  await Promise.all(stale.docs.map((entry) => entry.ref.delete()));
  await db.doc(MESSAGE).delete().catch(() => {});

  await db.doc(MESSAGE).set({
    senderId: "author-uid",
    senderName: "Author",
    senderPhotoUrl: null,
    senderIsCreator: false,
    senderIsStaff: false,
    content: "the original message",
    sentAt: FieldValue.serverTimestamp(),
    isDeleted: false,
    deletedBy: null,
    deletedAt: null,
  });

  // Exactly the write firestore.rules allows a moderator to make.
  await db.doc(MESSAGE).update({
    isDeleted: true,
    deletedBy: "mod-uid",
    deletedAt: FieldValue.serverTimestamp(),
    content: "",
  });

  const entries = await waitForAuditEntry();
  assert.ok(entries, "the trigger never fired — no audit entry appeared");
  assert.equal(entries.size, 1, "exactly one audit document");

  const entry = entries.docs[0];
  assert.ok(
    entry.id.startsWith("globalMessage_"),
    `audit id should be derived from the event id, got ${entry.id}`,
  );
  assert.equal(entry.data().actorId, "mod-uid");
  assert.equal(entry.data().details.authorId, "author-uid");
  assert.equal(entry.data().details.removedContent, "the original message");

  await Promise.all([
    ...entries.docs.map((doc) => doc.ref.delete()),
    db.doc(MESSAGE).delete(),
  ]);

  console.log("OK  the deployed binding delivers the event and writes "
    + `exactly one audit document (${entry.id})`);
}

main().catch((error) => {
  console.error("FAIL", error.message);
  process.exit(1);
});
