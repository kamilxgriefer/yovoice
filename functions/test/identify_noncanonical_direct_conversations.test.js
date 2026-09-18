const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const { canonicalPair } = require("../integrity/guards");
const {
  canonicalConversationId,
  canonicalPairKey,
} = require("../messaging/direct_integrity");
const script = require("../scripts/identify_noncanonical_direct_conversations");

// RC-6. Production holds 20 `conversations` roots against 17
// `directConversationPairs` guards. This script names the divergent roots and
// prints the dry-run commands for them. It repairs nothing — and the first test
// below is the one that has to keep being true.

const A = "idc-alice";
const B = "idc-bob";
const PARTICIPANTS = canonicalPair(A, B);
const PAIR_KEY = canonicalPairKey(...PARTICIPANTS);
const CONVERSATION_ID = canonicalConversationId(...PARTICIPANTS);
const NOW = { toMillis: () => 1_812_000_000_000 };

function participantMap(value) {
  return Object.fromEntries(PARTICIPANTS.map((uid) => [uid, value]));
}

function canonicalRootData(overrides = {}) {
  return {
    schemaVersion: 2,
    pairKey: PAIR_KEY,
    participantIds: [...PARTICIPANTS],
    participantNames: {
      [PARTICIPANTS[0]]: "Alice",
      [PARTICIPANTS[1]]: "Bob",
    },
    participantEmails: participantMap(""),
    participantPhotoUrls: participantMap(""),
    unreadCounts: participantMap(0),
    readSequences: participantMap(0),
    typing: {},
    archivedBy: [],
    mutedBy: [],
    lastMessage: "",
    lastMessageId: null,
    lastMessageSequence: 0,
    lastMessageType: "text",
    lastMessageSenderId: "",
    createdAt: NOW,
    updatedAt: NOW,
    ...overrides,
  };
}

function guardData(overrides = {}) {
  return {
    schemaVersion: 1,
    pairKey: PAIR_KEY,
    conversationId: CONVERSATION_ID,
    participantIds: [...PARTICIPANTS],
    createdAt: NOW,
    ...overrides,
  };
}

function snapshot(id, data, collection = "conversations") {
  return {
    exists: data !== null,
    id,
    data: () => data ?? {},
    ref: { path: `${collection}/${id}` },
  };
}

// A deliberately tiny stand-in: the script reads two collections and a set of
// guard documents, and writes nothing, so there is nothing else to fake.
function fakeDatabase({ conversations = [], guards = new Map() } = {}) {
  const pages = {
    conversations,
    directConversationPairs: [...guards.entries()]
      .map(([id, data]) => snapshot(id, data, "directConversationPairs")),
  };
  return {
    writes: [],
    collection(name) {
      const docs = pages[name] ?? [];
      const query = {
        orderBy: () => query,
        limit: (value) => ({
          get: async () => ({
            size: docs.length,
            docs: docs.slice(0, value),
          }),
        }),
      };
      return query;
    },
    doc(documentPath) {
      return { path: documentPath };
    },
    async getAll(...references) {
      return references.map((reference) => {
        const id = reference.path.split("/").at(-1);
        const data = guards.get(id) ?? null;
        return snapshot(id, data, "directConversationPairs");
      });
    },
  };
}

test("the identification script has no apply path at all", () => {
  // Not a disabled flag — an absent one. A repair here would be an unreviewed
  // production write, and the repair itself is a separate operator step.
  assert.equal(script.repair, undefined);
  assert.equal(script.runRepair, undefined);
  assert.equal(script.repairCandidate, undefined);
  assert.equal(script.writePrivateBackup, undefined);
  for (const argument of ["--apply", "--repair", "--backup-file", "--force"]) {
    assert.throws(
      () => script.parseArgs([argument]),
      /Unsupported argument/u,
      `${argument} must not be accepted`,
    );
  }

  const source = readFileSync(
    path.join(
      __dirname,
      "..",
      "scripts",
      "identify_noncanonical_direct_conversations.js",
    ),
    "utf8",
  );
  for (const forbidden of [
    ".set(",
    ".update(",
    ".create(",
    ".delete(",
    "runTransaction",
    "batch()",
  ]) {
    assert.equal(
      source.includes(forbidden),
      false,
      `${forbidden} must not appear in a read-only script`,
    );
  }
});

