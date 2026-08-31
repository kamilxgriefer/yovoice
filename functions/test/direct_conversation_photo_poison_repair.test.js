const assert = require("node:assert/strict");
const { mkdtemp, readFile, rm, stat } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { describe, test } = require("node:test");

const { canonicalPairKey } = require("../messaging/direct_integrity");
const {
  EXPECTED_PROJECT,
  assertArgs,
  canonicalRoot,
  parseArgs,
  poisonCandidate,
  repairCandidate,
  runRepair,
  serializable,
  writeFatalError,
  writePrivateBackup,
} = require("../scripts/repair_direct_conversation_photo_poison");

function clone(value) {
  if (value instanceof Date) return new Date(value.getTime());
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).map((key) => [key, clone(value[key])]),
    );
  }
  return value;
}

class FakeReference {
  constructor(database, documentPath) {
    this.database = database;
    this.path = documentPath;
    this.id = documentPath.split("/").at(-1);
  }
}

class FakeQuery {
  constructor(database, limit = Number.MAX_SAFE_INTEGER) {
    this.database = database;
    this.pageLimit = limit;
  }

  orderBy() {
    return this;
  }

  limit(value) {
    return new FakeQuery(this.database, value);
  }

  async get() {
    const docs = [...this.database.records.keys()]
      .filter((key) => key.startsWith("conversations/"))
      .sort()
      .slice(0, this.pageLimit)
      .map((key) => this.database.snapshot(this.database.doc(key)));
    return { docs, size: docs.length };
  }
}

class FakeDatabase {
  constructor() {
    this.records = new Map();
    this.mutations = 0;
    this.beforeTransaction = null;
    this.events = [];
  }

  set(documentPath, data, millis = 1_770_000_000_000) {
    this.records.set(documentPath, {
      data: clone(data),
      updateTime: new Date(millis),
    });
  }

  doc(documentPath) {
    return new FakeReference(this, documentPath);
  }

  collection(name) {
    assert.equal(name, "conversations");
    return new FakeQuery(this);
  }

  snapshot(reference) {
    const record = this.records.get(reference.path);
    return {
      id: reference.id,
      ref: reference,
      exists: record !== undefined,
      updateTime: record?.updateTime ?? null,
      data: () => clone(record?.data),
    };
  }

  async getAll(...references) {
    return references.map((reference) => this.snapshot(reference));
  }

  async runTransaction(callback) {
    if (this.beforeTransaction) {
      const hook = this.beforeTransaction;
      this.beforeTransaction = null;
      hook();
    }
    const updates = [];
    const transaction = {
      getAll: async (...references) => this.getAll(...references),
      update: (reference, value) => {
        this.events.push("update");
        updates.push({ reference, value: clone(value) });
      },
    };
    const result = await callback(transaction);
    for (const { reference, value } of updates) {
      const record = this.records.get(reference.path);
      record.data = Object.fromEntries([
        ...Object.keys(record.data).map((key) => [key, record.data[key]]),
        ...Object.keys(value).map((key) => [key, value[key]]),
      ]);
      record.updateTime = new Date(record.updateTime.getTime() + 1);
      this.mutations += 1;
    }
    return result;
  }
}

function ownMap(entries) {
  return Object.fromEntries(entries);
}

function fixture({
  conversationId = "dm_fixture",
  participants = ["uid-a", "uid-b"],
  poisonParticipant = participants[1],
} = {}) {
  const ordered = [...participants].sort((left, right) =>
    left < right ? -1 : left > right ? 1 : 0);
  const pairKey = canonicalPairKey(...ordered);
  const at = new Date("2026-08-29T10:00:00.000Z");
  const names = ownMap(ordered.map((uid, index) => [uid, `User ${index + 1}`]));
  const photos = ownMap([
    ...ordered.map((uid, index) => [uid, `https://example.test/${index}.jpg`]),
    [`\`${poisonParticipant}\``, "https://example.test/stale.jpg"],
  ]);
  const root = {
    archivedBy: [],
    createdAt: at,
    lastMessage: "",
    lastMessageId: null,
    lastMessageSenderId: "",
    lastMessageSequence: 0,
    lastMessageType: "text",
    mutedBy: [],
    pairKey,
    participantEmails: ownMap(ordered.map((uid) => [uid, ""])),
    participantIds: ordered,
    participantNames: names,
    participantPhotoUrls: photos,
    readSequences: ownMap(ordered.map((uid) => [uid, 0])),
    schemaVersion: 2,
    typing: {},
    unreadCounts: ownMap(ordered.map((uid) => [uid, 0])),
    updatedAt: at,
  };
  const guard = {
    conversationId,
    createdAt: at,
    pairKey,
    participantIds: ordered,
    schemaVersion: 1,
  };
  return { conversationId, guard, ordered, pairKey, root };
}

