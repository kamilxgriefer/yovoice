// ADR-230: who may see likers. Pure unit coverage of utils/likers_access.js.
const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  LIKERS_VIP_GRANT_SOURCES,
  canonicalLikersVipGrant,
  deriveLikersAccess,
  deriveLikersAccessFromSnapshots,
  likersAccessReferences,
} = require("../utils/likers_access");

const NOW = 1_820_000_000_000;

function ts(millis) {
  return { toMillis: () => millis };
}

function paid(overrides = {}) {
  return {
    plan: "monthly",
    status: "active",
    isPremium: true,
    premiumIdentityEnabled: true,
    creatorEnabled: true,
    canCreateClubs: true,
    maxOwnedClubs: 3,
    currentPeriodEnd: ts(NOW + 60_000),
    ...overrides,
  };
}

function testerGrant(overrides = {}) {
  return {
    source: "testerProgram",
    expiresAt: null,
    revoked: false,
    grantedBy: "owner-console",
    ...overrides,
  };
}

function legacyGrant(overrides = {}) {
  return {
    source: "legacyRoleMigration",
    grantedAt: ts(NOW - 86_400_000),
    expiresAt: null,
    revoked: false,
    ...overrides,
  };
}

const USER = Object.freeze({ role: "user" });

describe("canonicalLikersVipGrant (fail closed)", () => {
  test("accepts both known production shapes and the admin source", () => {
    assert.equal(canonicalLikersVipGrant(testerGrant(), NOW), true);
    assert.equal(canonicalLikersVipGrant(legacyGrant(), NOW), true);
    assert.equal(canonicalLikersVipGrant(testerGrant({ source: "admin" }), NOW), true);
    assert.equal(canonicalLikersVipGrant(testerGrant({ active: true }), NOW), true);
    assert.equal(
      canonicalLikersVipGrant(testerGrant({ expiresAt: ts(NOW + 1) }), NOW),
      true,
    );
    assert.deepEqual(
      [...LIKERS_VIP_GRANT_SOURCES],
      ["testerProgram", "legacyRoleMigration", "admin"],
    );
  });

  test("refuses every shape grantIsActive would accept loosely", () => {
    const refused = {
      empty: {},
      nullGrant: null,
      array: [],
      revokedString: testerGrant({ revoked: "true" }),
      revokedTrue: testerGrant({ revoked: true }),
      revokedAtExtraKey: testerGrant({ revokedAt: ts(NOW) }),
      missingRevoked: (() => {
        const grant = testerGrant();
        delete grant.revoked;
        return grant;
      })(),
      missingSource: (() => {
        const grant = testerGrant();
        delete grant.source;
        return grant;
      })(),
      missingExpiresAt: (() => {
        const grant = testerGrant();
        delete grant.expiresAt;
        return grant;
      })(),
      activeFalse: testerGrant({ active: false }),
      activeString: testerGrant({ active: "true" }),
      unknownSource: testerGrant({ source: "selfService" }),
      stringExpiresAt: testerGrant({ expiresAt: "2999-01-01T00:00:00Z" }),
      numberExpiresAt: testerGrant({ expiresAt: NOW + 60_000 }),
      dateExpiresAt: testerGrant({ expiresAt: new Date(NOW + 60_000) }),
      pastExpiresAt: testerGrant({ expiresAt: ts(NOW - 1) }),
      exactlyNowExpiresAt: testerGrant({ expiresAt: ts(NOW) }),
      emptyGrantedBy: testerGrant({ grantedBy: "" }),
      longGrantedBy: testerGrant({ grantedBy: "x".repeat(201) }),
      numberGrantedBy: testerGrant({ grantedBy: 7 }),
      stringGrantedAt: legacyGrant({ grantedAt: "yesterday" }),
      forgedVipField: testerGrant({ vip: true }),
    };
    for (const [label, grant] of Object.entries(refused)) {
      assert.equal(canonicalLikersVipGrant(grant, NOW), false, label);
    }
  });

  test("an invalid clock is a programming error, not a grant", () => {
    assert.throws(() => canonicalLikersVipGrant(testerGrant(), "now"), TypeError);
  });
});

