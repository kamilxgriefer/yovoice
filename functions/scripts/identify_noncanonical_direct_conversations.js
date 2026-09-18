#!/usr/bin/env node
// RC-6. READ-ONLY identification of direct-conversation roots that are not
// canonical, plus the dry-run commands an operator may run afterwards.
//
// Production holds 20 `conversations` roots against 17 `directConversationPairs`
// guards, so three roots have no pair guard or are not schemaVersion 2. This
// script names them and nothing else.
//
//   node scripts/identify_noncanonical_direct_conversations.js \
//     --project yovoice-ec54a
//
// THIS SCRIPT HAS NO APPLY PATH. Not a disabled one — an absent one. It opens
// Firestore read-only on the owner's application default credentials, writes
// nothing, and deploys nothing. The repair itself is a separate, deliberate
// operator step through migrateDirectIntegrityConversation, and the commands
// printed under `dryRunCommands` are exactly the dry runs to start from.
//
// Output discipline: conversation ids, pair-key digests, booleans and key
// names only. No participant uid, display name, e-mail, photo URL or message
// content ever reaches stdout, which is what makes the output safe to attach
// to an evidence file.

const { FieldPath } = require("firebase-admin/firestore");
const { canonicalPair } = require("../integrity/guards");
const {
  canonicalPairKey,
  validateConversation,
  validatePairGuard,
} = require("../messaging/direct_integrity");

const EXPECTED_PROJECT = "yovoice-ec54a";
const DEFAULT_MAX_CONVERSATIONS = 500;
const MAX_CONVERSATIONS_PER_RUN = 500;

// The canonical schema-v2 root shape, as declared by
// scripts/repair_direct_conversation_photo_poison.js and enforced by
// validateConversation in messaging/direct_integrity.js.
const ROOT_KEYS = Object.freeze([
  "archivedBy",
  "createdAt",
  "lastMessage",
  "lastMessageId",
  "lastMessageSenderId",
  "lastMessageSequence",
  "lastMessageType",
  "mutedBy",
  "pairKey",
  "participantEmails",
  "participantIds",
  "participantNames",
  "participantPhotoUrls",
  "readSequences",
  "schemaVersion",
  "typing",
  "unreadCounts",
  "updatedAt",
]);

// Optional per-participant delete-for-me state; see CONVERSATION_DELETION_KEYS
// in messaging/direct_integrity.js. Present or absent, both are canonical.
const ROOT_OPTIONAL_KEYS = Object.freeze(["deletedBy", "deletedSequences"]);

