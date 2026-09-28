// The Premium Pages contract (ADR-233 §1-§2): name safety, the exact Page
// document, field validation, the lapse function and the visibility entry.
// Pure: no emulator.
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { Timestamp } = require("firebase-admin/firestore");

const {
  pageNameViolation,
  nameSkeletonTokens,
} = require("../profile/name_safety");
const {
  PAGE_KEYS,
  canonicalPage,
  canonicalPageOrNull,
  derivePageListed,
  pageDisplayNameMirror,
  pageMalformedReason,
  pageNameSearch,
  validatePageFields,
} = require("../pages/contract");
const {
  BUSINESS_CATEGORIES,
  COMMUNITY_CATEGORIES,
  pageCategoryAllowed,
} = require("../pages/catalog");
const {
  PAGE_READ_ONLY_WINDOW_MS,
  effectivePageStatus,
  restoredPageFields,
} = require("../pages/lapse");
const {
  canonicalPageVisibility,
  pageVisibilityEntry,
} = require("../pages/visibility");
const { businessFields, pageDoc } = require("./helpers/pages_fixture");

const NOW_MS = 1_900_000_000_000;
const snapshot = (data) => ({ exists: data !== null, data: () => data });

function fields(overrides = {}) {
  return {
    kind: "business",
    category: "shop",
    description: "Hand-made things.",
    business: businessFields(),
    community: null,
    ...overrides,
  };
}

function rejects(fn, pattern) {
  assert.throws(fn, (error) => {
    assert.equal(error.code, "invalid-argument");
    if (pattern) assert.match(error.message, pattern);
    return true;
  });
}

// ------------------------------------------------------------ name safety

test("name safety refuses reserved names through skeleton look-alikes", () => {
  const refused = [
    "YO Voice", "yo voice", "YOVoice", "Y0 Voice", "Y O V O I C E",
    "УО Vоісе", "Ｙ０ Ｖｏｉｃｅ", "yovoice.app", "The YO-Voice team",
    "Official", "0fficial", "Offlcial Shop", "OfficialShop", "Oficjalna strona",
    "VIP", "V.I.P.", "VlP Lounge", "v i p",
    "Admin", "Adm1n", "TeamAdmin", "Administracja", "Moderator", "rnoderator",
    "Moderators", "Support", "Pomoc", "Wsparcie", "Verified", "Zweryfikowana Firma",
    "Staff",
    // Capitals mapped before lower-casing, small capitals, other scripts
    // (audit 2026-09-28): Greek capital Upsilon, Armenian oh, Cherokee gi and
    // its small form, Lisu, the phonetic small capitals.
    "\u03A5O Voice", "\u03A5\u039F Voice", "\u028F\u1D0F \u1D20\u1D0F\u026A\u1D04\u1D07",
    "\u1D20\u026A\u1D18", "Y\u0585 Voice", "\u13A9O Voice", "\uAB79o voice",
    "\uA4EC\uA4F3 Voice", "\u13D9\u13A5\u13E2", "\u0397\u0395\u039B\u03A1 Support",
  ];
  for (const name of refused) {
    assert.equal(pageNameViolation(name), "reserved", name);
  }
});

test("name safety refuses check-mark look-alikes anywhere", () => {
  for (const name of ["Moja Firma ✓", "✔ Shop", "Kawiarnia ✅", "Club ☑", "Pod 🗸", "Pod 🗹 🟣",
    "Shop \u221A", "Shop \u237B"]) {
    assert.equal(pageNameViolation(name), "lookalike", name);
  }
});

test("name safety keeps ordinary names", () => {
  for (const name of [
    "Kawiarnia Pod Lipą", "Café Nero", "Vipassana Club", "Olivia Bakery",
    "Badminton Club", "Legia Supporters", "Voice of the City", "Yoga Studio",
    "Klub Książki", "Muzeum Śląskie", "Fan Club 💜",
    "\u0397air Studio", "Caf\u00E9 \u039Dova", "\u0391thens Grill", "Bakery \u0141\u00F3d\u017A",
  ]) {
    assert.equal(pageNameViolation(name), null, name);
  }
  assert.equal(pageNameViolation(42), "reserved");
});

