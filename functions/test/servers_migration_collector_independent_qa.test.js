"use strict";
// Independent QA regressions for the servers migration dry-run collector (S1).
// Complements servers_migration_collector.test.js with cases its author did not
// write: page-size boundaries, UTF-16/UTF-8 ordering and the 128/129 envelope,
// root drift injected between scope listings, content isolation against a
// manifest key universe, budget minimums, an SDK-boundary read allowlist, CLI
// process refusals, determinism/tamper checks and prototype-named IDs. Pure
// cases use an in-memory fake backend; emulator cases run only against an
// explicit localhost Firestore emulator and write test-owned fixtures only.

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { after, test } = require("node:test");
const adminApp = require("firebase-admin/app");
const firestoreModule = require("firebase-admin/firestore");
const { REQUIRED_SCOPES, inspectLegacyMigrationInventory } = require("../servers/migration_inventory");
const {
  CHANNEL_FIELDS, DEFAULT_OPTIONS, ROOT_FIELDS, createLegacyMigrationCollector, manifestDigest, serializeManifest,
} = require("../servers/migration_collector");
const cli = require("../scripts/servers_migration_dry_run");

const { Timestamp } = firestoreModule;
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const SCRIPT = path.resolve(__dirname, "../scripts/servers_migration_dry_run.js");
const FIXED_CLOCK = 1_800_000_000_000;
const OWNER = "qa-owner-uid-9d1e";
const HOST = "qa-host-uid-9d1e";
const WIDE_A = "Ａ"; // FULLWIDTH LATIN CAPITAL LETTER A: UTF-16 FF21, UTF-8 EF BC A1
const GRIN = "\u{1F600}"; // GRINNING FACE: UTF-16 D83D DE00, UTF-8 F0 9F 98 80
const ID_128 = "x".repeat(128);
const ID_129 = "x".repeat(129);
const SECRET_MARK = "SECRET-9d1e";
const CONTENT_KEYS = ["text", "name", "description", "photoUrl", "token", "url", "body", "attachments"];
const NEVER_KEYS = [...CONTENT_KEYS, "imageUrl", "avatarUrl", "displayName", "hostName", "senderName", "senderId",
  "userId", "role", "memberCount", "position", "createdAt", "updatedAt", "createdBy", "category", "joinedAt", "isSpeaker"];
// Every key the manifest may legitimately carry (summary.unresolvedReasons and
// summary.records.byScope are checked separately because their keys are values).
const KNOWN_KEYS = new Set([
  "manifestVersion", "scope", "dryRun", "generatedAt", "projectId", "emulator", "collector", "pageSize", "maxPagesPerRoot",
  "maxRecordsPerRoot", "maxRoots", "rootFields", "club", "room", "channelFields", "scopeListingFields", "readMode",
  "consistentSnapshot", "roots", "kind", "id", "path", "readTimeSpan", "earliest", "latest", "seconds", "nanoseconds",
  "inventoryInput", "inventoryVersion", "source", "expectedUpdateTime", "observedRoot", "updateTime", "readTime", "pages",
  "parentPath", "pageIndex", "startAfter", "nextCursor", "exhausted", "records", "inventoryReport", "reportVersion",
  "observedUpdateTime", "sourceVersionMatches", "requiredScopes", "claimedCollectionCoverage", "status", "pageCount",
  "recordCount", "evidenceStatus", "unresolvedReasons", "unverifiedGates", "fullInventoryComplete", "applyReady",
  "writeCount", "reportDigest", "unresolved", "mappingReport", "requiredNextGates", "mappings", "sourcePath",
  "sourceVersion", "versionFingerprint", "disposition", "reasons", "serverId", "ownerId", "serverType", "privacy",
  "entitlementPolicyId", "provenance", "version", "sourceKind", "sourceId", "memberships", "channelId", "bindingAction",
  "reciprocalSourceVersion", "originalRoomId", "roomHistorySource", "roomId", "preserveRoomMediaAndNotificationIdentity",
  "sessionEvidence", "isLive", "participantCount", "voiceSessionId", "transientParticipants", "bindingIssues", "reason",
  "summary", "clubs", "rooms", "total", "discoveryTruncated", "inventoried", "structurallyConsistent", "includedInMapping",
  "byScope", "mapping", "computed", "ownerOverrides", "dispositions", "planned", "blocked", "deferred", "alreadyVersioned",
  // Completed on re-verification. `channels` (summary.mapping.records.channels)
  // predates this slice and was simply missing from the universe; the run-wide
  // record budget `maxTotalRecords` and the digest's domain-separation label
  // `digestPurpose` are the S1 P2-1 fix. All three are collector metadata, so
  // adding them keeps the property this test exists for: no CONTENT key and no
  // unannounced field may reach the manifest (NEVER_KEYS below is unchanged).
  "maxTotalRecords", "digestPurpose", "channels",
]);

const byteCompare = (a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
const utf16Compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const byteSorted = (ids) => [...ids].sort(byteCompare);
const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);
const rejectsAsync = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const rootByPath = (manifest, rootPath) => manifest.roots.find((root) => root.path === rootPath);
const mappingByPath = (manifest, rootPath) => manifest.mappingReport?.mappings.find((item) => item.sourcePath === rootPath);
const pagesFor = (root, scope) => root.inventoryInput.pages.filter((page) => page.scope === scope);
const recordIds = (root, scope) => pagesFor(root, scope).flatMap((page) => page.records.map((record) => record.id));
const coverageFor = (root, scope) => root.inventoryReport.claimedCollectionCoverage.find((item) => item.scope === scope);
const clubData = (extra = {}) => ({ ownerId: OWNER, type: "community", privacy: "public", status: "active", ...extra });
const roomData = (extra = {}) => ({ hostId: HOST, experience: "community", visibility: "public", isLive: false,
  participantCount: 0, status: "active", ...extra });
const range = (prefix, count) => Array.from({ length: count }, (_, index) => `${prefix}${String(index + 1).padStart(3, "0")}`);
const pureCollector = (firestore, projectId = "demo-fake") =>
  createLegacyMigrationCollector({ firestore, projectId, emulator: true, clock: () => FIXED_CLOCK });

const apps = [];
function namespace(label) {
  const projectId = `demo-yovoice-qa-${label}-${randomUUID().slice(0, 8)}`;
  const app = adminApp.initializeApp({ projectId }, `qa-${label}-${randomUUID()}`);
  apps.push(app);
  const db = firestoreModule.getFirestore(app);
  const collector = (firestore = db, clock = () => FIXED_CLOCK) =>
    createLegacyMigrationCollector({ firestore, projectId, emulator: true, clock });
  return { projectId, db, collector };
}
after(async () => { for (const app of apps) await adminApp.deleteApp(app); });

async function seedDocs(db, docs) {
  for (let index = 0; index < docs.length; index += 400) {
    const batch = db.batch();
    for (const [docPath, data] of docs.slice(index, index + 400)) batch.set(db.doc(docPath), data);
    await batch.commit();
  }
}

async function census(db) {
  const out = new Map();
  const visit = async (parent) => {
    for (const collection of await parent.listCollections()) {
      for (const document of await collection.listDocuments()) {
        const snapshot = await document.get();
        out.set(document.path, snapshot.exists ? `${snapshot.updateTime.seconds}.${snapshot.updateTime.nanoseconds}` : "missing");
        await visit(document);
      }
    }
  };
  await visit(db);
  return out;
}

function walk(value, visitor, trail = []) {
  if (Array.isArray(value)) value.forEach((item, index) => walk(item, visitor, [...trail, String(index)]));
  else if (value !== null && typeof value === "object") {
    visitor.object?.(value, trail);
    for (const [key, item] of Object.entries(value)) { visitor.key?.(key, trail); walk(item, visitor, [...trail, key]); }
  }
}

