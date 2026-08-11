// End-to-end smoke test for the moderateReport BINDING.
//
// The unit tests call the handler directly, which proves its logic but
// not that the deployed callable is reachable. This calls the emulated
// endpoint over HTTP exactly as the Flutter client will, with a forged
// *emulator* ID token — the Functions emulator accepts unsigned tokens
// so callables can be exercised locally, which is the only reason this
// works without real credentials.
//
// Kept out of `npm test`: it needs the functions emulator as well as
// Firestore.
//
//   firebase emulators:start --only functions,firestore \
//     --project yovoice-fn-test
//   node test/moderation_trigger.smoke.js
//
// Exits non-zero on failure.

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const assert = require("node:assert/strict");
const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const db = getFirestore();

const PROJECT = process.env.GCLOUD_PROJECT;
const FUNCTIONS_HOST =
  process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1:5001";
const ENDPOINT =
  `http://${FUNCTIONS_HOST}/${PROJECT}/europe-west1/moderateReport`;

const MOD = "smoke-mod-uid";
const AUTHOR = "smoke-author-uid";
const REPORTER = "smoke-reporter-uid";
const MESSAGE_ID = "smoke-target-msg";
const REPORT_ID = `${REPORTER}_globalMessage_${MESSAGE_ID}`;
const MESSAGE_PATH = `globalChat/main/messages/${MESSAGE_ID}`;

/// An unsigned JWT. Only the Functions emulator accepts these; it is how
/// a callable's `request.auth` is populated locally.
function emulatorIdToken(uid, claims = {}) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const header = encode({ alg: "none", typ: "JWT" });
  const payload = encode({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: uid,
    user_id: uid,
    uid,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    email_verified: true,
    firebase: { sign_in_provider: "custom", identities: {} },
    ...claims,
  });
  return `${header}.${payload}.`;
}

async function callModerateReport(body, { uid, role }) {
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${emulatorIdToken(uid, { role })}`,
    },
    body: JSON.stringify({ data: body }),
  });
  const json = await response.json().catch(() => ({}));
  return { status: response.status, json };
}

async function seed() {
  await Promise.all([
    db.doc(`users/${MOD}`).set({
      uid: MOD,
      displayName: "Smoke Mod",
      role: "moderator",
    }),
    db.doc(`users/${AUTHOR}`).set({ uid: AUTHOR, displayName: "Smoke Author" }),
    db.doc(MESSAGE_PATH).set({
      senderId: AUTHOR,
      senderName: "Smoke Author",
      senderPhotoUrl: null,
      senderIsCreator: false,
      senderIsStaff: false,
      content: "reported content",
      sentAt: FieldValue.serverTimestamp(),
      isDeleted: false,
      deletedBy: null,
      deletedAt: null,
    }),
    db.doc(`reports/${REPORT_ID}`).set({
      reporterId: REPORTER,
      targetType: "globalMessage",
      targetId: MESSAGE_ID,
      reportedUserId: AUTHOR,
      contextPath: MESSAGE_PATH,
      reason: "harassment",
      note: "",
      createdAt: FieldValue.serverTimestamp(),
      status: "open",
    }),
  ]);
  const stale = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", REPORT_ID)
    .get();
  await Promise.all(stale.docs.map((entry) => entry.ref.delete()));
}

async function main() {
  await seed();

  // An ordinary account must be refused by the deployed endpoint, not
  // just by the handler in isolation.
  const denied = await callModerateReport(
    { reportId: REPORT_ID, action: "claim", requestId: "smoke-denied-0001" },
    { uid: "smoke-plain-uid", role: "user" },
  );
  assert.equal(denied.status, 403, `ordinary user should be refused, got ${denied.status}`);

  const requestId = "smoke-request-000001";
  const first = await callModerateReport(
    {
      reportId: REPORT_ID,
      action: "removeAndResolve",
      requestId,
      resolution: "contentRemoved",
      moderatorNote: "smoke test",
    },
    { uid: MOD, role: "moderator" },
  );
  assert.equal(first.status, 200, `expected 200, got ${first.status}`);
  assert.equal(first.json.result?.status, "resolved");
  assert.equal(first.json.result?.contentRemoved, true);

  // Firestore state: the message is soft deleted, evidence intact.
  const message = (await db.doc(MESSAGE_PATH).get()).data();
  assert.equal(message.isDeleted, true, "message must be soft deleted");
  assert.equal(message.deletedBy, MOD);
  assert.equal(message.content, "");
  assert.equal(message.senderId, AUTHOR, "authorship evidence preserved");

  const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
  assert.equal(report.status, "resolved");
  assert.equal(report.contentRemoved, true);
  assert.equal(report.resolvedBy, MOD);
  assert.equal(report.reason, "harassment", "reporter evidence preserved");

  // The report action audit.
  const reportAudits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", REPORT_ID)
    .get();
  assert.equal(reportAudits.size, 1, "exactly one report-action audit");
  assert.equal(reportAudits.docs[0].id, `report_${REPORT_ID}_${requestId}`);

  // Replaying the same requestId must change nothing and add nothing.
  const replay = await callModerateReport(
    {
      reportId: REPORT_ID,
      action: "removeAndResolve",
      requestId,
      resolution: "contentRemoved",
    },
    { uid: MOD, role: "moderator" },
  );
  assert.equal(replay.status, 200);
  assert.equal(replay.json.result?.replayed, true, "retry must be a replay");
  assert.equal(
    (await db.collection("adminAuditLogs").where("targetId", "==", REPORT_ID).get()).size,
    1,
    "a retry must not add a second audit record",
  );

  // The separate onGlobalMessageModerated audit for the message removal
  // itself — a DIFFERENT record from the report-action one, by design:
  // one says "this report was resolved", the other says "this message
  // was removed", and they are keyed on different targets so neither
  // duplicates the other. The trigger fires asynchronously after the
  // write commits, so this polls rather than assuming it has landed.
  const deadline = Date.now() + 20000;
  let messageAudits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", MESSAGE_ID)
    .get();
  while (messageAudits.empty && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    messageAudits = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", MESSAGE_ID)
      .get();
  }
  assert.equal(
    messageAudits.size,
    1,
    "the message-removal trigger should also have recorded exactly once",
  );
  assert.ok(
    messageAudits.docs[0].id.startsWith("globalMessage_"),
    "the removal audit is keyed on the CloudEvent id",
  );

  console.log(
    "OK  moderateReport is reachable, refuses non-staff, soft-deletes the "
      + "target, resolves the report, and writes one audit per action "
      + `(${reportAudits.docs[0].id})`,
  );
}

main().catch((error) => {
  console.error("FAIL", error.message);
  process.exit(1);
});
