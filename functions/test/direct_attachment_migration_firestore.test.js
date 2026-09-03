const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";

const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const app = initializeApp({ projectId: process.env.GCLOUD_PROJECT },
  "direct-attachment-migration-firestore-test");
const db = getFirestore(app);
const RESERVE_LEDGER = "migration-index-reserve";
const FINALIZE_LEDGER = "migration-index-finalize";
const MESSAGE_ID = `m_${"a".repeat(40)}`;

async function cleanup() {
  await Promise.all([
    db.doc(`integrityOperationLedgers/${RESERVE_LEDGER}`).delete(),
    db.doc(`integrityOperationLedgers/${FINALIZE_LEDGER}`).delete(),
  ]);
}

before(cleanup);
after(cleanup);

test("Build 18 reserve and finalize ledgers are separated by the migration query", async () => {
  await Promise.all([
    db.doc(`integrityOperationLedgers/${RESERVE_LEDGER}`).set({
      kind: "direct.attachment.reserve",
      result: { messageId: MESSAGE_ID },
    }),
    db.doc(`integrityOperationLedgers/${FINALIZE_LEDGER}`).set({
      kind: "direct.attachment.finalize",
      result: { messageId: MESSAGE_ID },
    }),
  ]);

  const snapshot = await db
    .collection("integrityOperationLedgers")
    .where("kind", "==", "direct.attachment.finalize")
    .where("result.messageId", "==", MESSAGE_ID)
    .limit(2)
    .get();

  assert.equal(snapshot.size, 1);
  assert.equal(snapshot.docs[0].id, FINALIZE_LEDGER);
});
