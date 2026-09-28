// The Premium Pages wire and storage contract (ADR-233 §1-§2). Pure: no SDK
// import beyond the error type.
//
// pages/{pageId} is server-written; the owner may `get` it (firestore.rules)
// and every other reader goes through a callable. It has an EXACT key set,
// every key always present (null where empty), validated by canonicalPage.
// A document that fails it is `data-loss`: a server invariant broke, and no
// caller may act on a half-understood Page.

const { HttpsError } = require("firebase-functions/v2/https");

const { fail, timestampMillis } = require("../integrity/guards");
const { PAGE_KINDS, pageCategoryAllowed } = require("./catalog");

const PAGE_SCHEMA_VERSION = 1;
const PAGE_CONSENT_VERSION = 1;
const PAGE_ADULT_ATTESTATION_METHOD = "self_declared_birth_date";
const PAGE_STATUSES = Object.freeze(["active", "readOnly", "hidden"]);
const PAGE_KEYS = Object.freeze([
  "adultAttestationMethod",
  "adultAttestedAt",
  "business",
  "category",
  "community",
  "consentVersion",
  "createdAt",
  "description",
  "displayName",
  "kind",
  "lapsedAt",
  "lastPostAt",
  "listed",
  "nameChangedAt",
  "nameSearch",
  "ownerId",
  "ownerPaused",
  "pageId",
  "pinnedPostId",
  "postCount",
  "schemaVersion",
  "status",
  "suspended",
  "suspendedAt",
  "suspensionReason",
  "updatedAt",
]);
const BUSINESS_KEYS = Object.freeze([
  "address",
  "email",
  "hours",
  "legalNotice",
  "phone",
  "website",
]);
const COMMUNITY_KEYS = Object.freeze(["linkedServerId", "rules"]);

const PAGE_POST_ID_PATTERN = /^pp_[a-f0-9]{40}$/u;
const PAGE_MEDIA_ID_PATTERN = /^pm_[a-f0-9]{40}$/u;
const PAGE_COMMENT_ID_PATTERN = /^pc_[a-f0-9]{40}$/u;
const SUSPENSION_REASON_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/u;
const SERVER_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;

const PAGE_LIMITS = Object.freeze({
  description: 300,
  rules: 1000,
  hours: 120,
  address: 160,
  legalNotice: 1000,
  website: 200,
  email: 254,
  displayName: 120,
  nameSearch: 120,
});
const PAGE_NAME_CHANGE_FIND_DELAY_MS = 7 * 24 * 60 * 60 * 1000;

// Control and format characters are refused as in display_name.js. The
// multi-line fields keep LF (CRLF / CR are folded to LF first); nothing else
// in \p{Cc} survives.
const UNSAFE_SINGLE_LINE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;
const UNSAFE_MULTI_LINE = /[\u0000-\u0009\u000b-\u001f\u007f-\u009f\p{Cf}\p{Zl}\p{Zp}]/u;
const MULTI_LINE_FIELDS = new Set(["description", "rules", "legalNotice"]);

const EMAIL_PATTERN =
  /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/u;
const E164_PATTERN = /^\+[1-9][0-9]{7,14}$/u;

// ------------------------------------------------------------------ errors

function pagesError(code, message, reason) {
  return new HttpsError(code, message, { reason });
}

const PAGE_ERRORS = Object.freeze({
  exists: () => pagesError("failed-precondition",
    "This account already has a Page.", "pageExists"),
  notFound: () => pagesError("failed-precondition",
    "This account doesn't have a Page.", "pageNotFound"),
  profileNotPublic: () => pagesError("failed-precondition",
    "A Page needs a public profile.", "pageProfileNotPublic"),
  nameReserved: () => pagesError("failed-precondition",
    "This name can't be used for a Page.", "pageNameReserved"),
  hasAudience: () => pagesError("failed-precondition",
    "Pages can't be created on an account that already has followers yet.",
    "pageHasAudience"),
  adultRequired: () => pagesError("failed-precondition",
    "You must be 18 or older to run a Page.", "pageAdultRequired"),
  suspended: () => pagesError("failed-precondition",
    "This Page is suspended.", "pageSuspended"),
  linkedServerInvalid: () => pagesError("invalid-argument",
    "The linked server is unavailable.", "pageLinkedServerInvalid"),
  creatorAudienceBlocked: () => pagesError("failed-precondition",
    "Creator audience is unavailable while this account runs a Page.",
    "pageActive"),
});

// ------------------------------------------------------------- text helpers

