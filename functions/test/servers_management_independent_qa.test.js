"use strict";

// Independent QA for the management parity slice (ADR-F). Pure: no SDK, no
// emulator, no clock, no network. It deliberately does NOT re-test the
// behaviour servers_management.test.js proves against a live emulator; it
// tests the claims that would otherwise be true only in a comment:
//
//   - the ADR-F capability flags the migration engine now refuses against are
//     backed by real, registered callables and real staff adapters, so a flag
//     cannot survive its callable being deleted or renamed;
//   - the five new outbox kinds are accepted by the reviewed worker in their
//     canonical shape and refused in every malformed one;
//   - the ban field is validated, never read as truthy — the string-vs-boolean
//     confusion already CONFIRMED against the migration engine's `isPrivate`.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const {
  V1_MANAGEMENT_CAPABILITIES, managementParityExists,
} = require("../servers/migration_apply");
const { SERVER_CALLABLE_METHODS, CONVERGENCE_KINDS, OUTBOX_KINDS } = require("../servers/registration");
const { REMOVAL_ROLES, createServerManagementService, managedMember } = require("../servers/management");
const { MODERATOR_ROLES } = require("../servers/authority");
const { validateConvergenceJob } = require("../servers/convergence_runtime");
const { deletionCleanupState } = require("../servers/content_cleanup");

const ADMIN_CLUBS = path.join(__dirname, "..", "admin", "clubs.js");
const DOCS_SERVERS = path.join(__dirname, "..", "..", "docs", "Servers.md");

const ADR_F_CALLABLES = Object.freeze(["removeServerMemberV1", "setServerMemberBanV1", "deleteServerV1"]);
const STAFF_ADAPTERS = Object.freeze([
  "staffSetServerModerationStatus", "staffRemoveServerMember",
  "staffSetServerMemberBan", "staffDeleteServer",
]);

function service() {
  return createServerManagementService({
    db: { runTransaction: async () => {}, doc: () => ({}), collection: () => ({}) },
    Timestamp: { fromMillis: (millis) => ({ millis }) },
    clock: () => 1_900_000_000_000,
  });
}

const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);

test("QA ADR-F: every management capability flag is backed by a registered callable or a real staff adapter", () => {
  assert.deepEqual(
    Object.keys(V1_MANAGEMENT_CAPABILITIES).sort(),
    ["adminSurface", "banMember", "deleteServer", "removeMember"],
  );
  assert.equal(managementParityExists(), true);
  // A flag that stays true after its surface disappears would be worse than
  // no flag, so each one is checked against the real registration table.
  for (const name of ADR_F_CALLABLES) {
    assert.equal(SERVER_CALLABLE_METHODS[name], "management", name);
    assert.equal(typeof service()[name], "function", name);
  }
  for (const name of STAFF_ADAPTERS) {
    assert.equal(typeof service()[name], "function", name);
    // A staff adapter is deliberately NOT a callable: staff authentication,
    // step-up and the audit log stay with admin/clubs.js.
    assert.equal(Object.hasOwn(SERVER_CALLABLE_METHODS, name), false, name);
  }
});

test("QA ADR-F: the flag is a computed gate, not a constant — any false capability refuses migration", () => {
  for (const key of Object.keys(V1_MANAGEMENT_CAPABILITIES)) {
    assert.equal(managementParityExists({ ...V1_MANAGEMENT_CAPABILITIES, [key]: false }), false, key);
  }
  assert.equal(managementParityExists({}), true, "an empty registry vacuously passes; the real one is never empty");
});

test("QA ADR-F: the legacy admin surface really delegates the four staff verbs on a versioned root", () => {
  const source = fs.readFileSync(ADMIN_CLUBS, "utf8");
  for (const name of STAFF_ADAPTERS) {
    assert.ok(source.includes(`serverManagement().${name}(`), `admin/clubs.js must delegate ${name}`);
  }
  // The delegation must be reached through the versioned test, not by having
  // quietly dropped the legacy boundary: both must still be present.
  assert.ok(source.includes("isVersionedServer("), "the versioned branch selector must remain");
  assert.ok(source.includes("assertLegacyClubData("), "the legacy boundary must remain for legacy roots");
  // Staff ownership transfer is the ONE admin verb still legacy-only. If that
  // ever changes, this assertion is the reminder to move the report with it.
  const transfer = source.slice(source.indexOf("const transferClubOwnership = onCall("));
  assert.ok(transfer.includes("assertLegacyClubData(preflightClub)"),
    "transferClubOwnership still refuses a versioned root; the report documents that gap");
});

test("QA authority: removal and ban reuse Club's four removal-capable roles, by reference and not by a second list", () => {
  assert.deepEqual([...REMOVAL_ROLES], [...MODERATOR_ROLES]);
  assert.deepEqual([...REMOVAL_ROLES].sort(), ["admin", "coOwner", "moderator", "owner"]);
});

