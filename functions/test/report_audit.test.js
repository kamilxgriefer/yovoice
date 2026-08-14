// Coverage for listReportAuditTrail — the SCOPED audit reader.
//
// The threat this suite exists for is leakage: `adminAuditLogs` holds
// bans, role assignments, club deletions and every other admin action,
// and a moderator reviewing one report must see none of it. Most cases
// below are "does this return something it should not".
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { listReportAuditTrail, MAX_LIMIT } = require("../moderation/report_audit");

const db = getFirestore();
const run = listReportAuditTrail.run ?? listReportAuditTrail;

const MOD = "audit-mod-uid";
const ADMIN = "audit-admin-uid";
const PLAIN = "audit-plain-uid";
const BANNED_MOD = "audit-banned-mod";
const REVOKED_MOD = "audit-revoked-mod";
const AUTHOR = "audit-author-uid";

const REPORT_ID = "audit-reporter_globalMessage_audit-msg";
const OTHER_REPORT_ID = "audit-reporter_globalMessage_other-msg";
const MESSAGE_ID = "audit-msg";

function request(uid, role, data) {
  return { auth: { uid, token: { role } }, data };
}

function minutesAgo(minutes) {
  return Timestamp.fromDate(new Date(Date.now() - minutes * 60 * 1000));
}

async function seed() {
  await Promise.all([
    db.doc(`users/${MOD}`).set({ uid: MOD, displayName: "Mia Moderator", role: "moderator" }),
    db.doc(`users/${ADMIN}`).set({ uid: ADMIN, displayName: "Ada Admin", role: "superModerator" }),
    db.doc(`users/${PLAIN}`).set({ uid: PLAIN, displayName: "Plain", role: "user" }),
    db.doc(`users/${BANNED_MOD}`).set({
      uid: BANNED_MOD, displayName: "Banned", role: "moderator", banned: true,
    }),
    db.doc(`users/${REVOKED_MOD}`).set({
      uid: REVOKED_MOD, displayName: "Revoked", role: "user",
    }),
    db.doc(`reports/${REPORT_ID}`).set({
      reporterId: "audit-reporter",
      targetType: "globalMessage",
      targetId: MESSAGE_ID,
      reportedUserId: AUTHOR,
      reason: "harassment",
      note: "",
      createdAt: minutesAgo(120),
      status: "resolved",
    }),
    db.doc(`reports/${OTHER_REPORT_ID}`).set({
      reporterId: "audit-reporter",
      targetType: "globalMessage",
      targetId: "other-msg",
      reportedUserId: AUTHOR,
      reason: "spam",
      note: "",
      createdAt: minutesAgo(130),
      status: "open",
    }),
  ]);

  // Wipe any audit rows this suite owns, then lay down a known set.
  for (const targetId of [REPORT_ID, OTHER_REPORT_ID, MESSAGE_ID, "other-msg", "some-user"]) {
    const stale = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", targetId)
      .get();
    await Promise.all(stale.docs.map((d) => d.ref.delete()));
  }

  await Promise.all([
    // THIS report's workflow events.
    db.doc(`adminAuditLogs/report_${REPORT_ID}_req-1`).set({
      actorId: MOD, actorEmail: "mia@example.invalid", actorRole: "moderator",
      action: "report_claim", targetType: "report", targetId: REPORT_ID,
      details: { previousStatus: "open", newStatus: "inReview", contentRemoved: false },
      createdAt: minutesAgo(30),
    }),
    db.doc(`adminAuditLogs/report_${REPORT_ID}_req-2`).set({
      actorId: MOD, actorEmail: "mia@example.invalid", actorRole: "moderator",
      action: "report_removeAndResolve", targetType: "report", targetId: REPORT_ID,
      details: {
        previousStatus: "inReview", newStatus: "resolved",
        resolution: "contentRemoved", note: "clear violation", contentRemoved: true,
      },
      createdAt: minutesAgo(20),
    }),
    // The MESSAGE's own removal event.
    db.doc("adminAuditLogs/globalMessage_evt-1").set({
      actorId: MOD, actorEmail: "mia@example.invalid", actorRole: "moderator",
      action: "delete_global_message", targetType: "globalMessage",
      targetId: MESSAGE_ID, targetLabel: "Author",
      details: { channelId: "main", authorId: AUTHOR, removedContent: "the removed text" },
      createdAt: minutesAgo(20),
    }),
    // ANOTHER report's event — must never appear.
    db.doc(`adminAuditLogs/report_${OTHER_REPORT_ID}_req-9`).set({
      actorId: ADMIN, actorRole: "admin",
      action: "report_dismiss", targetType: "report", targetId: OTHER_REPORT_ID,
      details: { previousStatus: "open", newStatus: "dismissed" },
      createdAt: minutesAgo(10),
    }),
    // An UNRELATED admin action — must never appear.
    db.doc("adminAuditLogs/ban-entry-1").set({
      actorId: ADMIN, actorEmail: "ada@example.invalid", actorRole: "admin",
      action: "ban_user", targetType: "user", targetId: "some-user",
      details: { reason: "spam" },
      createdAt: minutesAgo(5),
    }),
  ]);
}

