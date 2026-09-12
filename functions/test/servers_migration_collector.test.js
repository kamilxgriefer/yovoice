"use strict";

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { after, before, test } = require("node:test");

// No default cloud endpoint or ambient credential access. Fixtures only exist
// in an explicitly selected localhost demo emulator project namespace.
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const projectId = `demo-yovoice-collector-${randomUUID().slice(0, 8)}`;
let app;
let db;
let Timestamp;
let firestoreModule;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  firestoreModule = require("firebase-admin/firestore");
  Timestamp = firestoreModule.Timestamp;
  app = adminApp.initializeApp({ projectId }, `collector-${randomUUID()}`);
  db = firestoreModule.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { templateChannels } = require("../servers/templates");
const { REQUIRED_SCOPES } = require("../servers/migration_inventory");
const { standaloneServerId } = require("../servers/migration_plan");
const {
  CHANNEL_FIELDS, DEFAULT_OPTIONS, DIGEST_PURPOSE, MAX_TOTAL_RECORDS, MIN_TOTAL_RECORDS, ROOT_FIELDS,
  createLegacyMigrationCollector, manifestDigest, serializeManifest,
} = require("../servers/migration_collector");
const cli = require("../scripts/servers_migration_dry_run");

const SCRIPT = path.resolve(__dirname, "../scripts/servers_migration_dry_run.js");
const SECRET = Object.freeze({
  name: "SECRET-NAME-8f2c", description: "SECRET-DESCRIPTION-8f2c", text: "SECRET-MESSAGE-BODY-8f2c",
  url: "https://cdn.example.invalid/SECRET-MEDIA-8f2c.png?token=SECRET-URL-TOKEN-8f2c",
  token: "SECRET-INVITE-TOKEN-8f2c", displayName: "SECRET-DISPLAY-8f2c",
});
const FORBIDDEN_KEYS = ["text", "name", "description", "photoUrl", "imageUrl", "avatarUrl", "hostPhotoUrl",
  "token", "displayName", "hostName", "senderName", "url", "attachments", "ownerName"];
const OWNER_A = "owner-a-uid-8f2c";
const MEMBER_B = "member-b-uid-8f2c";
const MEMBER_C = "member-c-uid-8f2c";
const HOST_S = "host-s-uid-8f2c";
const FAMILY_OWNER = "family-owner-uid-8f2c";
const V1_OWNER = "v1-owner-uid-8f2c";
const CLUB_A = "legacy_club_a";
const FAMILY_CLUB = `family_${FAMILY_OWNER}`;
const CLUB_IDS = "legacy_club_ids";
const BAD_ROOT = "bad.root";
const ROOM_S = "legacy_room_s";
const ROOM_B = "bound_room_b";
const LONG_ID = "x".repeat(129);
const DOT_CHANNEL = "ch.dot";
const MESSAGE_IDS = ["msg_0001", "msg_0002", "msg_0003"];
const V1_CHANNEL_COUNT = templateChannels("friends", "English", 1).length;
const byteCompare = (a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
let v1 = null;
let v1Rooms = [];
let K = 0;
const isolatedApps = [];

const emulatorTest = (name, fn) => test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const rejects = (fn, code) => assert.throws(fn, (error) => error.code === code);
const rejectsAsync = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const isTimestamp = (value) => Number.isSafeInteger(value.seconds) && Number.isInteger(value.nanoseconds) &&
  Object.keys(value).length === 2;
const coverage = (root) => Object.fromEntries(root.inventoryReport.claimedCollectionCoverage
  .map(({ scope, ...rest }) => [scope, rest]));
const rootByPath = (manifest, rootPath) => manifest.roots.find((root) => root.path === rootPath);
const mappingByPath = (manifest, rootPath) => manifest.mappingReport.mappings.find((item) => item.sourcePath === rootPath);
const collector = (firestore = db) => createLegacyMigrationCollector({ firestore, projectId, emulator: true,
  clock: () => 1_800_000_000_000 });

// A test-owned project namespace with its own fixture, for the cases whose
// arithmetic must not depend on how many roots the shared fixture holds.
function isolatedNamespace(label) {
  const isolatedProject = `demo-yovoice-collector-${label}-${randomUUID().slice(0, 8)}`;
  const isolatedApp = require("firebase-admin/app").initializeApp({ projectId: isolatedProject },
    `collector-${label}-${randomUUID()}`);
  isolatedApps.push(isolatedApp);
  const isolatedDb = firestoreModule.getFirestore(isolatedApp);
  return {
    projectId: isolatedProject, db: isolatedDb,
    seed: async (docs) => {
      const batch = isolatedDb.batch();
      for (const [docPath, data] of docs) batch.set(isolatedDb.doc(docPath), data);
      await batch.commit();
    },
    collector: (firestore = isolatedDb) => createLegacyMigrationCollector({ firestore,
      projectId: isolatedProject, emulator: true, clock: () => 1_800_000_000_000 }),
  };
}

// Returns a Firestore facade whose `name` root listing hands back each page in
// reverse byte order, i.e. a backend that does not collate IDs the way the
// cursor arithmetic assumes. Reads stay real; only the order is hostile.
function reversedRootOrder(target, name) {
  const reverseQuery = (query) => new Proxy(query, {
    get(source, property) {
      const member = Reflect.get(source, property, source);
      if (property === "get") {
        return async (...args) => {
          const snapshot = await member.apply(source, args);
          return { readTime: snapshot.readTime, docs: [...snapshot.docs].reverse() };
        };
      }
      return typeof member === "function" ? (...args) => reverseQuery(member.apply(source, args)) : member;
    },
  });
  return new Proxy(target, {
    get(source, property) {
      if (property !== "collection") {
        const member = Reflect.get(source, property, source);
        return typeof member === "function" ? member.bind(source) : member;
      }
      return (collectionName) => {
        const reference = source.collection(collectionName);
        return collectionName === name ? reverseQuery(reference) : reference;
      };
    },
  });
}

function walkKeys(value, seen = new Set()) {
  if (Array.isArray(value)) value.forEach((item) => walkKeys(item, seen));
  else if (value !== null && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) { seen.add(key); walkKeys(item, seen); }
  }
  return seen;
}