function normalizedField(value, label, maxLength) {
  if (value === null) return null;
  if (typeof value !== "string") {
    fail("invalid-argument", `${label} must be text or null.`);
  }
  let text = value.normalize("NFC");
  const multiLine = MULTI_LINE_FIELDS.has(label);
  if (multiLine) text = text.replace(/\r\n?/gu, "\n");
  text = text.trim();
  if ((multiLine ? UNSAFE_MULTI_LINE : UNSAFE_SINGLE_LINE).test(text)) {
    fail("invalid-argument", `${label} contains unsupported characters.`);
  }
  if (text.length > maxLength) {
    fail("invalid-argument", `${label} must be at most ${maxLength} characters.`);
  }
  return text;
}

// A nullable optional field: empty text is stored as null.
function optionalField(value, label, maxLength) {
  const text = normalizedField(value, label, maxLength);
  return text === null || text.length === 0 ? null : text;
}

function normalizedWebsite(value) {
  const text = optionalField(value, "website", 2048);
  if (text === null) return null;
  if (/\s/u.test(text)) fail("invalid-argument", "website is invalid.");
  let url;
  try {
    url = new URL(text);
  } catch {
    fail("invalid-argument", "website is invalid.");
  }
  // WHATWG URL already converts an IDN host to punycode.
  if (url.protocol !== "https:" || url.username !== "" || url.password !== "" ||
      url.port !== "" || !url.hostname.includes(".") ||
      url.hostname.startsWith(".") || url.hostname.endsWith(".") ||
      /^[0-9.]+$/u.test(url.hostname) || url.hostname.startsWith("[")) {
    fail("invalid-argument", "website is invalid.");
  }
  const href = url.href;
  if (href.length > PAGE_LIMITS.website) {
    fail("invalid-argument", `website must be at most ${PAGE_LIMITS.website} characters.`);
  }
  return href;
}

function normalizedEmail(value) {
  const text = optionalField(value, "email", PAGE_LIMITS.email);
  if (text === null) return null;
  if (!EMAIL_PATTERN.test(text)) fail("invalid-argument", "email is invalid.");
  const at = text.lastIndexOf("@");
  return `${text.slice(0, at)}@${text.slice(at + 1).toLowerCase()}`;
}

function normalizedPhone(value) {
  const text = optionalField(value, "phone", 32);
  if (text === null) return null;
  const compact = text.replace(/[ -]/gu, "");
  if (!E164_PATTERN.test(compact)) fail("invalid-argument", "phone is invalid.");
  return compact;
}

function requireExactObject(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", `${label} must be an object.`);
  }
  const actual = Object.keys(value).sort();
  if (actual.length !== keys.length || actual.some((key, index) => key !== keys[index])) {
    fail("invalid-argument", `${label} must contain exactly ${keys.join(", ")}.`);
  }
  return value;
}

/**
 * Validates the editable profile of a Page for `kind`: category,
 * description and exactly one of business / community (the other null).
 * Returns normalized values; the linked server is only format-checked here
 * (the transaction reads it).
 */
function validatePageFields({ kind, category, description, business, community }) {
  if (!PAGE_KINDS.includes(kind)) fail("invalid-argument", "kind is invalid.");
  if (!pageCategoryAllowed(kind, category)) {
    fail("invalid-argument", "category is invalid.");
  }
  const normalizedDescription =
    normalizedField(description, "description", PAGE_LIMITS.description);
  if (normalizedDescription === null) {
    fail("invalid-argument", "description must be text.");
  }
  let normalizedBusiness = null;
  let normalizedCommunity = null;
  if (kind === "business") {
    if (community !== null) fail("invalid-argument", "community must be null for a business Page.");
    const input = requireExactObject(business, BUSINESS_KEYS, "business");
    normalizedBusiness = {
      website: normalizedWebsite(input.website),
      email: normalizedEmail(input.email),
      phone: normalizedPhone(input.phone),
      address: optionalField(input.address, "address", PAGE_LIMITS.address),
      hours: optionalField(input.hours, "hours", PAGE_LIMITS.hours),
      legalNotice: optionalField(input.legalNotice, "legalNotice", PAGE_LIMITS.legalNotice),
    };
  } else {
    if (business !== null) fail("invalid-argument", "business must be null for a community Page.");
    const input = requireExactObject(community, COMMUNITY_KEYS, "community");
    const linkedServerId = input.linkedServerId;
    if (linkedServerId !== null &&
        (typeof linkedServerId !== "string" || !SERVER_ID_PATTERN.test(linkedServerId))) {
      fail("invalid-argument", "linkedServerId is invalid.");
    }
    normalizedCommunity = {
      rules: optionalField(input.rules, "rules", PAGE_LIMITS.rules),
      linkedServerId,
    };
  }
  return Object.freeze({
    kind,
    category,
    description: normalizedDescription,
    business: normalizedBusiness,
    community: normalizedCommunity,
  });
}