// Asserts one scope's page chain is exactly the validator-shaped chain for the
// given byte-ordered IDs at pageSize, and that the validator claimed it exhausted.
function assertExhaustedChain(root, scope, expectedIds, pageSize) {
  const pages = pagesFor(root, scope);
  const expectedPages = expectedIds.length === 0 ? 1 : Math.ceil(expectedIds.length / pageSize);
  assert.equal(pages.length, expectedPages, `${root.path}/${scope} pages at pageSize ${pageSize}`);
  let cursor = null;
  pages.forEach((page, index) => {
    const last = index === pages.length - 1;
    assert.equal(page.pageIndex, index);
    assert.equal(page.parentPath, root.path);
    assert.equal(page.startAfter, cursor);
    assert.equal(page.exhausted, last);
    assert.equal(page.records.length, last ? expectedIds.length - index * pageSize : pageSize);
    assert.equal(page.nextCursor, last ? null : page.records.at(-1).id);
    cursor = page.nextCursor;
  });
  assert.deepEqual(recordIds(root, scope), expectedIds);
  assert.deepEqual(coverageFor(root, scope), { scope, status: "claimed-exhausted", pageCount: expectedPages, recordCount: expectedIds.length });
}

// In-memory backend with a configurable ID collation so ordering behaviour is
// proven deterministically instead of depending on the emulator's collation.
function fakeFirestore({ order = byteCompare, roots, ignoreCursor = false, skew = 0 }) {
  const at = (offset) => ({ seconds: 1_700_000_000 + offset, nanoseconds: 0 });
  const project = (data, fields) => Object.fromEntries((fields ?? []).filter((field) => Object.hasOwn(data ?? {}, field))
    .map((field) => [field, data[field]]));
  const rowOf = (row) => (typeof row === "string" ? { id: row, data: {} } : row);
  const queryFor = (rows) => {
    const state = { limit: Number.POSITIVE_INFINITY, after: null, fields: null };
    const query = {
      orderBy: () => query,
      select: (...fields) => { state.fields = fields; return query; },
      limit: (count) => { state.limit = count; return query; },
      startAfter: (cursor) => { state.after = cursor; return query; },
      async get() {
        let sorted = rows.map(rowOf).sort((a, b) => order(a.id, b.id));
        if (state.after !== null && !ignoreCursor) sorted = sorted.filter((row) => order(row.id, state.after) > 0);
        return { readTime: at(2), docs: sorted.slice(0, state.limit).map((row) => ({ id: row.id, updateTime: at(1 + skew),
          data: () => project(row.data, state.fields) })) };
      },
    };
    return query;
  };
  return {
    collection: (name) => queryFor(Object.keys(roots).filter((docPath) => docPath.startsWith(`${name}/`))
      .map((docPath) => ({ id: docPath.slice(name.length + 1), data: roots[docPath].data }))),
    doc: (docPath) => ({ path: docPath, collection: (scope) => queryFor(roots[docPath]?.scopes?.[scope] ?? []) }),
    getAll: async (reference, options) => {
      const root = roots[reference.path];
      return [{ exists: root !== undefined, readTime: at(3), updateTime: root ? at(1) : undefined,
        data: () => project(root?.data, options.fieldMask) }];
    },
  };
}

// Strict SDK-boundary recorder: every property the collector touches must be on
// the allowlist (so any write or unexpected surface throws), arguments are
// unwrapped before reaching the SDK, and each call is logged with its origin.
function recordingFirestore(db, log) {
  const ALLOW = {
    Firestore: ["collection", "doc", "getAll"],
    CollectionReference: ["orderBy", "select", "limit", "startAfter", "get"],
    Query: ["orderBy", "select", "limit", "startAfter", "get"],
    DocumentReference: ["collection", "path", "id"],
    QuerySnapshot: ["docs", "readTime"],
    QueryDocumentSnapshot: ["id", "updateTime", "data", "exists", "readTime"],
    DocumentSnapshot: ["id", "updateTime", "data", "exists", "readTime"],
  };
  const RAW = new Set(["Object", "Array", "Timestamp"]);
  const targets = new WeakMap();
  const unwrap = (value) => (value !== null && typeof value === "object" && targets.has(value) ? targets.get(value) : value);
  const describe = (value) => (value !== null && typeof value === "object" && typeof value.path === "string" ? value.path : value);
  function wrap(value, origin) {
    if (value === null || typeof value !== "object") return value;
    if (typeof value.then === "function") return value.then((resolved) => wrap(resolved, origin));
    if (Array.isArray(value)) return value.map((item) => wrap(item, origin));
    const kind = value.constructor?.name;
    if (RAW.has(kind)) return value;
    assert.ok(ALLOW[kind], `unexpected SDK object reached the collector: ${kind}`);
    const proxy = new Proxy(value, {
      get(target, property) {
        if (typeof property === "symbol") return Reflect.get(target, property, target);
        // `await snapshot` (and any promise resolution) probes `.then` on the
        // resolved value before anything else touches it. That probe is the
        // JavaScript runtime's, not the collector's, so answering "not a
        // thenable" is the honest reply; throwing here made every awaited
        // wrapped snapshot fail as a forbidden access. Real SDK surface is
        // unaffected: a genuine `then` method would still be refused below.
        if (property === "then" && typeof Reflect.get(target, property, target) !== "function") return undefined;
        if (!ALLOW[kind].includes(property)) throw new Error(`unexpected access ${kind}.${property}`);
        const member = Reflect.get(target, property, target);
        if (typeof member !== "function") return wrap(member, origin);
        return (...args) => {
          const plain = args.map(unwrap);
          log.push({ kind, method: property, origin, args: plain.map(describe) });
          const nextOrigin = property === "collection" ? plain[0] : origin;
          return wrap(member.apply(target, plain), nextOrigin);
        };
      },
    });
    targets.set(proxy, value);
    return proxy;
  }
  return wrap(db, null);
}

// Wraps a query chain so the test-owned mutation runs right before its get().
function wrapQuery(query, beforeGet) {
  return new Proxy(query, {
    get(target, property) {
      const member = Reflect.get(target, property, target);
      if (property === "get") return async (...args) => { await beforeGet(); return member.apply(target, args); };
      if (typeof member === "function") return (...args) => wrapQuery(member.apply(target, args), beforeGet);
      return member;
    },
  });
}

// Fires each root's trigger once, immediately before that root's `scope`
// listing is read (i.e. after earlier scopes were paged, before verification).
function mutateBeforeScope(db, scope, triggers) {
  const pending = new Map(Object.entries(triggers));
  const targets = new WeakMap();
  const unwrap = (value) => (value !== null && typeof value === "object" && targets.has(value) ? targets.get(value) : value);
  return new Proxy(db, {
    get(target, property) {
      const member = Reflect.get(target, property, target);
      if (property === "getAll") return (...args) => member.apply(target, args.map(unwrap));
      if (property !== "doc") return typeof member === "function" ? member.bind(target) : member;
      return (docPath) => {
        const reference = member.call(target, docPath);
        if (!pending.has(docPath)) return reference;
        const proxy = new Proxy(reference, {
          get(referenceTarget, referenceProperty) {
            const inner = Reflect.get(referenceTarget, referenceProperty, referenceTarget);
            if (referenceProperty !== "collection") return typeof inner === "function" ? inner.bind(referenceTarget) : inner;
            return (name) => {
              const collectionReference = inner.call(referenceTarget, name);
              if (name !== scope || !pending.has(docPath)) return collectionReference;
              const trigger = pending.get(docPath);
              pending.delete(docPath);
              return wrapQuery(collectionReference, trigger);
            };
          },
        });
        targets.set(proxy, reference);
        return proxy;
      };
    },
  });
}

function runCli(args, env) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { env, encoding: "utf8", timeout: 120_000 });
}

function scrubVolatile(manifest) {
  const copy = JSON.parse(JSON.stringify(manifest));
  delete copy.generatedAt;
  delete copy.summary.readTimeSpan;
  for (const root of copy.roots) {
    delete root.readTimeSpan;
    if (root.inventoryInput) {
      delete root.inventoryInput.readTime;
      delete root.inventoryInput.observedRoot.readTime;
      for (const page of root.inventoryInput.pages) delete page.readTime;
    }
    if (root.inventoryReport) { delete root.inventoryReport.readTime; delete root.inventoryReport.reportDigest; }
  }
  return copy;
}

