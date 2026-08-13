// Coverage for adminDeleteMessage — privileged message redaction.
//
// The threats this suite exists for, in order of severity:
//
//  1. A caller who is not a super admin doing ANY of it.
//  2. A stale or forged claim — a token still saying superAdmin after the
//     role was revoked, or a client asserting a role the server never
//     wrote.
//  3. Path escape: the client naming its own Firestore location.
//  4. Private conversations being reachable without a matching report,
//     or with someone else's report.
//
// Most cases below are therefore "does this refuse something it must".
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { adminDeleteMessage, safeId } = require("../admin/messages");

const db = getFirestore();
const run = adminDeleteMessage.run ?? adminDeleteMessage;

const SUPER = "adm-del-super";
const STALE_SUPER = "adm-del-stale";
const BANNED_SUPER = "adm-del-banned";
const MOD = "adm-del-mod";
const PLAIN = "adm-del-plain";
const AUTHOR = "adm-del-author";

const CHANNEL = "adm-del-channel";
const CONVERSATION = "adm-del-conv-1";
const OTHER_CONVERSATION = "adm-del-conv-2";

function request(uid, role, data) {
  return { auth: { uid, token: { role } }, data };
}

// `node --test` runs suites in PARALLEL against one emulator, and
// `users`, `reports` and `adminAuditLogs` are shared with the other
// suites. Wiping those collections wholesale took their fixtures out
// from under them and produced eight unrelated failures; reusing common
// uids like `mod-uid` produced three more. Every document this suite
// writes is therefore prefixed `adm-del-`, it removes only what it owns,
// and it counts only audit entries written by the action under test.
async function wipeOwn() {
  const ids = [SUPER, STALE_SUPER, BANNED_SUPER, MOD, PLAIN];
  await Promise.all([
    ...ids.map((uid) => db.collection("users").doc(uid).delete()),
    ...["adm-del-r1", "adm-del-r-other", "adm-del-r-msg"].map((id) =>
      db.collection("reports").doc(id).delete(),
    ),
  ]);
  const mine = await db
    .collection("adminAuditLogs")
    .where("action", "==", "adminDeleteMessage")
    .get();
  await Promise.all(mine.docs.map((doc) => doc.ref.delete()));
}

async function ownAuditEntries() {
  return db
    .collection("adminAuditLogs")
    .where("action", "==", "adminDeleteMessage")
    .get();
}

beforeEach(async () => {
  await wipeOwn();

  // Claim AND server record agree only for SUPER.
  await db.collection("users").doc(SUPER).set({ role: "superAdmin" });
  // Claim says superAdmin; the server record does not (revoked role whose
  // token has not refreshed).
  await db.collection("users").doc(STALE_SUPER).set({ role: "moderator" });
  await db
    .collection("users")
    .doc(BANNED_SUPER)
    .set({ role: "superAdmin", banned: true });
  await db.collection("users").doc(MOD).set({ role: "moderator" });
  await db.collection("users").doc(PLAIN).set({ role: "user" });

  await db
    .collection("globalChat")
    .doc(CHANNEL)
    .collection("messages")
    .doc("adm-del-m1")
    .set({
      senderId: AUTHOR,
      content: "adm del public message",
      audioUrl: "https://example.invalid/o/voice%2Fm1.m4a?alt=media",
      isDeleted: false,
    });

  await db
    .collection("conversations")
    .doc(CONVERSATION)
    .collection("messages")
    .doc("adm-del-dm1")
    .set({ senderId: AUTHOR, content: "private", isDeleted: false });

  await db.collection("reports").doc("adm-del-r1").set({
    targetMessageId: "adm-del-dm1",
    targetConversationId: CONVERSATION,
  });
  // A real report, but about a different conversation.
  await db.collection("reports").doc("adm-del-r-other").set({
    targetMessageId: "adm-del-dm1",
    targetConversationId: OTHER_CONVERSATION,
  });
});

const globalArgs = {
  messageType: "globalMessage",
  reason: "abuse",
  ids: { channelId: CHANNEL, messageId: "adm-del-m1" },
};

describe("authorization", () => {
  test("a super admin can redact a public message", async () => {
    const result = await run(request(SUPER, "superAdmin", globalArgs));
    assert.equal(result.outcome, "redacted");

    const doc = await db
      .collection("globalChat")
      .doc(CHANNEL)
      .collection("messages")
      .doc("adm-del-m1")
      .get();
    assert.equal(doc.data().content, "");
    assert.equal(doc.data().isDeleted, true);
    assert.equal(doc.data().deletedBy, SUPER);
    // The tombstone stays so replies do not dangle.
    assert.equal(doc.exists, true);
    // Media reference is stripped from the document.
    assert.equal(doc.data().audioUrl, undefined);
  });

  test("an ordinary user is denied", async () => {
    await assert.rejects(
      () => run(request(PLAIN, "user", globalArgs)),
      /super administrator/i,
    );
  });

  test("a moderator is denied — this is not a moderator capability", async () => {
    await assert.rejects(
      () => run(request(MOD, "moderator", globalArgs)),
      /super administrator/i,
    );
  });

  test("an unauthenticated caller is denied", async () => {
    await assert.rejects(
      () => run({ auth: null, data: globalArgs }),
      /signed in/i,
    );
  });

  test("a FORGED claim is denied — the server record decides", async () => {
    // The token says superAdmin; users/{uid}.role says moderator.
    await assert.rejects(
      () => run(request(STALE_SUPER, "superAdmin", globalArgs)),
      /super administrator/i,
    );
  });

  test("a BANNED super admin is denied", async () => {
    await assert.rejects(
      () => run(request(BANNED_SUPER, "superAdmin", globalArgs)),
      /super administrator/i,
    );
  });

  test("a denied attempt writes NO audit entry and leaves the message", async () => {
    await assert.rejects(() => run(request(PLAIN, "user", globalArgs)));
    const logs = await ownAuditEntries();
    assert.equal(logs.size, 0);
    const doc = await db
      .collection("globalChat")
      .doc(CHANNEL)
      .collection("messages")
      .doc("adm-del-m1")
      .get();
    assert.equal(doc.data().isDeleted, false);
  });
});

