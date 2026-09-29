// Who may run a Premium Page (ADR-233 §2.2, D3; ADR-234: paid Premium
// counts). Pure: no emulator.
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { Timestamp } = require("firebase-admin/firestore");

const {
  PAGES_ALLOW_PAID_SOURCE,
  PAGE_ACCESS_REQUIRED_REASON,
  derivePagesCapability,
  derivePagesCapabilityFromData,
  pageAccessRequiredError,
} = require("../pages/access");
const { testerGrant } = require("./helpers/pages_fixture");

const NOW_MS = 1_900_000_000_000;
const user = (overrides = {}) => ({ role: "user", status: "active", ...overrides });
const paidEntitlement = (overrides = {}) => ({
  status: "active",
  isPremium: true,
  premiumIdentityEnabled: true,
  currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 86_400_000),
  ...overrides,
});
const snapshot = (data) => ({ exists: data !== null, data: () => data });

test("paid Premium counts (ADR-234, owner decision 2026-09-29)", () => {
  assert.equal(PAGES_ALLOW_PAID_SOURCE, true);
});

test("a canonical tester grant is allowed, as vipGrant", () => {
  assert.deepEqual(
    derivePagesCapabilityFromData({ user: user(), grant: testerGrant(), now: NOW_MS }),
    { allowed: true, source: "vipGrant" },
  );
  // Both legacy production shapes and the note the 2026-09-19 script wrote.
  for (const grant of [
    { source: "legacyRoleMigration", grantedAt: Timestamp.fromMillis(1), expiresAt: null, revoked: false },
    testerGrant({ note: "tester" }),
    testerGrant({ expiresAt: Timestamp.fromMillis(NOW_MS + 1) }),
  ]) {
    assert.equal(
      derivePagesCapabilityFromData({ user: user(), grant, now: NOW_MS }).allowed,
      true,
      JSON.stringify(grant),
    );
  }
});

test("paid Premium alone is allowed as paid; allowPaid:false still refuses it", () => {
  assert.deepEqual(
    derivePagesCapabilityFromData({ user: user(), entitlement: paidEntitlement(), now: NOW_MS }),
    { allowed: true, source: "paid" },
  );
  // The constant is the switch: turning it off refuses paid again.
  assert.deepEqual(
    derivePagesCapabilityFromData({
      user: user(),
      entitlement: paidEntitlement(),
      now: NOW_MS,
      allowPaid: false,
    }),
    { allowed: false, source: null },
  );
});

test("an admin-granted entitlement and the trialing and grace statuses are allowed", () => {
  for (const entitlement of [
    // adminSetPremiumEntitlements writes source "admin" through
    // applyEntitlements (premium/entitlements.js).
    paidEntitlement({ source: "admin", plan: "monthly" }),
    paidEntitlement({ source: "stripe", plan: "yearly" }),
    paidEntitlement({ status: "trialing" }),
    paidEntitlement({ status: "grace" }),
  ]) {
    assert.deepEqual(
      derivePagesCapabilityFromData({ user: user(), entitlement, now: NOW_MS }),
      { allowed: true, source: "paid" },
      JSON.stringify(entitlement),
    );
  }
});

test("an expired, cancelled, non-Premium or malformed entitlement is refused", () => {
  for (const entitlement of [
    paidEntitlement({ currentPeriodEnd: Timestamp.fromMillis(NOW_MS) }),
    paidEntitlement({ currentPeriodEnd: Timestamp.fromMillis(NOW_MS - 1) }),
    // A Firestore Timestamp only: a number or a Date never counts.
    paidEntitlement({ currentPeriodEnd: NOW_MS + 86_400_000 }),
    paidEntitlement({ currentPeriodEnd: new Date(NOW_MS + 86_400_000) }),
    paidEntitlement({ status: "expired" }),
    paidEntitlement({ status: "canceled" }),
    paidEntitlement({ isPremium: false }),
    paidEntitlement({ premiumIdentityEnabled: false }),
    paidEntitlement({ source: "admin", status: "expired", isPremium: false }),
  ]) {
    assert.deepEqual(
      derivePagesCapabilityFromData({ user: user(), entitlement, now: NOW_MS }),
      { allowed: false, source: null },
      JSON.stringify(entitlement),
    );
  }
});