// ---------------------------------------------------------------------------
// Pure cases (no emulator): collation, envelope and hostile backends.
// ---------------------------------------------------------------------------

test("a UTF-16-collated backend yields unsupported-record-order, never a chain the validator rejects", async () => {
  const ids = ["a", WIDE_A, GRIN, "z"];
  assert.deepEqual(byteSorted(ids), ["a", "z", WIDE_A, GRIN]);
  assert.deepEqual([...ids].sort(utf16Compare), ["a", "z", GRIN, WIDE_A]);
  for (const pageSize of [1, 2, 3, 500]) {
    const firestore = fakeFirestore({ order: utf16Compare, roots: { "clubs/order_club": { data: clubData(), scopes: { members: ids } } } });
    const manifest = await pureCollector(firestore).collect({ pageSize });
    const root = rootByPath(manifest, "clubs/order_club");
    assert.notEqual(root.inventoryReport, null, `validator rejected the emitted chain at pageSize ${pageSize}`);
    assert.equal(root.unresolved.includes("inventory-evidence-rejected"), false);
    assert.deepEqual(root.unresolved, ["unclosed-scope:members", "unsupported-record-order:members"]);
    assert.equal(coverageFor(root, "members").status, "unclosed");
    assert.deepEqual(recordIds(root, "members"), ["a", "z", GRIN], `pageSize ${pageSize}`);
    assert.ok(pagesFor(root, "members").every((page) => page.records.length > 0));
    assert.equal(manifest.summary.unresolvedReasons["unsupported-record-order:members"], 1);
    assert.equal(mappingByPath(manifest, "clubs/order_club").disposition, "planned");
  }
  for (const pageSize of [1, 3, 4, 500]) {
    const firestore = fakeFirestore({ order: byteCompare, roots: { "clubs/order_club": { data: clubData(), scopes: { members: ids } } } });
    const manifest = await pureCollector(firestore).collect({ pageSize });
    const root = rootByPath(manifest, "clubs/order_club");
    assert.equal(root.inventoryReport.evidenceStatus, "structurally-consistent-claims");
    assertExhaustedChain(root, "members", byteSorted(ids), pageSize);
    assert.deepEqual(manifest.unresolved, []);
  }
});

test("envelope-violating record IDs are reported and never emitted, including as the first record of a scope", async () => {
  const cases = [["lone-surrogate", "\uD800abc"], ["dot", "."], ["dot-dot", ".."], ["reserved", "__id7__"],
    ["proto", "__proto__"], ["129-units", ID_129], ["slash", "a/b"], ["control", "ab"]];
  for (const [label, bad] of cases) {
    const scopeIds = ["a", bad, "zz"];
    const firestore = fakeFirestore({ roots: { "clubs/env": { data: clubData(), scopes: { members: scopeIds } } } });
    const manifest = await pureCollector(firestore).collect({ pageSize: 2 });
    const root = rootByPath(manifest, "clubs/env");
    assert.notEqual(root.inventoryReport, null, label);
    assert.ok(root.unresolved.includes("unsupported-record-id:members"), label);
    assert.equal(root.unresolved.includes("inventory-evidence-rejected"), false, label);
    const kept = recordIds(root, "members");
    assert.equal(kept.includes(bad), false, label);
    const expectedPrefix = byteSorted(scopeIds).slice(0, byteSorted(scopeIds).indexOf(bad));
    assert.deepEqual(kept, expectedPrefix, label);
    // A scope whose very first listed record is unsupported cannot carry an
    // empty unclosed page (validator contract), so it surfaces as missing-scope
    // together with the collector's own unsupported-record-id reason.
    assert.equal(coverageFor(root, "members").status, expectedPrefix.length === 0 ? "missing" : "unclosed", label);
    if (bad.length > 2) assert.equal(JSON.stringify(manifest).includes(JSON.stringify(bad).slice(1, -1)), false, label);
  }
  const boundary = fakeFirestore({ roots: { "clubs/env": { data: clubData(),
    scopes: { members: ["__proto", "a", ID_128, ID_129], channels: [{ id: ID_128, data: { type: "chat", isPrivate: false } }] } } } });
  const manifest = await pureCollector(boundary).collect();
  const root = rootByPath(manifest, "clubs/env");
  assert.deepEqual(recordIds(root, "members"), ["__proto", "a", ID_128]);
  assert.deepEqual(root.unresolved, ["unclosed-scope:members", "unsupported-record-id:members"]);
  assert.equal(manifest.summary.mapping.records.channels, 1);
  assert.equal(manifest.mappingReport.bindingIssues.length, 0);
});

test("a backend that ignores cursors or repeats IDs is reported as unsupported-record-order", async () => {
  const ignoring = fakeFirestore({ ignoreCursor: true, roots: { "clubs/c": { data: clubData(), scopes: { members: ["a", "b", "c"] } } } });
  let manifest = await pureCollector(ignoring).collect({ pageSize: 2 });
  let root = rootByPath(manifest, "clubs/c");
  assert.deepEqual(recordIds(root, "members"), ["a", "b"]);
  assert.deepEqual(root.unresolved, ["unclosed-scope:members", "unsupported-record-order:members"]);
  assert.equal(pagesFor(root, "members").length, 1);
  const repeating = fakeFirestore({ roots: { "clubs/c": { data: clubData(), scopes: { members: ["a", "a", "b"] } } } });
  manifest = await pureCollector(repeating).collect();
  root = rootByPath(manifest, "clubs/c");
  assert.deepEqual(recordIds(root, "members"), ["a"]);
  assert.deepEqual(root.unresolved, ["unclosed-scope:members", "unsupported-record-order:members"]);
  assert.equal(root.inventoryReport.evidenceStatus, "unresolved");
});

test("a backend whose record times exceed its read time is recorded as inventory-evidence-rejected", async () => {
  const skewed = fakeFirestore({ skew: 10, roots: { "rooms/r": { data: roomData(), scopes: { messages: ["m1"] } } } });
  const manifest = await pureCollector(skewed).collect();
  const root = rootByPath(manifest, "rooms/r");
  assert.deepEqual(root.unresolved, ["inventory-evidence-rejected"]);
  assert.equal(root.inventoryReport, null);
  assert.equal(root.inventoryInput.pages.length, 3);
  assert.throws(() => inspectLegacyMigrationInventory(root.inventoryInput), TypeError);
  // Observation: the root still receives a mapping disposition; reviewers must
  // cross-reference `unresolved`, and applyReady stays false.
  assert.equal(mappingByPath(manifest, "rooms/r").disposition, "planned");
  assert.equal(manifest.summary.roots.inventoried, 0);
  assert.equal(manifest.summary.roots.unresolved, 1);
  assert.equal(manifest.applyReady, false);
});

test("option and dependency envelopes reject below-minimum values, prototype keys and non-integers", async () => {
  const firestore = fakeFirestore({ roots: {} });
  const collector = pureCollector(firestore);
  for (const options of [{ maxPagesPerRoot: 2 }, { maxRecordsPerRoot: 2 }, { pageSize: 0 }, { pageSize: 501 }, { maxRoots: 0 },
    { maxRoots: 10001 }, { pageSize: 1.5 }, { pageSize: "5" }, { pageSize: Number.NaN }, { pageSize: Number.POSITIVE_INFINITY },
    { maxPagesPerRoot: 2 ** 53 }, { pageSize: null }, { ["__proto__"]: { pageSize: 1 } }, { constructor: 1 }, [], null, "x"]) {
    await rejectsAsync(collector.collect(options), "invalid-argument");
  }
  for (const options of [{ maxPagesPerRoot: 3, maxRecordsPerRoot: 3, pageSize: 1, maxRoots: 1 },
    { maxPagesPerRoot: 1000, maxRecordsPerRoot: 10000, pageSize: 500, maxRoots: 10000 }, Object.create({ pageSize: 0 })]) {
    const manifest = await collector.collect(options);
    assert.equal(manifest.roots.length, 0);
  }
  assert.equal((await collector.collect(Object.create({ pageSize: 0 }))).collector.pageSize, DEFAULT_OPTIONS.pageSize);
  rejects(() => createLegacyMigrationCollector({ firestore, projectId: "demo-fake", emulator: true, extra: 1 }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore, projectId: "Demo", emulator: true }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore, projectId: "demo-fake", emulator: "true" }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore: { ...firestore, getAll: null }, projectId: "demo-fake", emulator: true }), "invalid-argument");
  assert.equal(cli.parseArguments(["--out", "dir", "--page-size", "007"]).value?.pageSize, 7);
});

