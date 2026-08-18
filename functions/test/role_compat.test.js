// Compatibility layer for the staff vocabulary and effective VIP.
//
// The vocabulary is STRICT: the 2026-08 production dry run found zero
// legacy documents, so `vip` and `admin` acceptance was removed. Half of
// this suite pins the new shape; the other half pins that the retired
// values confer NOTHING — no acceptance, no VIP, no set membership.
//
// Pure unit tests: no emulator, no Firestore, no production data.

const assert = require("node:assert/strict");
const { test, describe, afterEach } = require("node:test");

const {
  USER_ROLES,
  STAFF_ROLES,
  ALLOWED_ROLES,
  ADMIN_CENTER_ROLES,
  USER_MANAGEMENT_ROLES,
  ROOM_MANAGEMENT_ROLES,
  PERMANENT_DELETE_ROLES,
  isProtectedOwnerUid,
  protectedOwnerConfigured,
  setProtectedOwnerUidForTests,
} = require("../utils/roles");

const {
  VIP_SOURCES,
  effectiveVip,
  grantIsActive,
} = require("../utils/entitlements");

const OWNER = "owner-uid-under-test";

afterEach(() => {
  setProtectedOwnerUidForTests(null);
  delete process.env.YOVOICE_PROTECTED_OWNER_UID;
});

describe("protected owner", () => {
  test("the configured uid is recognised", () => {
    setProtectedOwnerUidForTests(OWNER);
    assert.equal(protectedOwnerConfigured(), true);
    assert.equal(isProtectedOwnerUid(OWNER), true);
  });

  test("a different uid is NOT the owner", () => {
    setProtectedOwnerUidForTests(OWNER);
    assert.equal(isProtectedOwnerUid("someone-else"), false);
    assert.equal(isProtectedOwnerUid(""), false);
    assert.equal(isProtectedOwnerUid(null), false);
  });

  test("a MISSING secret fails closed — everything reads as protected", () => {
    setProtectedOwnerUidForTests(null);
    assert.equal(protectedOwnerConfigured(), false);
    // Fail closed: with no way to identify the owner, no account may be
    // demoted or banned, rather than every account becoming fair game.
    assert.equal(isProtectedOwnerUid("anyone"), true);
    assert.equal(isProtectedOwnerUid(OWNER), true);
  });

  test("an empty or whitespace secret is treated as missing", () => {
    setProtectedOwnerUidForTests("   ");
    assert.equal(protectedOwnerConfigured(), false);
    assert.equal(isProtectedOwnerUid("anyone"), true);
  });

  test("the uid comes from the environment when not injected", () => {
    process.env.YOVOICE_PROTECTED_OWNER_UID = OWNER;
    assert.equal(isProtectedOwnerUid(OWNER), true);
    assert.equal(isProtectedOwnerUid("nope"), false);
  });

  test("no email-based owner authorization remains", () => {
    const roles = require("../utils/roles");
    assert.equal(roles.SUPER_ADMIN_EMAIL, undefined);
    assert.equal(roles.isProtectedOwnerEmail, undefined);
  });
});

describe("staff vocabulary", () => {
  test("the final vocabulary is the seven roles, and excludes vip", () => {
    assert.deepEqual(
      [...STAFF_ROLES].sort(),
      [
        "auditor",
        "guideMaster",
        "moderator",
        "superAdmin",
        "superModerator",
        "support",
        "user",
      ],
    );
    assert.equal(STAFF_ROLES.has("vip"), false);
    assert.equal(STAFF_ROLES.has("admin"), false);
  });

  test("legacy values are NO LONGER accepted", () => {
    assert.equal(ALLOWED_ROLES.has("vip"), false);
    assert.equal(ALLOWED_ROLES.has("admin"), false);
  });

  test("no legacy vocabulary remains exported from the runtime", () => {
    const roles = require("../utils/roles");
    assert.equal(roles.LEGACY_ROLES, undefined);
    assert.equal(roles.LEGACY_ROLE_MIGRATION, undefined);
  });
});