test("the skeleton folds width, diacritics, Cyrillic, leetspeak and spacing", () => {
  assert.deepEqual(nameSkeletonTokens("Ｃａｆé 5ТАR"), ["cafe", "star"]);
  assert.deepEqual(nameSkeletonTokens("Y O Voice"), ["yo", "voice"]);
});

// --------------------------------------------------------------- catalog

test("categories are server-owned per kind and exclude restricted ones", () => {
  assert.equal(BUSINESS_CATEGORIES.length, 11);
  assert.equal(COMMUNITY_CATEGORIES.length, 9);
  assert.equal(pageCategoryAllowed("business", "shop"), true);
  assert.equal(pageCategoryAllowed("community", "shop"), false);
  assert.equal(pageCategoryAllowed("business", "fan_club"), false);
  for (const restricted of ["alcohol", "gambling", "crypto", "dating", "weapons"]) {
    assert.equal(pageCategoryAllowed("business", restricted), false);
    assert.equal(pageCategoryAllowed("community", restricted), false);
  }
});

// ------------------------------------------------------ field validation

test("business fields are normalized and validated exactly", () => {
  const result = validatePageFields(fields({
    description: "  Line one\r\nLine two  ",
    business: businessFields({
      website: "https://bücher.example/sklep",
      email: "Hello@Example.COM",
      phone: "+48 600-100-200",
      address: "  ul. Lipowa 1, Kraków ",
      hours: "",
      legalNotice: "Firma X sp. z o.o.\nNIP 123",
    }),
  }));
  assert.equal(result.description, "Line one\nLine two");
  assert.deepEqual(result.business, {
    website: "https://xn--bcher-kva.example/sklep",
    email: "Hello@example.com",
    phone: "+48600100200",
    address: "ul. Lipowa 1, Kraków",
    hours: null,
    legalNotice: "Firma X sp. z o.o.\nNIP 123",
  });
  assert.equal(result.community, null);
});

test("website must be https, credential-free, port-free and dotted", () => {
  for (const website of [
    "http://example.com", "https://user:pw@example.com", "https://example.com:8443",
    "https://localhost", "ftp://example.com", "https://127.0.0.1", "https://exa mple.com",
    "javascript:alert(1)", `https://example.com/${"a".repeat(200)}`,
  ]) {
    rejects(() => validatePageFields(fields({ business: businessFields({ website }) })), /website/);
  }
});

test("email, phone and control characters are refused", () => {
  rejects(() => validatePageFields(fields({ business: businessFields({ email: "not-an-email" }) })), /email/);
  rejects(() => validatePageFields(fields({ business: businessFields({ phone: "600100200" }) })), /phone/);
  rejects(() => validatePageFields(fields({ business: businessFields({ phone: "+0123456789" }) })), /phone/);
  rejects(() => validatePageFields(fields({ business: businessFields({ phone: "+1234567" }) })), /phone/);
  rejects(() => validatePageFields(fields({ business: businessFields({ address: "a\nb" }) })), /address/);
  rejects(() => validatePageFields(fields({ description: "bad​zero-width" })), /description/);
  rejects(() => validatePageFields(fields({ description: "a".repeat(301) })), /description/);
  rejects(() => validatePageFields(fields({ description: null })), /description/);
});

