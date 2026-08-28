const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  DEFAULT_MAX_OWNED_CLUBS,
  deriveEffectivePremiumAccess,
  hasStaffPreviewAccess,
  isActiveAccountProfile,
  paidPremiumIsActive,
} = require("../utils/premium_access");

const NOW = 1_820_000_000_000;

function paid(overrides = {}) {
  return {
    plan: "monthly",
    status: "active",
    isPremium: true,
    premiumIdentityEnabled: true,
    creatorEnabled: true,
    canCreateClubs: true,
    maxOwnedClubs: 3,
    currentPeriodEnd: { toMillis: () => NOW + 60_000 },
    ...overrides,
  };
}

describe("moderator Premium preview", () => {
  test("only moderator and superModerator receive the mirror-derived overlay", () => {
    for (const role of ["moderator", "superModerator"]) {
      const access = deriveEffectivePremiumAccess({
        user: { role },
        now: NOW,
      });
      assert.equal(access.staffComplimentary, true, role);
      assert.equal(access.premiumIdentityEnabled, true, role);
      assert.equal(access.creatorEnabled, true, role);
      assert.equal(access.canCreateClubs, true, role);
      assert.equal(access.maxOwnedClubs, DEFAULT_MAX_OWNED_CLUBS, role);
      assert.equal(access.source, "staffPreview", role);
    }

    for (const role of [
      "user",
      "guideMaster",
      "support",
      "auditor",
      "superAdmin",
      "admin",
      "vip",
      "",
    ]) {
      assert.equal(
        deriveEffectivePremiumAccess({ user: { role }, now: NOW })
          .staffComplimentary,
        false,
        role,
      );
    }
  });

  test("an acting callable requires the signed role and mirror to match", () => {
    assert.equal(
      hasStaffPreviewAccess({
        user: { role: "moderator" },
        tokenRole: "moderator",
        requireTokenRole: true,
      }),
      true,
    );
    for (const tokenRole of [null, "user", "superModerator", "superAdmin"]) {
      assert.equal(
        hasStaffPreviewAccess({
          user: { role: "moderator" },
          tokenRole,
          requireTokenRole: true,
        }),
        false,
        String(tokenRole),
      );
    }

    for (const [mirrorRole, tokenRole] of [
      [" moderator", "moderator"],
      ["moderator ", "moderator"],
      ["moderator", " moderator"],
      ["moderator", "moderator "],
    ]) {
      assert.equal(
        hasStaffPreviewAccess({
          user: { role: mirrorRole },
          tokenRole,
          requireTokenRole: true,
        }),
        false,
        `${JSON.stringify(tokenRole)}/${JSON.stringify(mirrorRole)}`,
      );
    }
  });

  test("banned, disabled and deleted profiles lose the overlay immediately", () => {
    for (const profile of [
      null,
      { role: "moderator", banned: true },
      { role: "moderator", disabled: true },
      { role: "moderator", deleted: true },
      { role: "moderator", status: "deleted" },
    ]) {
      assert.equal(isActiveAccountProfile(profile), false);
      assert.equal(
        deriveEffectivePremiumAccess({ user: profile, now: NOW })
          .staffComplimentary,
        false,
      );
    }
  });

  test("VIP grants are not product-access inputs", () => {
    const access = deriveEffectivePremiumAccess({
      user: { role: "user" },
      entitlement: null,
      now: NOW,
      grant: { active: true },
    });
    assert.equal(access.hasPremiumAccess, false);
    assert.equal(access.creatorEnabled, false);
    assert.equal(access.canCreateClubs, false);
  });
});

describe("paid truth remains independent", () => {
  test("valid paid features work without a staff role", () => {
    const access = deriveEffectivePremiumAccess({
      user: { role: "user" },
      entitlement: paid({ maxOwnedClubs: 8 }),
      now: NOW,
    });
    assert.equal(access.paidActive, true);
    assert.equal(access.staffComplimentary, false);
    assert.equal(access.source, "paid");
    assert.equal(access.maxOwnedClubs, 8);
  });

  test("paid and staff sources coexist without changing billing fields", () => {
    const entitlement = paid({
      plan: "yearly",
      currentPeriodEnd: { toMillis: () => NOW + 120_000 },
    });
    const access = deriveEffectivePremiumAccess({
      user: { role: "moderator" },
      entitlement,
      now: NOW,
    });
    assert.equal(access.source, "paidAndStaffPreview");
    assert.equal(access.paidActive, true);
    assert.equal(access.staffComplimentary, true);
    assert.equal(entitlement.plan, "yearly");
    assert.equal(entitlement.currentPeriodEnd.toMillis(), NOW + 120_000);
  });

  test("expiry and disabled paid features do not suppress active staff preview", () => {
    const access = deriveEffectivePremiumAccess({
      user: { role: "superModerator" },
      entitlement: paid({
        status: "expired",
        isPremium: false,
        premiumIdentityEnabled: false,
        creatorEnabled: false,
        canCreateClubs: false,
        currentPeriodEnd: { toMillis: () => NOW - 1 },
      }),
      now: NOW,
    });
    assert.equal(access.paidActive, false);
    assert.equal(access.staffComplimentary, true);
    assert.equal(access.creatorEnabled, true);
    assert.equal(access.canCreateClubs, true);
  });

  test("malformed, expired and refunded billing states fail closed", () => {
    for (const entitlement of [
      null,
      paid({ isPremium: false }),
      paid({ status: "refunded" }),
      paid({ currentPeriodEnd: { toMillis: () => NOW } }),
      paid({ currentPeriodEnd: new Date(NOW + 60_000) }),
      paid({ currentPeriodEnd: NOW + 60_000 }),
      paid({ currentPeriodEnd: { toMillis: () => Number.POSITIVE_INFINITY } }),
      paid({ currentPeriodEnd: "not-a-date" }),
    ]) {
      assert.equal(paidPremiumIsActive(entitlement, NOW), false);
    }
  });

  test("non-finite clocks are rejected instead of widening access", () => {
    assert.throws(
      () => paidPremiumIsActive(
        paid(),
        { toMillis: () => Number.POSITIVE_INFINITY },
      ),
      /valid time value/,
    );
  });
});
