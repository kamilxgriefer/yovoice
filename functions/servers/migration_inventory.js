"use strict";

const crypto = require("node:crypto");
const { isValidOpaqueUid } = require("../achievements/identity");

const INVENTORY_VERSION = 1;
const MAX_INVENTORY_RECORDS = 10000;
const MAX_INVENTORY_PAGES = 1000;
const MAX_PAGE_RECORDS = 500;
const REQUIRED_SCOPES = Object.freeze({
  club: Object.freeze(["members", "invites", "channels"]),
  room: Object.freeze(["roomMembers", "participants", "messages"]),
});
const UNVERIFIED_GATES = Object.freeze([
  "operator-evidence-not-independently-verified",
  "complete-related-record-and-media-generation-inventory",
  "canonical-owner-membership-ban-and-invitation-validation",
  "reviewed-private-admission-and-channel-access-mapping",
  "shared-free-paid-and-family-allocation-reconciliation",
  "compatible-client-and-idle-session-cutover-gate",
  "transaction-time-source-and-provider-generation-revalidation",
  "reviewed-resumable-apply-and-non-destructive-rollback",
  "separate-production-migration-approval",
]);
const ERROR_MESSAGE = "Invalid server migration inventory evidence.";
const ROOT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const invalid = () => { throw new TypeError(ERROR_MESSAGE); };
const byteCompare = (a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));

// The accepted evidence is JSON-like data, not executable accessors. Copy only
// exact own enumerable data properties; never echo a rejected key or value.
function exact(value, keys) {
  if (value === null || typeof value !== "object" ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const actualKeys = Reflect.ownKeys(descriptors);
  if (actualKeys.length !== keys.length || actualKeys.some((key) => !keys.includes(key))) invalid();
  const result = {};
  for (const key of keys) {
    const descriptor = descriptors[key];
    if (!descriptor || !Object.hasOwn(descriptor, "value") || !descriptor.enumerable) invalid();
    result[key] = descriptor.value;
  }
  return result;
}

function list(value, maxLength) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype) invalid();
  const length = Object.getOwnPropertyDescriptor(value, "length")?.value;
  if (!Number.isSafeInteger(length) || length < 0 || length > maxLength ||
      Reflect.ownKeys(value).length !== length + 1) invalid();
  const result = [];
  for (let index = 0; index < length; index += 1) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (!descriptor || !Object.hasOwn(descriptor, "value") || !descriptor.enumerable) invalid();
    result.push(descriptor.value);
  }
  return result;
}

function timestamp(value) {
  const result = exact(value, ["seconds", "nanoseconds"]);
  if (!Number.isSafeInteger(result.seconds) || result.seconds < 0 ||
      result.seconds > 253402300799 || Object.is(result.seconds, -0) ||
      !Number.isInteger(result.nanoseconds) || result.nanoseconds < 0 ||
      result.nanoseconds >= 1e9 || Object.is(result.nanoseconds, -0)) invalid();
  return result;
}

function compareTime(a, b) {
  return a.seconds - b.seconds || a.nanoseconds - b.nanoseconds;
}

function recordId(value) {
  // Deliberately narrower than Firestore's general document-ID envelope:
  // 1..128 UTF-16 units, valid Unicode, no slash/control/reserved ID. Imported
  // numeric __id...__ references have a different SDK comparator and are not
  // supported. Unsupported IDs must be reported externally, never dropped.
  if (!isValidOpaqueUid(value) || !value.isWellFormed() ||
      value === "." || value === ".." || /^__.*__$/u.test(value)) invalid();
  return value;
}

function nullableCursor(value) { return value === null ? null : recordId(value); }

