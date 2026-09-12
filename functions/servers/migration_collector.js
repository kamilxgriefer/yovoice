"use strict";

const crypto = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const { fail } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const {
  INVENTORY_VERSION, MAX_INVENTORY_PAGES, MAX_INVENTORY_RECORDS, MAX_PAGE_RECORDS,
  REQUIRED_SCOPES, inspectLegacyMigrationInventory,
} = require("./migration_inventory");
const { MAX_MAPPING_RECORDS, planLegacyServerMappings } = require("./migration_plan");

const MANIFEST_VERSION = 1;
const MAX_COLLECTOR_ROOTS = MAX_MAPPING_RECORDS;
// One pretty-printed manifest is a single V8 string, and a run of roughly 2.4M
// records reaches the engine's maximum string length: serialization would throw
// after every read of the run had already been spent. The run-wide record
// budget below keeps even a maximal run an order of magnitude under that.
const MAX_TOTAL_RECORDS = 1000000;
// The manifest digest binds the manifest bytes and is unkeyed on purpose:
// anyone holding the file can recompute it, so it proves transport integrity,
// never operator authorization and never that the database was read completely.
const DIGEST_PURPOSE = "unkeyed-sha256-integrity-checksum-of-the-manifest-bytes-" +
  "not-an-authorization-and-not-a-completeness-proof";
const ROOT_KINDS = Object.freeze(["club", "room"]);
const ROOT_COLLECTIONS = Object.freeze({ club: "clubs", room: "rooms" });
// Every required scope needs at least one page, and a non-empty scope at least
// one record, before a root can be reported as anything better than missing.
const MIN_PER_ROOT = Math.max(...ROOT_KINDS.map((kind) => REQUIRED_SCOPES[kind].length));
// A run that can no longer afford one record per required scope of the next
// root stops before that root instead of reporting it as an empty one.
const MIN_TOTAL_RECORDS = MIN_PER_ROOT;
const DEFAULT_OPTIONS = Object.freeze({
  pageSize: MAX_PAGE_RECORDS, maxPagesPerRoot: MAX_INVENTORY_PAGES,
  maxRecordsPerRoot: MAX_INVENTORY_RECORDS, maxRoots: 1000, maxTotalRecords: MAX_TOTAL_RECORDS,
});
// Exactly the root and channel fields planLegacyServerMappings evaluates.
// Names, descriptions, artwork, tokens, message bodies and every other field
// are never requested from Firestore, so they cannot reach the manifest.
const ROOT_FIELDS = Object.freeze({
  club: Object.freeze(["serverSchemaVersion", "serverType", "serverActivationState", "status",
    "deletionInProgress", "ownerId", "type", "privacy", "defaultChatChannelId",
    "defaultVoiceChannelId", "announcementChannelId", "loungeRoomId"]),
  room: Object.freeze(["serverSchemaVersion", "serverId", "status", "deletionInProgress", "hostId",
    "experience", "visibility", "isLive", "participantCount", "voiceSessionId", "clubId", "channelId"]),
});
const CHANNEL_FIELDS = Object.freeze(["serverSchemaVersion", "type", "isPrivate", "roomId"]);
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const PROJECT_ID = /^[a-z][a-z0-9-]{0,62}$/u;
const MAX_TIMESTAMP_SECONDS = 253402300799;

const byteCompare = (a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
const compareTime = (a, b) => a.seconds - b.seconds || a.nanoseconds - b.nanoseconds;
const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

function plainTimestamp(value) {
  const seconds = value?.seconds;
  const nanoseconds = value?.nanoseconds;
  if (!Number.isSafeInteger(seconds) || seconds < 0 || seconds > MAX_TIMESTAMP_SECONDS ||
      !Number.isInteger(nanoseconds) || nanoseconds < 0 || nanoseconds >= 1e9) {
    fail("internal", "A Firestore snapshot did not carry a usable timestamp.");
  }
  return { seconds, nanoseconds };
}

// Mirrors the inventory validator's record-ID envelope so unsupported IDs are
// reported as an unclosed scope instead of rejecting the whole root later.
function supportedRecordId(id) {
  return isValidOpaqueUid(id) && id.isWellFormed() && id !== "." && id !== ".." && !/^__.*__$/u.test(id);
}

function pick(data, fields) {
  const result = {};
  if (data === null || typeof data !== "object") return result;
  for (const field of fields) {
    if (Object.hasOwn(data, field)) result[field] = data[field];
  }
  return result;
}

function positiveInteger(value, label, min, max) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail("invalid-argument", `${label} is invalid.`);
  return value;
}