test("the pinned project is mandatory in both directions", () => {
  assert.throws(
    () => script.assertArgs({ project: null }, null),
    /--project must be exactly/u,
  );
  assert.throws(
    () => script.assertArgs({ project: "some-other-project" }, null),
    /--project must be exactly/u,
  );
  assert.throws(
    () => script.assertArgs(
      { project: script.EXPECTED_PROJECT },
      "a-different-runtime-project",
    ),
    /Runtime project does not match/u,
  );
  script.assertArgs({ project: script.EXPECTED_PROJECT }, null);
  script.assertArgs(
    { project: script.EXPECTED_PROJECT },
    script.EXPECTED_PROJECT,
  );
  assert.throws(
    () => script.parseArgs(["--max-conversations", "0"]),
    /outside the safe bound/u,
  );
  assert.throws(
    () => script.parseArgs([
      "--max-conversations",
      String(script.MAX_CONVERSATIONS_PER_RUN + 1),
    ]),
    /outside the safe bound/u,
  );
});

test("a canonical root is not reported and a divergent one is", async () => {
  const guards = new Map([[PAIR_KEY, guardData()]]);
  const canonical = snapshot(CONVERSATION_ID, canonicalRootData());
  assert.equal(
    script.isCanonical(script.violationVector(canonical, snapshot(
      PAIR_KEY,
      guardData(),
      "directConversationPairs",
    ))),
    true,
  );

  const legacyId = `${PARTICIPANTS[0]}_${PARTICIPANTS[1]}`;
  const legacy = snapshot(legacyId, {
    participantIds: [...PARTICIPANTS],
    participantNames: { [PARTICIPANTS[0]]: "Alice" },
    typing: {},
    lastMessage: "legacy",
  });
  const database = fakeDatabase({
    conversations: [canonical, legacy],
    guards,
  });
  const report = await script.identify({
    database,
    maxConversations: 500,
  });

  assert.equal(report.readOnly, true);
  assert.equal(report.scannedConversations, 2);
  assert.equal(report.pairGuardDocuments, 1);
  assert.equal(report.canonicalConversations, 1);
  assert.equal(report.divergentConversations, 1);
  assert.equal(report.divergent[0].conversationId, legacyId);
  assert.equal(report.divergent[0].missingPairGuard, false);
  assert.equal(report.divergent[0].schemaVersionNot2, true);
  assert.ok(report.divergent[0].missingKeys.includes("schemaVersion"));
  assert.ok(report.divergent[0].missingKeys.includes("readSequences"));
  assert.deepEqual(report.divergent[0].extraKeys, []);
  assert.equal(report.divergent[0].rootRejectedByValidator, true);
  assert.deepEqual(report.dryRunCommands, [
    `migrateDirectIntegrityConversation({"conversationId": ${
      JSON.stringify(legacyId)}, "dryRun": true})`,
  ]);
  assert.deepEqual(database.writes, []);
});

test("a root with no pair guard and one with an extra key are both named",
  async () => {
    const orphan = snapshot(CONVERSATION_ID, canonicalRootData());
    const polluted = snapshot("idc-polluted", canonicalRootData({
      legacyMirrorField: 1,
    }));
    const report = await script.identify({
      database: fakeDatabase({
        conversations: [orphan, polluted],
        guards: new Map(),
      }),
      maxConversations: 500,
    });
    assert.equal(report.divergentConversations, 2);
    const byId = new Map(
      report.divergent.map((vector) => [vector.conversationId, vector]),
    );
    assert.equal(byId.get(CONVERSATION_ID).missingPairGuard, true);
    assert.equal(byId.get(CONVERSATION_ID).schemaVersionNot2, false);
    assert.deepEqual(byId.get("idc-polluted").extraKeys, [
      "legacyMirrorField",
    ]);
  });

test("the report carries ids and booleans, never a participant", async () => {
  const legacyId = `${PARTICIPANTS[0]}_${PARTICIPANTS[1]}`;
  const report = await script.identify({
    database: fakeDatabase({
      conversations: [
        snapshot("idc-opaque", {
          participantIds: [...PARTICIPANTS],
          participantNames: {
            [PARTICIPANTS[0]]: "Alice Example",
            [PARTICIPANTS[1]]: "Bob Example",
          },
          participantEmails: participantMap("private@old.invalid"),
          lastMessage: "a private message body",
          typing: {},
        }),
      ],
      guards: new Map(),
    }),
    maxConversations: 500,
  });
  const serialized = JSON.stringify(report);
  for (const secret of [
    "Alice Example",
    "Bob Example",
    "private@old.invalid",
    "a private message body",
    PARTICIPANTS[0],
    PARTICIPANTS[1],
  ]) {
    assert.equal(
      serialized.includes(secret),
      false,
      `${secret} must never reach the report`,
    );
  }
  // The pairKey is a one-way digest, so it names the guard document without
  // naming either participant.
  assert.equal(report.divergent[0].pairKey, PAIR_KEY);
  assert.equal(report.divergent[0].conversationId, "idc-opaque");
  assert.equal(legacyId.includes(PARTICIPANTS[0]), true);
});