// ---------------------------------------------------------------------------
// Emulator cases.
// ---------------------------------------------------------------------------

emulatorTest("scopes with exactly pageSize, pageSize+1 and 0 records chain into validator-accepted exhausted pages", async () => {
  const ns = namespace("pages");
  const members = range("m", 4);
  const invites = range("i", 5);
  const participants = range("p", 3);
  const messages = range("msg", 6);
  await seedDocs(ns.db, [
    ["clubs/page_club", clubData()], ...members.map((id) => [`clubs/page_club/members/${id}`, { role: "member" }]),
    ...invites.map((id) => [`clubs/page_club/invites/${id}`, { status: "pending" }]),
    ["rooms/page_room", roomData()], ...participants.map((id) => [`rooms/page_room/participants/${id}`, { isSpeaker: false }]),
    ...messages.map((id) => [`rooms/page_room/messages/${id}`, { position: 0 }]),
  ]);
  for (const pageSize of [1, 2, 3, 4, 5, 6, 7, 500]) {
    const manifest = await ns.collector().collect({ pageSize });
    const club = rootByPath(manifest, "clubs/page_club");
    const room = rootByPath(manifest, "rooms/page_room");
    assertExhaustedChain(club, "members", members, pageSize);
    assertExhaustedChain(club, "invites", invites, pageSize);
    assertExhaustedChain(club, "channels", [], pageSize);
    assertExhaustedChain(room, "roomMembers", [], pageSize);
    assertExhaustedChain(room, "participants", participants, pageSize);
    assertExhaustedChain(room, "messages", messages, pageSize);
    for (const root of [club, room]) {
      assert.equal(root.inventoryReport.evidenceStatus, "structurally-consistent-claims", `pageSize ${pageSize}`);
      assert.deepEqual(inspectLegacyMigrationInventory(root.inventoryInput), root.inventoryReport);
    }
    assert.deepEqual(manifest.unresolved, []);
    assert.deepEqual(manifest.summary.records, { total: 18, byScope: { members: 4, invites: 5, channels: 0, roomMembers: 0, participants: 3, messages: 6 } });
    assert.equal(manifest.summary.pages, club.inventoryInput.pages.length + room.inventoryInput.pages.length);
    assert.equal(manifest.summary.roots.structurallyConsistent, 2);
  }
});

emulatorTest("emulator-stored non-ASCII IDs and the 128/129 boundary produce validator-accepted chains only", async (t) => {
  const ns = namespace("order");
  const members = ["a", WIDE_A, GRIN, "z"];
  await seedDocs(ns.db, [
    ["clubs/order_club", clubData()], ...members.map((id) => [`clubs/order_club/members/${id}`, { role: "member" }]),
    [`clubs/order_club/invites/${ID_128}`, { status: "pending" }], [`clubs/order_club/invites/${ID_129}`, { status: "pending" }],
    [`clubs/order_club/channels/${ID_128}`, { type: "chat", isPrivate: false }],
    ["clubs/order_club/channels/ch+plus", { type: "chat", isPrivate: false }],
  ]);
  for (const pageSize of [1, 2, 500]) {
    const manifest = await ns.collector().collect({ pageSize });
    const root = rootByPath(manifest, "clubs/order_club");
    assert.notEqual(root.inventoryReport, null, `validator rejected the chain at pageSize ${pageSize}`);
    assert.equal(root.unresolved.includes("inventory-evidence-rejected"), false);
    assert.deepEqual(inspectLegacyMigrationInventory(root.inventoryInput), root.inventoryReport);
    const kept = recordIds(root, "members");
    for (let index = 1; index < kept.length; index += 1) assert.ok(byteCompare(kept[index - 1], kept[index]) < 0);
    if (root.unresolved.includes("unsupported-record-order:members")) {
      t.diagnostic(`emulator collates document IDs by UTF-16 code units (pageSize ${pageSize}); collector reported it`);
      assert.deepEqual(kept, ["a", "z", GRIN]);
      assert.equal(coverageFor(root, "members").status, "unclosed");
    } else {
      t.diagnostic(`emulator collates document IDs by UTF-8 bytes (pageSize ${pageSize})`);
      assertExhaustedChain(root, "members", byteSorted(members), pageSize);
    }
    assert.deepEqual(recordIds(root, "invites"), [ID_128]);
    assert.equal(coverageFor(root, "invites").status, "unclosed");
    assert.ok(root.unresolved.includes("unsupported-record-id:invites"));
    assert.ok(root.unresolved.includes("unclosed-scope:invites"));
    assertExhaustedChain(root, "channels", ["ch+plus", ID_128], pageSize);
    assert.ok(root.unresolved.includes("unsupported-channel-id"));
    assert.equal(manifest.summary.mapping.records.channels, 1);
    assert.equal(JSON.stringify(manifest.mappingReport).includes("ch+plus"), false);
    assert.equal(mappingByPath(manifest, "clubs/order_club").disposition, "planned");
  }
});

emulatorTest("roots deleted, edited or recreated between scope listings are reported from the verification read", async () => {
  const ns = namespace("drift");
  const roots = ["drift_delete", "drift_edit", "drift_recreate", "drift_control"];
  await seedDocs(ns.db, roots.flatMap((id) => [[`clubs/${id}`, clubData()], [`clubs/${id}/members/${OWNER}`, { role: "owner" }],
    [`clubs/${id}/channels/ch_main`, { type: "chat", isPrivate: false }]]));
  const before = await census(ns.db);
  const hooked = mutateBeforeScope(ns.db, "invites", {
    "clubs/drift_delete": () => ns.db.doc("clubs/drift_delete").delete(),
    "clubs/drift_edit": () => ns.db.doc("clubs/drift_edit").update({ privacy: "private", updatedAt: Timestamp.now() }),
    "clubs/drift_recreate": async () => {
      await ns.db.doc("clubs/drift_recreate").delete();
      await ns.db.doc("clubs/drift_recreate").set(clubData({ privacy: "inviteOnly" }));
    },
  });
  const manifest = await ns.collector(hooked).collect({ pageSize: 1 });
  assert.equal(manifest.summary.roots.total, 4);
  const deleted = rootByPath(manifest, "clubs/drift_delete");
  assert.deepEqual(deleted.unresolved, ["root-missing-at-verification"]);
  assert.equal(deleted.inventoryInput, null);
  assert.equal(deleted.inventoryReport, null);
  assert.equal(mappingByPath(manifest, "clubs/drift_delete"), undefined);
  for (const [id, privacy] of [["drift_edit", "private"], ["drift_recreate", "inviteOnly"]]) {
    const root = rootByPath(manifest, `clubs/${id}`);
    assert.deepEqual(root.unresolved, ["source-version-changed"], id);
    assert.equal(root.inventoryReport.sourceVersionMatches, false);
    assert.ok(root.inventoryReport.claimedCollectionCoverage.every((item) => item.status === "unresolved-source-change"));
    const { expectedUpdateTime } = root.inventoryInput.source;
    const observed = root.inventoryInput.observedRoot.updateTime;
    assert.ok(observed.seconds > expectedUpdateTime.seconds ||
      (observed.seconds === expectedUpdateTime.seconds && observed.nanoseconds > expectedUpdateTime.nanoseconds), id);
    assert.deepEqual(root.inventoryInput.readTime, root.inventoryInput.observedRoot.readTime);
    assert.deepEqual(inspectLegacyMigrationInventory(root.inventoryInput), root.inventoryReport);
    // The mapping is computed from the verified (post-edit) root, not from stale discovery data.
    const mapping = mappingByPath(manifest, `clubs/${id}`);
    assert.equal(mapping.privacy, privacy, id);
    assert.deepEqual(mapping.sourceVersion.updateTime, observed, id);
    assert.notDeepEqual(mapping.sourceVersion.updateTime, expectedUpdateTime, id);
    assert.deepEqual(recordIds(root, "members"), [OWNER]);
    assert.deepEqual(recordIds(root, "channels"), ["ch_main"]);
  }
  const control = rootByPath(manifest, "clubs/drift_control");
  assert.equal(control.inventoryReport.evidenceStatus, "structurally-consistent-claims");
  assert.deepEqual(manifest.summary.roots, { clubs: 4, rooms: 0, total: 4, discoveryTruncated: false, inventoried: 3,
    structurallyConsistent: 1, unresolved: 3, includedInMapping: 3 });
  assert.deepEqual(manifest.summary.unresolvedReasons, { "root-missing-at-verification": 1, "source-version-changed": 2 });
  // Only the three test-owned mutations changed the database.
  const afterRun = await census(ns.db);
  const changed = [...new Set([...before.keys(), ...afterRun.keys()])].filter((key) => before.get(key) !== afterRun.get(key)).sort();
  assert.deepEqual(changed, ["clubs/drift_delete", "clubs/drift_edit", "clubs/drift_recreate"]);
  // The deleted root survives only as a phantom parent of its orphaned subcollection.
  assert.equal(afterRun.get("clubs/drift_delete"), "missing");
  assert.equal(afterRun.has(`clubs/drift_delete/members/${OWNER}`), true);
});