function collectorOptions(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    fail("invalid-argument", "Collector options are invalid.");
  }
  const allowed = Object.keys(DEFAULT_OPTIONS);
  if (Object.keys(input).some((key) => !allowed.includes(key))) {
    fail("invalid-argument", "Collector options contain an unsupported key.");
  }
  const merged = { ...DEFAULT_OPTIONS, ...input };
  return Object.freeze({
    pageSize: positiveInteger(merged.pageSize, "pageSize", 1, MAX_PAGE_RECORDS),
    maxPagesPerRoot: positiveInteger(merged.maxPagesPerRoot, "maxPagesPerRoot", MIN_PER_ROOT, MAX_INVENTORY_PAGES),
    maxRecordsPerRoot: positiveInteger(merged.maxRecordsPerRoot, "maxRecordsPerRoot", MIN_PER_ROOT, MAX_INVENTORY_RECORDS),
    maxRoots: positiveInteger(merged.maxRoots, "maxRoots", 1, MAX_COLLECTOR_ROOTS),
    maxTotalRecords: positiveInteger(merged.maxTotalRecords, "maxTotalRecords", MIN_TOTAL_RECORDS, MAX_TOTAL_RECORDS),
  });
}

function createSpan(parent = null) {
  let earliest = null;
  let latest = null;
  return {
    observe(value) {
      const time = plainTimestamp(value);
      if (earliest === null || compareTime(time, earliest) < 0) earliest = { ...time };
      if (latest === null || compareTime(time, latest) > 0) latest = { ...time };
      if (parent) parent.observe(time);
      return time;
    },
    latest: () => (latest === null ? null : { ...latest }),
    snapshot: () => ({ earliest: earliest && { ...earliest }, latest: latest && { ...latest } }),
  };
}

async function discoverRoots({ firestore, kind, remaining, pageSize, span }) {
  const roots = [];
  let cursor = null;
  let truncated = false;
  let orderBroken = false;
  for (;;) {
    const allowance = Math.max(0, Math.min(pageSize, remaining - roots.length));
    let query = firestore.collection(ROOT_COLLECTIONS[kind])
      .orderBy(FieldPath.documentId()).select().limit(allowance + 1);
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    span.observe(snapshot.readTime);
    const docs = snapshot.docs;
    for (const doc of docs.slice(0, allowance)) {
      // The same byte-order self-check the scope listings run: a backend that
      // collates document IDs differently than the cursor arithmetic assumes is
      // reported and stops discovery, never silently paged over.
      const previous = roots.length > 0 ? roots.at(-1).id : cursor;
      if (previous !== null && byteCompare(previous, doc.id) >= 0) { orderBroken = true; break; }
      roots.push({ id: doc.id, updateTime: plainTimestamp(doc.updateTime) });
    }
    if (orderBroken) break;
    if (docs.length <= allowance) break;
    if (roots.length >= remaining) { truncated = true; break; }
    cursor = roots.at(-1).id;
  }
  return { roots, truncated: truncated || orderBroken, orderBroken };
}

async function collectScope({ parent, scope, fields, budget, pageSize, span }) {
  const pages = [];
  const channels = [];
  const reasons = [];
  // The per-root and the run-wide record budgets are both hard limits; the
  // smaller one binds, and the reported reason names the one that did.
  const capacity = Math.min(budget.records, budget.totalRecords);
  const budgetReason = budget.totalRecords < budget.records
    ? "total-record-budget-exhausted" : "record-budget-exhausted";
  let cursor = null;
  let exhausted = false;
  let records = 0;
  while (!exhausted && pages.length < budget.pages) {
    const allowance = Math.max(0, Math.min(pageSize, capacity - records));
    let query = parent.collection(scope).orderBy(FieldPath.documentId())
      .select(...fields).limit(allowance + 1);
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    span.observe(snapshot.readTime);
    const docs = snapshot.docs;
    const more = docs.length > allowance;
    const kept = [];
    let stop = null;
    for (const doc of docs.slice(0, allowance)) {
      const previous = kept.length > 0 ? kept.at(-1).id : cursor;
      if (!supportedRecordId(doc.id)) { stop = "unsupported-record-id"; break; }
      if (previous !== null && byteCompare(previous, doc.id) >= 0) { stop = "unsupported-record-order"; break; }
      const updateTime = plainTimestamp(doc.updateTime);
      kept.push({ id: doc.id, updateTime });
      if (fields.length > 0) channels.push({ id: doc.id, updateTime, data: pick(doc.data(), fields) });
    }
    if (stop !== null) reasons.push(`${stop}:${scope}`);
    const terminal = stop === null && !more;
    if (kept.length === 0 && !terminal) {
      // A non-terminal page must make progress; report the reason instead.
      if (stop === null) reasons.push(`${budgetReason}:${scope}`);
      break;
    }
    pages.push({ scope, parentPath: parent.path, readTime: null, pageIndex: pages.length,
      startAfter: cursor, nextCursor: terminal ? null : kept.at(-1).id, exhausted: terminal, records: kept });
    records += kept.length;
    exhausted = terminal;
    if (stop !== null) break;
    if (!terminal) {
      cursor = kept.at(-1).id;
      if (records >= capacity) { reasons.push(`${budgetReason}:${scope}`); break; }
    }
  }
  if (!exhausted && reasons.length === 0) reasons.push(`page-budget-exhausted:${scope}`);
  return { pages, channels, reasons, records, exhausted };
}