test("exactly the kind's profile object is accepted", () => {
  rejects(() => validatePageFields(fields({ community: { rules: null, linkedServerId: null } })), /community/);
  rejects(() => validatePageFields(fields({ business: { ...businessFields(), extra: 1 } })), /business/);
  rejects(() => validatePageFields(fields({ business: null })), /business/);
  rejects(() => validatePageFields(fields({ kind: "server" })), /kind/);
  const community = validatePageFields({
    kind: "community",
    category: "fan_club",
    description: "",
    business: null,
    community: { rules: "Be kind.", linkedServerId: "srv_abc" },
  });
  assert.deepEqual(community.community, { rules: "Be kind.", linkedServerId: "srv_abc" });
  rejects(() => validatePageFields({
    kind: "community",
    category: "fan_club",
    description: "",
    business: businessFields(),
    community: { rules: null, linkedServerId: null },
  }), /business/);
  rejects(() => validatePageFields({
    kind: "community",
    category: "fan_club",
    description: "",
    business: null,
    community: { rules: null, linkedServerId: "../x" },
  }), /linkedServerId/);
});

// ---------------------------------------------------------- Page document

test("a new Page has exactly the documented keys and is canonical", () => {
  const page = pageDoc("owner-1", NOW_MS);
  assert.deepEqual(Object.keys(page).sort(), [...PAGE_KEYS]);
  assert.equal(PAGE_KEYS.length, 26);
  assert.equal(pageMalformedReason(page, "owner-1"), null);
  assert.equal(page.listed, false);
  assert.equal(page.status, "active");
  assert.equal(page.adultAttestationMethod, "self_declared_birth_date");
  assert.deepEqual(canonicalPage(snapshot(page), "owner-1"), page);
  assert.equal(canonicalPage(snapshot(null), "owner-1"), null);
});

test("malformed Pages are data-loss (or null for derived mirrors)", () => {
  const ts = Timestamp.fromMillis(NOW_MS);
  const malformed = [
    { extra: 1 },
    { pageId: "someone-else" },
    { kind: "server" },
    { status: "readOnly" }, // no lapsedAt
    { status: "active", lapsedAt: ts },
    { suspended: true }, // no suspendedAt / reason
    { listed: true }, // postCount 0
    { postCount: -1 },
    { category: "fan_club" },
    { community: { rules: null, linkedServerId: null } },
    { displayName: " padded " },
    { pinnedPostId: "pp_short" },
    { consentVersion: 2 },
    { adultAttestationMethod: "document" },
  ];
  for (const overrides of malformed) {
    const data = { ...pageDoc("owner-1", NOW_MS), ...overrides };
    assert.throws(() => canonicalPage(snapshot(data), "owner-1"), (error) => {
      assert.equal(error.code, "data-loss");
      return true;
    }, JSON.stringify(overrides));
    assert.equal(canonicalPageOrNull(snapshot(data), "owner-1"), null);
  }
  const { pageId: _dropped, ...missingKey } = pageDoc("owner-1", NOW_MS);
  assert.equal(pageMalformedReason(missingKey, "owner-1"), "keys");
});

test("listed is derived from status, pause, suspension and posts", () => {
  const base = pageDoc("owner-1", NOW_MS);
  assert.equal(derivePageListed({ ...base, postCount: 1 }), true);
  assert.equal(derivePageListed({ ...base, postCount: 1, ownerPaused: true }), false);
  assert.equal(derivePageListed({ ...base, postCount: 1, suspended: true }), false);
  assert.equal(derivePageListed({ ...base, postCount: 1, status: "readOnly" }), false);
  assert.equal(derivePageListed(base), false);
});

test("the display-name mirror and search key follow the public projection", () => {
  assert.equal(pageDisplayNameMirror("  Kawiarnia  "), "Kawiarnia");
  assert.equal(pageDisplayNameMirror("   "), null);
  const astral = "😀".repeat(10) + "B".repeat(99) + " " + "😀";
  const mirror = pageDisplayNameMirror(astral);
  assert.ok(mirror.length <= 120);
  assert.equal(mirror, mirror.trim());
  assert.equal(pageNameSearch("ＫＡＷＩＡＲＮＩＡ  Pod"), "kawiarnia pod");
});

// ------------------------------------------------------------------ lapse

