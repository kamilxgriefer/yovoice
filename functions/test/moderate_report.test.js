// Coverage for the moderateReport callable: the ONLY path that can move
// a report's status. firestore.rules denies client writes to `reports`
// outright, so everything asserted here is the real enforcement, not a
// second opinion.
//
// The callable's HANDLER is exercised directly with a request object of
// the shape onCall provides ({auth, data}). That keeps this suite free
// of a firebase-functions-test dependency — functions/node_modules is
// tracked in this repository, so one devDependency would land ~200
// packages in every future diff. The BINDING (that the export exists and
// is deployable) is asserted in the discoverability test, and exercised
// for real by test/moderation_trigger.smoke.js.
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  moderateReport,
  moderationAuditId,
} = require("../moderation/reports");

const db = getFirestore();
const run = moderateReport.run ?? moderateReport;

const MOD = "mod-uid";
const ADMIN = "admin-uid";
const PLAIN = "plain-uid";
const BANNED_MOD = "banned-mod-uid";
const REVOKED_MOD = "revoked-mod-uid";
const DISABLED_MOD = "disabled-mod-uid";
const DELETED_FLAG_MOD = "deleted-flag-mod-uid";
const DELETED_STATUS_MOD = "deleted-status-mod-uid";
const CROSS_ROLE_MOD = "cross-role-mod-uid";
const AUTHOR = "author-uid";
const REPORTER = "reporter-uid";

const REPORT_ID = `${REPORTER}_globalMessage_msg-1`;
const MESSAGE = "globalChat/main/messages/msg-1";
const REEL_ID = "reel-1";
const REEL_REPORT_ID = "reel-report-1";
const REEL = `reels/${REEL_ID}`;

function request(uid, role, data, token = {}) {
  return {
    auth: {
      uid,
      token: {
        role,
        auth_time: Math.floor(Date.now() / 1000),
        ...token,
      },
    },
    data,
  };
}

async function seedAccounts() {
  await Promise.all([
    db.doc(`users/${MOD}`).set({ uid: MOD, displayName: "Mod", role: "moderator" }),
    db.doc(`users/${ADMIN}`).set({ uid: ADMIN, displayName: "Admin", role: "superModerator" }),
    db.doc(`users/${PLAIN}`).set({ uid: PLAIN, displayName: "Plain", role: "user" }),
    // Claim says moderator, account is restricted.
    db.doc(`users/${BANNED_MOD}`).set({
      uid: BANNED_MOD,
      displayName: "Banned mod",
      role: "moderator",
      banned: true,
    }),
    // Claim still says moderator (stale token); the server record does
    // not. This is what makes a revocation effective immediately.
    db.doc(`users/${REVOKED_MOD}`).set({
      uid: REVOKED_MOD,
      displayName: "Revoked mod",
      role: "user",
    }),
    db.doc(`users/${DISABLED_MOD}`).set({
      uid: DISABLED_MOD,
      displayName: "Disabled mod",
      role: "moderator",
      disabled: true,
    }),
    db.doc(`users/${DELETED_FLAG_MOD}`).set({
      uid: DELETED_FLAG_MOD,
      displayName: "Deleted mod",
      role: "moderator",
      deleted: true,
    }),
    db.doc(`users/${DELETED_STATUS_MOD}`).set({
      uid: DELETED_STATUS_MOD,
      displayName: "Deleted mod",
      role: "moderator",
      status: "deleted",
    }),
    db.doc(`users/${CROSS_ROLE_MOD}`).set({
      uid: CROSS_ROLE_MOD,
      displayName: "Cross-role mod",
      role: "superModerator",
    }),
    db.doc(`users/${AUTHOR}`).set({ uid: AUTHOR, displayName: "Author" }),
  ]);
}

const EVIDENCE = {
  reporterId: REPORTER,
  targetType: "globalMessage",
  targetId: "msg-1",
  reportedUserId: AUTHOR,
  contextPath: MESSAGE,
  reason: "harassment",
  note: "kept it up all evening",
  status: "open",
};

async function seedReport(overrides = {}) {
  await db.doc(`reports/${REPORT_ID}`).set(
    { ...EVIDENCE, createdAt: FieldValue.serverTimestamp(), ...overrides },
    { merge: false },
  );
}

