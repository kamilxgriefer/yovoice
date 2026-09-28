// ADR-230: the appConfig/likersV1 switch, the likers budgets and the gate, in
// the normative admission order (activation -> budgets -> gate).
const assert = require("node:assert/strict");
const { describe, test } = require("node:test");
const { HttpsError } = require("firebase-functions/v2/https");

const { rateLimitReference } = require("../integrity/guards");
const {
  LIKERS_ACTIVATION_PATH,
  LIKERS_SURFACES,
  canonicalLikersActivation,
  likersSurfaceEnabled,
} = require("../engagement/likers_activation");
const {
  LIKERS_ADMISSION_READS,
  LIKERS_RATE_LIMITS,
  admitLikersList,
} = require("../engagement/likers_admission");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
const { tracked } = require("./helpers/read_tracker");

const NOW_MS = 1_820_000_000_000;
const CALLER = "caller-uid-1";

function timingAt(nowMs) {
  return { nowMs, now: new Date(nowMs) };
}

function activation(overrides = {}) {
  return {
    schemaVersion: 1,
    enabled: true,
    serverMessagesEnabled: true,
    updatedAt: new Date(NOW_MS - 1_000),
    ...overrides,
  };
}

function testerGrant() {
  return {
    source: "testerProgram",
    expiresAt: null,
    revoked: false,
    grantedBy: "owner-console",
  };
}

function world({ config = activation(), user = { role: "user" }, grant = testerGrant() } = {}) {
  const db = new InMemoryFirestore();
  if (config !== null) db.seed(LIKERS_ACTIVATION_PATH, config);
  if (user !== null) db.seed(`users/${CALLER}`, user);
  if (grant !== null) db.seed(`vipGrants/${CALLER}`, grant);
  return db;
}

function logger() {
  const warnings = [];
  return { warnings, warn: (message, data) => warnings.push([message, data]) };
}

function rateCount(db, scope) {
  return db.data(rateLimitReference(db, scope, CALLER).path)?.count ?? 0;
}

async function admit(db, { surface = LIKERS_SURFACES.CONTENT, nowMs = NOW_MS, log = logger(), token = {} } = {}) {
  return admitLikersList({
    db,
    auth: { uid: CALLER, token },
    surface,
    timing: timingAt(nowMs),
    logger: log,
  });
}

function refusal(code, reason) {
  return (error) => {
    assert.ok(error instanceof HttpsError, String(error));
    assert.equal(error.code, code);
    if (reason !== undefined) assert.deepEqual(error.details, { reason });
    return true;
  };
}

describe("appConfig/likersV1 is fail closed", () => {
  const snapshot = (data) => ({ exists: data !== undefined, data: () => data });

  test("only the exact shape enables anything", () => {
    assert.deepEqual(
      { ...canonicalLikersActivation(snapshot(activation())) },
      { enabled: true, serverMessagesEnabled: true },
    );
    const disabled = {
      missing: undefined,
      listedSinceNull: activation({ listedSince: null }),
      listedSinceDate: activation({ listedSince: new Date(NOW_MS) }),
      extraKey: activation({ note: "on" }),
      missingServerSwitch: (() => {
        const data = activation();
        delete data.serverMessagesEnabled;
        return data;
      })(),
      missingUpdatedAt: (() => {
        const data = activation();
        delete data.updatedAt;
        return data;
      })(),
      stringEnabled: activation({ enabled: "true" }),
      numberServerSwitch: activation({ serverMessagesEnabled: 1 }),
      schemaVersion2: activation({ schemaVersion: 2 }),
      stringUpdatedAt: activation({ updatedAt: "2026-09-28" }),
      array: [],
    };
    for (const [label, data] of Object.entries(disabled)) {
      const result = canonicalLikersActivation(snapshot(data));
      assert.equal(likersSurfaceEnabled(result, LIKERS_SURFACES.CONTENT), false, label);
      assert.equal(
        likersSurfaceEnabled(result, LIKERS_SURFACES.SERVER_MESSAGE),
        false,
        label,
      );
    }
  });

  test("the server switch needs the master switch", () => {
    const serverOnly = canonicalLikersActivation(
      snapshot(activation({ enabled: false, serverMessagesEnabled: true })),
    );
    assert.equal(likersSurfaceEnabled(serverOnly, LIKERS_SURFACES.SERVER_MESSAGE), false);
    const contentOnly = canonicalLikersActivation(
      snapshot(activation({ serverMessagesEnabled: false })),
    );
    assert.equal(likersSurfaceEnabled(contentOnly, LIKERS_SURFACES.CONTENT), true);
    assert.equal(likersSurfaceEnabled(contentOnly, LIKERS_SURFACES.SERVER_MESSAGE), false);
  });

  test("a missing or malformed switch refuses BEFORE any budget, gate or content read", async () => {
    for (const config of [null, activation({ enabled: false }), activation({ listedSince: null })]) {
      const base = world({ config });
      const probe = tracked(base);
      await assert.rejects(
        admit(probe.db),
        refusal("failed-precondition", "likersNotEnabled"),
      );
      assert.deepEqual(probe.reads, [LIKERS_ACTIVATION_PATH]);
      assert.equal(probe.transactionCount(), 0);
      assert.equal(rateCount(base, "likers.list"), 0);
    }
  });

  test("serverMessagesEnabled:false refuses only the server surface", async () => {
    const db = world({ config: activation({ serverMessagesEnabled: false }) });
    await assert.rejects(
      admit(db, { surface: LIKERS_SURFACES.SERVER_MESSAGE }),
      refusal("failed-precondition", "likersNotEnabled"),
    );
    assert.equal(rateCount(db, "likers.list"), 0);
    const admitted = await admit(db, { surface: LIKERS_SURFACES.CONTENT });
    assert.equal(admitted.access.source, "vipGrant");
  });

  test("an unknown surface is a programming error", async () => {
    await assert.rejects(admit(world(), { surface: "dm" }), TypeError);
  });
});

