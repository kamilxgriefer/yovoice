const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { getAuth } = require("firebase-admin/auth");
const { FieldPath } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const {
  canonicalPair,
  timestampMillis,
} = require("../integrity/guards");
const { canonicalPairKey } = require("../messaging/direct_integrity");
const { db } = require("../utils/firestore");

const REGION = "europe-west1";

// A transaction may read up to 500 documents. Each discovery page becomes
// one transaction containing the canonical user plus at most 150 targets.
const TARGET_PAGE_SIZE = 150;

const CONVERSATION_ROOT_KEYS = Object.freeze([
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

const PAIR_GUARD_KEYS = Object.freeze([
  "conversationId",
  "createdAt",
  "pairKey",
  "participantIds",
  "schemaVersion",
]);

function codeUnitCompare(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function hasExactKeys(value, expected) {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value).sort(codeUnitCompare);
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]);
}

function isRetiredSource(data) {
  return (
    data.disabled === true ||
    data.banned === true ||
    data.deleted === true ||
    data.status === "deleted" ||
    data.authDeletedAt != null
  );
}

async function fetchAuthUserOrNull(uid) {
  try {
    return await getAuth().getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

function canonicalConversationBinding(data, uid) {
  if (!hasExactKeys(data, CONVERSATION_ROOT_KEYS) || data.schemaVersion !== 2) {
    return null;
  }
  const participantIds = data.participantIds;
  if (!Array.isArray(participantIds) || participantIds.length !== 2) return null;
  let participants;
  try {
    participants = canonicalPair(...participantIds);
  } catch (_) {
    return null;
  }
  if (!participants.includes(uid) ||
      participantIds.some((participantId, index) =>
        participantId !== participants[index])) {
    return null;
  }
  const pairKey = canonicalPairKey(...participants);
  return data.pairKey === pairKey ? { pairKey, participants } : null;
}

function isCanonicalConversationTarget(data, uid) {
  return canonicalConversationBinding(data, uid) !== null;
}

function hasExactPairGuard(snapshot, conversationId, binding) {
  if (!snapshot?.exists) return false;
  const guard = snapshot.data() ?? {};
  return hasExactKeys(guard, PAIR_GUARD_KEYS) &&
    guard.schemaVersion === 1 &&
    guard.pairKey === binding.pairKey &&
    guard.conversationId === conversationId &&
    Array.isArray(guard.participantIds) &&
    guard.participantIds.length === binding.participants.length &&
    guard.participantIds.every((participantId, index) =>
      participantId === binding.participants[index]) &&
    timestampMillis(guard.createdAt) !== null;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactParticipantKeys(value, participants) {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value).sort(codeUnitCompare);
  return (
    keys.length === participants.length &&
    keys.every((key, index) => key === participants[index])
  );
}

/**
 * Rebuilds both denormalized identity maps from the canonical participant
 * pair. The current user's values come from users/{uid}; the peer's values
 * must already be valid and are preserved byte-for-byte. Returning null is a
 * fail-closed response to a malformed peer snapshot: fan-out may repair its
 * own identity, but it must never invent or erase somebody else's identity.
 */
function canonicalConversationIdentityMaps(data, uid, identity, binding) {
  if (
    !isPlainObject(data.participantNames) ||
    !isPlainObject(data.participantPhotoUrls)
  ) {
    return null;
  }

  const nameEntries = [];
  const photoEntries = [];
  for (const participantId of binding.participants) {
    if (participantId === uid) {
      nameEntries.push([participantId, identity.displayName]);
      photoEntries.push([participantId, identity.photoUrl ?? ""]);
      continue;
    }

    if (!Object.prototype.hasOwnProperty.call(
      data.participantNames,
      participantId,
    ) || !Object.prototype.hasOwnProperty.call(
      data.participantPhotoUrls,
      participantId,
    )) {
      return null;
    }
    const peerName = data.participantNames[participantId];
    const peerPhotoUrl = data.participantPhotoUrls[participantId];
    if (
      typeof peerName !== "string" ||
      !peerName.trim() ||
      peerName.length > 80 ||
      typeof peerPhotoUrl !== "string" ||
      peerPhotoUrl.length > 2048
    ) {
      return null;
    }
    nameEntries.push([participantId, peerName]);
    photoEntries.push([participantId, peerPhotoUrl]);
  }

  // Object.fromEntries defines opaque uid keys as own data properties. In
  // particular, "__proto__" and "constructor" cannot mutate or shadow the
  // builder while the canonical maps are assembled.
  return {
    participants: binding.participants,
    participantNames: Object.fromEntries(nameEntries),
    participantPhotoUrls: Object.fromEntries(photoEntries),
  };
}

function safePhotoUrl(value) {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (candidate.length === 0 || candidate.length > 2048) return null;
  try {
    return new URL(candidate).protocol === "https:" ? candidate : null;
  } catch {
    return null;
  }
}

function canonicalIdentity(data) {
  const nameCandidate = [data.displayName, data.username].find(
    (value) => typeof value === "string" && value.trim().length > 0,
  );
  return {
    // All denormalized contracts (DMs and Moments in particular) cap names
    // at 80 even though the owner profile permits 120.
    displayName: (nameCandidate ?? "YO Voice user").trim().slice(0, 80),
    // Never let an owner-controlled malformed URL poison server-validated
    // conversation/Moment documents. Invalid values converge to no avatar.
    photoUrl: safePhotoUrl(data.photoUrl),
  };
}

async function syncTargetPage({ userReference, uid, targets, apply }) {
  if (!Array.isArray(targets) || targets.length > TARGET_PAGE_SIZE) {
    throw new RangeError(`targets must contain at most ${TARGET_PAGE_SIZE} items`);
  }
  return db.runTransaction(async (transaction) => {
    const snapshots = await transaction.getAll(
      userReference,
      ...targets.map((target) => target.reference),
    );
    const source = snapshots[0];
    if (!source.exists) {
      return {
        writes: 0,
        verifiedClubMemberships: 0,
        sourceUnavailable: true,
      };
    }
    const sourceData = source.data() ?? {};
    if (isRetiredSource(sourceData)) {
      return {
        writes: 0,
        verifiedClubMemberships: 0,
        sourceUnavailable: true,
      };
    }

    const identity = canonicalIdentity(sourceData);
    const conversationBindings = new Map();
    const pairGuardReferences = new Map();
    for (let index = 0; index < targets.length; index += 1) {
      const target = targets[index];
      if (target.kind !== "conversation") continue;
      const snapshot = snapshots[index + 1];
      if (!snapshot.exists) continue;
      const binding = canonicalConversationBinding(snapshot.data() ?? {}, uid);
      if (binding === null) continue;
      conversationBindings.set(index, binding);
      const reference = db.doc(`directConversationPairs/${binding.pairKey}`);
      pairGuardReferences.set(reference.path, reference);
    }

    // 150 targets + one source + at most 150 unique pair guards = 301 reads,
    // below Firestore's 500-document transaction limit. This second read
    // phase deliberately completes before the first possible write.
    const guardReferences = [...pairGuardReferences.values()];
    const guardSnapshots = guardReferences.length === 0
      ? []
      : await transaction.getAll(...guardReferences);
    const guardsByPath = new Map(
      guardSnapshots.map((snapshot) => [snapshot.ref.path, snapshot]),
    );
    let writes = 0;
    let verifiedClubMemberships = 0;

    for (let index = 0; index < targets.length; index += 1) {
      const target = targets[index];
      const snapshot = snapshots[index + 1];
      if (!snapshot.exists) continue;
      const data = snapshot.data() ?? {};

      if (target.kind === "conversation") {
        // Discovery can race a delete/recreate or migration. The transaction
        // snapshot is the final authority; never inject identity into a root
        // that no longer describes this exact two-party conversation.
        const binding = conversationBindings.get(index) ?? null;
        if (binding === null) continue;
        const guardPath = `directConversationPairs/${binding.pairKey}`;
        if (!hasExactPairGuard(
          guardsByPath.get(guardPath),
          target.reference.id,
          binding,
        )) {
          continue;
        }
        const maps = canonicalConversationIdentityMaps(
          data,
          uid,
          identity,
          binding,
        );
        if (maps === null) continue;
        if (
          hasExactParticipantKeys(data.participantNames, maps.participants) &&
          hasExactParticipantKeys(
            data.participantPhotoUrls,
            maps.participants,
          ) &&
          data.participantPhotoUrls[uid] ===
            maps.participantPhotoUrls[uid] &&
          data.participantNames[uid] === maps.participantNames[uid]
        ) {
          continue;
        }
        if (apply) {
          // Replace the complete maps instead of updating one nested leaf.
          // Besides converging the fresh identity, this removes poison keys
          // left by the historical FieldPath-as-object-key implementation.
          transaction.update(target.reference, {
            participantPhotoUrls: maps.participantPhotoUrls,
            participantNames: maps.participantNames,
          });
        }
        writes += 1;
        continue;
      }

      if (target.kind === "clubMember") {
        // users/{uid}/clubs is discovery only. The target path is derived
        // from its document id and the canonical member must assert this uid.
        if (data.userId !== uid) continue;
        verifiedClubMemberships += 1;
        if (
          (data.photoUrl ?? null) === identity.photoUrl &&
          data.displayName === identity.displayName
        ) {
          continue;
        }
        if (apply) {
          transaction.update(target.reference, {
            photoUrl: identity.photoUrl,
            displayName: identity.displayName,
          });
        }
        writes += 1;
        continue;
      }

      if (target.kind === "moment" && data.authorId === uid) {
        if (
          (data.authorPhotoUrl ?? null) === identity.photoUrl &&
          data.authorName === identity.displayName
        ) {
          continue;
        }
        if (apply) {
          transaction.update(target.reference, {
            authorPhotoUrl: identity.photoUrl,
            authorName: identity.displayName,
          });
        }
        writes += 1;
      }
    }

    return { writes, verifiedClubMemberships, sourceUnavailable: false };
  });
}

async function processTargetQuery({
  query,
  toTarget,
  userReference,
  uid,
  apply,
}) {
  let cursor = null;
  let scanned = 0;
  let writes = 0;
  let verifiedClubMemberships = 0;
  let sourceUnavailable = false;

  // Pages are discovered and committed one at a time. Memory stays bounded
  // even for a long-lived account; the function's explicit timeout is the
  // outer runtime bound rather than one unbounded get() allocation.
  while (!sourceUnavailable) {
    let pageQuery = query
      .orderBy(FieldPath.documentId())
      .limit(TARGET_PAGE_SIZE);
    if (cursor !== null) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    if (page.empty) break;

    const result = await syncTargetPage({
      userReference,
      uid,
      targets: page.docs.map(toTarget),
      apply,
    });
    scanned += page.size;
    writes += result.writes;
    verifiedClubMemberships += result.verifiedClubMemberships;
    sourceUnavailable = result.sourceUnavailable;
    cursor = page.docs[page.docs.length - 1];
    if (page.size < TARGET_PAGE_SIZE) break;
  }

  return { scanned, writes, verifiedClubMemberships, sourceUnavailable };
}

/**
 * Converges every denormalized identity snapshot on the CURRENT users/{uid}
 * document. Every target page reads that source in the same transaction as
 * its writes, so duplicate/out-of-order Eventarc deliveries cannot restore an
 * older avatar. Exported for the bounded repair script and emulator tests.
 */
async function syncProfileIdentity(
  uid,
  {
    apply = true,
    authUser = undefined,
    fetchAuthUser = fetchAuthUserOrNull,
  } = {},
) {
  // Firebase Auth is the existence authority. A lingering users/{uid}
  // document must never republish identity after Auth deletion/disablement.
  const authoritativeAuthUser =
    authUser === undefined ? await fetchAuthUser(uid) : authUser;
  if (
    authoritativeAuthUser === null ||
    authoritativeAuthUser?.disabled === true
  ) {
    return {
      conversations: 0,
      clubMemberships: 0,
      clubMirrorsScanned: 0,
      moments: 0,
      writes: 0,
      sourceUnavailable: true,
    };
  }

  const userReference = db.collection("users").doc(uid);
  const initialSource = await userReference.get();
  if (!initialSource.exists || isRetiredSource(initialSource.data() ?? {})) {
    return {
      conversations: 0,
      clubMemberships: 0,
      clubMirrorsScanned: 0,
      moments: 0,
      writes: 0,
      sourceUnavailable: true,
    };
  }

  const conversations = await processTargetQuery({
    query: db
      .collection("conversations")
      .where("participantIds", "array-contains", uid),
    toTarget: (document) => ({
      kind: "conversation",
      reference: document.ref,
    }),
    userReference,
    uid,
    apply,
  });
  if (conversations.sourceUnavailable) {
    return {
      conversations: conversations.scanned,
      clubMemberships: 0,
      clubMirrorsScanned: 0,
      moments: 0,
      writes: conversations.writes,
      sourceUnavailable: true,
    };
  }

  const memberships = await processTargetQuery({
    query: userReference.collection("clubs"),
    toTarget: (membership) => ({
      kind: "clubMember",
      reference: db
        .collection("clubs")
        .doc(membership.id)
        .collection("members")
        .doc(uid),
    }),
    userReference,
    uid,
    apply,
  });
  if (memberships.sourceUnavailable) {
    return {
      conversations: conversations.scanned,
      clubMemberships: memberships.verifiedClubMemberships,
      clubMirrorsScanned: memberships.scanned,
      moments: 0,
      writes: conversations.writes + memberships.writes,
      sourceUnavailable: true,
    };
  }

  const moments = await processTargetQuery({
    query: db.collection("voiceMoments").where("authorId", "==", uid),
    toTarget: (document) => ({ kind: "moment", reference: document.ref }),
    userReference,
    uid,
    apply,
  });

  return {
    conversations: conversations.scanned,
    clubMemberships: memberships.verifiedClubMemberships,
    clubMirrorsScanned: memberships.scanned,
    moments: moments.scanned,
    writes: conversations.writes + memberships.writes + moments.writes,
    sourceUnavailable: moments.sourceUnavailable,
  };
}

const onProfileIdentityChanged = onDocumentUpdated(
  {
    document: "users/{uid}",
    region: REGION,
    retry: true,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const photoChanged = (before.photoUrl ?? null) !== (after.photoUrl ?? null);
    const nameChanged =
      (before.displayName ?? null) !== (after.displayName ?? null);
    if (!photoChanged && !nameChanged) return;

    const result = await syncProfileIdentity(event.params.uid);
    logger.info("profile identity fan-out", {
      uid: event.params.uid,
      photoChanged,
      nameChanged,
      ...result,
    });
  },
);

module.exports = {
  canonicalIdentity,
  fetchAuthUserOrNull,
  isRetiredSource,
  isCanonicalConversationTarget,
  onProfileIdentityChanged,
  syncTargetPage,
  syncProfileIdentity,
};
