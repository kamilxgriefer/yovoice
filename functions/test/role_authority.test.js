const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  persistRoleAuthoritySafely,
} = require("../utils/role_authority");
const { hasStaffPreviewAccess } = require("../utils/premium_access");

describe("direction-aware role authority", () => {
  test("an Auth failure revokes a stale moderator token and the retry converges", async () => {
    let mirrorRole = "moderator";
    let claimRole = "moderator";
    let failAuthWrite = true;
    const writes = [];

    const operation = () => persistRoleAuthoritySafely({
      uid: "target",
      email: "target@example.invalid",
      role: "user",
      previousRole: "moderator",
      assignedBy: "owner",
      existingClaims: { role: claimRole, retainedClaim: true },
      writeMirror: async ({ role, roleTransitionInProgress }) => {
        writes.push("mirror");
        assert.equal(roleTransitionInProgress, false);
        mirrorRole = role;
      },
      writeClaims: async (_uid, claims) => {
        writes.push("claims");
        assert.equal(claims.retainedClaim, true);
        if (failAuthWrite) throw new Error("injected Auth failure");
        claimRole = claims.role;
      },
    });

    await assert.rejects(operation, /injected Auth failure/);
    assert.deepEqual(writes, ["mirror", "claims"]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "moderator");
    assert.equal(
      hasStaffPreviewAccess({
        user: { role: mirrorRole },
        tokenRole: claimRole,
        requireTokenRole: true,
      }),
      false,
      "a stale moderator token must buy nothing after mirror-first demotion",
    );

    failAuthWrite = false;
    await operation();
    assert.deepEqual(writes, ["mirror", "claims", "mirror", "claims"]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "user");
  });

  test("a failed re-promotion cannot reactivate a historical moderator token", async () => {
    let mirrorRole = "user";
    let claimRole = "user";
    const historicalTokenRole = "moderator";
    const writes = [];

    await assert.rejects(
      persistRoleAuthoritySafely({
        uid: "target",
        role: "moderator",
        previousRole: "user",
        assignedBy: "owner",
        existingClaims: { role: claimRole },
        writeMirror: async ({ role }) => {
          writes.push("mirror");
          mirrorRole = role;
        },
        writeClaims: async () => {
          writes.push("claims");
          throw new Error("injected Auth failure");
        },
      }),
      /injected Auth failure/,
    );

    assert.deepEqual(writes, ["claims"]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "user");
    assert.equal(
      hasStaffPreviewAccess({
        user: { role: mirrorRole },
        tokenRole: historicalTokenRole,
        requireTokenRole: true,
      }),
      false,
      "the old moderator token must still mismatch the unpromoted mirror",
    );
  });

  test("a demotion mirror failure never changes the claim", async () => {
    let claimWrites = 0;
    await assert.rejects(
      persistRoleAuthoritySafely({
        uid: "target",
        role: "user",
        previousRole: "moderator",
        assignedBy: "owner",
        writeMirror: async () => {
          throw new Error("injected mirror failure");
        },
        writeClaims: async () => {
          claimWrites += 1;
        },
      }),
      /injected mirror failure/,
    );
    assert.equal(claimWrites, 0);
  });

  test("non-moderation staff demotion is mirror-first too", async () => {
    let mirrorRole = "support";
    let claimRole = "support";
    const writes = [];

    await assert.rejects(
      persistRoleAuthoritySafely({
        uid: "target",
        role: "user",
        previousRole: "support",
        assignedBy: "owner",
        existingClaims: { role: claimRole },
        writeMirror: async ({ role, roleTransitionInProgress }) => {
          writes.push(`mirror:${role}`);
          assert.equal(roleTransitionInProgress, false);
          mirrorRole = role;
        },
        writeClaims: async () => {
          writes.push("claims");
          throw new Error("injected support Auth failure");
        },
      }),
      /injected support Auth failure/,
    );

    assert.deepEqual(writes, ["mirror:user", "claims"]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "support");
    assert.notEqual(mirrorRole, claimRole);
  });

  test("a lateral privileged change neutralizes both ABA token directions", async () => {
    let mirrorRole = "support";
    let claimRole = "support";
    let failAuth = true;
    let failFinalMirror = false;
    const writes = [];

    const operation = () => persistRoleAuthoritySafely({
      uid: "target",
      role: "auditor",
      previousRole: claimRole,
      assignedBy: "owner",
      existingClaims: { role: claimRole },
      writeMirror: async ({ role, roleTransitionInProgress }) => {
        writes.push(`mirror:${role}:${roleTransitionInProgress}`);
        if (failFinalMirror && role === "auditor") {
          throw new Error("injected final mirror failure");
        }
        mirrorRole = role;
      },
      writeClaims: async (_uid, claims) => {
        writes.push("claims");
        if (failAuth) throw new Error("injected lateral Auth failure");
        claimRole = claims.role;
      },
    });

    await assert.rejects(operation, /injected lateral Auth failure/);
    assert.deepEqual(writes, ["mirror:user:true", "claims"]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "support");
    assert.notEqual(mirrorRole, "support", "old support token must mismatch");
    assert.notEqual(mirrorRole, "auditor", "historical auditor token must mismatch");

    failAuth = false;
    failFinalMirror = true;
    writes.length = 0;
    await assert.rejects(operation, /injected final mirror failure/);
    assert.deepEqual(writes, [
      "mirror:user:true",
      "claims",
      "mirror:auditor:false",
    ]);
    assert.equal(mirrorRole, "user");
    assert.equal(claimRole, "auditor");
    assert.notEqual(mirrorRole, claimRole, "new auditor token must mismatch");

    failFinalMirror = false;
    writes.length = 0;
    await operation();
    assert.deepEqual(writes, ["claims", "mirror:auditor:false"]);
    assert.equal(mirrorRole, "auditor");
    assert.equal(claimRole, "auditor");
  });
});