test("QA contract: the three new callables are documented, and the docs order is the registration order", () => {
  const lines = fs.readFileSync(DOCS_SERVERS, "utf8").split("\n");
  const start = lines.findIndex((line) => /^#{1,6} .*Callable contract/u.test(line));
  const names = [];
  for (const line of lines.slice(start + 1)) {
    if (/^#{1,6} /u.test(line)) break;
    const match = /^\| `([A-Za-z]+V1)` \|/u.exec(line);
    if (match) names.push(match[1]);
  }
  assert.deepEqual(names, Object.keys(SERVER_CALLABLE_METHODS));
  for (const name of ADR_F_CALLABLES) assert.ok(names.includes(name), name);
});

const SERVER = "srv_0123456789abcdef0123456789abcdef01234567";

function memberJob(kind, changes = {}) {
  return {
    schemaVersion: 1, kind, serverId: SERVER, userId: "member-uid", membershipRevision: 2,
    operationId: "op", status: "pending", cursor: null, convergenceVersion: 1, rtcTargets: [],
    grantStatus: "completed", grantCursor: null, rtcStatus: "completed", rtcTargetIndex: 0,
    rtcRecipientCursor: null, bridgeLeaseId: null, bridgeLeaseExpiresAtMillis: 0,
    retryAfterMillis: 0, lastErrorCode: null, contentCleanupPending: false, ...changes,
  };
}

function serverJob(kind, changes = {}) {
  const { userId, membershipRevision, ...rest } = memberJob(kind);
  const cleanup = kind === "serverDelete" ? {
    requestedBy: "owner-uid",
    ...deletionCleanupState("serverDelete", { deletionRevision: 2, ownerId: "owner-uid" }),
  } : {};
  return { ...rest, contentCleanupPending: kind === "serverDelete", ...cleanup, ...changes };
}

test("QA outbox: the five management kinds are routable and accepted by the reviewed worker in canonical shape", () => {
  for (const kind of ["memberRemoved", "memberBanned", "memberBanLifted", "serverModeration", "serverDelete"]) {
    assert.ok(CONVERGENCE_KINDS.includes(kind), kind);
    assert.ok(OUTBOX_KINDS.includes(kind), kind);
  }
  for (const kind of ["memberRemoved", "memberBanned", "memberBanLifted"]) {
    assert.equal(validateConvergenceJob(memberJob(kind), "op").kind, kind);
    // A member kind without the member it names is not a member kind.
    rejects(() => validateConvergenceJob(memberJob(kind, { userId: undefined }), "op"), "invalid-argument");
  }
  for (const kind of ["serverModeration", "serverDelete"]) {
    assert.equal(validateConvergenceJob(serverJob(kind), "op").kind, kind);
    // A server-scoped job names no channel: a forged channelId is refused
    // rather than quietly narrowing the target-mode check.
    rejects(() => validateConvergenceJob(serverJob(kind, { channelId: "ch_x" }), "op"), "failed-precondition");
  }
});

test("QA outbox: content cleanup is fenced to deletion jobs and cannot read as completed while pending", () => {
  assert.equal(validateConvergenceJob(serverJob("serverDelete"), "op").contentCleanupPending, true);
  for (const kind of ["memberRemoved", "memberBanned", "memberBanLifted", "serverModeration"]) {
    rejects(() => validateConvergenceJob(
      kind === "serverModeration"
        ? serverJob(kind, { contentCleanupPending: true })
        : memberJob(kind, { contentCleanupPending: true }),
      "op",
    ), "failed-precondition");
  }
  // `status: completed` with content cleanup still pending is the state that would let
  // a deletion be reported as finished while its content is untouched.
  rejects(() => validateConvergenceJob(
    serverJob("serverDelete", { status: "completed" }), "op",
  ), "failed-precondition");
});

test("QA ban field: `banned` is validated as a boolean, never read as truthy", () => {
  const server = { ownerId: "owner-uid" };
  const snapshot = (data) => ({ exists: true, data: () => data });
  const base = { userId: "member-uid", role: "member", authorizationRevision: 1 };
  assert.equal(managedMember(snapshot(base), "member-uid", server).banned, undefined);
  assert.equal(managedMember(snapshot({ ...base, banned: true }), "member-uid", server).banned, true);
  assert.equal(managedMember(snapshot({ ...base, banned: false }), "member-uid", server).banned, false);
  // "true", 1 and {} are reconciliation, not a ban and not an absence of one.
  for (const value of ["true", "false", 1, 0, {}, []]) {
    rejects(() => managedMember(snapshot({ ...base, banned: value }), "member-uid", server), "data-loss");
  }
  // Everything canonicalMember refuses, this refuses identically.
  for (const change of [
    { userId: "other" }, { role: "nope" }, { authorizationRevision: 0 }, { role: "owner" },
  ]) {
    rejects(() => managedMember(snapshot({ ...base, ...change }), "member-uid", server), "permission-denied");
  }
  rejects(() => managedMember({ exists: false }, "member-uid", server), "permission-denied");
  // The owner role must agree with the root's ownerId in BOTH directions.
  rejects(() => managedMember(snapshot({ ...base, userId: "owner-uid" }), "owner-uid", server), "permission-denied");
});