emulatorTest("forbidden content keys at root, channel, message and member level never reach the manifest", async () => {
  const ns = namespace("content");
  const secret = (level, key) => `${SECRET_MARK}-${level}-${key}`;
  const forbidden = (level) => Object.fromEntries(CONTENT_KEYS.map((key) => [key, key === "attachments"
    ? [{ url: secret(level, "attachment-url"), token: secret(level, "attachment-token") }] : secret(level, key)]));
  await seedDocs(ns.db, [
    ["clubs/content_club", clubData({ ...forbidden("club"), memberCount: 2, category: secret("club", "category"),
      defaultChatChannelId: { url: secret("club", "nested-default-channel") }, loungeRoomId: "content_room" })],
    [`clubs/content_club/members/${OWNER}`, { ...forbidden("member"), userId: OWNER, role: "owner", displayName: secret("member", "displayName") }],
    ["clubs/content_club/invites/inv_1", { ...forbidden("invite"), createdBy: OWNER }],
    ["clubs/content_club/channels/ch_chat", { ...forbidden("channel"), type: "chat", isPrivate: false, position: 0,
      roomId: { token: secret("channel", "nested-room-id") } }],
    ["clubs/content_club/channels/ch_voice", { ...forbidden("channel-voice"), type: "voice", isPrivate: false, roomId: "content_room" }],
    ["clubs/content_club/channels/ch_voice/messages/nested_1", { ...forbidden("nested-channel-message"), senderId: OWNER }],
    ["rooms/content_room", roomData({ ...forbidden("room"), hostId: OWNER, clubId: "content_club", channelId: "ch_voice",
      hostName: secret("room", "hostName"), voiceSessionId: { token: secret("room", "nested-voice-session") } })],
    [`rooms/content_room/roomMembers/${OWNER}`, { ...forbidden("roomMember"), userId: OWNER, role: "host" }],
    [`rooms/content_room/participants/${OWNER}`, { ...forbidden("participant"), isSpeaker: true }],
    ["rooms/content_room/messages/msg_1", { ...forbidden("message"), senderId: OWNER, senderName: secret("message", "senderName") }],
    ["rooms/standalone_room", roomData({ ...forbidden("standalone"), imageUrl: secret("standalone", "imageUrl") })],
  ]);
  const manifest = await ns.collector().collect();
  const text = serializeManifest(manifest);
  assert.equal(text.includes(SECRET_MARK), false, "a seeded secret value reached the manifest");
  const keys = new Set();
  const badPaths = [];
  walk(manifest, {
    key: (key, trail) => {
      if (trail.join(".") === "summary.unresolvedReasons" || trail.join(".") === "summary.records.byScope") return;
      keys.add(key);
      if (!KNOWN_KEYS.has(key)) badPaths.push([...trail, key].join("."));
    },
    object: (value) => assert.equal(Object.getPrototypeOf(value), Object.prototype, "manifest objects must be plain"),
  });
  assert.deepEqual(badPaths, [], "keys outside the manifest key universe");
  assert.deepEqual(NEVER_KEYS.filter((key) => keys.has(key)), []);
  assert.deepEqual(Object.keys(manifest.summary.records.byScope), ["members", "invites", "channels", "roomMembers", "participants", "messages"]);
  for (const reason of Object.keys(manifest.summary.unresolvedReasons)) assert.match(reason, /^[A-Za-z:-]+$/u);
  assert.deepEqual(manifest.collector.rootFields, { club: [...ROOT_FIELDS.club], room: [...ROOT_FIELDS.room] });
  assert.deepEqual(manifest.collector.channelFields, [...CHANNEL_FIELDS]);
  assert.deepEqual(manifest.collector.scopeListingFields, []);
  // Malformed allowlisted values are reported as reasons, never echoed.
  const club = mappingByPath(manifest, "clubs/content_club");
  assert.ok(club.reasons.includes("unresolved-default-channel"));
  assert.ok(manifest.mappingReport.bindingIssues.some((issue) => issue.sourcePath === "clubs/content_club/channels/ch_chat" &&
    issue.reason === "malformed-room-reference"));
  assert.ok(mappingByPath(manifest, "rooms/content_room").reasons.includes("unresolved-session-state"));
  assert.equal(mappingByPath(manifest, "rooms/standalone_room").disposition, "planned");
  assert.equal(rootByPath(manifest, "clubs/content_club").inventoryReport.evidenceStatus, "structurally-consistent-claims");
  assert.deepEqual(manifest.summary.records.byScope, { members: 1, invites: 1, channels: 2, roomMembers: 1, participants: 1, messages: 1 });
  assert.deepEqual(JSON.parse(text), manifest, "serialization must be lossless (no undefined, getters or toJSON drift)");
});