async function seed() {
  const now = Timestamp.fromMillis(1_700_000_000_000);
  const batch = db.batch();
  const set = (docPath, data) => batch.set(db.doc(docPath), data);
  set(`clubs/${CLUB_A}`, { name: SECRET.name, description: SECRET.description, photoUrl: SECRET.url,
    avatarUrl: SECRET.url, ownerId: OWNER_A, ownerName: SECRET.displayName, type: "community", privacy: "public",
    status: "active", memberCount: 3, defaultChatChannelId: "ch_general", defaultVoiceChannelId: "ch_voice",
    loungeRoomId: ROOM_B, createdAt: now, updatedAt: now });
  for (const [uid, role] of [[OWNER_A, "owner"], [MEMBER_B, "member"], [MEMBER_C, "member"]]) {
    set(`clubs/${CLUB_A}/members/${uid}`, { userId: uid, displayName: SECRET.displayName, photoUrl: SECRET.url, role, joinedAt: now });
  }
  set(`clubs/${CLUB_A}/invites/inv_0001`, { token: SECRET.token, createdBy: OWNER_A, status: "pending" });
  set(`clubs/${CLUB_A}/invites/inv_0002`, { token: SECRET.token, createdBy: OWNER_A, status: "revoked" });
  set(`clubs/${CLUB_A}/channels/ch_general`, { name: SECRET.name, type: "chat", isPrivate: false, position: 0, roomId: null });
  set(`clubs/${CLUB_A}/channels/ch_voice`, { name: SECRET.name, type: "voice", isPrivate: false, position: 1, roomId: ROOM_B });
  set(`clubs/${FAMILY_CLUB}`, { name: SECRET.name, avatarUrl: SECRET.url, ownerId: FAMILY_OWNER, type: "family",
    privacy: "inviteOnly", status: "active", memberCount: 1 });
  set(`clubs/${FAMILY_CLUB}/members/${FAMILY_OWNER}`, { userId: FAMILY_OWNER, displayName: SECRET.displayName, role: "owner" });
  set(`clubs/${FAMILY_CLUB}/channels/ch_family`, { name: SECRET.name, type: "chat", isPrivate: false, position: 0 });
  set(`rooms/${ROOM_S}`, { name: SECRET.name, description: SECRET.description, imageUrl: SECRET.url, hostId: HOST_S,
    hostName: SECRET.displayName, hostPhotoUrl: SECRET.url, experience: "community", visibility: "public",
    isLive: false, participantCount: 0, status: "active", category: "music", createdAt: now });
  set(`rooms/${ROOM_S}/roomMembers/${HOST_S}`, { userId: HOST_S, displayName: SECRET.displayName, role: "host" });
  set(`rooms/${ROOM_S}/roomMembers/${MEMBER_B}`, { userId: MEMBER_B, displayName: SECRET.displayName, role: "member" });
  set(`rooms/${ROOM_S}/participants/${HOST_S}`, { userId: HOST_S, displayName: SECRET.displayName, isSpeaker: true });
  MESSAGE_IDS.forEach((id, index) => set(`rooms/${ROOM_S}/messages/${id}`, { text: SECRET.text, senderId: HOST_S,
    senderName: SECRET.displayName, attachments: [{ url: SECRET.url, token: SECRET.token }], createdAt: now, position: index }));
  set(`rooms/${ROOM_B}`, { name: SECRET.name, clubId: CLUB_A, channelId: "ch_voice", hostId: OWNER_A,
    hostName: SECRET.displayName, experience: "community", visibility: "public", isLive: false, participantCount: 0, status: "active" });
  set(`rooms/${ROOM_B}/roomMembers/${OWNER_A}`, { userId: OWNER_A, displayName: SECRET.displayName, role: "host" });
  set(`rooms/${ROOM_B}/messages/msg_bound_0001`, { text: SECRET.text, senderId: OWNER_A });
  set(`clubs/${CLUB_IDS}`, { name: SECRET.name, ownerId: OWNER_A, type: "community", privacy: "private", status: "active" });
  set(`clubs/${CLUB_IDS}/members/aaa`, { userId: "aaa", displayName: SECRET.displayName });
  set(`clubs/${CLUB_IDS}/members/${LONG_ID}`, { userId: LONG_ID, displayName: SECRET.displayName });
  set(`clubs/${CLUB_IDS}/channels/${DOT_CHANNEL}`, { name: SECRET.name, type: "chat", isPrivate: false });
  set(`clubs/${BAD_ROOT}`, { name: SECRET.name, ownerId: OWNER_A, type: "community", privacy: "public", status: "active" });
  set(`clubs/${BAD_ROOT}/members/${OWNER_A}`, { userId: OWNER_A, displayName: SECRET.displayName });
  await batch.commit();
  // The V1 held server is written by the real creation service, not by hand.
  await db.doc(`users/${V1_OWNER}`).set({ displayName: SECRET.displayName, status: "active" });
  const service = createServerCreationService({ db, Timestamp, clock: () => 1_900_000_000_000 });
  return service.createServerV1({ auth: { uid: V1_OWNER, token: { email_verified: true } }, data: {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1, name: SECRET.name,
    description: SECRET.description, privacy: "inviteOnly", defaultLanguage: "English",
  } });
}

async function census() {
  const out = new Map();
  const visit = async (reference) => {
    for (const collection of await reference.listCollections()) {
      for (const document of await collection.listDocuments()) {
        const snapshot = await document.get();
        out.set(document.path, snapshot.exists ? `${snapshot.updateTime.seconds}.${snapshot.updateTime.nanoseconds}` : "missing");
        await visit(document);
      }
    }
  };
  for (const name of ["clubs", "rooms", "users"]) {
    for (const document of await db.collection(name).listDocuments()) {
      const snapshot = await document.get();
      out.set(document.path, snapshot.exists ? `${snapshot.updateTime.seconds}.${snapshot.updateTime.nanoseconds}` : "missing");
      await visit(document);
    }
  }
  return out;
}

const WRITE_METHODS = new Set(["set", "update", "delete", "create", "add", "commit", "batch", "bulkWriter",
  "runTransaction", "recursiveDelete"]);
function denyWrites(value) {
  if (value === null || typeof value !== "object") return value;
  if (typeof value.then === "function") return value.then(denyWrites);
  return new Proxy(value, {
    get(target, property) {
      if (typeof property === "string" && WRITE_METHODS.has(property)) throw new Error(`write attempted: ${property}`);
      const member = Reflect.get(target, property, target);
      if (typeof member === "function") return (...args) => denyWrites(member.apply(target, args));
      return denyWrites(member);
    },
  });
}

async function withGuardedPrototypes(fn) {
  const { BulkWriter, CollectionReference, DocumentReference, Firestore, Transaction, WriteBatch } = firestoreModule;
  const targets = [
    [DocumentReference.prototype, ["set", "update", "delete", "create"]],
    [CollectionReference.prototype, ["add"]],
    [Firestore.prototype, ["batch", "bulkWriter", "runTransaction", "recursiveDelete"]],
    [WriteBatch.prototype, ["commit"]],
    [Transaction.prototype, ["set", "update", "delete", "create"]],
    [BulkWriter.prototype, ["set", "update", "delete", "create"]],
  ];
  const originals = [];
  for (const [prototype, names] of targets) {
    for (const name of names) {
      const descriptor = Object.getOwnPropertyDescriptor(prototype, name);
      assert.ok(descriptor, `SDK method ${name} must exist for the guard to be real`);
      originals.push([prototype, name, descriptor]);
      Object.defineProperty(prototype, name, { configurable: true, writable: true, value() {
        throw new Error(`write attempted: ${name}`);
      } });
    }
  }
  try {
    return await fn();
  } finally {
    for (const [prototype, name, descriptor] of originals) Object.defineProperty(prototype, name, descriptor);
  }
}

function runCli(args, env) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { env, encoding: "utf8", timeout: 120_000 });
}