// A root that discovery found but the run never read, because the run-wide
// record budget ran out first. It is reported as an uncollected root, never as
// a root whose collections happened to be empty.
function skippedRoot(kind, root) {
  return { kind, id: root.id, path: `${ROOT_COLLECTIONS[kind]}/${root.id}`, consistentSnapshot: false,
    readTimeSpan: { earliest: null, latest: null }, inventoryInput: null, inventoryReport: null,
    unresolved: ["collection-stopped-total-record-budget"] };
}

async function collectRoot({ firestore, kind, root, options, totalBudget, span: parentSpan }) {
  const path = `${ROOT_COLLECTIONS[kind]}/${root.id}`;
  const span = createSpan(parentSpan);
  const reasons = [];
  const entry = (patch) => ({ kind, id: root.id, path, consistentSnapshot: false,
    readTimeSpan: span.snapshot(), inventoryInput: null, inventoryReport: null,
    unresolved: [...new Set(reasons)].sort(compare), ...patch });
  if (!SAFE_ID.test(root.id)) {
    reasons.push("unsupported-root-id");
    return { entry: entry({}), mappingSource: null, records: 0 };
  }
  const parent = firestore.doc(path);
  const scopes = REQUIRED_SCOPES[kind];
  const pages = [];
  const channels = [];
  let pageTotal = 0;
  let recordTotal = 0;
  for (let index = 0; index < scopes.length; index += 1) {
    const scope = scopes[index];
    const reserve = scopes.length - 1 - index;
    const result = await collectScope({ parent, scope, span, pageSize: options.pageSize,
      fields: scope === "channels" ? CHANNEL_FIELDS : [],
      budget: { pages: options.maxPagesPerRoot - pageTotal - reserve,
        records: options.maxRecordsPerRoot - recordTotal - reserve,
        totalRecords: totalBudget - recordTotal - reserve } });
    pages.push(...result.pages);
    reasons.push(...result.reasons);
    pageTotal += result.pages.length;
    recordTotal += result.records;
    if (scope === "channels") {
      if (!result.exhausted) reasons.push("mapping-channels-incomplete");
      for (const channel of result.channels) {
        if (SAFE_ID.test(channel.id)) channels.push(channel);
        else reasons.push("unsupported-channel-id");
      }
    }
  }
  // Re-read the root after paging so a version change during collection is
  // reported by the validator instead of being hidden behind stale pages.
  const [verified] = await firestore.getAll(parent, { fieldMask: [...ROOT_FIELDS[kind]] });
  span.observe(verified.readTime);
  if (!verified.exists) {
    reasons.push("root-missing-at-verification");
    return { entry: entry({}), mappingSource: null, records: recordTotal };
  }
  const observedUpdateTime = plainTimestamp(verified.updateTime);
  const readTime = span.latest();
  const inventoryInput = {
    inventoryVersion: INVENTORY_VERSION,
    source: { kind, id: root.id, path, expectedUpdateTime: { ...root.updateTime } },
    observedRoot: { path, updateTime: observedUpdateTime, readTime: { ...readTime } },
    readTime: { ...readTime },
    pages: pages.map((page) => ({ ...page, readTime: { ...readTime } })),
  };
  let inventoryReport = null;
  try {
    inventoryReport = inspectLegacyMigrationInventory(inventoryInput);
    reasons.push(...inventoryReport.unresolvedReasons);
  } catch {
    reasons.push("inventory-evidence-rejected");
  }
  return {
    entry: entry({ inventoryInput, inventoryReport }),
    mappingSource: { data: pick(verified.data(), ROOT_FIELDS[kind]), updateTime: observedUpdateTime, channels },
    records: recordTotal,
  };
}

