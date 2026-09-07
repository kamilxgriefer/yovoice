#!/usr/bin/env node
// One-purpose repair for the historical DM avatar fan-out defect that wrote
// one participant uid wrapped in literal backticks as an extra
// participantPhotoUrls key.
//
// Dry-run first:
//   node scripts/repair_direct_conversation_photo_poison.js \
//     --project yovoice-ec54a
//
// Apply only after reviewing the aggregate dry-run result. The backup path is
// mandatory, absolute, must not exist, and is created owner-readable only:
//   node scripts/repair_direct_conversation_photo_poison.js \
//     --project yovoice-ec54a --apply \
//     --backup-file /absolute/private/path/pre-dm-photo-repair.json

const { promises: fs } = require("node:fs");
const path = require("node:path");
const { isDeepStrictEqual } = require("node:util");

const { FieldPath } = require("firebase-admin/firestore");
const { canonicalPair } = require("../integrity/guards");
const {
  canonicalPairKey,
  validateConversation,
} = require("../messaging/direct_integrity");

const EXPECTED_PROJECT = "yovoice-ec54a";
const DEFAULT_MAX_CONVERSATIONS = 500;
const MAX_CONVERSATIONS_PER_RUN = 500;
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

// Optional per-participant delete-for-me state. Rejecting it as an unknown
// key would make this repair skip every conversation someone had deleted for
// themselves — exactly the roots it must still be able to fix. See
// CONVERSATION_DELETION_KEYS in messaging/direct_integrity.js.
const ROOT_OPTIONAL_KEYS = Object.freeze(["deletedBy", "deletedSequences"]);

function compareCodeUnits(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected, optional = []) {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value)
    .filter((key) => !optional.includes(key))
    .sort(compareCodeUnits);
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]);
}