describe("bounded inputs", () => {
  test("an unsupported message type is refused", async () => {
    await assert.rejects(
      () =>
        run(
          request(SUPER, "superAdmin", {
            ...globalArgs,
            messageType: "userProfile",
          }),
        ),
      /Unsupported message type/,
    );
  });

  test("an arbitrary path cannot be smuggled through an id", async () => {
    for (const evil of ["../../users/victim", "a/b", "..", ""]) {
      await assert.rejects(
        () =>
          run(
            request(SUPER, "superAdmin", {
              ...globalArgs,
              ids: { channelId: CHANNEL, messageId: evil },
            }),
          ),
        /messageId/,
      );
    }
  });

  test("safeId refuses separators and traversal directly", () => {
    assert.throws(() => safeId("a/b", "x"), /not a valid id/);
    assert.throws(() => safeId("..", "x"), /not a valid id/);
    assert.throws(() => safeId("", "x"), /required/);
    assert.equal(safeId(" ok-id ", "x"), "ok-id");
  });

  test("a reason is required", async () => {
    await assert.rejects(
      () => run(request(SUPER, "superAdmin", { ...globalArgs, reason: "  " })),
      /reason is required/,
    );
  });
});

describe("direct messages", () => {
  const dmArgs = {
    messageType: "directMessage",
    reason: "harassment",
    ids: { conversationId: CONVERSATION, messageId: "adm-del-dm1" },
  };

  test("a matching report permits removal", async () => {
    const result = await run(
      request(SUPER, "superAdmin", { ...dmArgs, reportId: "adm-del-r1" }),
    );
    assert.equal(result.outcome, "redacted");
  });

  test("NO report means no access to a private conversation", async () => {
    await assert.rejects(
      () => run(request(SUPER, "superAdmin", dmArgs)),
      /through a report/,
    );
  });

  test("a report for a DIFFERENT conversation is refused", async () => {
    await assert.rejects(
      () => run(request(SUPER, "superAdmin", { ...dmArgs, reportId: "adm-del-r-other" })),
      /does not identify this message/,
    );
  });

  test("a report naming a different message is refused", async () => {
    await db.collection("reports").doc("adm-del-r-msg").set({
      targetMessageId: "some-other-message",
      targetConversationId: CONVERSATION,
    });
    await assert.rejects(
      () => run(request(SUPER, "superAdmin", { ...dmArgs, reportId: "adm-del-r-msg" })),
      /does not identify this message/,
    );
  });

  test("a report that does not exist is refused", async () => {
    await assert.rejects(
      () => run(request(SUPER, "superAdmin", { ...dmArgs, reportId: "nope" })),
      /does not exist/,
    );
  });
});

describe("idempotency and audit", () => {
  test("removing twice is safe and reports alreadyRemoved", async () => {
    const first = await run(request(SUPER, "superAdmin", globalArgs));
    assert.equal(first.outcome, "redacted");
    const second = await run(request(SUPER, "superAdmin", globalArgs));
    assert.equal(second.outcome, "alreadyRemoved");
    assert.equal(second.redacted, false);
  });

  test("a missing message reports missing rather than throwing", async () => {
    const result = await run(
      request(SUPER, "superAdmin", {
        ...globalArgs,
        ids: { channelId: CHANNEL, messageId: "never-existed" },
      }),
    );
    assert.equal(result.outcome, "missing");
  });

  test("the audit entry records the act but NEVER the message body", async () => {
    await run(request(SUPER, "superAdmin", globalArgs));
    const logs = await ownAuditEntries();
    assert.equal(logs.size, 1);
    const entry = logs.docs[0].data();

    assert.equal(entry.action, "adminDeleteMessage");
    assert.equal(entry.targetType, "globalMessage");
    assert.equal(entry.targetId, "adm-del-m1");

    // The whole serialised entry must not contain the message content.
    const serialised = JSON.stringify(entry);
    assert.equal(
      serialised.includes("adm del public message"),
      false,
      "private content leaked into adminAuditLogs",
    );
  });

  test("every outcome is audited, including the no-op ones", async () => {
    await run(request(SUPER, "superAdmin", globalArgs));
    await run(request(SUPER, "superAdmin", globalArgs));
    const logs = await ownAuditEntries();
    assert.equal(logs.size, 2);
  });
});