before(async () => {
  if (!enabled) return;
  v1 = await seed();
  const channels = await db.collection(`clubs/${v1.serverId}/channels`).get();
  v1Rooms = channels.docs.map((doc) => doc.get("roomId")).filter((roomId) => typeof roomId === "string").sort(byteCompare);
  K = v1Rooms.length;
  assert.ok(K >= 1);
});
after(async () => {
  const { deleteApp } = require("firebase-admin/app");
  for (const isolatedApp of isolatedApps) await deleteApp(isolatedApp);
  if (app) await deleteApp(app);
});

test("collector rejects malformed dependencies and options before reading anything", async () => {
  const stub = { collection() { throw new Error("must not read"); }, doc() {}, getAll() {} };
  rejects(() => createLegacyMigrationCollector(null), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore: {}, projectId: "demo-x", emulator: true }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore: stub, projectId: "Demo_X", emulator: true }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore: stub, projectId: "demo-x", emulator: "yes" }), "invalid-argument");
  rejects(() => createLegacyMigrationCollector({ firestore: stub, projectId: "demo-x", emulator: true, extra: 1 }), "invalid-argument");
  const instance = createLegacyMigrationCollector({ firestore: stub, projectId: "demo-x", emulator: true });
  for (const options of [{ pageSize: 0 }, { pageSize: 501 }, { pageSize: "2" }, { maxPagesPerRoot: 2 },
    { maxPagesPerRoot: 1001 }, { maxRecordsPerRoot: 10001 }, { maxRoots: 0 }, { maxRoots: 10001 }, { unknown: 1 }, null, [],
    { maxTotalRecords: MIN_TOTAL_RECORDS - 1 }, { maxTotalRecords: MAX_TOTAL_RECORDS + 1 }, { maxTotalRecords: 0 },
    { maxTotalRecords: 5.5 }, { maxTotalRecords: "1000" }, { maxTotalRecords: null }]) {
    await rejectsAsync(instance.collect(options), "invalid-argument");
  }
  // The run-wide record budget defaults far below the ~2.4M records at which a
  // pretty-printed manifest reaches V8's maximum string length.
  assert.deepEqual(DEFAULT_OPTIONS, { pageSize: 500, maxPagesPerRoot: 1000, maxRecordsPerRoot: 10000,
    maxRoots: 1000, maxTotalRecords: 1000000 });
  assert.equal(MAX_TOTAL_RECORDS, 1000000);
  assert.equal(MIN_TOTAL_RECORDS, 3);
  assert.match(DIGEST_PURPOSE, /^unkeyed-sha256-integrity-checksum-of-the-manifest-bytes-not-an-authorization/u);
  assert.deepEqual(ROOT_FIELDS.club, ["serverSchemaVersion", "serverType", "serverActivationState", "status",
    "deletionInProgress", "ownerId", "type", "privacy", "defaultChatChannelId", "defaultVoiceChannelId",
    "announcementChannelId", "loungeRoomId"]);
  assert.deepEqual(ROOT_FIELDS.room, ["serverSchemaVersion", "serverId", "status", "deletionInProgress", "hostId",
    "experience", "visibility", "isLive", "participantCount", "voiceSessionId", "clubId", "channelId"]);
  assert.deepEqual(CHANNEL_FIELDS, ["serverSchemaVersion", "type", "isPrivate", "roomId"]);
  for (const fields of [ROOT_FIELDS.club, ROOT_FIELDS.room, CHANNEL_FIELDS]) {
    assert.equal(fields.some((field) => FORBIDDEN_KEYS.includes(field)), false);
  }
});

test("CLI parses arguments strictly", () => {
  const parsed = cli.parseArguments(["--out", "/tmp/x", "--page-size", "25", "--max-roots", "7",
    "--max-total-records", "900", "--allow-project", "demo-yovoice"]);
  assert.deepEqual(parsed, { ok: true, value: { out: "/tmp/x", pageSize: 25, maxRoots: 7, maxTotalRecords: 900,
    allowProject: "demo-yovoice" } });
  assert.deepEqual(cli.parseArguments(["--out", "dir"]).value, { out: "dir", pageSize: 500, maxRoots: 1000,
    maxTotalRecords: 1000000, allowProject: null });
  for (const argv of [[], ["--page-size", "2"], ["--out"], ["--out", "--page-size"], ["--out", "dir", "--page-size", "0"],
    ["--out", "dir", "--page-size", "501"], ["--out", "dir", "--page-size", "2.5"], ["--out", "dir", "--max-roots", "10001"],
    ["--out", "dir", "--max-roots", "-1"], ["--out", "dir", "--apply"], ["--out", "dir", "--out", "other"],
    ["--out", "dir", "--allow-project", "Yovoice"], ["--out", "dir", "extra"], "not-an-array",
    ["--out", "dir", "--max-total-records", "2"], ["--out", "dir", "--max-total-records", "1000001"],
    ["--out", "dir", "--max-total-records", "1e6"], ["--out", "dir", "--max-total-records", "--out"],
    ["--out", "dir", "--max-total-records", "5", "--max-total-records", "5"]]) {
    const result = cli.parseArguments(argv);
    assert.equal(result.ok, false, JSON.stringify(argv));
    assert.match(result.message, /Usage: node functions\/scripts\/servers_migration_dry_run\.js/u);
  }
});