function own(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function snapshotVersion(snapshot) {
  const value = snapshot?.updateTime;
  if (Number.isSafeInteger(value?.seconds) &&
      Number.isSafeInteger(value?.nanoseconds)) {
    return `${value.seconds}:${value.nanoseconds}`;
  }
  if (typeof value?.toMillis === "function") {
    const millis = value.toMillis();
    return Number.isFinite(millis) ? `ms:${millis}` : null;
  }
  if (value instanceof Date && Number.isFinite(value.getTime())) {
    return `ms:${value.getTime()}`;
  }
  return null;
}

function dataSnapshot(data) {
  return { exists: true, data: () => data };
}

function canonicalIdentityMaps(data, participants) {
  if (!isPlainObject(data.participantNames) ||
      !isPlainObject(data.participantPhotoUrls)) {
    return null;
  }
  if (participants.some((uid) =>
    !own(data.participantNames, uid) ||
    !own(data.participantPhotoUrls, uid))) {
    return null;
  }
  return {
    participantNames: Object.fromEntries(
      participants.map((uid) => [uid, data.participantNames[uid]]),
    ),
    participantPhotoUrls: Object.fromEntries(
      participants.map((uid) => [uid, data.participantPhotoUrls[uid]]),
    ),
  };
}

function canonicalRoot(document, guardSnapshot) {
  if (!document?.exists) return null;
  const data = document.data() ?? {};
  if (!exactKeys(data, ROOT_KEYS, ROOT_OPTIONAL_KEYS) ||
      data.schemaVersion !== 2 ||
      !Array.isArray(data.participantIds) ||
      data.participantIds.length !== 2) {
    return null;
  }
  let participants;
  try {
    participants = canonicalPair(...data.participantIds);
  } catch (_) {
    return null;
  }
  if (data.participantIds.some((uid, index) => uid !== participants[index]) ||
      data.pairKey !== canonicalPairKey(...participants)) {
    return null;
  }
  try {
    validateConversation(
      document,
      document.id,
      participants[0],
      guardSnapshot,
    );
  } catch (_) {
    return null;
  }
  const maps = canonicalIdentityMaps(data, participants);
  if (maps === null ||
      !exactKeys(data.participantNames, participants) ||
      !exactKeys(data.participantPhotoUrls, participants)) {
    return null;
  }
  return { data, maps, participants };
}

function poisonCandidate(document, guardSnapshot) {
  if (!document?.exists) return null;
  const data = document.data() ?? {};
  if (!exactKeys(data, ROOT_KEYS, ROOT_OPTIONAL_KEYS) ||
      data.schemaVersion !== 2 ||
      !Array.isArray(data.participantIds) ||
      data.participantIds.length !== 2 ||
      !isPlainObject(data.participantPhotoUrls)) {
    return null;
  }
  let participants;
  try {
    participants = canonicalPair(...data.participantIds);
  } catch (_) {
    return null;
  }
  if (data.participantIds.some((uid, index) => uid !== participants[index]) ||
      data.pairKey !== canonicalPairKey(...participants)) {
    return null;
  }

  const photoKeys = Object.keys(data.participantPhotoUrls);
  const extraKeys = photoKeys.filter((key) => !participants.includes(key));
  if (photoKeys.length !== participants.length + 1 || extraKeys.length !== 1 ||
      !participants.some((uid) => extraKeys[0] === `\`${uid}\``)) {
    return null;
  }
  const maps = canonicalIdentityMaps(data, participants);
  if (maps === null) return null;

  // The root must become a fully valid canonical schema-v2 root by removing
  // this one historical key and changing nothing else.
  const cleanedData = Object.fromEntries(
    Object.keys(data).map((key) => [key, data[key]]),
  );
  cleanedData.participantPhotoUrls = maps.participantPhotoUrls;
  try {
    validateConversation(
      dataSnapshot(cleanedData),
      document.id,
      participants[0],
      guardSnapshot,
    );
  } catch (_) {
    return null;
  }

  const conversationVersion = snapshotVersion(document);
  const guardVersion = snapshotVersion(guardSnapshot);
  if (conversationVersion === null || guardVersion === null) return null;
  return {
    conversationId: document.id,
    conversationReference: document.ref,
    conversationVersion,
    guardReference: guardSnapshot.ref,
    guardVersion,
    maps,
    participants,
    poisonKey: extraKeys[0],
    rootData: data,
    guardData: guardSnapshot.data(),
  };
}

function parseArgs(argv) {
  const args = {
    apply: false,
    backupFile: null,
    maxConversations: DEFAULT_MAX_CONVERSATIONS,
    project: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") args.apply = true;
    else if (argument === "--project") args.project = argv[++index] ?? null;
    else if (argument === "--backup-file") {
      args.backupFile = argv[++index] ?? null;
    } else if (argument === "--max-conversations") {
      const value = Number.parseInt(argv[++index], 10);
      if (!Number.isSafeInteger(value) || value < 1 ||
          value > MAX_CONVERSATIONS_PER_RUN) {
        throw new Error("--max-conversations is outside the safe bound.");
      }
      args.maxConversations = value;
    } else {
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
  if (args.apply &&
      (typeof args.backupFile !== "string" ||
       !path.isAbsolute(args.backupFile))) {
    throw new Error("--apply requires an absolute --backup-file path.");
  }
}

async function scanCandidates({ database, maxConversations }) {
  const roots = await database
    .collection("conversations")
    .orderBy(FieldPath.documentId())
    .limit(maxConversations + 1)
    .get();
  const truncated = roots.size > maxConversations;
  const documents = roots.docs.slice(0, maxConversations);
  const potential = [];
  for (const document of documents) {
    const data = document.data() ?? {};
    if (!Array.isArray(data.participantIds) ||
        data.participantIds.length !== 2) continue;
    let participants;
    try {
      participants = canonicalPair(...data.participantIds);
    } catch (_) {
      continue;
    }
    if (data.participantIds.some((uid, index) => uid !== participants[index]) ||
        data.pairKey !== canonicalPairKey(...participants) ||
        !isPlainObject(data.participantPhotoUrls)) continue;
    const extras = Object.keys(data.participantPhotoUrls)
      .filter((key) => !participants.includes(key));
    if (extras.length === 1 &&
        participants.some((uid) => extras[0] === `\`${uid}\``)) {
      potential.push({ document, pairKey: data.pairKey });
    }
  }

  const guardReferences = potential.map(({ pairKey }) =>
    database.doc(`directConversationPairs/${pairKey}`));
  const guards = guardReferences.length === 0
    ? []
    : await database.getAll(...guardReferences);
  const candidates = [];
  for (let index = 0; index < potential.length; index += 1) {
    const candidate = poisonCandidate(potential[index].document, guards[index]);
    if (candidate !== null) candidates.push(candidate);
  }
  return {
    candidates,
    report: {
      boundedToConversations: maxConversations,
      candidateConversations: candidates.length,
      potentialSignatures: potential.length,
      scannedConversations: documents.length,
      truncated,
    },
  };
}

function serializable(value) {
  if (value === null || value === undefined ||
      typeof value === "string" || typeof value === "number" ||
      typeof value === "boolean") {
    return value ?? null;
  }
  if (value instanceof Date) {
    return { __firestoreType: "timestamp", iso: value.toISOString() };
  }
  if (Number.isSafeInteger(value?.seconds) &&
      Number.isSafeInteger(value?.nanoseconds)) {
    return {
      __firestoreType: "timestamp",
      nanoseconds: value.nanoseconds,
      seconds: value.seconds,
    };
  }
  if (Array.isArray(value)) return value.map(serializable);
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).map((key) => [key, serializable(value[key])]),
    );
  }
  throw new Error("Backup contains an unsupported value.");
}