describe("likers budgets", () => {
  test("the three scopes and limits are pinned", () => {
    assert.deepEqual(JSON.parse(JSON.stringify(LIKERS_RATE_LIMITS)), {
      "likers.list": { maxEvents: 10, windowMs: 60_000 },
      "likers.listHourly": { maxEvents: 120, windowMs: 3_600_000 },
      "likers.listDaily": { maxEvents: 500, windowMs: 86_400_000 },
    });
  });

  test("10 per minute, then resource-exhausted with a uid-free warning", async () => {
    const db = world();
    for (let call = 0; call < 10; call += 1) await admit(db);
    const log = logger();
    await assert.rejects(admit(db, { log }), refusal("resource-exhausted"));
    assert.deepEqual(log.warnings, [["likers budget exhausted", { scope: "likers.list" }]]);
    assert.ok(!JSON.stringify(log.warnings).includes(CALLER));
    // The next minute is a new window.
    await admit(db, { nowMs: NOW_MS + 60_000 });
  });

  test("120 per hour and 500 per day, all-or-nothing", async () => {
    for (const [scope, maxEvents] of [["likers.listHourly", 120], ["likers.listDaily", 500]]) {
      const db = world();
      const reference = rateLimitReference(db, scope, CALLER);
      db.seed(reference.path, {
        schemaVersion: 1,
        ownerId: CALLER,
        scope,
        windowStartedAt: new Date(NOW_MS - 1_000),
        count: maxEvents,
        updatedAt: new Date(NOW_MS - 1_000),
      });
      const log = logger();
      await assert.rejects(admit(db, { log }), refusal("resource-exhausted"), scope);
      assert.deepEqual(log.warnings, [["likers budget exhausted", { scope }]]);
      // The refused call wrote nothing: the per-minute budget is untouched.
      assert.equal(rateCount(db, "likers.list"), 0, scope);
      assert.equal(rateCount(db, scope), maxEvents, scope);
    }
  });

  test("the only transaction reads and writes privateRateLimits alone", async () => {
    const base = world();
    const probe = tracked(base);
    await admit(probe.db);
    assert.equal(probe.transactionCount(), 1);
    assert.equal(probe.transactionReads.length, 3);
    assert.ok(probe.transactionReads.every((path) => path.startsWith("privateRateLimits/")));
    const written = base.paths().filter((path) => path.startsWith("privateRateLimits/"));
    assert.equal(written.length, 3);
    for (const scope of Object.keys(LIKERS_RATE_LIMITS)) {
      assert.equal(rateCount(base, scope), 1, scope);
    }
    // Voice `read` and Yeel `view` budgets are NOT charged.
    for (const scope of ["moment.read", "moment.readHourly", "reel.view"]) {
      assert.equal(base.data(rateLimitReference(base, scope, CALLER).path), undefined, scope);
    }
  });
});

describe("likers gate", () => {
  test("a caller without paid, VIP or staff access is refused after budgets, before content", async () => {
    const base = world({ grant: null });
    const probe = tracked(base);
    await assert.rejects(
      admit(probe.db),
      refusal("failed-precondition", "likersAccessRequired"),
    );
    assert.equal(rateCount(base, "likers.list"), 1);
    assert.deepEqual(probe.reads, [
      LIKERS_ACTIVATION_PATH,
      `users/${CALLER}`,
      `entitlements/${CALLER}`,
      `vipGrants/${CALLER}`,
      `restrictions/${CALLER}`,
    ]);
  });

  test("a non-canonical grant is refused", async () => {
    for (const grant of [{}, { ...testerGrant(), revoked: "true" }, { ...testerGrant(), revokedAt: new Date(NOW_MS) }]) {
      await assert.rejects(
        admit(world({ grant })),
        refusal("failed-precondition", "likersAccessRequired"),
      );
    }
  });

  test("staff preview needs the matching signed role", async () => {
    const db = world({ grant: null, user: { role: "moderator" } });
    const admitted = await admit(db, { token: { role: "moderator" } });
    assert.equal(admitted.access.source, "staffPreview");
    await assert.rejects(
      admit(db, { token: {} }),
      refusal("failed-precondition", "likersAccessRequired"),
    );
  });

  test("a canonical VIP grant is admitted with the caller's own snapshots", async () => {
    const admitted = await admit(world());
    assert.deepEqual({ ...admitted.access }, { allowed: true, source: "vipGrant" });
    assert.equal(admitted.callerProfile.exists, true);
    assert.equal(admitted.callerRestriction.exists, false);
    assert.equal(LIKERS_ADMISSION_READS, 8);
  });

  test("the caller's own suspension or mute propagates as-is", async () => {
    await assert.rejects(
      admit(world({ user: { role: "user", banned: true } })),
      (error) => error.code === "permission-denied" &&
        /Your account is not active/u.test(error.message),
    );
    await assert.rejects(
      admit(world({ user: null })),
      (error) => error.code === "not-found",
    );
    const muted = world();
    muted.seed(`restrictions/${CALLER}`, {
      type: "communicationMute",
      expiresAt: new Date(NOW_MS + 60_000),
    });
    await assert.rejects(
      admit(muted),
      (error) => error.code === "permission-denied" &&
        /cannot communicate/u.test(error.message),
    );
  });
});