emulatorTest("minimum budgets keep every scope present and mark only truncated scopes unclosed", async () => {
  const ns = namespace("budget");
  await seedDocs(ns.db, [
    ["clubs/bud_members_big", clubData()], ...range("m", 10).map((id) => [`clubs/bud_members_big/members/${id}`, { role: "member" }]),
    ["clubs/bud_channels_big", clubData()], ...range("ch", 5).map((id) => [`clubs/bud_channels_big/channels/${id}`, { type: "chat", isPrivate: false }]),
    ["clubs/bud_mixed", clubData()], ...range("m", 2).map((id) => [`clubs/bud_mixed/members/${id}`, { role: "member" }]),
    ["clubs/bud_mixed/invites/i001", { status: "pending" }], ["clubs/bud_mixed/channels/ch001", { type: "chat", isPrivate: false }],
    ["rooms/bud_room", roomData()], [`rooms/bud_room/roomMembers/${HOST}`, { role: "host" }], [`rooms/bud_room/participants/${HOST}`, { isSpeaker: true }],
    ...range("msg", 50).map((id) => [`rooms/bud_room/messages/${id}`, { position: 0 }]),
  ]);
  const everyScopePresent = (manifest) => {
    for (const root of manifest.roots) {
      assert.notEqual(root.inventoryReport, null, root.path);
      for (const scope of REQUIRED_SCOPES[root.kind]) {
        const item = coverageFor(root, scope);
        assert.notEqual(item.status, "missing", `${root.path}/${scope}`);
        assert.ok(item.pageCount >= 1, `${root.path}/${scope}`);
        assert.equal(pagesFor(root, scope).at(-1).exhausted, item.status === "claimed-exhausted", `${root.path}/${scope}`);
      }
      assert.ok(root.inventoryInput.pages.length <= manifest.collector.maxPagesPerRoot);
      assert.ok(root.inventoryInput.pages.reduce((sum, page) => sum + page.records.length, 0) <= manifest.collector.maxRecordsPerRoot);
    }
  };
  const minimum = await ns.collector().collect({ maxPagesPerRoot: 3, maxRecordsPerRoot: 3, pageSize: 1 });
  everyScopePresent(minimum);
  assert.deepEqual(rootByPath(minimum, "clubs/bud_members_big").unresolved, ["record-budget-exhausted:members", "unclosed-scope:members"]);
  assert.deepEqual(recordIds(rootByPath(minimum, "clubs/bud_members_big"), "members"), ["m001"]);
  assert.deepEqual(rootByPath(minimum, "clubs/bud_channels_big").unresolved,
    ["mapping-channels-incomplete", "page-budget-exhausted:channels", "unclosed-scope:channels"]);
  assert.deepEqual(rootByPath(minimum, "clubs/bud_mixed").unresolved, ["record-budget-exhausted:members", "unclosed-scope:members"]);
  assert.deepEqual(recordIds(rootByPath(minimum, "clubs/bud_mixed"), "invites"), ["i001"]);
  assert.deepEqual(recordIds(rootByPath(minimum, "clubs/bud_mixed"), "channels"), ["ch001"]);
  assert.deepEqual(rootByPath(minimum, "rooms/bud_room").unresolved, ["record-budget-exhausted:messages", "unclosed-scope:messages"]);
  assert.deepEqual(recordIds(rootByPath(minimum, "rooms/bud_room"), "roomMembers"), [HOST]);
  // members = 1 (bud_members_big, asserted ["m001"] above) + 1 (bud_mixed,
  // record-budget-exhausted with one record per required scope) + 0
  // (bud_channels_big has no members): 2, not 3. Corrected on re-verification;
  // the per-root assertions above already implied it.
  assert.deepEqual(minimum.summary.records.byScope, { members: 2, invites: 1, channels: 2, roomMembers: 1, participants: 1, messages: 1 });

  const records3 = await ns.collector().collect({ maxRecordsPerRoot: 3 });
  everyScopePresent(records3);
  assert.deepEqual(recordIds(rootByPath(records3, "clubs/bud_channels_big"), "channels"), ["ch001", "ch002", "ch003"]);
  assert.deepEqual(rootByPath(records3, "clubs/bud_channels_big").unresolved,
    ["mapping-channels-incomplete", "record-budget-exhausted:channels", "unclosed-scope:channels"]);
  assert.equal(records3.mappingReport.mappings.length, 4);
  assert.equal(records3.summary.mapping.records.channels, 3 + 1);
  assert.deepEqual(recordIds(rootByPath(records3, "rooms/bud_room"), "messages"), ["msg001"]);

  const pages3 = await ns.collector().collect({ maxPagesPerRoot: 3, pageSize: 2 });
  everyScopePresent(pages3);
  assert.deepEqual(rootByPath(pages3, "clubs/bud_members_big").unresolved, ["page-budget-exhausted:members", "unclosed-scope:members"]);
  assert.deepEqual(recordIds(rootByPath(pages3, "clubs/bud_members_big"), "members"), ["m001", "m002"]);
  assert.deepEqual(rootByPath(pages3, "rooms/bud_room").unresolved, ["page-budget-exhausted:messages", "unclosed-scope:messages"]);
  assert.deepEqual(rootByPath(pages3, "clubs/bud_mixed").unresolved, []);

  for (const [maxRoots, clubs, rooms, truncated] of [[1, 1, 0, true], [2, 2, 0, true], [3, 3, 0, true], [4, 3, 1, false]]) {
    const manifest = await ns.collector().collect({ maxRoots, pageSize: 1 });
    assert.deepEqual([manifest.summary.roots.clubs, manifest.summary.roots.rooms, manifest.summary.roots.discoveryTruncated],
      [clubs, rooms, truncated], `maxRoots ${maxRoots}`);
    assert.equal(manifest.unresolved.some((item) => item.path === null && item.reason === "root-discovery-truncated"), truncated);
    assert.deepEqual(manifest.roots.map((root) => root.path),
      ["clubs/bud_channels_big", "clubs/bud_members_big", "clubs/bud_mixed", "rooms/bud_room"].slice(0, clubs + rooms));
  }
});

emulatorTest("touches only clubs, rooms and the six scopes with the declared projections, and writes nothing", async () => {
  const ns = namespace("reads");
  await seedDocs(ns.db, [
    ["clubs/read_club", clubData({ name: SECRET_MARK, defaultChatChannelId: "ch_1" })], [`clubs/read_club/members/${OWNER}`, { role: "owner" }],
    ["clubs/read_club/invites/i1", { token: SECRET_MARK }], ["clubs/read_club/channels/ch_1", { type: "chat", isPrivate: false, name: SECRET_MARK }],
    ["clubs/read_club/channels/ch_1/messages/m1", { text: SECRET_MARK }], ["clubs/read_club/bans/b1", { reason: SECRET_MARK }],
    ["rooms/read_room", roomData({ name: SECRET_MARK })], [`rooms/read_room/roomMembers/${HOST}`, { role: "host" }],
    [`rooms/read_room/participants/${HOST}`, { isSpeaker: true }], ["rooms/read_room/messages/m1", { text: SECRET_MARK }],
    ["rooms/read_room/reactions/x", { emoji: "x" }],
    ["users/u1", { displayName: SECRET_MARK }], ["users/u1/devices/d1", { token: SECRET_MARK }],
    ["reels/r1", { url: SECRET_MARK }], ["reels/r1/comments/c1", { text: SECRET_MARK }],
    ["servers/s1", { serverSchemaVersion: 1, name: SECRET_MARK }],
  ]);
  const before = await census(ns.db);
  assert.ok(before.has("users/u1") && before.has("reels/r1/comments/c1") && before.has("servers/s1"));
  const log = [];
  const manifest = await ns.collector(recordingFirestore(ns.db, log)).collect({ pageSize: 1 });
  assert.deepEqual(await census(ns.db), before);
  assert.equal(manifest.writeCount, 0);
  assert.equal(serializeManifest(manifest).includes(SECRET_MARK), false);
  const calls = (kind, method) => log.filter((entry) => entry.kind === kind && entry.method === method);
  assert.deepEqual(calls("Firestore", "collection").map((entry) => entry.args), [["clubs"], ["rooms"]]);
  assert.deepEqual(calls("Firestore", "doc").map((entry) => entry.args), [["clubs/read_club"], ["rooms/read_room"]]);
  const scopeCalls = calls("DocumentReference", "collection").map((entry) => entry.args[0]).sort();
  assert.deepEqual(scopeCalls, ["channels", "invites", "members", "messages", "participants", "roomMembers"]);
  const selects = log.filter((entry) => entry.method === "select");
  assert.ok(selects.length >= 8);
  for (const entry of selects) {
    assert.deepEqual(entry.args, entry.origin === "channels" ? [...CHANNEL_FIELDS] : [], `select from ${entry.origin}`);
  }
  assert.ok(selects.some((entry) => entry.origin === "channels"));
  for (const entry of log.filter((item) => item.method === "limit")) assert.ok(entry.args[0] >= 1 && entry.args[0] <= 2);
  const getAll = calls("Firestore", "getAll");
  assert.deepEqual(getAll.map((entry) => entry.args[0]), ["clubs/read_club", "rooms/read_room"]);
  assert.deepEqual(getAll.map((entry) => entry.args[1]), [{ fieldMask: [...ROOT_FIELDS.club] }, { fieldMask: [...ROOT_FIELDS.room] }]);
  for (const entry of getAll) assert.equal(entry.args.length, 2);
  const surface = [...new Set(log.map((entry) => `${entry.kind}.${entry.method}`))].sort();
  const allowedSurface = ["CollectionReference.orderBy", "DocumentReference.collection", "DocumentSnapshot.data", "Firestore.collection",
    "Firestore.doc", "Firestore.getAll", "Query.get", "Query.limit", "Query.orderBy", "Query.select", "Query.startAfter",
    "QueryDocumentSnapshot.data"];
  assert.deepEqual(surface.filter((name) => !allowedSurface.includes(name)), []);
  assert.equal(manifest.summary.roots.structurallyConsistent, 2);
  assert.deepEqual(manifest.summary.records.byScope, { members: 1, invites: 1, channels: 1, roomMembers: 1, participants: 1, messages: 1 });
});