async function seedMessage(overrides = {}) {
  await db.doc(MESSAGE).set({
    senderId: AUTHOR,
    senderName: "Author",
    senderPhotoUrl: null,
    senderIsCreator: false,
    senderIsStaff: false,
    content: "the original message",
    sentAt: FieldValue.serverTimestamp(),
    isDeleted: false,
    deletedBy: null,
    deletedAt: null,
    ...overrides,
  });
}

async function seedReelReport(overrides = {}) {
  await db.doc(`reports/${REEL_REPORT_ID}`).set({
    reporterId: REPORTER,
    targetType: "reel",
    targetId: REEL_ID,
    reportedUserId: AUTHOR,
    contextPath: REEL,
    reason: "harassment",
    note: "reported Reel evidence",
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
    ...overrides,
  });
}

async function seedReel(overrides = {}) {
  await db.doc(REEL).set({
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId: AUTHOR,
    authorName: "Author",
    media: {
      kind: "image",
      contentType: "image/jpeg",
      size: 1024,
      generation: "123",
      durationMs: 0,
      storagePath: `reels/${AUTHOR}/${REEL_ID}/media.jpg`,
    },
    backingAudio: null,
    composition: {
      caption: "Reported evidence",
      crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
      filter: "original",
      trimStartMs: 0,
      trimEndMs: 0,
      textOverlays: [],
      linkOverlays: [],
      originalAudioVolume: 0,
      backingAudioVolume: 0,
      audioTrimStartMs: 0,
      audioRightsAttested: false,
      audioAttribution: "",
    },
    sortKey: `1778000000000_${REEL_ID}`,
    publishedAt: Timestamp.fromMillis(1778000000000),
    updatedAt: Timestamp.fromMillis(1778000000000),
    ...overrides,
  });
}

async function clearAudits() {
  const entries = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", REPORT_ID)
    .get();
  await Promise.all(entries.docs.map((entry) => entry.ref.delete()));
}

async function auditsForReport() {
  return db
    .collection("adminAuditLogs")
    .where("targetId", "==", REPORT_ID)
    .get();
}