describe("the retired admin tier holds nothing", () => {
  test("admin is in NO permission set", () => {
    for (const set of [
      ADMIN_CENTER_ROLES,
      USER_MANAGEMENT_ROLES,
      ROOM_MANAGEMENT_ROLES,
      PERMANENT_DELETE_ROLES,
    ]) {
      assert.equal(set.has("admin"), false);
    }
  });

  test("superModerator gets room deletion but not user management", () => {
    assert.equal(
      PERMANENT_DELETE_ROLES.has(USER_ROLES.SUPER_MODERATOR),
      true,
    );
    // It is senior room staff, but not a user manager.
    assert.equal(ADMIN_CENTER_ROLES.has(USER_ROLES.SUPER_MODERATOR), true);
    assert.equal(ROOM_MANAGEMENT_ROLES.has(USER_ROLES.SUPER_MODERATOR), true);
    assert.equal(PERMANENT_DELETE_ROLES.has(USER_ROLES.SUPER_ADMIN), true);
    // ...and it is not a user manager either.
    assert.equal(
      USER_MANAGEMENT_ROLES.has(USER_ROLES.SUPER_MODERATOR),
      false,
    );
  });

  test("moderator keeps exactly what it had", () => {
    assert.equal(ADMIN_CENTER_ROLES.has(USER_ROLES.MODERATOR), true);
    assert.equal(ROOM_MANAGEMENT_ROLES.has(USER_ROLES.MODERATOR), true);
    assert.equal(PERMANENT_DELETE_ROLES.has(USER_ROLES.MODERATOR), false);
    assert.equal(USER_MANAGEMENT_ROLES.has(USER_ROLES.MODERATOR), false);
  });

  test("the new non-moderation roles carry no legacy authority yet", () => {
    for (const role of [
      USER_ROLES.GUIDE_MASTER,
      USER_ROLES.SUPPORT,
      USER_ROLES.AUDITOR,
    ]) {
      assert.equal(ADMIN_CENTER_ROLES.has(role), false, role);
      assert.equal(ROOM_MANAGEMENT_ROLES.has(role), false, role);
      assert.equal(PERMANENT_DELETE_ROLES.has(role), false, role);
      assert.equal(USER_MANAGEMENT_ROLES.has(role), false, role);
    }
  });
});

describe("effective VIP", () => {
  test("an account with nothing is not VIP", () => {
    const result = effectiveVip({ user: { role: "user" } });
    assert.equal(result.vip, false);
    assert.deepEqual(result.sources, []);
    assert.equal(result.primarySource, null);
  });

  test("an absent grant is safe, not an error", () => {
    assert.equal(effectiveVip().vip, false);
    assert.equal(effectiveVip({ user: {}, grant: null }).vip, false);
    assert.equal(effectiveVip({ user: {}, grant: undefined }).vip, false);
  });

  test("source 1: an active premiumIdentity", () => {
    const result = effectiveVip({ user: { premiumIdentity: true } });
    assert.equal(result.vip, true);
    assert.equal(result.primarySource, VIP_SOURCES.SUBSCRIPTION);
  });

  test("the RETIRED vip role value confers nothing at all", () => {
    // Safe because production holds zero of these: the dry run proved it
    // before this acceptance was removed.
    const result = effectiveVip({ user: { role: "vip" } });
    assert.equal(result.vip, false);
    assert.deepEqual(result.sources, []);
    assert.equal(VIP_SOURCES.LEGACY_ROLE, undefined);
  });

  test("source 2: a non-expiring complimentary grant", () => {
    const result = effectiveVip({
      user: { role: "user" },
      grant: { source: "adminGrant", expiresAt: null },
    });
    assert.equal(result.vip, true);
    assert.equal(result.primarySource, VIP_SOURCES.ADMIN_GRANT);
  });

  test("paid Premium stays DISTINGUISHABLE from a complimentary grant", () => {
    const paid = effectiveVip({ user: { premiumIdentity: true } });
    const comp = effectiveVip({ user: {}, grant: { expiresAt: null } });
    assert.equal(paid.primarySource, VIP_SOURCES.SUBSCRIPTION);
    assert.equal(comp.primarySource, VIP_SOURCES.ADMIN_GRANT);
    assert.notEqual(paid.primarySource, comp.primarySource);

    // Holding both reports both, and attributes to the subscription.
    const both = effectiveVip({
      user: { premiumIdentity: true },
      grant: { expiresAt: null },
    });
    assert.deepEqual(both.sources.sort(), ["adminGrant", "subscription"]);
    assert.equal(both.primarySource, VIP_SOURCES.SUBSCRIPTION);
  });

  test("an expired grant confers nothing", () => {
    const result = effectiveVip({
      user: {},
      grant: { expiresAt: new Date(Date.now() - 1000) },
    });
    assert.equal(result.vip, false);
  });

  test("a revoked grant confers nothing, even if unexpired", () => {
    assert.equal(
      effectiveVip({ user: {}, grant: { revoked: true, expiresAt: null } }).vip,
      false,
    );
    assert.equal(
      effectiveVip({ user: {}, grant: { active: false, expiresAt: null } }).vip,
      false,
    );
  });

  test("an unparseable expiry fails closed", () => {
    assert.equal(grantIsActive({ expiresAt: "not-a-date" }), false);
  });

  test("a Firestore Timestamp expiry is understood", () => {
    const future = { toDate: () => new Date(Date.now() + 60_000) };
    const past = { toDate: () => new Date(Date.now() - 60_000) };
    assert.equal(grantIsActive({ expiresAt: future }), true);
    assert.equal(grantIsActive({ expiresAt: past }), false);
  });

  test("VIP coexists with EVERY staff role", () => {
    for (const role of STAFF_ROLES) {
      const result = effectiveVip({
        user: { role, premiumIdentity: true },
        grant: null,
      });
      assert.equal(result.vip, true, `${role} should keep VIP`);
      assert.equal(result.primarySource, VIP_SOURCES.SUBSCRIPTION, role);
    }
  });

  test("a staff role alone never confers VIP", () => {
    for (const role of STAFF_ROLES) {
      assert.equal(effectiveVip({ user: { role } }).vip, false, role);
    }
  });
});