function summarize({ roots, discovered, truncated, mappingReport, mappingRecords, unresolved, span }) {
  const byScope = {};
  for (const kind of ROOT_KINDS) for (const scope of REQUIRED_SCOPES[kind]) byScope[scope] = 0;
  let pages = 0;
  for (const root of roots) {
    for (const page of root.inventoryInput?.pages ?? []) {
      pages += 1;
      byScope[page.scope] += page.records.length;
    }
  }
  const dispositions = { planned: 0, blocked: 0, deferred: 0, alreadyVersioned: 0 };
  for (const mapping of mappingReport?.mappings ?? []) {
    dispositions[mapping.disposition === "already-versioned" ? "alreadyVersioned" : mapping.disposition] += 1;
  }
  const unresolvedReasons = {};
  for (const item of unresolved) unresolvedReasons[item.reason] = (unresolvedReasons[item.reason] ?? 0) + 1;
  return {
    roots: {
      clubs: discovered.club.length, rooms: discovered.room.length,
      total: discovered.club.length + discovered.room.length, discoveryTruncated: truncated,
      inventoried: roots.filter((root) => root.inventoryReport !== null).length,
      structurallyConsistent: roots.filter((root) =>
        root.inventoryReport?.evidenceStatus === "structurally-consistent-claims").length,
      unresolved: roots.filter((root) => root.unresolved.length > 0).length,
      includedInMapping: mappingRecords.clubs + mappingRecords.rooms,
    },
    pages,
    records: { total: Object.values(byScope).reduce((sum, count) => sum + count, 0), byScope },
    mapping: {
      computed: mappingReport !== null, records: mappingRecords,
      dispositions: mappingReport ? dispositions : null,
      bindingIssues: mappingReport ? mappingReport.bindingIssues.length : null,
    },
    unresolvedReasons: Object.fromEntries(Object.entries(unresolvedReasons).sort(([a], [b]) => compare(a, b))),
    readTimeSpan: span.snapshot(),
  };
}

/**
 * Read-only legacy migration inventory collector. It discovers `clubs/{id}`
 * and `rooms/{id}` roots in bounded ID-ordered pages, lists each required
 * scope with an empty projection (channels: the mapping field allowlist),
 * re-reads each root with a field mask, and feeds the pure inventory
 * validator and mapping planner. It never constructs a write, batch,
 * transaction or bulk writer, and never reads names, bodies, media or tokens.
 * Sequential plain reads are not one consistent snapshot; the manifest says so.
 */