async function expectRejection(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

describe("listReportAuditTrail", () => {
  beforeEach(seed);

  describe("authorization", () => {
    test("unauthenticated is denied", async () => {
      await expectRejection(
        run({ auth: null, data: { reportId: REPORT_ID } }),
        "unauthenticated",
      );
    });

    test("an ordinary user is denied", async () => {
      await expectRejection(
        run(request(PLAIN, "user", { reportId: REPORT_ID })),
        "permission-denied",
      );
    });

    test("an unsupported role (vip) is denied", async () => {
      await expectRejection(
        run(request(PLAIN, "vip", { reportId: REPORT_ID })),
        "permission-denied",
      );
    });

    test("banned staff are denied", async () => {
      await expectRejection(
        run(request(BANNED_MOD, "moderator", { reportId: REPORT_ID })),
        "permission-denied",
      );
    });

    test("a claim/document-role mismatch is denied — a revoked "
      + "moderator's stale token buys nothing", async () => {
      await expectRejection(
        run(request(REVOKED_MOD, "moderator", { reportId: REPORT_ID })),
        "permission-denied",
      );
    });

    test("a moderator is allowed", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      assert.ok(Array.isArray(result.events));
    });

    test("a super moderator is allowed, under the same scoping as a moderator",
      async () => {
        const result = await run(request(ADMIN, "superModerator", { reportId: REPORT_ID }));
        const ids = result.events.map((e) => e.id);
        assert.ok(!ids.includes("ban-entry-1"), "still scoped to the report");
      });
  });

  describe("validation", () => {
    test("a malformed report id is rejected", async () => {
      for (const bad of ["../../users/x", "has spaces", ""]) {
        await expectRejection(
          run(request(MOD, "moderator", { reportId: bad })),
          "invalid-argument",
        );
      }
    });

    test("a nonexistent report is not-found", async () => {
      await expectRejection(
        run(request(MOD, "moderator", { reportId: "nope_globalMessage_nope" })),
        "not-found",
      );
    });

    test("a forged cursor is rejected", async () => {
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          cursor: "not-a-timestamp",
        })),
        "invalid-argument",
      );
    });

    test("an oversized page limit is clamped, never honoured", async () => {
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        limit: 5000,
      }));
      assert.ok(
        result.events.length <= MAX_LIMIT,
        `returned ${result.events.length}, cap is ${MAX_LIMIT}`,
      );
    });

    test("the caller cannot name an arbitrary target — the target is "
      + "read from the report", async () => {
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        // Ignored entirely: not a parameter the handler reads.
        targetId: "some-user",
        targetType: "user",
      }));
      const ids = result.events.map((e) => e.id);
      assert.ok(!ids.includes("ban-entry-1"), "unrelated target leaked");
    });
  });

  describe("scoping", () => {
    test("returns THIS report's workflow events and its message's "
      + "removal — and nothing else", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      const ids = result.events.map((e) => e.id).sort();

      assert.deepEqual(ids, [
        `report_${REPORT_ID}_req-1`,
        `report_${REPORT_ID}_req-2`,
        "globalMessage_evt-1",
      ].sort());
    });

    test("another report's events never appear", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      assert.ok(
        !result.events.some((e) => e.id.includes(OTHER_REPORT_ID)),
        "another report's audit leaked",
      );
    });

    test("unrelated admin actions never appear", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      assert.ok(
        !result.events.some((e) => e.action === "ban_user"),
        "an unrelated admin action leaked",
      );
    });

    test("the two record kinds are distinguished, not merged", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      const workflow = result.events.filter((e) => e.kind === "reportWorkflow");
      const content = result.events.filter((e) => e.kind === "contentModeration");

      assert.equal(workflow.length, 2);
      assert.equal(content.length, 1);
      // The content event carries the evidence; the workflow event
      // carries the transition.
      assert.equal(content[0].removedContent, "the removed text");
      assert.equal(content[0].previousStatus, null);
      assert.equal(workflow[0].removedContent, null);
      assert.ok(workflow.some((e) => e.newStatus === "resolved"));
    });

    test("a report about an ACCOUNT pulls no message history", async () => {
      await db.doc("reports/audit-reporter_user_someone").set({
        reporterId: "audit-reporter",
        targetType: "user",
        targetId: AUTHOR,
        reportedUserId: AUTHOR,
        reason: "impersonation",
        note: "",
        createdAt: minutesAgo(60),
        status: "open",
      });
      const result = await run(request(MOD, "moderator", {
        reportId: "audit-reporter_user_someone",
      }));
      assert.equal(result.events.length, 0);
    });
  });

  describe("response shape", () => {
    test("private and unrelated fields are absent", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      const allowed = new Set([
        "id", "kind", "action", "actorId", "actorName", "actorRole",
        "previousStatus", "newStatus", "resolution", "note",
        "contentRemoved", "removedContent", "createdAt",
      ]);
      for (const event of result.events) {
        for (const key of Object.keys(event)) {
          assert.ok(allowed.has(key), `unexpected field \`${key}\` in response`);
        }
        assert.equal(event.actorEmail, undefined, "actor email leaked");
        assert.equal(event.targetLabel, undefined);
        assert.equal(event.details, undefined, "raw details leaked");
      }
    });

    test("the acting moderator is named with a public display name",
      async () => {
        const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
        const claim = result.events.find((e) => e.action === "report_claim");
        assert.equal(claim.actorName, "Mia Moderator");
        assert.equal(claim.actorRole, "moderator");
      });

    test("the reporter is never named", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      const serialised = JSON.stringify(result);
      assert.ok(
        !serialised.includes("audit-reporter\""),
        "the reporter's identity appeared in the audit response",
      );
    });
  });

  describe("ordering and pagination", () => {
    test("newest first, deterministically", async () => {
      const result = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      const times = result.events.map((e) => e.createdAt);
      const sorted = [...times].sort().reverse();
      assert.deepEqual(times, sorted);

      // And stable across repeated calls.
      const again = await run(request(MOD, "moderator", { reportId: REPORT_ID }));
      assert.deepEqual(again.events.map((e) => e.id), result.events.map((e) => e.id));
    });

    test("paging with the returned cursor yields no duplicates and no "
      + "reordering", async () => {
      const first = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        limit: 2,
      }));
      assert.equal(first.events.length, 2);
      assert.equal(first.hasMore, true);
      assert.ok(first.nextCursor);

      const second = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        limit: 2,
        cursor: first.nextCursor,
      }));

      const firstIds = first.events.map((e) => e.id);
      const secondIds = second.events.map((e) => e.id);
      for (const id of secondIds) {
        assert.ok(!firstIds.includes(id), `duplicate across pages: ${id}`);
      }
      // Combined, still newest-first.
      const combined = [...first.events, ...second.events].map((e) => e.createdAt);
      assert.deepEqual(combined, [...combined].sort().reverse());
    });

    test("hasMore is false once the trail is exhausted", async () => {
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        limit: MAX_LIMIT,
      }));
      assert.equal(result.hasMore, false);
      assert.equal(result.nextCursor, null);
    });
  });

  test("the export is discoverable from functions/index.js", () => {
    const catalogue = require("../index.js");
    assert.equal(typeof catalogue.listReportAuditTrail, "function");
    const endpoint = catalogue.listReportAuditTrail.__endpoint;
    assert.ok(endpoint?.callableTrigger, "must be a callable");
    assert.equal(endpoint.region?.[0] ?? endpoint.region, "europe-west1");
  });
});