function backupPayload(candidate, capturedAt = new Date()) {
  return {
    schemaVersion: 1,
    projectId: EXPECTED_PROJECT,
    capturedAt: capturedAt.toISOString(),
    conversation: {
      id: candidate.conversationId,
      updateTime: candidate.conversationVersion,
      data: serializable(candidate.rootData),
    },
    pairGuard: {
      id: candidate.guardReference.id,
      updateTime: candidate.guardVersion,
      data: serializable(candidate.guardData),
    },
  };
}

async function writePrivateBackup(filePath, payload, fileSystem = fs) {
  if (typeof filePath !== "string" || !path.isAbsolute(filePath)) {
    throw new Error("The backup path must be absolute.");
  }
  const handle = await fileSystem.open(filePath, "wx", 0o600);
  try {
    await handle.writeFile(`${JSON.stringify(payload, null, 2)}\n`, "utf8");
    await handle.chmod(0o600);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function repairCandidate({ database, candidate }) {
  const outcome = await database.runTransaction(async (transaction) => {
    const [conversation, guard] = await transaction.getAll(
      candidate.conversationReference,
      candidate.guardReference,
    );
    const fresh = poisonCandidate(conversation, guard);
    if (fresh === null) {
      const canonical = canonicalRoot(conversation, guard);
      if (canonical !== null && conversation.id === candidate.conversationId &&
          canonical.participants.every((uid, index) =>
            uid === candidate.participants[index])) {
        return { status: "already-repaired" };
      }
      throw new Error("Candidate no longer matches the exact repair contract.");
    }
    if (fresh.conversationVersion !== candidate.conversationVersion ||
        fresh.guardVersion !== candidate.guardVersion) {
      throw new Error("Candidate changed after the dry scan.");
    }
    transaction.update(candidate.conversationReference, {
      participantNames: fresh.maps.participantNames,
      participantPhotoUrls: fresh.maps.participantPhotoUrls,
    });
    const expectedCleanRoot = Object.fromEntries(
      Object.keys(fresh.rootData).map((key) => [key, fresh.rootData[key]]),
    );
    expectedCleanRoot.participantNames = fresh.maps.participantNames;
    expectedCleanRoot.participantPhotoUrls = fresh.maps.participantPhotoUrls;
    return {
      status: "repaired",
      beforeGuard: serializable(fresh.guardData),
      expectedCleanRoot: serializable(expectedCleanRoot),
    };
  });

  const [conversationAfter, guardAfter] = await database.getAll(
    candidate.conversationReference,
    candidate.guardReference,
  );
  const canonicalAfter = canonicalRoot(conversationAfter, guardAfter);
  if (canonicalAfter === null) {
    throw new Error("Post-repair canonical verification failed.");
  }
  if (outcome.status === "repaired" &&
      (!isDeepStrictEqual(
        serializable(conversationAfter.data()),
        outcome.expectedCleanRoot,
      ) ||
       !isDeepStrictEqual(serializable(guardAfter.data()), outcome.beforeGuard))) {
    throw new Error("Post-repair preservation verification failed.");
  }
  return outcome.status;
}

async function runRepair({
  database,
  args,
  backupWriter = writePrivateBackup,
  now = () => new Date(),
}) {
  // Keep the safety gates on the reusable entry point too; tests and future
  // operator wrappers must not be able to bypass the project/backup contract.
  assertArgs(args, null);
  const { candidates, report } = await scanCandidates({
    database,
    maxConversations: args.maxConversations,
  });
  const result = {
    ...report,
    mode: args.apply ? "apply" : "dry-run",
    appliedRepairs: 0,
    verifiedRepairs: 0,
  };
  if (!args.apply) return result;
  if (report.truncated || candidates.length !== 1) {
    throw new Error("Apply requires one complete bounded candidate set.");
  }

  const candidate = candidates[0];
  await backupWriter(args.backupFile, backupPayload(candidate, now()));
  const status = await repairCandidate({ database, candidate });
  result.appliedRepairs = status === "repaired" ? 1 : 0;
  result.verifiedRepairs = 1;
  return result;
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
  const report = await runRepair({ database: getFirestore(), args });
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

function writeFatalError(_error, stream = process.stderr) {
  // SDK and filesystem errors can carry UIDs or the private backup path.
  stream.write("Direct conversation photo repair failed.\n");
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
  assertArgs,
  backupPayload,
  canonicalRoot,
  parseArgs,
  poisonCandidate,
  repairCandidate,
  runRepair,
  scanCandidates,
  serializable,
  writeFatalError,
  writePrivateBackup,
};