function createLegacyMigrationCollector(dependencies) {
  if (dependencies === null || typeof dependencies !== "object" || Array.isArray(dependencies)) {
    fail("invalid-argument", "Collector dependencies are invalid.");
  }
  const allowed = ["firestore", "projectId", "emulator", "clock"];
  if (Object.keys(dependencies).some((key) => !allowed.includes(key))) {
    fail("invalid-argument", "Collector dependencies contain an unsupported key.");
  }
  const { firestore, projectId, emulator, clock = Date.now } = dependencies;
  if (firestore === null || typeof firestore !== "object" ||
      ["collection", "doc", "getAll"].some((method) => typeof firestore[method] !== "function")) {
    fail("invalid-argument", "A Firestore instance is required.");
  }
  if (typeof projectId !== "string" || !PROJECT_ID.test(projectId)) fail("invalid-argument", "projectId is invalid.");
  if (typeof emulator !== "boolean") fail("invalid-argument", "emulator must be a boolean.");
  if (typeof clock !== "function") fail("invalid-argument", "clock must be a function.");

  async function collect(rawOptions = {}) {
    const options = collectorOptions(rawOptions);
    const now = clock();
    if (!Number.isSafeInteger(now) || now < 0) fail("internal", "The clock did not return a usable time.");
    const generatedAt = new Date(now).toISOString();
    const span = createSpan();
    const discovered = { club: [], room: [] };
    const discoveryReasons = [];
    let truncated = false;
    let remaining = options.maxRoots;
    for (const kind of ROOT_KINDS) {
      const collection = ROOT_COLLECTIONS[kind];
      const result = await discoverRoots({ firestore, kind, remaining, pageSize: options.pageSize, span });
      discovered[kind] = result.roots;
      if (result.orderBroken) discoveryReasons.push(`unsupported-root-order:${collection}`);
      if (result.truncated) {
        discoveryReasons.push(`root-discovery-truncated:${collection}`);
        // maxRoots is one budget the root collections consume in order, so a
        // later collection can be starved by an earlier one. That is reported
        // per collection instead of being hidden inside one run-wide flag.
        if (remaining < options.maxRoots) discoveryReasons.push(`root-discovery-starved:${collection}`);
      }
      remaining -= result.roots.length;
      truncated = truncated || result.truncated;
    }
    const roots = [];
    const mappingInput = { clubs: [], rooms: [], channels: [], ownerOverrides: [] };
    let recordBudget = options.maxTotalRecords;
    let stopped = false;
    for (const kind of ROOT_KINDS) {
      for (const root of discovered[kind]) {
        if (recordBudget < MIN_TOTAL_RECORDS) {
          // Stop collecting instead of throwing once the manifest cannot grow
          // any further; every remaining root says why it was not read.
          stopped = true;
          roots.push(skippedRoot(kind, root));
          continue;
        }
        const { entry, mappingSource, records } = await collectRoot({ firestore, kind, root, options,
          totalBudget: recordBudget, span });
        recordBudget -= records;
        roots.push(entry);
        if (!mappingSource) continue;
        const snapshot = { id: root.id, data: mappingSource.data, updateTime: mappingSource.updateTime };
        (kind === "club" ? mappingInput.clubs : mappingInput.rooms).push(snapshot);
        for (const channel of mappingSource.channels) {
          mappingInput.channels.push({ serverId: root.id, id: channel.id, data: channel.data, updateTime: channel.updateTime });
        }
      }
    }
    const mappingRecords = { clubs: mappingInput.clubs.length, rooms: mappingInput.rooms.length,
      channels: mappingInput.channels.length, ownerOverrides: 0 };
    const mappingTotal = mappingRecords.clubs + mappingRecords.rooms + mappingRecords.channels;
    const unresolved = [];
    let mappingReport = null;
    if (mappingTotal > MAX_MAPPING_RECORDS) {
      unresolved.push({ path: null, reason: "mapping-input-exceeds-limit" });
    } else {
      try {
        mappingReport = planLegacyServerMappings(mappingInput);
      } catch {
        unresolved.push({ path: null, reason: "mapping-input-rejected" });
      }
    }
    if (truncated) unresolved.push({ path: null, reason: "root-discovery-truncated" });
    for (const reason of discoveryReasons) unresolved.push({ path: null, reason });
    if (stopped) unresolved.push({ path: null, reason: "total-record-budget-exhausted" });
    for (const root of roots) {
      for (const reason of root.unresolved) unresolved.push({ path: root.path, reason });
    }
    for (const mapping of mappingReport?.mappings ?? []) {
      if (!["blocked", "deferred"].includes(mapping.disposition)) continue;
      for (const reason of mapping.reasons) unresolved.push({ path: mapping.sourcePath, reason: `mapping:${reason}` });
    }
    for (const issue of mappingReport?.bindingIssues ?? []) {
      unresolved.push({ path: issue.sourcePath, reason: `binding:${issue.reason}` });
    }
    const unique = new Map(unresolved.map((item) => [`${item.path ?? ""} ${item.reason}`, item]));
    const sortedUnresolved = [...unique.values()].sort((a, b) =>
      compare(a.path ?? "", b.path ?? "") || compare(a.reason, b.reason));
    return {
      manifestVersion: MANIFEST_VERSION,
      scope: "read-only-inventory-and-mapping-dry-run",
      dryRun: true,
      digestPurpose: DIGEST_PURPOSE,
      generatedAt,
      projectId,
      emulator,
      collector: {
        ...options, rootFields: { club: [...ROOT_FIELDS.club], room: [...ROOT_FIELDS.room] },
        channelFields: [...CHANNEL_FIELDS], scopeListingFields: [],
        readMode: "sequential-plain-reads", consistentSnapshot: false,
      },
      roots,
      mappingReport,
      unresolved: sortedUnresolved,
      summary: summarize({ roots, discovered, truncated, mappingReport, mappingRecords, unresolved: sortedUnresolved, span }),
      fullInventoryComplete: false,
      applyReady: false,
      writeCount: 0,
    };
  }

  return Object.freeze({ collect });
}

function serializeManifest(manifest) {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

function manifestDigest(text) {
  if (typeof text !== "string") fail("invalid-argument", "The manifest text is invalid.");
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

module.exports = {
  CHANNEL_FIELDS, DEFAULT_OPTIONS, DIGEST_PURPOSE, MANIFEST_VERSION, MAX_COLLECTOR_ROOTS,
  MAX_TOTAL_RECORDS, MIN_TOTAL_RECORDS, ROOT_FIELDS,
  createLegacyMigrationCollector, manifestDigest, serializeManifest,
};