// The happy path must print no diagnostic OF ITS OWN. That is not the same as
// an empty stderr: on a runner with no GCE metadata server (GitHub Actions),
// the Google auth library inside the spawned CLI emits
// "(node:PID) MetadataLookupWarning: ..." plus Node's "--trace-warnings" hint,
// and this was the only empty-stderr assertion in the whole suite. Strip the
// runtime's own warning lines and keep asserting that the collector is silent.
function withoutNodeRuntimeWarnings(stderr) {
  return String(stderr)
    .split(/\r?\n/u)
    .filter((line) => !/^\(node:\d+\) /u.test(line) && !/^\(Use `node --trace-warnings/u.test(line))
    .join("\n")
    .trim();
}

emulatorTest("CLI process refuses mismatched allow-project, non-local hosts, duplicate, unknown and out-of-range flags", async () => {
  const ns = namespace("cli");
  await seedDocs(ns.db, [["clubs/cli_club_7c3e", clubData({ name: SECRET_MARK })], [`clubs/cli_club_7c3e/members/${OWNER}`, { role: "owner" }],
    ["rooms/cli_room_7c3e", roomData({ name: SECRET_MARK })], ["rooms/cli_room_7c3e/messages/cli_msg_7c3e", { text: SECRET_MARK }]]);
  const base = { PATH: process.env.PATH, HOME: process.env.HOME, NODE_ENV: "test", GCLOUD_PROJECT: ns.projectId, FIRESTORE_EMULATOR_HOST: emulatorHost };
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-collector-qa-"));
  const outFor = (label) => path.join(scratch, label);
  const refused = (label, args, env, pattern) => {
    const result = runCli(args, env);
    assert.equal(result.status, 2, `${label}: ${result.stderr}`);
    assert.match(result.stderr, pattern, label);
    assert.equal(result.stdout, "", label);
    assert.equal(fs.existsSync(outFor(label)), false, `${label} must not create its out dir`);
  };
  refused("mismatch", ["--out", outFor("mismatch"), "--allow-project", `${ns.projectId}x`], base, /does not exactly match/u);
  refused("mismatch-case", ["--out", outFor("mismatch-case"), "--allow-project", ns.projectId.toUpperCase()], base, /not a project id|does not exactly match/u);
  refused("mismatch-prod", ["--out", outFor("mismatch-prod"), "--allow-project", "yovoice-ec54a"], base, /does not exactly match/u);
  for (const [index, host] of ["firestore.googleapis.com:443", "10.0.0.5:8080", "127.0.0.1", "localhost", "[::1]", "0.0.0.0:8090",
    "127.0.0.1.attacker.example:8090", " 127.0.0.1:8090", "127.0.0.1:8090 ", "http://127.0.0.1:8090", "127.0.0.1:8090/x",
    "localhost:8090;evil", "LOCALHOST:8090", "127.0.0.1:123456", "127.0.0.1:"].entries()) {
    refused(`host-${index}`, ["--out", outFor(`host-${index}`)], { ...base, FIRESTORE_EMULATOR_HOST: host }, /must name a local emulator/u);
    refused(`host-allow-${index}`, ["--out", outFor(`host-allow-${index}`), "--allow-project", ns.projectId],
      { ...base, FIRESTORE_EMULATOR_HOST: host }, /must name a local emulator/u);
  }
  refused("dup-out", ["--out", outFor("dup-out"), "--out", outFor("dup-out")], base, /Duplicate argument: --out/u);
  refused("dup-page", ["--out", outFor("dup-page"), "--page-size", "5", "--page-size", "5"], base, /Duplicate argument: --page-size/u);
  refused("unknown", ["--out", outFor("unknown"), "--dry-run", "true"], base, /Unknown argument: "--dry-run"/u);
  refused("unknown-apply", ["--apply", "--out", outFor("unknown-apply")], base, /Unknown argument: "--apply"/u);
  refused("page-0", ["--out", outFor("page-0"), "--page-size", "0"], base, /--page-size must be an integer between 1 and 500/u);
  refused("page-501", ["--out", outFor("page-501"), "--page-size", "501"], base, /--page-size must be an integer between 1 and 500/u);
  refused("page-neg", ["--out", outFor("page-neg"), "--page-size", "-1"], base, /requires a value|--page-size must be/u);
  refused("page-hex", ["--out", outFor("page-hex"), "--page-size", "0x10"], base, /--page-size must be/u);
  refused("roots-0", ["--out", outFor("roots-0"), "--max-roots", "0"], base, /--max-roots must be an integer between 1 and 10000/u);
  refused("roots-10001", ["--out", outFor("roots-10001"), "--max-roots", "10001"], base, /--max-roots must be/u);
  refused("missing-value", ["--out"], base, /--out requires a value/u);
  refused("flag-as-value", ["--out", "--page-size", "5"], base, /--out requires a value/u);
  refused("no-project", ["--out", outFor("no-project")], { ...base, GCLOUD_PROJECT: "" }, /no project id/u);
  refused("bad-config", ["--out", outFor("bad-config")], { ...base, GCLOUD_PROJECT: "", FIREBASE_CONFIG: "{" }, /no project id/u);
  refused("prod-no-emulator", ["--out", outFor("prod-no-emulator")], { PATH: base.PATH, HOME: base.HOME, GCLOUD_PROJECT: "yovoice-ec54a" }, /FIRESTORE_EMULATOR_HOST/u);
  // Existing digest or manifest alone already blocks a run and stays byte-identical.
  for (const existing of ["manifest.json", "manifest.sha256"]) {
    const dir = outFor(`existing-${existing}`);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, existing), "keep-me\n");
    const result = runCli(["--out", dir], base);
    assert.equal(result.status, 2, result.stderr);
    assert.match(result.stderr, /already holds a manifest/u);
    assert.deepEqual(fs.readdirSync(dir), [existing]);
    assert.equal(fs.readFileSync(path.join(dir, existing), "utf8"), "keep-me\n");
  }
  // A runtime failure (out dir under a regular file) exits 1 and writes nothing.
  fs.writeFileSync(outFor("a-file"), "x");
  const runtime = runCli(["--out", path.join(outFor("a-file"), "run")], base);
  assert.equal(runtime.status, 1, runtime.stderr);
  assert.match(runtime.stderr, /servers migration dry-run failed/u);
  assert.equal(runtime.stdout, "");
  // Happy path with the exact allow-project on a local emulator, boundary page size and max roots.
  const outDir = outFor("ok");
  const ok = runCli(["--out", outDir, "--allow-project", ns.projectId, "--page-size", "500", "--max-roots", "10000"], base);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(withoutNodeRuntimeWarnings(ok.stderr), "", ok.stderr);
  const text = fs.readFileSync(path.join(outDir, "manifest.json"), "utf8");
  const manifest = JSON.parse(text);
  assert.equal(serializeManifest(manifest), text, "manifest file must be the canonical serialization");
  assert.deepEqual([manifest.projectId, manifest.emulator, manifest.collector.pageSize, manifest.collector.maxRoots], [ns.projectId, true, 500, 10000]);
  assert.equal(manifest.summary.roots.total, 2);
  assert.equal(fs.readFileSync(path.join(outDir, "manifest.sha256"), "utf8"), `${manifestDigest(text)}  manifest.json\n`);
  const shasum = spawnSync("shasum", ["-a", "256", "-c", "manifest.sha256"], { cwd: outDir, encoding: "utf8" });
  assert.equal(shasum.status, 0, shasum.stderr);
  for (const leak of ["cli_club_7c3e", "cli_room_7c3e", "cli_msg_7c3e", OWNER, SECRET_MARK]) assert.equal(ok.stdout.includes(leak), false, leak);
  assert.ok(ok.stdout.includes("roots: clubs=1 rooms=1 total=2 discoveryTruncated=false"), ok.stdout);
  assert.ok(ok.stdout.includes("writeCount: 0"), ok.stdout);
  const minimal = runCli(["--out", outFor("ok-min"), "--page-size", "1", "--max-roots", "1"], base);
  assert.equal(minimal.status, 0, minimal.stderr);
  assert.ok(minimal.stdout.includes("roots: clubs=1 rooms=0 total=1 discoveryTruncated=true"), minimal.stdout);
  assert.ok(minimal.stdout.includes("root-discovery-truncated=1"), minimal.stdout);
  fs.rmSync(scratch, { recursive: true, force: true });
});

emulatorTest("two collects differ only in read times and generatedAt, and tampering breaks the bound chain", async () => {
  const ns = namespace("determinism");
  await seedDocs(ns.db, [
    ["clubs/det_club", clubData({ defaultVoiceChannelId: "ch_voice", loungeRoomId: "det_bound" })],
    ...range("m", 3).map((id) => [`clubs/det_club/members/${id}`, { role: "member" }]),
    ["clubs/det_club/channels/ch_voice", { type: "voice", isPrivate: false, roomId: "det_bound" }],
    ["rooms/det_bound", roomData({ hostId: OWNER, clubId: "det_club", channelId: "ch_voice" })],
    ["rooms/det_solo", roomData({ isLive: true, participantCount: 2 })], ...range("msg", 3).map((id) => [`rooms/det_solo/messages/${id}`, { position: 0 }]),
    ["clubs/det_versioned", clubData({ serverSchemaVersion: 1, serverType: "friends" })],
  ]);
  const first = await ns.collector(ns.db, () => 1_800_000_000_000).collect({ pageSize: 2 });
  const second = await ns.collector(ns.db, () => 1_800_000_999_000).collect({ pageSize: 2 });
  assert.notEqual(first.generatedAt, second.generatedAt);
  assert.deepEqual(scrubVolatile(first), scrubVolatile(second));
  assert.equal(manifestDigest(serializeManifest(scrubVolatile(first))), manifestDigest(serializeManifest(scrubVolatile(second))));
  assert.equal(first.mappingReport.reportDigest, second.mappingReport.reportDigest);
  assert.deepEqual(first.roots.map((root) => root.path), ["clubs/det_club", "clubs/det_versioned", "rooms/det_bound", "rooms/det_solo"]);
  assert.deepEqual(JSON.parse(serializeManifest(first)), first);
  for (const root of first.roots) {
    assert.ok(root.readTimeSpan.earliest && root.readTimeSpan.latest);
    assert.deepEqual(root.inventoryInput.readTime, root.readTimeSpan.latest);
    assert.deepEqual(inspectLegacyMigrationInventory(root.inventoryInput), root.inventoryReport);
  }
  assert.equal(mappingByPath(first, "rooms/det_solo").disposition, "deferred");
  assert.equal(mappingByPath(first, "clubs/det_versioned").disposition, "already-versioned");
  assert.equal(mappingByPath(first, "rooms/det_bound").bindingAction, "retain-reciprocal-link");
  const digest = manifestDigest(serializeManifest(first));
  const tamperedOrder = JSON.parse(JSON.stringify(first));
  const page = rootByPath(tamperedOrder, "clubs/det_club").inventoryInput.pages.find((item) => item.scope === "members");
  page.records[0].id = "zzz";
  assert.notEqual(manifestDigest(serializeManifest(tamperedOrder)), digest);
  assert.throws(() => inspectLegacyMigrationInventory(rootByPath(tamperedOrder, "clubs/det_club").inventoryInput), TypeError);
  const tamperedQuiet = JSON.parse(JSON.stringify(first));
  const quietRoot = rootByPath(tamperedQuiet, "clubs/det_club");
  quietRoot.inventoryInput.pages.find((item) => item.scope === "members").records[0].id = "a-earlier";
  assert.notEqual(manifestDigest(serializeManifest(tamperedQuiet)), digest);
  assert.notEqual(inspectLegacyMigrationInventory(quietRoot.inventoryInput).reportDigest, quietRoot.inventoryReport.reportDigest);
  const tamperedFlag = JSON.parse(JSON.stringify(first));
  const lastPage = rootByPath(tamperedFlag, "rooms/det_solo").inventoryInput.pages.filter((item) => item.scope === "messages").at(-1);
  lastPage.exhausted = false;
  assert.throws(() => inspectLegacyMigrationInventory(rootByPath(tamperedFlag, "rooms/det_solo").inventoryInput), TypeError);
  const tamperedTime = JSON.parse(JSON.stringify(first));
  rootByPath(tamperedTime, "clubs/det_club").inventoryInput.pages[0].records[0].updateTime.seconds += 10 ** 6;
  assert.throws(() => inspectLegacyMigrationInventory(rootByPath(tamperedTime, "clubs/det_club").inventoryInput), TypeError);
});

emulatorTest("prototype-named root, channel and record IDs neither pollute prototypes nor break the mapping", async (t) => {
  const ns = namespace("proto");
  const protoKeys = Object.getOwnPropertyNames(Object.prototype).sort();
  // `__defineGetter__` matches Firestore's reserved `__.*__` document-id
  // pattern, so it belongs with `__proto__` in the guarded probe below rather
  // than in the batch seed, where INVALID_ARGUMENT failed the whole test
  // before the collector ever ran.
  const members = ["toString", "valueOf", "__proto", "constructor", "hasOwnProperty"];
  await seedDocs(ns.db, [
    ["clubs/constructor", clubData()], ...members.map((id) => [`clubs/constructor/members/${id}`, { role: "member" }]),
    ["clubs/constructor/channels/constructor", { type: "voice", isPrivate: false, roomId: "hasOwnProperty" }],
    ["rooms/hasOwnProperty", roomData({ hostId: OWNER, clubId: "constructor", channelId: "constructor" })],
    ["clubs/toString", clubData()],
  ]);
  let reserved = "rejected";
  try {
    await ns.db.doc("clubs/toString/members/__proto__").set({ role: "member" });
    await ns.db.doc("clubs/toString/members/__defineGetter__").set({ role: "member" });
    reserved = "stored";
  } catch { /* expected: Firestore reserves `__.*__` document ids */ }
  t.diagnostic(`emulator ${reserved} the reserved record IDs __proto__ / __defineGetter__`);
  const manifest = await ns.collector().collect({ pageSize: 2 });
  assert.deepEqual(Object.getOwnPropertyNames(Object.prototype).sort(), protoKeys);
  assert.equal(Object.hasOwn({}, "polluted"), false);
  assert.equal(Object.prototype.toString.call({}), "[object Object]");
  const club = rootByPath(manifest, "clubs/constructor");
  assert.equal(club.inventoryReport.evidenceStatus, "structurally-consistent-claims");
  assert.deepEqual(recordIds(club, "members"), byteSorted(members));
  assert.deepEqual(recordIds(club, "channels"), ["constructor"]);
  const room = mappingByPath(manifest, "rooms/hasOwnProperty");
  assert.deepEqual([room.disposition, room.serverId, room.channelId, room.bindingAction], ["planned", "constructor", "constructor", "retain-reciprocal-link"]);
  assert.equal(mappingByPath(manifest, "clubs/constructor").disposition, "planned");
  const other = rootByPath(manifest, "clubs/toString");
  if (reserved === "stored") {
    assert.deepEqual(other.unresolved, ["missing-scope:members", "unsupported-record-id:members"]);
    assert.equal(other.inventoryInput.pages.filter((page) => page.scope === "members").length, 0);
  } else {
    assert.deepEqual(other.unresolved, []);
  }
  assert.deepEqual(JSON.parse(serializeManifest(manifest)), manifest);
  assert.deepEqual(Object.keys(manifest.summary.unresolvedReasons).filter((key) => key in Object.prototype), []);
  assert.deepEqual(manifest.summary.roots, { clubs: 2, rooms: 1, total: 3, discoveryTruncated: false, inventoried: 3,
    structurallyConsistent: reserved === "stored" ? 2 : 3, unresolved: reserved === "stored" ? 1 : 0, includedInMapping: 3 });
});