test("a VIP tester who also pays is admitted through the grant", () => {
  // deriveLikersAccess reports "paid" first for this account; the Pages gate
  // must not read that precedence as "no grant".
  assert.deepEqual(
    derivePagesCapabilityFromData({
      user: user(),
      entitlement: paidEntitlement(),
      grant: testerGrant(),
      now: NOW_MS,
    }),
    { allowed: true, source: "vipGrant" },
  );
});

test("staff preview is refused, even with a matching token role", () => {
  for (const role of ["moderator", "superModerator"]) {
    assert.deepEqual(
      derivePagesCapabilityFromData({
        user: user({ role }),
        tokenRole: role,
        now: NOW_MS,
      }),
      { allowed: false, source: null },
      role,
    );
    // A moderator who also pays runs a Page as paid, not as staff.
    assert.deepEqual(
      derivePagesCapabilityFromData({
        user: user({ role }),
        tokenRole: role,
        entitlement: paidEntitlement(),
        now: NOW_MS,
      }),
      { allowed: true, source: "paid" },
      role,
    );
  }
});

test("malformed, revoked, inactive or expired grants are refused", () => {
  const refused = [
    testerGrant({ revoked: true }),
    testerGrant({ revoked: "false" }),
    testerGrant({ expiresAt: Timestamp.fromMillis(NOW_MS) }),
    testerGrant({ expiresAt: NOW_MS + 1 }),
    testerGrant({ expiresAt: "2099-01-01" }),
    testerGrant({ source: "selfService" }),
    testerGrant({ active: false }),
    testerGrant({ pagesEnabled: true }),
    { source: "testerProgram", revoked: false },
    {},
    null,
  ];
  for (const grant of refused) {
    assert.equal(
      derivePagesCapabilityFromData({ user: user(), grant, now: NOW_MS }).allowed,
      false,
      JSON.stringify(grant),
    );
  }
});

test("an inactive or Auth-deleted account is refused whatever it holds", () => {
  for (const inactive of [
    user({ banned: true }),
    user({ disabled: true }),
    user({ status: "deleted" }),
    user({ authDeletedAt: Timestamp.fromMillis(NOW_MS - 1) }),
    null,
  ]) {
    assert.equal(
      derivePagesCapabilityFromData({ user: inactive, grant: testerGrant(), now: NOW_MS }).allowed,
      false,
    );
    assert.equal(
      derivePagesCapabilityFromData({
        user: inactive,
        entitlement: paidEntitlement(),
        now: NOW_MS,
      }).allowed,
      false,
    );
  }
});

test("snapshot form reads the same three documents", () => {
  assert.deepEqual(
    derivePagesCapability({
      userSnapshot: snapshot(user()),
      entitlementSnapshot: snapshot(null),
      grantSnapshot: snapshot(testerGrant()),
    }, { now: NOW_MS }),
    { allowed: true, source: "vipGrant" },
  );
  assert.deepEqual(
    derivePagesCapability({
      userSnapshot: snapshot(user()),
      entitlementSnapshot: snapshot(paidEntitlement()),
      grantSnapshot: snapshot(null),
    }, { now: NOW_MS }),
    { allowed: true, source: "paid" },
  );
  assert.equal(
    derivePagesCapability({
      userSnapshot: snapshot(user()),
      entitlementSnapshot: snapshot(paidEntitlement()),
      grantSnapshot: snapshot(null),
    }, { now: NOW_MS, allowPaid: false }).allowed,
    false,
  );
});

test("the refusal is the documented failed-precondition with its reason", () => {
  const error = pageAccessRequiredError();
  assert.equal(error.code, "failed-precondition");
  assert.equal(error.message, "YO Voice VIP is required to run a Page.");
  assert.deepEqual(error.details, { reason: PAGE_ACCESS_REQUIRED_REASON });
  assert.equal(PAGE_ACCESS_REQUIRED_REASON, "pageAccessRequired");
});