test("CLI access decision refuses without a local emulator or an exact allow-project match", () => {
  const refused = (env, allowProject) => {
    const decision = cli.accessDecision({ env, allowProject });
    assert.equal(decision.allowed, false);
    assert.match(decision.message, /^Refusing:/u);
    return decision.message;
  };
  refused({}, null);
  refused({ GCLOUD_PROJECT: "yovoice-ec54a" }, null);
  refused({ FIREBASE_CONFIG: '{"projectId":"yovoice-ec54a"}' }, null);
  refused({ GCLOUD_PROJECT: "yovoice-ec54a" }, "yovoice-ec54b");
  refused({ GCLOUD_PROJECT: "yovoice-ec54a", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" }, "other-project");
  refused({ GCLOUD_PROJECT: "demo-yovoice", FIRESTORE_EMULATOR_HOST: "firestore.example.com:8080" }, null);
  refused({ GCLOUD_PROJECT: "demo-yovoice", FIRESTORE_EMULATOR_HOST: "10.0.0.5:8080" }, null);
  refused({ FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" }, null);
  refused({ GCLOUD_PROJECT: "Bad Project", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" }, null);
  refused({ FIREBASE_CONFIG: "{not json", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" }, null);
  assert.deepEqual(cli.accessDecision({ env: { GCLOUD_PROJECT: "demo-yovoice", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" }, allowProject: null }),
    { allowed: true, projectId: "demo-yovoice", emulator: true });
  assert.deepEqual(cli.accessDecision({ env: { FIREBASE_CONFIG: '{"projectId":"demo-yovoice"}', FIRESTORE_EMULATOR_HOST: "localhost:8080" }, allowProject: "demo-yovoice" }),
    { allowed: true, projectId: "demo-yovoice", emulator: true });
  assert.deepEqual(cli.accessDecision({ env: { GOOGLE_CLOUD_PROJECT: "yovoice-ec54a" }, allowProject: "yovoice-ec54a" }),
    { allowed: true, projectId: "yovoice-ec54a", emulator: false });
});

test("CLI process refuses with exit 2 before any Firestore client exists", () => {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-collector-refusal-"));
  const bare = { PATH: process.env.PATH };
  const noEmulator = runCli(["--out", outDir], { ...bare, GCLOUD_PROJECT: "yovoice-ec54a" });
  assert.equal(noEmulator.status, 2, noEmulator.stderr);
  assert.match(noEmulator.stderr, /FIRESTORE_EMULATOR_HOST/u);
  const mismatch = runCli(["--out", outDir, "--allow-project", "yovoice-ec54b"], { ...bare, GCLOUD_PROJECT: "yovoice-ec54a" });
  assert.equal(mismatch.status, 2, mismatch.stderr);
  assert.match(mismatch.stderr, /does not exactly match/u);
  const noProject = runCli(["--out", outDir], { ...bare, FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" });
  assert.equal(noProject.status, 2, noProject.stderr);
  const malformed = runCli(["--page-size", "2"], { ...bare, GCLOUD_PROJECT: "demo-yovoice", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" });
  assert.equal(malformed.status, 2, malformed.stderr);
  assert.match(malformed.stderr, /--out <dir> is required/u);
  for (const result of [noEmulator, mismatch, noProject, malformed]) assert.equal(result.stdout, "");
  assert.deepEqual(fs.readdirSync(outDir), []);
});

emulatorTest("collects validator-accepted inventories for every legacy root and a held mapping report", async () => {
  const manifest = await collector().collect();
  const v1Lounge = `club_lounge_${v1.serverId}`;
  assert.ok(v1Rooms.includes(v1Lounge));
  assert.deepEqual(manifest.roots.map((root) => root.path), [
    ...[BAD_ROOT, FAMILY_CLUB, CLUB_A, CLUB_IDS, v1.serverId].sort(byteCompare).map((id) => `clubs/${id}`),
    ...[ROOM_B, ROOM_S, ...v1Rooms].sort(byteCompare).map((id) => `rooms/${id}`),
  ]);
  assert.equal(manifest.manifestVersion, 1);
  assert.equal(manifest.dryRun, true);
  assert.equal(manifest.projectId, projectId);
  assert.equal(manifest.emulator, true);
  assert.equal(manifest.generatedAt, "2027-01-15T08:00:00.000Z");
  assert.equal(manifest.applyReady, false);
  assert.equal(manifest.writeCount, 0);
  assert.equal(manifest.fullInventoryComplete, false);
  assert.equal(manifest.collector.consistentSnapshot, false);
  assert.deepEqual(manifest.collector.scopeListingFields, []);
  assert.equal(manifest.collector.maxTotalRecords, 1000000);
  // The digest is an integrity checksum of the bytes, and the manifest says so
  // rather than leaving an operator to read it as an approval.
  assert.equal(manifest.digestPurpose, DIGEST_PURPOSE);
  assert.ok(manifest.digestPurpose.includes("not-an-authorization"));

  const expected = {
    [`clubs/${CLUB_A}`]: { members: 3, invites: 2, channels: 2 },
    [`clubs/${FAMILY_CLUB}`]: { members: 1, invites: 0, channels: 1 },
    [`clubs/${v1.serverId}`]: { members: 1, invites: 0, channels: V1_CHANNEL_COUNT },
    [`rooms/${ROOM_S}`]: { roomMembers: 2, participants: 1, messages: 3 },
    [`rooms/${ROOM_B}`]: { roomMembers: 1, participants: 0, messages: 1 },
    ...Object.fromEntries(v1Rooms.map((id) => [`rooms/${id}`, { roomMembers: 0, participants: 0, messages: 0 }])),
  };
  for (const [rootPath, counts] of Object.entries(expected)) {
    const root = rootByPath(manifest, rootPath);
    assert.equal(root.inventoryReport.evidenceStatus, "structurally-consistent-claims", rootPath);
    assert.deepEqual(root.unresolved, [], rootPath);
    assert.equal(root.inventoryReport.sourceVersionMatches, true);
    assert.equal(root.inventoryReport.applyReady, false);
    assert.equal(root.inventoryReport.writeCount, 0);
    assert.deepEqual(coverage(root), Object.fromEntries(Object.entries(counts).map(([scope, recordCount]) =>
      [scope, { status: "claimed-exhausted", pageCount: 1, recordCount }])), rootPath);
    assert.deepEqual(root.inventoryInput.pages.map((page) => page.scope), REQUIRED_SCOPES[root.kind]);
    for (const page of root.inventoryInput.pages) {
      assert.equal(page.parentPath, rootPath);
      assert.deepEqual(page.readTime, root.inventoryInput.readTime);
      assert.equal(page.exhausted, true);
      assert.equal(page.nextCursor, null);
      assert.equal(page.startAfter, null);
      for (const record of page.records) {
        assert.deepEqual(Object.keys(record), ["id", "updateTime"]);
        assert.ok(isTimestamp(record.updateTime));
      }
    }
    assert.ok(isTimestamp(root.inventoryInput.readTime));
    assert.deepEqual(root.readTimeSpan.latest, root.inventoryInput.readTime);
    assert.deepEqual(root.inventoryInput.source.expectedUpdateTime, root.inventoryInput.observedRoot.updateTime);
    assert.equal(root.consistentSnapshot, false);
  }
  const clubA = rootByPath(manifest, `clubs/${CLUB_A}`);
  assert.deepEqual(clubA.inventoryInput.pages[0].records.map((record) => record.id), [MEMBER_B, MEMBER_C, OWNER_A]);
  assert.deepEqual(clubA.inventoryInput.pages[2].records.map((record) => record.id), ["ch_general", "ch_voice"]);

  const bad = rootByPath(manifest, `clubs/${BAD_ROOT}`);
  assert.equal(bad.inventoryInput, null);
  assert.equal(bad.inventoryReport, null);
  assert.deepEqual(bad.unresolved, ["unsupported-root-id"]);
  const ids = rootByPath(manifest, `clubs/${CLUB_IDS}`);
  assert.equal(ids.inventoryReport.evidenceStatus, "unresolved");
  assert.deepEqual(ids.unresolved, ["unclosed-scope:members", "unsupported-channel-id", "unsupported-record-id:members"]);
  assert.deepEqual(coverage(ids), {
    members: { status: "unclosed", pageCount: 1, recordCount: 1 },
    invites: { status: "claimed-exhausted", pageCount: 1, recordCount: 0 },
    channels: { status: "claimed-exhausted", pageCount: 1, recordCount: 1 },
  });
  assert.deepEqual(ids.inventoryInput.pages[0].records.map((record) => record.id), ["aaa"]);
  assert.equal(ids.inventoryInput.pages[0].nextCursor, "aaa");
  assert.equal(JSON.stringify(manifest).includes(LONG_ID), false);

  const mapping = manifest.mappingReport;
  assert.equal(mapping.applyReady, false);
  assert.equal(mapping.writeCount, 0);
  assert.equal(mapping.dryRun, true);
  assert.deepEqual(mapping.bindingIssues, []);
  const expectedDispositions = {
    [`clubs/${FAMILY_CLUB}`]: "planned", [`clubs/${CLUB_A}`]: "planned", [`clubs/${CLUB_IDS}`]: "planned",
    [`clubs/${v1.serverId}`]: "already-versioned", [`rooms/${ROOM_B}`]: "planned", [`rooms/${ROOM_S}`]: "planned",
    ...Object.fromEntries(v1Rooms.map((id) => [`rooms/${id}`, "already-versioned"])),
  };
  assert.deepEqual(mapping.mappings.map((item) => [item.sourcePath, item.disposition]),
    Object.entries(expectedDispositions).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  const clubMapping = mappingByPath(manifest, `clubs/${CLUB_A}`);
  assert.equal(clubMapping.serverId, CLUB_A);
  assert.equal(clubMapping.serverType, "community");
  assert.equal(clubMapping.privacy, "public");
  assert.equal(clubMapping.ownerId, OWNER_A);
  assert.equal(mappingByPath(manifest, `clubs/${FAMILY_CLUB}`).serverType, "family");
  const standalone = mappingByPath(manifest, `rooms/${ROOM_S}`);
  assert.equal(standalone.serverId, standaloneServerId(ROOM_S));
  assert.equal(standalone.channelId, "legacy_voice");
  assert.equal(standalone.serverType, "community");
  assert.equal(standalone.ownerId, HOST_S);
  const bound = mappingByPath(manifest, `rooms/${ROOM_B}`);
  assert.equal(bound.serverId, CLUB_A);
  assert.equal(bound.channelId, "ch_voice");
  assert.equal(bound.bindingAction, "retain-reciprocal-link");
  assert.deepEqual(manifest.unresolved, [
    { path: `clubs/${BAD_ROOT}`, reason: "unsupported-root-id" },
    { path: `clubs/${CLUB_IDS}`, reason: "unclosed-scope:members" },
    { path: `clubs/${CLUB_IDS}`, reason: "unsupported-channel-id" },
    { path: `clubs/${CLUB_IDS}`, reason: "unsupported-record-id:members" },
  ]);
  assert.deepEqual(manifest.summary.roots, { clubs: 5, rooms: 2 + K, total: 7 + K, discoveryTruncated: false,
    inventoried: 6 + K, structurallyConsistent: 5 + K, unresolved: 2, includedInMapping: 6 + K });
  assert.deepEqual(manifest.summary.records, { total: 20 + V1_CHANNEL_COUNT, byScope: {
    members: 6, invites: 2, channels: 4 + V1_CHANNEL_COUNT, roomMembers: 3, participants: 1, messages: 4 } });
  assert.equal(manifest.summary.pages, (6 + K) * 3);
  assert.deepEqual(manifest.summary.mapping, { computed: true,
    records: { clubs: 4, rooms: 2 + K, channels: 3 + V1_CHANNEL_COUNT, ownerOverrides: 0 },
    dispositions: { planned: 5, blocked: 0, deferred: 0, alreadyVersioned: 1 + K }, bindingIssues: 0 });
  assert.deepEqual(manifest.summary.unresolvedReasons, { "unclosed-scope:members": 1, "unsupported-channel-id": 1,
    "unsupported-record-id:members": 1, "unsupported-root-id": 1 });
  assert.ok(isTimestamp(manifest.summary.readTimeSpan.earliest) && isTimestamp(manifest.summary.readTimeSpan.latest));
});

emulatorTest("never reads or emits content, media or bearer fields", async () => {
  const manifest = await collector().collect();
  const text = serializeManifest(manifest);
  for (const value of Object.values(SECRET)) assert.equal(text.includes(value), false, value);
  for (const fragment of ["SECRET", "https://", "token=", "cdn.example.invalid"]) assert.equal(text.includes(fragment), false, fragment);
  const keys = walkKeys(manifest);
  for (const key of FORBIDDEN_KEYS) assert.equal(keys.has(key), false, key);
  assert.ok(keys.has("id") && keys.has("updateTime") && keys.has("readTime"));
  const summaryText = JSON.stringify(manifest.summary) + JSON.stringify(manifest.unresolved) + JSON.stringify(manifest.mappingReport);
  for (const recordId of [MEMBER_B, MEMBER_C, "inv_0001", ...MESSAGE_IDS, "msg_bound_0001"]) {
    assert.equal(summaryText.includes(recordId), false, recordId);
  }
});

emulatorTest("page size 2 chains cursors across pages and the validator accepts the chain", async () => {
  const manifest = await collector().collect({ pageSize: 2 });
  const clubA = rootByPath(manifest, `clubs/${CLUB_A}`);
  assert.equal(clubA.inventoryReport.evidenceStatus, "structurally-consistent-claims");
  assert.deepEqual(coverage(clubA), {
    members: { status: "claimed-exhausted", pageCount: 2, recordCount: 3 },
    invites: { status: "claimed-exhausted", pageCount: 1, recordCount: 2 },
    channels: { status: "claimed-exhausted", pageCount: 1, recordCount: 2 },
  });
  const members = clubA.inventoryInput.pages.filter((page) => page.scope === "members");
  assert.deepEqual(members.map((page) => [page.pageIndex, page.startAfter, page.nextCursor, page.exhausted,
    page.records.map((record) => record.id)]), [
    [0, null, MEMBER_C, false, [MEMBER_B, MEMBER_C]],
    [1, MEMBER_C, null, true, [OWNER_A]],
  ]);
  const roomS = rootByPath(manifest, `rooms/${ROOM_S}`);
  assert.equal(roomS.inventoryReport.evidenceStatus, "structurally-consistent-claims");
  const messages = roomS.inventoryInput.pages.filter((page) => page.scope === "messages");
  assert.deepEqual(messages.map((page) => [page.pageIndex, page.startAfter, page.nextCursor, page.exhausted,
    page.records.map((record) => record.id)]), [
    [0, null, MESSAGE_IDS[1], false, [MESSAGE_IDS[0], MESSAGE_IDS[1]]],
    [1, MESSAGE_IDS[1], null, true, [MESSAGE_IDS[2]]],
  ]);
  assert.equal(manifest.summary.pages, (6 + K) * 3 + 1 + Math.ceil(V1_CHANNEL_COUNT / 2));
  assert.equal(manifest.summary.records.total, 20 + V1_CHANNEL_COUNT);
  assert.deepEqual(manifest.mappingReport.mappings.map((item) => item.disposition).sort(),
    [...Array(1 + K).fill("already-versioned"), ...Array(5).fill("planned")]);
});

emulatorTest("page and record budgets truncate into reported unclosed scopes, never omitted ones", async () => {
  const byPages = await collector().collect({ pageSize: 1, maxPagesPerRoot: 3 });
  const roomS = rootByPath(byPages, `rooms/${ROOM_S}`);
  assert.equal(roomS.inventoryReport.evidenceStatus, "unresolved");
  assert.deepEqual(roomS.inventoryReport.unresolvedReasons, ["unclosed-scope:messages", "unclosed-scope:roomMembers"]);
  assert.deepEqual(roomS.unresolved, ["page-budget-exhausted:messages", "page-budget-exhausted:roomMembers",
    "unclosed-scope:messages", "unclosed-scope:roomMembers"]);
  assert.deepEqual(coverage(roomS), {
    roomMembers: { status: "unclosed", pageCount: 1, recordCount: 1 },
    participants: { status: "claimed-exhausted", pageCount: 1, recordCount: 1 },
    messages: { status: "unclosed", pageCount: 1, recordCount: 1 },
  });
  assert.equal(roomS.inventoryInput.pages.length, 3);
  assert.deepEqual(roomS.inventoryInput.pages.map((page) => [page.scope, page.nextCursor, page.exhausted]),
    [["roomMembers", HOST_S, false], ["participants", null, true], ["messages", MESSAGE_IDS[0], false]]);
  const clubAByPages = rootByPath(byPages, `clubs/${CLUB_A}`);
  assert.ok(clubAByPages.unresolved.includes("mapping-channels-incomplete"));
  assert.equal(byPages.mappingReport.applyReady, false);
  assert.ok(byPages.unresolved.some((item) => item.path === `rooms/${ROOM_S}` && item.reason === "page-budget-exhausted:messages"));

  const byRecords = await collector().collect({ pageSize: 2, maxRecordsPerRoot: 4 });
  const clubA = rootByPath(byRecords, `clubs/${CLUB_A}`);
  assert.equal(clubA.inventoryReport.evidenceStatus, "unresolved");
  assert.deepEqual(coverage(clubA), {
    members: { status: "unclosed", pageCount: 1, recordCount: 2 },
    invites: { status: "unclosed", pageCount: 1, recordCount: 1 },
    channels: { status: "unclosed", pageCount: 1, recordCount: 1 },
  });
  assert.deepEqual(clubA.unresolved, ["mapping-channels-incomplete", "record-budget-exhausted:channels",
    "record-budget-exhausted:invites", "record-budget-exhausted:members", "unclosed-scope:channels",
    "unclosed-scope:invites", "unclosed-scope:members"]);
  assert.equal(clubA.inventoryInput.pages.reduce((sum, page) => sum + page.records.length, 0), 4);
  const familyByRecords = rootByPath(byRecords, `clubs/${FAMILY_CLUB}`);
  assert.equal(familyByRecords.inventoryReport.evidenceStatus, "structurally-consistent-claims");
});

emulatorTest("performs zero writes: proxy, guarded SDK prototypes and an unchanged document census agree", async () => {
  const before = await census();
  assert.ok(before.size >= 30);
  const manifest = await withGuardedPrototypes(() => collector(denyWrites(db)).collect({ pageSize: 2 }));
  assert.equal(manifest.summary.roots.total, 7 + K);
  assert.equal(manifest.writeCount, 0);
  const after = await census();
  assert.deepEqual([...after.entries()], [...before.entries()]);
  await assert.rejects(withGuardedPrototypes(() => db.doc("clubs/must-not-exist").set({ ok: false })), /write attempted: set/u);
  assert.equal((await db.doc("clubs/must-not-exist").get()).exists, false);
});

emulatorTest("is deterministic apart from read times, and the manifest digest binds page metadata", async () => {
  const first = await collector().collect({ pageSize: 2 });
  const second = await collector().collect({ pageSize: 2 });
  const normalize = (value) => {
    if (Array.isArray(value)) return value.map(normalize);
    if (value !== null && typeof value === "object") {
      return Object.fromEntries(Object.entries(value)
        .filter(([key]) => !["readTime", "readTimeSpan", "reportDigest", "generatedAt"].includes(key))
        .map(([key, item]) => [key, normalize(item)]));
    }
    return value;
  };
  assert.deepEqual(normalize(first), normalize(second));
  assert.deepEqual(first.mappingReport, second.mappingReport);
  const firstText = serializeManifest(first);
  const digest = manifestDigest(firstText);
  assert.match(digest, /^[a-f0-9]{64}$/u);
  assert.equal(manifestDigest(serializeManifest(first)), digest);
  const tampered = JSON.parse(firstText);
  tampered.roots.find((root) => root.path === `clubs/${CLUB_A}`).inventoryInput.pages[0].records[0].id = "someone-else";
  assert.notEqual(manifestDigest(serializeManifest(tampered)), digest);
  const clubA = rootByPath(first, `clubs/${CLUB_A}`);
  const rebound = JSON.parse(JSON.stringify(clubA.inventoryInput));
  rebound.pages[0].records[0].id = "aaaa-" + rebound.pages[0].records[0].id;
  const { inspectLegacyMigrationInventory } = require("../servers/migration_inventory");
  assert.notEqual(inspectLegacyMigrationInventory(rebound).reportDigest, clubA.inventoryReport.reportDigest);
});

emulatorTest("CLI writes manifest and digest, prints counts only, and refuses to overwrite", () => {
  const outDir = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-collector-cli-")), "run");
  const env = { PATH: process.env.PATH, HOME: process.env.HOME, FIRESTORE_EMULATOR_HOST: emulatorHost,
    GCLOUD_PROJECT: projectId, NODE_ENV: "test" };
  const result = runCli(["--out", outDir, "--page-size", "2", "--max-roots", "50"], env);
  assert.equal(result.status, 0, result.stderr);
  const text = fs.readFileSync(path.join(outDir, "manifest.json"), "utf8");
  const manifest = JSON.parse(text);
  // Both output files list member and host UIDs: owner-only, in an owner-only
  // directory, from the moment the run creates them.
  assert.equal(fs.statSync(path.join(outDir, "manifest.json")).mode & 0o777, 0o600);
  assert.equal(fs.statSync(path.join(outDir, "manifest.sha256")).mode & 0o777, 0o600);
  assert.equal(fs.statSync(outDir).mode & 0o777, 0o700);
  assert.equal(cli.FILE_MODE, 0o600);
  assert.equal(cli.DIRECTORY_MODE, 0o700);
  assert.equal(manifest.digestPurpose, DIGEST_PURPOSE);
  assert.ok(result.stdout.includes(`digestPurpose: ${DIGEST_PURPOSE}`), result.stdout);
  assert.ok(result.stdout.includes("maxTotalRecords=1000000"), result.stdout);
  assert.equal(manifest.projectId, projectId);
  assert.equal(manifest.emulator, true);
  assert.equal(manifest.roots.length, 7 + K);
  assert.equal(manifest.collector.pageSize, 2);
  assert.equal(manifest.collector.maxRoots, 50);
  assert.equal(manifest.applyReady, false);
  assert.equal(fs.readFileSync(path.join(outDir, "manifest.sha256"), "utf8"), `${manifestDigest(text)}  manifest.json\n`);
  for (const line of [`roots: clubs=5 rooms=${2 + K} total=${7 + K} discoveryTruncated=false`, "fullInventoryComplete: false",
    "applyReady: false", "writeCount: 0", `mapping: computed=true planned=5 blocked=0 deferred=0 alreadyVersioned=${1 + K} bindingIssues=0`,
    `unresolved reasons: unclosed-scope:members=1, unsupported-channel-id=1, unsupported-record-id:members=1, unsupported-root-id=1`]) {
    assert.ok(result.stdout.includes(line), `${line}\n${result.stdout}`);
  }
  for (const secret of [MEMBER_B, OWNER_A, ...MESSAGE_IDS, "inv_0001", CLUB_A, BAD_ROOT, ...Object.values(SECRET)]) {
    assert.equal(result.stdout.includes(secret), false, secret);
  }
  const again = runCli(["--out", outDir], env);
  assert.equal(again.status, 2, again.stderr);
  assert.match(again.stderr, /already holds a manifest/u);
  assert.equal(JSON.parse(fs.readFileSync(path.join(outDir, "manifest.json"), "utf8")).generatedAt, manifest.generatedAt);
});

emulatorTest("reports a root that changes or vanishes during collection instead of trusting stale pages", async () => {
  const VANISH = "vanishing_root";
  await db.doc(`clubs/${VANISH}`).set({ name: SECRET.name, ownerId: OWNER_A, type: "community", privacy: "public", status: "active" });
  await db.doc(`clubs/${VANISH}/members/${OWNER_A}`).set({ userId: OWNER_A, displayName: SECRET.displayName });
  // Test-owned writes are injected between the collector's paging and its
  // root verification read; the collector itself still only reads.
  const hooked = new Proxy(db, {
    get(target, property) {
      if (property === "getAll") {
        return async (...args) => {
          const reference = args[0];
          if (reference.path === `clubs/${CLUB_A}`) await db.doc(reference.path).update({ updatedAt: Timestamp.now() });
          if (reference.path === `clubs/${VANISH}`) await db.doc(reference.path).delete();
          return target.getAll(...args);
        };
      }
      const member = Reflect.get(target, property, target);
      return typeof member === "function" ? member.bind(target) : member;
    },
  });
  const manifest = await collector(hooked).collect();
  assert.equal(manifest.summary.roots.clubs, 6);
  const changed = rootByPath(manifest, `clubs/${CLUB_A}`);
  assert.equal(changed.inventoryReport.evidenceStatus, "unresolved");
  assert.equal(changed.inventoryReport.sourceVersionMatches, false);
  assert.deepEqual(changed.inventoryReport.unresolvedReasons, ["source-version-changed"]);
  assert.deepEqual(changed.unresolved, ["source-version-changed"]);
  assert.notDeepEqual(changed.inventoryInput.source.expectedUpdateTime, changed.inventoryInput.observedRoot.updateTime);
  assert.deepEqual(Object.values(coverage(changed)).map((item) => item.status),
    ["unresolved-source-change", "unresolved-source-change", "unresolved-source-change"]);
  assert.equal(mappingByPath(manifest, `clubs/${CLUB_A}`).disposition, "planned");
  const vanished = rootByPath(manifest, `clubs/${VANISH}`);
  assert.equal(vanished.inventoryInput, null);
  assert.equal(vanished.inventoryReport, null);
  assert.deepEqual(vanished.unresolved, ["root-missing-at-verification"]);
  assert.equal(mappingByPath(manifest, `clubs/${VANISH}`), undefined);
  assert.equal(manifest.summary.roots.includedInMapping, 6 + K);
  assert.deepEqual(manifest.summary.unresolvedReasons, { "root-missing-at-verification": 1, "source-version-changed": 1,
    "unclosed-scope:members": 1, "unsupported-channel-id": 1, "unsupported-record-id:members": 1, "unsupported-root-id": 1 });
});

test("CLI failure output carries a closed-set reason and an error code, never an SDK or filesystem message", () => {
  const leaky = "clubs/legacy_club_a/members/member-b-uid-8f2c";
  assert.equal(cli.failureLine({ code: "invalid-argument", message: `bad option near ${leaky}` }),
    "servers migration dry-run failed: collector-rejected-the-run-options (code invalid-argument)");
  assert.equal(cli.failureLine({ code: "internal", message: leaky }),
    "servers migration dry-run failed: collector-internal-consistency-check-failed (code internal)");
  assert.equal(cli.failureLine({ code: "ENOTDIR", message: `ENOTDIR: not a directory, mkdir '${leaky}'` }),
    "servers migration dry-run failed: manifest-output-write-failed (code ENOTDIR)");
  assert.equal(cli.failureLine({ code: 5, message: `5 NOT_FOUND: no entity: ${leaky}` }),
    "servers migration dry-run failed: firestore-read-or-runtime-failure (code 5)");
  const unknown = "servers migration dry-run failed: firestore-read-or-runtime-failure (code none)";
  for (const error of [new Error(leaky), undefined, null, {}, { code: leaky }, { code: "code with spaces" },
    { code: "x".repeat(200) }, { code: -1 }, { code: 1e9 }, { code: 2.5 }, { code: { toString: () => leaky } }]) {
    assert.equal(cli.failureLine(error), unknown, JSON.stringify(error?.code ?? null));
  }
  for (const error of [{ code: "invalid-argument", message: leaky }, { code: "ENOENT", message: leaky }, new Error(leaky)]) {
    assert.equal(cli.failureLine(error).includes(leaky), false);
  }
});

test("CLI process reports a runtime failure without echoing the failing path or the SDK message", () => {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-collector-stderr-"));
  const blocker = path.join(scratch, "not-a-directory");
  fs.writeFileSync(blocker, "x");
  const result = runCli(["--out", path.join(blocker, "run")], { PATH: process.env.PATH, HOME: process.env.HOME,
    NODE_ENV: "test", GCLOUD_PROJECT: "demo-yovoice", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8090" });
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /^servers migration dry-run failed: manifest-output-write-failed \(code E[A-Z]+\)\n$/u);
  for (const leak of [blocker, scratch, "not a directory", "mkdir"]) {
    assert.equal(result.stderr.includes(leak), false, leak);
  }
  assert.equal(result.stdout, "");
  fs.rmSync(scratch, { recursive: true, force: true });
});

emulatorTest("a lowered run-wide record budget stops collection with a reported reason instead of throwing", async () => {
  const ns = isolatedNamespace("total");
  await ns.seed([
    ["clubs/b_one", { ownerId: OWNER_A, type: "community", privacy: "public", status: "active",
      defaultChatChannelId: "ch_one", name: SECRET.name }],
    ...[MEMBER_B, MEMBER_C, OWNER_A].map((uid) => [`clubs/b_one/members/${uid}`, { role: "member", displayName: SECRET.displayName }]),
    ["clubs/b_one/invites/inv_1", { token: SECRET.token }], ["clubs/b_one/invites/inv_2", { token: SECRET.token }],
    ["clubs/b_one/channels/ch_one", { type: "chat", isPrivate: false, name: SECRET.name }],
    ["clubs/b_one/channels/ch_two", { type: "voice", isPrivate: false, name: SECRET.name }],
    ["clubs/b_two", { ownerId: OWNER_A, type: "community", privacy: "public", status: "active" }],
    [`clubs/b_two/members/${OWNER_A}`, { role: "owner" }], ["clubs/b_two/invites/inv_3", { token: SECRET.token }],
    ["clubs/b_two/channels/ch_three", { type: "chat", isPrivate: false }],
    ["rooms/b_room", { hostId: HOST_S, experience: "community", visibility: "public", isLive: false,
      participantCount: 0, status: "active" }],
    [`rooms/b_room/roomMembers/${HOST_S}`, { role: "host" }], [`rooms/b_room/participants/${HOST_S}`, { isSpeaker: true }],
    ["rooms/b_room/messages/msg_1", { text: SECRET.text }],
  ]);
  const full = await ns.collector().collect();
  assert.equal(full.summary.records.total, 13);
  assert.deepEqual(full.unresolved, []);
  assert.equal(full.collector.maxTotalRecords, 1000000);

  // Five records is not enough to close clubs/b_one, and leaves nothing for the
  // roots behind it: both outcomes are reported, and nothing throws.
  const budgeted = await ns.collector().collect({ maxTotalRecords: 5 });
  assert.equal(budgeted.collector.maxTotalRecords, 5);
  assert.equal(budgeted.summary.records.total, 5);
  assert.deepEqual(budgeted.roots.map((root) => root.path), full.roots.map((root) => root.path));
  const one = rootByPath(budgeted, "clubs/b_one");
  assert.deepEqual(one.unresolved, ["mapping-channels-incomplete", "total-record-budget-exhausted:channels",
    "total-record-budget-exhausted:invites", "unclosed-scope:channels", "unclosed-scope:invites"]);
  assert.equal(one.inventoryReport.evidenceStatus, "unresolved");
  assert.deepEqual(coverage(one), {
    members: { status: "claimed-exhausted", pageCount: 1, recordCount: 3 },
    invites: { status: "unclosed", pageCount: 1, recordCount: 1 },
    channels: { status: "unclosed", pageCount: 1, recordCount: 1 },
  });
  for (const rootPath of ["clubs/b_two", "rooms/b_room"]) {
    const stopped = rootByPath(budgeted, rootPath);
    assert.deepEqual(stopped.unresolved, ["collection-stopped-total-record-budget"], rootPath);
    assert.equal(stopped.inventoryInput, null, rootPath);
    assert.equal(stopped.inventoryReport, null, rootPath);
    assert.deepEqual(stopped.readTimeSpan, { earliest: null, latest: null }, rootPath);
    assert.equal(mappingByPath(budgeted, rootPath), undefined, rootPath);
  }
  assert.deepEqual(budgeted.unresolved.filter((item) => item.path === null),
    [{ path: null, reason: "total-record-budget-exhausted" }]);
  assert.deepEqual(budgeted.summary.roots, { clubs: 2, rooms: 1, total: 3, discoveryTruncated: false, inventoried: 1,
    structurallyConsistent: 0, unresolved: 3, includedInMapping: 1 });
  assert.deepEqual(budgeted.summary.records.byScope, { members: 3, invites: 1, channels: 1,
    roomMembers: 0, participants: 0, messages: 0 });
  assert.equal(budgeted.summary.unresolvedReasons["collection-stopped-total-record-budget"], 2);
  assert.equal(budgeted.summary.unresolvedReasons["total-record-budget-exhausted"], 1);
  assert.equal(budgeted.applyReady, false);
  assert.equal(budgeted.writeCount, 0);
  // The manifest is still a complete, serializable, digestible document.
  assert.deepEqual(JSON.parse(serializeManifest(budgeted)), budgeted);
  assert.match(manifestDigest(serializeManifest(budgeted)), /^[a-f0-9]{64}$/u);
  assert.equal(serializeManifest(budgeted).includes(SECRET.name), false);
  // The per-root budget still reports itself; only the binding limit changes.
  const perRoot = await ns.collector().collect({ maxRecordsPerRoot: 3 });
  assert.ok(rootByPath(perRoot, "clubs/b_one").unresolved.includes("record-budget-exhausted:members"));
  assert.equal(perRoot.unresolved.some((item) => item.reason.startsWith("total-record-budget")), false);
});

emulatorTest("root discovery reports a backend that lists roots out of byte order and stops there", async () => {
  const ns = isolatedNamespace("order");
  await ns.seed([
    ["clubs/a_root", { ownerId: OWNER_A, type: "community", privacy: "public", status: "active" }],
    [`clubs/a_root/members/${OWNER_A}`, { role: "owner" }],
    ["clubs/b_root", { ownerId: OWNER_A, type: "community", privacy: "public", status: "active" }],
    [`clubs/b_root/members/${OWNER_A}`, { role: "owner" }],
    ["rooms/a_room", { hostId: HOST_S, experience: "community", visibility: "public", isLive: false,
      participantCount: 0, status: "active" }],
  ]);
  const honest = await ns.collector().collect();
  assert.deepEqual(honest.roots.map((root) => root.path), ["clubs/a_root", "clubs/b_root", "rooms/a_room"]);
  assert.deepEqual(honest.unresolved, []);

  const hostile = await ns.collector(reversedRootOrder(ns.db, "clubs")).collect();
  assert.deepEqual(hostile.roots.map((root) => root.path), ["clubs/b_root", "rooms/a_room"]);
  assert.deepEqual(hostile.unresolved.filter((item) => item.path === null).map((item) => item.reason),
    ["root-discovery-truncated", "root-discovery-truncated:clubs", "unsupported-root-order:clubs"]);
  assert.equal(hostile.summary.roots.discoveryTruncated, true);
  assert.equal(rootByPath(hostile, "clubs/b_root").inventoryReport.evidenceStatus, "structurally-consistent-claims");
  assert.equal(rootByPath(hostile, "rooms/a_room").inventoryReport.evidenceStatus, "structurally-consistent-claims");

  // maxRoots is one budget the collections consume in order, so a run that cuts
  // rooms off because clubs filled it says which collection was starved.
  const starved = await ns.collector().collect({ maxRoots: 2 });
  assert.deepEqual(starved.roots.map((root) => root.path), ["clubs/a_root", "clubs/b_root"]);
  assert.deepEqual(starved.unresolved.filter((item) => item.path === null).map((item) => item.reason),
    ["root-discovery-starved:rooms", "root-discovery-truncated", "root-discovery-truncated:rooms"]);
  assert.equal(starved.summary.roots.rooms, 0);
  assert.equal(starved.summary.roots.discoveryTruncated, true);
  const clubsCut = await ns.collector().collect({ maxRoots: 1 });
  assert.deepEqual(clubsCut.unresolved.filter((item) => item.path === null).map((item) => item.reason),
    ["root-discovery-starved:rooms", "root-discovery-truncated", "root-discovery-truncated:clubs",
      "root-discovery-truncated:rooms"]);
});