function inspect(input) {
  const data = exact(input, ["inventoryVersion", "source", "observedRoot", "readTime", "pages"]);
  if (data.inventoryVersion !== INVENTORY_VERSION) invalid();
  const source = exact(data.source, ["kind", "id", "path", "expectedUpdateTime"]);
  if (!["club", "room"].includes(source.kind) || typeof source.id !== "string" || !ROOT_ID.test(source.id)) invalid();
  const parentPath = `${source.kind === "club" ? "clubs" : "rooms"}/${source.id}`;
  if (source.path !== parentPath) invalid();
  const expectedUpdateTime = timestamp(source.expectedUpdateTime);
  const readTime = timestamp(data.readTime);
  const observed = exact(data.observedRoot, ["path", "updateTime", "readTime"]);
  const observedUpdateTime = timestamp(observed.updateTime);
  if (observed.path !== parentPath || compareTime(timestamp(observed.readTime), readTime) !== 0 ||
      compareTime(observedUpdateTime, readTime) > 0) invalid();

  const requiredScopes = REQUIRED_SCOPES[source.kind];
  const pagesByScope = new Map(requiredScopes.map((scope) => [scope, []]));
  let totalRecords = 0;
  for (const raw of list(data.pages, MAX_INVENTORY_PAGES)) {
    const page = exact(raw, ["scope", "parentPath", "readTime", "pageIndex", "startAfter", "nextCursor", "exhausted", "records"]);
    if (!requiredScopes.includes(page.scope) || page.parentPath !== parentPath ||
        !Number.isSafeInteger(page.pageIndex) || page.pageIndex < 0 ||
        page.pageIndex >= MAX_INVENTORY_PAGES || Object.is(page.pageIndex, -0) ||
        typeof page.exhausted !== "boolean" || compareTime(timestamp(page.readTime), readTime) !== 0) invalid();
    const startAfter = nullableCursor(page.startAfter);
    const nextCursor = nullableCursor(page.nextCursor);
    const rawRecords = list(page.records, MAX_PAGE_RECORDS);
    totalRecords += rawRecords.length;
    if (totalRecords > MAX_INVENTORY_RECORDS) invalid();
    let previousId = startAfter;
    const records = rawRecords.map((rawRecord) => {
      const record = exact(rawRecord, ["id", "updateTime"]);
      const id = recordId(record.id);
      const updateTime = timestamp(record.updateTime);
      if (compareTime(updateTime, readTime) > 0 ||
          (previousId !== null && byteCompare(previousId, id) >= 0)) invalid();
      previousId = id;
      return { id, updateTime };
    });
    if (page.exhausted ? nextCursor !== null :
      (records.length === 0 || nextCursor !== records.at(-1).id)) invalid();
    pagesByScope.get(page.scope).push({ scope: page.scope, parentPath,
      readTime: { ...readTime }, pageIndex: page.pageIndex, startAfter, nextCursor,
      exhausted: page.exhausted, records });
  }

  const sourceVersionMatches = compareTime(expectedUpdateTime, observedUpdateTime) === 0;
  const unresolvedReasons = sourceVersionMatches ? [] : ["source-version-changed"];
  const canonicalPages = [];
  const claimedCollectionCoverage = requiredScopes.map((scope) => {
    const pages = pagesByScope.get(scope).sort((a, b) => a.pageIndex - b.pageIndex);
    let cursor = null;
    let exhausted = false;
    let recordCount = 0;
    for (let index = 0; index < pages.length; index += 1) {
      const page = pages[index];
      if (page.pageIndex !== index || exhausted || page.startAfter !== cursor) invalid();
      cursor = page.nextCursor;
      exhausted = page.exhausted;
      recordCount += page.records.length;
      canonicalPages.push(page);
    }
    let status = pages.length === 0 ? "missing" : exhausted ? "claimed-exhausted" : "unclosed";
    if (status === "missing") unresolvedReasons.push(`missing-scope:${scope}`);
    if (status === "unclosed") unresolvedReasons.push(`unclosed-scope:${scope}`);
    if (!sourceVersionMatches && pages.length > 0) status = "unresolved-source-change";
    return { scope, status, pageCount: pages.length, recordCount };
  });
  unresolvedReasons.sort(byteCompare);
  const body = {
    reportVersion: INVENTORY_VERSION,
    scope: "inventory-page-chain-only",
    dryRun: true,
    source: { kind: source.kind, id: source.id, path: parentPath, expectedUpdateTime, observedUpdateTime },
    readTime, sourceVersionMatches, requiredScopes: [...requiredScopes], claimedCollectionCoverage,
    evidenceStatus: unresolvedReasons.length === 0 ? "structurally-consistent-claims" : "unresolved",
    unresolvedReasons, unverifiedGates: [...UNVERIFIED_GATES],
    fullInventoryComplete: false, applyReady: false, writeCount: 0,
  };
  // Binds the supplied metadata, including IDs, without emitting those IDs.
  // A digest is not collector authentication or proof of database completeness.
  const reportDigest = crypto.createHash("sha256").update(JSON.stringify([body, canonicalPages])).digest("hex");
  return { ...body, reportDigest };
}

/**
 * Pure operator-evidence inspection. No SDK, queries, files, current clock,
 * grants, role conversion, capacity inference, idleness or mutation operations.
 * readTime and exhaustion are supplied claims, not independently observed fact.
 * Subchannels, media/generations, mirrors, bans and semantic validity remain
 * unverified even when every supported collection claims an exhausted chain.
 */
function inspectLegacyMigrationInventory(input) {
  try { return inspect(input); } catch { return invalid(); }
}

module.exports = { INVENTORY_VERSION, MAX_INVENTORY_RECORDS, MAX_INVENTORY_PAGES,
  MAX_PAGE_RECORDS, REQUIRED_SCOPES, inspectLegacyMigrationInventory };