function compareCodeUnits(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function keyDivergence(data) {
  const present = new Set(
    Object.keys(isPlainObject(data) ? data : {})
      .filter((key) => !ROOT_OPTIONAL_KEYS.includes(key)),
  );
  return {
    missingKeys: ROOT_KEYS.filter((key) => !present.has(key))
      .sort(compareCodeUnits),
    extraKeys: [...present].filter((key) => !ROOT_KEYS.includes(key))
      .sort(compareCodeUnits),
  };
}

/**
 * The violation vector for one root. Every field is an id, a boolean or a key
 * name — never a value read out of the document.
 */
function violationVector(document, guardSnapshot) {
  const data = document.data() ?? {};
  const { extraKeys, missingKeys } = keyDivergence(data);
  const vector = {
    conversationId: document.id,
    missingPairGuard: !guardSnapshot?.exists,
    schemaVersionNot2: data.schemaVersion !== 2,
    missingKeys,
    extraKeys,
    participantsNotCanonical: false,
    pairKeyNotCanonical: false,
    pairGuardConflicts: false,
    rootRejectedByValidator: false,
    pairKey: null,
  };

  let participants = null;
  if (Array.isArray(data.participantIds) && data.participantIds.length === 2) {
    try {
      participants = canonicalPair(...data.participantIds);
    } catch (_) {
      participants = null;
    }
  }
  if (participants === null ||
      data.participantIds.some((uid, index) => uid !== participants[index])) {
    vector.participantsNotCanonical = true;
    vector.rootRejectedByValidator = true;
    return vector;
  }

  const pairKey = canonicalPairKey(...participants);
  // A digest, not a uid pair: canonicalPairKey is a one-way hash, so printing
  // it names the guard document without naming either participant.
  vector.pairKey = pairKey;
  vector.pairKeyNotCanonical = data.pairKey !== pairKey;

  if (guardSnapshot?.exists) {
    try {
      validatePairGuard(guardSnapshot, document.id, participants);
    } catch (_) {
      vector.pairGuardConflicts = true;
    }
  }
  try {
    validateConversation(document, document.id, participants[0], guardSnapshot);
  } catch (_) {
    vector.rootRejectedByValidator = true;
  }
  return vector;
}

function isCanonical(vector) {
  return !vector.missingPairGuard &&
    !vector.schemaVersionNot2 &&
    vector.missingKeys.length === 0 &&
    vector.extraKeys.length === 0 &&
    !vector.participantsNotCanonical &&
    !vector.pairKeyNotCanonical &&
    !vector.pairGuardConflicts &&
    !vector.rootRejectedByValidator;
}

function dryRunCommand(conversationId) {
  // Text for the operator to run later. This script runs none of it.
  return "migrateDirectIntegrityConversation(" +
    `{"conversationId": ${JSON.stringify(conversationId)}, "dryRun": true})`;
}

async function identify({ database, maxConversations }) {
  const roots = await database
    .collection("conversations")
    .orderBy(FieldPath.documentId())
    .limit(maxConversations + 1)
    .get();
  const truncated = roots.size > maxConversations;
  const documents = roots.docs.slice(0, maxConversations);

  const guardReferences = documents.map((document) => {
    const data = document.data() ?? {};
    let participants = null;
    if (Array.isArray(data.participantIds) && data.participantIds.length === 2) {
      try {
        participants = canonicalPair(...data.participantIds);
      } catch (_) {
        participants = null;
      }
    }
    return participants === null
      ? null
      : database.doc(
        `directConversationPairs/${canonicalPairKey(...participants)}`,
      );
  });
  const resolvable = guardReferences.filter((reference) => reference !== null);
  const fetched = resolvable.length === 0
    ? []
    : await database.getAll(...resolvable);
  const guardByPath = new Map(
    fetched.map((snapshot) => [snapshot.ref.path, snapshot]),
  );

  const divergent = [];
  let canonicalCount = 0;
  for (let index = 0; index < documents.length; index += 1) {
    const reference = guardReferences[index];
    const guardSnapshot = reference === null
      ? null
      : guardByPath.get(reference.path) ?? null;
    const vector = violationVector(documents[index], guardSnapshot);
    if (isCanonical(vector)) canonicalCount += 1;
    else divergent.push(vector);
  }

  const guards = await database
    .collection("directConversationPairs")
    .orderBy(FieldPath.documentId())
    .limit(maxConversations + 1)
    .get();

  return {
    boundedToConversations: maxConversations,
    scannedConversations: documents.length,
    truncated: truncated || guards.size > maxConversations,
    pairGuardDocuments: Math.min(guards.size, maxConversations),
    canonicalConversations: canonicalCount,
    divergentConversations: divergent.length,
    divergent,
    dryRunCommands: divergent.map((vector) =>
      dryRunCommand(vector.conversationId)),
    readOnly: true,
  };
}

function parseArgs(argv) {
  const args = {
    maxConversations: DEFAULT_MAX_CONVERSATIONS,
    project: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--max-conversations") {
      const value = Number.parseInt(argv[++index], 10);
      if (!Number.isSafeInteger(value) || value < 1 ||
          value > MAX_CONVERSATIONS_PER_RUN) {
        throw new Error("--max-conversations is outside the safe bound.");
      }
      args.maxConversations = value;
    } else {
      // There is deliberately no --apply, no --repair and no --backup-file.
      throw new Error("Unsupported argument.");
    }
  }
  return args;
}

function assertArgs(args, resolvedProject) {
  if (args.project !== EXPECTED_PROJECT) {
    throw new Error(`--project must be exactly ${EXPECTED_PROJECT}.`);
  }
  if (resolvedProject && resolvedProject !== EXPECTED_PROJECT) {
    throw new Error("Runtime project does not match the pinned project.");
  }
}

async function main() {
  const {
    applicationDefault,
    getApps,
    initializeApp,
  } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const args = parseArgs(process.argv.slice(2));
  const resolvedProject =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || null;
  assertArgs(args, resolvedProject);
  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId: EXPECTED_PROJECT,
    });
  }
  const report = await identify({
    database: getFirestore(),
    maxConversations: args.maxConversations,
  });
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

function writeFatalError(_error, stream = process.stderr) {
  // SDK errors can carry uids and document paths.
  stream.write("Direct conversation identification failed.\n");
}

if (require.main === module) {
  main().catch((error) => {
    writeFatalError(error);
    process.exitCode = 1;
  });
}

module.exports = {
  EXPECTED_PROJECT,
  MAX_CONVERSATIONS_PER_RUN,
  ROOT_KEYS,
  ROOT_OPTIONAL_KEYS,
  assertArgs,
  dryRunCommand,
  identify,
  isCanonical,
  keyDivergence,
  parseArgs,
  violationVector,
  writeFatalError,
};
