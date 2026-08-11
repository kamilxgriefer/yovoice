// Focused coverage for the ONE Cloud Function Global Chat adds:
// onGlobalMessageModerated, the trigger that records a moderator
// removing someone else's public message in adminAuditLogs.
//
// Runs the handler directly against the Firestore emulator — no project
// credentials, no deploy, and no extra dependency. Start the emulator
// first — see functions/test/README.md.
//
//   node --test test/
//
// Deliberately narrow: this covers the trigger's decision (is this
// moderation or an ordinary self-delete?), the payload it records, and
// its behaviour when the same event is delivered twice. Everything else
// about Global Chat is authorization, and that lives in
// firestore-tests/rules.test.js where the real rules are evaluated.

const assert = require("node:assert/strict");
const { test, after, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

// index.js is what initialises the app in production. These tests load
// the trigger module directly (so the whole function catalogue does not
// have to boot), and utils/firestore.js calls getFirestore() at import
// time — so the app has to exist first.
// No options, matching index.js exactly — Admin SDK rejects a second
// initializeApp() for the default app when the configuration differs,
// and the discoverability test below loads index.js.
if (getApps().length === 0) {
  initializeApp();
}

// The handler, not the onDocumentUpdated() wrapper. Deliberately no
// firebase-functions-test dependency: this repository tracks
// functions/node_modules in git, so a devDependency for one test file
// would add ~200 packages to every future diff. The wrapper is region +
// document-path configuration; the decision and the payload are here.
const { handleGlobalMessageModerated } = require("../moderation/global_chat");

const db = getFirestore();
const AUDIT = "adminAuditLogs";

const MESSAGE = {
  senderId: "author-uid",
  senderName: "Author",
  senderPhotoUrl: null,
  senderIsCreator: false,
  senderIsStaff: false,
  content: "the original message",
  isDeleted: false,
  deletedBy: null,
  deletedAt: null,
};

/// The shape onDocumentUpdated hands the handler: `data.before` and
/// `data.after` snapshots, the CloudEvent `id`, and the wildcard
/// `params`. A caller-supplied id is what lets a redelivery be simulated
/// exactly.
function moderationEvent({ before: beforeData, after: afterData, id }) {
  return {
    id,
    params: { channelId: "main", messageId: "msg-1" },
    data: {
      before: { data: () => beforeData },
      after: { data: () => afterData },
    },
  };
}

/// Scoped to THIS suite's target. adminAuditLogs is shared with the
/// moderateReport suite against the same emulator, so neither may
/// assert on — or delete — the whole collection.
async function auditsForMessage() {
  return db.collection(AUDIT).where("targetId", "==", "msg-1").get();
}

async function clearAudit() {
  const snapshot = await auditsForMessage();
  await Promise.all(snapshot.docs.map((entry) => entry.ref.delete()));
}

describe("the deployed export", () => {
  test("onGlobalMessageModerated is discoverable from functions/index.js, "
    + "so a deploy actually ships it", () => {
    const catalogue = require("../index.js");
    assert.equal(
      typeof catalogue.onGlobalMessageModerated,
      "function",
      "the trigger must be exported from index.js or it is never deployed",
    );
    // firebase-functions attaches its trigger metadata to the export;
    // this is the closest the harness gets to proving the BINDING (path
    // and event type) without a live functions emulator.
    const endpoint = catalogue.onGlobalMessageModerated.__endpoint;
    assert.ok(endpoint, "no trigger metadata on the export");
    assert.equal(endpoint.region?.[0] ?? endpoint.region, "europe-west1");
    assert.equal(
      endpoint.eventTrigger?.eventFilterPathPatterns?.document,
      "globalChat/{channelId}/messages/{messageId}",
    );
    assert.equal(
      endpoint.eventTrigger?.eventType,
      "google.cloud.firestore.document.v1.updated",
    );
  });
});

describe("onGlobalMessageModerated", () => {
  const wrapped = handleGlobalMessageModerated;

  beforeEach(clearAudit);

  after(clearAudit);

  test("an author deleting their OWN message is not moderation and is "
    + "not audited", async () => {
    await wrapped(
      moderationEvent({
        before: MESSAGE,
        after: {
          ...MESSAGE,
          isDeleted: true,
          deletedBy: "author-uid",
          content: "",
        },
        id: "event-self-delete",
      }),
    );

    const entries = await auditsForMessage();
    assert.equal(entries.size, 0);
  });

  test("a moderator soft deletion records who removed whose message, and "
    + "what it said", async () => {
    await wrapped(
      moderationEvent({
        before: MESSAGE,
        after: {
          ...MESSAGE,
          isDeleted: true,
          deletedBy: "mod-uid",
          content: "",
        },
        id: "event-moderated",
      }),
    );

    const entries = await auditsForMessage();
    assert.equal(entries.size, 1);

    const entry = entries.docs[0].data();
    assert.equal(entry.actorId, "mod-uid", "the moderator");
    assert.equal(entry.action, "delete_global_message");
    assert.equal(entry.targetType, "globalMessage");
    assert.equal(entry.targetId, "msg-1", "the message");
    assert.equal(entry.targetLabel, "Author");
    assert.equal(entry.details.authorId, "author-uid", "the original author");
    assert.equal(
      entry.details.removedContent,
      "the original message",
      "the text as it was before removal",
    );
    assert.equal(entry.details.channelId, "main");
  });

  test("an unrelated update to a live message creates no audit entry",
    async () => {
      await wrapped(
        moderationEvent({
          before: MESSAGE,
          after: { ...MESSAGE, senderName: "Author renamed" },
          id: "event-unrelated",
        }),
      );

      assert.equal((await auditsForMessage()).size, 0);
    });

  test("re-touching an ALREADY deleted message creates no second entry",
    async () => {
      const deleted = {
        ...MESSAGE,
        isDeleted: true,
        deletedBy: "mod-uid",
        content: "",
      };
      await wrapped(
        moderationEvent({
          before: deleted,
          after: { ...deleted, deletedAt: new Date() },
          id: "event-already-deleted",
        }),
      );

      assert.equal((await auditsForMessage()).size, 0);
    });

  test("a RETRIED delivery of the same event cannot duplicate the audit "
    + "record", async () => {
    const event = moderationEvent({
      before: MESSAGE,
      after: {
        ...MESSAGE,
        isDeleted: true,
        deletedBy: "mod-uid",
        content: "",
      },
      // Firestore triggers are at-least-once; a redelivery carries the
      // same CloudEvent id.
      id: "event-retried",
    });

    await wrapped(event);
    await wrapped(event);
    await wrapped(event);

    const entries = await auditsForMessage();
    assert.equal(entries.size, 1, "one removal, one record");
    assert.equal(entries.docs[0].id, "globalMessage_event-retried");
  });

  test("two DIFFERENT removals are recorded separately", async () => {
    for (const id of ["event-a", "event-b"]) {
      await wrapped(
        moderationEvent({
          before: MESSAGE,
          after: {
            ...MESSAGE,
            isDeleted: true,
            deletedBy: "mod-uid",
            content: "",
          },
          id,
        }),
      );
    }

    assert.equal((await auditsForMessage()).size, 2);
  });
});