// ----------------------------------------------------- name mirror + search

/// The Page's display-name mirror: the SAME derivation publicProfiles uses
/// (trim, cut at 120 UTF-16 units back to a whole code point, trim).
function pageDisplayNameMirror(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const cut = trimmed.length > PAGE_LIMITS.displayName
    ? trimmed.slice(0, PAGE_LIMITS.displayName)
    : trimmed;
  const lastUnit = cut.charCodeAt(cut.length - 1);
  const whole = lastUnit >= 0xd800 && lastUnit <= 0xdbff ? cut.slice(0, -1) : cut;
  const result = whole.trim();
  return result.length > 0 ? result : null;
}

/// NFKC case-folded prefix-search key (§2.7), at most 120 units.
function pageNameSearch(displayName) {
  const folded = String(displayName ?? "")
    .normalize("NFKC")
    .toLocaleLowerCase("en-US")
    .replace(/\s+/gu, " ")
    .trim();
  const cut = folded.length > PAGE_LIMITS.nameSearch
    ? folded.slice(0, PAGE_LIMITS.nameSearch)
    : folded;
  const lastUnit = cut.charCodeAt(cut.length - 1);
  return (lastUnit >= 0xd800 && lastUnit <= 0xdbff ? cut.slice(0, -1) : cut).trim();
}

// ------------------------------------------------------------- derivations

/// `listed` is fully derived (§1.2); every writer stores this value.
function derivePageListed(page) {
  return page.status === "active" && page.ownerPaused === false &&
    page.suspended === false && page.postCount > 0;
}

// ------------------------------------------------------------- validation

function isTimestamp(value) {
  return timestampMillis(value) !== null;
}

function nullableTimestamp(value) {
  return value === null || isTimestamp(value);
}

function boundedString(value, maxLength, { allowEmpty = true } = {}) {
  return typeof value === "string" && value.length <= maxLength &&
    (allowEmpty || value.length > 0);
}

function nullableBoundedString(value, maxLength) {
  return value === null || (boundedString(value, maxLength) && value.length > 0);
}

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === keys.length && actual.every((key, index) => key === keys[index]);
}

function validBusiness(value) {
  return exactKeys(value, BUSINESS_KEYS) &&
    nullableBoundedString(value.website, PAGE_LIMITS.website) &&
    nullableBoundedString(value.email, PAGE_LIMITS.email) &&
    (value.phone === null || (typeof value.phone === "string" && E164_PATTERN.test(value.phone))) &&
    nullableBoundedString(value.address, PAGE_LIMITS.address) &&
    nullableBoundedString(value.hours, PAGE_LIMITS.hours) &&
    nullableBoundedString(value.legalNotice, PAGE_LIMITS.legalNotice);
}

function validCommunity(value) {
  return exactKeys(value, COMMUNITY_KEYS) &&
    nullableBoundedString(value.rules, PAGE_LIMITS.rules) &&
    (value.linkedServerId === null ||
      (typeof value.linkedServerId === "string" && SERVER_ID_PATTERN.test(value.linkedServerId)));
}