test("effective status follows the O3 table", () => {
  const active = pageDoc("p", NOW_MS);
  const readOnly = { ...active, status: "readOnly", lapsedAt: Timestamp.fromMillis(NOW_MS) };
  const hidden = { ...readOnly, status: "hidden" };
  assert.equal(effectivePageStatus(active, true, NOW_MS, true), "active");
  assert.equal(effectivePageStatus(active, false, NOW_MS, true), "readOnly");
  assert.equal(effectivePageStatus(readOnly, false, NOW_MS + PAGE_READ_ONLY_WINDOW_MS - 1, true), "readOnly");
  assert.equal(effectivePageStatus(readOnly, false, NOW_MS + PAGE_READ_ONLY_WINDOW_MS, true), "hidden");
  assert.equal(effectivePageStatus(hidden, false, NOW_MS, true), "hidden");
  assert.equal(effectivePageStatus(hidden, true, NOW_MS, true), "active");
  assert.equal(effectivePageStatus(null, true, NOW_MS, true), null);
});

test("lapseEnabled false freezes downgrades but still restores", () => {
  const active = pageDoc("p", NOW_MS);
  const readOnly = { ...active, status: "readOnly", lapsedAt: Timestamp.fromMillis(NOW_MS) };
  assert.equal(effectivePageStatus(active, false, NOW_MS, false), "active");
  assert.equal(effectivePageStatus(readOnly, false, NOW_MS + 10 * PAGE_READ_ONLY_WINDOW_MS, false), "readOnly");
  assert.equal(effectivePageStatus(readOnly, true, NOW_MS, false), "active");
  assert.deepEqual(restoredPageFields(readOnly), { status: "active", lapsedAt: null });
  assert.deepEqual(restoredPageFields(active), {});
});

// ------------------------------------------------------------- visibility

test("the visibility entry is derived with suspended > hidden > paused", () => {
  const base = pageDoc("p", NOW_MS);
  const lapsedAt = Timestamp.fromMillis(NOW_MS - 5);
  assert.deepEqual(pageVisibilityEntry(base), { notViewable: null, readOnlySinceMs: null });
  assert.deepEqual(pageVisibilityEntry({ ...base, ownerPaused: true }),
    { notViewable: "paused", readOnlySinceMs: null });
  assert.deepEqual(pageVisibilityEntry({ ...base, ownerPaused: true, status: "hidden", lapsedAt }),
    { notViewable: "hidden", readOnlySinceMs: null });
  assert.deepEqual(pageVisibilityEntry({ ...base, ownerPaused: true, suspended: true }),
    { notViewable: "suspended", readOnlySinceMs: null });
  assert.deepEqual(pageVisibilityEntry({ ...base, status: "readOnly", lapsedAt }),
    { notViewable: null, readOnlySinceMs: NOW_MS - 5 });
  assert.deepEqual(pageVisibilityEntry(null), { notViewable: null, readOnlySinceMs: null });
});

test("the visibility index reads fail closed", () => {
  const updatedAt = Timestamp.fromMillis(NOW_MS);
  const index = canonicalPageVisibility(snapshot({
    schemaVersion: 1,
    notViewable: { a: "paused", b: "weird" },
    readOnlySince: { c: 5, d: "soon" },
    updatedAt,
  }));
  assert.equal(index.notViewable.get("a"), "paused");
  assert.equal(index.notViewable.get("b"), "hidden");
  assert.equal(index.readOnlySince.get("c"), 5);
  assert.equal(index.notViewable.get("d"), "hidden");
  assert.equal(canonicalPageVisibility(snapshot(null)).notViewable.size, 0);
  for (const broken of [
    { schemaVersion: 1, notViewable: [], readOnlySince: {}, updatedAt },
    { schemaVersion: 2, notViewable: {}, readOnlySince: {}, updatedAt },
    { schemaVersion: 1, notViewable: {}, readOnlySince: {}, updatedAt, extra: 1 },
  ]) {
    assert.throws(() => canonicalPageVisibility(snapshot(broken)), /malformed/);
  }
});