describe("deriveLikersAccess", () => {
  test("paid Premium with identity is allowed", () => {
    assert.deepEqual(
      { ...deriveLikersAccess({ user: USER, entitlement: paid(), now: NOW }) },
      { allowed: true, source: "paid" },
    );
  });

  test("expired, lapsed or identity-less paid Premium is refused", () => {
    const refused = {
      pastPeriodEnd: paid({ currentPeriodEnd: ts(NOW - 1) }),
      statusExpired: paid({ status: "expired" }),
      missingPeriodEnd: paid({ currentPeriodEnd: undefined }),
      stringPeriodEnd: paid({ currentPeriodEnd: "2999-01-01" }),
      notPremium: paid({ isPremium: false }),
      noIdentity: paid({ premiumIdentityEnabled: false }),
    };
    for (const [label, entitlement] of Object.entries(refused)) {
      assert.deepEqual(
        { ...deriveLikersAccess({ user: USER, entitlement, now: NOW }) },
        { allowed: false, source: null },
        label,
      );
    }
  });

  test("a canonical VIP grant is allowed; a non-canonical one is not", () => {
    assert.equal(
      deriveLikersAccess({ user: USER, grant: testerGrant(), now: NOW }).source,
      "vipGrant",
    );
    assert.equal(
      deriveLikersAccess({ user: USER, grant: legacyGrant(), now: NOW }).source,
      "vipGrant",
    );
    assert.equal(
      deriveLikersAccess({ user: USER, grant: {}, now: NOW }).allowed,
      false,
    );
  });

  test("staff preview needs the signed token role to match the mirror", () => {
    const moderator = { role: "moderator" };
    assert.equal(
      deriveLikersAccess({ user: moderator, tokenRole: "moderator", now: NOW }).source,
      "staffPreview",
    );
    assert.equal(
      deriveLikersAccess({ user: moderator, tokenRole: "superModerator", now: NOW })
        .allowed,
      false,
    );
    assert.equal(
      deriveLikersAccess({ user: moderator, tokenRole: null, now: NOW }).allowed,
      false,
    );
    // A token role alone (no mirror) is not staff either.
    assert.equal(
      deriveLikersAccess({ user: USER, tokenRole: "moderator", now: NOW }).allowed,
      false,
    );
  });

  test("an inactive account is refused whatever it holds", () => {
    for (const user of [
      null,
      { role: "user", banned: true },
      { role: "user", disabled: true },
      { role: "user", deleted: true },
      { role: "user", status: "deleted" },
      { role: "user", authDeletedAt: ts(NOW - 1) },
    ]) {
      assert.deepEqual(
        {
          ...deriveLikersAccess({
            user,
            entitlement: paid(),
            grant: testerGrant(),
            tokenRole: "moderator",
            now: NOW,
          }),
        },
        { allowed: false, source: null },
        JSON.stringify(user),
      );
    }
  });

  test("precedence is paid > vipGrant > staffPreview", () => {
    const moderator = { role: "moderator" };
    assert.equal(deriveLikersAccess({
      user: moderator, tokenRole: "moderator", entitlement: paid(),
      grant: testerGrant(), now: NOW,
    }).source, "paid");
    assert.equal(deriveLikersAccess({
      user: moderator, tokenRole: "moderator", grant: testerGrant(), now: NOW,
    }).source, "vipGrant");
    assert.equal(deriveLikersAccess({
      user: moderator, tokenRole: "moderator",
      entitlement: paid({ premiumIdentityEnabled: false }), now: NOW,
    }).source, "staffPreview");
  });

  test("client-visible badges and forged fields are never authority", () => {
    const forged = {
      role: "user",
      vip: true,
      premiumIdentity: { active: true, tier: "vip" },
      isPremium: true,
      likersAccess: true,
    };
    assert.deepEqual(
      { ...deriveLikersAccess({ user: forged, now: NOW }) },
      { allowed: false, source: null },
    );
  });

  test("snapshots map to data and a non-string token role is ignored", () => {
    const snapshot = (data) => ({
      exists: data !== null,
      data: () => (data === null ? undefined : data),
    });
    assert.equal(deriveLikersAccessFromSnapshots({
      userSnapshot: snapshot({ role: "moderator" }),
      entitlementSnapshot: snapshot(null),
      grantSnapshot: snapshot(null),
      tokenRole: { toString: () => "moderator" },
      now: NOW,
    }).allowed, false);
    assert.equal(deriveLikersAccessFromSnapshots({
      userSnapshot: snapshot(USER),
      entitlementSnapshot: snapshot(null),
      grantSnapshot: snapshot(testerGrant()),
      now: NOW,
    }).source, "vipGrant");
  });

  test("the gate reads exactly the caller's three authority documents", () => {
    const db = { doc: (path) => path };
    assert.deepEqual(likersAccessReferences(db, "caller-1"), [
      "users/caller-1",
      "entitlements/caller-1",
      "vipGrants/caller-1",
    ]);
  });
});

describe("vipGrants census script (read-only, aggregate)", () => {
  const { InMemoryFirestore } = require("./helpers/in_memory_firestore");
  const {
    assertProject,
    census,
    parseArgs,
  } = require("../scripts/census_vip_grants");

  test("counts per key set, source and canonical result, never a uid or grantedBy", async () => {
    const db = new InMemoryFirestore();
    db.seed("vipGrants/tester-uid-aaaa", testerGrant({ grantedBy: "secret-operator@example.com" }));
    db.seed("vipGrants/tester-uid-bbbb", testerGrant({ grantedBy: "secret-operator@example.com" }));
    db.seed("vipGrants/revoked-uid-cccc", testerGrant({ revoked: true }));
    db.seed("vipGrants/odd-uid-dddd", { source: "free text leak", revoked: "true", note: "x" });
    db.seed("vipGrants/empty-uid-eeee", {});
    const report = await census({ db, nowMs: NOW, pageSize: 2, documentIdField: "__name__" });
    assert.equal(report.total, 5);
    assert.equal(report.canonical, 2);
    assert.deepEqual(report.rows, {
      "{expiresAt,grantedBy,revoked,source} | testerProgram | canonical": 2,
      "{expiresAt,grantedBy,revoked,source} | testerProgram | NOT canonical": 1,
      "{<other>,revoked,source} | <other string> | NOT canonical": 1,
      "{} | <undefined> | NOT canonical": 1,
    });
    const printed = JSON.stringify(report);
    for (const leak of ["uid-", "secret-operator", "free text leak"]) {
      assert.equal(printed.includes(leak), false, leak);
    }
  });

  test("runs only against the named production project", () => {
    assert.deepEqual(parseArgs(["--project", "yovoice-ec54a"]), { project: "yovoice-ec54a" });
    assert.throws(() => parseArgs(["--apply"]), /Unknown argument/u);
    assert.throws(() => assertProject({ project: null }, null), /--project/u);
    assert.throws(() => assertProject({ project: "yovoice-ec54a" }, "other"), /refusing/u);
    assert.doesNotThrow(() => assertProject({ project: "yovoice-ec54a" }, "yovoice-ec54a"));
  });
});