async function expectRejection(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

describe("moderateReport", () => {
  beforeEach(async () => {
    await seedAccounts();
    await seedReport();
    await seedMessage();
    await clearAudits();
  });

  describe("authorization", () => {
    test("unauthenticated callers are denied", async () => {
      await expectRejection(
        run({ auth: null, data: { reportId: REPORT_ID, action: "claim" } }),
        "unauthenticated",
      );
    });

    test("an ordinary user is denied", async () => {
      await expectRejection(
        run(request(PLAIN, "user", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-plain-1",
        })),
        "permission-denied",
      );
    });

    test("an unsupported role (vip) is denied", async () => {
      await expectRejection(
        run(request(PLAIN, "vip", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-vip-1",
        })),
        "permission-denied",
      );
    });

    test("a stale moderator sign-in cannot mutate report workflow", async () => {
      await assert.rejects(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-stale-auth-1",
        }, {
          auth_time: Math.floor(Date.now() / 1000) - (5 * 60) - 1,
        })),
        (error) => {
          assert.equal(error.code, "failed-precondition");
          assert.equal(
            error.details?.reason,
            "recent-authentication-required",
          );
          return true;
        },
      );

      const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
      assert.equal(report.status, "open");
      assert.equal(report.assignedTo, undefined);
      assert.equal((await auditsForReport()).size, 0);
    });

    test("a BANNED moderator is denied", async () => {
      await expectRejection(
        run(request(BANNED_MOD, "moderator", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-banned-1",
        })),
        "permission-denied",
      );
    });

    test("a REVOKED moderator holding a stale token is denied — the "
      + "server record is what counts", async () => {
      await expectRejection(
        run(request(REVOKED_MOD, "moderator", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-revoked-1",
        })),
        "permission-denied",
      );
    });

    test("disabled, deleted and cross-role moderators are denied", async () => {
      for (const [uid, role] of [
        [DISABLED_MOD, "moderator"],
        [DELETED_FLAG_MOD, "moderator"],
        [DELETED_STATUS_MOD, "moderator"],
        [CROSS_ROLE_MOD, "moderator"],
      ]) {
        await expectRejection(
          run(request(uid, role, {
            reportId: REPORT_ID,
            action: "claim",
            requestId: `req-${uid}`,
          })),
          "permission-denied",
        );
      }
    });

    test("a moderator is accepted", async () => {
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "claim",
        requestId: "req-mod-ok",
      }));
      assert.equal(result.status, "inReview");
    });

    test("a super moderator is accepted", async () => {
      const result = await run(request(ADMIN, "superModerator", {
        reportId: REPORT_ID,
        action: "claim",
        requestId: "req-admin-ok",
      }));
      assert.equal(result.status, "inReview");
    });
  });

  describe("validation", () => {
    test("a malformed report id is rejected before anything is read",
      async () => {
        await expectRejection(
          run(request(MOD, "moderator", {
            reportId: "../../users/admin-uid",
            action: "claim",
            requestId: "req-bad-id",
          })),
          "invalid-argument",
        );
      });

    test("an unknown action is rejected", async () => {
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "banEveryone",
          requestId: "req-bad-action",
        })),
        "invalid-argument",
      );
    });

    test("a request id cannot escape the canonical audit collection",
      async () => {
        await expectRejection(
          run(request(MOD, "moderator", {
            reportId: REPORT_ID,
            action: "claim",
            requestId: "unsafe/audit-id",
          })),
          "invalid-argument",
        );

        const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
        assert.equal(report.status, "open");
        assert.equal(report.lastRequestId, undefined);
        assert.equal((await auditsForReport()).size, 0);
      });

    test("report and request ids are rejected before trimming or truncation",
      async () => {
        const reportPrefix = "r".repeat(256);
        const requestPrefix = "q".repeat(64);
        const cases = [
          {
            reportId: ` ${REPORT_ID}`,
            requestId: "req-no-trim-1",
          },
          {
            reportId: `${reportPrefix}extra`,
            requestId: "req-no-truncate-report",
          },
          {
            reportId: REPORT_ID,
            requestId: " req-no-trim-2",
          },
          {
            reportId: REPORT_ID,
            requestId: `${requestPrefix}extra`,
          },
        ];

        for (const input of cases) {
          await expectRejection(
            run(request(MOD, "moderator", {
              ...input,
              action: "claim",
            })),
            "invalid-argument",
          );
        }

        const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
        assert.equal(report.status, "open");
        assert.equal(report.lastRequestId, undefined);
        assert.equal((await auditsForReport()).size, 0);
      });

    test("closing without a valid resolution is rejected", async () => {
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "resolve",
          requestId: "req-no-resolution",
        })),
        "invalid-argument",
      );
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "dismiss",
          requestId: "req-bad-resolution",
          resolution: "becauseISaidSo",
        })),
        "invalid-argument",
      );
    });

    test("a missing report is reported as not-found", async () => {
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: "nobody_globalMessage_nothing",
          action: "claim",
          requestId: "req-missing",
        })),
        "not-found",
      );
    });
  });

  describe("workflow", () => {
    test("an invalid transition is refused", async () => {
      // release requires inReview; the report is open.
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "release",
          requestId: "req-bad-transition",
        })),
        "failed-precondition",
      );
    });

    test("a report already resolved cannot be resolved again", async () => {
      await seedReport({ status: "resolved", resolvedBy: MOD });
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "resolve",
          requestId: "req-already",
          resolution: "noActionNeeded",
        })),
        "failed-precondition",
      );
    });

    test("one moderator cannot take over another's active review",
      async () => {
        await run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-first-claim",
        }));
        await expectRejection(
          run(request(ADMIN, "superModerator", {
            reportId: REPORT_ID,
            action: "resolve",
            requestId: "req-steal",
            resolution: "noActionNeeded",
          })),
          "aborted",
        );
      });

    test("the claiming moderator can resolve their own review", async () => {
      await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "claim",
        requestId: "req-claim-then",
      }));
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "resolve",
        requestId: "req-resolve-own",
        resolution: "warningIssued",
        moderatorNote: "spoke to them",
      }));
      assert.equal(result.status, "resolved");

      const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
      assert.equal(report.resolvedBy, MOD);
      assert.equal(report.resolution, "warningIssued");
      assert.equal(report.resolutionNote, "spoke to them");
    });

    test("a repeated request with the same requestId is idempotent",
      async () => {
        const payload = {
          reportId: REPORT_ID,
          action: "resolve",
          requestId: "req-idempotent",
          resolution: "noActionNeeded",
        };
        const first = await run(request(MOD, "moderator", payload));
        const second = await run(request(MOD, "moderator", payload));
        const third = await run(request(MOD, "moderator", payload));

        assert.equal(first.replayed, false);
        assert.equal(second.replayed, true);
        assert.equal(third.replayed, true);
        assert.equal(second.status, "resolved");

        const audits = await auditsForReport();
        assert.equal(audits.size, 1, "one action, one audit record");
      });
  });

  describe("content removal", () => {
    test("remove-and-resolve soft deletes the message and closes the "
      + "report in one step", async () => {
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "removeAndResolve",
        requestId: "req-remove-1",
        resolution: "contentRemoved",
      }));
      assert.equal(result.status, "resolved");
      assert.equal(result.contentRemoved, true);

      const message = (await db.doc(MESSAGE).get()).data();
      assert.equal(message.isDeleted, true, "soft deleted, never removed");
      assert.equal(message.deletedBy, MOD);
      assert.equal(message.content, "");
      // Authorship evidence survives.
      assert.equal(message.senderId, AUTHOR);

      const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
      assert.equal(report.status, "resolved");
      assert.equal(report.contentRemoved, true);
    });

    test("a message already removed is handled safely and not "
      + "re-deleted", async () => {
      await seedMessage({
        isDeleted: true,
        deletedBy: "someone-else",
        content: "",
      });
      const result = await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "removeAndResolve",
        requestId: "req-remove-again",
        resolution: "contentRemoved",
      }));
      assert.equal(result.status, "resolved");
      assert.equal(
        result.contentRemoved,
        false,
        "no second removal, so no second moderation audit",
      );
      const message = (await db.doc(MESSAGE).get()).data();
      assert.equal(message.deletedBy, "someone-else", "not re-attributed");
    });

    test("a vanished target message fails the action instead of "
      + "half-resolving", async () => {
      await db.doc(MESSAGE).delete();
      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "removeAndResolve",
          requestId: "req-remove-gone",
          resolution: "contentRemoved",
        })),
        "failed-precondition",
      );
      const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
      assert.equal(report.status, "open", "the report did not move");
    });

    test("remove-and-resolve hides a canonical Reel and closes its report "
      + "atomically without deleting evidence", async () => {
      await seedReelReport();
      await seedReel();
      const before = (await db.doc(REEL).get()).data();

      const result = await run(request(MOD, "moderator", {
        reportId: REEL_REPORT_ID,
        action: "removeAndResolve",
        requestId: "req-hide-reel-1",
        resolution: "contentRemoved",
      }));

      assert.equal(result.status, "resolved");
      assert.equal(result.contentRemoved, true);

      const reelSnapshot = await db.doc(REEL).get();
      assert.equal(reelSnapshot.exists, true, "evidence document survives");
      const reel = reelSnapshot.data();
      assert.equal(reel.moderationStatus, "hidden");
      assert.equal(reel.status, "published");
      assert.equal(reel.authorId, AUTHOR);
      assert.deepEqual(reel.media, before.media, "media evidence is untouched");
      assert.deepEqual(
        reel.composition,
        before.composition,
        "composition evidence is untouched",
      );
      assert.ok(reel.updatedAt instanceof Timestamp);
      assert.ok(reel.updatedAt.toMillis() >= before.updatedAt.toMillis());

      const report = (await db.doc(`reports/${REEL_REPORT_ID}`).get()).data();
      assert.equal(report.status, "resolved");
      assert.equal(report.contentRemoved, true);
      assert.equal(report.targetId, REEL_ID, "reporter evidence is immutable");
      assert.equal(report.reportedUserId, AUTHOR);
    });

    test("a forged Reel report cannot hide another author's Reel or close "
      + "the report", async () => {
      await seedReel();
      await seedReelReport({ reportedUserId: "different-author" });

      await expectRejection(
        run(request(MOD, "moderator", {
          reportId: REEL_REPORT_ID,
          action: "removeAndResolve",
          requestId: "req-forged-reel",
          resolution: "contentRemoved",
        })),
        "failed-precondition",
      );

      assert.equal((await db.doc(REEL).get()).data().moderationStatus, "visible");
      assert.equal(
        (await db.doc(`reports/${REEL_REPORT_ID}`).get()).data().status,
        "open",
        "target validation and workflow update share one transaction",
      );
    });

    test("a Reel report cannot redirect moderation through a crafted target "
      + "id or context path", async () => {
      await seedReel();
      const craftedCases = [
        {
          targetId: "../users/admin-uid",
          contextPath: "reels/../users/admin-uid",
        },
        { targetId: REEL_ID, contextPath: `users/${AUTHOR}` },
      ];

      for (const [index, crafted] of craftedCases.entries()) {
        await seedReelReport(crafted);
        await expectRejection(
          run(request(MOD, "moderator", {
            reportId: REEL_REPORT_ID,
            action: "removeAndResolve",
            requestId: `req-reel-path-${index}`,
            resolution: "contentRemoved",
          })),
          "failed-precondition",
        );
        assert.equal(
          (await db.doc(REEL).get()).data().moderationStatus,
          "visible",
        );
        assert.equal(
          (await db.doc(`reports/${REEL_REPORT_ID}`).get()).data().status,
          "open",
        );
      }
    });

    test("a missing, tombstoned or non-canonical Reel fails closed without "
      + "half-resolving", async () => {
      const cases = [
        { label: "missing", seed: null },
        { label: "tombstoned", seed: { status: "deleted" } },
        { label: "unknown schema", seed: { schemaVersion: 2 } },
      ];

      for (const [index, entry] of cases.entries()) {
        await db.doc(REEL).delete();
        await seedReelReport({ status: "open" });
        if (entry.seed !== null) await seedReel(entry.seed);

        await expectRejection(
          run(request(MOD, "moderator", {
            reportId: REEL_REPORT_ID,
            action: "removeAndResolve",
            requestId: `req-reel-invalid-${index}`,
            resolution: "contentRemoved",
          })),
          "failed-precondition",
        );
        assert.equal(
          (await db.doc(`reports/${REEL_REPORT_ID}`).get()).data().status,
          "open",
          `${entry.label} target half-resolved the report`,
        );
      }
    });

    test("an already-hidden canonical Reel is not rewritten or re-attributed",
      async () => {
        const hiddenAt = Timestamp.fromMillis(1777000000000);
        await seedReel({ moderationStatus: "hidden", updatedAt: hiddenAt });
        await seedReelReport();

        const result = await run(request(MOD, "moderator", {
          reportId: REEL_REPORT_ID,
          action: "removeAndResolve",
          requestId: "req-reel-already-hidden",
          resolution: "contentRemoved",
        }));

        assert.equal(result.status, "resolved");
        assert.equal(result.contentRemoved, false);
        assert.equal((await db.doc(REEL).get()).data().updatedAt.toMillis(),
          hiddenAt.toMillis());
      });
  });

  describe("evidence and audit", () => {
    test("reporter-created evidence is never modified", async () => {
      await run(request(MOD, "moderator", {
        reportId: REPORT_ID,
        action: "dismiss",
        requestId: "req-evidence",
        resolution: "notAViolation",
      }));
      const report = (await db.doc(`reports/${REPORT_ID}`).get()).data();
      for (const [key, value] of Object.entries(EVIDENCE)) {
        if (key === "status") continue;
        assert.deepEqual(report[key], value, `${key} was altered`);
      }
    });

    test("an audit entry records the transition, actor and outcome",
      async () => {
        await run(request(MOD, "moderator", {
          reportId: REPORT_ID,
          action: "dismiss",
          requestId: "req-audit-shape",
          resolution: "duplicate",
        }));
        const audits = await auditsForReport();
        assert.equal(audits.size, 1);

        const entry = audits.docs[0];
        assert.equal(
          entry.id,
          moderationAuditId(REPORT_ID, "req-audit-shape"),
        );
        const data = entry.data();
        assert.equal(data.actorId, MOD);
        assert.equal(data.action, "report_dismiss");
        assert.equal(data.targetType, "report");
        assert.equal(data.targetId, REPORT_ID);
        assert.equal(data.details.previousStatus, "open");
        assert.equal(data.details.newStatus, "dismissed");
        assert.equal(data.details.resolution, "duplicate");
        assert.equal(data.details.contentRemoved, false);
        // No credentials, no private profile data.
        assert.equal(data.details.email, undefined);
      });

    test("a read-only failure creates no audit entry", async () => {
      await expectRejection(
        run(request(PLAIN, "user", {
          reportId: REPORT_ID,
          action: "claim",
          requestId: "req-denied-audit",
        })),
        "permission-denied",
      );
      assert.equal((await auditsForReport()).size, 0);
    });
  });

  test("the export is discoverable from functions/index.js", () => {
    const catalogue = require("../index.js");
    assert.equal(typeof catalogue.moderateReport, "function");
    const endpoint = catalogue.moderateReport.__endpoint;
    assert.ok(endpoint, "no trigger metadata on the export");
    assert.equal(endpoint.region?.[0] ?? endpoint.region, "europe-west1");
    assert.ok(endpoint.callableTrigger, "must be a callable");
  });
});