/// The reason `data` is not a canonical Page for `pageId`, or null.
function pageMalformedReason(data, pageId) {
  if (!exactKeys(data, PAGE_KEYS)) return "keys";
  if (data.schemaVersion !== PAGE_SCHEMA_VERSION) return "schemaVersion";
  if (data.pageId !== pageId || data.ownerId !== pageId) return "identity";
  if (!PAGE_KINDS.includes(data.kind)) return "kind";
  if (!PAGE_STATUSES.includes(data.status)) return "status";
  if (data.status === "active" ? data.lapsedAt !== null : !isTimestamp(data.lapsedAt)) {
    return "lapsedAt";
  }
  if (typeof data.ownerPaused !== "boolean") return "ownerPaused";
  if (typeof data.suspended !== "boolean") return "suspended";
  if (data.suspended
    ? !isTimestamp(data.suspendedAt) ||
      typeof data.suspensionReason !== "string" ||
      !SUSPENSION_REASON_PATTERN.test(data.suspensionReason)
    : data.suspendedAt !== null || data.suspensionReason !== null) {
    return "suspension";
  }
  if (!Number.isSafeInteger(data.postCount) || data.postCount < 0) return "postCount";
  if (typeof data.listed !== "boolean" || data.listed !== derivePageListed(data)) {
    return "listed";
  }
  if (!pageCategoryAllowed(data.kind, data.category)) return "category";
  if (!boundedString(data.description, PAGE_LIMITS.description)) return "description";
  if (data.kind === "business"
    ? !validBusiness(data.business) || data.community !== null
    : !validCommunity(data.community) || data.business !== null) {
    return "profile";
  }
  if (!boundedString(data.displayName, PAGE_LIMITS.displayName, { allowEmpty: false }) ||
      data.displayName !== data.displayName.trim()) {
    return "displayName";
  }
  if (!boundedString(data.nameSearch, PAGE_LIMITS.nameSearch)) return "nameSearch";
  if (!nullableTimestamp(data.nameChangedAt)) return "nameChangedAt";
  if (!nullableTimestamp(data.lastPostAt)) return "lastPostAt";
  if (data.pinnedPostId !== null &&
      (typeof data.pinnedPostId !== "string" || !PAGE_POST_ID_PATTERN.test(data.pinnedPostId))) {
    return "pinnedPostId";
  }
  if (!isTimestamp(data.adultAttestedAt) ||
      data.adultAttestationMethod !== PAGE_ADULT_ATTESTATION_METHOD) {
    return "adultAttestation";
  }
  if (data.consentVersion !== PAGE_CONSENT_VERSION) return "consentVersion";
  if (!isTimestamp(data.createdAt) || !isTimestamp(data.updatedAt)) return "timestamps";
  return null;
}

/**
 * The canonical Page in `snapshot` for `pageId`: null when the document does
 * not exist, the frozen data when it is exact, and `data-loss` otherwise.
 */
function canonicalPage(snapshot, pageId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data();
  if (pageMalformedReason(data, pageId) !== null) {
    fail("data-loss", "The Page record is malformed.");
  }
  return Object.freeze({ ...data });
}

/// Like canonicalPage, but a malformed document is null instead of an error
/// (derived mirrors such as the public badge fail to "no Page").
function canonicalPageOrNull(snapshot, pageId) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data();
  return pageMalformedReason(data, pageId) === null ? Object.freeze({ ...data }) : null;
}

/// A brand-new Page document (§2.2 create step 5).
function newPageDocument({
  pageId,
  fields,
  displayName,
  now,
}) {
  const page = {
    schemaVersion: PAGE_SCHEMA_VERSION,
    pageId,
    ownerId: pageId,
    kind: fields.kind,
    status: "active",
    lapsedAt: null,
    ownerPaused: false,
    suspended: false,
    suspendedAt: null,
    suspensionReason: null,
    listed: false,
    category: fields.category,
    description: fields.description,
    business: fields.business,
    community: fields.community,
    displayName,
    nameSearch: pageNameSearch(displayName),
    nameChangedAt: null,
    postCount: 0,
    lastPostAt: null,
    pinnedPostId: null,
    adultAttestedAt: now,
    adultAttestationMethod: PAGE_ADULT_ATTESTATION_METHOD,
    consentVersion: PAGE_CONSENT_VERSION,
    createdAt: now,
    updatedAt: now,
  };
  page.listed = derivePageListed(page);
  return page;
}

/// The owner-facing result of every managePageV1 op.
function pageLifecycleResult(page) {
  return {
    pageId: page.pageId,
    kind: page.kind,
    status: page.status,
    ownerPaused: page.ownerPaused,
  };
}

module.exports = {
  BUSINESS_KEYS,
  COMMUNITY_KEYS,
  PAGE_ADULT_ATTESTATION_METHOD,
  PAGE_COMMENT_ID_PATTERN,
  PAGE_CONSENT_VERSION,
  PAGE_ERRORS,
  PAGE_KEYS,
  PAGE_LIMITS,
  PAGE_MEDIA_ID_PATTERN,
  PAGE_NAME_CHANGE_FIND_DELAY_MS,
  PAGE_POST_ID_PATTERN,
  PAGE_SCHEMA_VERSION,
  PAGE_STATUSES,
  canonicalPage,
  canonicalPageOrNull,
  derivePageListed,
  newPageDocument,
  pageDisplayNameMirror,
  pageLifecycleResult,
  pageMalformedReason,
  pageNameSearch,
  pagesError,
  validatePageFields,
};