function seed(database, value) {
  database.set(`conversations/${value.conversationId}`, value.root);
  database.set(`directConversationPairs/${value.pairKey}`, value.guard);
}

function args(overrides = {}) {
  return {
    apply: false,
    backupFile: null,
    maxConversations: 500,
    project: EXPECTED_PROJECT,
    ...overrides,
  };
}

describe("targeted direct-conversation photo poison repair", () => {
  test("CLI is project-pinned, bounded, dry-run-first and requires an absolute backup", () => {
    assert.deepEqual(parseArgs(["--project", EXPECTED_PROJECT]), args());
    assert.equal(
      parseArgs(["--project", EXPECTED_PROJECT, "--apply"]).apply,
      true,
    );
    assert.throws(() => parseArgs(["--unknown"]), /Unsupported/u);
    assert.throws(
      () => parseArgs(["--max-conversations", "501"]),
      /safe bound/u,
    );
    assert.throws(() => assertArgs(args(), "another-project"), /Runtime/u);
    assert.throws(
      () => assertArgs(args({ apply: true, backupFile: "relative.json" })),
      /absolute/u,
    );
  });

  test("matches only the exact historical signature and treats UIDs as opaque keys", async () => {
    const database = new FakeDatabase();
    const value = fixture({
      participants: ["constructor", "__proto__"],
      poisonParticipant: "__proto__",
    });
    seed(database, value);
    const [root, guard] = await database.getAll(
      database.doc(`conversations/${value.conversationId}`),
      database.doc(`directConversationPairs/${value.pairKey}`),
    );
    const candidate = poisonCandidate(root, guard);
    assert.notEqual(candidate, null);
    assert.equal(ownMap([["__proto__", "safe"]]).__proto__, "safe");
    assert.equal(candidate.maps.participantNames.__proto__, "User 1");
    assert.equal(candidate.maps.participantNames.constructor, "User 2");
    assert.deepEqual(
      Object.keys(candidate.maps.participantPhotoUrls).sort(),
      value.ordered,
    );

    const extra = clone(value.root);
    extra.participantPhotoUrls = ownMap([
      ...Object.keys(extra.participantPhotoUrls).map((key) =>
        [key, extra.participantPhotoUrls[key]]),
      ["ordinary-extra", ""],
    ]);
    database.set(`conversations/${value.conversationId}`, extra);
    const [invalidRoot, validGuard] = await database.getAll(
      database.doc(`conversations/${value.conversationId}`),
      database.doc(`directConversationPairs/${value.pairKey}`),
    );
    assert.equal(poisonCandidate(invalidRoot, validGuard), null);
  });

  test("rejects a poison-looking root unless the cleaned root and exact guard fully validate", async () => {
    const database = new FakeDatabase();
    const value = fixture();
    value.root.participantNames[value.ordered[0]] = "";
    seed(database, value);
    let [root, guard] = await database.getAll(
      database.doc(`conversations/${value.conversationId}`),
      database.doc(`directConversationPairs/${value.pairKey}`),
    );
    assert.equal(poisonCandidate(root, guard), null);

    value.root.participantNames[value.ordered[0]] = "Valid";
    value.guard.conversationId = "another-conversation";
    seed(database, value);
    [root, guard] = await database.getAll(
      database.doc(`conversations/${value.conversationId}`),
      database.doc(`directConversationPairs/${value.pairKey}`),
    );
    assert.equal(poisonCandidate(root, guard), null);
  });

  test("dry-run is aggregate-only and mutates or backs up nothing", async () => {
    const database = new FakeDatabase();
    seed(database, fixture());
    let backupCalls = 0;
    const report = await runRepair({
      database,
      args: args(),
      backupWriter: async () => { backupCalls += 1; },
    });
    assert.deepEqual(report, {
      appliedRepairs: 0,
      boundedToConversations: 500,
      candidateConversations: 1,
      mode: "dry-run",
      potentialSignatures: 1,
      scannedConversations: 1,
      truncated: false,
      verifiedRepairs: 0,
    });
    assert.equal(backupCalls, 0);
    assert.equal(database.mutations, 0);
    assert.equal(JSON.stringify(report).includes("uid-"), false);
  });

  test("apply backs up first, removes only poison and verifies an idempotent canonical root", async () => {
    const database = new FakeDatabase();
    const value = fixture();
    seed(database, value);
    const beforeRoot = clone(value.root);
    const beforeGuard = clone(value.guard);
    let candidateFromBackup = null;
    const report = await runRepair({
      database,
      args: args({ apply: true, backupFile: "/private/backup.json" }),
      backupWriter: async (_file, payload) => {
        database.events.push("backup");
        candidateFromBackup = payload;
      },
    });
    assert.deepEqual(database.events, ["backup", "update"]);
    assert.equal(report.appliedRepairs, 1);
    assert.equal(report.verifiedRepairs, 1);
    assert.equal(candidateFromBackup.conversation.id, value.conversationId);

    const [rootAfter, guardAfter] = await database.getAll(
      database.doc(`conversations/${value.conversationId}`),
      database.doc(`directConversationPairs/${value.pairKey}`),
    );
    assert.notEqual(canonicalRoot(rootAfter, guardAfter), null);
    assert.deepEqual(
      Object.keys(rootAfter.data().participantPhotoUrls).sort(),
      value.ordered,
    );
    assert.deepEqual(rootAfter.data().participantNames, beforeRoot.participantNames);
    for (const key of Object.keys(beforeRoot)) {
      if (key === "participantNames" || key === "participantPhotoUrls") continue;
      assert.deepEqual(serializable(rootAfter.data()[key]), serializable(beforeRoot[key]));
    }
    assert.deepEqual(serializable(guardAfter.data()), serializable(beforeGuard));

    const originalCandidate = poisonCandidate(
      {
        id: value.conversationId,
        ref: database.doc(`conversations/${value.conversationId}`),
        exists: true,
        updateTime: new Date(1_770_000_000_000),
        data: () => clone(beforeRoot),
      },
      {
        id: value.pairKey,
        ref: database.doc(`directConversationPairs/${value.pairKey}`),
        exists: true,
        updateTime: new Date(1_770_000_000_000),
        data: () => clone(beforeGuard),
      },
    );
    assert.equal(
      await repairCandidate({ database, candidate: originalCandidate }),
      "already-repaired",
    );
    assert.equal(database.mutations, 1);
  });

  test("transaction refuses a still-poisoned root whose update time changed after scan", async () => {
    const database = new FakeDatabase();
    const value = fixture();
    seed(database, value);
    database.beforeTransaction = () => {
      const record = database.records.get(`conversations/${value.conversationId}`);
      record.updateTime = new Date(record.updateTime.getTime() + 100);
    };
    await assert.rejects(
      runRepair({
        database,
        args: args({ apply: true, backupFile: "/private/backup.json" }),
        backupWriter: async () => {},
      }),
      /changed after the dry scan/u,
    );
    assert.equal(database.mutations, 0);
  });

  test("apply refuses zero, multiple, and truncated candidate sets", async () => {
    const empty = new FakeDatabase();
    await assert.rejects(
      runRepair({
        database: empty,
        args: args({ apply: true, backupFile: "/private/backup.json" }),
      }),
      /one complete bounded candidate set/u,
    );

    const multiple = new FakeDatabase();
    seed(multiple, fixture({ conversationId: "dm_one" }));
    seed(multiple, fixture({
      conversationId: "dm_two",
      participants: ["uid-c", "uid-d"],
    }));
    await assert.rejects(
      runRepair({
        database: multiple,
        args: args({ apply: true, backupFile: "/private/backup.json" }),
      }),
      /one complete bounded candidate set/u,
    );

    const truncated = new FakeDatabase();
    seed(truncated, fixture());
    truncated.set("conversations/zz-unrelated", { ignored: true });
    await assert.rejects(
      runRepair({
        database: truncated,
        args: args({
          apply: true,
          backupFile: "/private/backup.json",
          maxConversations: 1,
        }),
      }),
      /one complete bounded candidate set/u,
    );
  });

  test("private backup is mode 0600, refuses overwrite, and fatal output redacts details", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "yo-dm-repair-"));
    const backupPath = path.join(directory, "backup.json");
    try {
      await writePrivateBackup(backupPath, { privateUid: "secret" });
      assert.equal((await stat(backupPath)).mode & 0o777, 0o600);
      assert.equal(JSON.parse(await readFile(backupPath, "utf8")).privateUid, "secret");
      await assert.rejects(
        writePrivateBackup(backupPath, { overwritten: true }),
        /EEXIST/u,
      );
      let output = "";
      writeFatalError(
        new Error(`failure for private uid at ${backupPath}`),
        { write: (value) => { output += value; } },
      );
      assert.equal(output, "Direct conversation photo repair failed.\n");
      assert.equal(output.includes(backupPath), false);
      assert.equal(output.includes("private uid"), false);
    } finally {
      await rm(directory, { recursive: true });
    }
  });
});
